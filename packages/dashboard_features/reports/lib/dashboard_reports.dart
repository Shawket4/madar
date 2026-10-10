/// The dashboard's reports area: its pages ([reportsRoutes]), its mock
/// backend ([registerReportsMocks]) and its i18n supplements, as
/// [reportsArea].
library;

import 'package:dashboard_core/dashboard_core.dart';

import 'src/mock/register.dart';
import 'src/routes.dart';

export 'src/mock/register.dart' show registerReportsMocks;
export 'src/routes.dart' show reportsRoutes;

/// The reports area as the shell mounts it. Each unit owns its supplement
/// pair `assets/i18n/<unit>.{en,ar}.json`; the area-wide pair comes first.
const DashArea reportsArea = DashArea(
  key: 'reports',
  routes: reportsRoutes,
  registerMocks: registerReportsMocks,
  i18nSupplements: [
    'packages/dashboard_reports/assets/i18n/en.json',
    'packages/dashboard_reports/assets/i18n/ar.json',
    'packages/dashboard_reports/assets/i18n/operations.en.json',
    'packages/dashboard_reports/assets/i18n/operations.ar.json',
    'packages/dashboard_reports/assets/i18n/financial.en.json',
    'packages/dashboard_reports/assets/i18n/financial.ar.json',
    'packages/dashboard_reports/assets/i18n/legal.en.json',
    'packages/dashboard_reports/assets/i18n/legal.ar.json',
    'packages/dashboard_reports/assets/i18n/basira.en.json',
    'packages/dashboard_reports/assets/i18n/basira.ar.json',
    'packages/dashboard_reports/assets/i18n/tills_report.en.json',
    'packages/dashboard_reports/assets/i18n/tills_report.ar.json',
    'packages/dashboard_reports/assets/i18n/staff_pool_bundles.en.json',
    'packages/dashboard_reports/assets/i18n/staff_pool_bundles.ar.json',
    'packages/dashboard_reports/assets/i18n/loyalty_inventory_staff.en.json',
    'packages/dashboard_reports/assets/i18n/loyalty_inventory_staff.ar.json',
  ],
);
