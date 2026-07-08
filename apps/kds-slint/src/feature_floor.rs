//! Floor feature glue — port of the Flutter `feature_floor` provider
//! (floor_provider.dart) over madar-core: sections, tables, bookings, the
//! open-tickets join, host ops (seat / notify / set status), and the settle
//! shift-guard. All business logic stays in the core; this only sequences
//! core calls and marshals view data into the `FloorState` slint global.
//!
//! Integration (see NOTES-floor.md): construct a [`Floor`] next to `App`,
//! call [`wire`] once after building the window, [`enter`] whenever the
//! shell routes onto the floor screen, and [`reload`] from the realtime
//! listener's `ticket.*` / `order.*` events (the Flutter ticketTick /
//! deliveryTick listens). `settle-ticket` is the one callback left for the
//! integrator — it opens the shared checkout drawer (feature_checkout), the
//! drawer's terminal action then calls [`settle_ticket`] here.

use madar_core::{error::CoreError, MadarCore};
use slint::{ComponentHandle, ModelRc, SharedString, VecModel, Weak};
use std::sync::{
    atomic::{AtomicBool, AtomicI32, Ordering},
    Arc, Mutex, OnceLock,
};

use crate::{AppWindow, FloorBookingData, FloorSectionData, FloorState, FloorTableData,
    FloorTicketLineData, SeatRowData};

/// The one tokio runtime backing every core call. (Duplicate of the private
/// `rt()` in main.rs — flag for promotion to a shared module.)
fn rt() -> &'static tokio::runtime::Runtime {
    static RT: OnceLock<tokio::runtime::Runtime> = OnceLock::new();
    RT.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
            .expect("tokio runtime")
    })
}

/// Fallback canvas extent when a section carries none (natives: 1000×700).
const FALLBACK_CANVAS_W: f32 = 1000.0;
const FALLBACK_CANVAS_H: f32 = 700.0;

/// Mirror of the natives' AppModel floor slice (FloorState in
/// floor_provider.dart): sections, tables, bookings, the open-tickets join,
/// and the transient seat picks of the seat sheet.
#[derive(Default)]
struct FloorData {
    sections: Vec<madar_core::reservations::FloorSectionView>,
    tables: Vec<madar_core::reservations::FloorTableView>,
    reservations: Vec<madar_core::reservations::ReservationView>,
    open_tickets: Vec<madar_core::tickets::TicketView>,
    /// The picked section id (None = first section, the natives' default).
    active_section_id: Option<String>,
    /// Tables picked in the seat sheet (multiple ⇒ merged tables).
    seat_picks: Vec<String>,
    /// The booking the seat sheet is presenting.
    seat_booking_id: Option<String>,
}

/// The floor board's shared state — kept alive across the shell so the
/// 15-second live refresh lands wherever the plan is shown.
pub struct Floor {
    core: Arc<MadarCore>,
    ui: Weak<AppWindow>,
    data: Mutex<FloorData>,
    toast_seq: AtomicI32,
    /// Realtime health — the 15s heartbeat polls ONLY while this is false
    /// (the Flutter RealtimeGatedPoll). The integrator sets it from the
    /// realtime listener's `on_connection_changed`.
    connected: AtomicBool,
}

impl Floor {
    pub fn new(core: Arc<MadarCore>, ui: Weak<AppWindow>) -> Arc<Self> {
        Arc::new(Self {
            core,
            ui,
            data: Mutex::new(FloorData::default()),
            toast_seq: AtomicI32::new(0),
            connected: AtomicBool::new(true),
        })
    }

    /// Realtime connection health (drives the poll gate).
    pub fn set_connected(&self, connected: bool) {
        self.connected.store(connected, Ordering::Relaxed);
    }
}

// ── UI thread helper (the main.rs `on_ui` shape, over Floor) ────────────────

