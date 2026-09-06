import 'package:design_system/design_system.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge_dashboard/rust_bridge_dashboard.dart';

import '../../app/providers.dart';
import '../../format.dart';
import '../../theme/palette.dart';
import '../../widgets/cards.dart';
import '../../widgets/motion.dart';
import '../../widgets/skeletons.dart';

/// Home KPI summary for the active scope (branch or all-branches) + period.
final dashboardSummaryProvider =
    FutureProvider.autoDispose<DashboardSummaryView>((ref) async {
      ref.watch(scopeProvider);
      ref.watch(periodProvider);
      final (from, to) = ref.read(periodProvider.notifier).range();
      return ref.read(coreProvider).bridge.dashboardSummary(from: from, to: to);
    });

/// Revenue trend for the active scope + period.
final dashboardTimeseriesProvider =
    FutureProvider.autoDispose<List<DashboardTimePointView>>((ref) async {
      ref.watch(scopeProvider);
      ref.watch(periodProvider);
      final n = ref.read(periodProvider.notifier);
      final (from, to) = n.range();
      return ref
          .read(coreProvider)
          .bridge
          .dashboardTimeseries(
            from: from,
            to: to,
            granularity: n.granularity(),
          );
    });

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final singleBranch = ref.watch(scopeProvider)?.branchId != null;
    final async = ref.watch(dashboardSummaryProvider);
    return async.when(
      loading: () => const DashboardSkeleton(),
      error: (e, _) {
        final msg = e is MadarError
            ? ref.read(coreProvider).bridge.humanMessage(e)
            : '$e';
        return ErrorState(
          message: msg,
          retryLabel: t('common.retry'),
          onRetry: () => ref.invalidate(dashboardSummaryProvider),
        );
      },
      data: (s) => _Body(summary: s, singleBranch: singleBranch),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.summary, required this.singleBranch});

  final DashboardSummaryView summary;
  final bool singleBranch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Space.xl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final wide = w >= 760;

              final sideCard = singleBranch
                  ? _RankedBarList(
                      title: 'dashboard.categories',
                      items: [
                        for (final cat in summary.byCategory.take(6))
                          (
                            name: cat.categoryName.isEmpty
                                ? '—'
                                : cat.categoryName,
                            revenue: cat.revenueMinor.toInt(),
                          ),
                      ],
                      currency: summary.currencyCode,
                    )
                  : _RankedBarList(
                      title: 'dashboard.branches',
                      items: [
                        for (final b in summary.branchRanking.take(8))
                          (name: b.branchName, revenue: b.revenueMinor.toInt()),
                      ],
                      currency: summary.currencyCode,
                    );

              // The KPI grid staggers its own cards; the rest cascade in after.
              final sections = <Widget>[
                _TrendCard(currency: summary.currencyCode),
                _split(wide, _PaymentMixCard(summary: summary), sideCard),
                if (singleBranch && summary.topItems.isNotEmpty)
                  _TopItemsCard(summary: summary, locale: locale),
              ];

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _KpiGrid(
                    summary: summary,
                    singleBranch: singleBranch,
                    width: w,
                  ),
                  const SizedBox(height: Space.lg),
                  for (final (i, section) in sections.indexed) ...[
                    Reveal(
                      delay: Duration(milliseconds: 320 + i * 90),
                      child: section,
                    ),
                    if (i != sections.length - 1)
                      const SizedBox(height: Space.lg),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _split(bool wide, Widget a, Widget b) {
    if (!wide) {
      return Column(
        children: [
          a,
          const SizedBox(height: Space.lg),
          b,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: a),
        const SizedBox(width: Space.lg),
        Expanded(child: b),
      ],
    );
  }
}

class _KpiGrid extends ConsumerWidget {
  const _KpiGrid({
    required this.summary,
    required this.singleBranch,
    required this.width,
  });

