/// The dashboard's reports area: its pages ([reportsRoutes]), its mock backend
/// ([registerReportsMocks]) and its i18n supplement, as [reportsArea].
library;

import 'package:dashboard_core/dashboard_core.dart';

import 'src/mock/register.dart';
import 'src/routes.dart';

export 'src/mock/register.dart' show registerReportsMocks;
export 'src/routes.dart' show reportsRoutes;

/// The reports area as the shell mounts it.
const DashArea reportsArea = DashArea(
  key: 'reports',
  routes: reportsRoutes,
  registerMocks: registerReportsMocks,
  i18nSupplements: [
    'packages/dashboard_reports/assets/i18n/en.json',
    'packages/dashboard_reports/assets/i18n/ar.json',
  ],
);
