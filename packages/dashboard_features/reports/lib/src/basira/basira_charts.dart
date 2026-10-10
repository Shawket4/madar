/// Basira's charts, as `result-block.tsx` draws them with Recharts
/// (REP-BAS-023): a 240 tall plot that reads left to right in both
/// languages, a value axis of plain numbers 52 wide (money in pounds, no
/// currency, no compaction), no legend on the area and bar charts, and a
/// tooltip naming each measure by its column label, formatted by its kind.
///
/// The kit's charts mirror in Arabic, compact their axes and cannot leave a
/// gap in a line, hence these (kit candidates).
library;

import 'dart:math' as math;

import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// Geometry from the web's classes.
abstract final class BasiraMetrics {
  /// The pinned rail (`w-[276px]`).
  static const double rail = 276;

  /// The slide-over's cap (`max-w-[340px]`), at most 86% of the window.
  static const double sheet = 340;

  /// The transcript's and composer's measure (`max-w-3xl`).
  static const double measure = 768;

  /// The composer's tallest (`max-h-40`).
  static const double composer = 160;

  /// The rename dialog (`sm:max-w-sm`).
  static const double renameDialog = 384;

  /// The web's `gap-1.5` / `py-1.5` (6).
  static const double tight = Space.xs + DashMetrics.hair;

  /// The web's `p-2.5` / `px-2.5` / `gap-2.5` (10).
  static const double snug = Space.sm + DashMetrics.hair;

  /// The web's `p-3.5` / `px-3.5` (14).
  static const double roomy = Space.md + DashMetrics.hair;

  /// The web's `text-[11px]`: meta lines, chips, the SQL, axis ticks.
  static final double caption = MadarType.labelSm.fontSize!;

  /// The web's `text-[10px]`: the heatmap's labels (no design_system step).
  static const double micro = 10;
}

/// One measure to plot: its column label, one value per category (null is
/// a gap, never a zero) and its tooltip format.
@immutable
class BasiraSeries {
  const BasiraSeries({
    required this.label,
    required this.values,
    required this.format,
  });

  final String label;
  final List<double?> values;
  final String Function(double v) format;
}

/// The web's `YAxis width={52}`.
const double basiraValueAxis = 52;

/// The row chart's `YAxis width={120}`.
const double basiraLabelAxis = 120;

