/// The team pages' route prefetches ([DashRoute.prefetch]): each warms the
/// reads its page watches on mount, with the page's own keys (the scope's
/// branch, the page's default window on the active zone's calendar, the
/// person's rights), so opening the page answers from the cache.
///
/// A page's remembered filters (`DashRememberedState`) are the page's own
/// state; the warm is the page's default view, the one a first visit shows.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart' show dashParseYmd, dashYmd;
import 'package:dashboard_kit/dashboard_kit.dart'
    show DashQuickRange, dashQuickRange;

import 'approvals/approvals_providers.dart';
import 'attendance/attendance_providers.dart';
import 'employees/employees_providers.dart';
import 'payroll/payroll_data.dart';
import 'requests/requests_providers.dart';
import 'rules/rules_data.dart';
import 'schedule/schedule_data.dart' show monthOf;
import 'schedule/schedule_providers.dart';
import 'shifts/shifts_providers.dart';
import 'shared/setup_data.dart';
import 'shared/team_format.dart' show isoDaysFromToday;
import 'shared/week.dart';
import 'team_board/team_board_providers.dart';
import 'team_reports/team_reports_page.dart' show reportReadOf, reportTabs;
import 'team_reports/team_reports_providers.dart' show ReportQuery;

/// Today (plus [days]) on the active zone's calendar: `teamTodayIsoOf`.
String _today(DashPrefetcher warm, [int days = 0]) => isoDaysFromToday(
  days,
  timezone: warm.read(activeTimezoneProvider),
  now: warm.read(clockProvider)(),
);

const _everyone = (status: null, departmentId: null);

/// `/staff/setup`: the checklist's three reads.
void prefetchTeamSetup(DashPrefetcher warm, Scope s) {
  warm(setupActiveEmployeesProvider);
  warm(setupWorkShiftsProvider);
  warm(setupAttendanceSettingsProvider);
}

/// `/staff/employees`: the departments and the unfiltered list.
void prefetchEmployees(DashPrefetcher warm, Scope s) {
  warm(staffDepartmentsProvider);
  warm(employeesReadFor(_everyone));
}

/// `/staff/attendance`: the last 7 days at the scope's branch, the people
/// picker and the rules.
void prefetchAttendance(DashPrefetcher warm, Scope s) {
  final AttendanceQuery k = (
    from: _today(warm, -6),
    to: _today(warm),
    branchId: s.branchId,
    status: null,
    employeeId: null,
  );
  warm(employeesListProvider(_everyone));
  warm(attendanceListProvider(k));
  warm(attendanceSummaryProvider(k));
  warm(staffAttendanceSettingsProvider);
}

/// `/staff/shifts`: the work shifts, the active people and the roster.
void prefetchWorkShifts(DashPrefetcher warm, Scope s) {
  warm(staffWorkShiftsProvider);
  warm(staffActiveEmployeesProvider);
  warm(shiftsRosterProvider);
  // The shift cards' branch names (the shell's list, warmed in case the
  // shell let it go).
  warm(branchesProvider);
}

/// `/staff/team`: presence and flags at the scope's branch (with the right
/// to read attendance), then today's records once presence names the
/// business day (with the right to punch for others).
void prefetchTeamBoard(DashPrefetcher warm, Scope s) {
  final authz = warm.read(authzProvider);
  if (!authz.can(Cap.hrAttendanceRead)) return;
  final b = s.branchId;
  final presence = teamPresenceProvider(b);
  warm(presence);
  warm(teamFlagsProvider(b));
  if (!authz.can(Cap.hrAttendancePunchOthers)) return;
  warm.read(presence.future).then((p) {
    final day = p.businessDate;
    warm(teamTodayRecordsProvider((day: day, branchId: b)));
  }, onError: (Object _) {});
}

