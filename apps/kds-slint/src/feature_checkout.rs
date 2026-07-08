//! Checkout feature glue — the Rust port of checkout_provider.dart (the
//! CheckoutNotifier session) + receipt_sheet.dart (ReceiptPreviewNotifier),
//! backing ui/feature_checkout.slint's `CheckoutState` global.
//!
//! Architecture (the main.rs pattern): the session state is authoritative
//! HERE; every UI intent lands in a callback, mutates the session, and a
//! whole-state `render` pushes the derived view (due / change / canPlace /
//! split remaining / quick-cash presets) back into the Slint global — the
//! Flutter drawer's "one legitimate whole-state watch", inverted.

use madar_core::{
    checkout::{CheckoutInput, CheckoutSplit, ReceiptView},
    error::CoreError,
    menu::{DiscountView, PaymentMethodView},
    receipt::PrinterBrand,
    timefmt::TimeStyle,
    MadarCore,
};
use slint::{ComponentHandle, Model, ModelRc, SharedString, VecModel, Weak};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use crate::{human_message, rt, AppWindow};
use crate::{
    CheckoutState, DiscountChipData, PaperRowData, PaperRowKind, PayMethodData, PrintState,
    QuickCashData, SplitRowData, Tone,
};

// ── Constants (checkout_provider.dart) ───────────────────────────────────────

/// Thermal receipt width in characters — the natives' `32u` raster width.
const RECEIPT_CHARS: u32 = 32;

/// Default JetDirect (raw-TCP) printer port, used when the device config
/// carries no explicit port (the natives' `parsePrinter` fallback).
const JET_DIRECT_PORT: u16 = 9100;

/// Round-number cash presets in minor units (natives: 50/100/200/500 major).
const CASH_PRESETS: [i64; 4] = [5000, 10000, 20000, 50000];

/// How many presets show at or above the amount due (natives: take(3)).
const CASH_PRESET_COUNT: usize = 3;

/// Toast auto-dismiss delay (design_system ToastData.seconds = 2.6).
const TOAST_MS: u64 = 2600;

// ── LITERAL ink-on-paper colors (receipt_paper.dart) — a receipt is always
// white paper with dark ink in BOTH themes; these are NOT theme roles. ──────
const INK: slint::Color = slint::Color::from_rgb_u8(0x1A, 0x1A, 0x1A); // 0xFF1A1A1A
const FAINT: slint::Color = slint::Color::from_rgb_u8(0x6B, 0x6B, 0x6B); // 0xFF6B6B6B
/// The voided stamp's red (natives: 0xFFB71C1C).
const VOID_RED: slint::Color = slint::Color::from_rgb_u8(0xB7, 0x1C, 0x1C);

// ── Money / parsing helpers (widgets.dart + design_system money.dart) ───────

/// Money.format — minor units → `"EGP 12.50"`: two decimals, uppercased code
/// before the amount, leading `-` for negatives, empty code → bare amount.
fn money(minor: i64, currency: &str) -> String {
    let neg = minor < 0;
    let cents = minor.abs();
    let amount = format!("{}{}.{:02}", if neg { "-" } else { "" }, cents / 100, cents % 100);
    let code = currency.to_uppercase();
    if code.is_empty() {
        amount
    } else {
        format!("{code} {amount}")
    }
}

/// Parse a major-unit decimal string ("500", "499.50") → minor units.
fn to_minor(s: &str) -> i64 {
    let cleaned: String = s.chars().filter(|c| c.is_ascii_digit() || *c == '.').collect();
    let major: f64 = cleaned.parse().unwrap_or(0.0);
    (major * 100.0).round() as i64
}

/// Minor units → the editable major-unit text ("12.50", whole "12").
fn minor_to_text(minor: i64) -> String {
    if minor % 100 == 0 {
        format!("{}", minor / 100)
    } else {
        format!("{:.2}", minor as f64 / 100.0)
    }
}

/// `#RRGGBB` → opaque color. Pairs with PaymentMethodView's brand hex.
fn hex_color(hex: &str) -> slint::Color {
    let s = hex.trim_start_matches('#');
    let value = u32::from_str_radix(s, 16).unwrap_or(0);
    slint::Color::from_argb_encoded(0xFF00_0000 | value)
}

/// Device-config brand string (`epson`/`star`) → PrinterBrand; anything else
/// falls back to Epson (the natives' default dialect).
fn printer_brand_of(brand: Option<&str>) -> PrinterBrand {
    if brand == Some("star") {
        PrinterBrand::Star
    } else {
        PrinterBrand::Epson
    }
}

// ── Session state (CheckoutState in checkout_provider.dart) ─────────────────

/// The money breakdown the drawer renders in its summary card + hero total.
#[derive(Clone, Copy, Default)]
pub struct Summary {
    pub subtotal_minor: i64,
    pub discount_minor: i64,
    pub tax_minor: i64,
    pub total_minor: i64,
}

/// Print lifecycle of the receipt confirmation — the natives' `PrintState`.
#[derive(Clone, Copy, PartialEq, Eq, Default)]
enum Print {
    #[default]
    Idle,
    Printing,
    Printed,
    Failed,
    NoPrinter,
}

