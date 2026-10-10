/// Financial's Recharts plots: one bar or area series over categories,
/// 288 px tall (`h-72`), a dashed horizontal grid, the y axis on the left
/// and the plot LEFT TO RIGHT in both languages (REP-ALL-020), with the
/// web's rich tooltips (payment split, peak averages). The kit's charts
/// mirror in Arabic and print one "label value" per series, so these are
/// local (kit candidate: an LTR option and a tooltip-lines builder).
library;

import 'dart:math' as math;

import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// The web's `h-72` plot.
const double finChartHeight = 288;

/// One tooltip line: a label and its figure; [dot] a series swatch,
/// [strong] the bold figure, [gap] a break before it (the web's `border-t`).
typedef FinTipLine = ({
  String label,
  String value,
  bool strong,
  Color? dot,
  bool gap,
});

FinTipLine finTip(
  String label,
  String value, {
  bool strong = false,
  Color? dot,
  bool gap = false,
}) => (label: label, value: value, strong: strong, dot: dot, gap: gap);

TextStyle _axis(BuildContext context) => DashType.tableHeader.copyWith(
  letterSpacing: 0,
  fontWeight: FontWeight.w400,
  color: context.madarColors.textSecondary,
  fontFeatures: const [FontFeature.tabularFigures()],
);

/// One series as bars ([area] false) or a monotone area.
class FinChart extends StatelessWidget {
  const FinChart({
    required this.labels,
    required this.values,
    required this.formatY,
    required this.tooltip,
    this.area = false,
    this.color,
    this.every,
    this.yWidth = 64,
    this.maxBar = 56,
    super.key,
  });

  final List<String> labels;
  final List<double> values;

  /// The y tick text.
  final String Function(double) formatY;

  /// The tooltip lines under the hovered label.
  final List<FinTipLine> Function(int index) tooltip;
  final bool area;
  final Color? color;

  /// Show every Nth x label (`interval={N-1}`); null thins to fit, as
  /// Recharts' default does.
  final int? every;

  /// The y axis' width (`width={64}` money, `{36}` counts).
  final double yWidth;
  final double maxBar;