/// `/staff/approvals`: every pending list this person may decide.
void prefetchApprovals(DashPrefetcher warm, Scope s) {
  final authz = warm.read(authzProvider);
  final requests = authz.canAny(const [Cap.hrLeaveEdit, Cap.hrAttendanceEdit]);
  if (requests) {
    warm(approvalsRequestsProvider);
    if (warm.read(currentSessionProvider) != null) {
      warm(employeesListProvider(_everyone));
    }
  }
  if (authz.can(Cap.hrAdvancesDecide)) warm(approvalsAdvancesProvider);
  if (authz.can(Cap.hrScheduleEdit)) {
    warm(approvalsSwapsProvider);
    warm(
      approvalsClaimsProvider((
        from: _today(warm, -366),
        to: _today(warm, 366),
      )),
    );
  }
  if (authz.can(Cap.hrShiftCoverConfirm)) {
    warm(approvalsAttendanceProvider(pendingCovers));
  }
  if (authz.can(Cap.hrOvertimeApprove)) {
    warm(approvalsAttendanceProvider(pendingOvertime));
  }
  if (authz.can(Cap.hrPayrollRun)) warm(approvalsPayLinesProvider);
}

/// `/staff/schedule`: this week's roster, the 45-day look-ahead, the
/// suggestions (with the right to edit) and the fairness cards (with the
/// roster settings right), at the scope's branch or the first one.
void prefetchSchedule(DashPrefetcher warm, Scope s) {
  final authz = warm.read(authzProvider);
  if (!authz.can(Cap.hrScheduleRead)) return;
  final branches = warm.read(branchesProvider).value;
  final branch =
      s.branchId ??
      (branches == null || branches.isEmpty ? null : branches.first.id);
  if (branch == null) return;
  final week = weekStartOf(_today(warm));
  warm(
    scheduleRosterProvider((
      branchId: branch,
      from: week,
      to: addDays(week, 6),
    )),
  );
  warm(
    scheduleRosterProvider((
      branchId: branch,
      from: _today(warm),
      to: _today(warm, 45),
    )),
  );
  if (authz.can(Cap.hrScheduleEdit)) {
    warm(scheduleSuggestionsProvider((branchId: branch, weekStart: week)));
  }
  if (authz.can(Cap.hrRosterSettings)) {
    warm(scheduleFairnessProvider(monthOf(week)));
    warm(scheduleFairnessAuditsProvider);
  }
}

/// `/staff/requests`: the pending list and the people.
void prefetchRequests(DashPrefetcher warm, Scope s) {
  warm(requestsReadFor((status: 'pending', kind: null)));
  warm(employeesListProvider(_everyone));
}

/// `/staff/payroll`: this month, the people, and the open tab's list.
void prefetchPayroll(DashPrefetcher warm, Scope s) {
  warm(payrollCurrentProvider);
  // The branch names on the lines (the shell's list).
  warm(branchesProvider);
  if (!warm.read(payrollCanReadProvider)) return;
  warm(payrollPeopleProvider);
  switch (warm.read(payrollViewProvider).tab) {
    case PayrollTab.lines:
      warm(payrollAdjustmentsProvider);
    case PayrollTab.advances:
      warm(payrollAdvancesProvider);
    case PayrollTab.expenses:
      warm(payrollExpensesProvider(s.branchId));
    default:
      break;
  }
}

/// `/staff/reports`: the first tab this person sees, over this pay period
/// (from the rules' period start day, read first).
void prefetchStaffReports(DashPrefetcher warm, Scope s) {
  final authz = warm.read(authzProvider);
  final tabs = reportTabs(
    attendance: authz.can(Cap.hrAttendanceRead),
    payroll: authz.can(Cap.hrPayrollRead),
    pos: warm.read(orgModulesProvider).has('pos'),
  );
  if (tabs.isEmpty) return;
  final today = dashParseYmd(_today(warm))!;
  void warmTab(int periodStartDay) {
    final r = dashQuickRange(
      DashQuickRange.thisPeriod,
      today: today,
      periodStartDay: periodStartDay,
    );
    final ReportQuery k = (
      from: dashYmd(r.from),
      to: dashYmd(r.to),
      branchId: s.branchId,
    );
    warm(reportReadOf(tabs.first, k));
  }

  warm(staffAttendanceSettingsProvider);
  warm
      .read(staffAttendanceSettingsProvider.future)
      .then(
        (a) => warmTab(a.periodStartDay),
        onError: (Object _) => warmTab(1),
      );
}

/// `/staff/rules`: the business's rules and every branch's own (with the
/// right to view them).
void prefetchRules(DashPrefetcher warm, Scope s) {
  final authz = warm.read(authzProvider);
  if (!authz.ready) return;
  if (!authz.can(Cap.hrRulesEdit) && !authz.can(Cap.hrRulesView)) return;
  warm(rulesBranchesProvider);
  warm(rulesSettingsFor(null));
}
