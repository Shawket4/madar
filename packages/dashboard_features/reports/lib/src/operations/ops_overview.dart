/// Operations › Overview (`features/analytics/analytics-page.tsx`
/// `OverviewTab`, REP-OPS-034…046, 064, 068, 069): branch sales for the
/// period as six KPIs (Items Sold carrying the exclude control), revenue by
/// payment method beside revenue by category (two columns from 1024 px), and
/// the top items by quantity.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show BranchSalesReport, MenuItem;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/report_shared.dart';
import 'ops_charts.dart';
import 'ops_data.dart';
import 'ops_support.dart';

/// One payment method's slice: value > 0, largest first (`ap:71-74`).
List<(String, int)> opsPaymentSlices(BranchSalesReport? d) {
  final map = d?.revenueByMethod;
  if (map is! Map) return const [];
  final out = <(String, int)>[
    for (final e in map.entries)
      if (e.value is num && (e.value as num) > 0)
        ('${e.key}', (e.value as num).toInt()),
  ]..sort((a, b) => b.$2.compareTo(a.$2));
  return out;
}

class OpsOverviewView extends ConsumerStatefulWidget {
  const OpsOverviewView({super.key});

  @override
  ConsumerState<OpsOverviewView> createState() => _OpsOverviewViewState();
}

