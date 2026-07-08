//! Incoming feature glue — the Rust side of `ui/feature_incoming.slint`:
//! the Slint port of the Flutter `incoming_provider.dart` (IncomingNotifier).
//! All business rules (status steps, reject-vs-cancel, finalize replay,
//! settle dedup) live in the CORE; this only sequences core calls and maps
//! the views into the `In` global's structs.
//!
//! Wiring (see NOTES-incoming.md): `let incoming = feature_incoming::wire(
//! core, &app_window);` once at boot, `feature_incoming::enter(&incoming,
//! tab)` on navigation, and forward `delivery.*`/`order.*`/`ticket.*`
//! realtime events + connection changes from the app's EventListener.

use madar_core::{delivery, error::CoreError, MadarCore};
use slint::{ComponentHandle, ModelRc, SharedString, VecModel, Weak};
use std::sync::{Arc, Mutex, Weak as StdWeak};

use crate::{human_message, rt, AppWindow, DeliveryOrderData, In, OrderLineData, PaymentMethodData, TicketData};

/// The wire statuses the "Active" filter keeps (everything not yet terminal)
/// — the natives' `activeStatusFilter` (AppModel.kt).
const ACTIVE_DELIVERY_STATUSES: &str = "received,confirmed,preparing,ready,out_for_delivery";

/// Shared incoming state reachable from both loops — the Riverpod
/// `IncomingNotifier`'s non-UI slice (the UI slice lives in the `In` global).
pub struct IncomingGlue {
    core: Arc<MadarCore>,
    ui: Weak<AppWindow>,
    /// Filter toggle — active lifecycle states only (default) vs everything.
    active_only: Mutex<bool>,
}

// ── UI thread helpers ─────────────────────────────────────────────────────────

fn on_ui(g: &Arc<IncomingGlue>, f: impl FnOnce(AppWindow, Arc<IncomingGlue>) + Send + 'static) {
    let ui = g.ui.clone();
    let g = g.clone();
    let _ = slint::invoke_from_event_loop(move || {
        if let Some(ui) = ui.upgrade() {
            f(ui, g);
        }
    });
}

fn set_busy(g: &Arc<IncomingGlue>, busy: bool) {
    on_ui(g, move |ui, _| ui.global::<In>().set_busy(busy));
}

/// Human message for a failed bridge call + clear busy (the Dart `_fail`).
/// (The Flutter port additionally raises the app-wide re-auth request on an
/// expired bearer; this shell has no re-auth surface — see NOTES.)
fn fail(g: &Arc<IncomingGlue>, e: &CoreError) {
    let msg = human_message(&g.core, e);
    on_ui(g, move |ui, _| {
        let inc = ui.global::<In>();
        inc.set_error(msg.into());
        inc.set_busy(false);
    });
}

fn set_error(g: &Arc<IncomingGlue>, msg: String) {
    on_ui(g, move |ui, _| ui.global::<In>().set_error(msg.into()));
}

/// Toast tones: 0 neutral · 1 success · 2 warning; icons: 0 none ·
/// 1 checkmark.circle · 2 exclamationmark.triangle (the Dart notifier's set).
fn show_toast(g: &Arc<IncomingGlue>, text: String, tone: i32, icon: i32) {
    on_ui(g, move |ui, _| {
        let inc = ui.global::<In>();
        inc.set_toast_text(text.into());
        inc.set_toast_tone(tone);
        inc.set_toast_icon(icon);
        // Re-key: flip off first so a toast shown over a live toast restarts
        // the slide + the 2.6s dismiss timer (the Dart sequence key).
        inc.set_toast_shown(false);
        inc.set_toast_shown(true);
    });
}

// ── Formatting (design_system Money.format, verbatim) ────────────────────────

/// `"EGP 12.50"` — two decimals, uppercased code before the amount, leading
/// `-` for negatives; an empty code yields just the amount.
fn money(minor: i64, currency: &str) -> String {
    let neg = minor < 0;
    let cents = minor.abs();
    let amount = format!("{}{}.{:02}", if neg { "-" } else { "" }, cents / 100, cents % 100);
    let code = currency.to_uppercase();
    if code.is_empty() { amount } else { format!("{code} {amount}") }
}

