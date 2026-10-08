/// The Operations page's reads, one provider per endpoint, keyed like the
/// web's React Query keys so a branch, period (or language) change asks
/// again:
///
/// - Tables (REP-OPS-006): `POST /metrics/query`, key
///   `["metrics","tables",branchId,from,to,locale]`. Never refreshed by
///   realtime, not even `resync` (REP-OPS-065).
/// - The floor lookup (REP-OPS-025): key `["floor-tables",branchId]`, also
///   never refreshed by realtime.
/// - A table's history (REP-OPS-027): `/floor/tables/{id}/history`,
///   refreshed by floor, table, booking and ticket events.
/// - The analytics reads (REP-OPS-034…054): `/reports/...`, refreshed by a
///   `till.*` event (and `resync`) while a branch is selected (REP-ALL-009).
///
/// Every read stays in the page's [OpsCache] while the page is open.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show
        AddonSalesRow,
        BranchSalesReport,
        CombinedItemSalesRow,
        Dir,
        FloorTable,
        MenuItem,
        MetricsQueryRequest,
        MetricsQueryResponse,
        OrgComparisonReport,
        Period,
        QuerySpec,
        Sort,
        TableHistory,
        TellerStats,
        WaiterStatsReport,
        WidgetRequest;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ops_support.dart';

DateTime _instant(String iso) => DateTime.parse(iso);

/// Runs [fetch] as a cached read of the page: kept while the page is open,
/// its answer time noted under [key] for the stale check.
Future<T> _cached<T>(Ref ref, String key, Future<T> Function() fetch) async {
  final cache = ref.read(opsCacheProvider);
  cache.keep(ref, key);
  final out = await fetch();
  cache.fetched(key);
  return out;
}

// ── Tables ────────────────────────────────────────────────────────────────

/// The `tables` dataset's measures (`tables-util.ts` `TABLE_MEASURES`).
const List<String> tableMeasures = [
  'turns',
  'turns_per_day',
  'covers',
  'table_revenue',
  'revenue_per_cover',
  'avg_dwell_minutes',
];

/// The three widgets the Tables tab asks for (`SPECS`, `byTableSpec`).
List<WidgetRequest> tablesWidgets({required bool branchScoped}) => [
  const WidgetRequest(
    key: 'summary',
    spec: QuerySpec(
      dataset: 'tables',
      measures: [...tableMeasures, 'active_tables', 'revenue_per_table'],
    ),
  ),
  WidgetRequest(
    key: 'byTable',
    spec: QuerySpec(
      dataset: 'tables',
      // The metrics engine takes two dimensions: one branch → section +
      // table; every branch → branch + table (sections can collide).
      dimensions: branchScoped ? ['section', 'table'] : ['branch', 'table'],
      measures: tableMeasures,
      sort: const Sort(measure: 'turns', dir: Dir.desc),
      limit: 500,
    ),
  ),
  const WidgetRequest(
    key: 'byHour',
    spec: QuerySpec(
      dataset: 'tables',
      dimensions: ['hour'],
      measures: ['turns', 'covers'],
      limit: 24,
    ),
  ),
];

String tablesKey(Scope s, String locale) =>
    'metrics|tables|${s.branchId}|${s.from}|${s.to}|$locale';

/// REP-OPS-006: the branch rides the `X-Branch-Id` header (the scope's).
final opsTablesProvider = FutureProvider.autoDispose
    .family<MetricsQueryResponse, (Scope, String)>((ref, k) {
      ref.webCache();
      final (s, locale) = k;
      return _cached(
        ref,
        tablesKey(s, locale),
        () => ref
            .watch(apiProvider)
            .metrics
            .runMetricsQuery(
              body: MetricsQueryRequest(
                locale: locale,
                period: Period(from: s.from, to: s.to),
                widgets: tablesWidgets(branchScoped: s.branchId != null),
              ),
            ),
      );
    });

/// REP-OPS-025: the floor's tables, to turn a label into a table id.
final opsFloorTablesProvider = FutureProvider.autoDispose
    .family<List<FloorTable>, String>((ref, branchId) {
      ref.webCache();
      return _cached(
        ref,
        'floor-tables|$branchId',
        () => ref
            .watch(apiProvider)
            .reservations
            .listFloorTables(branchId: branchId),
      );
    });

/// REP-OPS-027: a table's history over the scope's period.
final opsTableHistoryProvider = FutureProvider.autoDispose
    .family<TableHistory, (String, String, String)>((ref, k) {
      ref.webCache();
      final (id, from, to) = k;
      ref.watch(realtimeEpochProvider('/floor/tables/$id/history'));
      return _cached(
        ref,
        'history|$id|$from|$to',
        () => ref
            .watch(apiProvider)
            .floor
            .tableHistory(id: id, from: _instant(from), to: _instant(to)),
      );
    });

// ── Overview ──────────────────────────────────────────────────────────────

String salesKey(Scope s, String? exclude) =>
    'sales|${s.scopeBranchId}|${s.from}|${s.to}|$exclude';

/// REP-OPS-034: branch sales; [exclude] is the `exclude_items` list (null
/// when nothing is excluded).
final opsSalesProvider = FutureProvider.autoDispose
    .family<BranchSalesReport, (Scope, String?)>((ref, k) {
      ref.webCache();
      final (s, exclude) = k;
      ref.watch(
        realtimeEpochProvider('/reports/branches/${s.scopeBranchId}/sales'),
      );
      return _cached(
        ref,
        salesKey(s, exclude),
        () => ref
            .watch(apiProvider)
            .reports
            .branchSales(
              branchId: s.scopeBranchId,
              from: _instant(s.from),
              to: _instant(s.to),
              excludeItems: exclude,
            ),
      );
    });

