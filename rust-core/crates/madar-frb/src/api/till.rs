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
use crate::api::cash_spot::SpotViewLineView;
pub use madar_core::orders::TillStatsView;
pub use madar_core::queue::{ClosePreflightView, HeldLeftOpenView};

/// One order a till close would leave open.
#[frb(mirror(HeldLeftOpenView))]
pub struct _HeldLeftOpenView {
    pub id: String,
    pub label: String,
    pub started_by_name: Option<String>,
    pub item_count: i64,
    pub total_minor: i64,
    pub in_hand: bool,
}

/// What a till close warns about before it counts anything.
#[frb(mirror(ClosePreflightView))]
pub struct _ClosePreflightView {
    pub held_count: i64,
    pub held_total_minor: i64,
    pub held: Vec<HeldLeftOpenView>,
    pub title: String,
    pub body: String,
}
pub use madar_core::till::{
    BranchOpenTillView, CashMovementView, CloseTillMethodView, CloseTillOutcomeView,
    CloseTillPreviewView, LastTillWarningView, OpenBillsNoticeView, OpenTillOutcome,
    ReconciliationInput, ReconciliationLineView, TillElsewhereView, TillLockView,
    TillReportCashLine, TillReportPaymentLine, TillReportView, TillSummaryView,
};

/// Is this device walled to the open-till screen, and why? ONE answer the
/// shell reads — no screen decides this for itself.
#[frb(mirror(TillLockView))]
pub struct _TillLockView {
    pub locked: bool,
    /// `""` | `"no_till"` | `"not_permitted"` | `"open_elsewhere"`.
    pub reason: String,
    pub title: String,
    pub body: String,
    pub can_open: bool,
    pub holds_drawer: bool,
    pub elsewhere: Option<TillElsewhereView>,
}

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
    pub held_orders_left_open: Option<i64>,
    pub held_orders_left_open_total_minor: Option<i64>,
    pub opened_while_another_open: bool,
    pub verification: String,
    pub spot_views: Vec<SpotViewLineView>,
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

    /// Whether the shell must wall this device to the open-till screen, with
    /// the reason and what to do next. Sync + offline-safe.
    #[frb(sync)]
    pub fn till_lock(&self) -> TillLockView {
        self.inner.till_lock()
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

    /// A pay-out handed to an employee for shop purchases: their expense
    /// advance in Dawam, never deducted (AV-8). `amount_minor` is positive.
    pub async fn record_expense_advance(
        &self,
        amount_minor: i64,
        note: String,
        person: String,
    ) -> Result<CashMovementView, MadarError> {
        self.inner.record_expense_advance(amount_minor, note, person).await.map_err(MadarError::from)
    }

    /// This branch's staff, for the expense-advance picker (the last list offline).
    pub async fn branch_people(&self) -> Result<Vec<BranchPersonView>, MadarError> {
        self.inner.branch_people().await.map_err(MadarError::from)
    }

    /// A dead or forgotten phone: clock in or out with the till PIN (CL-13).
    pub async fn till_punch(&self, pin: String) -> Result<TillPunchView, MadarError> {
        self.inner.till_punch(pin).await.map_err(MadarError::from)
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
        leave_held_open: bool,
    ) -> Result<CloseTillOutcomeView, MadarError> {
        self.inner
            .close_till_confirmed(closing_cash_minor, cash_note, reconciliation, leave_held_open)
            .await
            .map_err(MadarError::from)
    }

    /// The held-orders warning a close shows first: every order still parked
    /// on this device (and the counter cart), with names and totals. Local.
    #[frb(sync)]
    pub fn close_preflight(&self) -> ClosePreflightView {
        self.inner.close_preflight()
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

    /// The shift totals of the PAST ORDERS screen (owner decision 3: that
    /// screen is never gated). Every other surface uses
    /// [`Self::till_stats_checked`].
    pub fn till_stats(&self, orders: Vec<OrderSummaryView>) -> TillStatsView {
        self.inner.till_stats(orders)
    }

    /// The shift totals as the signed-in person may see them: refused
    /// (`Forbidden`) without `till.cash_spot_check`, the one check the report
    /// and the close preview go through.
    pub fn till_stats_checked(&self, orders: Vec<OrderSummaryView>) -> Result<TillStatsView, MadarError> {
        self.inner.till_stats_checked(orders).map_err(MadarError::from)
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

pub use madar_core::till_dawam::{BranchPersonView, TillPunchView};

/// Someone at this branch, for the expense-advance picker.
#[frb(mirror(BranchPersonView))]
pub struct _BranchPersonView {
    pub employee_id: String,
    pub name: String,
}

/// What a till PIN punch did, worded by the core.
#[frb(mirror(TillPunchView))]
pub struct _TillPunchView {
    pub name: String,
    /// `in` · `out`
    pub punched: String,
    pub message: String,
}