impl Print {
    fn to_slint(self) -> PrintState {
        match self {
            Print::Idle => PrintState::Idle,
            Print::Printing => PrintState::Printing,
            Print::Printed => PrintState::Printed,
            Print::Failed => PrintState::Failed,
            Print::NoPrinter => PrintState::NoPrinter,
        }
    }
}

/// One tender session: org config, the money summary under charge, the
/// teller's in-progress tender picks, and the checkout + print lifecycle.
#[derive(Default)]
struct Session {
    payment_methods: Vec<PaymentMethodView>,
    discounts: Vec<DiscountView>,
    cart_discount_id: Option<String>,
    org_logo_path: Option<String>,
    currency: String,
    branch_name: String,
    summary: Summary,
    receipt: Option<ReceiptView>,
    is_placing: bool,
    print_state: Print,
    error: Option<String>,
    /// Explicit method pick; None falls back to cash-first.
    selected_method_id: Option<String>,
    tendered_minor: i64,
    tip_minor: i64,
    tip_method_id: Option<String>,
    split_mode: bool,
    split_amounts: HashMap<String, i64>,
    /// Caller-config: cart tender shows discounts + customer fields; a
    /// settle drawer hides both (checkout_drawer.dart constructor flags).
    show_discount_picker: bool,
    show_customer_fields: bool,
}

impl Session {
    /// Cash-first default (the natives' LaunchedEffect pick), resolved
    /// lazily so the async method load never races the first frame.
    fn effective_selected(&self) -> Option<&PaymentMethodView> {
        if let Some(picked) = self
            .selected_method_id
            .as_deref()
            .and_then(|id| self.payment_methods.iter().find(|m| m.id == id))
        {
            return Some(picked);
        }
        self.payment_methods
            .iter()
            .find(|m| m.is_cash)
            .or_else(|| self.payment_methods.first())
    }
}

/// Receipt-preview sheet state (receipt_sheet.dart ReceiptPreviewState).
#[derive(Default)]
struct Preview {
    printing: bool,
    receipt: Option<ReceiptView>,
    toast_seq: u64,
}

/// The feature context — hand `wire()` the app window once at boot.
pub struct CheckoutFeature {
    core: Arc<MadarCore>,
    ui: Weak<AppWindow>,
    session: Mutex<Session>,
    preview: Mutex<Preview>,
}

fn on_ui(feature: &Arc<CheckoutFeature>, f: impl FnOnce(AppWindow, Arc<CheckoutFeature>) + Send + 'static) {
    let ui = feature.ui.clone();
    let feature = feature.clone();
    let _ = slint::invoke_from_event_loop(move || {
        if let Some(ui) = ui.upgrade() {
            f(ui, feature);
        }
    });
}

impl CheckoutFeature {
    pub fn new(core: Arc<MadarCore>, ui: Weak<AppWindow>) -> Arc<Self> {
        Arc::new(Self {
            core,
            ui,
            session: Mutex::new(Session::default()),
            preview: Mutex::new(Preview::default()),
        })
    }
}

// ── Localization — every tr key the Dart source uses, resolved per locale. ──

pub fn apply_checkout_strings(ui: &AppWindow, core: &MadarCore) {
    let t = |k: &str| SharedString::from(core.tr(k.into()));
    let s = ui.global::<CheckoutState>();
    // TenderSheet chrome (tender_sheet.dart).
    s.set_title(t("order.tender"));
    s.set_terminal_label(t("order.place_order"));
    // Drawer sections (checkout_drawer.dart).
    s.set_tr_total(t("order.total"));
    s.set_tr_subtotal(t("order.subtotal"));
    s.set_tr_discount(t("order.discount"));
    s.set_tr_tax(t("order.tax"));
    s.set_tr_payment_method(t("order.payment_method"));
    s.set_tr_split_payment(t("order.split_payment"));
    s.set_tr_split_remaining(t("order.split_remaining"));
    s.set_tr_cash_received(t("order.cash_received"));
    s.set_tr_change_due(t("order.change_due"));
    s.set_tr_short_by(t("order.short_by"));
    s.set_tr_tip(t("order.tip"));
    s.set_tr_customer(t("order.customer"));
    s.set_tr_customer_hint(t("order.customer_hint"));
    s.set_tr_notes_hint(t("order.notes_hint"));
    // Confirmation (tender_sheet.dart).
    s.set_tr_order_placed(t("order.order_placed"));
    s.set_tr_new_order(t("order.new_order"));
    s.set_tr_reprint(t("receipt.reprint"));
    s.set_tr_printed(t("receipt.printed"));
    s.set_tr_no_printer(t("receipt.no_printer"));
    s.set_tr_print_failed(t("receipt.print_failed"));
    // Receipt preview sheet (receipt_sheet.dart).
    s.set_tr_receipt_title(t("receipt.title"));
    s.set_tr_print(t("receipt.print"));
    s.set_tr_done(t("order.done"));
    s.set_tr_settled(t("receipt.settled"));
}

// ── Whole-state render — the drawer's derived view, recomputed per intent. ──

