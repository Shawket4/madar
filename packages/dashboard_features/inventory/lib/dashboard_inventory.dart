/// The dashboard's inventory area: its pages ([inventoryRoutes]), its mock
/// backend ([registerInventoryMocks]) and its i18n supplement, as
/// [inventoryArea].
library;

import 'package:dashboard_core/dashboard_core.dart';

import 'src/mock/register.dart';
import 'src/routes.dart';

export 'src/mock/register.dart' show registerInventoryMocks;
export 'src/routes.dart' show inventoryRoutes;

/// The inventory area as the shell mounts it.
const DashArea inventoryArea = DashArea(
  key: 'inventory',
  routes: inventoryRoutes,
  registerMocks: registerInventoryMocks,
  i18nSupplements: [
    'packages/dashboard_inventory/assets/i18n/en.json',
    'packages/dashboard_inventory/assets/i18n/ar.json',
  ],
);
