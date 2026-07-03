//! Orders domain — checkout + order history reads/void, delegated to
//! madar-core. Mirrors the order view DTOs (`orders.rs`) and the
//! checkout/receipt DTOs (`checkout.rs`); binding code only.
use flutter_rust_bridge::frb;

use crate::api::bridge::MadarBridge;
use crate::api::error::MadarError;

pub use madar_core::checkout::{
    CheckoutInput, CheckoutSplit, ReceiptComponentView, ReceiptLineView, ReceiptModifierView,
    ReceiptView,
};
pub use madar_core::orders::{
    OrderDetailLineView, OrderDetailView, OrderSearchPage, OrderSummaryView,
};

// ── checkout / receipt DTO mirrors (madar-core/src/checkout.rs) ─────────────

/// A priced modifier on a receipt line (an addon or a chosen optional).
#[frb(mirror(ReceiptModifierView))]
pub struct _ReceiptModifierView {
    pub name: String,
    pub price_minor: i64,
}

/// One component of a bundle line on the receipt, with its own modifiers.
#[frb(mirror(ReceiptComponentView))]
pub struct _ReceiptComponentView {
    pub name: String,
    pub size_label: Option<String>,
    pub addons: Vec<ReceiptModifierView>,
    pub optionals: Vec<ReceiptModifierView>,
}

/// One line on the receipt the host shows after placing an order.
#[frb(mirror(ReceiptLineView))]
pub struct _ReceiptLineView {
    pub name: String,
    pub qty: i64,
    /// Size variant ("(Large)"), printed inline after the name when present.
    pub size_label: Option<String>,
    pub line_total_minor: i64,
    /// A bundle/combo line — its breakdown is in `components`, not `addons`.
    pub is_bundle: bool,
    pub addons: Vec<ReceiptModifierView>,
    pub optionals: Vec<ReceiptModifierView>,
    pub components: Vec<ReceiptComponentView>,
}

/// The order confirmation / receipt summary.
#[frb(mirror(ReceiptView))]
pub struct _ReceiptView {
    /// Client-generated order id (the outbox idempotency key).
    pub local_order_id: String,
    /// Human order number (server-assigned); `None` for a freshly-queued sale.
    pub order_number: Option<i64>,
    /// Cross-channel order reference (e.g. delivery ticket id), printed when set.
    pub order_ref: Option<String>,
    /// `true` when the order is voided — prints a `*** VOIDED ***` stamp.
    pub is_voided: bool,
    pub lines: Vec<ReceiptLineView>,
    /// Localized payment-method label for display.
    pub payment_label: String,
    pub subtotal_minor: i64,
    /// Discount applied before tax (0 when none).
    pub discount_minor: i64,
    pub tax_minor: i64,
    /// Delivery fee (0 for dine-in).
    pub delivery_fee_minor: i64,
    pub total_minor: i64,
    /// Gratuity added on top of the total (0 when none).
    pub tip_minor: i64,
    pub amount_tendered_minor: i64,
    pub change_minor: i64,
    pub is_cash: bool,
    /// Customer name (dine-in pickup or delivery); printed when present.
    pub customer_name: Option<String>,
    /// Teller who rang the sale; printed in the footer when present.
    pub teller_name: Option<String>,
    /// Delivery block — populated only for delivery orders.
    pub is_delivery: bool,
    pub delivery_channel: Option<String>,
    pub customer_phone: Option<String>,
    pub delivery_address: Option<String>,
    pub delivery_zone: Option<String>,
    pub delivery_ref: Option<String>,
    pub payment_hint: Option<String>,
    pub delivery_notes: Option<String>,
    /// `true` while the order is still queued (offline); `false` once sent.
    pub queued_offline: bool,
    pub created_at: String,
}

/// One leg of a split payment (a method + the amount paid on it).
#[frb(mirror(CheckoutSplit))]
pub struct _CheckoutSplit {
    pub payment_method_id: String,
    pub amount_minor: i64,
}

/// Everything the tender screen collects for a checkout.
#[frb(mirror(CheckoutInput))]
pub struct _CheckoutInput {
    /// The (primary) payment method id.
    pub payment_method_id: String,
    /// Cash handed over (for change); 0 / ignored for non-cash.
    pub amount_tendered_minor: i64,
    /// Gratuity on top of the total (0 = none).
    pub tip_minor: i64,
    /// Which method the tip is paid on (defaults to the order method).
    pub tip_payment_method_id: Option<String>,
    pub customer_name: Option<String>,
    pub notes: Option<String>,
    /// Per-method split legs (empty = single payment).
    pub splits: Vec<CheckoutSplit>,
}

// ── order view mirrors (madar-core/src/orders.rs) ───────────────────────────

