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
import 'bases/bases_providers.dart';
import 'bases/packaging_rules_page.dart';
import 'groups/groups_page.dart';
import 'items/items_page.dart';
import 'items/items_providers.dart' show prefetchMenuItems;
import 'pricing/pricing_page.dart';
import 'pricing/pricing_providers.dart' show prefetchPricing;
import 'shared/menu_providers.dart';
import 'studio/menu_studio_page.dart';
import 'studio/studio_providers.dart';

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
    prefetch: prefetchMenuItems,
  ),
  DashRoute(
    path: '/menu/items/:itemId',
    builder: _studio,
    titleKey: 'menu.studio.itemTitle',
    titleFallback: 'Menu item',
    module: OrgModule.pos,
    prefetch: _prefetchStudio,
  ),
  DashRoute(
    path: '/menu/groups',
    builder: _groups,
    titleKey: 'menu.groups.title',
    titleFallback: 'Choice groups',
    module: OrgModule.pos,
    prefetch: _prefetchGroups,
  ),
  DashRoute(
    path: '/menu/pricing',
    builder: _pricing,
    titleKey: 'menu.pricing.title',
    titleFallback: 'Pricing & availability',
    module: OrgModule.pos,
    prefetch: prefetchPricing,
  ),
  DashRoute(
    path: '/menu/bases',
    builder: _bases,
    titleKey: 'modeling.bases.title',
    titleFallback: 'Recipe bases',
    module: OrgModule.pos,
    prefetch: _prefetchBases,
  ),
  DashRoute(
    path: '/menu/packaging',
    builder: _packaging,
    titleKey: 'modeling.packaging.title',
    titleFallback: 'Packaging rules',
    module: OrgModule.pos,
    prefetch: _prefetchPackaging,
  ),
];

/// The studio's mount reads (`/menu/items/:itemId`): the aggregate, the item
/// (the meal section's target), the step library, the area's shared reads
/// (ingredients, categories, bases, active groups) and the meal section's
/// combos and full item list. A new item (`new`) reads nothing to warm; the
/// steps' animation files are fetched per step URL once the library lands,
/// and the recipe link only for a linked copy, so the page reads those.
void _prefetchStudio(DashPrefetcher warm, Scope s) {
  final id = warm.params['itemId'];
  final org = s.orgId;
  if (id == null || id == 'new' || org == null) return;
  warm(menuStudioProvider(id));
  warm(studioMenuItemProvider(id));
  warm(stepPresetsProvider);
  warm(ingredientCatalogProvider(org));
  warm(menuCategoriesProvider(org));
  warm(recipeBasesProvider(org));
  warm(modifierGroupsProvider((orgId: org, includeInactive: false)));
  warm(studioCombosProvider);
  warm(studioMenuOptionsProvider(org));
}

/// `/menu/groups`: the list, inactive included (the page's key). Each
/// group's usage is keyed by an id the list answers, so the page reads it.
void _prefetchGroups(DashPrefetcher warm, Scope s) {
  final org = s.orgId;
  if (org == null) return;
  warm(modifierGroupsProvider((orgId: org, includeInactive: true)));
}

/// `/menu/bases`: the bases and the ingredient catalog they read.
void _prefetchBases(DashPrefetcher warm, Scope s) {
  final org = s.orgId;
  if (org == null) return;
  warm(recipeBasesProvider(org));
  warm(ingredientCatalogProvider(org));
}

/// `/menu/packaging`: the rules, the ingredient catalog, the menu
/// categories and the first 500 catalog items the rows name.
void _prefetchPackaging(DashPrefetcher warm, Scope s) {
  final org = s.orgId;
  if (org == null) return;
  warm(packagingRulesProvider(org));
  warm(ingredientCatalogProvider(org));
  warm(menuCategoriesProvider(org));
  warm(packagingItemOptionsProvider(org));
}
