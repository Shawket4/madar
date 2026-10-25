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

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
            final data = LineChartData(
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
            );
            return DashChartSelection<int>(
              builder: (context, at, touch) => LineChart(
                duration: DashMotion.of(context, DashMotion.slow),
                dashLineSelected(data, at, touch),
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
            final data = BarChartData(
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
    );
  }
}

/// One slice's reading: its figure in the column's format and its share of
/// what the pie draws (the shares add up to the circle the merchant sees).
/// A null figure is "unknown": shown as "—", drawn as nothing.
@immutable
class BasiraSliceReading {
  const BasiraSliceReading({
    required this.label,
    required this.value,
    required this.share,
  });

  final String label;
  final String value;
  final String share;
}

/// Every slice's reading, in [labels] order.
List<BasiraSliceReading> basiraSliceReadings({
  required List<String> labels,
  required List<double?> values,
  required String Function(double v) format,
  required String Function(num ratio) percent,
}) {
  double drawn(int i) {
    final v = i < values.length ? values[i] : null;
    return v == null || !v.isFinite || v <= 0 ? 0 : v;
  }

  var total = 0.0;
  for (var i = 0; i < labels.length; i++) {
    total += drawn(i);
  }
  return [
    for (final (i, l) in labels.indexed)
      BasiraSliceReading(
        label: l,
        value: i < values.length && values[i] != null
            ? format(values[i]!)
            : '—',
        share: percent(total <= 0 ? 0 : drawn(i) / total),
      ),
  ];
}

/// A pie or donut on the first measure (`pie` / `donut`) that answers when
/// pressed: a tap on a slice or on its legend entry keeps it, pulls it out,
/// fades the others and reads its label, figure and share of the total in
/// the panel under the plot. A tap on it again, on the plot's empty space
/// or anywhere outside lets it go; a mouse previews a slice on hover while
/// nothing is kept. The legend entries are buttons carrying the whole
/// reading, so a keyboard and a screen reader get the same. The plot reads
/// left to right in Arabic like every Basira chart; the panel and the
/// legend follow the language.
class BasiraPieChart extends ConsumerStatefulWidget {
  const BasiraPieChart({
    required this.labels,
    required this.values,
    required this.format,
    this.donut = false,
    this.height = 240,
    super.key,
  });

  final List<String> labels;

  /// One figure per label as plotted (pounds for money); null is unknown.
  final List<double?> values;
  final String Function(double v) format;
  final bool donut;
  final double height;

  @override
  ConsumerState<BasiraPieChart> createState() => _BasiraPieChartState();
}

class _BasiraPieChartState extends ConsumerState<BasiraPieChart> {
  int? _kept;
  int? _hovered;

  /// A kept slice wins; a hover previews only while nothing is kept.
  int? get _shown {
    final i = _kept ?? _hovered;
    return i != null && i < widget.labels.length ? i : null;
  }

  void _toggle(int? i) => setState(() {
    _hovered = null;
    _kept = i == null || i == _kept ? null : i;
  });

