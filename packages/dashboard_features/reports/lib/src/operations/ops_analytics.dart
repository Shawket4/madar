/// Operations › Items, Tellers, Waiters and Branches
/// (`features/reports/operations/volume-tabs.tsx`, REP-OPS-047…055, 063,
/// 064): laid out like the Overview (the report kit): a chart card, then the
/// detail table in a titled card. Items is a ranked table ([OpsRankTable]:
/// picture and category, units, revenue, share, menu price, average extra;
/// sortable, searchable, filtered by category, with motion) above the
/// add-ons. Revenue is chart colour 0 on every tab, and each card fails on
/// its own with the card error and Retry.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show
        AddonSalesRow,
        AssetGroupRefReadyGroupRef,
        BranchComparison,
        BranchSalesReport,
        CategorySales,
        CombinedItemSalesRow,
        ItemSales,
        MenuItemFull,
        OrgComparisonReport,
        TellerStats,
        WaiterStats;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/report_shared.dart';
import 'ops_charts.dart';
import 'ops_data.dart';
import 'ops_rank_table.dart';
import 'ops_report_kit.dart';
import 'ops_support.dart';

DashEmptyState _noData(Translator t) =>
    DashEmptyState(title: t('analytics.noData'), framed: false);

// ── Items ─────────────────────────────────────────────────────────────────

/// One line of the Items table: the combined units sold (the tab's own read,
/// `items-combined`, combos included) with what the period's sales report
/// says of the item sold on its own (revenue, units, category, what was paid
/// on top of the size's price) and the menu's picture and price. Every figure
/// is one a current read returns; none is estimated.
@immutable
class OpsItemRow {
  const OpsItemRow({
    required this.id,
    required this.rank,
    required this.name,
    required this.category,
    required this.imageUrl,
    required this.quantity,
    required this.revenue,
    required this.share,
    required this.priceMin,
    required this.priceMax,
    required this.avgExtra,
  });

  final String id;

  /// 1-based, by units sold (the read's order).
  final int rank;
  final String name;

  /// The category's shown name; null when the sales report has none.
  final String? category;
  final String? imageUrl;

  /// Units sold, combos included.
  final int quantity;

  /// Revenue of the item sold on its own (the sales report's).
  final int revenue;

  /// [revenue] over the table's revenue, 0..1.
  final double share;

  /// The menu's price today (piastres): the cheapest and dearest active
  /// size (equal for a one-size item); null when the menu does not list it.
  final int? priceMin;
  final int? priceMax;

  /// Per unit sold on its own, what was paid on top of the menu price of
  /// the size bought (add-ons, swaps, optional fields; before discounts),
  /// piastres: the sales report's `extras_total` over `quantity_sold`.
  /// Null when the report does not list the item or predates the field.
  final int? avgExtra;
}

/// `n / d` rounded half away from zero (the server's `avg_extra` rule).
int opsRoundedDiv(int n, int d) {
  final q = (2 * n.abs() + d) ~/ (2 * d);
  return n < 0 ? -q : q;
}

/// An item's menu price range today: its active sizes (`all_sizes`, which
/// keeps a one-size item's `one_size` row; else the legacy `sizes`), else
/// its base price.
(int, int) opsMenuPriceRange(MenuItemFull m) {
  final sizes = [
    for (final s in m.allSizes ?? m.sizes)
      if (s.isActive) s.priceOverride,
  ];
  if (sizes.isEmpty) return (m.basePrice, m.basePrice);
  sizes.sort();
  return (sizes.first, sizes.last);
}

/// The menu's picture of an item: a ready asset group's tile, else the legacy
/// address (`menuImageUrl`).
String? opsMenuImageUrl(MenuItemFull? m) {
  final image = m?.image;
  if (image is AssetGroupRefReadyGroupRef) {
    final v = image.value.variants;
    final url = (v.tile ?? v.thumb ?? v.full)?.url;
    if (url != null && url.isNotEmpty) return url;
  }
  final legacy = m?.imageUrl;
  return legacy == null || legacy.isEmpty ? null : legacy;
}