fn on_ui(floor: &Arc<Floor>, f: impl FnOnce(AppWindow, Arc<Floor>) + Send + 'static) {
    let ui = floor.ui.clone();
    let floor = floor.clone();
    let _ = slint::invoke_from_event_loop(move || {
        if let Some(ui) = ui.upgrade() {
            f(ui, floor);
        }
    });
}

/// Port of the Flutter bridge's `humanMessage` — host conditions get
/// core-localized strings; server/validation details pass through verbatim.
/// (Duplicate of the private fn in main.rs — flag for promotion.)
fn human_message(core: &MadarCore, e: &CoreError) -> String {
    let or = |detail: &str| {
        if detail.trim().is_empty() {
            core.tr("err.generic".into())
        } else {
            detail.to_string()
        }
    };
    match e {
        CoreError::Offline { .. } => core.tr("err.offline_no_setup".into()),
        CoreError::Unauthenticated { detail } => or(detail),
        CoreError::Validation { field, detail } => {
            if field.trim().is_empty() {
                or(detail)
            } else {
                or(&format!("{} {detail}", field.replace('_', " ")))
            }
        }
        CoreError::Server { detail, .. } => or(detail),
        CoreError::Transient { .. } => core.tr("err.network".into()),
        CoreError::Forbidden { .. } => core.tr("err.not_allowed".into()),
        CoreError::Internal { detail } => or(detail),
    }
}

/// Money.format — minor units to `"CODE W.FF"`, uppercased code, leading `-`
/// for negatives, empty code → bare amount (design_system money.dart, itself
/// the Kotlin/Swift `Money` natives).
fn money_format(minor: i64, currency: &str) -> String {
    let neg = minor < 0;
    let cents = minor.unsigned_abs();
    let whole = cents / 100;
    let frac = cents % 100;
    let amount = format!("{}{whole}.{frac:02}", if neg { "-" } else { "" });
    let code = currency.to_uppercase();
    if code.is_empty() {
        amount
    } else {
        format!("{code} {amount}")
    }
}

/// Ticket status → chip tone name (the natives' `ticketStatusTone`,
/// TicketReviewCard._tone in floor_sheets.dart).
fn ticket_status_tone(status: &str) -> &'static str {
    match status {
        "ready" => "success",
        "queued" => "warning",
        "settled" => "neutral",
        _ => "accent",
    }
}

// ── Localization: every `tr` key the Dart source resolves. ──────────────────

pub fn apply_floor_strings(ui: &AppWindow, core: &MadarCore) {
    let t = |k: &str| SharedString::from(core.tr(k.into()));
    let fs = ui.global::<FloorState>();
    fs.set_tr_title(t("reservations.title"));
    fs.set_tr_no_bookings(t("reservations.noBookings"));
    fs.set_tr_seat(t("reservations.seat"));
    fs.set_tr_set_status(t("reservations.setStatus"));
    fs.set_tr_status_free(t("reservations.status_free"));
    fs.set_tr_status_held(t("reservations.status_held"));
    fs.set_tr_status_seated(t("reservations.status_seated"));
    fs.set_tr_status_dirty(t("reservations.status_dirty"));
    fs.set_tr_cancel(t("common.cancel"));
    fs.set_tr_settle(t("waiter.settle"));
    // Header subtitle — the branch name (empty hides it).
    fs.set_branch_name(
        core.device_config()
            .branch_name
            .unwrap_or_default()
            .into(),
    );
}

// ── Selectors (FloorState.activeSection / tablesIn / ticketForTable) ────────

impl FloorData {
    /// The active section, resolving a stale/unset pick to the first section.
    fn active_section(&self) -> Option<&madar_core::reservations::FloorSectionView> {
        self.sections
            .iter()
            .find(|s| Some(&s.id) == self.active_section_id.as_ref())
            .or_else(|| self.sections.first())
    }

    /// Tables belonging to the active section, in canvas order.
    fn tables_in_active(&self) -> Vec<&madar_core::reservations::FloorTableView> {
        let section_id = self.active_section().map(|s| s.id.clone());
        self.tables
            .iter()
            .filter(|t| t.section_id == section_id)
            .collect()
    }

