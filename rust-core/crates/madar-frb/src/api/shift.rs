//! Shift domain — lifecycle (close/refresh), Z-reports, cash drawer movements,
//! shift history, live stats and the till picker, delegated to madar-core.
//! Mirrors the shift view DTOs (`shift.rs` / `orders.rs` / lib root); binding
//! code only. `ShiftView` itself is mirrored in `types.rs`; `OrderSummaryView`
//! is owned by the orders sibling.
use flutter_rust_bridge::frb;

use crate::api::bridge::MadarBridge;
use crate::api::error::MadarError;
use crate::api::orders::OrderSummaryView;
use crate::api::types::ShiftView;

pub use madar_core::orders::ShiftStatsView;
pub use madar_core::shift::{
    CashMovementView, ShiftReportCashLine, ShiftReportPaymentLine, ShiftReportView,
    ShiftSummaryView,
};
pub use madar_core::TillView;

// ── shift DTO mirrors (madar-core/src/shift.rs) ─────────────────────────────

/// A cash-drawer movement (pay-in / pay-out). `amount_minor` is signed:
/// positive = cash in, negative = cash out.
#[frb(mirror(CashMovementView))]
pub struct _CashMovementView {
    pub id: String,
    pub amount_minor: i64,
    pub note: String,
    pub moved_by_name: String,
    pub created_at: String,
}

/// A past shift, projected for the history list.
#[frb(mirror(ShiftSummaryView))]
pub struct _ShiftSummaryView {
    pub id: String,
    pub branch_name: Option<String>,
    /// Teller who owns the shift (the Teller column in the past-shifts table).
    pub teller_name: Option<String>,
    pub opened_at: String,
    pub closed_at: Option<String>,
    pub opening_cash_minor: i64,
    pub closing_declared_minor: Option<i64>,
    pub closing_system_minor: Option<i64>,
    pub discrepancy_minor: Option<i64>,
    pub status: String,
    pub is_open: bool,
}

/// One payment-method line in the shift report.
#[frb(mirror(ShiftReportPaymentLine))]
pub struct _ShiftReportPaymentLine {
    pub method: String,
    pub is_cash: bool,
    pub order_count: i64,
    pub total_minor: i64,
}

/// One itemised cash-drawer movement on the report. `amount_minor` is signed
/// (positive = pay-in, negative = pay-out).
#[frb(mirror(ShiftReportCashLine))]
pub struct _ShiftReportCashLine {
    pub amount_minor: i64,
    pub note: String,
    pub moved_by_name: String,
    pub created_at: String,
}

/// The shift report shown on close (drives the system-cash + discrepancy) and in
/// a report preview. `expected_cash_minor` is the server's expected drawer cash
/// PLUS still-queued cash sales (offline: opening cash + queued cash).
#[frb(mirror(ShiftReportView))]
pub struct _ShiftReportView {
    /// Teller who ran the shift, and the open/close/print timestamps (RFC3339) —
    /// the host stamps them to the branch timezone for display.
    pub teller_name: String,
    pub opened_at: String,
    /// `None` while the shift is still open.
    pub closed_at: Option<String>,
    pub printed_at: String,
    pub is_open: bool,
    pub expected_cash_minor: i64,
    pub opening_cash_minor: i64,
    /// Opening-cash mismatch: when the teller's opening count differed from the
    /// suggested (last close), `opening_cash_was_edited` is set, `*_original_minor`
    /// is the suggested amount, and `*_edit_reason` is the teller's note.
    pub opening_cash_was_edited: bool,
    pub opening_cash_original_minor: Option<i64>,
    pub opening_cash_edit_reason: Option<String>,
    /// Cash actually counted at close (the drawer count). `None` until closed —
    /// drives the reconciliation block + the over/short difference.
    pub closing_cash_declared_minor: Option<i64>,
    pub total_payments_minor: i64,
    pub net_payments_minor: i64,
    pub voided_amount_minor: i64,
    pub cash_movements_net_minor: i64,
    /// Pay-in / pay-out drawer totals (separate, not just the net) — Z-report depth.
    pub cash_in_minor: i64,
    pub cash_out_minor: i64,
    pub payment_lines: Vec<ShiftReportPaymentLine>,
    /// Each individual cash movement (newest-first), for the itemised drawer block.
    pub cash_movements: Vec<ShiftReportCashLine>,
    /// `false` = offline fallback (no server figures, just opening + queued).
    pub from_server: bool,
}