/// The session's currency code ('' when signed out — Money then bare).
fn currency(core: &MadarCore) -> String {
    core.current_session().map(|s| s.currency_code).unwrap_or_default()
}

/// "Address:" → "Address" (the natives' removeSuffix(":")).
fn strip_colon(label: String) -> String {
    label.strip_suffix(':').map(str::to_string).unwrap_or(label)
}

// ── Localization: every tr key the Dart source resolves. ────────────────────

pub fn apply_strings(ui: &AppWindow, core: &MadarCore) {
    let t = |k: &str| SharedString::from(core.tr(k.into()));
    let inc = ui.global::<In>();
    inc.set_tr_title(t("incoming.title"));
    inc.set_tr_delivery_tab(t("delivery.title"));
    inc.set_tr_tickets_tab(t("waiter.title"));
    inc.set_tr_active(t("delivery.active"));
    inc.set_tr_all(t("delivery.all"));
    inc.set_tr_accepting(t("delivery.accepting"));
    inc.set_tr_delivery_empty(t("delivery.empty"));
    inc.set_tr_view_order(t("order.view_order"));
    inc.set_tr_finalize(t("delivery.finalize"));
    inc.set_tr_add_prep(t("delivery.add_prep"));
    inc.set_tr_cancel(t("delivery.cancel"));
    inc.set_tr_cancel_reason(t("delivery.cancel_reason"));
    inc.set_tr_restore_inventory(t("delivery.restore_inventory"));
    inc.set_tr_settle(t("waiter.settle"));
    inc.set_tr_no_tickets(t("waiter.no_tickets"));
    inc.set_tr_queued(t("waiter.queued"));
    inc.set_tr_items_header(t("order.items"));
    inc.set_tr_cart_empty(t("order.cart_empty"));
    inc.set_tr_total(t("order.total"));
    inc.set_tr_subtotal(t("order.subtotal"));
    inc.set_tr_discount(t("order.discount"));
    inc.set_tr_delivery_fee(t("receipt.delivery_fee"));
    inc.set_tr_address(strip_colon(core.tr("receipt.address".into())).into());
    inc.set_tr_payment_method(t("order.payment_method"));
    inc.set_tr_delivery_title(t("delivery.title"));
}

// ── View → struct mapping ────────────────────────────────────────────────────

fn line_row(l: &madar_core::tickets::TicketLineView, cur: &str) -> OrderLineData {
    // Size + modifiers as one light secondary line, " · " joined (the Dart
    // `detail` list join).
    let mut detail: Vec<String> = Vec::new();
    if let Some(size) = l.size_label.as_deref().filter(|s| !s.is_empty()) {
        detail.push(size.to_string());
    }
    detail.extend(l.modifiers.iter().cloned());
    OrderLineData {
        qty_label: format!("{}×", l.qty).into(),
        name: l.name.clone().into(),
        detail: detail.join(" · ").into(),
        total: money(l.line_total_minor, cur).into(),
        voided: l.voided,
    }
}

fn order_row(core: &MadarCore, o: &delivery::DeliveryOrderView, cur: &str) -> DeliveryOrderData {
    let tr = |k: &str| core.tr(k.into());
    DeliveryOrderData {
        id: o.id.clone().into(),
        order_ref: o.order_ref.clone().unwrap_or_default().into(),
        status: o.status.clone().into(),
        status_label: tr(&format!("delivery.status.{}", o.status)).into(),
        channel_label: tr(&format!("delivery.{}", o.channel)).into(),
        customer_name: o.customer_name.clone().into(),
        customer_phone: o.customer_phone.clone().into(),
        address: o.address.clone().unwrap_or_default().into(),
        delivery_notes: o.delivery_notes.clone().unwrap_or_default().into(),
        payment_hint: o.payment_hint.clone().unwrap_or_default().into(),
        total: money(o.total_minor, cur).into(),
        subtotal: money(o.subtotal_minor, cur).into(),
        // "−" prefixed like the Dart totals row; "" hides.
        discount: if o.discount_minor > 0 {
            format!("−{}", money(o.discount_minor, cur)).into()
        } else {
            SharedString::new()
        },
        delivery_fee: if o.delivery_fee_minor > 0 {
            money(o.delivery_fee_minor, cur).into()
        } else {
            SharedString::new()
        },
        // The card's '· Delivery fee EGP 10.00' trailer ("" hides).
        fee_line: if o.delivery_fee_minor > 0 {
            format!("· {} {}", tr("receipt.delivery_fee"), money(o.delivery_fee_minor, cur)).into()
        } else {
            SharedString::new()
        },
        items_label: format!("{} {}", o.item_count, tr("delivery.items")).into(),
        // One forward lifecycle step the STATUS endpoint accepts;
        // out_for_delivery → None → the card offers Settle instead.
        next_label: delivery::next_status(&o.status)
            .map(|n| tr(&format!("delivery.action.{n}")))
            .unwrap_or_default()
            .into(),
        is_terminal: o.is_terminal,
        lines: ModelRc::new(VecModel::from(
            o.lines.iter().map(|l| line_row(l, cur)).collect::<Vec<_>>(),
        )),
    }
}

