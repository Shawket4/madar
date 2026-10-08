/// The reads several inventory pages share, as providers (one cache per org
/// or branch, so Today, Ingredients, Purchasing, Counts and the dialogs
/// agree), and the web's `invalidateInventory()`.
///
/// Every provider here watches the core's [realtimeEpochProvider] for its
/// path, so [invalidateInventory] (and a realtime `resync`) refetches it. A
/// unit's own providers do the same with their own paths.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The path families an inventory change makes stale (`lib.ts:16`).
const List<String> inventoryPathFamilies = [
  '/inventory',
  '/stocktakes',
  '/purchasing',
  '/reports',
];

/// `invalidateInventory()`: every read under [inventoryPathFamilies] —
/// this area's and the reports area's — refetches. Call it after every
/// successful inventory mutation, before the success toast.
void invalidateInventory(WidgetRef ref) =>
    ref.read(realtimeBusProvider).invalidate(inventoryPathFamilies);

/// [invalidateInventory] from inside a provider or notifier.
void invalidateInventoryFrom(Ref ref) =>
    ref.read(realtimeBusProvider).invalidate(inventoryPathFamilies);

/// `GET /inventory/orgs/{org_id}/catalog` (listCatalog), by name.
final inventoryCatalogProvider = FutureProvider.autoDispose
    .family<List<OrgIngredient>, String>((ref, orgId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/inventory/orgs/$orgId/catalog'));
      return ref.watch(apiProvider).inventory.listCatalog(orgId: orgId);
    });

/// `GET /inventory/orgs/{org_id}/categories` (listIngredientCategories).
final ingredientCategoriesProvider = FutureProvider.autoDispose
    .family<List<IngredientCategory>, String>((ref, orgId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/inventory/orgs/$orgId/categories'));
      return ref
          .watch(apiProvider)
          .inventory
          .listIngredientCategories(orgId: orgId);
    });

/// `GET /purchasing/orgs/{org_id}/suppliers` (listSuppliers), by name.
final inventorySuppliersProvider = FutureProvider.autoDispose
    .family<List<Supplier>, String>((ref, orgId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/purchasing/orgs/$orgId/suppliers'));
      return ref.watch(apiProvider).purchasing.listSuppliers(orgId: orgId);
    });

/// `GET /inventory/branches/{branch_id}/stock` (listBranchStock): the whole
/// catalog as one branch sees it.
final branchStockProvider = FutureProvider.autoDispose
    .family<List<BranchStockRow>, String>((ref, branchId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/inventory/branches/$branchId/stock'));
      return ref
          .watch(apiProvider)
          .inventory
          .listBranchStock(branchId: branchId);
    });

/// `GET /stocktakes/branches/{branch_id}` (listStocktakes); pass
/// [Scope.scopeBranchId] (the all-branches sentinel rolls the org up).
final stocktakesProvider = FutureProvider.autoDispose
    .family<List<Stocktake>, String>((ref, branchId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/stocktakes/branches/$branchId'));
      return ref
          .watch(apiProvider)
          .stocktakes
          .listStocktakes(branchId: branchId);
    });

/// The active suppliers a picker offers (inactive ones are listed on the
/// Suppliers tab only, INV-PUR-059).
List<Supplier> activeSuppliers(List<Supplier> all) => [
  for (final s in all)
    if (s.isActive) s,
];
