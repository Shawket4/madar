//! Employee self-service FRB surface — mirrors the projected staff DTOs and adds
//! the delegating methods as an `impl MadarBridge` block.
//!
//! Every method here is online-only by design (see `madar_core::staff`): a
//! check-in is a claim about where and when someone was, so it is never queued.
use flutter_rust_bridge::frb;

pub use madar_core::staff::{
    AdjustmentView, AttendanceRecordView, EmployeeView, LeaveBalanceView, PayrollLineView,
    PayrollPeriodView, PayslipView, PresenceRowView, SalaryAdvanceView, ScheduledDayView,
    ScheduledShiftView, StaffRequestView, TeamPresenceView, TodayView,
};

use crate::api::bridge::MadarBridge;
use crate::api::error::MadarError;

#[frb(mirror(AttendanceRecordView))]
pub struct _AttendanceRecordView {
    pub id: String,
    pub status: String,
    pub business_date: String,
    pub work_shift_name: String,
    pub check_in_at: String,
    pub check_out_at: String,
    pub check_in_distance_meters: i64,
    pub late_minutes: i64,
    pub overtime_minutes: i64,
    pub worked_minutes: i64,
    pub is_manual: bool,
    pub notes: String,
}

#[frb(mirror(ScheduledShiftView))]
pub struct _ScheduledShiftView {
    pub work_shift_id: String,
    pub name: String,
    pub scheduled_start_at: String,
    pub scheduled_end_at: String,
    pub grace_minutes: i64,
}

#[frb(mirror(TodayView))]
pub struct _TodayView {
    pub business_date: String,
    pub open_record: Option<AttendanceRecordView>,
    pub closed_records: Vec<AttendanceRecordView>,
    pub scheduled: Vec<ScheduledShiftView>,
    pub can_check_in: bool,
    pub can_check_out: bool,
    pub blocked_reason: String,
    pub branch_id: String,
    pub branch_name: String,
}

#[frb(mirror(StaffRequestView))]
pub struct _StaffRequestView {
    pub id: String,
    pub user_name: String,
    pub kind: String,
    pub on_date: String,
    pub end_date: String,
    pub from_time: String,
    pub to_time: String,
    pub leave_type_name: String,
    pub is_half_day: bool,
    pub title: String,
    pub status: String,
    pub is_paid: Option<bool>,
    pub reason: String,
    pub decision_note: String,
}

#[frb(mirror(LeaveBalanceView))]
pub struct _LeaveBalanceView {
    pub leave_type_id: String,
    pub leave_type_name: String,
    pub year: i64,
    pub entitled_centidays: i64,
    pub used_centidays: i64,
    pub remaining_centidays: i64,
}

#[frb(mirror(PayslipView))]
pub struct _PayslipView {
    pub id: String,
    pub base_minor: i64,
    pub overtime_minor: i64,
    pub bonuses_minor: i64,
    pub deductions_minor: i64,
    pub advance_installment_minor: i64,
    pub net_minor: i64,
    pub worked_centidays: i64,
    pub absent_centidays: i64,
    pub late_minutes: i64,
    pub overtime_minutes: i64,
    pub generated_at: String,
    pub period_name: String,
    pub period_start: String,
    pub period_end: String,
}

#[frb(mirror(SalaryAdvanceView))]
pub struct _SalaryAdvanceView {
    pub id: String,
    pub amount_minor: i64,
    pub installments: i64,
    pub monthly_installment_minor: i64,
    pub remaining_minor: i64,
    pub status: String,
    pub reason: String,
}

// ── Manager surface ──────────────────────────────────────────

#[frb(mirror(PresenceRowView))]
pub struct _PresenceRowView {
    pub user_id: String,
    pub name: String,
    pub job_title: String,
    pub branch_name: String,
    pub state: String,
    pub check_in_at: String,
    pub check_out_at: String,
    pub late_minutes: i64,
    pub worked_minutes: i64,
    pub scheduled_minutes: i64,
}

#[frb(mirror(TeamPresenceView))]
pub struct _TeamPresenceView {
    pub business_date: String,
    pub present: i64,
    pub late_count: i64,
    pub absent: i64,
    pub on_leave: i64,
    pub worked_minutes: i64,
    pub planned_minutes: i64,
    pub rows: Vec<PresenceRowView>,
}

#[frb(mirror(EmployeeView))]
pub struct _EmployeeView {
    pub user_id: String,
    pub name: String,
    pub job_title: String,
    pub department_name: String,
    pub employment_status: String,
    pub phone: String,
    pub employee_number: String,
    pub hire_date: String,
    pub base_salary_minor: i64,
}

#[frb(mirror(ScheduledDayView))]
pub struct _ScheduledDayView {
    pub date: String,
    pub branch_name: String,
    pub shifts: Vec<ScheduledShiftView>,
}

#[frb(mirror(PayrollPeriodView))]
pub struct _PayrollPeriodView {
    pub id: String,
    pub name: String,
    pub start_date: String,
    pub end_date: String,
    pub status: String,
    pub employee_count: i64,
    pub total_net_minor: i64,
}

