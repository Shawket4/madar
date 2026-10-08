/// The dashboard's team area: its pages ([teamRoutes]), its mock backend
/// ([registerTeamMocks]) and its i18n supplement, as [teamArea].
library;

import 'package:dashboard_core/dashboard_core.dart';

import 'src/mock/register.dart';
import 'src/routes.dart';

export 'src/mock/register.dart' show registerTeamMocks;
export 'src/routes.dart' show teamRoutes;

/// The team area as the shell mounts it. Each unit keeps its own supplement
/// tables (`assets/i18n/<unit>.<lang>.json`) so builders never share a file.
const DashArea teamArea = DashArea(
  key: 'team',
  routes: teamRoutes,
  registerMocks: registerTeamMocks,
  i18nSupplements: [
    'packages/dashboard_team/assets/i18n/en.json',
    'packages/dashboard_team/assets/i18n/ar.json',
    'packages/dashboard_team/assets/i18n/schedule.en.json',
    'packages/dashboard_team/assets/i18n/schedule.ar.json',
    'packages/dashboard_team/assets/i18n/employees.en.json',
    'packages/dashboard_team/assets/i18n/employees.ar.json',
    'packages/dashboard_team/assets/i18n/team_setup.en.json',
    'packages/dashboard_team/assets/i18n/team_setup.ar.json',
    'packages/dashboard_team/assets/i18n/attendance.en.json',
    'packages/dashboard_team/assets/i18n/attendance.ar.json',
    'packages/dashboard_team/assets/i18n/payroll.en.json',
    'packages/dashboard_team/assets/i18n/payroll.ar.json',
    'packages/dashboard_team/assets/i18n/rules.en.json',
    'packages/dashboard_team/assets/i18n/rules.ar.json',
    'packages/dashboard_team/assets/i18n/requests.en.json',
    'packages/dashboard_team/assets/i18n/requests.ar.json',
    'packages/dashboard_team/assets/i18n/shifts.en.json',
    'packages/dashboard_team/assets/i18n/shifts.ar.json',
    'packages/dashboard_team/assets/i18n/team_board.en.json',
    'packages/dashboard_team/assets/i18n/team_board.ar.json',
    'packages/dashboard_team/assets/i18n/approvals.en.json',
    'packages/dashboard_team/assets/i18n/approvals.ar.json',
    'packages/dashboard_team/assets/i18n/team_reports.en.json',
    'packages/dashboard_team/assets/i18n/team_reports.ar.json',
  ],
);
