//! Table bookings on the POS: today's arrivals (an offline-readable cache of
//! the branch's active bookings), seating a booked party, and marking a
//! no-show. Both writes are optimistic-local + queued for `/sync/replay`, like
//! every other floor op, so a waiter can seat a party while the cloud is
//! unreachable. The floor mirror carries each table's `next_booking` (see
//! `held.rs`), which is how the canvas shows a table as reserved.

use serde::{Deserialize, Serialize};


/// One booking as the floor staff see it.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct BookingView {
    pub id: String,
    /// `confirmed` | `seated` | `completed` | `no_show` | `cancelled`.
    pub status: String,
    pub party_size: i32,
    /// RFC3339 instants (UTC); the host renders them in the branch zone.
    pub starts_at: String,
    pub ends_at: String,
    /// From here the table reads as reserved.
    pub held_from: String,
    pub guest_name: String,
    pub guest_phone: String,
    pub notes: Option<String>,
    pub table_ids: Vec<String>,
    pub table_labels: Vec<String>,
    /// Active but holding no table — the host must pick one when seating.
    pub needs_table: bool,
    /// `public` (booked online) | `host`.
    pub source: String,
}

impl From<madar_api::models::BookingView> for BookingView {
    fn from(b: madar_api::models::BookingView) -> Self {
        Self {
            id: b.id.to_string(),
            status: b.status,
            party_size: b.party_size,
            starts_at: b.starts_at.to_rfc3339(),
            ends_at: b.ends_at.to_rfc3339(),
            held_from: b.held_from.to_rfc3339(),
            guest_name: b.guest_name,
            guest_phone: b.guest_phone,
            notes: b.notes.flatten(),
            table_ids: b.table_ids.into_iter().map(|u| u.to_string()).collect(),
            table_labels: b.table_labels,
            needs_table: b.needs_table,
            source: b.source,
        }
    }
}


/// Outbox payloads (the `/sync/replay` bodies minus the actor, which the drain adds).
#[derive(Serialize, Deserialize, Clone, Debug)]
pub(crate) struct SeatBookingCommand {
    pub booking_id: String,
    pub request: serde_json::Value,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub(crate) struct NoShowBookingCommand {
    pub booking_id: String,
}
