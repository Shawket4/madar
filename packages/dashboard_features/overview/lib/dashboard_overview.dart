/// The dashboard's overview area: its pages ([overviewRoutes]), its mock
/// backend ([registerOverviewMocks]) and its i18n supplement, as
/// [overviewArea].
library;

import 'package:dashboard_core/dashboard_core.dart';

import 'src/mock/register.dart';
import 'src/routes.dart';

export 'src/mock/register.dart' show registerOverviewMocks;
export 'src/routes.dart' show overviewRoutes;

/// The overview area as the shell mounts it.
const DashArea overviewArea = DashArea(
  key: 'overview',
  routes: overviewRoutes,
  registerMocks: registerOverviewMocks,
  i18nSupplements: [
    'packages/dashboard_overview/assets/i18n/en.json',
    'packages/dashboard_overview/assets/i18n/ar.json',
  ],
);
