/// The dashboard's sell area: its pages ([sellRoutes]), its mock backend
/// ([registerSellMocks]) and its i18n supplement, as [sellArea].
library;

import 'package:dashboard_core/dashboard_core.dart';

import 'src/mock/register.dart';
import 'src/routes.dart';

export 'src/mock/register.dart' show registerSellMocks;
export 'src/routes.dart' show sellRoutes;

/// The sell area as the shell mounts it.
const DashArea sellArea = DashArea(
  key: 'sell',
  routes: sellRoutes,
  registerMocks: registerSellMocks,
  i18nSupplements: [
    'packages/dashboard_sell/assets/i18n/en.json',
    'packages/dashboard_sell/assets/i18n/ar.json',
  ],
);
