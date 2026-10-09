/// The items page's own reads (the shared ones — categories, add-ons, groups,
/// the ingredient catalog — are in `shared/menu_providers.dart`). Each is
/// keyed by exactly the params its request sends, as the web's query key.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/menu_providers.dart';
import '../shared/menu_queries.dart';

/// Cards per page (`ITEMS_PER_PAGE`, also the grid's client page size).
const int itemsPerPage = 24;

/// `listMenuCatalog`'s params (`per_page` is always [itemsPerPage]; [page]
/// is 1-based).
typedef CatalogQuery = ({
  String orgId,
  String? categoryId,
  String? search,
  bool? hasRecipe,
  int page,
});

/// `GET /costing/catalog`: one page of items with their per-size costs.
final menuCatalogProvider = FutureProvider.autoDispose
    .family<PaginatedMenuItems, CatalogQuery>((ref, q) {
      ref.webCache();
      watchMenuPath(ref, MenuPaths.costingCatalog);
      return ref
          .watch(apiProvider)
          .menu
          .listMenuCatalog(
            orgId: q.orgId,
            categoryId: q.categoryId,
            search: q.search,
            hasRecipe: q.hasRecipe,
            page: q.page,
            perPage: itemsPerPage,
          );
    });

/// `GET /costing/addon-items?org_id`: the add-ons' cost rollup (read only
/// while the Add-ons tab is open), fresh for 60 s (`COST_STALE`).
final addonCostsProvider = FutureProvider.autoDispose
    .family<List<AddonCost>, String>((ref, orgId) {
      ref.webCache(staleTime: const Duration(seconds: 60));
      watchMenuPath(ref, MenuPaths.costingAddons);
      return ref.watch(apiProvider).costing.listAddonCosts(orgId: orgId);
    });

/// `GET /branch-menu-overrides?branch_id` (one branch scoped).
final branchMenuOverridesProvider = FutureProvider.autoDispose
    .family<List<BranchMenuOverride>, String>((ref, branchId) {
      ref.webCache();
      watchMenuPath(ref, MenuPaths.branchMenuOverrides);
      return ref
          .watch(apiProvider)
          .menu
          .listBranchMenuOverrides(branchId: branchId);
    });

/// `GET /branch-addon-overrides?branch_id` (one branch scoped).
final branchAddonOverridesProvider = FutureProvider.autoDispose
    .family<List<BranchAddonOverride>, String>((ref, branchId) {
      ref.webCache();
      watchMenuPath(ref, MenuPaths.branchAddonOverrides);
      return ref
          .watch(apiProvider)
          .menu
          .listBranchAddonOverrides(branchId: branchId);
    });

/// The catalog page the page opens on (and the route warms).
CatalogQuery firstCatalogPage(String orgId) =>
    (orgId: orgId, categoryId: null, search: null, hasRecipe: null, page: 1);

/// The web's `prefetchRoute('/menu/items')`: catalog page 1 (24 per page),
/// the categories and the add-ons, with the page's own keys.
void prefetchMenuItems(DashPrefetcher warm, Scope s) {
  final org = s.orgId;
  if (org == null) return;
  warm(menuCatalogProvider(firstCatalogPage(org)));
  warm(menuCategoriesProvider(org));
  warm(addonItemsProvider(org));
}
