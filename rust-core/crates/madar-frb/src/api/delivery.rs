//! Delivery domain — the teller's side of the delivery stack: list/work the
//! branch's delivery queue (advance status, prep time, cancel, finalize into a
//! real sale) plus the branch delivery settings and accepting overrides.
//! Binding only: every method is a one-line delegation into madar-core.
use crate::api::bridge::MadarBridge;
use crate::api::error::MadarError;
use crate::api::tickets::TicketLineView;
use flutter_rust_bridge::frb;

pub use madar_core::delivery::{DeliveryFinalizeView, DeliveryOrderView, DeliverySettingsView};

/// One delivery order, projected for the queue list + detail. Money is minor
/// units; `channel`/`status` are wire strings the host localizes.
#[frb(mirror(DeliveryOrderView))]
pub struct _DeliveryOrderView {
    pub id: String,
    pub order_ref: Option<String>,
    /// "in_mall" | "outside".
    pub channel: String,
    /// received | confirmed | preparing | ready | out_for_delivery | delivered |
    /// cancelled | rejected.
    pub status: String,
    pub customer_name: String,
    pub customer_phone: String,
    /// One-line composed address (place, line, unit, floor, landmark).
    pub address: Option<String>,
    pub delivery_notes: Option<String>,
    pub payment_hint: Option<String>,
    pub subtotal_minor: i64,
    pub discount_minor: i64,
    pub delivery_fee_minor: i64,
    pub total_minor: i64,
    pub item_count: i64,
    /// The order's actual priced lines, projected from the frozen `cart.lines`
    /// snapshot into the SAME shape tickets use — so both render identically.
    pub lines: Vec<TicketLineView>,
    pub created_at: String,
    /// `true` once the order reached a terminal state (delivered/cancelled/rejected).
    pub is_terminal: bool,
}

/// The branch's delivery configuration + the POS-owned accepting overrides.
#[frb(mirror(DeliverySettingsView))]
pub struct _DeliverySettingsView {
    pub in_mall_enabled: bool,
    /// "auto" | "open" | "closed".
    pub in_mall_override: String,
    pub in_mall_fee_minor: i64,
    pub outside_enabled: bool,
    pub outside_override: String,
    pub prep_time_minutes: i64,
}

/// Result of finalizing a delivery order into a real sale.
#[frb(mirror(DeliveryFinalizeView))]
pub struct _DeliveryFinalizeView {
    pub order_id: String,
    pub order_ref: Option<String>,
    pub warnings: Vec<String>,
}

impl MadarBridge {
    /// The branch's delivery queue (newest first). `status` is a comma-separated
    /// wire filter (e.g. "received,confirmed"); `None` = all. Online-only.
    pub async fn list_delivery_orders(
        &self,
        status: Option<String>,
    ) -> Result<Vec<DeliveryOrderView>, MadarError> {
        self.inner
            .list_delivery_orders(status)
            .await
            .map_err(MadarError::from)
    }

    /// A single delivery order by id.
    pub async fn delivery_order_detail(&self, id: String) -> Result<DeliveryOrderView, MadarError> {
        self.inner
            .delivery_order_detail(id)
            .await
            .map_err(MadarError::from)
    }

    /// Set a delivery order's status to an explicit wire value.
    pub async fn delivery_set_status(
        &self,
        id: String,
        status: String,
    ) -> Result<DeliveryOrderView, MadarError> {
        self.inner
            .delivery_set_status(id, status)
            .await
            .map_err(MadarError::from)
    }

    /// Advance one step in the lifecycle from `current` (received→confirmed→…→
    /// delivered). Errors if there's no further forward step.
    pub async fn delivery_advance_status(
        &self,
        id: String,
        current: String,
    ) -> Result<DeliveryOrderView, MadarError> {
        self.inner
            .delivery_advance_status(id, current)
            .await
            .map_err(MadarError::from)
    }

    /// Set the per-order extra prep time (non-negative multiple of 5 minutes).
    pub async fn delivery_set_prep_time(
        &self,
        id: String,
        extra_minutes: i32,
    ) -> Result<DeliveryOrderView, MadarError> {
        self.inner
            .delivery_set_prep_time(id, extra_minutes)
            .await
            .map_err(MadarError::from)
    }

    /// Cancel a delivery order. `restore_inventory = false` means the food was
    /// made and is wasted (the frozen plan is deducted + logged as waste).
    pub async fn delivery_cancel(
        &self,
        id: String,
        reason: Option<String>,
        restore_inventory: bool,
    ) -> Result<DeliveryOrderView, MadarError> {
        self.inner
            .delivery_cancel(id, reason, restore_inventory)
            .await
            .map_err(MadarError::from)
    }

    /// Finalize a delivery order into a real completed sale on the current open
    /// shift — replays the frozen snapshot. `payment_method_id` resolves to the
    /// raw wire method. Returns the new order id/ref + any oversold warnings.
    pub async fn delivery_finalize(
        &self,
        id: String,
        payment_method_id: String,
    ) -> Result<DeliveryFinalizeView, MadarError> {
        self.inner
            .delivery_finalize(id, payment_method_id)
            .await
            .map_err(MadarError::from)
    }

    /// The branch's delivery settings + accepting overrides.
    pub async fn delivery_settings(&self) -> Result<DeliverySettingsView, MadarError> {
        self.inner
            .delivery_settings()
            .await
            .map_err(MadarError::from)
    }

    /// Set a channel's accepting override. `channel` = "in_mall"/"outside",
    /// `mode` = "auto"/"open"/"closed". 409 if opening a dashboard-disabled channel.
    pub async fn delivery_set_accepting(
        &self,
        channel: String,
        mode: String,
    ) -> Result<DeliverySettingsView, MadarError> {
        self.inner
            .delivery_set_accepting(channel, mode)
            .await
            .map_err(MadarError::from)
    }
}
