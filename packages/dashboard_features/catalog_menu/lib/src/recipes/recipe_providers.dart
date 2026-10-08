/// The recipes unit's reads, for the hosts of the recipe builder (the items
/// unit's add-on recipe dialog).
library;

import 'package:dashboard_api/dashboard_api.dart' show AddonIngredient;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/menu_queries.dart';

/// `GET /recipes/addons/{addonItemId}` (`useListAddonIngredients`): an
/// add-on's ingredient lines. Refetched by `invalidateRecipes` (its key
/// starts with `/recipes`).
final addonIngredientsProvider = FutureProvider.autoDispose
    .family<List<AddonIngredient>, String>((ref, addonItemId) {
      ref.webCache();
      watchMenuPath(ref, MenuPaths.addonIngredients(addonItemId));
      return ref
          .watch(apiProvider)
          .recipes
          .listAddonIngredients(addonItemId: addonItemId);
    });
