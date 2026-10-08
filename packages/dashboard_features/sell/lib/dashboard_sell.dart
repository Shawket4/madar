/// The dashboard's sell area: its pages ([sellRoutes]), its mock backend
/// ([registerSellMocks]) and its i18n supplement, as [sellArea].
library;

import 'package:dashboard_core/dashboard_core.dart';

import 'src/mock/register.dart';
import 'src/routes.dart';

export 'src/mock/register.dart' show registerSellMocks;
export 'src/routes.dart' show sellRoutes;

/// The sell area as the shell mounts it.
///
/// Supplements: the area-wide pair, then one pair per unit
/// (`assets/i18n/<unit>/<lang>.json`, the file name is the language), so the
/// units' builders never edit the same table.
const DashArea sellArea = DashArea(
  key: 'sell',
  routes: sellRoutes,
  registerMocks: registerSellMocks,
  i18nSupplements: [
    'packages/dashboard_sell/assets/i18n/en.json',
    'packages/dashboard_sell/assets/i18n/ar.json',
    'packages/dashboard_sell/assets/i18n/orders/en.json',
    'packages/dashboard_sell/assets/i18n/orders/ar.json',
    'packages/dashboard_sell/assets/i18n/floor/en.json',
    'packages/dashboard_sell/assets/i18n/floor/ar.json',
    'packages/dashboard_sell/assets/i18n/bookings/en.json',
    'packages/dashboard_sell/assets/i18n/bookings/ar.json',
    'packages/dashboard_sell/assets/i18n/tills/en.json',
    'packages/dashboard_sell/assets/i18n/tills/ar.json',
    'packages/dashboard_sell/assets/i18n/customers/en.json',
    'packages/dashboard_sell/assets/i18n/customers/ar.json',
  ],
);
