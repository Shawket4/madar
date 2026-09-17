//! Till domain (TILLS_CONTRACT §4.8): a person's sales session on this device —
//! open (server / LAN verification, unverified fallback), cash, close with per-
//! method reconciliation, force-close, Z-reports, history, branch open tills,
//! payment-method availability. Delegation to madar-core only.
use flutter_rust_bridge::frb;

use crate::api::bridge::MadarBridge;
use crate::api::error::MadarError;
use crate::api::orders::OrderSummaryView;
use crate::api::types::TillView;

use crate::api::catalog::PaymentMethodView;
pub use madar_core::cash_spot::SpotCheckLineView;
pub use madar_core::orders::TillStatsView;
pub use madar_core::till::{
    BranchOpenTillView, CashMovementView, CloseTillMethodView, CloseTillOutcomeView,
    CloseTillPreviewView, LastTillWarningView, OpenBillsNoticeView, OpenTillOutcome,
    ReconciliationInput, ReconciliationLineView, TillElsewhereView, TillReportCashLine,
    TillReportPaymentLine, TillReportView, TillSummaryView,
};

#[frb(mirror(CashMovementView))]
pub struct _CashMovementView {
    pub id: String,
    /// `pay_in` | `pay_out` | `safe_drop` | `correction`.
    pub kind: String,
    pub amount_minor: i64,
    pub note: String,
    pub moved_by_name: String,
    pub created_at: String,
}

/// A past till, projected for the history list.
#[frb(mirror(TillSummaryView))]
pub struct _TillSummaryView {
    pub id: String,
    pub branch_name: Option<String>,
    pub teller_name: Option<String>,
    pub opened_at: String,
    pub closed_at: Option<String>,
    pub opening_cash_minor: i64,
    pub closing_declared_minor: Option<i64>,
    pub closing_system_minor: Option<i64>,
    pub discrepancy_minor: Option<i64>,
    pub status: String,
    pub is_open: bool,
    pub device_code: Option<String>,
    pub verification: String,
    pub opened_while_another_open: bool,
    pub reconciliation_status: Option<String>,
}

#[frb(mirror(TillReportPaymentLine))]
pub struct _TillReportPaymentLine {
    pub method: String,
    pub is_cash: bool,
    pub order_count: i64,
    pub total_minor: i64,
}

#[frb(mirror(TillReportCashLine))]
pub struct _TillReportCashLine {
    pub amount_minor: i64,
    pub note: String,
    pub moved_by_name: String,
    pub created_at: String,
}

/// The till report (Z report / close figures).
#[frb(mirror(TillReportView))]
pub struct _TillReportView {
    pub teller_name: String,
    pub opened_at: String,
    pub closed_at: Option<String>,
    pub printed_at: String,
    pub is_open: bool,
    pub expected_cash_minor: i64,
    pub opening_cash_minor: i64,
    pub opening_cash_was_edited: bool,
    pub opening_cash_original_minor: Option<i64>,
    pub opening_cash_edit_reason: Option<String>,
    pub closing_cash_declared_minor: Option<i64>,
    pub total_payments_minor: i64,
    pub net_payments_minor: i64,
    pub voided_amount_minor: i64,
    pub refunds_issued_minor: i64,
    pub refunds_issued_cash_minor: i64,
    pub refunds_issued_count: i64,
    pub cash_in_refunded_sales_minor: i64,
    /// Tax / service charge on this till's sales, net of their refunds.
    pub total_tax_minor: i64,
    pub total_service_charge_minor: i64,
    /// Table bills whose service charge was waived, and what it came to.
    pub service_charge_waived_count: i64,
    pub service_charge_waived_minor: i64,
    pub cash_movements_net_minor: i64,
    pub cash_in_minor: i64,
    pub cash_out_minor: i64,
    pub payment_lines: Vec<TillReportPaymentLine>,
    pub cash_movements: Vec<TillReportCashLine>,
    pub from_server: bool,
    pub device_code: Option<String>,
    pub order_number_first: Option<i64>,
    pub order_number_last: Option<i64>,
    pub reconciliation: Vec<ReconciliationLineView>,
    pub old_bills_count: Option<i64>,
    pub open_bills_count: Option<i64>,
    pub opened_while_another_open: bool,
    pub verification: String,
    pub spot_checks: Vec<SpotCheckLineView>,
}

#[frb(mirror(TillStatsView))]
pub struct _TillStatsView {
    pub sales_minor: i64,
    pub order_count: i64,
}

#[frb(mirror(TillElsewhereView))]
pub struct _TillElsewhereView {
    pub till_id: String,
    pub device_code: Option<String>,
    pub device_label: Option<String>,
    pub opened_at: String,
    /// `server` | `lan`.
    pub source: String,
}

#[frb(mirror(OpenTillOutcome))]
pub struct _OpenTillOutcome {
    pub till: Option<TillView>,
    pub verification: String,
    pub open_elsewhere: Option<TillElsewhereView>,
}

#[frb(mirror(OpenBillsNoticeView))]
pub struct _OpenBillsNoticeView {
    pub open_bills_count: i64,
    pub open_bills_amount_minor: i64,
    pub oldest_opened_at: Option<String>,
    pub old_bills_count: i64,
    pub old_bill_hours: i64,
    pub seated_tables_count: i64,
    pub since: Option<String>,
}

#[frb(mirror(ReconciliationInput))]
pub struct _ReconciliationInput {
    pub method: String,
    /// `checked` | `disagreed`.
    pub status: String,
    pub declared_amount_minor: Option<i64>,
    pub note: Option<String>,
}