// ── stats + till mirrors (madar-core/src/orders.rs, lib root) ───────────────

/// Live shift totals for the action-bar stats pill: sales total + order count,
/// voided orders excluded.
#[frb(mirror(ShiftStatsView))]
pub struct _ShiftStatsView {
    pub sales_minor: i64,
    pub order_count: i64,
}

/// A till (physical drawer) the device can bind to — the device-setup / Settings
/// till picker. Cash continuity + the one-open-shift rule key on the till.
#[frb(mirror(TillView))]
pub struct _TillView {
    pub id: String,
    pub name: String,
    pub is_default: bool,
    pub is_active: bool,
}

impl MadarBridge {
    /// Suggested opening cash for the next shift (minor units) — the previous
    /// shift's declared closing, for cash continuity. 0 when none is known.
    pub fn suggested_opening_cash_minor(&self) -> Result<i64, MadarError> {
        self.inner
            .suggested_opening_cash_minor()
            .map_err(MadarError::from)
    }

    /// Close the current open shift: count the closing drawer cash + an optional
    /// note. Marks the shift closed locally and queues an idempotent
    /// `close_shift` command; works offline. Errors if there is no open shift.
    pub async fn close_shift(
        &self,
        closing_cash_minor: i64,
        cash_note: Option<String>,
    ) -> Result<(), MadarError> {
        self.inner
            .close_shift(closing_cash_minor, cash_note)
            .await
            .map_err(MadarError::from)
    }

    /// The current shift's report — drives the close-shift system-cash +
    /// discrepancy. Online: the server report plus still-queued cash sales.
    /// Offline / on error: opening cash + queued cash (`from_server = false`).
    pub async fn shift_report(&self) -> Result<ShiftReportView, MadarError> {
        self.inner.shift_report().await.map_err(MadarError::from)
    }

    /// Reconcile the device's shift with the server (online). Caches the server's
    /// open shift, or CLEARS the local cache when the server reports none — call
    /// this on login and on app resume.
    pub async fn refresh_shift(&self) -> Result<Option<ShiftView>, MadarError> {
        self.inner.refresh_shift().await.map_err(MadarError::from)
    }

    /// Record a cash-drawer movement against the open shift — pay-IN when
    /// `amount_minor > 0`, pay-OUT when `< 0`. Offline-first and idempotent on a
    /// minted `client_ref`, so a replay never double-applies cash.
    pub async fn record_cash_movement(
        &self,
        amount_minor: i64,
        note: String,
    ) -> Result<CashMovementView, MadarError> {
        self.inner
            .record_cash_movement(amount_minor, note)
            .await
            .map_err(MadarError::from)
    }

    /// Cash movements for the open shift — server rows merged with still-queued
    /// (offline) ones, so the drawer view is complete with or without a connection.
    pub async fn list_cash_movements(&self) -> Result<Vec<CashMovementView>, MadarError> {
        self.inner
            .list_cash_movements()
            .await
            .map_err(MadarError::from)
    }

    /// Past shifts for this branch, newest first (the history screen). Live when
    /// online (cached write-through), else the last-synced snapshot.
    pub async fn list_shifts(&self) -> Result<Vec<ShiftSummaryView>, MadarError> {
        self.inner.list_shifts().await.map_err(MadarError::from)
    }

    /// A PAST shift's Z-report (history-screen reprint). Live when online (cached
    /// write-through), else the cached report; a shift opened+closed entirely
    /// offline is reconstructed from local data.
    pub async fn shift_report_for(&self, shift_id: String) -> Result<ShiftReportView, MadarError> {
        self.inner
            .shift_report_for(shift_id)
            .await
            .map_err(MadarError::from)
    }

    /// Live shift stats (sales total + order count) for the action-bar pill,
    /// derived from the orders the host already loaded via `list_shift_orders`
    /// (synced + queued), voided excluded. Pure — no extra network.
    pub fn shift_stats(&self, orders: Vec<OrderSummaryView>) -> ShiftStatsView {
        self.inner.shift_stats(orders)
    }

    /// The branch's active tills (the device-setup / Settings till picker). Write-
    /// through cached so the picker still works offline. Default till first.
    pub async fn list_tills(&self) -> Result<Vec<TillView>, MadarError> {
        self.inner.list_tills().await.map_err(MadarError::from)
    }
}