class _OpsOverviewViewState extends ConsumerState<OpsOverviewView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final scope = ref.read(currentScopeProvider);
      final exclude = excludeItemsParam(
        ref.read(excludedItemsProvider(scope.orgId)),
      );
      if (ref.read(opsCacheProvider).isStale(salesKey(scope, exclude))) {
        ref.invalidate(opsSalesProvider((scope, exclude)));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final lang = ref.watch(localeProvider);
    final c = context.madarColors;
    final scope = ref.watch(currentScopeProvider);
    final excluded = ref.watch(excludedItemsProvider(scope.orgId));
    final key = (scope, excludeItemsParam(excluded));
    final q = ref.watch(opsSalesProvider(key));
    void retry() => ref.invalidate(opsSalesProvider(key));
    final d = q.value;
    final loading = q.firstLoad;
    final failed = q.hasError;
    final aov = d != null && d.totalOrders > 0
        ? (d.totalRevenue / d.totalOrders).round()
        : 0;
    final payments = opsPaymentSlices(d);
    final byCategory = [
      for (final cat in d?.byCategory ?? const [])
        (
          translatedName(
            cat.categoryName ?? '—',
            cat.categoryNameTranslations,
            lang,
          ),
          cat.revenue,
        ),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    final topCategories = byCategory.take(10).toList();
    // Every card keeps the exclude button's 44 pt row, so the strip's cards
    // share one height.
    const room = SizedBox(height: DashMetrics.target);

    final kpis = DashLedgerStrip(
      items: [
        DashLedgerItem(
          key: 'revenue',
          label: t('dashboard.revenue'),
          icon: 'coins',
          value: d?.totalRevenue ?? 0,
          format: DashStatFormat.money,
          loading: loading,
          action: room,
        ),
        DashLedgerItem(
          key: 'tax',
          label: t('orders.tax'),
          icon: 'percent',
          tone: DashTone.info,
          value: d?.totalTax ?? 0,
          format: DashStatFormat.money,
          loading: loading,
          action: room,
        ),
        DashLedgerItem(
          key: 'orders',
          label: t('dashboard.orders'),
          icon: 'receipt',
          tone: DashTone.accent,
          value: d?.totalOrders ?? 0,
          format: DashStatFormat.number,
          loading: loading,
          action: room,
        ),
        DashLedgerItem(
          key: 'line_items',
          label: t('analytics.itemsSold'),
          icon: 'shopping-basket',
          tone: DashTone.info,
          value: d?.totalLineItems ?? 0,
          format: DashStatFormat.number,
          loading: loading,
          hint: excluded.isEmpty
              ? null
              : t('analytics.nExcluded', count: excluded.length),
          action: OpsExcludeItemsControl(orgId: scope.orgId),
        ),
        DashLedgerItem(
          key: 'aov',
          label: t('analytics.avgOrder'),
          icon: 'trending-up',
          tone: DashTone.info,
          value: aov,
          format: DashStatFormat.money,
          loading: loading,
          action: room,
        ),
        DashLedgerItem(
          key: 'voided',
          label: t('orders.voided'),
          icon: 'ban',
          tone: DashTone.warning,
          value: d?.voidedOrders ?? 0,
          format: DashStatFormat.number,
          loading: loading,
          action: room,
        ),
      ],
    );

    final noData = t('analytics.noData');
    final paymentCard = DashChartCard(
      title: t('analytics.revenueByPayment'),
      child: OpsChartBody(
        loading: loading,
        failed: failed,
        empty: payments.isEmpty,
        emptyTitle: noData,
        onRetry: retry,
        chart: (_) => Column(
          mainAxisSize: MainAxisSize.min,
          spacing: Space.md,
          children: [
            SizedBox(
              height: opsChartHeight,
              child: Center(
                child: DashDonutChart(
                  key: const ValueKey('ops-payment-donut'),
                  size: opsChartHeight * 0.8,
                  legend: false,
                  centerValue: '',
                  centerLabel: '',
                  formatValue: (v) => f.fmtMoney(v),
                  slices: [
                    for (final (i, (m, v)) in payments.indexed)
                      DashSlice(
                        label: paymentMethodLabel(t, m),
                        value: v.toDouble(),
                        color: opsPaymentColor(c, m, i),
                      ),
                  ],
                ),
              ),
            ),
            // Swatch + label + amount: colour is never the only signal.
            Wrap(
              alignment: WrapAlignment.center,
              spacing: Space.lg,
              runSpacing: Space.xs + DashMetrics.hair,
              children: [
                for (final (i, (m, v)) in payments.indexed)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: Space.xs + DashMetrics.hair,
                    children: [
                      Container(
                        width: Space.sm + DashMetrics.hair,
                        height: Space.sm + DashMetrics.hair,
                        decoration: BoxDecoration(
                          color: opsPaymentColor(c, m, i),
                          borderRadius: BorderRadius.circular(DashMetrics.hair),
                        ),
                      ),
                      Text(
                        paymentMethodLabel(t, m),
                        style: DashType.small.copyWith(color: c.textSecondary),
                      ),
                      Text(
                        dashFigure(f.fmtMoney(v)),
                        style: DashType.smallMedium.copyWith(
                          color: c.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );

    final categoryCard = DashChartCard(
      title: t('analytics.byCategory'),
      child: OpsChartBody(
        loading: loading,
        failed: failed,
        empty: topCategories.isEmpty,
        emptyTitle: noData,
        onRetry: retry,
        chart: (_) => OpsBarChart(
          key: const ValueKey('ops-by-category'),
          labels: [for (final (n, _) in topCategories) n],
          values: [for (final (_, v) in topCategories) v.toDouble()],
          color: opsChartColor(c, 0),
          formatAxis: f.fmtMoneyCompact,
          tooltip: (i) =>
              '${t('dashboard.revenue')}: ${f.fmtMoney(topCategories[i].$2)}',
        ),
      ),
    );

    final top = (d?.topItems ?? const []).take(10).toList();
    final topCard = DashChartCard(
      title: t('analytics.topItemsQty'),
      child: OpsChartBody(
        height: null,
        loading: false,
        failed: failed,
        empty: !loading && top.isEmpty,
        emptyTitle: noData,
        onRetry: retry,
        chart: (_) => loading
            ? const Column(
                spacing: Space.sm,
                children: [
                  for (var i = 0; i < 5; i++)
                    DashSkeleton(height: Space.xxl + Space.xs),
                ],
              )
            : Column(
                children: [
                  for (final (i, it) in top.indexed)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: Space.sm + DashMetrics.hair,
                      ),
                      decoration: BoxDecoration(
                        border: i == top.length - 1
                            ? null
                            : Border(bottom: BorderSide(color: c.hairline)),
                      ),
                      child: Row(
                        spacing: Space.md,
                        children: [
                          SizedBox(
                            width: Space.xl,
                            child: Text(
                              dashFigure('${i + 1}'),
                              textAlign: TextAlign.end,
                              style: DashType.mono.copyWith(
                                fontSize: 12,
                                color: c.textSecondary,
                              ),
                            ),
                          ),
                          Expanded(
                            child: MadarClippedText(
                              translatedName(
                                it.itemName,
                                it.itemNameTranslations,
                                lang,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DashType.bodyMedium.copyWith(
                                color: c.textPrimary,
                              ),
                            ),
                          ),
                          Text(
                            '${dashFigure(fmtNum(f, it.quantitySold))} '
                            '${t('analytics.sold')}',
                            style: DashType.small.copyWith(
                              color: c.textSecondary,
                            ),
                          ),
                          ConstrainedBox(
                            constraints: const BoxConstraints(
                              minWidth: Space.xxl * 3,
                            ),
                            child: Text(
                              dashFigure(f.fmtMoney(it.revenue)),
                              textAlign: TextAlign.end,
                              style: DashType.monoStrong.copyWith(
                                color: c.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );

    final wide = MediaQuery.sizeOf(context).width >= DashBreakpoints.lg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        kpis,
        if (wide)
          OpsEqualRow(children: [paymentCard, categoryCard])
        else ...[
          paymentCard,
          categoryCard,
        ],
        topCard,
      ],
    );
  }
}

// ── the exclude control (REP-OPS-039/040/068) ─────────────────────────────

/// A funnel on the Items Sold card: a searchable list of the menu where a
/// tap leaves an item out of the count (and puts it back), saved per org on
/// this device. The menu loads only once the list opens.
class OpsExcludeItemsControl extends ConsumerWidget {
  const OpsExcludeItemsControl({required this.orgId, super.key});

  final String? orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final excluded = ref.watch(excludedItemsProvider(orgId));
    final any = excluded.isNotEmpty;
    return DashPopover(
      width: Space.xxl * 8,
      align: DashPopoverAlign.end,
      anchor: (context, ctl) => DashPressable(
        key: const ValueKey('ops-exclude-trigger'),
        onTap: ctl.toggle,
        pressScale: false,
        tooltip: t('analytics.excludeItems'),
        semanticLabel: t('analytics.excludeItems'),
        excludeChildSemantics: true,
        builder: (context, s) => SizedBox.square(
          dimension: DashMetrics.target,
          child: Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                DashIcon(
                  'list-filter',
                  size: IconSize.xs,
                  color: any ? c.info : c.textSecondary,
                ),
                if (any)
                  PositionedDirectional(
                    end: -Space.sm,
                    top: -Space.sm,
                    child: Container(
                      width: Space.md + DashMetrics.hair,
                      height: Space.md + DashMetrics.hair,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.info,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${excluded.length}',
                        style: DashType.smallStrong.copyWith(
                          fontSize: 9,
                          height: 1,
                          color: c.textOnAccent,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      content: (context, ctl) => _ExcludeList(orgId: orgId),
    );
  }
}

class _ExcludeList extends ConsumerStatefulWidget {
  const _ExcludeList({required this.orgId});

  final String? orgId;

  @override
  ConsumerState<_ExcludeList> createState() => _ExcludeListState();
}

class _ExcludeListState extends ConsumerState<_ExcludeList> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final lang = ref.watch(localeProvider);
    final c = context.madarColors;
    final org = widget.orgId;
    final excluded = ref.watch(excludedItemsProvider(org));
    final notifier = ref.read(excludedItemsProvider(org).notifier);
    final AsyncValue<List<MenuItem>> menu = org == null
        ? const AsyncData(<MenuItem>[])
        : ref.watch(opsMenuItemsProvider(org));
    final options = [
      for (final m in menu.value ?? const <MenuItem>[])
        (m.id, translatedName(m.name, m.nameTranslations, lang)),
    ];
    final q = _query.trim().toLowerCase();
    final shown = [
      for (final o in options)
        if (q.isEmpty || o.$2.toLowerCase().contains(q)) o,
    ];
    final small = DashType.small.copyWith(color: c.textSecondary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.md,
            vertical: Space.sm,
          ),
          decoration: BoxDecoration(
            color: c.muted.withValues(alpha: 0.4),
            border: Border(bottom: BorderSide(color: c.hairline)),
          ),
          child: Text(t('analytics.excludeScopeNote'), style: small),
        ),
        Padding(
          padding: const EdgeInsets.all(Space.sm),
          child: DashSearchInput(
            key: const ValueKey('ops-exclude-search'),
            value: _query,
            placeholder: t('common.search'),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Flexible(
          child: shown.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(Space.lg),
                  child: Text(
                    menu.isLoading ? t('common.loading') : t('common.noResults'),
                    textAlign: TextAlign.center,
                    style: DashType.body.copyWith(color: c.textSecondary),
                  ),
                )
              : ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: Space.xs),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Space.md,
                        vertical: Space.xs,
                      ),
                      child: Text(
                        t('analytics.excludedFromCount'),
                        style: DashType.smallMedium.copyWith(
                          color: c.textSecondary,
                        ),
                      ),
                    ),
                    for (final (id, label) in shown)
                      DashPressable(
                        key: ValueKey('ops-exclude-$id'),
                        onTap: () => notifier.toggle(id),
                        pressScale: false,
                        selected: excluded.contains(id),
                        semanticLabel: label,
                        excludeChildSemantics: true,
                        builder: (context, s) => Container(
                          constraints: const BoxConstraints(
                            minHeight: DashMetrics.target,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: Space.md,
                          ),
                          color: s.highlighted ? c.hover : null,
                          child: Row(
                            spacing: Space.sm,
                            children: [
                              Opacity(
                                opacity: excluded.contains(id) ? 1 : 0,
                                child: DashIcon(
                                  'check',
                                  size: IconSize.sm,
                                  color: c.textPrimary,
                                ),
                              ),
                              Expanded(
                                child: MadarClippedText(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: DashType.body.copyWith(
                                    color: c.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        if (excluded.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(Space.xs),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.hairline)),
            ),
            child: DashButton(
              key: const ValueKey('ops-exclude-clear'),
              label: t('common.clear'),
              variant: DashButtonVariant.ghost,
              size: DashButtonSize.compact,
              expand: true,
              onPressed: () => notifier.set(const []),
            ),
          ),
      ],
    );
  }
}
