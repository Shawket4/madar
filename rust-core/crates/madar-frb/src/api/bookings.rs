//! Bookings at service time — FRB delegation over `madar_core::MadarCore`
//! plus the booking view mirror. Binding code only.
use flutter_rust_bridge::frb;

use crate::api::bridge::MadarBridge;
use crate::api::error::MadarError;

pub use madar_core::bookings::BookingView;

/// One of today's bookings, as the floor staff see it.
#[frb(mirror(BookingView))]
pub struct _BookingView {
    pub id: String,
    /// `confirmed` | `seated` | `completed` | `no_show` | `cancelled`.
    pub status: String,
    pub party_size: i32,
    /// RFC3339 instants (UTC) — render in the branch zone.
    pub starts_at: String,
    pub ends_at: String,
    /// From here the table reads as reserved.
    pub held_from: String,
    pub guest_name: String,
    pub guest_phone: String,
    pub notes: Option<String>,
    pub table_ids: Vec<String>,
    pub table_labels: Vec<String>,
    /// Active but holding no table — pick one when seating.
    pub needs_table: bool,
    /// `public` | `host`.
    pub source: String,
}

impl MadarBridge {
    /// Pull today's active bookings into the offline cache (best-effort; a
    /// `refresh_floor` does this too).
    pub async fn refresh_arrivals(&self) -> Result<(), MadarError> {
        self.inner
            .refresh_arrivals()
            .await
            .map_err(MadarError::from)
    }

    /// Today's active bookings from the cache, earliest first.
    pub fn list_arrivals(&self) -> Result<Vec<BookingView>, MadarError> {
        self.inner.list_arrivals().map_err(MadarError::from)
    }

    /// The party arrived: mark the booking seated (optionally on another
    /// table). Optimistic-local + queued. Fire their ticket with `booking_id`
    /// to link it.
    pub fn seat_booking(
        &self,
        booking_id: String,
        table_id: Option<String>,
    ) -> Result<(), MadarError> {
        self.inner
            .seat_booking(booking_id, table_id)
            .map_err(MadarError::from)
    }

    /// The party never came: release the table. Optimistic-local + queued.
    pub fn no_show_booking(&self, booking_id: String) -> Result<(), MadarError> {
        self.inner
            .no_show_booking(booking_id)
            .map_err(MadarError::from)
    }
}
