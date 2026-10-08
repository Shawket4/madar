/// Today's own reads (INV-TOD-003), one provider per endpoint, keyed the way
/// the web's React Query keys are (the path and its params), each watching
/// `realtimeEpochProvider(<its path>)` so [invalidateInventory] and the
/// shell's realtime (`till.*` → `/reports`, `resync` → everything) refetch
/// it.
///
/// The reads Today shares with other pages (catalog, suppliers, branch stock,
/// stocktakes) are `shared/inventory_data.dart`'s.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show InventoryValuationReport, LowStockRow, PurchaseOrder, StockMovement;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The start (00:00:00.000) and end (23:59:59.999) of today in the ACTIVE
/// zone, as UTC ISO instants (INV-TOD-004).
class TodayBounds {
  const TodayBounds(this.startIso, this.endIso);

  final String startIso;
  final String endIso;

  DateTime get start => DateTime.parse(startIso);
  DateTime get end => DateTime.parse(endIso);

  /// Today's bounds in [zone] at [now].
  factory TodayBounds.at(String zone, DateTime now) {
    final f = DashFormat(timezone: zone, clock: () => now);
    final d = f.cairoNow();
    return TodayBounds(
      f.cairoDateISO(d.year, d.month - 1, d.day),
      f.cairoDateISO(d.year, d.month - 1, d.day, endOfDay: true),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TodayBounds &&
      other.startIso == startIso &&
      other.endIso == endIso;

  @override
  int get hashCode => Object.hash(startIso, endIso);
}

/// Today's bounds, worked out once per visit and again only when the active
/// zone changes — the web memoizes them on the zone alone, so a page left
/// open across midnight keeps yesterday's day (INV-TOD-038).
final todayBoundsProvider = Provider.autoDispose<TodayBounds>((ref) {
  final zone = ref.watch(activeTimezoneProvider);
  final now = ref.read(clockProvider)();
  return TodayBounds.at(zone, now);
});

/// `GET /reports/branches/{branch_id}/inventory-valuation`.
final todayBranchValuationProvider = FutureProvider.autoDispose
    .family<InventoryValuationReport, String>((ref, branchId) {
      ref.webCache();
      ref.watch(
        realtimeEpochProvider(
          '/reports/branches/$branchId/inventory-valuation',
        ),
      );
      return ref
          .watch(apiProvider)
          .reports
          .branchInventoryValuation(branchId: branchId);
    });

/// `GET /reports/orgs/{org_id}/inventory-valuation` (all branches).
final todayOrgValuationProvider = FutureProvider.autoDispose
    .family<InventoryValuationReport, String>((ref, orgId) {
      ref.webCache();
      ref.watch(
        realtimeEpochProvider('/reports/orgs/$orgId/inventory-valuation'),
      );
      return ref.watch(apiProvider).reports.orgInventoryValuation(orgId: orgId);
    });

/// `GET /reports/branches/{branch_id}/low-stock`.
final todayBranchLowStockProvider = FutureProvider.autoDispose
    .family<List<LowStockRow>, String>((ref, branchId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/reports/branches/$branchId/low-stock'));
      return ref.watch(apiProvider).reports.branchLowStock(branchId: branchId);
    });

/// `GET /reports/orgs/{org_id}/low-stock` (every branch of the org).
final todayOrgLowStockProvider = FutureProvider.autoDispose
    .family<List<LowStockRow>, String>((ref, orgId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/reports/orgs/$orgId/low-stock'));
      return ref.watch(apiProvider).reports.orgLowStock(orgId: orgId);
    });

/// Which org's orders, expected by when (an ISO instant).
typedef TodayOrdersKey = ({String orgId, String expectedBefore});

/// `GET /purchasing/orgs/{org_id}/orders?expected_before=<end of today>`:
/// every branch's orders, the org's (INV-TOD-008).
final todayOrdersProvider = FutureProvider.autoDispose
    .family<List<PurchaseOrder>, TodayOrdersKey>((ref, k) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/purchasing/orgs/${k.orgId}/orders'));
      return ref
          .watch(apiProvider)
          .purchasing
          .listOrgPurchaseOrders(
            orgId: k.orgId,
            expectedBefore: DateTime.parse(k.expectedBefore),
          );
    });

/// `GET /inventory/branches/{branch_id}/waste` (the server's default page:
/// the 200 most recent).
final todayWasteProvider = FutureProvider.autoDispose
    .family<List<StockMovement>, String>((ref, branchId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/inventory/branches/$branchId/waste'));
      return ref.watch(apiProvider).inventory.listWaste(branchId: branchId);
    });

/// The orders that are on their way: placed (`ordered`) or partly in
/// (`partially_received`). The list is already cut at the end of today, so
/// an overdue one counts too (INV-TOD-008, INV-TOD-034).
List<PurchaseOrder> arrivingOrders(List<PurchaseOrder> orders) => [
  for (final p in orders)
    if (p.status == 'ordered' || p.status == 'partially_received') p,
];

/// The waste lines the server received since [start] (`created_at`, not when
/// the till says it happened — INV-TOD-024).
List<StockMovement> wasteSince(List<StockMovement> lines, DateTime start) => [
  for (final m in lines)
    if (!m.createdAt.isBefore(start)) m,
];

/// React Query's `isLoading`: the first load, nothing to show yet.
extension TodayAsync<T> on AsyncValue<T> {
  bool get firstLoad => isLoading && !hasValue && !hasError;
}