#[frb(mirror(AdjustmentView))]
pub struct _AdjustmentView {
    pub id: String,
    pub user_id: String,
    pub user_name: String,
    pub amount_minor: i64,
    pub reason: String,
    pub effective_date: String,
    pub source: String,
    pub status: String,
    pub original_amount_minor: i64,
    pub overridden: bool,
    pub override_reason: String,
    pub waived: bool,
    pub waive_reason: String,
}

#[frb(mirror(PayrollLineView))]
pub struct _PayrollLineView {
    pub user_id: String,
    pub name: String,
    pub worked_minutes: i64,
    pub overtime_minutes: i64,
    pub late_minutes: i64,
    pub base_minor: i64,
    pub overtime_minor: i64,
    pub bonuses_minor: i64,
    pub deductions_minor: i64,
    pub advance_minor: i64,
    pub net_minor: i64,
    pub worked_centidays: i64,
    pub absent_centidays: i64,
    pub exception: String,
}

impl MadarBridge {
    /// The home screen in one round trip.
    pub async fn staff_today(&self) -> Result<TodayView, MadarError> {
        self.inner.staff_today().await.map_err(MadarError::from)
    }

    /// Clock in at `branch_id` with the device's current position.
    ///
    /// The coordinates are evidence, not a decision — the server measures the
    /// distance and refuses the punch when it is outside the branch's fence. A
    /// refusal arrives as `MadarError::Forbidden`/`Server` carrying the server's
    /// own wording, which already names the measured distance; show it verbatim.
    pub async fn staff_check_in(
        &self,
        branch_id: String,
        latitude: Option<f64>,
        longitude: Option<f64>,
    ) -> Result<AttendanceRecordView, MadarError> {
        self.inner
            .staff_check_in(branch_id, latitude, longitude)
            .await
            .map_err(MadarError::from)
    }

    /// Clock out of the currently open record. The server picks which one, so the
    /// app cannot close the wrong shift.
    pub async fn staff_check_out(
        &self,
        latitude: Option<f64>,
        longitude: Option<f64>,
    ) -> Result<AttendanceRecordView, MadarError> {
        self.inner
            .staff_check_out(latitude, longitude)
            .await
            .map_err(MadarError::from)
    }

    /// Own attendance over `[from, to]`, ISO `yyyy-mm-dd`.
    pub async fn staff_attendance(
        &self,
        from: String,
        to: String,
    ) -> Result<Vec<AttendanceRecordView>, MadarError> {
        self.inner
            .staff_attendance(from, to)
            .await
            .map_err(MadarError::from)
    }

    /// Own requests of every kind, newest first.
    pub async fn staff_requests(&self) -> Result<Vec<StaffRequestView>, MadarError> {
        self.inner.staff_requests().await.map_err(MadarError::from)
    }

    /// File a request of any kind; it lands as `pending` for a manager to decide.
    ///
    /// The SERVER validates each kind's required shape and returns a message
    /// naming what is missing, so the app carries no second copy of those rules.
    #[allow(clippy::too_many_arguments)]
    pub async fn staff_create_request(
        &self,
        kind: String,
        on_date: String,
        end_date: Option<String>,
        from_time: Option<String>,
        to_time: Option<String>,
        leave_type_id: Option<String>,
        is_half_day: bool,
        title: Option<String>,
        reason: Option<String>,
        attendance_record_id: Option<String>,
    ) -> Result<StaffRequestView, MadarError> {
        self.inner
            .staff_create_request(
                kind,
                on_date,
                end_date,
                from_time,
                to_time,
                leave_type_id,
                is_half_day,
                title,
                reason,
                attendance_record_id,
            )
            .await
            .map_err(MadarError::from)
    }

    /// Own leave balances for `year` (current calendar year when `None`).
    pub async fn staff_leave_balances(
        &self,
        year: Option<i64>,
    ) -> Result<Vec<LeaveBalanceView>, MadarError> {
        self.inner
            .staff_leave_balances(year)
            .await
            .map_err(MadarError::from)
    }

    /// Own payslips — finalised periods only.
    pub async fn staff_payslips(&self) -> Result<Vec<PayslipView>, MadarError> {
        self.inner.staff_payslips().await.map_err(MadarError::from)
    }

    /// Own salary advances and what is still owed.
    pub async fn staff_advances(&self) -> Result<Vec<SalaryAdvanceView>, MadarError> {
        self.inner.staff_advances().await.map_err(MadarError::from)
    }

    /// Request a salary advance repaid over `installments` months.
    pub async fn staff_request_advance(
        &self,
        amount_minor: i64,
        installments: i64,
        reason: Option<String>,
    ) -> Result<SalaryAdvanceView, MadarError> {
        self.inner
            .staff_request_advance(amount_minor, installments, reason)
            .await
            .map_err(MadarError::from)
    }

    // ── Manager surface ──────────────────────────────────────
    //
    // Permission-checked server-side; the tabs are hidden client-side purely
    // as a courtesy.

