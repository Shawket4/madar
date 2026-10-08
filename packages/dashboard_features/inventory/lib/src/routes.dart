/// The inventory area's pages (`/inventory/today`, `/inventory/counts`,
/// `/inventory/ingredients`, `/inventory/purchasing`, `/inventory/waste`,
/// `/inventory/transfers`, `/inventory/settings`) with the web's capabilities
/// (any-of, from the generated nav: `nav.ts:164-170`) and module (`pos`).
///
/// The legacy paths (`/inventory`, `/inventory/items`, `/inventory/reports`)
/// are the shell's redirects (INV-ALL-007).
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'counts/counts_page.dart';
import 'ingredients/ingredients_page.dart';
import 'inv_settings/inventory_settings_page.dart';
import 'purchasing/purchasing_page.dart';
import 'today/today_page.dart';
import 'transfers/transfers_page.dart';
import 'waste/waste_page.dart';

Widget _today(BuildContext context, GoRouterState state) => const TodayPage();

Widget _counts(BuildContext context, GoRouterState state) => const CountsPage();

Widget _ingredients(BuildContext context, GoRouterState state) =>
    const IngredientsPage();

Widget _purchasing(BuildContext context, GoRouterState state) =>
    const PurchasingPage();

Widget _waste(BuildContext context, GoRouterState state) => const WastePage();

Widget _transfers(BuildContext context, GoRouterState state) =>
    const TransfersPage();

Widget _settings(BuildContext context, GoRouterState state) =>
    const InventorySettingsPage();

const List<DashRoute> inventoryRoutes = [
  DashRoute(
    path: '/inventory/today',
    builder: _today,
    titleKey: 'nav.invToday',
    titleFallback: 'Today',
    caps: [Cap.inventoryRead],
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/inventory/counts',
    builder: _counts,
    titleKey: 'nav.invCounts',
    titleFallback: 'Stock counts',
    caps: [Cap.inventoryCountsRead],
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/inventory/ingredients',
    builder: _ingredients,
    titleKey: 'nav.ingredients',
    titleFallback: 'Ingredients',
    caps: [Cap.inventoryRead],
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/inventory/purchasing',
    builder: _purchasing,
    titleKey: 'nav.invPurchasing',
    titleFallback: 'Purchasing',
    caps: [Cap.purchasingOrdersRead, Cap.purchasingSuppliersRead],
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/inventory/waste',
    builder: _waste,
    titleKey: 'nav.invWaste',
    titleFallback: 'Waste',
    caps: [Cap.inventoryWasteRead],
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/inventory/transfers',
    builder: _transfers,
    titleKey: 'nav.invTransfers',
    titleFallback: 'Transfers',
    caps: [Cap.inventoryTransfersRead],
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/inventory/settings',
    builder: _settings,
    titleKey: 'nav.invSettings',
    titleFallback: 'Settings',
    caps: [Cap.inventoryAdjust],
    module: OrgModule.pos,
  ),
];
