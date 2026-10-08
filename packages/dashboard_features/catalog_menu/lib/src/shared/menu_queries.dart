/// The menu area's reads as API paths (the web's React Query keys are the
/// paths) and its invalidation helpers, over dashboard_core's prefix bus.
///
/// A provider that reads a path watches `realtimeEpochProvider(path)` (see
/// [watchMenuPath]); a mutation calls the helper the web calls
/// (`ref.menuInvalidate.catalog()` for `invalidateCatalog()`), which bumps
/// every epoch whose path starts with one of the helper's prefixes, exactly
/// the web's `queryKey[0].startsWith(prefix)` predicates
/// (`features/menu/util.ts`, `features/recipes/util.ts`,
/// `features/menu/studio/util.ts`, `features/menu/pricing/util.ts`).
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The paths this area reads (query keys) and the prefixes it invalidates.
abstract final class MenuPaths {
  static const String menuItems = '/menu-items';
  static const String categories = '/categories';
  static const String addonItems = '/addon-items';
  static const String addonCatalog = '/addon-items/catalog';
  static const String branchMenuOverrides = '/branch-menu-overrides';
  static const String branchAddonOverrides = '/branch-addon-overrides';
  static const String channelOverrides = '/delivery/channel-overrides';
  static const String channelAddonOverrides =
      '/delivery/channel-addon-overrides';
  static const String catalog = '/catalog';
  static const String costing = '/costing';

  /// `listMenuCatalog` (items with their per-size costs).
  static const String costingCatalog = '/costing/catalog';

  /// `listAddonCosts`.
  static const String costingAddons = '/costing/addon-items';
  static const String recipes = '/recipes';
  static const String stepPresets = '/recipes/step-presets';
  static const String inventory = '/inventory';
  static const String modifierGroups = '/modifier-groups';
  static const String recipeBases = '/recipe-bases';
  static const String packagingRules = '/packaging-rules';
  static const String combos = '/combos';

  static String menuItem(String id) => '/menu-items/$id';
  static String studio(String id) => '/menu-items/$id/studio';
  static String itemCost(String id) => '/menu-items/$id/cost';
  static String recipeLink(String id) => '/menu-items/$id/recipe-link';
  static String groupUsage(String gid) => '/modifier-groups/$gid/usage';
  static String baseUsage(String id) => '/recipe-bases/$id/usage';
  static String addonIngredients(String id) => '/recipes/addons/$id';
  static String ingredientCatalog(String orgId) =>
      '/inventory/orgs/$orgId/catalog';
  static String ingredientCategories(String orgId) =>
      '/inventory/orgs/$orgId/categories';

  /// Stands for "any `/menu-items/…/studio`" (the pricing page's predicate):
  /// a studio read watches it besides its own path (see [watchStudioPaths]).
  static const String anyStudio = '/menu-items/*/studio';
}

/// Watches the invalidation epoch of [path], so the calling provider re-runs
/// when a helper below (or a realtime event) invalidates a prefix of it.
void watchMenuPath(Ref ref, String path) =>
    ref.watch(realtimeEpochProvider(path));

/// What a studio read watches: its own path and [MenuPaths.anyStudio].
void watchStudioPaths(Ref ref, String itemId) {
  ref
    ..watch(realtimeEpochProvider(MenuPaths.studio(itemId)))
    ..watch(realtimeEpochProvider(MenuPaths.anyStudio));
}

/// The web's invalidation helpers for this area.
class MenuInvalidator {
  const MenuInvalidator(this.bus);

  final RealtimeBus bus;

  static const List<String> _catalog = [
    MenuPaths.menuItems,
    MenuPaths.categories,
    MenuPaths.addonItems,
    MenuPaths.branchMenuOverrides,
    MenuPaths.branchAddonOverrides,
    MenuPaths.catalog,
    MenuPaths.costing,
  ];

  /// `invalidateCatalog()` (menu util): items, categories, add-ons, branch
  /// overrides, catalog and costing reads (NOT groups, bases, rules or the
  /// ingredient catalog).
  void catalog() => bus.invalidate(_catalog);

  /// `invalidateRecipes()` (recipes util): recipes, items, add-ons, costing
  /// and the inventory reads (the ingredient catalog).
  void recipes() => bus.invalidate(const [
    MenuPaths.recipes,
    MenuPaths.menuItems,
    MenuPaths.addonItems,
    MenuPaths.costing,
    MenuPaths.inventory,
  ]);

  /// `invalidateStudio(itemId)`: the item's studio and cost (both under
  /// `/menu-items`), plus items, categories, catalog, costing and groups.
  void studio(String itemId) => bus.invalidate(const [
    MenuPaths.menuItems,
    MenuPaths.categories,
    MenuPaths.catalog,
    MenuPaths.costing,
    MenuPaths.modifierGroups,
  ]);

  /// `invalidateIngredientCosts(orgId, itemId)`: the org ingredient catalog,
  /// then [studio].
  void ingredientCosts(String? orgId, String itemId) {
    if (orgId != null) bus.invalidate([MenuPaths.ingredientCatalog(orgId)]);
    studio(itemId);
  }

  /// `invalidatePricingOverrides()`: the four override list reads and every
  /// item's studio.
  void pricingOverrides() => bus.invalidate(const [
    MenuPaths.branchMenuOverrides,
    MenuPaths.branchAddonOverrides,
    MenuPaths.channelOverrides,
    MenuPaths.channelAddonOverrides,
    MenuPaths.anyStudio,
  ]);

  /// Any other prefixes (a page's own list after a write, e.g.
  /// `/recipe-bases`, `/packaging-rules`, `/modifier-groups`).
  void paths(List<String> prefixes) => bus.invalidate(prefixes);
}

/// `ref.menuInvalidate.catalog()` from a widget.
extension MenuInvalidateWidgetRef on WidgetRef {
  MenuInvalidator get menuInvalidate =>
      MenuInvalidator(read(realtimeBusProvider));
}

/// `ref.menuInvalidate.catalog()` from a provider or notifier.
extension MenuInvalidateRef on Ref {
  MenuInvalidator get menuInvalidate =>
      MenuInvalidator(read(realtimeBusProvider));
}