    /// The employee's own roster for a date range.
    pub async fn staff_schedule(
        &self,
        from: String,
        to: String,
    ) -> Result<Vec<ScheduledDayView>, MadarError> {
        self.inner
            .staff_schedule(from, to)
            .await
            .map_err(MadarError::from)
    }

    /// Who is in, late, absent or on leave right now.
    pub async fn manager_team_presence(
        &self,
        branch_id: Option<String>,
    ) -> Result<TeamPresenceView, MadarError> {
        self.inner
            .manager_team_presence(branch_id)
            .await
            .map_err(MadarError::from)
    }

    /// The approvals queue, or any slice of it.
    pub async fn manager_requests(
        &self,
        status: Option<String>,
        kind: Option<String>,
    ) -> Result<Vec<StaffRequestView>, MadarError> {
        self.inner
            .manager_requests(status, kind)
            .await
            .map_err(MadarError::from)
    }

    /// Approve or reject a request.
    pub async fn manager_decide_request(
        &self,
        request_id: String,
        approve: bool,
        note: Option<String>,
        is_paid: Option<bool>,
    ) -> Result<StaffRequestView, MadarError> {
        self.inner
            .manager_decide_request(request_id, approve, note, is_paid)
            .await
            .map_err(MadarError::from)
    }

    /// The roster, optionally filtered by a search string.
    pub async fn manager_employees(
        &self,
        search: Option<String>,
    ) -> Result<Vec<EmployeeView>, MadarError> {
        self.inner
            .manager_employees(search)
            .await
            .map_err(MadarError::from)
    }

    /// Payroll periods, newest first.
    pub async fn manager_payroll_periods(&self) -> Result<Vec<PayrollPeriodView>, MadarError> {
        self.inner
            .manager_payroll_periods()
            .await
            .map_err(MadarError::from)
    }

    /// What generating this period would pay.
    pub async fn manager_payroll_preview(
        &self,
        period_id: String,
    ) -> Result<Vec<PayrollLineView>, MadarError> {
        self.inner
            .manager_payroll_preview(period_id)
            .await
            .map_err(MadarError::from)
    }

    /// Approve the run — generate the payslips.
    pub async fn manager_payroll_generate(&self, period_id: String) -> Result<i64, MadarError> {
        self.inner
            .manager_payroll_generate(period_id)
            .await
            .map_err(MadarError::from)
    }

    /// Move a generated period to `paid` or `closed`.
    pub async fn manager_payroll_set_status(
        &self,
        period_id: String,
        status: String,
    ) -> Result<PayrollPeriodView, MadarError> {
        self.inner
            .manager_payroll_set_status(period_id, status)
            .await
            .map_err(MadarError::from)
    }

    // ── Payroll adjustments ──────────────────────────────────

    /// Bonuses (`deductions: false`) or deductions (`true`) over a window.
    pub async fn manager_adjustments(
        &self,
        deductions: bool,
        user_id: Option<String>,
        from: Option<String>,
        to: Option<String>,
        base_salary_minor: i64,
    ) -> Result<Vec<AdjustmentView>, MadarError> {
        self.inner
            .manager_adjustments(deductions, user_id, from, to, base_salary_minor)
            .await
            .map_err(MadarError::from)
    }

    /// Add a bonus or a manual deduction.
    pub async fn manager_create_adjustment(
        &self,
        deductions: bool,
        user_id: String,
        amount_minor: i64,
        reason: String,
        effective_date: String,
    ) -> Result<AdjustmentView, MadarError> {
        self.inner
            .manager_create_adjustment(deductions, user_id, amount_minor, reason, effective_date)
            .await
            .map_err(MadarError::from)
    }

    /// Delete a hand-entered adjustment (never a rule-generated one).
    pub async fn manager_delete_adjustment(
        &self,
        deductions: bool,
        id: String,
    ) -> Result<(), MadarError> {
        self.inner
            .manager_delete_adjustment(deductions, id)
            .await
            .map_err(MadarError::from)
    }

    /// Charge a different figure than the rule computed; the original is kept.
    pub async fn manager_override_deduction(
        &self,
        id: String,
        amount_minor: i64,
        reason: String,
    ) -> Result<AdjustmentView, MadarError> {
        self.inner
            .manager_override_deduction(id, amount_minor, reason)
            .await
            .map_err(MadarError::from)
    }

    /// Cancel a deduction without erasing it.
    pub async fn manager_waive_deduction(
        &self,
        id: String,
        reason: String,
    ) -> Result<AdjustmentView, MadarError> {
        self.inner
            .manager_waive_deduction(id, reason)
            .await
            .map_err(MadarError::from)
    }

    /// Every salary advance in the org.
    pub async fn manager_advances(&self) -> Result<Vec<SalaryAdvanceView>, MadarError> {
        self.inner
            .manager_advances()
            .await
            .map_err(MadarError::from)
    }

    /// Approve or reject an advance request.
    pub async fn manager_decide_advance(
        &self,
        advance_id: String,
        approve: bool,
        note: Option<String>,
    ) -> Result<SalaryAdvanceView, MadarError> {
        self.inner
            .manager_decide_advance(advance_id, approve, note)
            .await
            .map_err(MadarError::from)
    }
}