    /// The settleable open ticket sitting on `table_id`, if any.
    fn ticket_for_table(&self, table_id: &str) -> Option<&madar_core::tickets::TicketView> {
        self.open_tickets.iter().find(|t| {
            t.table_id.as_deref() == Some(table_id)
                && (t.status == "open" || t.status == "ready")
        })
    }
}

// ── Rendering: floor slices → slint models ──────────────────────────────────

fn render(floor: &Arc<Floor>) {
    on_ui(floor, |ui, floor| {
        let data = floor.data.lock().unwrap();
        let fs = ui.global::<FloorState>();

        let section = data.active_section();
        fs.set_active_section_id(
            section.map(|s| s.id.clone()).unwrap_or_default().into(),
        );
        // Fallback canvas extent when a section carries none.
        let (cw, ch) = section
            .map(|s| (s.canvas_w, s.canvas_h))
            .unwrap_or((0, 0));
        fs.set_canvas_w(if cw > 0 { cw as f32 } else { FALLBACK_CANVAS_W });
        fs.set_canvas_h(if ch > 0 { ch as f32 } else { FALLBACK_CANVAS_H });

        fs.set_sections(ModelRc::new(VecModel::from(
            data.sections
                .iter()
                .map(|s| FloorSectionData { id: s.id.clone().into(), name: s.name.clone().into() })
                .collect::<Vec<_>>(),
        )));
        fs.set_tables(ModelRc::new(VecModel::from(
            data.tables_in_active()
                .iter()
                .map(|t| FloorTableData {
                    id: t.id.clone().into(),
                    label: t.label.clone().into(),
                    seats_text: t.seats.to_string().into(),
                    circle: t.shape == "circle",
                    status: t.status.clone().into(),
                    pos_x: t.pos_x as f32,
                    pos_y: t.pos_y as f32,
                    w: t.width as f32,
                    h: t.height as f32,
                })
                .collect::<Vec<_>>(),
        )));
        // "party · status" — the raw status string, as the Dart row shows it.
        fs.set_bookings(ModelRc::new(VecModel::from(
            data.reservations
                .iter()
                .map(|b| FloorBookingData {
                    id: b.id.clone().into(),
                    name: b.customer_name.clone().into(),
                    meta: format!("{} · {}", b.party_size, b.status).into(),
                })
                .collect::<Vec<_>>(),
        )));
        drop(data);
        apply_floor_strings(&ui, &floor.core);
        render_seat_rows_on(&ui, &floor);
    });
}

/// Seat-sheet rows — "label · seats · status" over the ACTIVE section's
/// tables, check-tinted by the live pick set. (Must run on the UI thread.)
fn render_seat_rows_on(ui: &AppWindow, floor: &Arc<Floor>) {
    let data = floor.data.lock().unwrap();
    let rows: Vec<SeatRowData> = data
        .tables_in_active()
        .iter()
        .map(|t| {
            let status_label = floor.core.tr(format!("reservations.status_{}", t.status));
            SeatRowData {
                id: t.id.clone().into(),
                text: format!("{} · {} · {}", t.label, t.seats, status_label).into(),
                picked: data.seat_picks.contains(&t.id),
            }
        })
        .collect();
    let any = !data.seat_picks.is_empty();
    drop(data);
    let fs = ui.global::<FloorState>();
    fs.set_seat_rows(ModelRc::new(VecModel::from(rows)));
    fs.set_seat_any_picked(any);
}

// ── ui slices ────────────────────────────────────────────────────────────────

/// Surface a failed op — human message into the error slot. (The Flutter
/// `_raise` also requests re-auth on a 401; this shell has no reauth flow —
/// documented in NOTES-floor.md.)
fn raise(floor: &Arc<Floor>, e: &CoreError) {
    let msg = human_message(&floor.core, e);
    on_ui(floor, move |ui, _| ui.global::<FloorState>().set_error(msg.into()));
}

