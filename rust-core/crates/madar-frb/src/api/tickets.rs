//! Waiter open tickets (fire-now-pay-later) — FRB delegation over
//! `madar_core::MadarCore` plus the ticket view mirrors. Binding code only.
use flutter_rust_bridge::frb;

use crate::api::bridge::MadarBridge;
use crate::api::error::MadarError;

pub use madar_core::tickets::{TicketBillView, TicketFiredView, TicketLineView, TicketView};

/// The slim "sent to kitchen" confirmation after a fire/round — deliberately NOT
/// a money-laden receipt (a fired ticket has no payment yet). `queued_offline` is
/// true when the fire is still in the outbox (no network) — the UI shows "queued".
#[frb(mirror(TicketFiredView))]
pub struct _TicketFiredView {
    /// The client ticket id (idempotency key) — stable across the offline→online
    /// transition, so the UI can track the ticket before the server view arrives.
    pub ticket_id: String,
    /// The server-minted human ref (`T-…`), once known (None while queued offline).
    pub ticket_ref: Option<String>,
    pub queued_offline: bool,
}

/// An open ticket for the waiter list / detail screens.
#[frb(mirror(TicketView))]
pub struct _TicketView {
    pub id: String,
    pub ticket_ref: Option<String>,
    pub table_id: Option<String>,
    /// open | ready | settled | voided | queued (the last = still in the outbox).
    pub status: String,
    pub customer_name: Option<String>,
    /// The WAITER who opened this ticket (`open_tickets.opened_by` → user name),
    /// so the teller can see who took the table. `null` if the name is unknown.
    pub waiter_name: Option<String>,
    pub guest_count: Option<i32>,
    /// The lines before discount — the bill's first line, not the bill.
    pub subtotal_minor: i64,
    /// What the drawer must collect, priced by the server. `None` only for a
    /// fire still in the outbox, which nothing has priced yet.
    pub bill: Option<TicketBillView>,
    pub order_id: Option<String>,
    pub opened_at: String,
    pub queued_offline: bool,
    pub lines: Vec<TicketLineView>,
}

/// The bill as the server prices it — the figure the drawer collects, because
/// it is the figure the settle books.
#[frb(mirror(TicketBillView))]
pub struct _TicketBillView {
    pub subtotal_minor: i64,
    /// The waiter's discount, resolved. A cashier clearing it at settle will
    /// see a different total, which is why it is shown.
    pub discount_minor: i64,
    pub service_charge_minor: i64,
    /// Inside the total when `tax_inclusive`, on top of it otherwise.
    pub tax_minor: i64,
    pub total_minor: i64,
    pub tax_rate: f64,
    pub service_charge_rate: f64,
    pub tax_inclusive: bool,
}

/// One bill line (display projection of the frozen `StoredTicketLine`).
#[frb(mirror(TicketLineView))]
pub struct _TicketLineView {
    /// `open_ticket_items.id` — what a reward names to cover this line. Empty
    /// for a line that has not synced, which cannot be redeemed against.
    pub id: String,
    /// Which menu item this is, for matching against the reward catalogue.
    pub menu_item_id: Option<String>,
    pub name: String,
    pub qty: i32,
    pub size_label: Option<String>,
    pub modifiers: Vec<String>,
    pub line_total_minor: i64,
    pub voided: bool,
    /// Which visit to the table this line arrived on, and when (RFC3339).
    pub round_number: i32,
    pub round_fired_at: String,
}

impl MadarBridge {
    // ── waiter open tickets (fire-now-pay-later via the outbox) ───────────

    /// FIRE the current cart as a new dine-in open ticket (round 1). Prices the
    /// cart client-authoritatively (same engine as checkout), enqueues the durable
    /// fire op (offline-first), clears the cart, and best-effort drains. Returns a
    /// slim "sent to kitchen" confirmation — NOT a money receipt. The branch must
    /// be operating (the server enforces an open till at fire time).
    pub async fn fire_ticket(
        &self,
        table_id: Option<String>,
        customer_name: Option<String>,
        notes: Option<String>,
        guest_count: Option<i32>,
        booking_id: Option<String>,
    ) -> Result<TicketFiredView, MadarError> {
        self.inner
            .fire_ticket(table_id, customer_name, notes, guest_count, booking_id)
            .await
            .map_err(MadarError::from)
    }

    /// Add a ROUND of the current cart to an existing open ticket. Same offline-first
    /// path as `fire_ticket`; gated behind the original fire if it hasn't synced.
    pub async fn add_ticket_round(&self, ticket_id: String) -> Result<TicketFiredView, MadarError> {
        self.inner
            .add_ticket_round(ticket_id)
            .await
            .map_err(MadarError::from)
    }

    /// VOID an open ticket (and pull its kitchen tickets off the KDS). Offline-first.
    pub async fn void_ticket(
        &self,
        ticket_id: String,
        reason: Option<String>,
    ) -> Result<bool, MadarError> {
        self.inner
            .void_ticket(ticket_id, reason)
            .await
            .map_err(MadarError::from)
    }

    /// SETTLE an open ticket into a paid order in the cashier's shift (a till
    /// action). Offline-first: the order is materialized server-side at replay,
    /// deduped on the ticket id. Returns true when still queued (offline). The
    /// cashier's settle-time discount/tip override the ticket's own.
    #[allow(clippy::too_many_arguments)]
    /// Settle a ticket into a paid order. Returns the ORDER ID once the settle
    /// has acked, so the caller can fetch its receipt and print — `None` while
    /// it is still queued offline, where no order exists yet.
    pub async fn settle_ticket(
        &self,
        ticket_id: String,
        shift_id: String,
        payment_method_id: String,
        amount_tendered_minor: Option<i64>,
        tip_minor: Option<i64>,
        tip_payment_method_id: Option<String>,
        discount_id: Option<String>,
        discount_type: Option<String>,
        discount_value: Option<f64>,
        // `loyalty_customer_id` is the member spending a balance on this bill;
        // `loyalty_redemptions` names which of the ticket's LINES their rewards
        // cover — by line id, never by position (see
        // `CheckoutRedemption::ticket_line_id`).
        loyalty_customer_id: Option<String>,
        loyalty_redemptions: Vec<crate::api::orders::CheckoutRedemption>,
    ) -> Result<Option<String>, MadarError> {
        self.inner
            .settle_ticket(
                ticket_id,
                shift_id,
                payment_method_id,
                amount_tendered_minor,
                tip_minor,
                tip_payment_method_id,
                discount_id,
                discount_type,
                discount_value,
                loyalty_customer_id,
                loyalty_redemptions,
            )
            .await
            .map_err(MadarError::from)
    }

    /// The branch's OPEN/READY open tickets (newest first). Server list (write-through
    /// cached, so it survives offline) PLUS any still-queued local fires overlaid as
    /// `status = "queued"` — offline-first visibility before the fire syncs.
    pub async fn list_open_tickets(&self) -> Result<Vec<TicketView>, MadarError> {
        self.inner
            .list_open_tickets()
            .await
            .map_err(MadarError::from)
    }

    /// One open ticket by server id (the detail screen). Online; a queued (unsynced)
    /// ticket has no server id yet — read it from `list_open_tickets` instead.
    pub async fn get_ticket(&self, ticket_id: String) -> Result<TicketView, MadarError> {
        self.inner
            .get_ticket(ticket_id)
            .await
            .map_err(MadarError::from)
    }
}
