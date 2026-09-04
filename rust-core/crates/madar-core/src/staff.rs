//! Employee self-service — the staff app's whole domain.
//!
//! Two surfaces, one binary. `/staff/me/*` is what an employee has over their
//! OWN record. The `manager_*` calls are the other half — team presence, the
//! approvals queue, the roster, and the payroll run — and they are gated by the
//! server's permission check, not by which build you installed. Hiding a tab is
//! a courtesy; the backend re-checks every one of these on every call.
//!
//! THE SERVER DECIDES. The app sends coordinates and nothing else — not the time,
//! not the distance, not whether the arrival counts as late. Every one of those
//! is computed backend-side (see `src/staff/attendance.rs` there), because a
//! phone can lie about all three. What the app gets back is already adjudicated,
//! so these `View` types are projections for rendering, not inputs to a rule.
//!
//! Money is integer minor units (piastres) end to end; the host formats it with
//! the session currency, exactly like `reports`.

use madar_api::models;
use serde::{Deserialize, Serialize};

/// One clocked (or adjudicated) day.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct AttendanceRecordView {
    pub id: String,
    /// `present` | `late` | `absent` | `half_day` | `on_leave`.
    pub status: String,
    /// The day in the BRANCH's timezone, as decided by the server.
    pub business_date: String,
    pub work_shift_name: String,
    /// RFC3339, or empty when there is no stamp (an absence has neither).
    pub check_in_at: String,
    pub check_out_at: String,
    /// Metres from the branch when clocking in; `-1` when not measured.
    pub check_in_distance_meters: i64,
    pub late_minutes: i64,
    pub overtime_minutes: i64,
    pub worked_minutes: i64,
    /// True when an admin entered or corrected this row by hand.
    pub is_manual: bool,
    pub notes: String,
}

/// A shift the employee is expected to work today.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ScheduledShiftView {
    pub work_shift_id: String,
    pub name: String,
    pub scheduled_start_at: String,
    pub scheduled_end_at: String,
    pub grace_minutes: i64,
}

/// Everything the home screen needs in one round trip.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct TodayView {
    pub business_date: String,
    /// The still-open record when currently clocked in.
    pub open_record: Option<AttendanceRecordView>,
    pub closed_records: Vec<AttendanceRecordView>,
    /// Empty means a rest day.
    pub scheduled: Vec<ScheduledShiftView>,
    pub can_check_in: bool,
    pub can_check_out: bool,
    /// Server-authored explanation, safe to show verbatim. Empty when unblocked.
    pub blocked_reason: String,
    /// WHERE to clock in — resolved server-side, never picked in the app. Empty
    /// when the server cannot tell, in which case `can_check_in` is false too.
    pub branch_id: String,
    /// That branch's name, so the geofence chip can say where it is.
    pub branch_name: String,
}

/// One request the employee filed — of any kind.
///
/// The five kinds share one shape because each is an excused window inside a day:
/// a late arrival is open at the start, an early departure open at the end, a
/// permission closed at both, and leave/mission cover whole days. See the
/// backend's `staff_requests` migration.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct StaffRequestView {
    pub id: String,
    /// Who filed it. Empty on `/staff/me/*` (it is always you); set on the
    /// manager's queue, where it is the first thing read.
    pub user_name: String,
    /// `leave` | `late_arrival` | `early_departure` | `excuse` | `mission`.
    pub kind: String,
    pub on_date: String,
    /// Empty unless the request spans days (`leave`, `mission`).
    pub end_date: String,
    /// `HH:MM` local wall clock; empty means open to the shift boundary.
    pub from_time: String,
    pub to_time: String,
    pub leave_type_name: String,
    pub is_half_day: bool,
    pub title: String,
    /// `pending` | `approved` | `rejected` | `cancelled`.
    pub status: String,
    /// Whether the excused time is paid. `None` until the manager decides.
    pub is_paid: Option<bool>,
    pub reason: String,
    pub decision_note: String,
}

/// Remaining entitlement for one leave type in one year.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct LeaveBalanceView {
    /// Needed to FILE a leave request: the balance list is the app's only source
    /// of leave types, so it has to carry the id and not just the name.
    pub leave_type_id: String,
    pub leave_type_name: String,
    pub year: i64,
    /// Days, ×100 so a half day survives the FFI boundary as an integer.
    pub entitled_centidays: i64,
    pub used_centidays: i64,
    pub remaining_centidays: i64,
}