fn set_busy(floor: &Arc<Floor>, busy: bool) {
    on_ui(floor, move |ui, _| ui.global::<FloorState>().set_busy(busy));
}

/// Present a transient toast pill (the notifier's `showToast`).
fn show_toast(floor: &Arc<Floor>, text: String, tone: &'static str, has_icon: bool) {
    let id = floor.toast_seq.fetch_add(1, Ordering::Relaxed) + 1;
    on_ui(floor, move |ui, _| {
        let fs = ui.global::<FloorState>();
        fs.set_toast_id(id);
        fs.set_toast_text(text.into());
        fs.set_toast_tone(tone.into());
        fs.set_toast_has_icon(has_icon);
        fs.set_toast_shown(true);
    });
}

// ── loads ────────────────────────────────────────────────────────────────────

/// Best-effort refresh of every floor slice — each list keeps its last good
/// value on failure (the natives' `runCatching { … }.getOrNull()`; the
/// Flutter `_quiet`). Call on screen entry, after every host op, and from
/// the realtime `ticket.*` / `order.*` events.
pub fn reload(floor: &Arc<Floor>) {
    let floor = floor.clone();
    rt().spawn(async move {
        let sections = floor.core.list_floor_sections().await.ok();
        let tables = floor.core.list_floor_tables().await.ok();
        let reservations = floor.core.list_reservations().await.ok();
        let open_tickets = floor.core.list_open_tickets().await.ok();
        {
            let mut data = floor.data.lock().unwrap();
            if let Some(v) = sections {
                data.sections = v;
            }
            if let Some(v) = tables {
                data.tables = v;
            }
            if let Some(v) = reservations {
                data.reservations = v;
            }
            if let Some(v) = open_tickets {
                data.open_tickets = v;
            }
        }
        render(&floor);
    });
}

/// Screen entry — the Dart initState post-frame `loadFloor`.
pub fn enter(floor: &Arc<Floor>) {
    render(floor); // last good state paints immediately
    reload(floor);
}

// ── taps ─────────────────────────────────────────────────────────────────────

/// Tap routing: occupied by an open ticket → summary + settle; otherwise the
/// natives' status picker. (Long-press always opens the status picker.)
fn tap_table(floor: &Arc<Floor>, table_id: String) {
    let has_ticket = floor
        .data
        .lock()
        .unwrap()
        .ticket_for_table(&table_id)
        .is_some();
    if has_ticket {
        open_ticket_sheet(floor, table_id);
    } else {
        open_status_sheet(floor, table_id);
    }
}

fn open_status_sheet(floor: &Arc<Floor>, table_id: String) {
    let label = floor
        .data
        .lock()
        .unwrap()
        .tables
        .iter()
        .find(|t| t.id == table_id)
        .map(|t| t.label.clone())
        .unwrap_or_default();
    on_ui(floor, move |ui, _| {
        let fs = ui.global::<FloorState>();
        fs.set_status_table_id(table_id.into());
        fs.set_status_table_label(label.into());
        fs.set_status_open(true);
    });
}

/// Occupied-table summary — TicketReviewCard data + the Settle CTA.
fn open_ticket_sheet(floor: &Arc<Floor>, table_id: String) {
    let data = floor.data.lock().unwrap();
    let Some(ticket) = data.ticket_for_table(&table_id) else { return };
    let table_label = data
        .tables
        .iter()
        .find(|t| t.id == table_id)
        .map(|t| t.label.clone())
        .unwrap_or_default();
    let currency = floor
        .core
        .current_session()
        .map(|s| s.currency_code)
        .unwrap_or_default();
    let core = &floor.core;
    let ticket_id = ticket.id.clone();
    let ref_label = ticket
        .ticket_ref
        .clone()
        .unwrap_or_else(|| core.tr("waiter.ticket".into()));
    let status_label = core.tr(format!("ticket.status.{}", ticket.status));
    let status_tone = ticket_status_tone(&ticket.status);
    let lines: Vec<FloorTicketLineData> = ticket
        .lines
        .iter()
        .map(|l| FloorTicketLineData {
            text: format!("{}× {}", l.qty, l.name).into(),
            money: money_format(l.line_total_minor, &currency).into(),
            voided: l.voided,
        })
        .collect();
    drop(data);
    on_ui(floor, move |ui, _| {
        let fs = ui.global::<FloorState>();
        fs.set_ticket_id(ticket_id.into());
        fs.set_ticket_table_label(table_label.into());
        fs.set_ticket_ref_label(ref_label.into());
        fs.set_ticket_status_label(status_label.into());
        fs.set_ticket_status_tone(status_tone.into());
        fs.set_ticket_lines(ModelRc::new(VecModel::from(lines)));
        fs.set_ticket_open(true);
    });
}

