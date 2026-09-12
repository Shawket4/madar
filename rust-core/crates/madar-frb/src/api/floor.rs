//! Reservations & floor-plan bindings: sections/tables/bookings for the
//! signed-in branch, plus the live host actions (seat, set status, nudge,
//! move ticket). One-line delegation to `madar-core`; view-type mirrors for
//! `reservations.rs` live here.
use flutter_rust_bridge::frb;

pub use madar_core::held::{
    FloorLayoutView, FloorSectionInfo, FloorTableStateView, TransferQueueView,
};
pub use madar_core::reservations::{FloorSectionView, FloorTableView};

use crate::api::bridge::MadarBridge;
use crate::api::error::MadarError;

/// A floor area (e.g. Patio, Indoor) with its canvas extent for to-scale render.
#[frb(mirror(FloorSectionView))]
pub struct _FloorSectionView {
    pub id: String,
    pub name: String,
    pub ordering: i32,
    pub canvas_w: i32,
    pub canvas_h: i32,
}

/// A table's geometry + live status, ready to draw on the floor canvas.
#[frb(mirror(FloorTableView))]
pub struct _FloorTableView {
    pub id: String,
    pub section_id: Option<String>,
    pub label: String,
    pub seats: i32,
    /// `rect` | `circle`.
    pub shape: String,
    /// `free` | `held` | `seated` | `dirty`.
    pub status: String,
    pub pos_x: f64,
    pub pos_y: f64,
    pub width: f64,
    pub height: f64,
    pub rotation: f64,
}

impl MadarBridge {
    // ── The floor: offline canvas, occupancy, transfer waitlist ──────────
    //
    // Everything here reads and writes the kv mirrors and the outbox, so it
    // works with no network. There used to be a second, older set of
    // network-BLOCKING calls above doing the same jobs -- read the floor, set a
    // table's status, move a ticket -- with opposite offline semantics. They
    // are gone, along with the booking flow they were built for.

    /// The branch floor (sections + tables + held-order occupancy) from the
    /// offline mirror. EMPTY sections+tables ⇒ the branch has no layout ⇒ hide
    /// every table affordance (the feature gate).
    pub fn floor_layout(&self) -> Result<FloorLayoutView, MadarError> {
        self.inner.floor_layout().map_err(MadarError::from)
    }

    /// Re-pull the layout + held orders + waitlist from the server NOW. Call
    /// on opening a floor surface and on a `floor.*` realtime event (a manager
    /// re-arranged the room in the dashboard, another till seated a party).
    /// Best-effort: offline leaves the mirrors as they are.
    pub async fn refresh_floor(&self) -> Result<(), MadarError> {
        self.inner.refresh_floor().await.map_err(MadarError::from)
    }

    /// Swap whatever sits on two tables (held orders and/or waiter tickets);
    /// one empty side = a move. Offline-safe (queued; the server arbitrates).
    pub fn swap_floor_tables(&self, table_a: String, table_b: String) -> Result<(), MadarError> {
        self.inner
            .swap_tables(table_a, table_b)
            .map_err(MadarError::from)
    }

    /// The transfer waitlist (waiting entries, FIFO, labels resolved).
    pub fn list_transfer_queue(&self) -> Result<Vec<TransferQueueView>, MadarError> {
        self.inner.list_transfer_queue().map_err(MadarError::from)
    }

    /// Queue a party — a held order (`occupant_kind: "held_order"`) or an open
    /// ticket (`"open_ticket"`) — to move to a section or a specific table.
    pub fn create_transfer(
        &self,
        occupant_kind: String,
        occupant_id: String,
        target_section_id: Option<String>,
        target_table_id: Option<String>,
        note: Option<String>,
    ) -> Result<(), MadarError> {
        self.inner
            .create_transfer(
                occupant_kind,
                occupant_id,
                target_section_id,
                target_table_id,
                note,
            )
            .map_err(MadarError::from)
    }

    /// Withdraw a waiting transfer wish.
    pub fn cancel_transfer(&self, id: String) -> Result<(), MadarError> {
        self.inner.cancel_transfer(id).map_err(MadarError::from)
    }

    /// Seat a waiting party on `table_id` (must satisfy its wish and be free).
    pub fn fulfill_transfer(&self, id: String, table_id: String) -> Result<(), MadarError> {
        self.inner
            .fulfill_transfer(id, table_id)
            .map_err(MadarError::from)
    }

    /// Reflect a status the server will derive anyway (dirty after checkout,
    /// free after a void or move) in the local canvas. Queues nothing.
    pub fn mirror_table_status(&self, table_id: String, status: String) -> Result<(), MadarError> {
        self.inner
            .mirror_table_status(table_id, status)
            .map_err(MadarError::from)
    }

    /// Clear a bussed table — the one human act a table's status cannot
    /// derive. Everything else follows from the ticket sitting on it.
    /// Offline-safe: optimistic locally, queued for the server.
    pub fn clear_table(&self, table_id: String) -> Result<(), MadarError> {
        self.inner.clear_table(table_id).map_err(MadarError::from)
    }
    /// SEAT a party: take the table, and nothing else.
    ///
    /// The floor's primary gesture. Takes the table on this device immediately
    /// and on every other one once it drains. It raises no kitchen ticket and
    /// opens no tab — sitting down is not a bill. The party's FIRST ROUND
    /// starts the tab and claims the table they are already at.
    pub async fn seat_table(&self, table_id: String) -> Result<(), MadarError> {
        self.inner
            .seat_table(table_id)
            .await
            .map_err(MadarError::from)
    }