fn render(feature: &Arc<CheckoutFeature>) {
    on_ui(feature, |ui, feature| {
        let s = feature.session.lock().unwrap();
        let core = &feature.core;
        let g = ui.global::<CheckoutState>();
        let cur = s.currency.clone();
        let total = s.summary.total_minor;

        // Header + summary card.
        g.set_currency_code(cur.to_uppercase().into());
        g.set_header_total(money(total, &cur).into());
        g.set_summary_subtotal(money(s.summary.subtotal_minor, &cur).into());
        g.set_summary_discount(
            if s.summary.discount_minor > 0 {
                format!("\u{2212}{}", money(s.summary.discount_minor, &cur))
            } else {
                String::new()
            }
            .into(),
        );
        g.set_summary_tax(
            if s.summary.tax_minor > 0 { money(s.summary.tax_minor, &cur) } else { String::new() }
                .into(),
        );
        g.set_summary_total(money(total, &cur).into());

        // Methods + selection.
        let selected = s.effective_selected().map(|m| m.id.clone());
        let method = s
            .payment_methods
            .iter()
            .find(|m| Some(&m.id) == selected.as_ref());
        let is_cash = method.map(|m| m.is_cash).unwrap_or(false);
        g.set_methods(ModelRc::new(VecModel::from(
            s.payment_methods
                .iter()
                .map(|m| PayMethodData {
                    id: m.id.clone().into(),
                    name: m.name.clone().into(),
                    is_cash: m.is_cash,
                    glyph: m.icon.to_lowercase().into(),
                    brand: hex_color(&m.color),
                })
                .collect::<Vec<_>>(),
        )));
        g.set_selected_id(selected.clone().unwrap_or_default().into());
        g.set_selected_is_cash(is_cash);
        g.set_split_mode(s.split_mode);

        // A tip paid by cash comes out of the same drawer → due with the
        // bill. The tip can ride a DIFFERENT method than the order, so gate
        // on the TIP method's isCash (tipMethod ?? selected), not the order's.
        let tip_method_id = s.tip_method_id.clone().or_else(|| selected.clone());
        let tip_method_view = s
            .payment_methods
            .iter()
            .find(|m| Some(&m.id) == tip_method_id.as_ref());
        let tip_method_is_cash =
            s.tip_minor > 0 && tip_method_view.map(|m| m.is_cash).unwrap_or(is_cash);
        let tip_cash = if tip_method_is_cash { s.tip_minor } else { 0 };
        let due_cash = total + tip_cash;
        let change = (s.tendered_minor - due_cash).max(0);
        let short = (due_cash - s.tendered_minor).max(0);

        g.set_due_cash_text(money(due_cash, &cur).into());
        g.set_show_change(s.tendered_minor > 0);
        g.set_change_ok(short <= 0);
        g.set_change_text(money(if short <= 0 { change } else { short }, &cur).into());

        // Round-number cash presets at or above the amount due (Exact first).
        let mut quick: Vec<QuickCashData> = vec![QuickCashData {
            label: core.tr("order.exact".into()).into(),
            minor: due_cash as i32,
            active: s.tendered_minor == due_cash,
        }];
        quick.extend(
            CASH_PRESETS
                .iter()
                .filter(|p| **p >= due_cash)
                .take(CASH_PRESET_COUNT)
                .map(|p| QuickCashData {
                    label: money(*p, &cur).into(),
                    minor: *p as i32,
                    active: s.tendered_minor == *p,
                }),
        );
        g.set_quick_cash(ModelRc::new(VecModel::from(quick)));

        // Tip card.
        g.set_tip_chip(
            if s.tip_minor > 0 { money(s.tip_minor, &cur) } else { String::new() }.into(),
        );
        g.set_tip_method_id(tip_method_id.unwrap_or_default().into());

        // Split allocator.
        let split_allocated: i64 = s.split_amounts.values().sum();
        let split_remaining = total - split_allocated;
        let positive_legs: Vec<(&String, &i64)> =
            s.split_amounts.iter().filter(|(_, v)| **v > 0).collect();
        g.set_split_rows(ModelRc::new(VecModel::from(
            s.payment_methods
                .iter()
                .map(|m| SplitRowData {
                    id: m.id.clone().into(),
                    name: m.name.clone().into(),
                    brand: hex_color(&m.color),
                    amount_text: match s.split_amounts.get(&m.id).copied().unwrap_or(0) {
                        0 => String::new(),
                        v => minor_to_text(v),
                    }
                    .into(),
                })
                .collect::<Vec<_>>(),
        )));
        g.set_split_remaining_text(money(split_remaining, &cur).into());
        g.set_split_settled(split_remaining == 0);

        // Discount chips (cart only): No-discount + each ACTIVE discount;
        // empty list hides the whole section (the Dart early-return).
        let active: Vec<&DiscountView> = s.discounts.iter().filter(|d| d.is_active).collect();
        let chips: Vec<DiscountChipData> = if active.is_empty() {
            Vec::new()
        } else {
            let mut chips = vec![DiscountChipData {
                id: SharedString::new(),
                label: core.tr("order.no_discount".into()).into(),
                active: s.cart_discount_id.is_none(),
            }];
            chips.extend(active.iter().map(|d| DiscountChipData {
                id: d.id.clone().into(),
                label: if d.dtype == "percentage" {
                    format!("{} {}%", d.name, d.value)
                } else {
                    d.name.clone()
                }
                .into(),
                active: s.cart_discount_id.as_deref() == Some(&d.id),
            }));
            chips
        };
        g.set_discount_chips(ModelRc::new(VecModel::from(chips)));
        g.set_show_discount_picker(s.show_discount_picker);
        g.set_show_customer_fields(s.show_customer_fields);

        // Terminal gate (the Dart canPlace switch).
        let placing = s.is_placing;
        let can_place = if placing {
            false
        } else if s.split_mode {
            split_allocated == total && !positive_legs.is_empty()
        } else {
            selected.is_some() && (!is_cash || s.tendered_minor >= due_cash)
        };
        g.set_placing(placing);
        g.set_can_place(can_place);
        g.set_error(s.error.clone().unwrap_or_default().into());

        // Confirmation flip + receipt paper.
        g.set_has_receipt(s.receipt.is_some());
        g.set_print_state(s.print_state.to_slint());
        if let Some(r) = &s.receipt {
            g.set_queued_offline(r.queued_offline);
            g.set_tr_status_hint(
                core.tr(if r.queued_offline { "order.queued_hint" } else { "order.sent_hint" }.into())
                    .into(),
            );
            set_paper(&ui, core, r, &s.branch_name, &cur, s.org_logo_path.as_deref());
        }
    });
}