// ── host ops ─────────────────────────────────────────────────────────────────

/// Set a table's live status (`free` | `held` | `seated` | `dirty`).
fn set_table_status(floor: &Arc<Floor>, table_id: String, status: String) {
    let floor = floor.clone();
    rt().spawn(async move {
        match floor.core.set_floor_table_status(table_id, status).await {
            Ok(_) => reload(&floor),
            Err(e) => raise(&floor, &e),
        }
    });
}

/// Send the booking's nudge (reservation departure / waitlist ready).
fn notify_reservation(floor: &Arc<Floor>, booking_id: String) {
    let floor = floor.clone();
    rt().spawn(async move {
        match floor.core.notify_reservation(booking_id).await {
            Ok(_) => reload(&floor),
            Err(e) => raise(&floor, &e),
        }
    });
}

/// Present the seat sheet — every seat session starts with a clean pick set,
/// set up BEFORE the sheet presents (the Dart `clearSeatPicks` + `_openSeat`).
fn open_seat(floor: &Arc<Floor>, booking_id: String) {
    let title = {
        let mut data = floor.data.lock().unwrap();
        data.seat_picks.clear();
        data.seat_booking_id = Some(booking_id.clone());
        data.reservations
            .iter()
            .find(|b| b.id == booking_id)
            .map(|b| b.customer_name.clone())
            .unwrap_or_default()
    };
    on_ui(floor, move |ui, floor| {
        let fs = ui.global::<FloorState>();
        fs.set_seat_title(title.into());
        render_seat_rows_on(&ui, &floor);
        fs.set_seat_open(true);
    });
}

/// Toggle one table in the seat sheet's pick set.
fn toggle_seat_pick(floor: &Arc<Floor>, table_id: String) {
    {
        let mut data = floor.data.lock().unwrap();
        if let Some(at) = data.seat_picks.iter().position(|id| *id == table_id) {
            data.seat_picks.remove(at);
        } else {
            data.seat_picks.push(table_id);
        }
    }
    on_ui(floor, |ui, floor| render_seat_rows_on(&ui, &floor));
}

/// Seat a party onto the picked tables (multiple ⇒ merged). Opens a dine-in
/// ticket in the core; pops the sheet + toasts on success.
fn confirm_seat(floor: &Arc<Floor>) {
    let (booking_id, picks) = {
        let data = floor.data.lock().unwrap();
        (data.seat_booking_id.clone(), data.seat_picks.clone())
    };
    let Some(booking_id) = booking_id else { return };
    if picks.is_empty() {
        return;
    }
    let floor = floor.clone();
    set_busy(&floor, true);
    rt().spawn(async move {
        let result = floor.core.seat_reservation(booking_id, picks).await;
        match result {
            Ok(_) => {
                reload(&floor);
                show_toast(
                    &floor,
                    floor.core.tr("reservations.seated".into()),
                    "success",
                    true, // icon: checkmark.circle
                );
                on_ui(&floor, |ui, _| ui.global::<FloorState>().set_seat_open(false));
            }
            Err(e) => raise(&floor, &e),
        }
        set_busy(&floor, false);
    });
}

