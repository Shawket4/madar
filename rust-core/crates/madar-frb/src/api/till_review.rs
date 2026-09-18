//! "N actions need a manager": the till's refused + flagged acts and the one
//! manager PIN that clears them (stream 11 part 2). Pure delegation to
//! madar-core; owns the view mirrors.
use flutter_rust_bridge::frb;

use crate::api::bridge::MadarBridge;
use crate::api::error::MadarError;

pub use madar_core::till_review::{BatchAuthorizeView, ManagerActionView, ManagerActionsView};

/// One thing at this till that needs a manager.
#[frb(mirror(ManagerActionView))]
pub struct _ManagerActionView {
    pub id: String,
    pub kind: String,
    pub what: String,
    pub why: String,
    pub capability: String,
    pub person_name: String,
    pub person_id: String,
    pub occurred_at: String,
    pub amount_minor: Option<i64>,
}

/// The indicator and its list.
#[frb(mirror(ManagerActionsView))]
pub struct _ManagerActionsView {
    pub count: u32,
    pub items: Vec<ManagerActionView>,
    pub headline: String,
    pub can_authorize: bool,
    pub blocked_reason: String,
}

/// What one manager PIN managed to clear.
#[frb(mirror(BatchAuthorizeView))]
pub struct _BatchAuthorizeView {
    pub authorized: Vec<String>,
    pub left: Vec<ManagerActionView>,
    pub summary: String,
}

impl MadarBridge {
    /// Everything at this till that needs a manager. Offline — the outbox and
    /// the last pulled flags, never the network.
    #[frb(sync)]
    pub fn pending_manager_actions(&self) -> ManagerActionsView {
        self.inner.pending_manager_actions()
    }

    /// Pull this branch's open flags so the list is current. Best-effort.
    pub async fn refresh_review_flags(&self) -> Result<u32, MadarError> {
        self.inner.refresh_review_flags().await.map_err(MadarError::from)
    }

    /// One manager PIN for the whole batch. The signed-in person does not
    /// change. An empty `ids` means everything in the list.
    pub async fn authorize_manager_actions(
        &self,
        approver_pin: String,
        ids: Vec<String>,
    ) -> Result<BatchAuthorizeView, MadarError> {
        self.inner
            .authorize_manager_actions(approver_pin, ids)
            .await
            .map_err(MadarError::from)
    }
}