// ── Session starters (checkout_provider.dart) ────────────────────────────────

/// The cashier tender session — mirror of the natives' on-appear load:
/// payment methods, discounts, the applied cart discount, the org logo, and
/// the live cart totals as the summary. Call as the TenderSheet opens.
pub fn start_cart(feature: &Arc<CheckoutFeature>) {
    let feature = feature.clone();
    rt().spawn(async move {
        let core = &feature.core;
        // The core's cart/menu reads are sync; failures are swallowed like
        // the Dart `_quiet` (cache reads / best-effort refreshes).
        let methods = core.list_payment_methods().unwrap_or_default();
        let discounts = core.list_discounts().unwrap_or_default();
        let discount_id = core.cart_discount_id().ok().flatten();
        let logo = core.org_logo_local_path();
        let totals = core.cart_totals().ok();
        {
            let mut s = feature.session.lock().unwrap();
            *s = Session {
                currency: core.current_session().map(|s| s.currency_code).unwrap_or_default(),
                branch_name: core.device_config().branch_name.unwrap_or_default(),
                payment_methods: methods,
                discounts,
                cart_discount_id: discount_id,
                org_logo_path: logo,
                summary: totals
                    .map(|t| Summary {
                        subtotal_minor: t.subtotal_minor,
                        discount_minor: t.discount_minor,
                        tax_minor: t.tax_minor,
                        total_minor: t.total_minor,
                    })
                    .unwrap_or_default(),
                show_discount_picker: true,
                show_customer_fields: true,
                ..Session::default()
            };
        }
        reset_field_texts(&feature);
        render(&feature);
    });
}

/// A settle / finalize session over a FIXED summary (e.g. a ticket's
/// subtotal) — payment methods only; the discount is frozen at fire time.
pub fn start_settle(feature: &Arc<CheckoutFeature>, summary: Summary) {
    let feature = feature.clone();
    rt().spawn(async move {
        let core = &feature.core;
        let methods = core.list_payment_methods().unwrap_or_default();
        {
            let mut s = feature.session.lock().unwrap();
            *s = Session {
                currency: core.current_session().map(|s| s.currency_code).unwrap_or_default(),
                branch_name: core.device_config().branch_name.unwrap_or_default(),
                payment_methods: methods,
                summary,
                show_discount_picker: false,
                show_customer_fields: false,
                ..Session::default()
            };
        }
        reset_field_texts(&feature);
        render(&feature);
    });
}

/// Clear the editable field texts for a fresh session (the autoDispose
/// "every presented drawer starts fresh" behavior).
fn reset_field_texts(feature: &Arc<CheckoutFeature>) {
    on_ui(feature, |ui, _| {
        let g = ui.global::<CheckoutState>();
        g.set_tendered_text(SharedString::new());
        g.set_tip_text(SharedString::new());
        g.set_customer_text(SharedString::new());
        g.set_notes_text(SharedString::new());
    });
}

// ── Cart ops ─────────────────────────────────────────────────────────────────

/// Apply or clear the cart discount, then re-read the applied id and the
/// totals so the summary + hero total update live (natives' setDiscount).
fn set_discount(feature: &Arc<CheckoutFeature>, id: Option<String>) {
    let feature = feature.clone();
    rt().spawn(async move {
        let core = &feature.core;
        let _ = match &id {
            Some(id) => core.cart_set_discount(id.clone()),
            None => core.cart_clear_discount(),
        };
        let discount_id = core.cart_discount_id().ok().flatten();
        let totals = core.cart_totals().ok();
        {
            let mut s = feature.session.lock().unwrap();
            s.cart_discount_id = discount_id;
            if let Some(t) = totals {
                s.summary = Summary {
                    subtotal_minor: t.subtotal_minor,
                    discount_minor: t.discount_minor,
                    tax_minor: t.tax_minor,
                    total_minor: t.total_minor,
                };
            }
        }
        render(&feature);
    });
}

