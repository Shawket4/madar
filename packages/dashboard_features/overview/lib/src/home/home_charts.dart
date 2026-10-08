/// Revenue trend (area chart of the timeseries) and Payment mix (donut and
/// ledger legend) — `dashboard-page.tsx`'s two chart cards.
library;

import 'package:dashboard_api/dashboard_api.dart' show TimeseriesPoint;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'home_data.dart';
import 'home_parts.dart';
import 'home_providers.dart';

/// The period's revenue, one point per period that had orders.
class HomeRevenueTrendCard extends ConsumerWidget {
  const HomeRevenueTrendCard({required this.scope, super.key});

  final Scope scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final q = watchIf(ref, scope.orgId != null, homeTimeseriesProvider(scope));
    final points = q.value ?? const <TimeseriesPoint>[];
    final Widget body;
    if (q.firstLoad) {
      body = const HomeSkeleton(height: HomeMetrics.chart);
    } else if (q.hasError) {
      body = HomeStateBox(
        height: HomeMetrics.chart,
        child: DashErrorState(
          framed: false,
          title: t('dashboard.trendFailed'),
          retryLabel: t('common.retry'),
          onRetry: () => ref.invalidate(homeTimeseriesProvider(scope)),
        ),
      );
    } else if (points.isEmpty) {
      body = HomeStateBox(
        height: HomeMetrics.chart,
        child: DashEmptyState(
          framed: false,
          title: t('dashboard.noSalesPeriod'),
        ),
      );
    } else {
      // The timeseries' naive wall-clock periods are shown as they are (the
      // web formats them on a device in the branch's zone).
      final g = scope.granularity;
      String label(String period) =>
          fmt.copyWith(timezone: 'UTC').fmtPeriodNamed('${period}Z', g);
      body = DashLineChart(
        height: HomeMetrics.chart,
        labels: [for (final p in points) label(p.period)],
        series: [
          DashSeries(
            label: t('dashboard.revenue'),
            values: [for (final p in points) p.revenue.toDouble()],
            color: homeChartColor(context.madarColors, 0),
          ),
        ],
        formatY: (v) => fmt.fmtMoneyCompact(v),
        formatValue: (v) => fmt.fmtMoney(v),
        yReserved: Space.xxl * 2,
        legend: false,
      );
    }
    return DashChartCard(title: t('dashboard.revenueTrend'), child: body);
  }
}

/// Where the money came from: one slice per method with money, its share of
/// the total in the legend.
class HomePaymentMixCard extends ConsumerWidget {
  const HomePaymentMixCard({required this.data, super.key});

  final HomeData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    final payments = data.payments;
    final Widget body;
    if (data.kpiLoading) {
      body = const HomeSkeleton(height: HomeMetrics.chart);
    } else if (data.paymentsFailed) {
      body = HomeStateBox(
        height: HomeMetrics.chart,
        child: DashErrorState(
          framed: false,
          title: t('dashboard.paymentsFailed'),
          retryLabel: t('common.retry'),
          onRetry: () => data.branchPicked
              ? ref.invalidate(homeBranchSalesProvider(data.scope))
              : ref.invalidate(homeComparisonProvider(data.scope)),
        ),
      );
    } else if (payments.isEmpty) {
      body = HomeStateBox(
        height: HomeMetrics.chart,
        child: DashEmptyState(
          framed: false,
          title: t('dashboard.noSalesPeriod'),
        ),
      );
    } else {
      final total = payments.fold(0, (s, p) => s + p.value);
      String name(String method) =>
          t.exists('payments.$method') ? t('payments.$method') : method;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          Center(
            child: DashDonutChart(
              size: HomeMetrics.donut,
              legend: false,
              // A touched slice names itself in the middle (the web's
              // tooltip: "<method>: <money>").
              centerValue: '',
              centerLabel: '',
              formatValue: (v) => fmt.fmtMoney(v),
              slices: [
                for (final (i, p) in payments.indexed)
                  DashSlice(
                    label: name(p.method),
                    value: p.value.toDouble(),
                    color: homePaymentColor(c, p.method, i),
                  ),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, box) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.sm,
              children: [
                for (final (i, p) in payments.indexed)
                  _LegendLine(
                    color: homePaymentColor(c, p.method, i),
                    name: name(p.method),
                    money: fmt.fmtMoney(p.value),
                    share: fmt.fmtShare(p.value, total),
                    // A narrow card puts the figures under the name rather
                    // than squeezing the name to nothing.
                    stacked: box.maxWidth < _LegendLine.inlineWidth,
                  ),
              ],
            ),
          ),
        ],
      );
    }
    return DashChartCard(title: t('dashboard.payments'), child: body);
  }
}

/// One payment method in the legend: dot, name, money, share.
class _LegendLine extends StatelessWidget {
  const _LegendLine({
    required this.color,
    required this.name,
    required this.money,
    required this.share,
    required this.stacked,
  });

  /// Below this width the figures go under the name.
  static const double inlineWidth = Space.xxl * 9;

  final Color color;
  final String name;
  final String money;
  final String share;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final dot = Padding(
      padding: EdgeInsets.only(top: stacked ? Space.xs + DashMetrics.hair : 0),
      child: Container(
        width: Space.sm + DashMetrics.hair,
        height: Space.sm + DashMetrics.hair,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
    final label = MadarClippedText(
      name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: DashType.body.copyWith(color: c.textSecondary),
    );
    final figure = Text(
      money,
      maxLines: 1,
      softWrap: false,
      style: DashType.monoMedium.copyWith(
        fontSize: DashType.body.fontSize,
        color: c.textPrimary,
      ),
    );
    final pct = SizedBox(
      width: Space.xxl + Space.md,
      child: Text(
        share,
        textAlign: TextAlign.end,
        maxLines: 1,
        softWrap: false,
        style: DashType.mono.copyWith(
          fontSize: DashType.small.fontSize,
          color: c.textSecondary,
        ),
      ),
    );
    if (stacked) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Space.sm,
        children: [
          dot,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                label,
                Row(
                  children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: figure,
                      ),
                    ),
                    pct,
                  ],
                ),
              ],
            ),
          ),
        ],
      );
    }
    return Row(
      spacing: Space.sm,
      children: [
        dot,
        Expanded(child: label),
        figure,
        pct,
      ],
    );
  }
}