fn ticket_row(core: &MadarCore, t: &madar_core::tickets::TicketView, cur: &str) -> TicketData {
    let tr = |k: &str| core.tr(k.into());
    let waiter = t.waiter_name.clone().unwrap_or_default();
    let waiter_line = if waiter.is_empty() {
        String::new()
    } else {
        format!("{}: {}", tr("order.waiter"), waiter)
    };
    TicketData {
        id: t.id.clone().into(),
        ticket_ref: t
            .ticket_ref
            .clone()
            .filter(|r| !r.is_empty())
            .unwrap_or_else(|| tr("waiter.ticket"))
            .into(),
        status: t.status.clone().into(),
        status_label: tr(&format!("ticket.status.{}", t.status)).into(),
        customer_name: t.customer_name.clone().unwrap_or_default().into(),
        ctx_waiter: waiter_line.clone().into(),
        waiter_line: waiter_line.into(),
        ctx_table: t
            .table_id
            .clone()
            .filter(|x| !x.is_empty())
            .map(|x| format!("{} {}", tr("order.table"), x))
            .unwrap_or_default()
            .into(),
        ctx_covers: t
            .guest_count
            .filter(|c| *c > 0)
            .map(|c| format!("{} {}", c, tr("waiter.covers")))
            .unwrap_or_default()
            .into(),
        queued_offline: t.queued_offline,
        subtotal: money(t.subtotal_minor, cur).into(),
        items_label: format!("{} {}", t.lines.len(), tr("waiter.items")).into(),
        lines: ModelRc::new(VecModel::from(
            t.lines.iter().map(|l| line_row(l, cur)).collect::<Vec<_>>(),
        )),
    }
}

fn set_settings(g: &Arc<IncomingGlue>, s: delivery::DeliverySettingsView) {
    let core = g.core.clone();
    on_ui(g, move |ui, _| {
        let tr = |k: &str| core.tr(k.into());
        let chip = |label_key: &str, mode: &str| -> SharedString {
            // '$label: ${tr('delivery.mode_$mode')}' (the Dart chip label).
            format!("{}: {}", tr(label_key), tr(&format!("delivery.mode_{mode}"))).into()
        };
        let inc = ui.global::<In>();
        inc.set_in_mall_chip(chip("delivery.in_mall", &s.in_mall_override));
        inc.set_in_mall_mode(s.in_mall_override.clone().into());
        inc.set_in_mall_enabled(s.in_mall_enabled);
        inc.set_outside_chip(chip("delivery.outside", &s.outside_override));
        inc.set_outside_mode(s.outside_override.clone().into());
        inc.set_outside_enabled(s.outside_enabled);
        inc.set_has_settings(true);
    });
}

// ── Feeds (the notifier's loadDeliveryOrders / loadOpenTickets) ─────────────