/// Place the cart as an order via the core (online or queued offline). On
/// success the core has emptied the cart; the receipt flips the sheet to
/// the confirmation. Mirrors the natives' placeOrder split/tendered mapping:
/// split legs zero the tendered amount, a non-cash single payment tenders 0.
fn place_order(feature: &Arc<CheckoutFeature>, customer: String, notes: String) {
    let (input, receipt_ready) = {
        let s = feature.session.lock().unwrap();
        if s.is_placing {
            return;
        }
        let total = s.summary.total_minor;
        let selected = s.effective_selected().map(|m| m.id.clone());
        let is_cash = s
            .effective_selected()
            .map(|m| m.is_cash)
            .unwrap_or(false);
        // Split legs + the largest leg as the primary (the booking method).
        let mut splits: Vec<CheckoutSplit> = s
            .split_amounts
            .iter()
            .filter(|(_, v)| **v > 0)
            .map(|(id, v)| CheckoutSplit { payment_method_id: id.clone(), amount_minor: *v })
            .collect();
        splits.sort_by(|a, b| a.payment_method_id.cmp(&b.payment_method_id));
        let split_primary = splits
            .iter()
            .max_by_key(|leg| leg.amount_minor)
            .map(|leg| leg.payment_method_id.clone());
        let primary = if s.split_mode { split_primary } else { selected };
        let Some(primary) = primary else { return };
        let splits = if s.split_mode { splits } else { Vec::new() };
        let blank = |v: &str| {
            let t = v.trim();
            if t.is_empty() { None } else { Some(t.to_string()) }
        };
        let _ = total; // total participates via can-place gating in render()
        (
            CheckoutInput {
                payment_method_id: primary,
                amount_tendered_minor: if splits.is_empty() && is_cash { s.tendered_minor } else { 0 },
                tip_minor: s.tip_minor,
                tip_payment_method_id: s.tip_method_id.clone(),
                customer_name: blank(&customer),
                notes: blank(&notes),
                splits,
            },
            (),
        )
    };
    let _ = receipt_ready;
    {
        let mut s = feature.session.lock().unwrap();
        s.is_placing = true;
        s.error = None;
    }
    render(feature);
    let feature = feature.clone();
    rt().spawn(async move {
        let result = feature.core.checkout(input).await;
        match result {
            Ok(receipt) => {
                {
                    let mut s = feature.session.lock().unwrap();
                    s.receipt = Some(receipt);
                    s.print_state = Print::Idle;
                    s.is_placing = false;
                }
                render(&feature);
                // Auto-print the receipt on checkout — the confirmation's
                // Print button is for REPRINTS. print_receipt no-ops with no
                // printer configured and swallows its own errors, so it can
                // never fail the placed order.
                print_receipt(&feature, true).await;
            }
            Err(e) => {
                let msg = human_message(&feature.core, &e);
                {
                    let mut s = feature.session.lock().unwrap();
                    s.error = Some(msg);
                    s.is_placing = false;
                }
                // NOTE: the Flutter port also raises a shared re-auth request
                // on a 401 with a live session; this app has no re-auth
                // surface yet — the error banner carries the message.
                let _ = matches!(e, CoreError::Unauthenticated { .. });
                render(&feature);
            }
        }
    });
}

/// Render the placed receipt in the core and stream it to the configured
/// network printer (best-effort). Pops the till on a cash sale — only on
/// the original auto-print; a reprint passes `kick_drawer` = false.
async fn print_receipt(feature: &Arc<CheckoutFeature>, kick_drawer: bool) {
    let (receipt, branch_name, currency) = {
        let s = feature.session.lock().unwrap();
        let Some(r) = s.receipt.clone() else { return };
        (r, s.branch_name.clone(), s.currency.clone())
    };
    let core = &feature.core;
    let config = core.device_config();
    let host = config.printer_host.as_deref().unwrap_or("").trim().to_string();
    if host.is_empty() {
        feature.session.lock().unwrap().print_state = Print::NoPrinter;
        render(feature);
        return;
    }
    let port = config.printer_port.unwrap_or(JET_DIRECT_PORT);
    let brand = printer_brand_of(config.printer_brand.as_deref());
    feature.session.lock().unwrap().print_state = Print::Printing;
    render(feature);
    let is_cash = receipt.is_cash;
    let bytes = core.render_receipt(receipt, branch_name, currency, RECEIPT_CHARS, brand);
    let sent = core.send_to_printer(host.clone(), port, bytes).await;
    match sent {
        Ok(()) => {
            if kick_drawer && is_cash {
                // Best-effort till pop — failures swallowed (Dart `_quiet`).
                let kick = core.cash_drawer_kick(brand);
                let _ = core.send_to_printer(host, port, kick).await;
            }
            feature.session.lock().unwrap().print_state = Print::Printed;
        }
        Err(_) => feature.session.lock().unwrap().print_state = Print::Failed,
    }
    render(feature);
}

// ── Receipt paper flattening (receipt_paper.dart, row for row) ──────────────