/// The Items table's rows, in rank order.
List<OpsItemRow> opsItemRows({
  required List<CombinedItemSalesRow> items,
  required BranchSalesReport? sales,
  required List<MenuItemFull>? menu,
  required String lang,
}) {
  // The report, by item. An item renamed mid-window is listed once per
  // name: its figures are summed (an extra only when every row has one).
  final sold = <String, _Sold>{};
  for (final cat in sales?.byCategory ?? const <CategorySales>[]) {
    final name = cat.categoryName == null
        ? null
        : translatedName(cat.categoryName!, cat.categoryNameTranslations, lang);
    for (final ItemSales it in cat.items) {
      final prev = sold[it.menuItemId];
      final extras = it.extrasTotal;
      sold[it.menuItemId] = (
        revenue: (prev?.revenue ?? 0) + it.revenue,
        units: (prev?.units ?? 0) + it.quantitySold,
        extras: prev != null && prev.extras == null
            ? null
            : (extras == null ? null : (prev?.extras ?? 0) + extras),
        category: prev?.category ?? name,
      );
    }
  }
  final byId = {for (final m in menu ?? const <MenuItemFull>[]) m.id: m};
  final total = items.fold<int>(
    0,
    (s, r) => s + (sold[r.itemId]?.revenue ?? 0),
  );
  return [
    for (final (i, r) in items.indexed)
      () {
        final s = sold[r.itemId];
        final revenue = s?.revenue ?? 0;
        final units = s?.units ?? 0;
        final extras = s?.extras;
        final m = byId[r.itemId];
        final price = m == null ? null : opsMenuPriceRange(m);
        return OpsItemRow(
          id: r.itemId,
          rank: i + 1,
          name: translatedName(r.itemName, r.itemNameTranslations, lang),
          category: s?.category,
          imageUrl: opsMenuImageUrl(m),
          quantity: r.totalQty,
          revenue: revenue,
          share: total > 0 ? revenue / total : 0,
          priceMin: price?.$1,
          priceMax: price?.$2,
          avgExtra: extras != null && units > 0
              ? opsRoundedDiv(extras, units)
              : null,
        );
      }(),
  ];
}

typedef _Sold = ({int revenue, int units, int? extras, String? category});

/// A price range in the app's money format: one price, or "min–max" with
/// the currency said once, placed where `fmtMoney` puts it
/// (`EGP 55.00–75.00` / `55.00–75.00 ج.م`, the figures one LTR run); "—"
/// with none.
String opsPriceRangeText(DashFormat f, int? min, int? max) {
  if (min == null || max == null) return '—';
  if (min == max) return f.fmtMoney(min);
  String bare(int v) =>
      f.fmtMoney(v, currency: false).replaceAll(RegExp('[\u2066\u2069]'), '');
  final range = '${bare(min)}–${bare(max)}';
  return f.isArabic
      ? '${ltr(range)} ${f.currencyLabel()}'
      : '${f.currencyLabel()} $range';
}

const String _allCategories = '__all__';

class OpsItemsView extends ConsumerStatefulWidget {
  const OpsItemsView({super.key});

  @override
  ConsumerState<OpsItemsView> createState() => _OpsItemsViewState();
}

class _OpsItemsViewState extends ConsumerState<OpsItemsView> {
  String _query = '';
  String _category = _allCategories;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final lang = ref.watch(localeProvider);
    final c = context.madarColors;
    final scope = ref.watch(currentScopeProvider);
    final items = ref.watch(opsItemsProvider(scope.opsRange));
    final addons = ref.watch(opsAddonsProvider(scope.opsRange));
    // The Overview's read (same key, so one cache): revenue and category.
    final salesKey = scope.opsSales(
      excludeItemsParam(ref.watch(excludedItemsProvider(scope.orgId))),
    );
    final sales = ref.watch(opsSalesProvider(salesKey));
    // Pictures and menu prices: the table never waits for them, nor fails
    // with them.
    final org = scope.orgId;
    final menu = org == null ? null : ref.watch(opsMenuFullProvider(org));
    final strong = DashType.monoStrong.copyWith(color: c.textPrimary);
    final figures = DashType.mono.copyWith(color: c.textPrimary);