/// One order row for the history list (+ a totals detail).
#[frb(mirror(OrderSummaryView))]
pub struct _OrderSummaryView {
    /// Server id, or the client order uuid while queued.
    pub id: String,
    /// `None` until the server assigns it (queued orders have no number yet).
    pub order_number: Option<i32>,
    pub subtotal_minor: i64,
    pub tax_minor: i64,
    pub total_minor: i64,
    /// Raw payment-method name as recorded on the order.
    pub payment_label: String,
    /// Server status (`completed`/`voided`/…), or `queued`/`failed` for unsynced.
    pub status: String,
    pub created_at: String,
    /// `true` while the order is still in the outbox (not yet on the server).
    pub queued: bool,
    /// Teller who rang the order; `None` for queued orders.
    pub teller_name: Option<String>,
    /// Order origin: `dine_in` / `delivery` / … — drives the type filter.
    pub order_type: String,
    /// Optional customer name shown as a muted chip in the history row.
    pub customer_name: Option<String>,
    /// Optional human order ref (server-assigned) shown under the order number.
    pub order_ref: Option<String>,
}

/// One line of a fetched order (item + its chosen modifiers).
#[frb(mirror(OrderDetailLineView))]
pub struct _OrderDetailLineView {
    pub name: String,
    pub qty: i64,
    pub size_label: Option<String>,
    pub line_total_minor: i64,
    /// Addon labels ("Oat milk ×2"), already qty-suffixed for display.
    pub addons: Vec<String>,
    /// Optional-field labels.
    pub optionals: Vec<String>,
}

/// A fetched order with its lines — drives the history detail + reprint.
#[frb(mirror(OrderDetailView))]
pub struct _OrderDetailView {
    pub id: String,
    pub order_number: Option<i32>,
    pub status: String,
    pub payment_label: String,
    pub subtotal_minor: i64,
    pub discount_minor: i64,
    pub tax_minor: i64,
    pub total_minor: i64,
    pub created_at: String,
    pub lines: Vec<OrderDetailLineView>,
}

/// A page of all-orders search results (history lookup across shifts).
#[frb(mirror(OrderSearchPage))]
pub struct _OrderSearchPage {
    pub orders: Vec<OrderSummaryView>,
    /// 1-based page just returned.
    pub page: u32,
    /// Total matching orders on the server.
    pub total: u32,
    /// Whether a further page exists.
    pub has_more: bool,
}

// ── delegation ───────────────────────────────────────────────────────────────

impl MadarBridge {
    /// Place the current cart as an order: price it (client-authoritative),
    /// queue an idempotent `create_order` command, clear the cart, and try to
    /// send now. Works offline — the order stays queued and `queued_offline`
    /// is `true` on the receipt until it syncs.
    pub async fn checkout(&self, input: CheckoutInput) -> Result<ReceiptView, MadarError> {
        self.inner.checkout(input).await.map_err(MadarError::from)
    }

    /// The current shift's orders — still-queued sales (offline-safe) plus
    /// the server's synced orders when online (best-effort).
    pub async fn list_shift_orders(&self) -> Result<Vec<OrderSummaryView>, MadarError> {
        self.inner
            .list_shift_orders()
            .await
            .map_err(MadarError::from)
    }

    /// Fetch a synced order's full detail (lines + modifiers) — the expanded
    /// history row. Offline-durable for any order seen online (cached).
    pub async fn order_detail(&self, order_id: String) -> Result<OrderDetailView, MadarError> {
        self.inner
            .order_detail(order_id)
            .await
            .map_err(MadarError::from)
    }

    /// Project a synced order into a ReceiptView (no bytes) — for an on-screen
    /// receipt preview before reprinting. Offline-durable for any order seen online.
    pub async fn order_receipt_view(&self, order_id: String) -> Result<ReceiptView, MadarError> {
        self.inner
            .order_receipt_view(order_id)
            .await
            .map_err(MadarError::from)
    }

    /// A PAST shift's synced orders (history-screen expansion). Live when
    /// online, else the last-synced snapshot.
    pub async fn list_orders_for_shift(
        &self,
        shift_id: String,
    ) -> Result<Vec<OrderSummaryView>, MadarError> {
        self.inner
            .list_orders_for_shift(shift_id)
            .await
            .map_err(MadarError::from)
    }

    /// Search the branch's orders ACROSS shifts (history lookup) with optional
    /// filters (status / teller / payment method / from-to dates) + pagination
    /// (50/page, 1-based). Online-only.
    pub async fn search_orders(
        &self,
        status: Option<String>,
        teller_name: Option<String>,
        payment_method: Option<String>,
        from: Option<String>,
        to: Option<String>,
        page: u32,
    ) -> Result<OrderSearchPage, MadarError> {
        self.inner
            .search_orders(status, teller_name, payment_method, from, to, page)
            .await
            .map_err(MadarError::from)
    }

    /// Void a synced order (mistake/refund). Queues an idempotent `void_order`
    /// command and tries to send now; works offline. History reflects it
    /// immediately via the pending-void overlay.
    pub async fn void_order(
        &self,
        order_id: String,
        reason: String,
        note: Option<String>,
        restore_inventory: bool,
    ) -> Result<(), MadarError> {
        self.inner
            .void_order(order_id, reason, note, restore_inventory)
            .await
            .map_err(MadarError::from)
    }
}
