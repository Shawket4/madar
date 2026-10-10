/// The Loyalty liability bars (REP-LOY-015): one bar per week of the net
/// change, x labels `fmtDate(week)`, a 48 px number axis, bars at most
/// 40 px wide. The plot reads left to right in both languages
/// (REP-ALL-020) and goes below zero for a week that redeemed more than it
/// earned (the kit's bar chart starts at zero and mirrors in Arabic: a kit
/// candidate).
library;

import 'dart:math' as math;

import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// The web's `h-72` plot.
const double liabilityChartHeight = 288;

class LiabilityChart extends StatelessWidget {
  const LiabilityChart({
    required this.labels,
    required this.values,
    required this.formatAxis,
    required this.tooltip,
    super.key,
  });

  /// One per bar (`fmtDate(week)`).
  final List<String> labels;
  final List<double> values;
  final String Function(double v) formatAxis;

  /// The tooltip line for bar [i] ("12 orders").
  final String Function(int i) tooltip;

  /// Recharts' `[auto, auto]` with zero in view: whole, nice steps over
  /// the data (the figures are counts).
  static (double, double, double) bounds(List<double> values) {
    final hi = values.fold<double>(0, math.max);
    final lo = values.fold<double>(0, math.min);
    final step = math.max(1.0, dashNiceCeil(math.max(hi, -lo) / 4));
    final top = hi <= 0 ? 0.0 : (hi / step).ceil() * step;
    final bottom = lo >= 0 ? 0.0 : (lo / step).floor() * step;
    return (bottom, top == bottom ? step : top, step);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final textDir = Directionality.of(context);
    final color = dashSeriesColor(context, 0);
    final (minY, maxY, step) = bounds(values);
    final style = DashType.tableHeader.copyWith(
      letterSpacing: 0,
      fontWeight: FontWeight.w400,
      color: c.textSecondary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    const yAxis = 48.0;
    return Semantics(
      container: true,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          height: liabilityChartHeight,
          child: LayoutBuilder(
            builder: (context, box) {
              final n = math.max(1, labels.length);
              final slot = (box.maxWidth - yAxis) / n;
              final bar = math.min(40.0, slot * 0.8);
              // Recharts' default `preserveEnd`: labels that would collide
              // are skipped, keeping the last.
              final widest = labels.fold<double>(0, (w, l) {
                final tp = TextPainter(
                  text: TextSpan(text: l, style: style),
                  textDirection: textDir,
                  maxLines: 1,
                )..layout();
                final width = tp.width;
                tp.dispose();
                return math.max(w, width);
              });
              final every = math.max(1, ((widest + Space.sm) / slot).ceil());
              final data = BarChartData(
                minY: minY,
                maxY: maxY,
                alignment: BarChartAlignment.spaceAround,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: step,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: c.hairline,
                    strokeWidth: 1,
                    dashArray: const [3, 3],
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: yAxis,
                      interval: step,
                      getTitlesWidget: (v, meta) => SideTitleWidget(
                        meta: meta,
                        child: Text(
                          dashFigure(formatAxis(v)),
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
                            i >= labels.length ||
                            (labels.length - 1 - i) % every != 0) {
                          return const SizedBox.shrink();
                        }
                        return SideTitleWidget(
                          meta: meta,
                          fitInside: SideTitleFitInsideData.fromTitleMeta(
                            meta,
                            distanceFromEdge: 0,
                          ),
                          child: SizedBox(
                            width: math.min(widest + Space.sm, slot * every),
                            child: Directionality(
                              textDirection: textDir,
                              child: MadarClippedText(
                                labels[i],
                                style: style,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => c.card,
                    tooltipBorder: BorderSide(color: c.hairline),
                    tooltipBorderRadius: BorderRadius.circular(Radii.xs),
                    tooltipPadding: const EdgeInsets.symmetric(
                      horizontal: Space.md,
                      vertical: Space.sm,
                    ),
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    maxContentWidth: 240,
                    getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                      '${labels[gi]}\n',
                      DashType.smallMedium.copyWith(color: c.textPrimary),
                      textAlign: TextAlign.start,
                      textDirection: textDir,
                      children: [
                        TextSpan(
                          text: '● ',
                          style: DashType.small.copyWith(color: color),
                        ),
                        TextSpan(
                          text: tooltip(gi),
                          style: DashType.small.copyWith(
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < labels.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          fromY: 0,
                          toY: i < values.length ? values[i] : 0,
                          width: bar,
                          color: color,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(
                              (i < values.length ? values[i] : 0) < 0
                                  ? 0
                                  : Space.xs,
                            ),
                            bottom: Radius.circular(
                              (i < values.length ? values[i] : 0) < 0
                                  ? Space.xs
                                  : 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              );
              return DashChartSelection<(int, int)>(
                builder: (context, at, touch) => BarChart(
                  duration: DashMotion.of(context, DashMotion.slow),
                  dashBarSelected(data, at, touch),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
