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
///
/// Supplements: the area's own tables, then one pair per unit (each unit's
/// builder edits only its own pair), so units never touch the same file.
const DashArea inventoryArea = DashArea(
  key: 'inventory',
  routes: inventoryRoutes,
  registerMocks: registerInventoryMocks,
  i18nSupplements: [
    'packages/dashboard_inventory/assets/i18n/en.json',
    'packages/dashboard_inventory/assets/i18n/ar.json',
    'packages/dashboard_inventory/assets/i18n/today.en.json',
    'packages/dashboard_inventory/assets/i18n/today.ar.json',
    'packages/dashboard_inventory/assets/i18n/counts.en.json',
    'packages/dashboard_inventory/assets/i18n/counts.ar.json',
    'packages/dashboard_inventory/assets/i18n/ingredients.en.json',
    'packages/dashboard_inventory/assets/i18n/ingredients.ar.json',
    'packages/dashboard_inventory/assets/i18n/purchasing.en.json',
    'packages/dashboard_inventory/assets/i18n/purchasing.ar.json',
    'packages/dashboard_inventory/assets/i18n/waste.en.json',
    'packages/dashboard_inventory/assets/i18n/waste.ar.json',
    'packages/dashboard_inventory/assets/i18n/transfers.en.json',
    'packages/dashboard_inventory/assets/i18n/transfers.ar.json',
    'packages/dashboard_inventory/assets/i18n/inv_settings.en.json',
    'packages/dashboard_inventory/assets/i18n/inv_settings.ar.json',
  ],
);