fn mono(text: String, size: f32, weight: i32, ink: slint::Color, align_start: bool) -> PaperRowData {
    PaperRowData {
        kind: PaperRowKind::Mono,
        text: text.into(),
        right: SharedString::new(),
        size,
        weight,
        ink,
        align_start,
        bold: false,
        faint: false,
    }
}

fn money_row(left: String, right: String, bold: bool, faint: bool) -> PaperRowData {
    PaperRowData {
        kind: PaperRowKind::Money,
        text: left.into(),
        right: right.into(),
        size: 0.0,
        weight: 0,
        ink: INK,
        align_start: false,
        bold,
        faint,
    }
}

fn rule() -> PaperRowData {
    PaperRowData {
        kind: PaperRowKind::Rule,
        text: SharedString::new(),
        right: SharedString::new(),
        size: 0.0,
        weight: 0,
        ink: INK,
        align_start: false,
        bold: false,
        faint: false,
    }
}

fn name_with_size(base: &str, size: Option<&str>) -> String {
    match size {
        None => base.to_string(),
        Some(s) if s.is_empty() => base.to_string(),
        Some(s) => format!("{base} ({s})"),
    }
}

/// A priced modifier row — faint, indented, `+amount` only when charged.
fn mod_row(prefix: &str, m: &madar_core::checkout::ReceiptModifierView, cur: &str) -> PaperRowData {
    money_row(
        format!("{prefix}{}", m.name),
        if m.price_minor > 0 { format!("+{}", money(m.price_minor, cur)) } else { String::new() },
        false,
        true,
    )
}

/// Flatten a ReceiptView into paper rows + push the logo — mirrors the
/// receipt_paper.dart widget tree order EXACTLY (type sizes 15/13/12/11).
fn set_paper(
    ui: &AppWindow,
    core: &MadarCore,
    r: &ReceiptView,
    store_name: &str,
    currency: &str,
    logo_path: Option<&str>,
) {
    let t = |k: &str| core.tr(k.into());
    let m = |minor: i64| money(minor, currency);
    let mut rows: Vec<PaperRowData> = Vec::new();

    // ── header block ──
    if r.is_voided {
        rows.push(mono(format!("*** {} ***", t("receipt.voided")), 13.0, 700, VOID_RED, false));
    }
    rows.push(mono(
        if store_name.trim().is_empty() { "MADAR".to_string() } else { store_name.to_uppercase() },
        15.0,
        700,
        INK,
        false,
    ));
    if r.is_delivery {
        if let Some(channel) = &r.delivery_channel {
            let label = if channel == "in_mall" { t("delivery.in_mall") } else { t("receipt.delivery") };
            rows.push(mono(format!("— {} —", label.to_uppercase()), 11.0, 400, FAINT, false));
        }
    }
    rows.push(rule());

    // "Order #12" when the server assigned a number, else the local order
    // id's first uuid segment (the natives' orderTitle).
    let order_title = match r.order_number {
        Some(n) => format!("{} #{n}", t("receipt.order")),
        None => format!(
            "{} {}",
            t("receipt.order"),
            r.local_order_id.split('-').next().unwrap_or("").to_uppercase()
        ),
    };
    rows.push(money_row(
        order_title,
        core.format_time(r.created_at.clone(), TimeStyle::Receipt),
        false,
        false,
    ));
    if let Some(order_ref) = &r.order_ref {
        rows.push(money_row(format!("{}: {order_ref}", t("receipt.ref")), String::new(), false, false));
    }
    rows.push(rule());

    // ── delivery block ──
    if r.is_delivery {
        if let Some(v) = &r.customer_name {
            rows.push(money_row(t("receipt.customer"), v.clone(), false, false));
        }
        if let Some(v) = &r.customer_phone {
            rows.push(money_row(t("receipt.phone"), v.clone(), false, false));
        }
        if let Some(v) = &r.delivery_address {
            rows.push(mono(format!("{} {v}", t("receipt.address")), 12.0, 400, INK, true));
        }
        if let Some(v) = &r.delivery_zone {
            rows.push(money_row(t("receipt.zone"), v.clone(), false, false));
        }
        if let Some(v) = &r.delivery_ref {
            rows.push(money_row(t("receipt.delivery_ref"), v.clone(), false, false));
        }
        if let Some(v) = &r.payment_hint {
            rows.push(money_row(t("receipt.payment_hint"), v.clone(), false, false));
        }
        if let Some(v) = &r.delivery_notes {
            if !v.trim().is_empty() {
                rows.push(mono(format!("{} {v}", t("receipt.notes")), 12.0, 400, INK, true));
            }
        }
        rows.push(rule());
    }

    // ── line blocks: `qty× name (size) … amount`, then modifiers — a bundle
    // indents its components with their own addons/optionals. ──
    for line in &r.lines {
        rows.push(money_row(
            format!("{}× {}", line.qty, name_with_size(&line.name, line.size_label.as_deref())),
            m(line.line_total_minor),
            false,
            false,
        ));
        if line.is_bundle {
            for c in &line.components {
                rows.push(mono(
                    format!("  – {}", name_with_size(&c.name, c.size_label.as_deref())),
                    12.0,
                    400,
                    FAINT,
                    true,
                ));
                for md in &c.addons {
                    rows.push(mod_row("    + ", md, currency));
                }
                for md in &c.optionals {
                    rows.push(mod_row("    + ", md, currency));
                }
            }
        } else {
            for md in &line.addons {
                rows.push(mod_row("  + ", md, currency));
            }
            for md in &line.optionals {
                rows.push(mod_row("  + ", md, currency));
            }
        }
    }
    rows.push(rule());

    // ── totals block ──
    rows.push(money_row(t("order.subtotal"), m(r.subtotal_minor), false, false));
    if r.discount_minor > 0 {
        rows.push(money_row(
            t("order.discount"),
            format!("\u{2212}{}", m(r.discount_minor)),
            false,
            false,
        ));
    }
    if r.tax_minor > 0 {
        rows.push(money_row(t("order.tax"), m(r.tax_minor), false, false));
    }
    if r.delivery_fee_minor > 0 {
        rows.push(money_row(t("receipt.delivery_fee"), m(r.delivery_fee_minor), false, false));
    }
    rows.push(money_row(t("order.total").to_uppercase(), m(r.total_minor), true, false));
    if r.tip_minor > 0 {
        rows.push(money_row(t("order.tip"), m(r.tip_minor), false, false));
    }
    if r.is_cash {
        rows.push(money_row(t("receipt.cash"), m(r.amount_tendered_minor), false, false));
        rows.push(money_row(t("order.change"), m(r.change_minor), false, false));
    }
    rows.push(rule());

    // ── payment footer ──
    rows.push(mono(r.payment_label.to_uppercase(), 11.0, 600, INK, false));
    if let Some(teller) = &r.teller_name {
        rows.push(mono(format!("{} {teller}", t("receipt.served_by")), 11.0, 400, FAINT, false));
    }
    rows.push(mono(t("receipt.thank_you"), 12.0, 400, INK, false));

    let g = ui.global::<CheckoutState>();
    g.set_paper_rows(ModelRc::new(VecModel::from(rows)));
    // Org brand mark — the CORE-cached local file (downloaded during
    // refresh_catalog); nothing draws on failure, so an offline reprint
    // just shows the store name.
    let logo = logo_path
        .filter(|p| !p.is_empty())
        .and_then(|p| slint::Image::load_from_path(std::path::Path::new(p)).ok());
    g.set_has_logo(logo.is_some());
    g.set_org_logo(logo.unwrap_or_default());
}