  final DashboardSummaryView summary;
  final bool singleBranch;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final currency = summary.currencyCode;
    final orders = summary.totalOrders.toInt();
    final revenue = summary.totalRevenueMinor.toInt();
    final avg = orders > 0 ? revenue ~/ orders : 0;
    final countStyle = MadarType.moneyLg.copyWith(color: c.textPrimary);

    final specs =
        <({String label, String icon, Widget Function(Duration) value})>[
          (
            label: t('dashboard.revenue'),
            icon: 'banknote',
            value: (d) => AnimatedMoney(revenue, currency: currency, delay: d),
          ),
          (
            label: t('dashboard.orders'),
            icon: 'receipt',
            value: (d) =>
                AnimatedCountText(orders, style: countStyle, delay: d),
          ),
          (
            label: t('dashboard.avgOrder'),
            icon: 'plus.forwardslash.minus',
            value: (d) => AnimatedMoney(avg, currency: currency, delay: d),
          ),
          if (singleBranch) ...[
            (
              label: t('dashboard.subtotal'),
              icon: 'creditcard',
              value: (d) => AnimatedMoney(
                summary.subtotalMinor.toInt(),
                currency: currency,
                delay: d,
              ),
            ),
            (
              label: t('dashboard.discounts'),
              icon: 'tag',
              value: (d) => AnimatedMoney(
                summary.totalDiscountMinor.toInt(),
                currency: currency,
                delay: d,
              ),
            ),
            (
              label: t('dashboard.tax'),
              icon: 'plus.forwardslash.minus',
              value: (d) => AnimatedMoney(
                summary.totalTaxMinor.toInt(),
                currency: currency,
                delay: d,
              ),
            ),
          ],
          (
            label: t('dashboard.voided'),
            icon: 'xmark.circle',
            value: (d) => AnimatedCountText(
              summary.voidedOrders.toInt(),
              style: countStyle,
              delay: d,
            ),
          ),
        ];

    final cols = width >= 1000
        ? 4
        : width >= 720
        ? 3
        : width >= 460
        ? 2
        : 1;
    const gap = Space.md;
    final cardW = (width - (cols - 1) * gap) / cols;

    return Wrap(
      spacing: gap,
      runSpacing: gap,
      children: [
        for (final (i, s) in specs.indexed)
          SizedBox(
            width: cardW,
            child: Reveal(
              delay: Duration(milliseconds: i * 55),
              child: StatCard(
                label: s.label,
                icon: s.icon,
                value: s.value(Duration(milliseconds: i * 55)),
              ),
            ),
          ),
      ],
    );
  }
}

class _TrendCard extends ConsumerWidget {
  const _TrendCard({required this.currency});

  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final locale = ref.watch(localeProvider);
    final period = ref.watch(periodProvider);
    final hourly =
        period.preset == Period.today || period.preset == Period.yesterday;
    final async = ref.watch(dashboardTimeseriesProvider);
    return ChartCard(
      title: t('dashboard.revenueTrend'),
      child: SizedBox(
        height: 240,
        child: async.when(
          loading: () => const SizedBox(
            width: double.infinity,
            child: SkeletonBlock(height: 200, corner: 12),
          ),
          error: (_, _) => _noData(context, t),
          data: (points) => points.isEmpty
              ? _noData(context, t)
              : _TrendLine(
                  points: points,
                  currency: currency,
                  locale: locale,
                  hourly: hourly,
                ),
        ),
      ),
    );
  }

  Widget _noData(BuildContext context, String Function(String) t) => Center(
    child: Text(
      t('dashboard.noData'),
      style: MadarType.bodySm.copyWith(color: context.madarColors.textMuted),
    ),
  );
}

/// Revenue line with a draw-in animation (starts flat at 0, eases up to the
/// real values on mount) + touch tooltips.
class _TrendLine extends StatefulWidget {
  const _TrendLine({
    required this.points,
    required this.currency,
    required this.locale,
    required this.hourly,
  });

  final List<DashboardTimePointView> points;
  final String currency;
  final String locale;
  final bool hourly;

