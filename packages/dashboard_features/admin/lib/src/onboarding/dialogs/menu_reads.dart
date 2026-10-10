/// The reads the onboarding steps and their editors share (one provider per
/// web hook, keyed by exactly the request's arguments), and the web's
/// invalidation helpers over dashboard_core's prefix bus.
///
/// | provider | web hook | used by |
/// |---|---|---|
/// | [menuCategoriesProvider] | `useListCategories({org_id})` | menu-items and recipes steps, item dialog |
/// | [menuItemsProvider] | `useListMenuItems({org_id})` | recipes step |
/// | [menuItemProvider] | `useGetMenuItem(id)` | item dialog (edit) |
/// | [addonItemsProvider] | `useListAddonItems({org_id})` | item dialog |
/// | [modifierGroupsProvider] | `useListGroups({org_id})` | add-on dialog, item dialog, group editor |
/// | [ingredientCatalogProvider] | `useListCatalog(orgId)` | item dialog (recipe), group editor |
/// | [ingredientCategoriesProvider] | `useListIngredientCategories(orgId)` | ingredient dialog, group editor |
///
/// Each provider watches the epoch of its request path, so a helper below
/// (`ref.menuInvalidate.catalog()` for the web's `invalidateCatalog()`)
/// refetches exactly the reads whose path starts with one of its prefixes,
/// as the web's `queryKey[0].startsWith(prefix)` predicates do.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The request paths (the web's query keys) and invalidated prefixes.
abstract final class MenuPaths {
  static const String menuItems = '/menu-items';
  static const String categories = '/categories';
  static const String addonItems = '/addon-items';
  static const String branchMenuOverrides = '/branch-menu-overrides';
  static const String branchAddonOverrides = '/branch-addon-overrides';
  static const String catalog = '/catalog';
  static const String costing = '/costing';
  static const String recipes = '/recipes';
  static const String inventory = '/inventory';
  static const String modifierGroups = '/modifier-groups';
  static const String paymentMethods = '/payment-methods';

  static String menuItem(String id) => '/menu-items/$id';
  static String ingredientCatalog(String orgId) =>
      '/inventory/orgs/$orgId/catalog';
  static String ingredientCategories(String orgId) =>
      '/inventory/orgs/$orgId/categories';
}

void _watch(Ref ref, String path) => ref.watch(realtimeEpochProvider(path));

/// `GET /categories?org_id`: the menu categories, in POS order.
final menuCategoriesProvider = FutureProvider.autoDispose
    .family<List<Category>, String>((ref, orgId) {
      ref.webCache();
      _watch(ref, MenuPaths.categories);
      return ref.watch(apiProvider).menu.listCategories(orgId: orgId);
    });

/// `GET /menu-items?org_id`: the org's items.
final menuItemsProvider = FutureProvider.autoDispose
    .family<List<MenuItem>, String>((ref, orgId) {
      ref.webCache();
      _watch(ref, MenuPaths.menuItems);
      return ref.watch(apiProvider).menu.listMenuItems(orgId: orgId);
    });

/// `GET /menu-items/{id}`: one item with its sizes, recipes and add-ons.
final menuItemProvider = FutureProvider.autoDispose
    .family<MenuItemFull, String>((ref, id) {
      ref.webCache();
      _watch(ref, MenuPaths.menuItem(id));
      return ref.watch(apiProvider).menu.getMenuItem(id: id);
    });

/// `GET /addon-items?org_id`: every add-on (a shared group's option).
final addonItemsProvider = FutureProvider.autoDispose
    .family<List<AddonItem>, String>((ref, orgId) {
      ref.webCache();
      _watch(ref, MenuPaths.addonItems);
      return ref.watch(apiProvider).menu.listAddonItems(orgId: orgId);
    });

/// `GET /modifier-groups?org_id`: the active choice groups.
final modifierGroupsProvider = FutureProvider.autoDispose
    .family<List<GroupOut>, String>((ref, orgId) {
      ref.webCache();
      _watch(ref, MenuPaths.modifierGroups);
      return ref.watch(apiProvider).menu.listGroups(orgId: orgId);
    });

/// `GET /inventory/orgs/{orgId}/catalog`: the org's ingredients.
final ingredientCatalogProvider = FutureProvider.autoDispose
    .family<List<OrgIngredient>, String>((ref, orgId) {
      ref.webCache();
      _watch(ref, MenuPaths.ingredientCatalog(orgId));
      return ref.watch(apiProvider).inventory.listCatalog(orgId: orgId);
    });

/// `GET /inventory/orgs/{orgId}/categories`: the ingredient categories.
final ingredientCategoriesProvider = FutureProvider.autoDispose
    .family<List<IngredientCategory>, String>((ref, orgId) {
      ref.webCache();
      _watch(ref, MenuPaths.ingredientCategories(orgId));
      return ref
          .watch(apiProvider)
          .inventory
          .listIngredientCategories(orgId: orgId);
    });

/// The ingredient catalog by id (`catalogById`).
Map<String, OrgIngredient> ingredientsById(Iterable<OrgIngredient> catalog) => {
  for (final c in catalog) c.id: c,
};

/// The web's invalidation helpers the editors call.
class MenuInvalidator {
  const MenuInvalidator(this.bus);

  final RealtimeBus bus;

  /// `invalidateCatalog()` (menu util): items, categories, add-ons, branch
  /// overrides, catalog and costing reads.
  void catalog() => bus.invalidate(const [
    MenuPaths.menuItems,
    MenuPaths.categories,
    MenuPaths.addonItems,
    MenuPaths.branchMenuOverrides,
    MenuPaths.branchAddonOverrides,
    MenuPaths.catalog,
    MenuPaths.costing,
  ]);

  /// `invalidateRecipes()` (recipes util): recipes, items, add-ons, costing
  /// and every inventory read (the ingredient catalog).
  void recipes() => bus.invalidate(const [
    MenuPaths.recipes,
    MenuPaths.menuItems,
    MenuPaths.addonItems,
    MenuPaths.costing,
    MenuPaths.inventory,
  ]);

  /// `invalidatePaymentMethods()`: every `/payment-methods…` read.
  void paymentMethods() => bus.invalidate(const [MenuPaths.paymentMethods]);
}

/// `ref.menuInvalidate.catalog()` from a widget.
extension MenuInvalidateWidgetRef on WidgetRef {
  MenuInvalidator get menuInvalidate =>
      MenuInvalidator(read(realtimeBusProvider));
}
