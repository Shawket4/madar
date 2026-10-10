/// The team area's pages (`/staff/setup`, `/staff/employees`,
/// `/staff/attendance`, `/staff/shifts`, `/staff/team`, `/staff/approvals`,
/// `/staff/schedule`, `/staff/requests`, `/staff/payroll`, `/staff/reports`,
/// `/staff/rules`), every one in module `dawam`.
///
/// Capabilities as the web: its `/staff/*` routes carry NO guard
/// (`routes/_app/staff/*.tsx`), so none is set here. The sidebar and the
/// command palette show each leaf by the generated nav's capabilities
/// (TEAM-ALL-002/003/004). Seven pages refuse in-page with their OWN title
/// and `who` words (`TeamPageGate`, TEAM-ALL-007): Set-up, Team, Approvals,
/// Schedule, Payroll, Reports and Rules; Employees, Attendance, Work shifts
/// and Requests have no in-page guard and let their reads 403 into each
/// list's error state.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'approvals/approvals_page.dart';
import 'attendance/attendance_page.dart';
import 'employees/employees_page.dart';
import 'payroll/payroll_page.dart';
import 'requests/requests_page.dart';
import 'rules/rules_page.dart';
import 'schedule/schedule_page.dart';
import 'shifts/shifts_page.dart';
import 'team_board/team_board_page.dart';
import 'team_reports/team_reports_page.dart';
import 'team_setup/team_setup_page.dart';

const List<DashRoute> teamRoutes = [
  DashRoute(
    path: '/staff/setup',
    titleKey: 'nav.staffSetup',
    titleFallback: 'Set-up',
    module: OrgModule.dawam,
    // The nav shows it only while the checklist is incomplete; the page
    // itself opens for whoever holds `hr.rules.edit`.
    setupOnly: true,
    builder: _teamSetupPage,
  ),
  DashRoute(
    path: '/staff/employees',
    titleKey: 'nav.employees',
    titleFallback: 'Employees',
    module: OrgModule.dawam,
    builder: _employeesPage,
  ),
  DashRoute(
    path: '/staff/attendance',
    titleKey: 'nav.attendance',
    titleFallback: 'Attendance',
    module: OrgModule.dawam,
    builder: _attendancePage,
  ),
  DashRoute(
    path: '/staff/shifts',
    titleKey: 'nav.workShifts',
    titleFallback: 'Work shifts',
    module: OrgModule.dawam,
    builder: _workShiftsPage,
  ),
  DashRoute(
    path: '/staff/team',
    titleKey: 'nav.team',
    titleFallback: 'Team',
    module: OrgModule.dawam,
    builder: _teamBoardPage,
  ),
  DashRoute(
    path: '/staff/approvals',
    titleKey: 'nav.approvals',
    titleFallback: 'Approvals',
    module: OrgModule.dawam,
    builder: _approvalsPage,
  ),
  DashRoute(
    path: '/staff/schedule',
    titleKey: 'nav.schedule',
    titleFallback: 'Schedule',
    module: OrgModule.dawam,
    builder: _schedulePage,
  ),
  DashRoute(
    path: '/staff/requests',
    titleKey: 'nav.requests',
    titleFallback: 'Requests',
    module: OrgModule.dawam,
    builder: _requestsInboxPage,
  ),
  DashRoute(
    path: '/staff/payroll',
    titleKey: 'nav.payroll',
    titleFallback: 'Payroll',
    module: OrgModule.dawam,
    builder: _payrollPage,
  ),
  DashRoute(
    path: '/staff/reports',
    titleKey: 'nav.staffReports',
    titleFallback: 'Reports',
    module: OrgModule.dawam,
    builder: _staffReportsPage,
  ),
  DashRoute(
    path: '/staff/rules',
    titleKey: 'nav.attendanceRules',
    titleFallback: 'Attendance rules',
    module: OrgModule.dawam,
    builder: _attendanceRulesPage,
  ),
];

// Top-level builders: a tear-off is a constant, so the routes (and the
// area) stay `const`.
Widget _teamSetupPage(BuildContext context, GoRouterState state) =>
    const TeamSetupPage();
Widget _employeesPage(BuildContext context, GoRouterState state) =>
    const EmployeesPage();
Widget _attendancePage(BuildContext context, GoRouterState state) =>
    const AttendancePage();
Widget _workShiftsPage(BuildContext context, GoRouterState state) =>
    const WorkShiftsPage();
Widget _teamBoardPage(BuildContext context, GoRouterState state) =>
    const TeamBoardPage();
Widget _approvalsPage(BuildContext context, GoRouterState state) =>
    const ApprovalsPage();
Widget _schedulePage(BuildContext context, GoRouterState state) =>
    const SchedulePage();
Widget _requestsInboxPage(BuildContext context, GoRouterState state) =>
    const RequestsInboxPage();
Widget _payrollPage(BuildContext context, GoRouterState state) =>
    const PayrollPage();
Widget _staffReportsPage(BuildContext context, GoRouterState state) =>
    const StaffReportsPage();
Widget _attendanceRulesPage(BuildContext context, GoRouterState state) =>
    const AttendanceRulesPage();