  @override
  State<_TrendLine> createState() => _TrendLineState();
}

class _TrendLineState extends State<_TrendLine> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  double _bottomInterval(int n) => n <= 6 ? 1 : (n / 5).floorToDouble();

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final points = widget.points;
    final maxRev = points.fold<double>(0, (a, p) {
      final v = p.revenueMinor.toInt() / 100;
      return v > a ? v : a;
    });
    final maxY = maxRev <= 0 ? 1.0 : maxRev * 1.15;
    final spots = <FlSpot>[
      for (final (i, p) in points.indexed)
        FlSpot(i.toDouble(), _ready ? p.revenueMinor.toInt() / 100 : 0),
    ];
    return RepaintBoundary(
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY,
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: maxY / 3,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: c.border, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 46,
                interval: maxY / 3,
                getTitlesWidget: (value, meta) => Padding(
                  padding: const EdgeInsetsDirectional.only(end: Space.xs),
                  child: Text(
                    fmtAxisMoney(value, locale: widget.locale),
                    style: MadarType.labelSm.copyWith(color: c.textMuted),
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: _bottomInterval(points.length),
                getTitlesWidget: (value, meta) {
                  final i = value.round();
                  if (i < 0 || i >= points.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: Space.xs),
                    child: Text(
                      fmtAxisDate(
                        points[i].period,
                        hourly: widget.hourly,
                        locale: widget.locale,
                      ),
                      style: MadarType.labelSm.copyWith(color: c.textMuted),
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => c.textPrimary,
              getTooltipItems: (touched) => [
                for (final s in touched)
                  LineTooltipItem(
                    fmtMoney(
                      (s.y * 100).round(),
                      currency: widget.currency,
                      locale: widget.locale,
                    ),
                    MadarType.label.copyWith(color: c.surface),
                  ),
              ],
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: c.accent,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    c.accent.withValues(alpha: 0.28),
                    c.accent.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
      ),
    );
  }
}

class _PaymentMixCard extends ConsumerStatefulWidget {
  const _PaymentMixCard({required this.summary});

  final DashboardSummaryView summary;

  @override
  ConsumerState<_PaymentMixCard> createState() => _PaymentMixCardState();
}

class _PaymentMixCardState extends ConsumerState<_PaymentMixCard> {
  int _touched = -1;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final t = ref.watch(tProvider);
    final locale = ref.watch(localeProvider);
    final mix = widget.summary.paymentMix;
    final total = mix.fold<int>(0, (a, s) => a + s.revenueMinor.toInt());

    return ChartCard(
      title: t('dashboard.paymentMix'),
      child: mix.isEmpty
          ? SizedBox(
              height: 100,
              child: Center(
                child: Text(
                  t('dashboard.noData'),
                  style: MadarType.bodySm.copyWith(color: c.textMuted),
                ),
              ),
            )
          : Row(
              children: [
                RepaintBoundary(
                  child: SizedBox(
                    width: 132,
                    height: 132,
                    child: PieChart(
                      PieChartData(
                        centerSpaceRadius: 36,
                        sectionsSpace: 2,
                        pieTouchData: PieTouchData(
                          touchCallback: (event, resp) {
                            setState(() {
                              if (!event.isInterestedForInteractions ||
                                  resp == null ||
                                  resp.touchedSection == null) {
                                _touched = -1;
                                return;
                              }
                              _touched =
                                  resp.touchedSection!.touchedSectionIndex;
                            });
                          },
                        ),
                        sections: [
                          for (final (i, s) in mix.indexed)
                            PieChartSectionData(
                              value: s.revenueMinor.toInt().toDouble(),
                              color: paymentColor(s.method),
                              radius: _touched == i ? 27 : 20,
                              showTitle: false,
                            ),
                        ],
                      ),
                      duration: const Duration(milliseconds: 250),
                    ),
                  ),
                ),
                const SizedBox(width: Space.lg),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final (i, s) in mix.indexed)
                        _LegendRow(
                          color: paymentColor(s.method),
                          label: paymentLabel(s.method),
                          value: fmtMoney(
                            s.revenueMinor.toInt(),
                            currency: widget.summary.currencyCode,
                            locale: locale,
                          ),
                          pct: total > 0 ? s.revenueMinor.toInt() / total : 0,
                          highlight: _touched == i,
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.color,
    required this.label,
    required this.value,
    required this.pct,
    this.highlight = false,
  });

  final Color color;
  final String label;
  final String value;
  final double pct;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(
        vertical: Space.xs,
        horizontal: Space.xs,
      ),
      decoration: BoxDecoration(
        color: highlight ? c.surfaceAlt : Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.xs),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              label,
              style: MadarType.bodySm.copyWith(
                color: c.textSecondary,
                fontWeight: highlight ? FontWeight.w700 : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${(pct * 100).round()}%',
            style: MadarType.labelSm.copyWith(color: c.textMuted),
          ),
          const SizedBox(width: Space.sm),
          Text(value, style: MadarType.money.copyWith(color: c.textPrimary)),
        ],
      ),
    );
  }
}

