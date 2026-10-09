/// Financial's Revenue and Channel tabs (`features/analytics/analytics-page.tsx`
/// `RevenueTab` / `ChannelTab`, REP-FIN-054…064, 073).
library;

import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/report_shared.dart';
import 'fin_charts.dart';
import 'fin_data.dart';
import 'fin_profitability.dart' show FinAsync;

/// The Revenue tab's granularities, in the control's order.
const List<String> finGranularities = [
  'peak_hours',
  'peak_days',
  'daily',
  'monthly',
];

/// `PAYMENT_COLORS[method]`, else the method's chart colour.
Color finPaymentColor(BuildContext context, String method, int i) {
  final c = context.madarColors;
  return switch (method) {
    'cash' => c.success,
    'card' => c.info,
    'digital_wallet' => Color.lerp(c.info, c.danger, 0.5)!,
    'mixed' => c.warning,
    'talabat_online' => Color.lerp(c.warning, c.danger, 0.45)!,
    'talabat_cash' => Color.lerp(c.warning, c.danger, 0.2)!,
    _ => dashSeriesColor(context, i),
  };
}

/// One peak bucket (an hour or a weekday), as both tooltips read it.
typedef FinPeak = ({
  String label,
  int avgRevenue,
  double avgOrders,
  double revenuePct,
  double ordersPct,
  int revenue,
  int orders,
  int lineItems,
  int addons,
  int discount,
});

/// The web's lg (1024) breakpoint for the lower pair.
const double _lg = 1024;

class FinRevenueTab extends ConsumerWidget {
  const FinRevenueTab({required this.gran, required this.onGran, super.key});

  /// Page state: survives switching tabs (REP-FIN-054).
  final String gran;
  final ValueChanged<String> onGran;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final scope = ref.watch(currentScopeProvider);
    final isPeak = gran.startsWith('peak');
    final ts = isPeak
        ? null
        : ref.watch(finSeriesProvider(scope.finSeries(gran)));
    final ph = gran == 'peak_hours'
        ? ref.watch(finPeakHoursProvider(scope.finSales))
        : null;
    final pd = gran == 'peak_days'
        ? ref.watch(finPeakDaysProvider(scope.finSales))
        : null;
    final AsyncValue<Object> q = ts ?? ph ?? pd!;
    void retry() {
      if (ts != null) ref.invalidate(finSeriesProvider(scope.finSeries(gran)));
      if (ph != null) ref.invalidate(finPeakHoursProvider(scope.finSales));
      if (pd != null) ref.invalidate(finPeakDaysProvider(scope.finSales));
    }

    final points = ts?.value ?? const <TimeseriesPoint>[];
    final peaks = <FinPeak>[
      for (final p in ph?.value ?? const <PeakHourPoint>[])
        (
          label: f.fmtHour(p.hour),
          avgRevenue: p.avgRevenuePerDay,
          avgOrders: p.avgOrdersPerDay,
          revenuePct: p.revenuePct,
          ordersPct: p.ordersPct,
          revenue: p.revenue,
          orders: p.orders,
          lineItems: p.lineItems,
          addons: p.addons,
          discount: p.discount,
        ),
      for (final p in pd?.value ?? const <PeakDayPoint>[])
        (
          label: t(_weekdays[p.dayOfWeek % 7]),
          avgRevenue: p.avgRevenuePerDay,
          avgOrders: p.avgOrdersPerDay,
          revenuePct: p.revenuePct,
          ordersPct: p.ordersPct,
          revenue: p.revenue,
          orders: p.orders,
          lineItems: p.lineItems,
          addons: p.addons,
          discount: p.discount,
        ),
    ];
    final labels = isPeak
        ? [for (final p in peaks) p.label]
        : [for (final p in points) f.fmtPeriodNamed(p.period, gran)];
    final every = gran == 'peak_hours' ? 3 : (gran == 'peak_days' ? 1 : null);
    String money(double v) => f.fmtMoneyCompact(v);

