/// The dashboard's overview area: its pages ([overviewRoutes]: the home and
/// Setup), its mock backend ([registerOverviewMocks]), its i18n supplement
/// and the frame foot's Madar apps, as [overviewArea].
library;

import 'package:dashboard_core/dashboard_core.dart';

import 'src/apps/app_tiles.dart';
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
  footer: madarAppsFooter,
);
