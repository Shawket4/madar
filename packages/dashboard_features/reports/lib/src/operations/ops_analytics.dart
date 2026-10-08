/// Operations › Items, Tellers, Waiters and Branches
/// (`features/analytics/analytics-page.tsx`, REP-OPS-047…055, 063, 064):
/// each a leaderboard chart and/or a table of its rows.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show
        AddonSalesRow,
        BranchComparison,
        CombinedItemSalesRow,
        OrgComparisonReport,
        TellerStats,
        WaiterStats;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderBase;

import '../shared/report_shared.dart';
import 'ops_charts.dart';
import 'ops_data.dart';
import 'ops_support.dart';

/// A card holding a table edge to edge (the web's `ChartCard
/// contentClassName="px-0"` around a frameless `DataTable`).
class OpsTableCard extends StatelessWidget {
  const OpsTableCard({
    required this.title,
    required this.child,
    this.footer,
    super.key,
  });

  final String title;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final phone = DashBreakpoints.isPhone(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: Space.card),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: c.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.lg,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.card),
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: DashType.sectionTitle.copyWith(color: c.textPrimary),
              ),
            ),
          ),
          // Phone cards need a margin; the wide table runs edge to edge.
          Padding(
            padding: EdgeInsets.symmetric(horizontal: phone ? Space.md : 0),
            child: child,
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: footer,
            ),
        ],
      ),
    );
  }
}

/// Refetch a tab's reads quietly when they are older than the stale time
/// (REP-OPS-062), once, when the tab is shown again.
void _refreshIfStale(
  WidgetRef ref,
  List<(String, ProviderBase<Object?>)> reads,
) {
  final cache = ref.read(opsCacheProvider);
  for (final (key, p) in reads) {
    if (cache.isStale(key)) ref.invalidate(p);
  }
}

mixin _StaleOnShow<W extends ConsumerStatefulWidget> on ConsumerState<W> {
  List<(String, ProviderBase<Object?>)> reads(Scope scope);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshIfStale(ref, reads(ref.read(currentScopeProvider)));
    });
  }
}

DashEmptyState _noData(Translator t) =>
    DashEmptyState(title: t('analytics.noData'), framed: false);

// ── Items ─────────────────────────────────────────────────────────────────

class OpsItemsView extends ConsumerStatefulWidget {
  const OpsItemsView({super.key});

  @override
  ConsumerState<OpsItemsView> createState() => _OpsItemsViewState();
}

