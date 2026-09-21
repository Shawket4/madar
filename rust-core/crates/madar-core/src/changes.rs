//! Local table-change notifications (OFFLINE_B_DESIGN §6).
//!
//! Every write that changes what a screen reads names the LOGICAL tables it
//! touched; after the transaction commits the store broadcasts them. The host
//! subscribes once (`MadarCore::watch_tables`, an FRB `StreamSink`) and re-runs
//! the matching local read — Dart never polls the core for data and never
//! decides what a change means.
//!
//! Notifications are hints, not a journal: a subscriber that falls behind gets
//! [`ALL`] (re-read everything) instead of a replay, and a crash loses nothing
//! because every screen reads fresh on start. That is why there is no
//! `change_log_local` table (decision log, OFFLINE_B_DESIGN "Implementation
//! status").

use std::collections::BTreeSet;
use std::time::Duration;

use tokio::sync::broadcast;

/// A till's sessions (open/close, verification, flags).
pub const TILLS: &str = "tills";
/// Sales on any till (incl. voids and payment legs).
pub const ORDERS: &str = "orders";
/// Drawer pay-ins / pay-outs / safe drops / corrections.
pub const CASH_MOVEMENTS: &str = "cash_movements";
/// Money handed back.
pub const REFUNDS: &str = "refunds";
/// Open bills (tickets, rounds, line voids).
pub const OPEN_TICKETS: &str = "open_tickets";
/// Kitchen tickets and bumps.
pub const KITCHEN: &str = "kitchen";
/// The delivery queue.
pub const DELIVERY: &str = "delivery";
/// Bookings / arrivals.
pub const BOOKINGS: &str = "bookings";
/// Floor sections, tables, occupancies, transfers.
pub const FLOOR: &str = "floor";
/// Menu, categories, addons, bundles, discounts, settings.
pub const CATALOG: &str = "catalog";
/// Payment methods and their availability.
pub const PAYMENT_METHODS: &str = "payment_methods";
/// The outbox (queued / failed counts, the sync center).
pub const OUTBOX: &str = "outbox";
/// Sync health (cursor, phase, freshness).
pub const SYNC: &str = "sync";
/// Everything — a lagging subscriber re-reads every board.
pub const ALL: &str = "*";

/// Every logical table name a subscriber may see (besides [`ALL`]).
pub const TABLES: &[&str] = &[
    TILLS, ORDERS, CASH_MOVEMENTS, REFUNDS, OPEN_TICKETS, KITCHEN, DELIVERY, BOOKINGS, FLOOR, CATALOG,
    PAYMENT_METHODS, OUTBOX, SYNC,
];

/// The logical table a changefeed wire type lands in.
pub fn table_for_sync_type(ty: &str) -> &'static str {
    match ty {
        "till" => TILLS,
        "order" => ORDERS,
        "cash_movement" => CASH_MOVEMENTS,
        "refund" => REFUNDS,
        "open_ticket" => OPEN_TICKETS,
        "kitchen_ticket" => KITCHEN,
        "delivery" => DELIVERY,
        "booking" => BOOKINGS,
        "staff_drink" => ORDERS,
        "floor_section" | "floor_table" | "table_occupancy" | "table_transfer" => FLOOR,
        "payment_method" | "payment_availability" => PAYMENT_METHODS,
        _ => CATALOG,
    }
}

/// The logical tables an outbox op changes locally when it is queued, acked or
/// dead-lettered (the outbox itself is always one of them).
pub fn tables_for_op(op_type: &str) -> Vec<&'static str> {
    let mut t = vec![OUTBOX];
    t.extend_from_slice(match op_type {
        "open_till" | "open_shift" | "close_till" | "close_shift" => &[TILLS][..],
        "create_order" | "void_order" => &[ORDERS, TILLS][..],
        "refund_order" => &[REFUNDS, ORDERS, TILLS][..],
        "cash_movement" => &[CASH_MOVEMENTS, TILLS][..],
        "spot_report_view" => &[TILLS][..],
        // The pool count lives on the order screen, beside the cart it is spent from.
        "record_staff_drink" => &[ORDERS][..],
        // The history row and the sale's detail show who it is for.
        "attach_customer" => &[ORDERS][..],
        // The bill's header and the bills list show who it is for.
        "set_ticket_customer" => &[OPEN_TICKETS][..],
        "settle_open_ticket" => &[OPEN_TICKETS, ORDERS, TILLS, FLOOR][..],
        "open_ticket" | "ticket_add_round" | "void_ticket" | "void_ticket_line" => {
            &[OPEN_TICKETS, FLOOR, KITCHEN][..]
        }
        "bump_kitchen" | "unbump_kitchen" => &[KITCHEN][..],
        "seat_booking" | "no_show_booking" => &[BOOKINGS, FLOOR][..],
        "swap_tables" | "create_table_transfer" | "cancel_table_transfer" | "fulfill_table_transfer"
        | "clear_table" | "hold_table" | "release_table" => &[FLOOR][..],
        // A LAN peer's op mirrored here: its bills and kitchen work overlay the boards.
        "lan_mirror" => &[OPEN_TICKETS, KITCHEN, FLOOR, ORDERS, TILLS, CASH_MOVEMENTS, REFUNDS][..],
        _ => &[][..],
    });
    t
}