  @override
  void didUpdateWidget(BasiraPieChart old) {
    super.didUpdateWidget(old);
    if (!listEquals(old.labels, widget.labels)) {
      _kept = null;
      _hovered = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final readings = basiraSliceReadings(
      labels: widget.labels,
      values: widget.values,
      format: widget.format,
      percent: context.dashFormats.percent,
    );
    final drawn = [
      for (var i = 0; i < widget.labels.length; i++)
        switch (i < widget.values.length ? widget.values[i] : null) {
          final v? when v.isFinite && v > 0 => v,
          _ => 0.0,
        },
    ];
    final total = drawn.fold<double>(0, (a, b) => a + b);
    final colors = [
      for (var i = 0; i < widget.labels.length; i++)
        dashSeriesColor(context, i),
    ];
    final shown = _shown;
    // Recharts' `outerRadius="78%"` of the frame, leaving room to pull out.
    final size = widget.height * 0.8;
    final radius = size / 2 - Space.sm;
    final ring = widget.donut ? radius * 0.45 : radius;

    final plot = Directionality(
      textDirection: TextDirection.ltr,
      child: ExcludeSemantics(
        child: SizedBox(
          height: widget.height * 0.9,
          child: Center(
            child: SizedBox.square(
              dimension: size,
              child: RepaintBoundary(
                child: PieChart(
                  duration: DashMotion.of(context, DashMotion.slow),
                  PieChartData(
                    sectionsSpace: widget.labels.length > 1 ? 1.5 : 0,
                    centerSpaceRadius: widget.donut ? radius - ring : 0,
                    startDegreeOffset: -90,
                    pieTouchData: PieTouchData(
                      touchCallback: (e, r) {
                        final hit = switch (r?.touchedSection) {
                          final s?
                              when total > 0 && s.touchedSectionIndex >= 0 =>
                            s.touchedSectionIndex,
                          _ => null,
                        };
                        switch (e) {
                          case FlPointerHoverEvent():
                            if (hit != _hovered) {
                              setState(() => _hovered = hit);
                            }
                          case FlPointerExitEvent():
                            if (_hovered != null) {
                              setState(() => _hovered = null);
                            }
                          case FlTapUpEvent():
                            _toggle(hit);
                          default:
                        }
                      },
                    ),
                    sections: [
                      if (total <= 0)
                        PieChartSectionData(
                          value: 1,
                          color: c.muted,
                          radius: ring,
                          showTitle: false,
                        )
                      else
                        for (var i = 0; i < drawn.length; i++)
                          PieChartSectionData(
                            value: drawn[i],
                            color: shown == null || shown == i
                                ? colors[i]
                                : colors[i].withValues(alpha: 0.35),
                            radius: shown == i ? ring + Space.sm : ring,
                            borderSide: shown == i
                                ? BorderSide(color: c.card, width: 2)
                                : const BorderSide(
                                    width: 0,
                                    color: Color(0x00000000),
                                  ),
                            showTitle: false,
                          ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final focus = shown == null ? null : readings[shown];
    final detail = Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        key: const ValueKey('basira-pie-detail'),
        constraints: const BoxConstraints(minHeight: Space.xxl + Space.md),
        padding: const EdgeInsets.symmetric(
          horizontal: BasiraMetrics.snug + DashMetrics.hair,
          vertical: Space.sm,
        ),
        decoration: BoxDecoration(
          color: c.muted.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(Radii.xs),
          border: Border.all(color: c.hairline),
        ),
        child: focus == null
            ? Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  t('basira.slice.hint'),
                  style: DashType.small.copyWith(color: c.textSecondary),
                ),
              )
            : Row(
                spacing: Space.md - DashMetrics.hair,
                children: [
                  Container(
                    width: BasiraMetrics.snug,
                    height: BasiraMetrics.snug,
                    decoration: BoxDecoration(
                      color: colors[shown!],
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      focus.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DashType.smallMedium.copyWith(
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        dashFigure(focus.value),
                        maxLines: 1,
                        softWrap: false,
                        style: DashType.monoMedium.copyWith(
                          fontSize: DashType.small.fontSize,
                          color: c.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        t('basira.slice.share', args: {'share': focus.share}),
                        maxLines: 1,
                        softWrap: false,
                        style: DashType.small.copyWith(
                          fontSize: BasiraMetrics.caption,
                          color: c.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );

    final legend = Wrap(
      spacing: BasiraMetrics.tight,
      runSpacing: BasiraMetrics.tight,
      children: [
        for (final (i, r) in readings.indexed)
          DashPressable(
            key: ValueKey('basira-pie-legend-$i'),
            onTap: () => _toggle(i),
            selected: _kept == i,
            semanticLabel: t(
              'basira.slice.aria',
              args: {'label': r.label, 'value': r.value, 'share': r.share},
            ),
            excludeChildSemantics: true,
            pressScale: false,
            builder: (context, s) => Container(
              padding: const EdgeInsets.symmetric(
                horizontal: BasiraMetrics.snug,
                vertical: Space.xs,
              ),
              foregroundDecoration: dashFocusRing(
                context,
                s,
                BorderRadius.circular(Radii.pill),
              ),
              decoration: BoxDecoration(
                color: _kept == i
                    ? c.hover
                    : (s.highlighted ? c.hover.withValues(alpha: 0.6) : null),
                borderRadius: BorderRadius.circular(Radii.pill),
                border: Border.all(
                  color: _kept == i ? c.textSecondary : const Color(0x00000000),
                ),
              ),
              child: Opacity(
                opacity: shown == null || shown == i ? 1 : 0.6,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: BasiraMetrics.tight,
                  children: [
                    Container(
                      width: Space.sm,
                      height: Space.sm,
                      decoration: BoxDecoration(
                        color: colors[i],
                        shape: BoxShape.circle,
                      ),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 160),
                      child: Text(
                        r.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DashType.small.copyWith(
                          fontSize: BasiraMetrics.caption,
                          color: _kept == i ? c.textPrimary : c.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );

    return TapRegion(
      // Anywhere outside the chart, its panel and its legend lets go.
      onTapOutside: (_) {
        if (_kept != null || _hovered != null) {
          setState(() {
            _kept = null;
            _hovered = null;
          });
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.md - DashMetrics.hair,
        children: [plot, detail, legend],
      ),
    );
  }
}