/// The branch delivery queue (online). Active-only by default; the accepting
/// settings ride along quietly (natives' loadDeliveryOrders).
pub fn load_delivery_orders(g: &Arc<IncomingGlue>) {
    let g = g.clone();
    on_ui(&g.clone(), |ui, _| ui.global::<In>().set_loading_delivery(true));
    rt().spawn(async move {
        let status = if *g.active_only.lock().unwrap() {
            Some(ACTIVE_DELIVERY_STATUSES.to_string())
        } else {
            None
        };
        match g.core.list_delivery_orders(status).await {
            Ok(orders) => {
                let core = g.core.clone();
                on_ui(&g, move |ui, _| {
                    let cur = currency(&core);
                    let rows: Vec<DeliveryOrderData> =
                        orders.iter().map(|o| order_row(&core, o, &cur)).collect();
                    let inc = ui.global::<In>();
                    inc.set_delivery_orders(ModelRc::new(VecModel::from(rows)));
                    inc.set_loading_delivery(false);
                });
            }
            Err(e) => {
                let msg = human_message(&g.core, &e);
                on_ui(&g, move |ui, _| {
                    let inc = ui.global::<In>();
                    inc.set_error(msg.into());
                    inc.set_loading_delivery(false);
                });
            }
        }
        // Best-effort — the natives swallow this refresh.
        if let Ok(settings) = g.core.delivery_settings().await {
            set_settings(&g, settings);
        }
    });
}

/// Quiet refresh — the natives swallow failures (runCatching). Only
/// OPEN/READY tickets can be settled (IncomingState.settleableTickets).
pub fn load_open_tickets(g: &Arc<IncomingGlue>) {
    let g = g.clone();
    rt().spawn(async move {
        if let Ok(tickets) = g.core.list_open_tickets().await {
            let core = g.core.clone();
            on_ui(&g, move |ui, _| {
                let cur = currency(&core);
                let rows: Vec<TicketData> = tickets
                    .iter()
                    .filter(|t| t.status == "open" || t.status == "ready")
                    .map(|t| ticket_row(&core, t, &cur))
                    .collect();
                ui.global::<In>().set_tickets(ModelRc::new(VecModel::from(rows)));
            });
        }
    });
}

/// Payment methods for the finalize/settle sheet (cached core read).
fn load_payment_methods(g: &Arc<IncomingGlue>) {
    let g = g.clone();
    rt().spawn(async move {
        if let Ok(methods) = g.core.list_payment_methods() {
            on_ui(&g, move |ui, _| {
                ui.global::<In>().set_payment_methods(ModelRc::new(VecModel::from(
                    methods
                        .iter()
                        .map(|m| PaymentMethodData {
                            id: m.id.clone().into(),
                            name: m.name.clone().into(),
                            is_cash: m.is_cash,
                        })
                        .collect::<Vec<_>>(),
                )));
            });
        }
    });
}

/// Screen entry: land on [tab], clear stale failures, and load both feeds so
/// the tab badges populate immediately (the notifier's `enter`).
pub fn enter(g: &Arc<IncomingGlue>, tab: i32) {
    on_ui(g, move |ui, g| {
        apply_strings(&ui, &g.core);
        let inc = ui.global::<In>();
        inc.set_tab(tab);
        inc.set_error(SharedString::new());
        inc.set_busy(false);
        inc.set_cancel_open(false);
        inc.set_pay_open(false);
        inc.set_toast_shown(false);
        load_delivery_orders(&g);
        load_open_tickets(&g);
        load_payment_methods(&g);
    });
}

/// Session-level realtime tick routing — the shell bumps the delivery feed
/// on `delivery.*`/`order.*` and the tickets feed on `ticket.*` (the Flutter
/// deliveryTickProvider / ticketTickProvider listens).
pub fn on_realtime_event(g: &Arc<IncomingGlue>, event_type: &str) {
    if event_type.starts_with("delivery.") || event_type.starts_with("order.") {
        load_delivery_orders(g);
    }
    if event_type.starts_with("ticket.") {
        load_open_tickets(g);
    }
}

/// Connection changes gate the 60s delivery safety poll in the UI.
pub fn on_connection_changed(g: &Arc<IncomingGlue>, connected: bool) {
    on_ui(g, move |ui, _| ui.global::<In>().set_realtime_connected(connected));
}

// ── Mutations ─────────────────────────────────────────────────────────────────

