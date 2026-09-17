//! Manager approval on the till (phase 5). Pure delegation to madar-core;
//! owns the `ActDecisionView` and `ApprovalView` mirrors.
use flutter_rust_bridge::frb;

use crate::api::bridge::MadarBridge;
use crate::api::error::MadarError;

pub use madar_core::approvals::{ActDecisionView, ApprovalView};

/// What the till may do about an act right now.
#[frb(mirror(ActDecisionView))]
pub struct _ActDecisionView {
    pub outcome: String,
    pub reason: String,
}

/// A manager's approval, to pass to the act it was asked for.
#[frb(mirror(ApprovalView))]
pub struct _ApprovalView {
    pub id: String,
    pub capability: String,
    pub approver_id: String,
    pub approver_name: String,
    pub amount_minor: Option<i64>,
    pub value_minor: Option<i64>,
    pub percent_bps: Option<i64>,
}

pub use madar_core::discounts::CartDiscountView;

/// The cart's discount as the tender screen shows it.
#[frb(mirror(CartDiscountView))]
pub struct _CartDiscountView {
    pub kind: String,
    pub preset_id: Option<String>,
    pub amount_minor: Option<i64>,
    pub percent_bps: Option<i64>,
    pub off_minor: i64,
    pub approved_by_name: Option<String>,
}

impl MadarBridge {
    /// Allowed / needs a manager / refused for a discount on the cart
    /// (`kind`: preset | manual_amount | manual_percent). Offline.
    #[frb(sync)]
    pub fn decide_discount(
        &self,
        table_id: Option<String>,
        kind: String,
        preset_id: Option<String>,
        amount_minor: Option<i64>,
        percent_bps: Option<i64>,
    ) -> ActDecisionView {
        self.inner
            .decide_discount(table_id, kind, preset_id, amount_minor, percent_bps)
    }

    /// A manager approves a discount on the cart with their PIN.
    pub fn approve_discount(
        &self,
        approver_pin: String,
        table_id: Option<String>,
        kind: String,
        preset_id: Option<String>,
        amount_minor: Option<i64>,
        percent_bps: Option<i64>,
    ) -> Result<ApprovalView, MadarError> {
        self.inner
            .approve_discount(approver_pin, table_id, kind, preset_id, amount_minor, percent_bps)
            .map_err(MadarError::from)
    }

    /// Put a discount on the cart; refused unless allowed or approved.
    pub fn apply_discount(
        &self,
        table_id: Option<String>,
        kind: String,
        preset_id: Option<String>,
        amount_minor: Option<i64>,
        percent_bps: Option<i64>,
        approval: Option<ApprovalView>,
    ) -> Result<(), MadarError> {
        self.inner
            .apply_discount(table_id, kind, preset_id, amount_minor, percent_bps, approval)
            .map_err(MadarError::from)
    }

    /// The cart's discount: kind, figures, what it takes off, who approved.
    pub fn cart_discount(&self, table_id: Option<String>) -> Result<CartDiscountView, MadarError> {
        self.inner.cart_discount(table_id).map_err(MadarError::from)
    }

    /// Allowed, needs a manager, or refused — for the signed-in person, offline.
    #[frb(sync)]
    pub fn decide_act(
        &self,
        cap_key: String,
        amount_minor: Option<i64>,
        age_minutes: Option<i64>,
        own: Option<bool>,
    ) -> ActDecisionView {
        self.inner.decide_act(cap_key, amount_minor, age_minutes, own)
    }

    /// A manager approves the act with their own PIN on this device.
    pub fn approve_act(
        &self,
        approver_pin: String,
        cap_key: String,
        amount_minor: Option<i64>,
        age_minutes: Option<i64>,
        own: Option<bool>,
    ) -> Result<ApprovalView, MadarError> {
        self.inner
            .approve_act(approver_pin, cap_key, amount_minor, age_minutes, own)
            .map_err(MadarError::from)
    }

    /// Allowed / needs a manager / refused for an act on one sale (whose sale
    /// and how old come from the core's ledger).
    #[frb(sync)]
    pub fn decide_order_act(
        &self,
        cap_key: String,
        order_id: String,
        amount_minor: Option<i64>,
    ) -> ActDecisionView {
        self.inner.decide_order_act(cap_key, order_id, amount_minor)
    }

    /// A manager approves an act on one sale with their PIN.
    pub fn approve_order_act(
        &self,
        approver_pin: String,
        cap_key: String,
        order_id: String,
        amount_minor: Option<i64>,
    ) -> Result<ApprovalView, MadarError> {
        self.inner
            .approve_order_act(approver_pin, cap_key, order_id, amount_minor)
            .map_err(MadarError::from)
    }

    /// Void a sale with a manager's approval.
    pub async fn void_order_approved(
        &self,
        order_id: String,
        reason: String,
        note: Option<String>,
        restore_inventory: bool,
        approval: Option<ApprovalView>,
    ) -> Result<(), MadarError> {
        self.inner
            .void_order_approved(order_id, reason, note, restore_inventory, approval)
            .await
            .map_err(MadarError::from)
    }

    /// Refund with a manager's approval.
    pub async fn refund_order_approved(
        &self,
        order_id: String,
        amount_minor: i64,
        method: String,
        reason: String,
        note: Option<String>,
        approval: Option<ApprovalView>,
    ) -> Result<(), MadarError> {
        self.inner
            .refund_order_approved(order_id, amount_minor, method, reason, note, approval)
            .await
            .map_err(MadarError::from)
    }
}
