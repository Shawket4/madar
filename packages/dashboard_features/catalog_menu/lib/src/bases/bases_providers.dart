/// The reads only the recipe-bases and packaging-rules pages make (one
/// provider per web hook, refetched by the area's invalidation helpers):
///
/// | provider | web hook | path |
/// |---|---|---|
/// | [baseUsageProvider] | `useGetBaseUsage` | `GET /recipe-bases/{id}/usage` |
/// | [packagingRulesProvider] | `useListRules` | `GET /packaging-rules` |
/// | [packagingItemOptionsProvider] | `useListMenuCatalog({per_page: 500})` | `GET /costing/catalog` |
///
/// The bases list, the menu categories and the ingredient catalog are the
/// area's shared reads (`shared/menu_providers.dart`).
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/menu_queries.dart';

/// `GET /recipe-bases/{id}/usage`: the item sizes following one base.
final baseUsageProvider = FutureProvider.autoDispose
    .family<RecipeBaseUsage, String>((ref, baseId) {
      ref.webCache();
      watchMenuPath(ref, MenuPaths.baseUsage(baseId));
      return ref.watch(apiProvider).menu.getBaseUsage(id: baseId);
    });

/// `GET /packaging-rules` (the server scopes it to the org; keyed by the org
/// so switching orgs refetches).
final packagingRulesProvider = FutureProvider.autoDispose
    .family<List<PackagingRuleOut>, String>((ref, orgId) {
      ref.webCache();
      watchMenuPath(ref, MenuPaths.packagingRules);
      return ref.watch(apiProvider).menu.listRules();
    });

/// `GET /costing/catalog?org_id&per_page=500`: the first 500 menu items, for
/// the rule rows' item names and the rule dialog's item picker.
final packagingItemOptionsProvider = FutureProvider.autoDispose
    .family<List<MenuItemWithCosts>, String>((ref, orgId) async {
      ref.webCache();
      watchMenuPath(ref, MenuPaths.costingCatalog);
      final page = await ref
          .watch(apiProvider)
          .menu
          .listMenuCatalog(orgId: orgId, perPage: 500);
      return page.data;
    });