/// Cycle a channel's accepting override: auto → open → closed → auto.
fn cycle_accepting(g: &Arc<IncomingGlue>, channel: String, current: String) {
    let next = match current.as_str() {
        "auto" => "open",
        "open" => "closed",
        _ => "auto",
    };
    let g = g.clone();
    set_busy(&g, true);
    set_error(&g, String::new());
    rt().spawn(async move {
        match g.core.delivery_set_accepting(channel, next.to_string()).await {
            Ok(settings) => {
                set_settings(&g, settings);
                set_busy(&g, false);
            }
            Err(e) => fail(&g, &e),
        }
    });
}

/// Advance one lifecycle step (Confirm → Preparing → … → Out for delivery).
fn advance_delivery(g: &Arc<IncomingGlue>, id: String, status: String) {
    let g = g.clone();
    set_busy(&g, true);
    set_error(&g, String::new());
    rt().spawn(async move {
        match g.core.delivery_advance_status(id, status).await {
            Ok(_) => {
                load_delivery_orders(&g);
                set_busy(&g, false);
            }
            Err(e) => fail(&g, &e),
        }
    });
}

/// Add extra prep time (multiples of 5).
fn add_delivery_prep(g: &Arc<IncomingGlue>, id: String) {
    let g = g.clone();
    rt().spawn(async move {
        match g.core.delivery_set_prep_time(id, 5).await {
            Ok(_) => load_delivery_orders(&g),
            Err(e) => set_error(&g, human_message(&g.core, &e)),
        }
    });
}

/// Cancel a delivery order (optionally restocking ingredients). Reject =
/// cancel a not-yet-accepted (received) order — the backend's cancel
/// endpoint flips received→rejected; the core models it, we just call.
fn cancel_delivery(g: &Arc<IncomingGlue>, id: String, reason: String, restock: bool) {
    let g = g.clone();
    set_busy(&g, true);
    set_error(&g, String::new());
    rt().spawn(async move {
        let reason = {
            let r = reason.trim().to_string();
            if r.is_empty() { None } else { Some(r) }
        };
        match g.core.delivery_cancel(id, reason, restock).await {
            Ok(_) => {
                load_delivery_orders(&g);
                // Success pops the sheet (the Dart `maybePop` on ok).
                on_ui(&g, |ui, _| {
                    let inc = ui.global::<In>();
                    inc.set_busy(false);
                    inc.set_cancel_open(false);
                });
            }
            Err(e) => fail(&g, &e), // failure surfaces INSIDE the sheet
        }
    });
}

/// Finalize into a real sale on the open shift, charged to a payment method.
/// Surfaces oversold warnings instead of dropping them — the teller must SEE
/// that (the natives' finalizeDelivery).
fn finalize_delivery(g: &Arc<IncomingGlue>, id: String, payment_method_id: String) {
    let g = g.clone();
    set_busy(&g, true);
    set_error(&g, String::new());
    rt().spawn(async move {
        match g.core.delivery_finalize(id, payment_method_id).await {
            Ok(res) => {
                load_delivery_orders(&g);
                let order_ref = res
                    .order_ref
                    .map(|r| format!(" · {r}"))
                    .unwrap_or_default();
                let finalized = g.core.tr("delivery.finalized".into());
                if res.warnings.is_empty() {
                    show_toast(&g, format!("{finalized}{order_ref}"), 1, 1);
                } else {
                    show_toast(
                        &g,
                        format!("{finalized}{order_ref} — {}", res.warnings.join("; ")),
                        2,
                        2,
                    );
                }
                on_ui(&g, |ui, _| {
                    let inc = ui.global::<In>();
                    inc.set_busy(false);
                    inc.set_pay_open(false);
                });
                // Flutter continues into the created order's ReceiptSheet —
                // the receipt feature isn't ported yet (see NOTES).
            }
            Err(e) => fail(&g, &e), // failure surfaces INSIDE the drawer
        }
    });
}