/// One month's pay, as frozen at generation time.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct PayslipView {
    pub id: String,
    pub base_minor: i64,
    pub overtime_minor: i64,
    pub bonuses_minor: i64,
    pub deductions_minor: i64,
    pub advance_installment_minor: i64,
    pub net_minor: i64,
    /// Days, ×100 (see [`LeaveBalanceView`]).
    pub worked_centidays: i64,
    pub absent_centidays: i64,
    pub late_minutes: i64,
    pub overtime_minutes: i64,
    /// RFC3339.
    pub generated_at: String,
    /// The period this covers, e.g. "July 2026". A payslip labelled only by its
    /// generation date is unreadable — two months run on the same day would look
    /// identical to the employee.
    pub period_name: String,
    pub period_start: String,
    pub period_end: String,
}

/// A salary advance and what is still owed on it.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SalaryAdvanceView {
    pub id: String,
    pub amount_minor: i64,
    pub installments: i64,
    pub monthly_installment_minor: i64,
    pub remaining_minor: i64,
    /// `pending` | `approved` | `rejected` | `settled` | `cancelled`.
    pub status: String,
    pub reason: String,
}

// ── Conversions ──────────────────────────────────────────────────
//
// The generated client models everything nullable as `Option<Option<T>>` (the
// outer for "absent from the JSON", the inner for an explicit null), and dates as
// typed values. Flattening happens exactly once, here, so no caller has to.

fn flat(v: Option<Option<String>>) -> String {
    v.flatten().unwrap_or_default()
}

fn dt(v: Option<Option<chrono::DateTime<chrono::FixedOffset>>>) -> String {
    v.flatten().map(|d| d.to_rfc3339()).unwrap_or_default()
}

/// Days → centidays. The API sends fractional days (0.5 for a half day) as a
/// float; the FFI surface is integers only, so scale rather than truncate.
fn centidays(v: f64) -> i64 {
    (v * 100.0).round() as i64
}

pub(crate) fn record_view(r: models::AttendanceRecord) -> AttendanceRecordView {
    AttendanceRecordView {
        id: r.id.to_string(),
        status: r.status,
        business_date: r.business_date.to_string(),
        work_shift_name: flat(r.work_shift_name),
        check_in_at: dt(r.check_in_at),
        check_out_at: dt(r.check_out_at),
        // -1, not 0: "not measured" and "standing on the exact centre" are
        // different facts, and 0 would read as the latter.
        check_in_distance_meters: r
            .check_in_distance_meters
            .flatten()
            .map(|d| d.round() as i64)
            .unwrap_or(-1),
        late_minutes: r.late_minutes as i64,
        overtime_minutes: r.overtime_minutes as i64,
        worked_minutes: r.worked_minutes as i64,
        is_manual: r.is_manual,
        notes: flat(r.notes),
    }
}

pub(crate) fn shift_view(s: models::ResolvedShift) -> ScheduledShiftView {
    ScheduledShiftView {
        work_shift_id: s.work_shift_id.to_string(),
        name: s.name,
        scheduled_start_at: s.scheduled_start_at.to_rfc3339(),
        scheduled_end_at: s.scheduled_end_at.to_rfc3339(),
        grace_minutes: s.grace_minutes as i64,
    }
}

pub(crate) fn today_view(t: models::MyAttendanceToday) -> TodayView {
    TodayView {
        business_date: t.business_date.to_string(),
        open_record: t.open_record.flatten().map(|r| record_view(*r)),
        closed_records: t.closed_records.into_iter().map(record_view).collect(),
        scheduled: t.scheduled.into_iter().map(shift_view).collect(),
        can_check_in: t.can_check_in,
        can_check_out: t.can_check_out,
        blocked_reason: flat(t.blocked_reason),
        branch_name: flat(t.branch_name),
        branch_id: t
            .branch_id
            .flatten()
            .map(|b| b.to_string())
            .unwrap_or_default(),
    }
}

pub(crate) fn request_view(r: models::StaffRequest) -> StaffRequestView {
    // Times arrive as `HH:MM:SS`; the app only ever shows minutes.
    let hhmm = |v: Option<Option<String>>| flat(v).get(..5).map(str::to_string).unwrap_or_default();
    StaffRequestView {
        id: r.id.to_string(),
        user_name: flat(r.user_name),
        kind: r.kind,
        on_date: r.on_date.to_string(),
        end_date: r
            .end_date
            .flatten()
            .map(|d| d.to_string())
            .unwrap_or_default(),
        from_time: hhmm(r.from_time),
        to_time: hhmm(r.to_time),
        leave_type_name: flat(r.leave_type_name),
        is_half_day: r.is_half_day,
        title: flat(r.title),
        status: r.status,
        is_paid: r.is_paid.flatten(),
        reason: flat(r.reason),
        decision_note: flat(r.decision_note),
    }
}