#[frb(mirror(CloseTillMethodView))]
pub struct _CloseTillMethodView {
    pub method: String,
    pub label: String,
    pub is_cash: bool,
    pub system_total_minor: i64,
    pub order_count: i64,
}

#[frb(mirror(LastTillWarningView))]
pub struct _LastTillWarningView {
    pub open_bills_count: i64,
    pub open_bills_amount_minor: i64,
    pub seated_tables_count: i64,
}

#[frb(mirror(CloseTillPreviewView))]
pub struct _CloseTillPreviewView {
    pub till: TillView,
    pub expected_cash_minor: i64,
    pub methods: Vec<CloseTillMethodView>,
    pub last_till_warning: Option<LastTillWarningView>,
    pub from_server: bool,
    pub figures_hidden: bool,
}

#[frb(mirror(ReconciliationLineView))]
pub struct _ReconciliationLineView {
    pub method: String,
    pub label: String,
    pub is_cash: bool,
    pub system_total_minor: i64,
    pub status: String,
    pub declared_amount_minor: Option<i64>,
    pub note: Option<String>,
    pub changed_after_close: bool,
}

#[frb(mirror(CloseTillOutcomeView))]
pub struct _CloseTillOutcomeView {
    pub queued: bool,
    pub reconciliation: Vec<ReconciliationLineView>,
    pub last_till_warning: Option<LastTillWarningView>,
}

#[frb(mirror(BranchOpenTillView))]
pub struct _BranchOpenTillView {
    pub till_id: String,
    pub teller_id: String,
    pub teller_name: String,
    pub device_code: Option<String>,
    pub device_label: Option<String>,
    pub opened_at: String,
    pub is_this_device: bool,
    /// `server` | `lan` | `both`.
    pub source: String,
}

impl MadarBridge {
    // session / open
    pub fn current_till(&self) -> Result<Option<TillView>, MadarError> {
        self.inner.current_till().map_err(MadarError::from)
    }

    pub async fn check_till_elsewhere(&self) -> Result<Option<TillElsewhereView>, MadarError> {
        self.inner.check_till_elsewhere().await.map_err(MadarError::from)
    }

    pub fn suggested_opening_cash_minor(&self) -> Result<i64, MadarError> {
        self.inner.suggested_opening_cash_minor().map_err(MadarError::from)
    }

    pub async fn open_till(
        &self,
        opening_cash_minor: i64,
        opening_reason: Option<String>,
    ) -> Result<OpenTillOutcome, MadarError> {
        self.inner
            .open_till(opening_cash_minor, opening_reason)
            .await
            .map_err(MadarError::from)
    }

    pub async fn refresh_till(&self) -> Result<Option<TillView>, MadarError> {
        self.inner.refresh_till().await.map_err(MadarError::from)
    }

    /// `None` when no bills are open.
    pub async fn open_bills_notice(&self) -> Result<Option<OpenBillsNoticeView>, MadarError> {
        self.inner.open_bills_notice().await.map_err(MadarError::from)
    }

    // cash
    pub async fn record_cash_movement(
        &self,
        amount_minor: i64,
        note: String,
        kind: Option<String>,
        corrects: Option<String>,
    ) -> Result<CashMovementView, MadarError> {
        self.inner
            .record_cash_movement(amount_minor, note, kind, corrects)
            .await
            .map_err(MadarError::from)
    }

    pub async fn list_cash_movements(&self) -> Result<Vec<CashMovementView>, MadarError> {
        self.inner.list_cash_movements().await.map_err(MadarError::from)
    }

    // close / reconciliation
    pub async fn close_till_preview(&self) -> Result<CloseTillPreviewView, MadarError> {
        self.inner.close_till_preview_checked().await.map_err(MadarError::from)
    }

    pub async fn close_till(
        &self,
        closing_cash_minor: i64,
        cash_note: Option<String>,
        reconciliation: Vec<ReconciliationInput>,
    ) -> Result<CloseTillOutcomeView, MadarError> {
        self.inner
            .close_till(closing_cash_minor, cash_note, reconciliation)
            .await
            .map_err(MadarError::from)
    }

    pub async fn force_close_till(&self, till_id: String, reason: String) -> Result<(), MadarError> {
        self.inner
            .force_close_till(till_id, reason)
            .await
            .map_err(MadarError::from)
    }

    pub async fn till_report(&self) -> Result<TillReportView, MadarError> {
        self.inner.till_report_checked().await.map_err(MadarError::from)
    }

    pub async fn till_report_for(&self, till_id: String) -> Result<TillReportView, MadarError> {
        self.inner.till_report_for_checked(till_id).await.map_err(MadarError::from)
    }

    // lists
    pub async fn list_tills(&self) -> Result<Vec<TillSummaryView>, MadarError> {
        self.inner.list_tills().await.map_err(MadarError::from)
    }

    pub async fn branch_open_tills(&self) -> Result<Vec<BranchOpenTillView>, MadarError> {
        self.inner.branch_open_tills().await.map_err(MadarError::from)
    }

    pub fn till_stats(&self, orders: Vec<OrderSummaryView>) -> TillStatsView {
        self.inner.till_stats(orders)
    }

    // payment methods
    pub fn available_payment_methods(&self) -> Result<Vec<PaymentMethodView>, MadarError> {
        self.inner.available_payment_methods().map_err(MadarError::from)
    }

    // device
    #[frb(sync)]
    pub fn device_id(&self) -> String {
        self.inner.device_id()
    }
}
