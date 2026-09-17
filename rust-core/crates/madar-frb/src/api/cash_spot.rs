//! Cash spot: the live till report, its print, and the record of every look
//! (owner design 2026-09-16 item 5, corrected 2026-09-17).
//! Pure delegation to madar-core; owns the view mirrors.
use flutter_rust_bridge::frb;

use crate::api::approvals::{ActDecisionView, ApprovalView};
use crate::api::bridge::MadarBridge;
use crate::api::error::MadarError;
use crate::api::till::{CloseTillMethodView, CloseTillPreviewView, TillReportView};

pub use madar_core::cash_spot::{CashSpotView, SpotViewLineView};

#[frb(mirror(SpotViewLineView))]
pub struct _SpotViewLineView {
    pub id: String,
    pub viewed_by_name: String,
    pub approved_by_name: Option<String>,
    pub viewed_at: String,
    pub printed: bool,
    pub queued: bool,
}

#[frb(mirror(CashSpotView))]
pub struct _CashSpotView {
    pub view_id: String,
    pub report: TillReportView,
    pub expected_cash_minor: i64,
    pub methods: Vec<CloseTillMethodView>,
    pub views: Vec<SpotViewLineView>,
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

    /// Open the cash spot: the full live till report (records the look).
    pub async fn cash_spot_view(&self, approval: Option<ApprovalView>) -> Result<CashSpotView, MadarError> {
        self.inner.cash_spot_view(approval).await.map_err(MadarError::from)
    }

    /// The spot report of this look was printed.
    pub async fn record_cash_spot_print(&self, view_id: String) -> Result<SpotViewLineView, MadarError> {
        self.inner.record_cash_spot_print(view_id).await.map_err(MadarError::from)
    }

    /// The expected figures on the close screen, before closing.
    pub async fn close_figures(&self, approval: Option<ApprovalView>) -> Result<CloseTillPreviewView, MadarError> {
        self.inner.close_figures(approval).await.map_err(MadarError::from)
    }
}