/// An axis tick as Recharts prints a number: plain, no grouping.
String basiraTick(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

TextStyle _axisStyle(BuildContext context) => DashType.small.copyWith(
  fontSize: BasiraMetrics.caption,
  color: context.madarColors.textSecondary,
  fontFeatures: const [FontFeature.tabularFigures()],
);

({double min, double max}) _bounds(List<BasiraSeries> series) {
  var lo = 0.0, hi = 0.0;
  for (final s in series) {
    for (final v in s.values) {
      if (v == null) continue;
      lo = math.min(lo, v);
      hi = math.max(hi, v);
    }
  }
  return (min: lo < 0 ? -dashNiceCeil(-lo) : 0, max: dashNiceCeil(hi));
}

double _textWidth(BuildContext context, String s, TextStyle style) {
  final tp = TextPainter(
    text: TextSpan(text: s, style: style),
    textDirection: Directionality.of(context),
    maxLines: 1,
  )..layout();
  final w = tp.width;
  tp.dispose();
  return w;
}

FlGridData _grid(BuildContext context, double step, {bool vertical = false}) {
  final line = FlLine(
    color: context.madarColors.hairline,
    strokeWidth: 1,
    dashArray: const [3, 3],
  );
  return FlGridData(
    drawVerticalLine: vertical,
    drawHorizontalLine: !vertical,
    horizontalInterval: step,
    verticalInterval: step,
    getDrawingHorizontalLine: (_) => line,
    getDrawingVerticalLine: (_) => line,
  );
}

AxisTitles _valueTitles(BuildContext context, double step, double size) {
  final style = _axisStyle(context);
  return AxisTitles(
    sideTitles: SideTitles(
      showTitles: true,
      reservedSize: size,
      interval: step,
      getTitlesWidget: (v, meta) => SideTitleWidget(
        meta: meta,
        child: Text(basiraTick(v), style: style, maxLines: 1, softWrap: false),
      ),
    ),
  );
}

TextStyle _tipTitle(BuildContext context) =>
    DashType.smallMedium.copyWith(color: context.madarColors.textPrimary);

List<TextSpan> _tipLine(
  BuildContext context,
  BasiraSeries s,
  Color color,
  double v,
) {
  final c = context.madarColors;
  return [
    TextSpan(
      text: '● ',
      style: DashType.small.copyWith(color: color),
    ),
    TextSpan(
      text: '${s.label}  ',
      style: DashType.small.copyWith(color: c.textSecondary),
    ),
    TextSpan(
      text: dashFigure(s.format(v)),
      style: DashType.monoMedium.copyWith(
        fontSize: DashType.small.fontSize,
        color: c.textPrimary,
      ),
    ),
  ];
}

/// An area per measure over the first dimension (`line` / `area`).
class BasiraAreaChart extends StatelessWidget {
  const BasiraAreaChart({
    required this.labels,
    required this.series,
    this.height = 240,
    super.key,
  });

  final List<String> labels;
  final List<BasiraSeries> series;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final b = _bounds(series);
    final step = (b.max - b.min) / 4;
    final style = _axisStyle(context);
    final colors = [
      for (var i = 0; i < series.length; i++) dashSeriesColor(context, i),
    ];
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        height: height,
        padding: EdgeInsets.only(right: Space.sm),
        child: LayoutBuilder(
          builder: (context, box) {
            // Recharts' `minTickGap={24}`: skip labels that would touch.
            final n = labels.length;
            final slot = (box.maxWidth - basiraValueAxis) / math.max(1, n - 1);
            final widest = labels
                .map((l) => _textWidth(context, l, style))
                .fold<double>(0, math.max);
            final every = math.max(1, ((widest + Space.xl) / slot).ceil());
            return LineChart(
              duration: DashMotion.of(context, DashMotion.slow),
              LineChartData(
                minX: 0,
                maxX: math.max(1, n - 1).toDouble(),
                minY: b.min,
                maxY: b.max,
                borderData: FlBorderData(show: false),
                gridData: _grid(context, step),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: _valueTitles(context, step, basiraValueAxis),
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
                            i % every != 0) {
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
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => c.card,
                    tooltipBorder: BorderSide(color: c.hairline),
                    tooltipBorderRadius: BorderRadius.circular(Radii.xs),
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    maxContentWidth: 240,
                    getTooltipItems: (spots) {
                      final sorted = [...spots]
                        ..sort((a, b) => a.barIndex.compareTo(b.barIndex));
                      return [
                        for (final (k, s) in sorted.indexed)
                          LineTooltipItem(
                            k == 0 ? '${labels[s.x.round()]}\n' : '',
                            _tipTitle(context),
                            textAlign: TextAlign.start,
                            children: _tipLine(
                              context,
                              series[s.barIndex],
                              colors[s.barIndex],
                              s.y,
                            ),
                          ),
                      ];
                    },
                  ),
                ),
                lineBarsData: [
                  for (final (si, s) in series.indexed)
                    LineChartBarData(
                      // A gap is a day with no data: never joined across.
                      spots: [
                        for (var i = 0; i < n && i < s.values.length; i++)
                          s.values[i] == null
                              ? FlSpot.nullSpot
                              : FlSpot(i.toDouble(), s.values[i]!),
                      ],
                      isCurved: true,
                      preventCurveOverShooting: true,
                      color: colors[si],
                      barWidth: 2,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            colors[si].withValues(alpha: 0.28),
                            colors[si].withValues(alpha: 0.02),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Bars per category, at most two measures side by side: vertical (`bar`,
/// every label shown, tilted −25° past six) or [horizontal] (`row`, the
/// labels on a 120 axis).
class BasiraBarChart extends StatelessWidget {
  const BasiraBarChart({
    required this.labels,
    required this.series,
    this.horizontal = false,
    this.height = 240,
    super.key,
  });

  final List<String> labels;
  final List<BasiraSeries> series;
  final bool horizontal;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final b = _bounds(series);
    final step = (b.max - b.min) / 4;
    final style = _axisStyle(context);
    final n = labels.length;
    final tilt = !horizontal && n > 6;
    final colors = [
      for (var i = 0; i < series.length; i++) dashSeriesColor(context, i),
    ];
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        height: height,
        padding: EdgeInsets.only(right: horizontal ? Space.xl : Space.sm),
        child: LayoutBuilder(
          builder: (context, box) {
            // The category axis runs along the width, or (turned a quarter
            // for `row`) down the height.
            final along = horizontal
                ? box.maxHeight - Space.xl
                : box.maxWidth - basiraValueAxis;
            final slot = along / math.max(1, n);
            final rod = math.min(48.0, slot * 0.8 / math.max(1, series.length));
            final categories = AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: horizontal
                    ? basiraLabelAxis
                    : (tilt ? Space.xxl * 2 - Space.sm : Space.xl + Space.sm),
                interval: 1,
                getTitlesWidget: (v, meta) {
                  final i = v.round();
                  if ((v - i).abs() > 0.01 || i < 0 || i >= n) {
                    return const SizedBox.shrink();
                  }
                  final text = Text(
                    labels[i],
                    style: style,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    textAlign: horizontal ? TextAlign.right : TextAlign.center,
                  );
                  return SideTitleWidget(
                    meta: meta,
                    angle: tilt ? -25 * math.pi / 180 : 0,
                    child: horizontal
                        ? SizedBox(
                            width: basiraLabelAxis - Space.sm,
                            child: text,
                          )
                        : (tilt ? text : SizedBox(width: slot, child: text)),
                  );
                },
              ),
            );
            return BarChart(
              duration: DashMotion.of(context, DashMotion.slow),
              BarChartData(
                rotationQuarterTurns: horizontal ? 1 : 0,
                minY: b.min,
                maxY: b.max,
                alignment: BarChartAlignment.spaceAround,
                borderData: FlBorderData(show: false),
                gridData: _grid(context, step),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  // Turned a quarter, the right axis reads along the bottom.
                  rightTitles: horizontal
                      ? _valueTitles(context, step, Space.xl)
                      : const AxisTitles(),
                  leftTitles: horizontal
                      ? const AxisTitles()
                      : _valueTitles(context, step, basiraValueAxis),
                  bottomTitles: categories,
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => c.card,
                    tooltipBorder: BorderSide(color: c.hairline),
                    tooltipBorderRadius: BorderRadius.circular(Radii.xs),
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    maxContentWidth: 240,
                    getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                      '${labels[gi]}\n',
                      _tipTitle(context),
                      textAlign: TextAlign.start,
                      children: [
                        for (final (si, s) in series.indexed) ...[
                          if (si > 0) const TextSpan(text: '\n'),
                          ..._tipLine(
                            context,
                            s,
                            colors[si],
                            gi < s.values.length ? s.values[gi] ?? 0 : 0,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < n; i++)
                    BarChartGroupData(
                      x: i,
                      barsSpace: Space.xs,
                      barRods: [
                        for (final (si, s) in series.indexed)
                          BarChartRodData(
                            toY: i < s.values.length ? s.values[i] ?? 0 : 0,
                            width: rod,
                            color: colors[si],
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(Space.xs),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A pie or donut on the first measure, with a legend (`pie` / `donut`).
class BasiraPieChart extends StatelessWidget {
  const BasiraPieChart({
    required this.labels,
    required this.values,
    required this.format,
    this.donut = false,
    this.height = 240,
    super.key,
  });

  final List<String> labels;
  final List<double> values;
  final String Function(double v) format;
  final bool donut;
  final double height;

  @override
  Widget build(BuildContext context) => DashDonutChart(
    pie: !donut,
    // Recharts' `outerRadius="80%"` of the 240 frame.
    size: height * 0.8,
    formatValue: format,
    slices: [
      for (final (i, l) in labels.indexed)
        DashSlice(label: l, value: i < values.length ? values[i] : 0),
    ],
  );
}