pub(crate) fn leave_balance_view(b: models::LeaveBalance) -> LeaveBalanceView {
    LeaveBalanceView {
        leave_type_id: b.leave_type_id.to_string(),
        leave_type_name: flat(b.leave_type_name),
        year: b.year as i64,
        entitled_centidays: centidays(b.entitled_days),
        used_centidays: centidays(b.used_days),
        remaining_centidays: centidays(b.remaining_days),
    }
}

pub(crate) fn payslip_view(p: models::Payslip) -> PayslipView {
    PayslipView {
        id: p.id.to_string(),
        base_minor: p.base_salary_piastres,
        overtime_minor: p.overtime_piastres,
        bonuses_minor: p.bonuses_piastres,
        deductions_minor: p.deductions_piastres,
        advance_installment_minor: p.advance_installment_piastres,
        net_minor: p.net_piastres,
        worked_centidays: centidays(p.worked_days),
        absent_centidays: centidays(p.absent_days),
        late_minutes: p.late_minutes as i64,
        overtime_minutes: p.overtime_minutes as i64,
        generated_at: p.generated_at.to_rfc3339(),
        period_name: flat(p.period_name),
        period_start: p
            .period_start
            .flatten()
            .map(|d| d.to_string())
            .unwrap_or_default(),
        period_end: p
            .period_end
            .flatten()
            .map(|d| d.to_string())
            .unwrap_or_default(),
    }
}

pub(crate) fn advance_view(a: models::SalaryAdvance) -> SalaryAdvanceView {
    SalaryAdvanceView {
        id: a.id.to_string(),
        amount_minor: a.amount_piastres,
        installments: a.installments as i64,
        monthly_installment_minor: a.monthly_installment_piastres,
        remaining_minor: a.remaining_piastres,
        status: a.status,
        reason: flat(a.reason),
    }
}

// ── Manager surface ───────────────────────────────────────────

/// One person's state right now, for the team screen.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct PresenceRowView {
    pub user_id: String,
    pub name: String,
    pub job_title: String,
    pub branch_name: String,
    /// `in` | `late` | `absent` | `on_leave` | `off` | `done`.
    pub state: String,
    pub check_in_at: String,
    pub check_out_at: String,
    pub late_minutes: i64,
    pub worked_minutes: i64,
    pub scheduled_minutes: i64,
}

/// The team's state right now, plus the day's labour against plan.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct TeamPresenceView {
    pub business_date: String,
    pub present: i64,
    /// Deliberately not `late`: that is a Dart keyword, and the generated
    /// binding would surface it as the unreadable `late_`.
    pub late_count: i64,
    pub absent: i64,
    pub on_leave: i64,
    pub worked_minutes: i64,
    pub planned_minutes: i64,
    pub rows: Vec<PresenceRowView>,
}

/// A roster entry — the manager's list of who works here.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct EmployeeView {
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

/// A day the employee is rostered for.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ScheduledDayView {
    pub date: String,
    pub branch_name: String,
    /// Empty = a rest day.
    pub shifts: Vec<ScheduledShiftView>,
}

/// A payroll period as the run screen shows it.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct PayrollPeriodView {
    pub id: String,
    pub name: String,
    pub start_date: String,
    pub end_date: String,
    /// `draft` | `generated` | `paid` | `closed`.
    pub status: String,
    pub employee_count: i64,
    pub total_net_minor: i64,
}

/// One line of a payroll run — computed, not yet written.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct PayrollLineView {
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
    /// Days, ×100 (see [`LeaveBalanceView`]).
    pub worked_centidays: i64,
    pub absent_centidays: i64,
    /// Set when the line needs a human's eye before the run is approved —
    /// an absence, or a day with no check-out. Empty when it is clean.
    pub exception: String,
}

/// A bonus or a deduction — the same shape with opposite signs.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct AdjustmentView {
    pub id: String,
    pub user_id: String,
    pub user_name: String,
    /// Already resolved: a percent-of-base row arrives here as piastres.
    pub amount_minor: i64,
    pub reason: String,
    pub effective_date: String,
    /// `manual` | `late_penalty` | `absence`. Only `manual` rows are deletable.
    pub source: String,
    pub status: String,
    /// What the RULE computed before a human touched it. `0` when nothing was
    /// overridden — the UI shows the strike-through only when this differs.
    pub original_amount_minor: i64,
    pub overridden: bool,
    pub override_reason: String,
    /// A waived deduction keeps its amount and stays visible; payroll skips it.
    pub waived: bool,
    pub waive_reason: String,
}