/// SETTLE an occupied table's open ticket into a paid order in the cashier's
/// shift — the natives' AppModel.settleTicket verbatim (shift-guard → core
/// call → reload + toast). The integrator's checkout drawer calls this from
/// its terminal action; `done(ok)` mirrors the Dart Future<bool> so the
/// drawer can pop on success / surface `FloorState.error` inside on failure.
pub fn settle_ticket(
    floor: &Arc<Floor>,
    ticket_id: String,
    payment_method_id: String,
    amount_tendered_minor: Option<i64>,
    tip_minor: Option<i64>,
    tip_payment_method_id: Option<String>,
    done: Box<dyn FnOnce(bool) + Send>,
) {
    let floor = floor.clone();
    rt().spawn(async move {
        // Shift guard — the settle lands in the cashier's open shift.
        let shift_id = floor.core.current_shift().ok().flatten().map(|s| s.id);
        let Some(shift_id) = shift_id else {
            let msg = floor.core.tr("waiter.need_shift".into());
            on_ui(&floor, move |ui, _| ui.global::<FloorState>().set_error(msg.into()));
            done(false);
            return;
        };
        set_busy(&floor, true);
        on_ui(&floor, |ui, _| ui.global::<FloorState>().set_error(SharedString::new()));
        let result = floor
            .core
            .settle_ticket(
                ticket_id,
                shift_id,
                payment_method_id,
                amount_tendered_minor,
                tip_minor,
                tip_payment_method_id,
                None, // discount_id — the floor settle carries no override
                None, // discount_type
                None, // discount_value
            )
            .await;
        let ok = match result {
            Ok(_) => {
                reload(&floor);
                show_toast(&floor, floor.core.tr("waiter.settled".into()), "success", false);
                true
            }
            Err(e) => {
                raise(&floor, &e);
                false
            }
        };
        set_busy(&floor, false);
        done(ok);
    });
}

// ── Wiring: hook every FloorState intent (call once after window build). ────
// `settle-ticket` is NOT hooked here — the integrator wires it to the shared
// checkout settle drawer (see NOTES-floor.md), and `back` belongs to the
// shell's router.

pub fn wire(floor: &Arc<Floor>, ui: &AppWindow) {
    let fs = ui.global::<FloorState>();
    {
        let f = floor.clone();
        fs.on_pick_section(move |id| {
            f.data.lock().unwrap().active_section_id = Some(id.to_string());
            render(&f);
        });
    }
    {
        let f = floor.clone();
        fs.on_tap_table(move |id| tap_table(&f, id.to_string()));
    }
    {
        let f = floor.clone();
        fs.on_long_press_table(move |id| open_status_sheet(&f, id.to_string()));
    }
    {
        let f = floor.clone();
        fs.on_pick_status(move |table_id, status| {
            set_table_status(&f, table_id.to_string(), status.to_string());
        });
    }
    {
        let f = floor.clone();
        fs.on_open_seat(move |booking_id| open_seat(&f, booking_id.to_string()));
    }
    {
        let f = floor.clone();
        fs.on_notify(move |booking_id| notify_reservation(&f, booking_id.to_string()));
    }
    {
        let f = floor.clone();
        fs.on_toggle_seat_pick(move |table_id| toggle_seat_pick(&f, table_id.to_string()));
    }
    {
        let f = floor.clone();
        fs.on_confirm_seat(move || confirm_seat(&f));
    }
    {
        let f = floor.clone();
        fs.on_clear_error(move || {
            on_ui(&f, |ui, _| ui.global::<FloorState>().set_error(SharedString::new()));
        });
    }
    {
        let f = floor.clone();
        fs.on_dismiss_toast(move |id| {
            on_ui(&f, move |ui, _| {
                let fs = ui.global::<FloorState>();
                // Auto-dismiss only clears ITS payload (the Dart dismissToast
                // id guard) — a newer toast keeps showing.
                if fs.get_toast_id() == id {
                    fs.set_toast_shown(false);
                }
            });
        });
    }
    {
        // 15s heartbeat: poll ONLY while realtime is disconnected — when
        // connected, the floor refreshes on the ticket/order ticks instead.
        let f = floor.clone();
        fs.on_poll_tick(move || {
            if !f.connected.load(Ordering::Relaxed) {
                reload(&f);
            }
        });
    }
}

