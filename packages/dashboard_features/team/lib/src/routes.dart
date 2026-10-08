/// The team area's pages (`/staff/setup`, `/staff/employees`,
/// `/staff/attendance`, `/staff/shifts`, `/staff/team`, `/staff/approvals`,
/// `/staff/schedule`, `/staff/requests`, `/staff/payroll`, `/staff/reports`,
/// `/staff/rules`) with the web's capabilities (any-of, from the generated nav
/// and settings nav) and module. A route without a builder shows the shell's
/// placeholder until its page lands.
library;

import 'package:dashboard_core/dashboard_core.dart';

const List<DashRoute> teamRoutes = [
  DashRoute(
    path: '/staff/setup',
    titleKey: 'nav.staffSetup',
    titleFallback: 'Set-up',
    caps: [Cap.hrRulesEdit],
    module: OrgModule.dawam,
    setupOnly: true,
  ),
  DashRoute(
    path: '/staff/employees',
    titleKey: 'nav.employees',
    titleFallback: 'Employees',
    caps: [Cap.hrStaffRead],
    module: OrgModule.dawam,
  ),
  DashRoute(
    path: '/staff/attendance',
    titleKey: 'nav.attendance',
    titleFallback: 'Attendance',
    caps: [Cap.hrAttendanceRead],
    module: OrgModule.dawam,
  ),
  DashRoute(
    path: '/staff/shifts',
    titleKey: 'nav.workShifts',
    titleFallback: 'Work shifts',
    caps: [Cap.hrScheduleRead],
    module: OrgModule.dawam,
  ),
  DashRoute(
    path: '/staff/team',
    titleKey: 'nav.team',
    titleFallback: 'Team',
    caps: [Cap.hrAttendanceRead],
    module: OrgModule.dawam,
  ),
  DashRoute(
    path: '/staff/approvals',
    titleKey: 'nav.approvals',
    titleFallback: 'Approvals',
    caps: [
      Cap.hrLeaveEdit,
      Cap.hrAttendanceEdit,
      Cap.hrAdvancesDecide,
      Cap.hrScheduleEdit,
      Cap.hrShiftCoverConfirm,
      Cap.hrOvertimeApprove,
      Cap.hrPayrollRun,
    ],
    module: OrgModule.dawam,
  ),
  DashRoute(
    path: '/staff/schedule',
    titleKey: 'nav.schedule',
    titleFallback: 'Schedule',
    caps: [Cap.hrScheduleRead],
    module: OrgModule.dawam,
  ),
  DashRoute(
    path: '/staff/requests',
    titleKey: 'nav.requests',
    titleFallback: 'Requests',
    caps: [Cap.hrLeaveRead],
    module: OrgModule.dawam,
  ),
  DashRoute(
    path: '/staff/payroll',
    titleKey: 'nav.payroll',
    titleFallback: 'Payroll',
    caps: [Cap.hrPayrollRead, Cap.hrPayrollRun],
    module: OrgModule.dawam,
  ),
  DashRoute(
    path: '/staff/reports',
    titleKey: 'nav.staffReports',
    titleFallback: 'Reports',
    caps: [Cap.hrAttendanceRead, Cap.hrPayrollRead],
    module: OrgModule.dawam,
  ),
  DashRoute(
    path: '/staff/rules',
    titleKey: 'nav.attendanceRules',
    titleFallback: 'Attendance rules',
    caps: [Cap.hrRulesEdit, Cap.hrRulesView],
    module: OrgModule.dawam,
  ),
];