/// SETTLE a ticket into a paid order on the current open shift — requires a
/// shift, books via the core, then reloads + toasts. `tendered_text` is the
/// sheet's cash field ("12.50" major units; sent only for a cash primary).
fn settle_ticket(
    g: &Arc<IncomingGlue>,
    ticket_id: String,
    payment_method_id: String,
    tendered_text: String,
    is_cash: bool,
) {
    let g = g.clone();
    rt().spawn(async move {
        // Quiet lookup (the notifier's `_quiet`) — a shift-read failure reads
        // as "no shift", never an unhandled error.
        let shift = g.core.current_shift().ok().flatten();
        let Some(shift) = shift else {
            set_error(&g, g.core.tr("waiter.need_shift".into()));
            return;
        };
        set_busy(&g, true);
        set_error(&g, String::new());
        // The natives' settle mapping: tendered only for a cash primary.
        let tendered = if is_cash {
            tendered_text
                .trim()
                .parse::<f64>()
                .ok()
                .map(|v| (v * 100.0).round() as i64)
                .filter(|v| *v > 0)
        } else {
            None
        };
        let result = g
            .core
            .settle_ticket(
                ticket_id,
                shift.id,
                payment_method_id,
                tendered,
                None, // tip — the CheckoutDrawer extra, not in this stand-in
                None,
                None, // settle-time discount — cashier drawer only
                None,
                None,
            )
            .await;
        match result {
            Ok(_) => {
                load_open_tickets(&g);
                show_toast(&g, g.core.tr("waiter.settled".into()), 1, 0);
                on_ui(&g, |ui, _| {
                    let inc = ui.global::<In>();
                    inc.set_busy(false);
                    inc.set_pay_open(false);
                });
            }
            Err(e) => fail(&g, &e), // failure surfaces INSIDE the drawer
        }
    });
}

// ── Wiring ────────────────────────────────────────────────────────────────────

/// Hook every `In` callback up to the core. Call once at boot, after the
/// window exists; keep the returned Arc and drive `enter` / realtime with it.
pub fn wire(core: Arc<MadarCore>, ui: &AppWindow) -> Arc<IncomingGlue> {
    let g = Arc::new(IncomingGlue {
        core,
        ui: ui.as_weak(),
        active_only: Mutex::new(true),
    });
    let inc = ui.global::<In>();

    // Per-callback closures below each capture their own clone of `g`.

    {
        let g = g.clone();
        inc.on_reload_delivery(move || load_delivery_orders(&g));
    }
    {
        let g = g.clone();
        inc.on_reload_tickets(move || load_open_tickets(&g));
    }
    {
        // The 60s safety net — the UI only runs this timer while realtime is
        // down (RealtimeGatedPoll), so a plain reload is correct here.
        let g = g.clone();
        inc.on_delivery_poll(move || load_delivery_orders(&g));
    }
    {
        // Active/All filter toggle — reloads the queue under the new filter.
        let g = g.clone();
        inc.on_set_active_only(move |active| {
            {
                let mut a = g.active_only.lock().unwrap();
                if *a == active {
                    return;
                }
                *a = active;
            }
            if let Some(ui) = g.ui.upgrade() {
                ui.global::<In>().set_delivery_active_only(active);
            }
            load_delivery_orders(&g);
        });
    }
    {
        let g = g.clone();
        inc.on_cycle_accepting(move |channel, mode| {
            cycle_accepting(&g, channel.to_string(), mode.to_string());
        });
    }
    {
        let g = g.clone();
        inc.on_advance(move |id, status| {
            advance_delivery(&g, id.to_string(), status.to_string());
        });
    }
    {
        let g = g.clone();
        inc.on_add_prep(move |id| add_delivery_prep(&g, id.to_string()));
    }
    {
        let g = g.clone();
        inc.on_cancel_delivery(move |id, reason, restock| {
            cancel_delivery(&g, id.to_string(), reason.to_string(), restock);
        });
    }
    {
        let g = g.clone();
        inc.on_finalize(move |id, pm| {
            finalize_delivery(&g, id.to_string(), pm.to_string());
        });
    }
    {
        let g = g.clone();
        inc.on_settle(move |ticket_id, pm, tendered, is_cash| {
            settle_ticket(&g, ticket_id.to_string(), pm.to_string(), tendered.to_string(), is_cash);
        });
    }
    // `In.back()` is the app's to route (screen switch) — wired by the
    // integrator in main.rs, not here.
    g
}