class _OpsItemsViewState extends ConsumerState<OpsItemsView> with _StaleOnShow {
  @override
  List<(String, ProviderBase<Object?>)> reads(Scope s) => [
    (itemsKey(s), opsItemsProvider(s)),
    (addonsKey(s), opsAddonsProvider(s)),
  ];

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final lang = ref.watch(localeProvider);
    final c = context.madarColors;
    final scope = ref.watch(currentScopeProvider);
    final items = ref.watch(opsItemsProvider(scope));
    final addons = ref.watch(opsAddonsProvider(scope));
    final strong = DashType.monoStrong.copyWith(color: c.textPrimary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        OpsTableCard(
          title: t('analytics.tabs.items'),
          child: DashDataTable<CombinedItemSalesRow>(
            key: const ValueKey('ops-items-table'),
            framed: false,
            hideViewOptions: true,
            pageSize: 50,
            rows: items.value ?? const [],
            rowKey: (r) => r.itemId,
            loading: items.firstLoad,
            errorMessage: items.hasError ? opsErrorText(items.error, t) : null,
            onRetry: () => ref.invalidate(opsItemsProvider(scope)),
            empty: _noData(t),
            columns: [
              DashColumn<CombinedItemSalesRow>(
                id: 'name',
                label: t('common.name'),
                phone: DashPhoneRole.title,
                flex: 3,
                text: (r) =>
                    translatedName(r.itemName, r.itemNameTranslations, lang),
                cell: (context, r) => MadarClippedText(
                  translatedName(r.itemName, r.itemNameTranslations, lang),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                ),
              ),
              DashColumn<CombinedItemSalesRow>(
                id: 'total',
                label: t('analytics.totalSold'),
                numeric: true,
                text: (r) => fmtNum(f, r.totalQty),
                cell: (context, r) =>
                    Text(dashFigure(fmtNum(f, r.totalQty)), style: strong),
              ),
            ],
          ),
        ),
        OpsTableCard(
          title: t('analytics.addonSales'),
          child: DashDataTable<AddonSalesRow>(
            key: const ValueKey('ops-addons-table'),
            framed: false,
            hideViewOptions: true,
            rows: addons.value ?? const [],
            rowKey: (r) => r.addonItemId,
            loading: addons.firstLoad,
            errorMessage: addons.hasError
                ? opsErrorText(addons.error, t)
                : null,
            onRetry: () => ref.invalidate(opsAddonsProvider(scope)),
            empty: _noData(t),
            columns: [
              DashColumn<AddonSalesRow>(
                id: 'name',
                label: t('common.name'),
                phone: DashPhoneRole.title,
                flex: 3,
                text: (r) =>
                    translatedName(r.addonName, r.addonNameTranslations, lang),
                cell: (context, r) => MadarClippedText(
                  translatedName(r.addonName, r.addonNameTranslations, lang),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                ),
              ),
              DashColumn<AddonSalesRow>(
                id: 'sold',
                label: t('analytics.sold'),
                numeric: true,
                text: (r) => fmtNum(f, r.quantitySold),
              ),
              DashColumn<AddonSalesRow>(
                id: 'revenue',
                label: t('dashboard.revenue'),
                numeric: true,
                text: (r) => f.fmtMoney(r.revenue),
                cell: (context, r) =>
                    Text(dashFigure(f.fmtMoney(r.revenue)), style: strong),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Tellers ───────────────────────────────────────────────────────────────

class OpsTellersView extends ConsumerStatefulWidget {
  const OpsTellersView({super.key});

  @override
  ConsumerState<OpsTellersView> createState() => _OpsTellersViewState();
}

class _OpsTellersViewState extends ConsumerState<OpsTellersView>
    with _StaleOnShow {
  @override
  List<(String, ProviderBase<Object?>)> reads(Scope s) => [
    (tellersKey(s), opsTellersProvider(s)),
  ];

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final scope = ref.watch(currentScopeProvider);
    final q = ref.watch(opsTellersProvider(scope));
    final rows = q.value ?? const <TellerStats>[];
    final chart = [...rows]..sort((a, b) => b.revenue.compareTo(a.revenue));
    final top = chart.take(10).toList();
    void retry() => ref.invalidate(opsTellersProvider(scope));
    final strong = DashType.monoStrong.copyWith(color: c.textPrimary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        DashChartCard(
          title: t('analytics.revenueByTeller'),
          child: OpsChartBody(
            loading: q.firstLoad,
            failed: q.hasError,
            empty: top.isEmpty,
            emptyTitle: t('analytics.noData'),
            onRetry: retry,
            chart: (_) => OpsHBarChart(
              key: const ValueKey('ops-tellers-chart'),
              labels: [for (final r in top) r.tellerName],
              values: [for (final r in top) r.revenue.toDouble()],
              color: opsChartColor(c, 2),
              formatAxis: f.fmtMoneyCompact,
              tooltip: (i) =>
                  '${t('dashboard.revenue')}: ${f.fmtMoney(top[i].revenue)}',
            ),
          ),
        ),
        OpsTableCard(
          title: t('analytics.tellerDetails'),
          child: DashDataTable<TellerStats>(
            key: const ValueKey('ops-tellers-table'),
            framed: false,
            hideViewOptions: true,
            pageSize: 50,
            rows: rows,
            rowKey: (r) => r.tellerId,
            loading: q.firstLoad,
            errorMessage: q.hasError ? opsErrorText(q.error, t) : null,
            onRetry: retry,
            empty: _noData(t),
            columns: [
              DashColumn<TellerStats>(
                id: 'name',
                label: t('users.role'),
                phone: DashPhoneRole.title,
                flex: 2,
                text: (r) => r.tellerName,
                cell: (context, r) => MadarClippedText(
                  r.tellerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                ),
              ),
              DashColumn<TellerStats>(
                id: 'orders',
                label: t('dashboard.orders'),
                numeric: true,
                minWidth: 80,
                text: (r) => fmtNum(f, r.orders),
              ),
              DashColumn<TellerStats>(
                id: 'revenue',
                label: t('dashboard.revenue'),
                numeric: true,
                text: (r) => f.fmtMoney(r.revenue),
                cell: (context, r) =>
                    Text(dashFigure(f.fmtMoney(r.revenue)), style: strong),
              ),
              DashColumn<TellerStats>(
                id: 'aov',
                label: t('analytics.aov'),
                numeric: true,
                text: (r) => f.fmtMoney(r.avgOrderValue),
              ),
              DashColumn<TellerStats>(
                id: 'voided',
                label: t('orders.voided'),
                numeric: true,
                minWidth: 96,
                text: (r) => fmtNum(f, r.voided),
              ),
              DashColumn<TellerStats>(
                id: 'tills',
                label: t('nav.tills'),
                numeric: true,
                minWidth: 80,
                text: (r) => fmtNum(f, r.shifts),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Waiters ───────────────────────────────────────────────────────────────

class OpsWaitersView extends ConsumerStatefulWidget {
  const OpsWaitersView({super.key});

  @override
  ConsumerState<OpsWaitersView> createState() => _OpsWaitersViewState();
}

class _OpsWaitersViewState extends ConsumerState<OpsWaitersView>
    with _StaleOnShow {
  @override
  List<(String, ProviderBase<Object?>)> reads(Scope s) => [
    (waitersKey(s), opsWaitersProvider(s)),
  ];

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final scope = ref.watch(currentScopeProvider);
    final q = ref.watch(opsWaitersProvider(scope));
    final report = q.value;
    final rows = report?.waiters ?? const <WaiterStats>[];
    final top = ([
      ...rows,
    ]..sort((a, b) => b.revenue.compareTo(a.revenue))).take(10).toList();
    void retry() => ref.invalidate(opsWaitersProvider(scope));
    final strong = DashType.monoStrong.copyWith(color: c.textPrimary);
    final coverage =
        !q.isLoading && !q.hasError && report != null && report.totalOrders > 0
        ? Text(
            t(
              'analytics.waiterCoverage',
              args: {
                'attributed': fmtNum(f, report.attributedOrders),
                'total': fmtNum(f, report.totalOrders),
              },
            ),
            style: DashType.small.copyWith(color: c.textSecondary),
          )
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        DashChartCard(
          title: t('analytics.revenueByWaiter'),
          child: OpsChartBody(
            loading: q.firstLoad,
            failed: q.hasError,
            empty: top.isEmpty,
            emptyTitle: t('analytics.noData'),
            onRetry: retry,
            chart: (_) => OpsHBarChart(
              key: const ValueKey('ops-waiters-chart'),
              labels: [for (final r in top) r.waiterName],
              values: [for (final r in top) r.revenue.toDouble()],
              color: opsChartColor(c, 4),
              formatAxis: f.fmtMoneyCompact,
              tooltip: (i) =>
                  '${t('dashboard.revenue')}: ${f.fmtMoney(top[i].revenue)}',
            ),
          ),
        ),
        OpsTableCard(
          title: t('analytics.waiterDetails'),
          footer: coverage,
          child: DashDataTable<WaiterStats>(
            key: const ValueKey('ops-waiters-table'),
            framed: false,
            hideViewOptions: true,
            pageSize: 50,
            rows: rows,
            rowKey: (r) => r.waiterId,
            loading: q.firstLoad,
            errorMessage: q.hasError ? opsErrorText(q.error, t) : null,
            onRetry: retry,
            empty: _noData(t),
            columns: [
              DashColumn<WaiterStats>(
                id: 'name',
                label: t('tills.waiter'),
                phone: DashPhoneRole.title,
                flex: 2,
                text: (r) => r.waiterName,
                cell: (context, r) => MadarClippedText(
                  r.waiterName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                ),
              ),
              DashColumn<WaiterStats>(
                id: 'orders',
                label: t('dashboard.orders'),
                numeric: true,
                minWidth: 80,
                text: (r) => fmtNum(f, r.orders),
              ),
              DashColumn<WaiterStats>(
                id: 'revenue',
                label: t('dashboard.revenue'),
                numeric: true,
                text: (r) => f.fmtMoney(r.revenue),
                cell: (context, r) =>
                    Text(dashFigure(f.fmtMoney(r.revenue)), style: strong),
              ),
              DashColumn<WaiterStats>(
                id: 'aov',
                label: t('analytics.aov'),
                numeric: true,
                text: (r) => f.fmtMoney(r.avgOrderValue),
              ),
              DashColumn<WaiterStats>(
                id: 'items',
                label: t('analytics.itemsSold'),
                numeric: true,
                minWidth: 96,
                text: (r) => fmtNum(f, r.lineItems),
              ),
              DashColumn<WaiterStats>(
                id: 'ipo',
                label: t('analytics.itemsPerOrder'),
                numeric: true,
                minWidth: 96,
                text: (r) => fmtNum(f, r.avgItemsPerOrder, maxDp: 1),
              ),
              DashColumn<WaiterStats>(
                id: 'voided',
                label: t('orders.voided'),
                numeric: true,
                minWidth: 96,
                text: (r) => fmtNum(f, r.voided),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Branches ──────────────────────────────────────────────────────────────

class OpsBranchesView extends ConsumerStatefulWidget {
  const OpsBranchesView({super.key});

  @override
  ConsumerState<OpsBranchesView> createState() => _OpsBranchesViewState();
}

class _OpsBranchesViewState extends ConsumerState<OpsBranchesView>
    with _StaleOnShow {
  @override
  List<(String, ProviderBase<Object?>)> reads(Scope s) => [
    if (s.orgId != null) (branchesKey(s), opsBranchesProvider(s)),
  ];

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final scope = ref.watch(currentScopeProvider);
    // No org in scope (a platform admin who has not picked one): the read
    // stays off, as the web's `enabled: !!orgId`.
    final AsyncValue<OrgComparisonReport?> q = scope.orgId == null
        ? const AsyncData(null)
        : ref.watch(opsBranchesProvider(scope));
    final report = q.value;
    final rows = report?.branches ?? const <BranchComparison>[];
    final chart = [...rows]
      ..sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));
    void retry() => ref.invalidate(opsBranchesProvider(scope));
    final strong = DashType.monoStrong.copyWith(color: c.textPrimary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        DashChartCard(
          title: t('analytics.revenueByBranch'),
          child: OpsChartBody(
            loading: q.firstLoad,
            failed: q.hasError,
            empty: chart.isEmpty,
            emptyTitle: t('analytics.noData'),
            onRetry: retry,
            chart: (_) => OpsBarChart(
              key: const ValueKey('ops-branches-chart'),
              labels: [for (final r in chart) r.branchName],
              values: [for (final r in chart) r.totalRevenue.toDouble()],
              color: opsChartColor(c, 0),
              formatAxis: f.fmtMoneyCompact,
              tooltip: (i) =>
                  '${t('dashboard.revenue')}: ${f.fmtMoney(chart[i].totalRevenue)}',
            ),
          ),
        ),
        OpsTableCard(
          title: t('analytics.branchDetails'),
          child: DashDataTable<BranchComparison>(
            key: const ValueKey('ops-branches-table'),
            framed: false,
            hideViewOptions: true,
            pageSize: 50,
            rows: rows,
            rowKey: (r) => r.branchId,
            loading: q.firstLoad,
            errorMessage: q.hasError ? opsErrorText(q.error, t) : null,
            onRetry: retry,
            empty: _noData(t),
            columns: [
              DashColumn<BranchComparison>(
                id: 'name',
                label: t('nav.branches'),
                phone: DashPhoneRole.title,
                flex: 2,
                text: (r) => r.branchName,
                cell: (context, r) => MadarClippedText(
                  r.branchName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                ),
              ),
              DashColumn<BranchComparison>(
                id: 'orders',
                label: t('dashboard.orders'),
                numeric: true,
                minWidth: 80,
                text: (r) => fmtNum(f, r.totalOrders),
              ),
              DashColumn<BranchComparison>(
                id: 'revenue',
                label: t('dashboard.revenue'),
                numeric: true,
                text: (r) => f.fmtMoney(r.totalRevenue),
                cell: (context, r) =>
                    Text(dashFigure(f.fmtMoney(r.totalRevenue)), style: strong),
              ),
              DashColumn<BranchComparison>(
                id: 'aov',
                label: t('analytics.aov'),
                numeric: true,
                text: (r) => f.fmtMoney(r.avgOrderValue),
              ),
              DashColumn<BranchComparison>(
                id: 'void',
                label: t('analytics.voidRate'),
                numeric: true,
                minWidth: 96,
                text: (r) => f.fmtPercent(r.voidRatePct / 100),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
