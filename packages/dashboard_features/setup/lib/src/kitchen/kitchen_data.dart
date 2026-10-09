/// Kitchen stations and order routing: the reads, the invalidation and the
/// browser-side rules (web `features/kitchen-stations/{stations-page,
/// routing-page,util}.ts(x)`).
///
/// - one autoDispose read per endpoint, keyed by exactly the params the
///   request sends, each watching `realtimeEpochProvider(<its path>)` so a
///   `kitchen.*` event (→ `/kitchen`) and the page's own writes refetch it;
/// - [invalidateStations] / [invalidateRouting]: the web's two predicate
///   invalidations (`util.ts`);
/// - [KitchenRouting]: what the routing page derives from the three reads
///   (only ACTIVE stations are offered or named, SET-KRT-019).
library;

import 'package:dashboard_api/dashboard_api.dart'
    show
        Category,
        KitchenStation,
        MenuItemWithCosts,
        PaginatedMenuItems,
        PrinterBrand,
        RoutingModeResponse,
        StationRoutes;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The query-key paths (the web's Orval keys start with the path).
abstract final class KitchenPaths {
  static const String stations = '/kitchen/stations';
  static const String routingMode = '/kitchen/routing-mode';
  static const String routes = '/kitchen/routes';
  static const String categories = '/categories';
  static const String catalog = '/costing/catalog';
}

/// `GET /kitchen/stations?branch_id=` (useListStations).
final kitchenStationsProvider = FutureProvider.autoDispose
    .family<List<KitchenStation>, String>((ref, branchId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider(KitchenPaths.stations));
      return ref.watch(apiProvider).kitchen.listStations(branchId: branchId);
    });

/// `GET /kitchen/routing-mode?branch_id=` (useGetRoutingMode).
final kitchenRoutingModeProvider = FutureProvider.autoDispose
    .family<RoutingModeResponse, String>((ref, branchId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider(KitchenPaths.routingMode));
      return ref.watch(apiProvider).kitchen.getRoutingMode(branchId: branchId);
    });

/// `GET /kitchen/routes?branch_id=` (useListRoutes).
final kitchenRoutesProvider = FutureProvider.autoDispose
    .family<StationRoutes, String>((ref, branchId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider(KitchenPaths.routes));
      return ref.watch(apiProvider).kitchen.listRoutes(branchId: branchId);
    });

/// `GET /categories?org_id=` (useListCategories).
final kitchenCategoriesProvider = FutureProvider.autoDispose
    .family<List<Category>, String>((ref, orgId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider(KitchenPaths.categories));
      return ref.watch(apiProvider).menu.listCategories(orgId: orgId);
    });

/// The per-item list's page size (`PER_PAGE`).
const int kitchenCatalogPerPage = 50;

/// The catalogue read's params: `{org_id, search (absent when empty), page
/// (1-based), per_page: 50}`.
typedef KitchenCatalogKey = ({String orgId, String? search, int page});

/// `GET /costing/catalog?org_id&search&page&per_page=50` (useListMenuCatalog).
final kitchenCatalogProvider = FutureProvider.autoDispose
    .family<PaginatedMenuItems, KitchenCatalogKey>((ref, k) {
      ref.webCache();
      ref.watch(realtimeEpochProvider(KitchenPaths.catalog));
      return ref
          .watch(apiProvider)
          .menu
          .listMenuCatalog(
            orgId: k.orgId,
            search: k.search,
            page: k.page,
            perPage: kitchenCatalogPerPage,
          );
    });

/// After a station is created, changed or deleted: every read whose key
/// starts `/kitchen/stations` (`invalidateStations`). Take the bus before the
/// write's await: the refetch happens even when the dialog has gone.
void invalidateStations(RealtimeBus bus) =>
    bus.invalidate(const [KitchenPaths.stations]);

/// After the routing mode or a route changes: `/kitchen/routes*` and
/// `/kitchen/routing-mode*` (`invalidateRouting`).
void invalidateRouting(RealtimeBus bus) =>
    bus.invalidate(const [KitchenPaths.routes, KitchenPaths.routingMode]);

/// The routing-mode select's values; `auto` is the stored `null`.
const List<String> kitchenModes = ['auto', 'kds', 'till', 'both', 'off'];

/// The printer brand as the table shows it (CSS `capitalize`): "Star",
/// "Epson"; an unknown brand from a newer server, its first letter raised.
String printerBrandLabel(PrinterBrand b) => b.value.isEmpty
    ? b.value
    : b.value[0].toUpperCase() + b.value.substring(1);

/// `getTranslatedName`: the Arabic name when the UI is Arabic and the
/// translations carry an Arabic string, else [name].
String kitchenName(String name, Object? translations, String lang) {
  if (lang.startsWith('ar') && translations is Map) {
    final v = translations['ar'];
    if (v is String) return v;
  }
  return name;
}

/// What the routing page reads off its three answers.
class KitchenRouting {
  KitchenRouting({
    required List<KitchenStation> stations,
    required StationRoutes? routes,
  }) : active = [
         for (final s in stations)
           if (s.isActive) s,
       ],
       byCategory = {
         for (final r in routes?.categories ?? const []) r.categoryId: r.stationId,
       },
       byItem = {
         for (final r in routes?.items ?? const []) r.menuItemId: r.stationId,
       };

  /// The stations offered and named: only the active ones.
  final List<KitchenStation> active;
  final Map<String, String> byCategory;
  final Map<String, String> byItem;

  /// The ACTIVE station [id] names; null for none, an unknown or an
  /// inactive one (`stationName`).
  String? stationName(String? id) {
    if (id == null) return null;
    for (final s in active) {
      if (s.id == id) return s.name;
    }
    return null;
  }

  /// The select's value for [id]: the station when it is offered, else
  /// null — an inactive station's route reads as an EMPTY select, not the
  /// "unassigned" choice (SET-KRT-019).
  String? selectValue(String? id) => id == null
      ? kitchenUnassigned
      : active.any((s) => s.id == id)
      ? id
      : null;

  /// The station an item inherits from its category, by name.
  String? inherited(MenuItemWithCosts it) =>
      stationName(it.categoryId == null ? null : byCategory[it.categoryId]);

  /// The item's own override, by name.
  String? override(MenuItemWithCosts it) => stationName(byItem[it.id]);
}

/// The "Default / unassigned" and "Inherit (category)" choice (`UNASSIGNED`).
const String kitchenUnassigned = '__none__';