/// REP-OPS-039: the org's menu, read only once the exclude list opens.
final opsMenuItemsProvider = FutureProvider.autoDispose
    .family<List<MenuItem>, String>((ref, orgId) {
      ref.webCache();
      return ref.watch(apiProvider).menu.listMenuItems(orgId: orgId);
    });

// ── Items, Tellers, Waiters, Branches ─────────────────────────────────────

String itemsKey(Scope s) => 'items|${s.scopeBranchId}|${s.from}|${s.to}';
String addonsKey(Scope s) => 'addons|${s.scopeBranchId}|${s.from}|${s.to}';
String tellersKey(Scope s) => 'tellers|${s.scopeBranchId}|${s.from}|${s.to}';
String waitersKey(Scope s) => 'waiters|${s.scopeBranchId}|${s.from}|${s.to}';
String branchesKey(Scope s) => 'branches|${s.orgId}|${s.from}|${s.to}';

/// REP-OPS-047: combined item sales, the top 50.
final opsItemsProvider = FutureProvider.autoDispose
    .family<List<CombinedItemSalesRow>, Scope>((ref, s) {
      ref.webCache();
      ref.watch(
        realtimeEpochProvider(
          '/reports/branches/${s.scopeBranchId}/items-combined',
        ),
      );
      return _cached(
        ref,
        itemsKey(s),
        () => ref
            .watch(apiProvider)
            .reports
            .branchCombinedItemSales(
              branchId: s.scopeBranchId,
              from: _instant(s.from),
              to: _instant(s.to),
              limit: 50,
            ),
      );
    });

/// REP-OPS-048: the top 20 add-ons.
final opsAddonsProvider = FutureProvider.autoDispose
    .family<List<AddonSalesRow>, Scope>((ref, s) {
      ref.webCache();
      ref.watch(
        realtimeEpochProvider('/reports/branches/${s.scopeBranchId}/addons'),
      );
      return _cached(
        ref,
        addonsKey(s),
        () => ref
            .watch(apiProvider)
            .reports
            .branchAddonSales(
              branchId: s.scopeBranchId,
              from: _instant(s.from),
              to: _instant(s.to),
              limit: 20,
            ),
      );
    });

/// REP-OPS-049: teller stats.
final opsTellersProvider = FutureProvider.autoDispose
    .family<List<TellerStats>, Scope>((ref, s) {
      ref.webCache();
      ref.watch(
        realtimeEpochProvider('/reports/branches/${s.scopeBranchId}/tellers'),
      );
      return _cached(
        ref,
        tellersKey(s),
        () => ref
            .watch(apiProvider)
            .reports
            .branchTellerStats(
              branchId: s.scopeBranchId,
              from: _instant(s.from),
              to: _instant(s.to),
              limit: 50,
            ),
      );
    });

/// REP-OPS-051: waiter stats.
final opsWaitersProvider = FutureProvider.autoDispose
    .family<WaiterStatsReport, Scope>((ref, s) {
      ref.webCache();
      ref.watch(
        realtimeEpochProvider('/reports/branches/${s.scopeBranchId}/waiters'),
      );
      return _cached(
        ref,
        waitersKey(s),
        () => ref
            .watch(apiProvider)
            .reports
            .branchWaiterStats(
              branchId: s.scopeBranchId,
              from: _instant(s.from),
              to: _instant(s.to),
            ),
      );
    });

/// REP-OPS-054: every branch of the org (needs an org in scope).
final opsBranchesProvider = FutureProvider.autoDispose
    .family<OrgComparisonReport, Scope>((ref, s) {
      ref.webCache();
      final org = s.orgId!;
      ref.watch(realtimeEpochProvider('/reports/orgs/$org/comparison'));
      return _cached(
        ref,
        branchesKey(s),
        () => ref
            .watch(apiProvider)
            .reports
            .orgBranchComparison(
              orgId: org,
              from: _instant(s.from),
              to: _instant(s.to),
            ),
      );
    });

// ── the excluded items (REP-OPS-039/068) ──────────────────────────────────

/// The device setting's key, shared with the Orders page's Items Sold KPI
/// (`madar.excluded-line-items.<orgId>`).
String excludedItemsPrefKey(String orgId) => 'madar.excluded-line-items.$orgId';

/// The menu item ids left out of Items Sold, per org on this device. Read
/// again whenever the page mounts or the org changes; nothing is saved
/// without an org.
class ExcludedItems extends Notifier<List<String>> {
  ExcludedItems(this.orgId);

  final String? orgId;

  @override
  List<String> build() {
    final org = orgId;
    if (org == null) return const [];
    final raw = ref
        .read(preferencesProvider)
        .getJson(excludedItemsPrefKey(org));
    return raw is List ? [for (final v in raw) '$v'] : const [];
  }

  void set(List<String> ids) {
    state = List.unmodifiable(ids);
    final org = orgId;
    if (org != null) {
      ref.read(preferencesProvider).setJson(excludedItemsPrefKey(org), ids);
    }
  }

  void toggle(String id) => set(
    state.contains(id) ? [...state.where((x) => x != id)] : [...state, id],
  );
}

final excludedItemsProvider = NotifierProvider.autoDispose
    .family<ExcludedItems, List<String>, String?>(ExcludedItems.new);

/// `excludeItemsParam`: the comma list, or null when nothing is excluded.
String? excludeItemsParam(List<String> ids) =>
    ids.isEmpty ? null : ids.join(',');