    final all = opsItemRows(
      items: items.value ?? const [],
      sales: sales.value,
      menu: menu?.value,
      lang: lang,
    );
    final categories = {
      for (final r in all)
        if (r.category != null) r.category!,
    }.toList()..sort();
    final category = categories.contains(_category)
        ? _category
        : _allCategories;
    final q = _query.trim().toLowerCase();
    final rows = [
      for (final r in all)
        if ((category == _allCategories || r.category == category) &&
            (q.isEmpty || r.name.toLowerCase().contains(q)))
          r,
    ];
    final topShare = all.fold<double>(0, (m, r) => r.share > m ? r.share : m);
    final itemsFailed = items.failed || sales.failed;
    final itemsLoading = items.awaitingFirst || sales.awaitingFirst;
    void retryItems() {
      if (items.failed) ref.invalidate(opsItemsProvider(scope.opsRange));
      if (sales.failed) ref.invalidate(opsSalesProvider(salesKey));
    }

    final toolbar = Padding(
      padding: opsTableToolbarPadding(context),
      child: Wrap(
        spacing: Space.sm,
        runSpacing: Space.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DashSearchInput(
            key: const ValueKey('ops-items-search'),
            value: _query,
            width: DashBreakpoints.isPhone(context)
                ? double.infinity
                : DashMetrics.searchWidth,
            placeholder: t('common.search'),
            onChanged: (v) => setState(() => _query = v),
          ),
          if (categories.length > 1)
            DashSelect<String>(
              key: const ValueKey('ops-items-category'),
              expand: false,
              minWidth: 160,
              semanticLabel: t('common.category'),
              value: category,
              options: [
                DashOption(
                  value: _allCategories,
                  label: t('menu.allCategories'),
                ),
                for (final name in categories)
                  DashOption(value: name, label: name),
              ],
              onChanged: (v) => setState(() => _category = v),
            ),
        ],
      ),
    );

    final table = OpsRankTable<OpsItemRow>(
      key: const ValueKey('ops-items-table'),
      rows: rows,
      rowKey: (r) => r.id,
      loading: itemsLoading,
      empty: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.xl),
        child: _noData(t),
      ),
      initialSort: (columnId: 'quantity', descending: true),
      sortedAscendingLabel: t('analytics.sortedAscending'),
      sortedDescendingLabel: t('analytics.sortedDescending'),
      lead: OpsRankColumn<OpsItemRow>(
        id: 'item',
        label: t('insights.columns.item'),
        width: 280,
        sortValue: (r) => r.name.toLowerCase(),
        cell: (context, r) => _ItemCell(row: r),
      ),
      columns: [
        OpsRankColumn<OpsItemRow>(
          id: 'quantity',
          label: t('insights.columns.sold'),
          width: 96,
          numeric: true,
          sortValue: (r) => r.quantity,
          cell: (context, r) =>
              Text(dashFigure(fmtNum(f, r.quantity)), style: figures),
        ),
        OpsRankColumn<OpsItemRow>(
          id: 'revenue',
          label: t('dashboard.revenue'),
          width: 168,
          numeric: true,
          sortValue: (r) => r.revenue,
          cell: (context, r) => Text(
            dashFigure(f.fmtMoney(r.revenue)),
            maxLines: 1,
            softWrap: false,
            style: strong,
          ),
        ),
        OpsRankColumn<OpsItemRow>(
          id: 'share',
          label: t('analytics.share'),
          width: 176,
          numeric: true,
          sortValue: (r) => r.share,
          cell: (context, r) => Row(
            spacing: Space.sm,
            children: [
              Expanded(
                child: OpsShareBar(
                  // Against the biggest share, so a long tail still reads.
                  fraction: topShare > 0 ? r.share / topShare : 0,
                  color: opsChartColor(c, 0),
                ),
              ),
              SizedBox(
                width: Space.xxl + Space.md,
                child: Text(
                  dashFigure(f.fmtPercent(r.share)),
                  textAlign: TextAlign.end,
                  style: DashType.mono.copyWith(
                    fontSize: 12,
                    color: c.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        OpsRankColumn<OpsItemRow>(
          id: 'price',
          label: t('common.price'),
          width: 184,
          numeric: true,
          sortValue: (r) => r.priceMin,
          cell: (context, r) => Text(
            r.priceMin == null
                ? '—'
                : dashFigure(opsPriceRangeText(f, r.priceMin, r.priceMax)),
            maxLines: 1,
            softWrap: false,
            style: figures,
          ),
        ),
        OpsRankColumn<OpsItemRow>(
          id: 'avg_extra',
          label: t('analytics.avgExtra'),
          width: 136,
          numeric: true,
          sortValue: (r) => r.avgExtra,
          cell: (context, r) => Text(
            r.avgExtra == null ? '—' : dashFigure(f.fmtMoney(r.avgExtra!)),
            maxLines: 1,
            softWrap: false,
            style: figures,
          ),
        ),
      ],
    );

    return OpsReportStack(
      children: [
        OpsTableCard(
          title: t('analytics.tabs.items'),
          failed: itemsFailed,
          loading: itemsLoading,
          retrying: items.isLoading || sales.isLoading,
          onRetry: retryItems,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.md,
            children: [toolbar, table],
          ),
        ),
        OpsTableCard(
          title: t('analytics.addonSales'),
          failed: addons.failed,
          loading: addons.awaitingFirst,
          retrying: addons.isLoading,
          onRetry: () => ref.invalidate(opsAddonsProvider(scope.opsRange)),
          child: DashDataTable<AddonSalesRow>(
            key: const ValueKey('ops-addons-table'),
            framed: false,
            toolbarPadding: opsTableToolbarPadding(context),
            hideViewOptions: true,
            rows: addons.value ?? const [],
            rowKey: (r) => r.addonItemId,
            loading: addons.awaitingFirst,
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

/// A share as an inline bar in the revenue colour, growing from 0 when it
/// first shows (instant under reduced motion). Decorative: the % beside it
/// says the figure.
class OpsShareBar extends StatelessWidget {
  const OpsShareBar({required this.fraction, required this.color, super.key});

  /// 0..1 of the bar's track.
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return ExcludeSemantics(
      child: Container(
        height: DashMetrics.progress,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.muted,
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: fraction.clamp(0, 1).toDouble()),
            duration: DashMotion.of(context, DashMotion.slow),
            curve: DashMotion.ease,
            builder: (context, v, _) => FractionallySizedBox(
              widthFactor: v,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rank, picture, name and category.
class _ItemCell extends StatelessWidget {
  const _ItemCell({required this.row});

  final OpsItemRow row;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    const size = Space.xxl;
    final glyph = Center(
      child: DashIcon('image', size: IconSize.sm, color: c.textSecondary),
    );
    final url = row.imageUrl;
    return Row(
      spacing: Space.sm,
      children: [
        SizedBox(
          width: Space.lg + Space.xs,
          child: Text(
            dashFigure('${row.rank}'),
            textAlign: TextAlign.end,
            style: DashType.mono.copyWith(fontSize: 12, color: c.textSecondary),
          ),
        ),
        Container(
          width: size,
          height: size,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: c.muted,
            borderRadius: BorderRadius.circular(Radii.control),
          ),
          child: url == null
              ? glyph
              : Image.network(
                  url,
                  fit: BoxFit.cover,
                  excludeFromSemantics: true,
                  errorBuilder: (_, _, _) => glyph,
                ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              MadarClippedText(
                row.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashType.bodyMedium.copyWith(color: c.textPrimary),
              ),
              if (row.category != null)
                MadarClippedText(
                  row.category!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashType.small.copyWith(color: c.textSecondary),
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

class _OpsTellersViewState extends ConsumerState<OpsTellersView> {
  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final scope = ref.watch(currentScopeProvider);
    final q = ref.watch(opsTellersProvider(scope.opsRange));
    final rows = q.value ?? const <TellerStats>[];
    final chart = [...rows]..sort((a, b) => b.revenue.compareTo(a.revenue));
    final top = chart.take(10).toList();
    void retry() => ref.invalidate(opsTellersProvider(scope.opsRange));
    final strong = DashType.monoStrong.copyWith(color: c.textPrimary);
    return OpsReportStack(
      children: [
        DashChartCard(
          title: t('analytics.revenueByTeller'),
          child: OpsChartBody(
            loading: q.awaitingFirst,
            failed: q.failed,
            empty: top.isEmpty,
            emptyTitle: t('analytics.noData'),
            onRetry: retry,
            chart: (_) => OpsHBarChart(
              key: const ValueKey('ops-tellers-chart'),
              labels: [for (final r in top) r.tellerName],
              values: [for (final r in top) r.revenue.toDouble()],
              color: opsChartColor(c, 0),
              formatAxis: f.fmtMoneyCompact,
              tooltip: (i) =>
                  '${t('dashboard.revenue')}: ${f.fmtMoney(top[i].revenue)}',
            ),
          ),
        ),
        OpsTableCard(
          title: t('analytics.tellerDetails'),
          failed: q.failed,
          loading: q.awaitingFirst,
          retrying: q.isLoading,
          onRetry: retry,
          child: DashDataTable<TellerStats>(
            key: const ValueKey('ops-tellers-table'),
            framed: false,
            toolbarPadding: opsTableToolbarPadding(context),
            hideViewOptions: true,
            pageSize: 50,
            rows: rows,
            rowKey: (r) => r.tellerId,
            loading: q.awaitingFirst,
            empty: _noData(t),
            columns: [
              DashColumn<TellerStats>(
                id: 'name',
                label: t('orders.teller'),
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

class _OpsWaitersViewState extends ConsumerState<OpsWaitersView> {
  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final scope = ref.watch(currentScopeProvider);
    final q = ref.watch(opsWaitersProvider(scope.opsRange));
    final report = q.value;
    final rows = report?.waiters ?? const <WaiterStats>[];
    final top = ([
      ...rows,
    ]..sort((a, b) => b.revenue.compareTo(a.revenue))).take(10).toList();
    void retry() => ref.invalidate(opsWaitersProvider(scope.opsRange));
    final strong = DashType.monoStrong.copyWith(color: c.textPrimary);
    // Hidden only on the first load and on a failure (React Query's
    // `isLoading`), so a background refresh never blinks it.
    final coverage =
        !q.awaitingFirst &&
            !q.failed &&
            report != null &&
            report.totalOrders > 0
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
    return OpsReportStack(
      children: [
        DashChartCard(
          title: t('analytics.revenueByWaiter'),
          child: OpsChartBody(
            loading: q.awaitingFirst,
            failed: q.failed,
            empty: top.isEmpty,
            emptyTitle: t('analytics.noData'),
            onRetry: retry,
            chart: (_) => OpsHBarChart(
              key: const ValueKey('ops-waiters-chart'),
              labels: [for (final r in top) r.waiterName],
              values: [for (final r in top) r.revenue.toDouble()],
              color: opsChartColor(c, 0),
              formatAxis: f.fmtMoneyCompact,
              tooltip: (i) =>
                  '${t('dashboard.revenue')}: ${f.fmtMoney(top[i].revenue)}',
            ),
          ),
        ),
        OpsTableCard(
          title: t('analytics.waiterDetails'),
          failed: q.failed,
          loading: q.awaitingFirst,
          retrying: q.isLoading,
          onRetry: retry,
          footnote: coverage,
          child: DashDataTable<WaiterStats>(
            key: const ValueKey('ops-waiters-table'),
            framed: false,
            toolbarPadding: opsTableToolbarPadding(context),
            hideViewOptions: true,
            pageSize: 50,
            rows: rows,
            rowKey: (r) => r.waiterId,
            loading: q.awaitingFirst,
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

class _OpsBranchesViewState extends ConsumerState<OpsBranchesView> {
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
        : ref.watch(opsBranchesProvider(scope.opsOrgRange));
    final report = q.value;
    final rows = report?.branches ?? const <BranchComparison>[];
    final chart = [...rows]
      ..sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));
    void retry() => ref.invalidate(opsBranchesProvider(scope.opsOrgRange));
    final strong = DashType.monoStrong.copyWith(color: c.textPrimary);
    return OpsReportStack(
      children: [
        DashChartCard(
          title: t('analytics.revenueByBranch'),
          child: OpsChartBody(
            loading: q.awaitingFirst,
            failed: q.failed,
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
          failed: q.failed,
          loading: q.awaitingFirst,
          retrying: q.isLoading,
          onRetry: retry,
          child: DashDataTable<BranchComparison>(
            key: const ValueKey('ops-branches-table'),
            framed: false,
            toolbarPadding: opsTableToolbarPadding(context),
            hideViewOptions: true,
            pageSize: 50,
            rows: rows,
            rowKey: (r) => r.branchId,
            loading: q.awaitingFirst,
            empty: _noData(t),
            columns: [
              DashColumn<BranchComparison>(
                id: 'name',
                label: t('orders.branch'),
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
