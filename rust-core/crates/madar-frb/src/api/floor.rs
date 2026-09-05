//! Reservations & floor-plan bindings: sections/tables/bookings for the
//! signed-in branch, plus the live host actions (seat, set status, nudge,
//! move ticket). One-line delegation to `madar-core`; view-type mirrors for
//! `reservations.rs` live here.
use flutter_rust_bridge::frb;

pub use madar_core::held::{
    FloorLayoutView, FloorSectionInfo, FloorTableStateView, TransferQueueView,
};
pub use madar_core::reservations::{FloorSectionView, FloorTableView, ReservationView};

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

/// A booking — reservation (`reserved_for` set) or waitlist entry (none).
#[frb(mirror(ReservationView))]
pub struct _ReservationView {
    pub id: String,
    pub branch_id: String,
    /// `reservation` | `walk_in`.
    pub kind: String,
    pub customer_name: String,
    pub customer_phone: String,
    pub party_size: i32,
    /// RFC-3339 instant, or `None` for a waitlist entry.
    pub reserved_for: Option<String>,
    pub status: String,
    /// Assigned table ids (multiple ⇒ merged tables).
    pub table_ids: Vec<String>,
    pub customer_lat: Option<f64>,
    pub customer_lng: Option<f64>,
    pub notes: Option<String>,
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