/// A titled card of proportional revenue bars — categories or the all-branches
/// ranking.
class _RankedBarList extends ConsumerWidget {
  const _RankedBarList({
    required this.title,
    required this.items,
    required this.currency,
  });

  final String title;
  final List<({String name, int revenue})> items;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.madarColors;
    final t = ref.watch(tProvider);
    final locale = ref.watch(localeProvider);
    final maxRev = items.fold<int>(1, (a, b) => b.revenue > a ? b.revenue : a);

    return ChartCard(
      title: t(title),
      child: items.isEmpty
          ? SizedBox(
              height: 100,
              child: Center(
                child: Text(
                  t('dashboard.noData'),
                  style: MadarType.bodySm.copyWith(color: c.textMuted),
                ),
              ),
            )
          : Column(
              children: [
                for (final (i, it) in items.indexed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Space.xs),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                it.name,
                                style: MadarType.bodySm.copyWith(
                                  color: c.textSecondary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              fmtMoney(
                                it.revenue,
                                currency: currency,
                                locale: locale,
                              ),
                              style: MadarType.money.copyWith(
                                color: c.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: Space.xs),
                        _Bar(
                          fraction: it.revenue / maxRev,
                          color: kSeriesColors[i % kSeriesColors.length],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.pill),
      child: Stack(
        children: [
          Container(height: 8, color: c.surfaceAlt),
          FractionallySizedBox(
            widthFactor: fraction.clamp(0.02, 1.0),
            child: Container(height: 8, color: color),
          ),
        ],
      ),
    );
  }
}

class _TopItemsCard extends ConsumerWidget {
  const _TopItemsCard({required this.summary, required this.locale});

  final DashboardSummaryView summary;
  final String locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.madarColors;
    final t = ref.watch(tProvider);
    final items = summary.topItems;

    return ChartCard(
      title: t('dashboard.topItems'),
      child: Column(
        children: [
          for (final (i, it) in items.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.sm),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.accentBg,
                      borderRadius: BorderRadius.circular(Radii.xs),
                    ),
                    child: Text(
                      fmtInt(i + 1, locale: locale),
                      style: MadarType.labelSm.copyWith(color: c.accent),
                    ),
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Text(
                      it.itemName,
                      style: MadarType.body.copyWith(color: c.textPrimary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${t('dashboard.qtySold')} ${fmtInt(it.quantitySold.toInt(), locale: locale)}',
                    style: MadarType.bodySm.copyWith(color: c.textMuted),
                  ),
                  const SizedBox(width: Space.lg),
                  Text(
                    fmtMoney(
                      it.revenueMinor.toInt(),
                      currency: summary.currencyCode,
                      locale: locale,
                    ),
                    style: MadarType.money.copyWith(color: c.accent),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
