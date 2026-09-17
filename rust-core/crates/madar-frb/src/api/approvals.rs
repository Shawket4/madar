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
}

impl MadarBridge {
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

    /// Allowed / needs a manager / refused for a queue act (`"resume"` |
    /// `"discard"`) on a held order — whose it is and how old come from the core.
    #[frb(sync)]
    pub fn decide_draft_act(&self, act: String, id: String) -> ActDecisionView {
        self.inner.decide_draft_act(act, id)
    }

    /// A manager approves a queue act on a held order with their PIN.
    pub fn approve_draft_act(
        &self,
        approver_pin: String,
        act: String,
        id: String,
    ) -> Result<ApprovalView, MadarError> {
        self.inner
            .approve_draft_act(approver_pin, act, id)
            .map_err(MadarError::from)
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