  @override
  Widget build(BuildContext context) {
    final dir = Directionality.of(context);
    final c = context.madarColors;
    final paint = color ?? dashSeriesColor(context, 0);
    final maxY = dashNiceCeil(values.fold<double>(0, math.max));
    return SizedBox(
      height: finChartHeight,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: LayoutBuilder(
          builder: (context, box) {
            final n = labels.length;
            final style = _axis(context);
            // Every [every]th label (the web's interval), thinned further
            // when they would collide on a narrow plot.
            var widest = 0.0;
            for (final l in labels) {
              final tp = TextPainter(
                text: TextSpan(text: l, style: style),
                textDirection: TextDirection.ltr,
                maxLines: 1,
              )..layout();
              widest = math.max(widest, tp.width);
              tp.dispose();
            }
            final fit = math.max(
              1,
              (box.maxWidth - yWidth) ~/ (widest + Space.sm),
            );
            final step = math.max(every ?? 1, (n / fit).ceil());
            final titles = FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: yWidth,
                  interval: maxY / 4,
                  getTitlesWidget: (v, meta) => SideTitleWidget(
                    meta: meta,
                    child: Text(
                      dashFigure(formatY(v)),
                      style: style,
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: Space.xl + Space.xs,
                  interval: 1,
                  getTitlesWidget: (v, meta) {
                    final i = v.round();
                    if ((v - i).abs() > 0.01 ||
                        i < 0 ||
                        i >= n ||
                        i % step != 0) {
                      return const SizedBox.shrink();
                    }
                    return SideTitleWidget(
                      meta: meta,
                      child: Text(
                        labels[i],
                        style: style,
                        maxLines: 1,
                        softWrap: false,
                      ),
                    );
                  },
                ),
              ),
            );
            final grid = FlGridData(
              drawVerticalLine: false,
              horizontalInterval: maxY / 4,
              getDrawingHorizontalLine: (_) => FlLine(
                color: c.hairline,
                strokeWidth: 1,
                dashArray: const [3, 3],
              ),
            );
            final tipTitle = DashType.smallMedium.copyWith(
              color: c.textPrimary,
            );
            List<TextSpan> tipBody(int i) => [
              for (final l in tooltip(i)) ...[
                TextSpan(text: l.gap ? '\n\n' : '\n'),
                if (l.dot != null)
                  TextSpan(
                    text: '● ',
                    style: DashType.small.copyWith(color: l.dot),
                  ),
                TextSpan(
                  text: '${l.label}  ',
                  style: DashType.small.copyWith(color: c.textSecondary),
                ),
                TextSpan(
                  text: dashFigure(l.value),
                  style: (l.strong ? DashType.monoMedium : DashType.mono)
                      .copyWith(fontSize: 12, color: c.textPrimary),
                ),
              ],
            ];
            final duration = DashMotion.of(context, DashMotion.slow);
            if (area) {
              final data = LineChartData(
                minX: 0,
                maxX: math.max(1, n - 1).toDouble(),
                minY: 0,
                maxY: maxY,
                titlesData: titles,
                gridData: grid,
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => c.card,
                    tooltipBorder: BorderSide(color: c.hairline),
                    tooltipBorderRadius: BorderRadius.circular(Radii.xs),
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    maxContentWidth: 240,
                    getTooltipItems: (spots) => [
                      for (final s in spots)
                        LineTooltipItem(
                          labels[s.x.round()],
                          tipTitle,
                          textAlign: TextAlign.start,
                          textDirection: dir,
                          children: tipBody(s.x.round()),
                        ),
                    ],
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: [
                      for (var i = 0; i < n; i++)
                        FlSpot(i.toDouble(), values[i]),
                    ],
                    isCurved: true,
                    preventCurveOverShooting: true,
                    color: paint,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          paint.withValues(alpha: 0.35),
                          paint.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ],
              );
              return DashChartSelection<int>(
                builder: (context, at, touch) => LineChart(
                  duration: duration,
                  dashLineSelected(data, at, touch),
                ),
              );
            }
            final slot = (box.maxWidth - yWidth) / math.max(1, n);
            final data = BarChartData(
              minY: 0,
              maxY: maxY,
              alignment: BarChartAlignment.spaceAround,
              titlesData: titles,
              gridData: grid,
              borderData: FlBorderData(show: false),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => c.card,
                  tooltipBorder: BorderSide(color: c.hairline),
                  tooltipBorderRadius: BorderRadius.circular(Radii.xs),
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  maxContentWidth: 240,
                  getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                    labels[group.x],
                    tipTitle,
                    textAlign: TextAlign.start,
                    textDirection: dir,
                    children: tipBody(group.x),
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < n; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: values[i],
                        width: math.min(maxBar, math.max(3, slot * 0.8)),
                        color: paint,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(Space.xs),
                        ),
                      ),
                    ],
                  ),
              ],
            );
            return DashChartSelection<(int, int)>(
              builder: (context, at, touch) => BarChart(
                duration: duration,
                dashBarSelected(data, at, touch),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A chart card's body by state (REP-ALL-020): a 288 px skeleton while
/// nothing is loaded, a frameless error with Retry and no server message
/// (the web's `ChartError`; never drawn as empty), the page's empty words,
/// or the chart.
class FinChartBody extends StatelessWidget {
  const FinChartBody({
    required this.loading,
    required this.error,
    required this.retrying,
    required this.empty,
    required this.emptyTitle,
    required this.retryLabel,
    required this.onRetry,
    required this.chart,
    this.errorTitle,
    super.key,
  });

  final bool loading;
  final bool error;
  final bool retrying;
  final bool empty;
  final String emptyTitle;
  final String retryLabel;
  final String? errorTitle;
  final VoidCallback onRetry;
  final WidgetBuilder chart;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const DashSkeleton(height: finChartHeight);
    }
    if (error) {
      return SizedBox(
        height: finChartHeight,
        child: Center(
          child: DashErrorState(
            framed: false,
            title: errorTitle,
            retrying: retrying,
            retryLabel: retryLabel,
            onRetry: onRetry,
          ),
        ),
      );
    }
    if (empty) {
      return SizedBox(
        height: finChartHeight,
        child: Center(child: DashEmptyState(framed: false, title: emptyTitle)),
      );
    }
    return chart(context);
  }
}
