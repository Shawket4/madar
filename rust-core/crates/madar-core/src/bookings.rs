//! Table bookings on the POS: today's arrivals (an offline-readable cache of
//! the branch's active bookings), seating a booked party, and marking a
//! no-show. Both writes are optimistic-local + queued for `/sync/replay`, like
//! every other floor op, so a waiter can seat a party while the cloud is
//! unreachable. The floor mirror carries each table's `next_booking` (see
//! `held.rs`), which is how the canvas shows a table as reserved.

use serde::{Deserialize, Serialize};

use crate::error::CoreResult;
use crate::store::Store;

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

/// kv key for today's active bookings (the arrivals list, readable offline).
pub(crate) const K_ARRIVALS: &str = "cache:bookings:arrivals";

pub(crate) fn load_arrivals(store: &Store) -> CoreResult<Vec<BookingView>> {
    Ok(store
        .kv_get(K_ARRIVALS)?
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default())
}

pub(crate) fn save_arrivals(store: &Store, list: &[BookingView]) -> CoreResult<()> {
    store.kv_put(K_ARRIVALS, &serde_json::to_string(list)?)?;
    Ok(())
}

/// Optimistic status flip in the arrivals cache (the server view lands on the
/// next pull). A terminal status drops the row from "arrivals".
pub(crate) fn set_status_local(store: &Store, booking_id: &str, status: &str) -> CoreResult<()> {
    let mut list = load_arrivals(store)?;
    if let Some(b) = list.iter_mut().find(|b| b.id == booking_id) {
        b.status = status.to_string();
    }
    list.retain(|b| matches!(b.status.as_str(), "confirmed" | "seated"));
    save_arrivals(store, &list)
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

#[cfg(test)]
mod tests {
    use super::*;

    fn b(id: &str, status: &str) -> BookingView {
        BookingView {
            id: id.into(),
            status: status.into(),
            party_size: 2,
            starts_at: "2026-09-10T16:30:00+00:00".into(),
            ends_at: "2026-09-10T18:00:00+00:00".into(),
            held_from: "2026-09-10T16:15:00+00:00".into(),
            guest_name: "A".into(),
            guest_phone: "2010".into(),
            notes: None,
            table_ids: vec![],
            table_labels: vec![],
            needs_table: true,
            source: "host".into(),
        }
    }

    #[test]
    fn local_status_flip_keeps_active_rows_only() {
        let store = Store::open("").unwrap();
        save_arrivals(&store, &[b("1", "confirmed"), b("2", "confirmed")]).unwrap();
        set_status_local(&store, "1", "seated").unwrap();
        set_status_local(&store, "2", "no_show").unwrap();
        let list = load_arrivals(&store).unwrap();
        assert_eq!(list.len(), 1);
        assert_eq!((list[0].id.as_str(), list[0].status.as_str()), ("1", "seated"));
    }
}
