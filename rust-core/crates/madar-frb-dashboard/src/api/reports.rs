//! Dashboard analytics FRB surface — mirrors the projected report DTOs and adds
//! the delegating read methods as an `impl MadarBridge` block.
use flutter_rust_bridge::frb;

pub use madar_core::reports::{
    DashboardBranchRankView, DashboardCategorySalesView, DashboardItemSalesView,
    DashboardPaymentSliceView, DashboardSummaryView, DashboardTimePointView,
};

use crate::api::bridge::MadarBridge;
use crate::api::error::MadarError;

#[frb(mirror(DashboardItemSalesView))]
pub struct _DashboardItemSalesView {
    pub item_name: String,
    pub quantity_sold: i64,
    pub revenue_minor: i64,
}

#[frb(mirror(DashboardCategorySalesView))]
pub struct _DashboardCategorySalesView {
    pub category_name: String,
    pub quantity_sold: i64,
    pub revenue_minor: i64,
}

#[frb(mirror(DashboardPaymentSliceView))]
pub struct _DashboardPaymentSliceView {
    pub method: String,
    pub revenue_minor: i64,
}

#[frb(mirror(DashboardBranchRankView))]
pub struct _DashboardBranchRankView {
    pub branch_name: String,
    pub revenue_minor: i64,
}

#[frb(mirror(DashboardTimePointView))]
pub struct _DashboardTimePointView {
    pub period: String,
    pub revenue_minor: i64,
    pub orders: i64,
}

#[frb(mirror(DashboardSummaryView))]
pub struct _DashboardSummaryView {
    pub branch_name: String,
    pub currency_code: String,
    pub from: String,
    pub to: String,
    pub total_orders: i64,
    pub voided_orders: i64,
    pub subtotal_minor: i64,
    pub total_discount_minor: i64,
    pub total_tax_minor: i64,
    pub total_revenue_minor: i64,
    pub top_items: Vec<DashboardItemSalesView>,
    pub by_category: Vec<DashboardCategorySalesView>,
    pub payment_mix: Vec<DashboardPaymentSliceView>,
    pub branch_ranking: Vec<DashboardBranchRankView>,
}

impl MadarBridge {
    /// Dashboard home KPI summary for the active scope over an optional RFC3339
    /// `[from, to]` window. Online-only.
    pub async fn dashboard_summary(
        &self,
        from: Option<String>,
        to: Option<String>,
    ) -> Result<DashboardSummaryView, MadarError> {
        self.inner
            .dashboard_summary(from, to)
            .await
            .map_err(MadarError::from)
    }

    /// Revenue trend points for the active scope over `[from, to]` at
    /// `granularity` ("hourly"/"daily"/…). Online-only.
    pub async fn dashboard_timeseries(
        &self,
        from: Option<String>,
        to: Option<String>,
        granularity: Option<String>,
    ) -> Result<Vec<DashboardTimePointView>, MadarError> {
        self.inner
            .dashboard_timeseries(from, to, granularity)
            .await
            .map_err(MadarError::from)
    }
}
