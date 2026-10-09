/// The Operations page's reads, one provider per endpoint, keyed by exactly
/// the params its request sends (the web's React Query key), so a branch,
/// period (or language) change asks again and nothing else does. Every read
/// calls `ref.webCache()` first: kept 5 min unwatched, refetched in the
/// background when a tab opens on data older than 30 s (REP-OPS-062).
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

DateTime _instant(String iso) => DateTime.parse(iso);

/// A report read's key: the branch (or org) id and the period it sends.
typedef OpsRange = ({String id, String from, String to});

/// Branch sales' key: its range and the `exclude_items` list (null when
/// nothing is excluded, as the web's `undefined` drops out of its key).
typedef OpsSalesKey = ({String id, String from, String to, String? exclude});

/// The Tables read's key (`["metrics","tables",branchId,from,to,locale]`).
typedef OpsTablesKey = ({String? branchId, String from, String to, String locale});

/// A table history's key.
typedef OpsHistoryKey = ({String id, String from, String to});

/// The one place each read's key is built from the scope (the page, the
/// Retry buttons, the prefetch and the tests all use these).
extension OpsKeys on Scope {
  /// The analytics reads: the branch or the all-branches sentinel.
  OpsRange get opsRange => (id: scopeBranchId, from: from, to: to);

  /// The Branches tab: the org in scope (only read with one).
  OpsRange get opsOrgRange => (id: orgId!, from: from, to: to);

  /// The Overview: [exclude] is `excludeItemsParam(...)`.
  OpsSalesKey opsSales(String? exclude) =>
      (id: scopeBranchId, from: from, to: to, exclude: exclude);

  /// Tables, in [locale] (`ar` or `en`).
  OpsTablesKey opsTables(String locale) =>
      (branchId: branchId, from: from, to: to, locale: locale);
}

/// `i18n.language.startsWith("ar") ? "ar" : "en"`.
String opsMetricsLocale(String lang) => lang.startsWith('ar') ? 'ar' : 'en';

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

/// REP-OPS-006: the branch rides the `X-Branch-Id` header (the scope's), so
/// it is in the key but not in the body.
final opsTablesProvider = FutureProvider.autoDispose
    .family<MetricsQueryResponse, OpsTablesKey>((ref, k) {
      ref.webCache();
      return ref
          .watch(apiProvider)
          .metrics
          .runMetricsQuery(
            body: MetricsQueryRequest(
              locale: k.locale,
              period: Period(from: k.from, to: k.to),
              widgets: tablesWidgets(branchScoped: k.branchId != null),
            ),
          );
    });

/// REP-OPS-025: the floor's tables, to turn a label into a table id.
final opsFloorTablesProvider = FutureProvider.autoDispose
    .family<List<FloorTable>, String>((ref, branchId) {
      ref.webCache();
      return ref
          .watch(apiProvider)
          .reservations
          .listFloorTables(branchId: branchId);
    });

/// REP-OPS-027: a table's history over the scope's period.
final opsTableHistoryProvider = FutureProvider.autoDispose
    .family<TableHistory, OpsHistoryKey>((ref, k) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/floor/tables/${k.id}/history'));
      return ref
          .watch(apiProvider)
          .floor
          .tableHistory(id: k.id, from: _instant(k.from), to: _instant(k.to));
    });

// ── Overview ──────────────────────────────────────────────────────────────

/// REP-OPS-034: branch sales; `exclude` is the `exclude_items` list.
final opsSalesProvider = FutureProvider.autoDispose
    .family<BranchSalesReport, OpsSalesKey>((ref, k) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/reports/branches/${k.id}/sales'));
      return ref
          .watch(apiProvider)
          .reports
          .branchSales(
            branchId: k.id,
            from: _instant(k.from),
            to: _instant(k.to),
            excludeItems: k.exclude,
          );
    });

/// REP-OPS-039: the org's menu, read only once the exclude list opens.
final opsMenuItemsProvider = FutureProvider.autoDispose
    .family<List<MenuItem>, String>((ref, orgId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/menu-items'));
      return ref.watch(apiProvider).menu.listMenuItems(orgId: orgId);
    });

// ── Items, Tellers, Waiters, Branches ─────────────────────────────────────

/// REP-OPS-047: combined item sales, the top 50.
final opsItemsProvider = FutureProvider.autoDispose
    .family<List<CombinedItemSalesRow>, OpsRange>((ref, k) {
      ref.webCache();
      ref.watch(
        realtimeEpochProvider('/reports/branches/${k.id}/items-combined'),
      );
      return ref
          .watch(apiProvider)
          .reports
          .branchCombinedItemSales(
            branchId: k.id,
            from: _instant(k.from),
            to: _instant(k.to),
            limit: 50,
          );
    });

/// REP-OPS-048: the top 20 add-ons.
final opsAddonsProvider = FutureProvider.autoDispose
    .family<List<AddonSalesRow>, OpsRange>((ref, k) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/reports/branches/${k.id}/addons'));
      return ref
          .watch(apiProvider)
          .reports
          .branchAddonSales(
            branchId: k.id,
            from: _instant(k.from),
            to: _instant(k.to),
            limit: 20,
          );
    });

/// REP-OPS-049: teller stats.
final opsTellersProvider = FutureProvider.autoDispose
    .family<List<TellerStats>, OpsRange>((ref, k) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/reports/branches/${k.id}/tellers'));
      return ref
          .watch(apiProvider)
          .reports
          .branchTellerStats(
            branchId: k.id,
            from: _instant(k.from),
            to: _instant(k.to),
            limit: 50,
          );
    });

/// REP-OPS-051: waiter stats.
final opsWaitersProvider = FutureProvider.autoDispose
    .family<WaiterStatsReport, OpsRange>((ref, k) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/reports/branches/${k.id}/waiters'));
      return ref
          .watch(apiProvider)
          .reports
          .branchWaiterStats(
            branchId: k.id,
            from: _instant(k.from),
            to: _instant(k.to),
          );
    });

/// REP-OPS-054: every branch of the org (needs an org in scope).
final opsBranchesProvider = FutureProvider.autoDispose
    .family<OrgComparisonReport, OpsRange>((ref, k) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/reports/orgs/${k.id}/comparison'));
      return ref
          .watch(apiProvider)
          .reports
          .orgBranchComparison(
            orgId: k.id,
            from: _instant(k.from),
            to: _instant(k.to),
          );
    });