// ── Receipt preview sheet (receipt_sheet.dart) ───────────────────────────────

/// Present any order's receipt in the preview sheet — a fresh checkout's
/// result or a re-rendered past order (`core.order_receipt_view`). The
/// integrator flips the ReceiptSheet `open` after calling this.
pub fn present_receipt_preview(feature: &Arc<CheckoutFeature>, receipt: ReceiptView, celebrate: bool) {
    {
        let mut p = feature.preview.lock().unwrap();
        p.receipt = Some(receipt.clone());
        p.printing = false;
    }
    let feature = feature.clone();
    rt().spawn(async move {
        let logo = feature.core.org_logo_local_path();
        let branch = feature.core.device_config().branch_name.unwrap_or_default();
        let currency = feature
            .core
            .current_session()
            .map(|s| s.currency_code)
            .unwrap_or_default();
        on_ui(&feature, move |ui, feature| {
            let g = ui.global::<CheckoutState>();
            g.set_celebrate(celebrate);
            g.set_preview_printing(false);
            g.set_toast_shown(false);
            set_paper(&ui, &feature.core, &receipt, &branch, &currency, logo.as_deref());
        });
    });
}

/// Print feedback toast — auto-dismissed after ToastData.seconds (2.6s).
fn toast(feature: &Arc<CheckoutFeature>, text: String, tone: Tone, icon: &'static str) {
    let seq = {
        let mut p = feature.preview.lock().unwrap();
        p.toast_seq += 1;
        p.toast_seq
    };
    on_ui(feature, move |ui, _| {
        let g = ui.global::<CheckoutState>();
        g.set_toast_text(text.into());
        g.set_toast_tone(tone);
        g.set_toast_icon(icon_for(&ui, icon));
        g.set_toast_shown(true);
    });
    let feature = feature.clone();
    rt().spawn(async move {
        tokio::time::sleep(std::time::Duration::from_millis(TOAST_MS)).await;
        if feature.preview.lock().unwrap().toast_seq == seq {
            on_ui(&feature, |ui, _| ui.global::<CheckoutState>().set_toast_shown(false));
        }
    });
}

/// Toast icons — resolved from the compiled asset catalog (the Dart passes
/// MadarIcon names; these are the same three glyph files icons.slint maps).
fn icon_for(_ui: &AppWindow, name: &str) -> slint::Image {
    let path = match name {
        "exclamationmark.triangle" => "assets/icons/triangle-alert.svg",
        "checkmark.circle" => "assets/icons/circle-check.svg",
        _ => "assets/icons/circle-x.svg", // xmark.circle
    };
    slint::Image::load_from_path(std::path::Path::new(path)).unwrap_or_default()
}

