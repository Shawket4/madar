//! Cash spot check and the live drawer figures (owner design 2026-09-16 item 5).
//! Pure delegation to madar-core; owns the view mirrors.
use flutter_rust_bridge::frb;

use crate::api::approvals::{ActDecisionView, ApprovalView};
use crate::api::bridge::MadarBridge;
use crate::api::error::MadarError;
use crate::api::till::{CloseTillMethodView, CloseTillPreviewView, SpotCheckLineView, TillReportView};

pub use madar_core::cash_spot::{CashSpotView, SpotCheckResultView, SpotCountInput, SpotMethodResultView};

#[frb(mirror(SpotCheckLineView))]
pub struct _SpotCheckLineView {
    pub id: String,
    pub counted_cash_minor: i64,
    pub expected_cash_minor: i64,
    pub discrepancy_minor: i64,
    pub checked_by_name: String,
    pub approved_by_name: Option<String>,
    pub checked_at: String,
    pub note: Option<String>,
    pub queued: bool,
}

#[frb(mirror(CashSpotView))]
pub struct _CashSpotView {
    pub report: TillReportView,
    pub expected_cash_minor: i64,
    pub methods: Vec<CloseTillMethodView>,
    pub checks: Vec<SpotCheckLineView>,
    pub approval_id: Option<String>,
}

#[frb(mirror(SpotCountInput))]
pub struct _SpotCountInput {
    pub method: String,
    pub counted_minor: Option<i64>,
}

#[frb(mirror(SpotMethodResultView))]
pub struct _SpotMethodResultView {
    pub method: String,
    pub label: String,
    pub is_cash: bool,
    pub expected_minor: i64,
    pub counted_minor: Option<i64>,
    pub discrepancy_minor: Option<i64>,
}

#[frb(mirror(SpotCheckResultView))]
pub struct _SpotCheckResultView {
    pub check: SpotCheckLineView,
    pub methods: Vec<SpotMethodResultView>,
    pub verdict: String,
}

impl MadarBridge {
    /// The signed-in person may see the open till's figures.
    #[frb(sync)]
    pub fn till_figures_visible(&self) -> bool {
        self.inner.till_figures_visible()
    }

    /// Cash spot / close figures: `allow` or `needs_approval` (a PIN).
    #[frb(sync)]
    pub fn cash_spot_access(&self) -> ActDecisionView {
        self.inner.cash_spot_access()
    }

    /// Someone holding the grant unlocks one action with their PIN.
    pub fn approve_cash_spot(&self, approver_pin: String) -> Result<ApprovalView, MadarError> {
        self.inner.approve_cash_spot(approver_pin).map_err(MadarError::from)
    }

    /// The full live drawer view.
    pub async fn cash_spot_view(&self, approval: Option<ApprovalView>) -> Result<CashSpotView, MadarError> {
        self.inner.cash_spot_view(approval).await.map_err(MadarError::from)
    }

    /// The expected figures on the close screen, before closing.
    pub async fn close_figures(&self, approval: Option<ApprovalView>) -> Result<CloseTillPreviewView, MadarError> {
        self.inner.close_figures(approval).await.map_err(MadarError::from)
    }

    /// Record a spot check (queued; offline-capable).
    pub async fn record_cash_spot_check(
        &self,
        counted_cash_minor: i64,
        counts: Vec<SpotCountInput>,
        note: Option<String>,
        approval: Option<ApprovalView>,
    ) -> Result<SpotCheckResultView, MadarError> {
        self.inner
            .record_cash_spot_check(counted_cash_minor, counts, note, approval)
            .await
            .map_err(MadarError::from)
    }
}