    List<FinTipLine> peakTip(int i, {required bool revenue}) {
      final p = peaks[i];
      return [
        finTip(
          t('analytics.avgPerDay'),
          revenue
              ? f.fmtMoney(p.avgRevenue)
              : f.fmtNumber(
                  p.avgOrders,
                  const NumberOptions(maximumFractionDigits: 1),
                ),
          strong: true,
        ),
        finTip(
          t('analytics.shareOfTotal'),
          f.fmtPercent((revenue ? p.revenuePct : p.ordersPct) / 100),
        ),
        finTip(
          t('analytics.periodTotal'),
          revenue ? f.fmtMoney(p.revenue) : f.fmtNumber(p.orders),
          gap: true,
        ),
        finTip(t('dashboard.orders'), f.fmtNumber(p.orders), gap: true),
        finTip(t('analytics.itemsSold'), f.fmtNumber(p.lineItems)),
        finTip(t('analytics.addonsSold'), f.fmtNumber(p.addons)),
      ];
    }

    List<FinTipLine> revenueTip(int i) {
      final p = points[i];
      final raw = p.revenueByMethod;
      final methods = <(String, int)>[
        if (raw is Map)
          for (final e in raw.entries)
            if (e.value is num && (e.value as num) > 0)
              ('${e.key}', (e.value as num).toInt()),
      ]..sort((a, b) => b.$2.compareTo(a.$2));
      return [
        finTip(t('dashboard.revenue'), f.fmtMoney(p.revenue), strong: true),
        for (final (k, (m, v)) in methods.indexed)
          finTip(
            paymentMethodLabel(t, m),
            f.fmtMoney(v),
            dot: finPaymentColor(context, m, k),
            gap: k == 0,
          ),
        finTip(t('dashboard.orders'), f.fmtNumber(p.orders), gap: true),
        finTip(t('analytics.itemsSold'), f.fmtNumber(p.lineItems)),
        finTip(t('analytics.addonsSold'), f.fmtNumber(p.addons)),
      ];
    }

    String title(String hour, String day, String time) =>
        t(gran == 'peak_hours' ? hour : (gran == 'peak_days' ? day : time));

    Widget card(String titleText, WidgetBuilder chart, Key key) =>
        DashChartCard(
          key: key,
          title: titleText,
          child: FinChartBody(
            loading: q.firstLoad,
            error: q.hasError ? errorMessage(q.error, t) : null,
            retrying: q.isLoading,
            empty: labels.isEmpty,
            emptyTitle: t('analytics.noData'),
            retryLabel: t('common.retry'),
            onRetry: retry,
            chart: chart,
          ),
        );

    final revenueCard = card(
      title(
        'analytics.revenueByHour',
        'analytics.revenueByWeekday',
        'analytics.revenueOverTime',
      ),
      (context) => FinChart(
        key: const ValueKey('fin-revenue-chart'),
        labels: labels,
        values: isPeak
            ? [for (final p in peaks) p.avgRevenue.toDouble()]
            : [for (final p in points) p.revenue.toDouble()],
        area: gran == 'daily',
        every: every,
        formatY: money,
        tooltip: isPeak ? (i) => peakTip(i, revenue: true) : revenueTip,
      ),
      const ValueKey('fin-revenue-card'),
    );
    final ordersCard = card(
      title(
        'analytics.ordersByHour',
        'analytics.ordersByWeekday',
        'analytics.ordersOverTime',
      ),
      (context) => FinChart(
        key: const ValueKey('fin-orders-chart'),
        labels: labels,
        values: isPeak
            ? [for (final p in peaks) p.avgOrders]
            : [for (final p in points) p.orders.toDouble()],
        color: dashSeriesColor(context, 1),
        every: every,
        yWidth: 36,
        formatY: (v) => f.fmtNumber(
          v,
          NumberOptions(maximumFractionDigits: isPeak ? 1 : 0),
        ),
        tooltip: isPeak
            ? (i) => peakTip(i, revenue: false)
            : (i) => [
                finTip(t('dashboard.orders'), f.fmtNumber(points[i].orders)),
              ],
      ),
      const ValueKey('fin-orders-card'),
    );
    final discountsCard = card(
      title(
        'analytics.discountsByHour',
        'analytics.discountsByWeekday',
        'analytics.discountsOverTime',
      ),
      (context) => FinChart(
        key: const ValueKey('fin-discounts-chart'),
        labels: labels,
        values: isPeak
            ? [for (final p in peaks) p.discount.toDouble()]
            : [for (final p in points) p.discount.toDouble()],
        color: dashSeriesColor(context, 3),
        area: !isPeak,
        every: every,
        formatY: money,
        tooltip: (i) => [
          finTip(
            t('nav.discounts'),
            f.fmtMoney(isPeak ? peaks[i].discount : points[i].discount),
          ),
        ],
      ),
      const ValueKey('fin-discounts-card'),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DashSegmentedControl<String>(
              key: const ValueKey('fin-granularity'),
              value: gran,
              onChanged: onGran,
              options: [
                for (final g in finGranularities)
                  DashOption(value: g, label: t('analytics.granularity.$g')),
              ],
            ),
          ),
        ),
        revenueCard,
        LayoutBuilder(
          builder: (context, box) => box.maxWidth >= _lg - Space.xxl * 4
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Space.lg,
                  children: [
                    Expanded(child: ordersCard),
                    Expanded(child: discountsCard),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: Space.lg,
                  children: [ordersCard, discountsCard],
                ),
        ),
      ],
    );
  }
}