pub(crate) fn adjustment_view(
    a: models::PayrollAdjustment,
    base_salary_minor: i64,
) -> AdjustmentView {
    // A row is either a flat amount or a percentage of base. Resolving it HERE
    // rather than in the UI keeps one implementation of that rule, and it is the
    // same one payroll uses.
    let amount = a.amount_piastres.flatten().unwrap_or_else(|| {
        a.percent_of_base
            .flatten()
            .map(|pct| ((base_salary_minor as f64) * pct / 100.0).round() as i64)
            .unwrap_or(0)
    });
    AdjustmentView {
        id: a.id.to_string(),
        user_id: a.user_id.to_string(),
        user_name: flat(a.user_name),
        amount_minor: amount,
        reason: a.reason,
        effective_date: a.effective_date.to_string(),
        source: a.source,
        status: a.status,
        original_amount_minor: a.original_amount_piastres.flatten().unwrap_or(0),
        overridden: a.overridden_at.flatten().is_some(),
        override_reason: flat(a.override_reason),
        waived: a.waived_at.flatten().is_some(),
        waive_reason: flat(a.waive_reason),
    }
}

pub(crate) fn presence_view(r: models::PresenceRow) -> PresenceRowView {
    PresenceRowView {
        user_id: r.user_id.to_string(),
        name: r.user_name,
        job_title: flat(r.job_title),
        branch_name: flat(r.branch_name),
        state: r.state,
        check_in_at: dt(r.check_in_at),
        check_out_at: dt(r.check_out_at),
        late_minutes: r.late_minutes as i64,
        worked_minutes: r.worked_minutes as i64,
        scheduled_minutes: r.scheduled_minutes,
    }
}

pub(crate) fn team_presence_view(p: models::TeamPresence) -> TeamPresenceView {
    TeamPresenceView {
        business_date: p.business_date.to_string(),
        present: p.present,
        late_count: p.late,
        absent: p.absent,
        on_leave: p.on_leave,
        worked_minutes: p.worked_minutes,
        planned_minutes: p.planned_minutes,
        rows: p.rows.into_iter().map(presence_view).collect(),
    }
}

pub(crate) fn employee_view(e: models::Employee) -> EmployeeView {
    EmployeeView {
        user_id: e.user_id.to_string(),
        name: e.name,
        job_title: flat(e.job_title),
        department_name: flat(e.department_name),
        employment_status: e.employment_status,
        phone: flat(e.phone),
        employee_number: flat(e.employee_code),
        hire_date: e
            .hire_date
            .flatten()
            .map(|d| d.to_string())
            .unwrap_or_default(),
        // `None` when the caller lacks `payroll:read` — the roster is visible to
        // more people than salaries are, so an unreadable salary is 0, not an
        // error that blanks the whole screen.
        base_salary_minor: e.base_salary_piastres.flatten().unwrap_or(0),
    }
}

pub(crate) fn scheduled_day_view(d: models::ScheduledDay) -> ScheduledDayView {
    ScheduledDayView {
        date: d.date.to_string(),
        branch_name: flat(d.branch_name),
        shifts: d.shifts.into_iter().map(shift_view).collect(),
    }
}

pub(crate) fn period_view(p: models::PayrollPeriod) -> PayrollPeriodView {
    PayrollPeriodView {
        id: p.id.to_string(),
        name: p.name,
        start_date: p.start_date.to_string(),
        end_date: p.end_date.to_string(),
        status: p.status,
        employee_count: p.employee_count as i64,
        total_net_minor: p.total_net_piastres,
    }
}

pub(crate) fn payroll_line_view(c: models::ComputedPayslip) -> PayrollLineView {
    // An exception is anything a manager should look at before approving the
    // run. Absence outranks a missing punch because it costs more.
    let absent = centidays(c.absent_days);
    let exception = if absent > 0 {
        "absence".to_string()
    } else {
        String::new()
    };
    PayrollLineView {
        user_id: c.user_id.to_string(),
        name: c.name,
        worked_minutes: 0,
        overtime_minutes: c.overtime_minutes,
        late_minutes: c.late_minutes,
        base_minor: c.base_piastres,
        overtime_minor: c.overtime_piastres,
        bonuses_minor: c.bonuses_piastres,
        deductions_minor: c.deductions_piastres,
        advance_minor: c.advance_installment_piastres,
        net_minor: c.net_piastres,
        worked_centidays: centidays(c.worked_days),
        absent_centidays: absent,
        exception,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fractional_days_survive_as_centidays() {
        assert_eq!(centidays(0.5), 50);
        assert_eq!(centidays(21.0), 2100);
        assert_eq!(centidays(0.0), 0);
    }

    #[test]
    fn centidays_round_rather_than_truncate() {
        // 1/3 of a day must not silently become 33 twice and lose a hundredth.
        assert_eq!(centidays(0.335), 34);
        assert_eq!(centidays(0.334), 33);
    }

    #[test]
    fn a_missing_optional_string_flattens_to_empty() {
        assert_eq!(flat(None), "");
        assert_eq!(flat(Some(None)), "");
        assert_eq!(flat(Some(Some("x".into()))), "x");
    }
}