    /// Give a table back without a sale: they left before ordering, or the
    /// wrong table was tapped. Frees it outright — nobody ate, so there is
    /// nothing to bus.
    pub async fn unseat_table(&self, table_id: String) -> Result<(), MadarError> {
        self.inner
            .unseat_table(table_id)
            .await
            .map_err(MadarError::from)
    }
}

/// A floor area (level/zone) for the offline canvas.
#[frb(mirror(FloorSectionInfo))]
pub struct _FloorSectionInfo {
    pub id: String,
    pub name: String,
    pub ordering: i32,
    pub canvas_w: i32,
    pub canvas_h: i32,
}

/// A table on the offline canvas: geometry + last-known status + the held
/// order sitting on it. Open-ticket occupancy is joined by the host (the
/// waiter screen already holds the ticket list).
#[frb(mirror(FloorTableStateView))]
pub struct _FloorTableStateView {
    pub id: String,
    pub section_id: Option<String>,
    pub label: String,
    pub seats: i32,
    /// `rect` | `circle`.
    pub shape: String,
    /// Last-known `free` | `held` | `seated` | `dirty`.
    pub status: String,
    pub pos_x: f64,
    pub pos_y: f64,
    pub width: f64,
    pub height: f64,
    pub rotation: f64,
    pub held_order_id: Option<String>,
    pub held_order_name: Option<String>,
    /// RFC3339 stamp of when the order started — rendered as time-on-table.
    pub held_since: Option<String>,
    pub held_locked_by_other: bool,
    /// The next booking claiming this table today (see `madar_core::held`).
    pub booking_id: Option<String>,
    pub booking_guest: Option<String>,
    pub booking_party: Option<i32>,
    pub booking_starts_at: Option<String>,
    pub booking_held_from: Option<String>,
    pub booking_status: Option<String>,
}

/// The whole branch layout + occupancy, offline.
#[frb(mirror(FloorLayoutView))]
pub struct _FloorLayoutView {
    pub sections: Vec<FloorSectionInfo>,
    pub tables: Vec<FloorTableStateView>,
}

/// One entry of the transfer waitlist, display-ready.
#[frb(mirror(TransferQueueView))]
pub struct _TransferQueueView {
    pub id: String,
    /// `held_order` | `open_ticket`.
    pub occupant_kind: String,
    pub occupant_id: String,
    pub occupant_label: Option<String>,
    pub from_table_id: Option<String>,
    pub from_table_label: Option<String>,
    pub target_section_id: Option<String>,
    pub target_section_name: Option<String>,
    pub target_table_id: Option<String>,
    pub target_table_label: Option<String>,
    pub note: Option<String>,
    /// `waiting` | `fulfilled` | `cancelled`.
    pub status: String,
    pub created_at: String,
}

/// One sitting at a table: the bill opened on it and what it came to.
///
/// A plain FRB struct rather than a mirror of the generated API model — the
/// wire type carries `chrono` instants and optionals FRB cannot cross, and a
/// host wants strings it can format in the branch's own zone anyway.
pub struct TableSittingView {
    pub ticket_id: String,
    pub ticket_ref: Option<String>,
    /// RFC3339. The closest the server has to when the party sat down.
    pub opened_at: String,
    /// RFC3339; `None` while the bill is still open.
    pub closed_at: Option<String>,
    pub minutes: i64,
    /// `open` | `settled` | `voided`.
    pub status: String,
    pub customer_name: Option<String>,
    pub guest_count: Option<i32>,
    pub order_ref: Option<String>,
    /// Minor units. `None` for a bill that took no money.
    pub total_minor: Option<i64>,
}

/// What a table has done over the window, and what it earns.
pub struct TableHistoryView {
    pub table_id: String,
    pub label: String,
    /// Newest first.
    pub sittings: Vec<TableSittingView>,
    pub covers: i64,
    pub settled_count: i64,
    pub total_minor: i64,
    pub average_bill_minor: i64,
    pub average_minutes: i64,
    /// Settled bills per day, ×100 so the wire stays integer.
    pub turns_per_day_x100: i64,
}

impl MadarBridge {
    /// A table's history and takings — ONLINE ONLY, never mirrored.
    ///
    /// Every other floor read is cached because a till has to keep selling
    /// with the network down. This one is a manager's question between
    /// services, and a stale copy would quietly answer a question about money
    /// with last week's numbers.
    pub async fn table_history(&self, table_id: String) -> Result<TableHistoryView, MadarError> {
        let h = self
            .inner
            .table_history(table_id)
            .await
            .map_err(MadarError::from)?;
        Ok(TableHistoryView {
            table_id: h.table_id.to_string(),
            label: h.label,
            covers: h.covers,
            settled_count: h.settled_count,
            total_minor: h.total_minor,
            average_bill_minor: h.average_bill_minor,
            average_minutes: h.average_minutes,
            turns_per_day_x100: h.turns_per_day_x100,
            sittings: h
                .sittings
                .into_iter()
                .map(|s| TableSittingView {
                    ticket_id: s.open_ticket_id.to_string(),
                    ticket_ref: s.ticket_ref.flatten(),
                    opened_at: s.opened_at.to_rfc3339(),
                    closed_at: s.closed_at.flatten().map(|d| d.to_rfc3339()),
                    minutes: s.minutes,
                    status: s.status,
                    customer_name: s.customer_name.flatten(),
                    guest_count: s.guest_count.flatten(),
                    order_ref: s.order_number.flatten().map(|n| n.to_string()),
                    total_minor: s.total_amount.flatten().map(i64::from),
                })
                .collect(),
        })
    }
}