/// The logical tables a realtime event announces a change to. The board
/// re-reads at once (a board still on its legacy read fetches then); the pull
/// the same event nudges brings the rows and announces them again.
pub fn tables_for_event(event_type: &str) -> Vec<&'static str> {
    if event_type == "resync" {
        return vec![ALL];
    }
    let mut t = Vec::new();
    let has = |p: &str| event_type.starts_with(p);
    if has("kitchen.") {
        t.push(KITCHEN);
    }
    if has("ticket.") {
        t.extend([OPEN_TICKETS, TILLS]);
    }
    if has("delivery.") {
        t.push(DELIVERY);
    }
    if has("order.") {
        t.extend([DELIVERY, ORDERS, TILLS]);
    }
    if has("till.") {
        t.push(TILLS);
    }
    if has("sync.") {
        t.push(SYNC);
    }
    if has("payment_methods.") {
        t.extend([PAYMENT_METHODS, CATALOG]);
    }
    if has("floor.") || has("table.") || has("transfer.") {
        t.push(FLOOR);
    }
    if has("booking.") {
        t.extend([FLOOR, BOOKINGS]);
    }
    t
}

/// The broadcast half kept by the [`crate::store::Store`].
#[derive(Clone)]
pub struct TableChanges {
    tx: broadcast::Sender<Vec<String>>,
}

impl Default for TableChanges {
    fn default() -> Self {
        Self::new()
    }
}

impl TableChanges {
    pub fn new() -> Self {
        // A few hundred pending notifications is far more than any UI frame can
        // fall behind by; past it the subscriber is told to re-read everything.
        let (tx, _) = broadcast::channel(512);
        Self { tx }
    }

    /// Announce that `tables` changed (a no-op with no subscriber).
    pub fn emit<'a>(&self, tables: impl IntoIterator<Item = &'a str>) {
        let set: BTreeSet<String> = tables.into_iter().map(str::to_string).collect();
        if set.is_empty() || self.tx.receiver_count() == 0 {
            return;
        }
        let _ = self.tx.send(set.into_iter().collect());
    }

    pub fn subscribe(&self) -> TableChangeSubscription {
        TableChangeSubscription {
            rx: self.tx.subscribe(),
        }
    }
}

/// One subscriber's view of the change stream.
pub struct TableChangeSubscription {
    rx: broadcast::Receiver<Vec<String>>,
}

impl TableChangeSubscription {
    /// The next batch of changed tables, coalesced over `window`: everything that
    /// arrives inside the window after the first change is merged into one set, so
    /// a 500-row pull page is one refresh, not 500. `None` once the store is gone.
    pub async fn next(&mut self, window: Duration) -> Option<Vec<String>> {
        let mut set: BTreeSet<String> = BTreeSet::new();
        match self.rx.recv().await {
            Ok(t) => set.extend(t),
            Err(broadcast::error::RecvError::Lagged(_)) => {
                set.insert(ALL.to_string());
            }
            Err(broadcast::error::RecvError::Closed) => return None,
        }
        if !window.is_zero() {
            tokio::time::sleep(window).await;
        }
        loop {
            match self.rx.try_recv() {
                Ok(t) => set.extend(t),
                Err(broadcast::error::TryRecvError::Lagged(_)) => {
                    set.insert(ALL.to_string());
                }
                Err(_) => break,
            }
        }
        if set.contains(ALL) {
            return Some(vec![ALL.to_string()]);
        }
        Some(set.into_iter().collect())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn changes_coalesce_inside_the_window() {
        let c = TableChanges::new();
        let mut sub = c.subscribe();
        c.emit([ORDERS]);
        c.emit([TILLS, ORDERS]);
        c.emit([OUTBOX]);
        let got = sub.next(Duration::from_millis(10)).await.unwrap();
        assert_eq!(got, vec![ORDERS.to_string(), OUTBOX.to_string(), TILLS.to_string()]);
    }

    #[tokio::test]
    async fn a_lagging_subscriber_is_told_to_reread_everything() {
        let c = TableChanges::new();
        let mut sub = c.subscribe();
        for _ in 0..600 {
            c.emit([ORDERS]);
        }
        assert_eq!(sub.next(Duration::ZERO).await.unwrap(), vec![ALL.to_string()]);
    }

    #[test]
    fn emitting_without_subscribers_is_free_and_silent() {
        let c = TableChanges::new();
        c.emit([ORDERS]);
        c.emit(Vec::<&str>::new());
    }

    #[test]
    fn every_sync_type_maps_to_a_known_table() {
        for ty in crate::sync_pull::ALL_TYPES {
            assert!(TABLES.contains(&table_for_sync_type(ty)), "{ty}");
        }
    }

    #[test]
    fn realtime_events_name_the_boards_they_move() {
        assert_eq!(tables_for_event("resync"), vec![ALL]);
        assert!(tables_for_event("ticket.fired").contains(&OPEN_TICKETS));
        assert!(tables_for_event("order.created").contains(&TILLS));
        assert!(tables_for_event("booking.arriving").contains(&BOOKINGS));
        assert!(tables_for_event("payment_methods.availability_changed").contains(&PAYMENT_METHODS));
        assert!(tables_for_event("unknown.thing").is_empty());
    }

    #[test]
    fn money_ops_touch_the_till() {
        for op in ["create_order", "void_order", "refund_order", "cash_movement", "settle_open_ticket"] {
            assert!(tables_for_op(op).contains(&TILLS), "{op}");
            assert!(tables_for_op(op).contains(&OUTBOX), "{op}");
        }
    }
}
