//! Reservations & floor-plan bindings: sections/tables/bookings for the
//! signed-in branch, plus the live host actions (seat, set status, nudge,
//! move ticket). One-line delegation to `madar-core`; view-type mirrors for
//! `reservations.rs` live here.
use flutter_rust_bridge::frb;

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
    /// Floor sections for the signed-in branch (dashboard-authored geometry).
    pub async fn list_floor_sections(&self) -> Result<Vec<FloorSectionView>, MadarError> {
        self.inner
            .list_floor_sections()
            .await
            .map_err(MadarError::from)
    }

    /// Tables (geometry + live status) for the signed-in branch.
    pub async fn list_floor_tables(&self) -> Result<Vec<FloorTableView>, MadarError> {
        self.inner
            .list_floor_tables()
            .await
            .map_err(MadarError::from)
    }

    /// Active bookings (reservations + waitlist) for the signed-in branch.
    pub async fn list_reservations(&self) -> Result<Vec<ReservationView>, MadarError> {
        self.inner
            .list_reservations()
            .await
            .map_err(MadarError::from)
    }

    /// Seat a party onto one or more tables (multiple ⇒ merged tables). The
    /// backend opens a dine-in ticket on the primary table.
    pub async fn seat_reservation(
        &self,
        booking_id: String,
        table_ids: Vec<String>,
    ) -> Result<ReservationView, MadarError> {
        self.inner
            .seat_reservation(booking_id, table_ids)
            .await
            .map_err(MadarError::from)
    }

    /// Set a table's live status (`free` | `held` | `seated` | `dirty`).
    pub async fn set_floor_table_status(
        &self,
        table_id: String,
        status: String,
    ) -> Result<FloorTableView, MadarError> {
        self.inner
            .set_floor_table_status(table_id, status)
            .await
            .map_err(MadarError::from)
    }

    /// Send the booking's nudge (reservation departure / waitlist ready).
    pub async fn notify_reservation(
        &self,
        booking_id: String,
    ) -> Result<ReservationView, MadarError> {
        self.inner
            .notify_reservation(booking_id)
            .await
            .map_err(MadarError::from)
    }

    /// Move an open ticket to another table (the "switch table" action). Frees the
    /// old table, occupies the new one, and keeps the booking assignment in sync.
    pub async fn move_ticket_to_table(
        &self,
        ticket_id: String,
        table_id: String,
    ) -> Result<(), MadarError> {
        self.inner
            .move_ticket_to_table(ticket_id, table_id)
            .await
            .map_err(MadarError::from)
    }
}
