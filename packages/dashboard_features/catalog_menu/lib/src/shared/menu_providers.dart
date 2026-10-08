/// Reads several menu pages share (one provider per web hook, keyed by the
/// org, refetched by the invalidation helpers of `menu_queries.dart`):
///
/// | provider | web hook | used by |
/// |---|---|---|
/// | [ingredientCatalogProvider] | `useListCatalog` | item dialogs, recipe builder, studio, groups editor, bases, packaging |
/// | [ingredientCategoriesProvider] | `useListIngredientCategories` | create-ingredient dialog, group editor |
/// | [menuCategoriesProvider] | `useListCategories` | items, studio, packaging |
/// | [modifierGroupsProvider] | `useListGroups` | items (add-on and item dialogs), groups, studio |
/// | [addonItemsProvider] | `useListAddonItems` | items (tab and item dialog) |
/// | [recipeBasesProvider] | `useListBases` | bases page, studio base picker |
///
/// A page-only read belongs in its unit, not here.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'menu_queries.dart';

/// `GET /inventory/orgs/{orgId}/catalog`: the org's ingredients.
final ingredientCatalogProvider = FutureProvider.autoDispose
    .family<List<OrgIngredient>, String>((ref, orgId) {
      watchMenuPath(ref, MenuPaths.ingredientCatalog(orgId));
      return ref.watch(apiProvider).inventory.listCatalog(orgId: orgId);
    });

/// `GET /inventory/orgs/{orgId}/categories`: the ingredient categories.
final ingredientCategoriesProvider = FutureProvider.autoDispose
    .family<List<IngredientCategory>, String>((ref, orgId) {
      watchMenuPath(ref, MenuPaths.ingredientCategories(orgId));
      return ref
          .watch(apiProvider)
          .inventory
          .listIngredientCategories(orgId: orgId);
    });

/// `GET /categories?org_id`: the menu categories, in POS order.
final menuCategoriesProvider = FutureProvider.autoDispose
    .family<List<Category>, String>((ref, orgId) {
      watchMenuPath(ref, MenuPaths.categories);
      return ref.watch(apiProvider).menu.listCategories(orgId: orgId);
    });

/// The arguments of [modifierGroupsProvider].
typedef GroupsQuery = ({String orgId, bool includeInactive});

/// `GET /modifier-groups?org_id[&include_inactive=true]`.
final modifierGroupsProvider = FutureProvider.autoDispose
    .family<List<GroupOut>, GroupsQuery>((ref, q) {
      watchMenuPath(ref, MenuPaths.modifierGroups);
      return ref
          .watch(apiProvider)
          .menu
          .listGroups(
            orgId: q.orgId,
            includeInactive: q.includeInactive ? true : null,
          );
    });

/// `GET /addon-items?org_id`: every add-on (a view over the shared groups'
/// options; an add-on's id is its option's id).
final addonItemsProvider = FutureProvider.autoDispose
    .family<List<AddonItem>, String>((ref, orgId) {
      watchMenuPath(ref, MenuPaths.addonItems);
      return ref.watch(apiProvider).menu.listAddonItems(orgId: orgId);
    });

/// `GET /recipe-bases` (the server scopes it to the org; keyed by the org so
/// switching orgs refetches).
final recipeBasesProvider = FutureProvider.autoDispose
    .family<List<RecipeBaseOut>, String>((ref, orgId) {
      watchMenuPath(ref, MenuPaths.recipeBases);
      return ref.watch(apiProvider).menu.listBases();
    });

/// The ingredient catalog by id (`catalogById`).
Map<String, OrgIngredient> ingredientsById(Iterable<OrgIngredient> catalog) => {
  for (final c in catalog) c.id: c,
};
