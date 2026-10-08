/// The menu catalogue area's pages (`/menu/items`, `/menu/items/:itemId`,
/// `/menu/groups`, `/menu/pricing`, `/menu/bases`, `/menu/packaging`), module
/// `pos`.
///
/// No page carries capabilities: the web's route files have no guard and no
/// page of this area renders `<Restricted>` (MENU-AREA-008), so a person who
/// types the address sees the page and the server refuses what they may not
/// read or write. The sidebar and the command palette keep the nav's caps
/// (`menu.items.read`; Pricing `menu.items.edit`) from the generated nav.
///
/// The studio is its own top-level route, as the web un-nests it
/// (`items_.$itemId`): the items page is not built under it.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'bases/bases_page.dart';
import 'bases/packaging_rules_page.dart';
import 'groups/groups_page.dart';
import 'items/items_page.dart';
import 'pricing/pricing_page.dart';
import 'studio/menu_studio_page.dart';

Widget _items(BuildContext context, GoRouterState state) =>
    const MenuItemsPage();

Widget _studio(BuildContext context, GoRouterState state) => MenuStudioPage(
  itemId: state.pathParameters['itemId']!,
  tab: state.uri.queryParameters['tab'],
);

Widget _groups(BuildContext context, GoRouterState state) =>
    GroupsPage(edit: state.uri.queryParameters['edit']);

Widget _pricing(BuildContext context, GoRouterState state) =>
    const PricingAvailabilityPage();

Widget _bases(BuildContext context, GoRouterState state) =>
    const RecipeBasesPage();

Widget _packaging(BuildContext context, GoRouterState state) =>
    const PackagingRulesPage();

const List<DashRoute> catalogMenuRoutes = [
  DashRoute(
    path: '/menu/items',
    builder: _items,
    titleKey: 'nav.menu',
    titleFallback: 'Menu',
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/menu/items/:itemId',
    builder: _studio,
    titleKey: 'menu.studio.itemTitle',
    titleFallback: 'Menu item',
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/menu/groups',
    builder: _groups,
    titleKey: 'menu.groups.title',
    titleFallback: 'Choice groups',
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/menu/pricing',
    builder: _pricing,
    titleKey: 'menu.pricing.title',
    titleFallback: 'Pricing & availability',
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/menu/bases',
    builder: _bases,
    titleKey: 'modeling.bases.title',
    titleFallback: 'Recipe bases',
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/menu/packaging',
    builder: _packaging,
    titleKey: 'modeling.packaging.title',
    titleFallback: 'Packaging rules',
    module: OrgModule.pos,
  ),
];