// ── Dev preview (`MADAR_PREVIEW=floor`): sample data so the surface is
// reviewable without a provisioned backend. Never set in production. ────────

pub fn preview(ui: &AppWindow, core: &MadarCore) {
    use madar_core::reservations::{FloorSectionView, FloorTableView, ReservationView};
    apply_floor_strings(ui, core);
    let table = |id: &str, label: &str, seats: i32, shape: &str, status: &str,
                 x: f64, y: f64, w: f64, h: f64| FloorTableView {
        id: id.into(),
        section_id: Some("s1".into()),
        label: label.into(),
        seats,
        shape: shape.into(),
        status: status.into(),
        pos_x: x,
        pos_y: y,
        width: w,
        height: h,
        rotation: 0.0,
    };
    let booking = |id: &str, name: &str, party: i32, status: &str| ReservationView {
        id: id.into(),
        branch_id: "b1".into(),
        kind: "reservation".into(),
        customer_name: name.into(),
        customer_phone: String::new(),
        party_size: party,
        reserved_for: None,
        status: status.into(),
        table_ids: vec![],
        customer_lat: None,
        customer_lng: None,
        notes: None,
    };
    let fs = ui.global::<FloorState>();
    fs.set_branch_name("Downtown Branch".into());
    fs.set_active_section_id("s1".into());
    fs.set_canvas_w(1000.0);
    fs.set_canvas_h(700.0);
    let sections = [
        FloorSectionView { id: "s1".into(), name: "Main Hall".into(), ordering: 0, canvas_w: 1000, canvas_h: 700 },
        FloorSectionView { id: "s2".into(), name: "الشرفة".into(), ordering: 1, canvas_w: 800, canvas_h: 500 },
    ];
    fs.set_sections(ModelRc::new(VecModel::from(
        sections
            .iter()
            .map(|s| FloorSectionData { id: s.id.clone().into(), name: s.name.clone().into() })
            .collect::<Vec<_>>(),
    )));
    let tables = [
        table("t1", "T1", 4, "rect", "free", 60.0, 60.0, 160.0, 120.0),
        table("t2", "T2", 2, "circle", "held", 300.0, 80.0, 110.0, 110.0),
        table("t3", "طاولة ٣", 6, "rect", "seated", 500.0, 60.0, 220.0, 130.0),
        table("t4", "T4", 4, "rect", "dirty", 80.0, 300.0, 160.0, 120.0),
        table("t5", "T5", 8, "rect", "free", 380.0, 320.0, 300.0, 150.0),
    ];
    fs.set_tables(ModelRc::new(VecModel::from(
        tables
            .iter()
            .map(|t| FloorTableData {
                id: t.id.clone().into(),
                label: t.label.clone().into(),
                seats_text: t.seats.to_string().into(),
                circle: t.shape == "circle",
                status: t.status.clone().into(),
                pos_x: t.pos_x as f32,
                pos_y: t.pos_y as f32,
                w: t.width as f32,
                h: t.height as f32,
            })
            .collect::<Vec<_>>(),
    )));
    let bookings = [
        booking("b1", "Nour El-Sayed", 4, "confirmed"),
        booking("b2", "أحمد فؤاد", 2, "waitlist"),
    ];
    fs.set_bookings(ModelRc::new(VecModel::from(
        bookings
            .iter()
            .map(|b| FloorBookingData {
                id: b.id.clone().into(),
                name: b.customer_name.clone().into(),
                meta: format!("{} · {}", b.party_size, b.status).into(),
            })
            .collect::<Vec<_>>(),
    )));
}