/// `WEEKDAYS[day_of_week]` (0 = Sunday).
const List<String> _weekdays = [
  'staff.sun',
  'staff.mon',
  'staff.tue',
  'staff.wed',
  'staff.thu',
  'staff.fri',
  'staff.sat',
];

class FinChannelTab extends ConsumerWidget {
  const FinChannelTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final key = ref.watch(currentScopeProvider).finSales;
    final q = ref.watch(finChannelsProvider(key));
    final rows = q.value ?? const <ChannelBreakdownRow>[];
    void retry() => ref.invalidate(finChannelsProvider(key));
    final error = q.hasError ? errorMessage(q.error, t) : null;
    final empty = DashEmptyState(framed: false, title: t('analytics.noData'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        DashChartCard(
          key: const ValueKey('fin-channel-chart-card'),
          title: t('analytics.revenueByChannel'),
          child: FinChartBody(
            loading: q.firstLoad,
            error: error,
            retrying: q.isLoading,
            empty: rows.isEmpty,
            emptyTitle: t('analytics.noData'),
            retryLabel: t('common.retry'),
            onRetry: retry,
            chart: (context) => FinChart(
              key: const ValueKey('fin-channel-chart'),
              labels: [for (final r in rows) channelLabel(t, r.channel)],
              values: [for (final r in rows) r.revenue.toDouble()],
              every: 1,
              maxBar: 72,
              formatY: (v) => f.fmtMoneyCompact(v),
              tooltip: (i) => [
                finTip(t('dashboard.revenue'), f.fmtMoney(rows[i].revenue)),
              ],
            ),
          ),
        ),
        DashChartCard(
          key: const ValueKey('fin-channel-table-card'),
          title: t('analytics.channelDetails'),
          child: DashDataTable<ChannelBreakdownRow>(
            key: const ValueKey('fin-channel-table'),
            framed: false,
            hideViewOptions: true,
            pageSize: 50,
            rows: rows,
            rowKey: (r) => r.channel,
            loading: q.firstLoad,
            errorMessage: error,
            onRetry: retry,
            empty: empty,
            columns: [
              DashColumn(
                id: 'channel',
                label: t('orders.channel'),
                phone: DashPhoneRole.title,
                text: (r) => channelLabel(t, r.channel),
                cell: (context, r) => Text(
                  channelLabel(t, r.channel),
                  style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                ),
              ),
              DashColumn(
                id: 'orders',
                label: t('dashboard.orders'),
                numeric: true,
                text: (r) => f.fmtNumber(r.orders),
              ),
              DashColumn(
                id: 'revenue',
                label: t('dashboard.revenue'),
                numeric: true,
                text: (r) => f.fmtMoney(r.revenue),
                cell: (context, r) => Text(
                  dashFigure(f.fmtMoney(r.revenue)),
                  style: DashType.monoStrong.copyWith(color: c.textPrimary),
                ),
              ),
              DashColumn(
                id: 'aov',
                label: t('analytics.aov'),
                numeric: true,
                text: (r) => f.fmtMoney(r.avgOrderValue),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