/// Render the previewed receipt in the core and stream it to the configured
/// printer. Guards on the printer config: with no printer bound it raises a
/// warning toast instead of attempting the send. No drawer kick — this is a
/// preview / reprint surface (the natives' printReceiptView).
fn preview_print(feature: &Arc<CheckoutFeature>) {
    let receipt = {
        let p = feature.preview.lock().unwrap();
        if p.printing {
            return;
        }
        let Some(r) = p.receipt.clone() else { return };
        r
    };
    let feature = feature.clone();
    rt().spawn(async move {
        let core = &feature.core;
        let config = core.device_config();
        let host = config.printer_host.as_deref().unwrap_or("").trim().to_string();
        if host.is_empty() {
            toast(
                &feature,
                core.tr("receipt.no_printer".into()),
                Tone::Warning,
                "exclamationmark.triangle",
            );
            return;
        }
        feature.preview.lock().unwrap().printing = true;
        on_ui(&feature, |ui, _| ui.global::<CheckoutState>().set_preview_printing(true));
        let bytes = core.render_receipt(
            receipt,
            config.branch_name.clone().unwrap_or_default(),
            core.current_session().map(|s| s.currency_code).unwrap_or_default(),
            RECEIPT_CHARS,
            printer_brand_of(config.printer_brand.as_deref()),
        );
        let sent = core
            .send_to_printer(host, config.printer_port.unwrap_or(JET_DIRECT_PORT), bytes)
            .await;
        match sent {
            Ok(()) => toast(&feature, core.tr("receipt.printed".into()), Tone::Success, "checkmark.circle"),
            Err(_) => toast(&feature, core.tr("receipt.print_failed".into()), Tone::Danger, "xmark.circle"),
        }
        feature.preview.lock().unwrap().printing = false;
        on_ui(&feature, |ui, _| ui.global::<CheckoutState>().set_preview_printing(false));
    });
}

// ── Wiring — connect every CheckoutState callback to the session ops. ───────

pub fn wire(ui: &AppWindow, feature: &Arc<CheckoutFeature>) {
    let g = ui.global::<CheckoutState>();
    {
        let f = feature.clone();
        g.on_select_method(move |id| {
            f.session.lock().unwrap().selected_method_id = Some(id.to_string());
            render(&f);
        });
    }
    {
        let f = feature.clone();
        g.on_toggle_split(move || {
            let mut s = f.session.lock().unwrap();
            s.split_mode = !s.split_mode;
            drop(s);
            render(&f);
        });
    }
    {
        let f = feature.clone();
        g.on_split_edited(move |id, text| {
            f.session
                .lock()
                .unwrap()
                .split_amounts
                .insert(id.to_string(), to_minor(text.as_str()));
            render(&f);
        });
    }
    {
        let f = feature.clone();
        g.on_tendered_edited(move |text| {
            f.session.lock().unwrap().tendered_minor = to_minor(text.as_str());
            render(&f);
        });
    }
    {
        // Quick-cash presets are the ONE external write into the tendered
        // field (the Dart AmountField's didUpdateWidget prefill).
        let f = feature.clone();
        let weak = ui.as_weak();
        g.on_quick_cash_tap(move |minor| {
            f.session.lock().unwrap().tendered_minor = minor as i64;
            if let Some(ui) = weak.upgrade() {
                ui.global::<CheckoutState>()
                    .set_tendered_text(minor_to_text(minor as i64).into());
            }
            render(&f);
        });
    }
    {
        let f = feature.clone();
        g.on_tip_edited(move |text| {
            f.session.lock().unwrap().tip_minor = to_minor(text.as_str());
            render(&f);
        });
    }
    {
        let f = feature.clone();
        g.on_tip_method(move |id| {
            f.session.lock().unwrap().tip_method_id = Some(id.to_string());
            render(&f);
        });
    }
    {
        let f = feature.clone();
        g.on_pick_discount(move |id| {
            let id = if id.is_empty() { None } else { Some(id.to_string()) };
            set_discount(&f, id);
        });
    }
    {
        let f = feature.clone();
        g.on_fire_terminal(move |customer, notes| {
            place_order(&f, customer.to_string(), notes.to_string());
        });
    }
    {
        // Drawer closed / sheet dismissed — drop the session so the next
        // presentation starts fresh (the autoDispose provider behavior).
        let f = feature.clone();
        g.on_closed(move || {
            *f.session.lock().unwrap() = Session::default();
        });
    }
    {
        // Confirmation reprint — never re-kicks the till.
        let f = feature.clone();
        g.on_reprint(move || {
            let f = f.clone();
            rt().spawn(async move { print_receipt(&f, false).await });
        });
    }
    {
        // "New Order" — the sheet pops; reset like a dismissal.
        let f = feature.clone();
        g.on_new_order(move || {
            *f.session.lock().unwrap() = Session::default();
        });
    }
    {
        let f = feature.clone();
        g.on_preview_print(move || preview_print(&f));
    }
    {
        let f = feature.clone();
        g.on_preview_done(move || {
            let mut p = f.preview.lock().unwrap();
            p.receipt = None;
            p.printing = false;
        });
    }
    {
        let f = feature.clone();
        g.on_toast_dismiss(move || {
            on_ui(&f, |ui, _| ui.global::<CheckoutState>().set_toast_shown(false));
        });
    }
}
