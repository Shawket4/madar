import 'dart:math' as math;

import 'package:design_system/design_system.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

import 'foundation/l10n.dart';
import 'foundation/tokens.dart';

/// The categorical colour for series [i], from design_system's series tokens
/// (theme-aware).
Color dashSeriesColor(BuildContext context, int i) {
  final s = context.madarColors.series;
  return s[i % s.length];
}

/// A chart in a card (the web's `ChartCard`): a 16/600 title, a muted
/// description, actions at the end, the plot under them.
class DashChartCard extends StatelessWidget {
  const DashChartCard({
    required this.child,
    this.title,
    this.description,
    this.actions = const [],
    this.legend,
    super.key,
  });

  final Widget child;
  final String? title;
  final String? description;
  final List<Widget> actions;

  /// A [DashChartLegend] under the header.
  final Widget? legend;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final wide = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm;
    final hasHeader =
        title != null || description != null || actions.isNotEmpty;
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
          if (hasHeader)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.card),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Space.md,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      spacing: Space.xs,
                      children: [
                        if (title != null)
                          Semantics(
                            header: true,
                            child: Text(
                              title!,
                              style: DashType.sectionTitle.copyWith(
                                color: c.textPrimary,
                              ),
                            ),
                          ),
                        if (description != null)
                          Text(
                            description!,
                            style: DashType.body.copyWith(
                              color: c.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  ...actions,
                ],
              ),
            ),
          if (legend != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.card),
              child: legend,
            ),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: wide ? Space.card : Space.md,
            ),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// One entry of a [DashChartLegend].
@immutable
class DashLegendItem {
  const DashLegendItem({required this.label, required this.color, this.value});
  final String label;
  final Color color;

  /// A figure after the label (a donut's share).
  final String? value;
}

/// Coloured dots and their names, wrapping.
class DashChartLegend extends StatelessWidget {
  const DashChartLegend({
    required this.items,
    this.vertical = false,
    super.key,
  });
  final List<DashLegendItem> items;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    Widget entry(DashLegendItem i) => Row(
      mainAxisSize: vertical ? MainAxisSize.max : MainAxisSize.min,
      spacing: Space.xs + DashMetrics.hair,
      children: [
        Container(
          width: Space.sm + DashMetrics.hair,
          height: Space.sm + DashMetrics.hair,
          decoration: BoxDecoration(color: i.color, shape: BoxShape.circle),
        ),
        if (vertical)
          Expanded(
            child: Text(
              i.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DashType.small.copyWith(color: c.textSecondary),
            ),
          )
        else
          Text(i.label, style: DashType.small.copyWith(color: c.textSecondary)),
        if (i.value != null)
          Text(
            dashFigure(i.value!),
            maxLines: 1,
            softWrap: false,
            style: DashType.monoMedium.copyWith(
              fontSize: 12,
              color: c.textPrimary,
            ),
          ),
      ],
    );
    if (vertical) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.sm,
        children: [for (final i in items) entry(i)],
      );
    }
    return Wrap(
      spacing: Space.lg,
      runSpacing: Space.xs,
      children: [for (final i in items) entry(i)],
    );
  }
}

/// One series of a line, area or bar chart.
@immutable
class DashSeries {
  const DashSeries({required this.label, required this.values, this.color});
  final String label;

  /// One value per x label.
  final List<double> values;

  /// Defaults to the series token for its index.
  final Color? color;
}

TextStyle _axisStyle(BuildContext context) => DashType.tableHeader.copyWith(
  letterSpacing: 0,
  fontWeight: FontWeight.w400,
  color: context.madarColors.textSecondary,
  fontFeatures: const [FontFeature.tabularFigures()],
);

/// [s]'s one-line width in [style], at the window's text scale.
double _textWidth(BuildContext context, String s, TextStyle style) {
  final tp = TextPainter(
    text: TextSpan(text: s, style: style),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final w = tp.width;
  tp.dispose();
  return w;
}

/// Recharts' `minTickGap` on the web's charts.
const double _labelGap = Space.xl;

/// The axis labels drawn, as Recharts' default `preserveEnd` picks them:
/// from the last one back, each label whole inside `[0, extent]` (one at an
/// edge shifted in) and [_labelGap] clear of the one kept after it. So every
/// label shows when they fit, and the latest is always named. [centres] are
/// in label order, running either way.
Set<int> _thinLabels(List<double> centres, List<double> widths, double extent) {
  final kept = <int>{};
  double? lo, hi;
  for (var i = centres.length - 1; i >= 0; i--) {
    final w = widths[i];
    final room = math.max(0.0, extent - w);
    final l = (centres[i] - w / 2).clamp(0.0, room);
    final r = l + w;
    if (lo == null || r + _labelGap <= lo || l >= hi! + _labelGap) {
      kept.add(i);
      lo = l;
      hi = r;
    }
  }
  return kept;
}

/// A "nice" axis ceiling for [max]: 1, 2, 2.5 or 5 × 10ⁿ.
double dashNiceCeil(double max) {
  if (max <= 0) return 1;
  final exp = math.pow(10, (math.log(max) / math.ln10).floor()).toDouble();
  for (final m in [1.0, 2.0, 2.5, 5.0, 10.0]) {
    if (m * exp >= max) return m * exp;
  }
  return 10 * exp;
}

/// Recharts' axis ticks (recharts-scale `getNiceTickValues`, [count] ticks)
/// for data from [min] to [max], the range widened to take in 0: an even
/// step, a quarter of the range rounded up to 0.05 × 10ⁿ (0.1 × 10ⁿ for a
/// one-digit step), so 0…272 → 0…280 by 70, 0…10 → 0…12 by 3 and −30…100 →
/// −35…105 by 35. Whole steps unless [allowDecimals]; all zero → 0…4.
List<double> dashNiceTicks(
  double min,
  double max, {
  int count = 5,
  bool allowDecimals = true,
}) {
  final lo = math.min(min, 0.0), hi = math.max(max, 0.0);
  if (lo == hi) return [for (var k = 0; k < count; k++) k.toDouble()];
  // Float noise off before a ceiling (0.7 / 0.05 is 13.999…).
  double clean(double v) => double.parse(v.toStringAsPrecision(12));
  final rough = (hi - lo) / (count - 1);
  var digits = (math.log(rough) / math.ln10).floor() + 1;
  if (math.pow(10, digits) <= rough) digits++; // log10(1000) is 2.999…
  if (math.pow(10, digits - 1) > rough) digits--;
  final unit = math.pow(10, digits).toDouble();
  final scale = digits == 1 ? 0.1 : 0.05;
  for (var correction = 0; ; correction++) {
    var step = clean(
      (clean(rough / unit / scale).ceil() + correction) * scale * unit,
    );
    if (!allowDecimals) step = step.ceilToDouble();
    var below = clean(-lo / step).ceil();
    var up = clean(hi / step).ceil();
    final total = below + up + 1;
    if (total > count) continue;
    if (hi > 0) {
      up += count - total;
    } else {
      below += count - total;
    }
    return [for (var k = -below; k <= up; k++) clean(k * step)];
  }
}

/// [dashNiceTicks] over [values], a NaN (a gap) skipped.
List<double> _ticksOf(Iterable<double> values, bool allowDecimals) {
  var lo = 0.0, hi = 0.0;
  for (final v in values) {
    if (v.isNaN) continue;
    lo = math.min(lo, v);
    hi = math.max(hi, v);
  }
  return dashNiceTicks(lo, hi, allowDecimals: allowDecimals);
}

/// Shared axis + grid + tooltip styling.
class _Axes {
  _Axes(
    this.context, {
    required this.labels,
    required this.formatY,
    required this.ticks,
    required this.width,
    required this.ltr,
    this.bars = false,
    double? yReserved,
  }) : yReserved = yReserved ?? _measure(context, formatY, ticks);

  final BuildContext context;
  final List<String> labels;
  final String Function(double) formatY;

  /// From [dashNiceTicks]: the y range and its step.
  final List<double> ticks;
  final double width;
  final bool ltr;

  /// Each label centred in its own band (bars), not on a point (lines).
  final bool bars;
  final double yReserved;

  double get minY => ticks.first;
  double get maxY => ticks.last;
  double get step => ticks[1] - ticks[0];

  /// Room for the widest y tick.
  static double _measure(
    BuildContext context,
    String Function(double) formatY,
    List<double> ticks,
  ) {
    final style = _axisStyle(context);
    return ticks
            .map((t) => _textWidth(context, formatY(t), style))
            .fold<double>(0, math.max) +
        Space.md;
  }

  /// The y axis sits at the reading start: on the right in Arabic.
  bool get rtl => Directionality.of(context) == TextDirection.rtl;

  /// The x axis runs from the right: Arabic, unless [ltr].
  bool get mirror => rtl && !ltr;

  /// Chart x for data index [i], and back.
  double x(int i) => mirror ? (labels.length - 1 - i).toDouble() : i.toDouble();
  int index(double x) => mirror ? labels.length - 1 - x.round() : x.round();

  /// The x labels drawn, by the room they really take ([_thinLabels]).
  late final Set<int> shown = () {
    final n = labels.length;
    final plot = math.max(0.0, width - yReserved);
    final style = _axisStyle(context);
    return _thinLabels(
      [
        for (var i = 0; i < n; i++)
          bars ? (x(i) + 0.5) * plot / n : x(i) * plot / math.max(1, n - 1),
      ],
      [for (final l in labels) _textWidth(context, l, style)],
      plot,
    );
  }();

  FlTitlesData titles() {
    final style = _axisStyle(context);
    final y = AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: yReserved,
        interval: step,
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
    );
    const none = AxisTitles();
    return FlTitlesData(
      leftTitles: rtl ? none : y,
      rightTitles: rtl ? y : none,
      topTitles: none,
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: Space.xl + Space.xs,
          interval: 1,
          getTitlesWidget: (v, meta) {
            if ((v - v.roundToDouble()).abs() > 0.01) {
              return const SizedBox.shrink();
            }
            final i = index(v);
            if (!shown.contains(i)) return const SizedBox.shrink();
            return SideTitleWidget(
              meta: meta,
              // A label at an edge is shifted in, never cut by the card.
              fitInside: SideTitleFitInsideData.fromTitleMeta(
                meta,
                distanceFromEdge: 0,
              ),
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
  }

  FlGridData grid() => FlGridData(
    drawVerticalLine: false,
    horizontalInterval: step,
    getDrawingHorizontalLine: (_) => FlLine(
      color: context.madarColors.hairline,
      strokeWidth: 1,
      dashArray: const [3, 3],
    ),
  );

  TextStyle get tipTitle => _tipTitle(context);
  TextStyle get tipBody => _tipBody(context);
  TextStyle get tipValue => _tipValue(context);
}

TextStyle _tipTitle(BuildContext context) =>
    DashType.smallMedium.copyWith(color: context.madarColors.textPrimary);
TextStyle _tipBody(BuildContext context) =>
    DashType.small.copyWith(color: context.madarColors.textSecondary);
TextStyle _tipValue(BuildContext context) => DashType.monoMedium.copyWith(
  fontSize: 12,
  color: context.madarColors.textPrimary,
);

/// An fl_chart touch event and the item under it (null: nothing).
typedef DashChartTouch<K> = void Function(FlTouchEvent event, K? hit);

/// A chart's kept selection, as the web's Recharts keeps it. fl_chart's own
/// touch handling shows a tooltip only while a finger is down, so a quick
/// tap only flashed it. Here a tap selects what it hit and keeps it (a tap
/// on it again, on nothing or outside the chart clears it), a drag or a
/// long press scrubs it, and a mouse shows it on hover and drops it on
/// leaving. [builder] gets the kept item and the `touch` to feed the
/// chart's touch events, mapped to the item hit: [dashLineSelected] and
/// [dashBarSelected] wire a line or a bar chart.
class DashChartSelection<K extends Object> extends StatefulWidget {
  const DashChartSelection({required this.builder, super.key});

  final Widget Function(
    BuildContext context,
    K? selected,
    DashChartTouch<K> touch,
  )
  builder;

  @override
  State<DashChartSelection<K>> createState() => _DashChartSelectionState<K>();
}

class _DashChartSelectionState<K extends Object>
    extends State<DashChartSelection<K>> {
  K? _selected;

  /// Picked by a hovering mouse: leaving drops it.
  bool _hovered = false;

  void _select(K? k, {bool hover = false}) {
    _hovered = hover;
    if (k != _selected) setState(() => _selected = k);
  }

  void _touch(FlTouchEvent e, K? hit) {
    switch (e) {
      case FlPointerHoverEvent():
        _select(hit, hover: true);
      case FlPointerExitEvent():
        if (_hovered) _select(null);
      // A mouse click lands on what its hover already shows.
      case FlTapUpEvent(:final details)
          when details.kind != PointerDeviceKind.mouse:
        _select(hit == _selected ? null : hit);
      case FlPanStartEvent() ||
              FlPanUpdateEvent() ||
              FlLongPressStart() ||
              FlLongPressMoveUpdate()
          when hit != null:
        _select(hit);
      default:
    }
  }

  @override
  Widget build(BuildContext context) => TapRegion(
    onTapOutside: (_) => _select(null),
    child: widget.builder(context, _selected, _touch),
  );
}

/// [data] under a [DashChartSelection] keyed by spot index (the lines share
/// their indices, one per x): fl_chart's own touch handling off, the
/// nearest x anywhere on the plot touched (as Recharts picks it), and the
/// kept [x] shown, each line's dot and the tooltip.
LineChartData dashLineSelected(
  LineChartData data,
  int? x,
  DashChartTouch<int> touch,
) {
  final bars = [
    for (final b in data.lineBarsData)
      if (x != null && x < b.spots.length && b.spots[x].isNotNull())
        b.copyWith(showingIndicators: [x])
      else
        b,
  ];
  final spots = [
    for (final (i, b) in bars.indexed)
      if (b.showingIndicators.isNotEmpty) LineBarSpot(b, i, b.spots[x!]),
  ];
  return data.copyWith(
    lineTouchData: data.lineTouchData.copyWith(
      handleBuiltInTouches: false,
      touchSpotThreshold: double.infinity,
      touchCallback: (e, r) =>
          touch(e, r?.lineBarSpots?.firstOrNull?.spotIndex),
    ),
    lineBarsData: bars,
    showingTooltipIndicators: [
      if (spots.isNotEmpty) ShowingTooltipIndicators(spots),
    ],
  );
}

/// [data] under a [DashChartSelection] keyed by (group, rod) index:
/// fl_chart's own touch handling off, a bar touched anywhere in its column
/// (a short bar is a target too), and the kept [at]'s tooltip shown.
BarChartData dashBarSelected(
  BarChartData data,
  (int, int)? at,
  DashChartTouch<(int, int)> touch,
) => data.copyWith(
  barTouchData: data.barTouchData.copyWith(
    handleBuiltInTouches: false,
    touchExtraThreshold: const EdgeInsets.symmetric(
      horizontal: Space.xs,
      vertical: double.infinity,
    ),
    touchCallback: (e, r) => touch(e, switch (r?.spot) {
      final s? => (s.touchedBarGroupIndex, s.touchedRodDataIndex),
      null => null,
    }),
  ),
  barGroups: [
    for (final (i, g) in data.barGroups.indexed)
      if (at != null && at.$1 == i && at.$2 < g.barRods.length)
        g.copyWith(showingTooltipIndicators: [at.$2])
      else
        g,
  ],
);

/// A line or area chart over categories (days, hours) — the web's Recharts
/// `AreaChart` / `LineChart`. Theme-aware series colours, a dashed grid, y
/// ticks from [dashNiceTicks] (below zero too) formatted by [formatY], x
/// labels thinned by the room they take, a tooltip listing every series at
/// the touched x, and the y axis at the reading start (the right in Arabic).
/// Time runs left to right in both languages ([ltr]); a NaN value is a gap
/// in the line (the web's `connectNulls={false}`).
class DashLineChart extends StatelessWidget {
  const DashLineChart({
    required this.labels,
    required this.series,
    required this.formatY,
    this.formatValue,
    this.area = true,
    this.curved = true,
    this.height = 240,
    this.legend = true,
    this.yReserved,
    this.ltr = true,
    this.allowDecimals = true,
    super.key,
  });

  final List<String> labels;
  final List<DashSeries> series;

  /// Tick text for the y axis (compact).
  final String Function(double) formatY;

  /// Tooltip figures (full); defaults to [formatY].
  final String Function(double)? formatValue;

  /// A flat 12% fill under the lines (the web's `fillOpacity={0.12}`).
  final bool area;
  final bool curved;
  final double height;

  /// A legend under the plot when there is more than one series.
  final bool legend;

  /// Room for the y ticks; measured from them when null.
  final double? yReserved;

  /// On by default, as this is a time axis: the earliest point on the left
  /// in Arabic too, as Recharts draws it (the web keeps every plot left to
  /// right). Off: the x axis mirrors in Arabic.
  final bool ltr;

  /// Ticks may fall between whole numbers (Recharts' `allowDecimals`).
  final bool allowDecimals;

  @override
  Widget build(BuildContext context) {
    final colors = [
      for (var i = 0; i < series.length; i++)
        series[i].color ?? dashSeriesColor(context, i),
    ];
    final ticks = _ticksOf(series.expand((s) => s.values), allowDecimals);
    final fmt = formatValue ?? formatY;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.md,
      children: [
        SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final ax = _Axes(
                context,
                labels: labels,
                formatY: formatY,
                ticks: ticks,
                width: constraints.maxWidth,
                ltr: ltr,
                yReserved: yReserved,
              );
              final c = context.madarColors;
              final data = LineChartData(
                minX: 0,
                maxX: math.max(1, labels.length - 1).toDouble(),
                minY: ax.minY,
                maxY: ax.maxY,
                titlesData: ax.titles(),
                gridData: ax.grid(),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(
                  getTouchedSpotIndicator: (bar, spots) => [
                    for (final _ in spots)
                      TouchedSpotIndicatorData(
                        FlLine(color: c.input, strokeWidth: 1),
                        FlDotData(
                          getDotPainter: (spot, p, b, i) => FlDotCirclePainter(
                            radius: 3.5,
                            color: b.color ?? c.accent,
                            strokeWidth: 2,
                            strokeColor: c.card,
                          ),
                        ),
                      ),
                  ],
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => c.card,
                    tooltipBorder: BorderSide(color: c.hairline),
                    tooltipBorderRadius: BorderRadius.circular(Radii.xs),
                    tooltipPadding: const EdgeInsets.symmetric(
                      horizontal: Space.md,
                      vertical: Space.sm,
                    ),
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    maxContentWidth: 220,
                    getTooltipItems: (spots) {
                      final sorted = [...spots]
                        ..sort((a, b) => a.barIndex.compareTo(b.barIndex));
                      return [
                        for (var k = 0; k < spots.length; k++)
                          () {
                            final s = sorted[k];
                            final i = ax.index(s.x);
                            final head = k == 0 && i >= 0 && i < labels.length
                                ? '${labels[i]}\n'
                                : '';
                            return LineTooltipItem(
                              head,
                              ax.tipTitle,
                              textAlign: TextAlign.start,
                              textDirection: Directionality.of(context),
                              children: [
                                TextSpan(
                                  text: '● ',
                                  style: ax.tipBody.copyWith(
                                    color: colors[s.barIndex],
                                  ),
                                ),
                                TextSpan(
                                  text: '${series[s.barIndex].label}  ',
                                  style: ax.tipBody,
                                ),
                                TextSpan(
                                  text: dashFigure(fmt(s.y)),
                                  style: ax.tipValue,
                                ),
                              ],
                            );
                          }(),
                      ];
                    },
                  ),
                ),
                lineBarsData: [
                  for (var si = 0; si < series.length; si++)
                    LineChartBarData(
                      spots: [
                        for (var k = 0; k < labels.length; k++)
                          if (ax.index(k.toDouble()) case final i
                              when i < series[si].values.length)
                            series[si].values[i].isNaN
                                ? FlSpot.nullSpot
                                : FlSpot(k.toDouble(), series[si].values[i]),
                      ],
                      isCurved: curved,
                      preventCurveOverShooting: true,
                      color: colors[si],
                      barWidth: 2,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: area,
                        color: colors[si].withValues(alpha: 0.12),
                      ),
                    ),
                ],
              );
              // Its own layer: the draw-in and a hover repaint the plot
              // alone, and a count-up or an entrance beside it never
              // repaints the plot.
              return RepaintBoundary(
                child: DashChartSelection<int>(
                  builder: (context, at, touch) => LineChart(
                    duration: DashMotion.of(context, DashMotion.slow),
                    dashLineSelected(data, at, touch),
                  ),
                ),
              );
            },
          ),
        ),
        if (legend && series.length > 1)
          DashChartLegend(
            items: [
              for (var i = 0; i < series.length; i++)
                DashLegendItem(label: series[i].label, color: colors[i]),
            ],
          ),
      ],
    );
  }
}

/// Bars over categories, grouped side by side or [stacked] (the web's
/// Recharts `BarChart`), with the same axes, tooltip and labels as
/// [DashLineChart]; a bar below zero hangs from the zero line, a NaN is no
/// bar. Mirrored in Arabic unless [ltr].
class DashBarChart extends StatelessWidget {
  const DashBarChart({
    required this.labels,
    required this.series,
    required this.formatY,
    this.formatValue,
    this.stacked = false,
    this.height = 240,
    this.legend = true,
    this.yReserved,
    this.ltr = false,
    this.allowDecimals = true,
    super.key,
  });

  final List<String> labels;
  final List<DashSeries> series;
  final String Function(double) formatY;
  final String Function(double)? formatValue;
  final bool stacked;
  final double height;
  final bool legend;

  /// Room for the y ticks; measured from them when null.
  final double? yReserved;

  /// Left to right in Arabic too, as the web draws it: turn it on for a
  /// time axis (hours, days). Off (categories): the bars mirror in Arabic.
  final bool ltr;

  /// Ticks may fall between whole numbers (Recharts' `allowDecimals`).
  final bool allowDecimals;

  @override
  Widget build(BuildContext context) {
    final colors = [
      for (var i = 0; i < series.length; i++)
        series[i].color ?? dashSeriesColor(context, i),
    ];
    double valueAt(int s, int i) {
      final v = i < series[s].values.length ? series[s].values[i] : 0.0;
      return v.isNaN ? 0 : v;
    }

    final ticks = _ticksOf(
      stacked
          ? [
              for (var i = 0; i < labels.length; i++)
                [
                  for (var s = 0; s < series.length; s++) valueAt(s, i),
                ].fold<double>(0, (a, b) => a + b),
            ]
          : series.expand((s) => s.values),
      allowDecimals,
    );
    final fmt = formatValue ?? formatY;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.md,
      children: [
        SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final c = context.madarColors;
              final ax = _Axes(
                context,
                labels: labels,
                formatY: formatY,
                ticks: ticks,
                width: constraints.maxWidth,
                ltr: ltr,
                bars: true,
                yReserved: yReserved,
              );
              final mirror = ax.mirror;
              final n = labels.length;
              final groupWidth =
                  (constraints.maxWidth - ax.yReserved) / math.max(1, n);
              final rodWidth = stacked
                  ? (groupWidth * 0.55).clamp(4.0, 32.0)
                  : (groupWidth * 0.7 / math.max(1, series.length)).clamp(
                      3.0,
                      20.0,
                    );
              final order = [for (var k = 0; k < n; k++) ax.index(k * 1.0)];
              const top = Radius.circular(Space.xs);
              final data = BarChartData(
                minY: ax.minY,
                maxY: ax.maxY,
                alignment: BarChartAlignment.spaceAround,
                titlesData: ax.titles(),
                gridData: ax.grid(),
                borderData: FlBorderData(show: false),
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
                    maxContentWidth: 220,
                    getTooltipItem: (group, gi, rod, ri) {
                      final i = order[gi];
                      final rows = stacked
                          ? [for (var s = 0; s < series.length; s++) s]
                          : [mirror ? series.length - 1 - ri : ri];
                      return BarTooltipItem(
                        '${labels[i]}\n',
                        ax.tipTitle,
                        textAlign: TextAlign.start,
                        textDirection: Directionality.of(context),
                        children: [
                          for (final s in rows) ...[
                            TextSpan(
                              text: '● ',
                              style: ax.tipBody.copyWith(color: colors[s]),
                            ),
                            TextSpan(
                              text: '${series[s].label}  ',
                              style: ax.tipBody,
                            ),
                            TextSpan(
                              text: dashFigure(fmt(valueAt(s, i))),
                              style: ax.tipValue,
                            ),
                            if (s != rows.last) const TextSpan(text: '\n'),
                          ],
                        ],
                      );
                    },
                  ),
                ),
                barGroups: [
                  for (var k = 0; k < n; k++)
                    () {
                      final i = order[k];
                      if (stacked) {
                        var acc = 0.0;
                        final stack = <BarChartRodStackItem>[];
                        for (var s = 0; s < series.length; s++) {
                          final v = valueAt(s, i);
                          stack.add(
                            BarChartRodStackItem(acc, acc + v, colors[s]),
                          );
                          acc += v;
                        }
                        return BarChartGroupData(
                          x: k,
                          barRods: [
                            BarChartRodData(
                              toY: acc,
                              width: rodWidth,
                              rodStackItems: stack,
                              color: Colors.transparent,
                              borderRadius: const BorderRadius.vertical(
                                top: top,
                              ),
                            ),
                          ],
                        );
                      }
                      return BarChartGroupData(
                        x: k,
                        barsSpace: 2,
                        barRods: [
                          for (var q = 0; q < series.length; q++)
                            () {
                              final s = mirror ? series.length - 1 - q : q;
                              final v = valueAt(s, i);
                              return BarChartRodData(
                                toY: v,
                                width: rodWidth,
                                color: colors[s],
                                // The end away from zero is rounded.
                                borderRadius: v < 0
                                    ? const BorderRadius.vertical(bottom: top)
                                    : const BorderRadius.vertical(top: top),
                              );
                            }(),
                        ],
                      );
                    }(),
                ],
              );
              // Its own layer (as [DashLineChart]'s).
              return RepaintBoundary(
                child: DashChartSelection<(int, int)>(
                  builder: (context, at, touch) => BarChart(
                    duration: DashMotion.of(context, DashMotion.slow),
                    dashBarSelected(data, at, touch),
                  ),
                ),
              );
            },
          ),
        ),
        if (legend && series.length > 1)
          DashChartLegend(
            items: [
              for (var i = 0; i < series.length; i++)
                DashLegendItem(label: series[i].label, color: colors[i]),
            ],
          ),
      ],
    );
  }
}

/// Recharts' `maxBarSize={48}` on Basira's bars.
const double _maxBar = Space.xxl + Space.lg;

/// Horizontal bars, a row per label — the web's Recharts `BarChart
/// layout="vertical"` (the Tellers and Waiters leaderboards, Basira's row
/// chart): the names on a [labelWidth] axis at the start, the figures' axis
/// under the rows with [dashNiceTicks] (below zero too), a dashed line at
/// each tick, the series side by side in a row, and a tap or hover on a row
/// showing its figures. Mirrored in Arabic (names on the right, bars growing
/// left) unless [ltr], which draws it left to right as the web does.
class DashHBarChart extends StatelessWidget {
  const DashHBarChart({
    required this.labels,
    required this.series,
    required this.formatX,
    this.formatValue,
    this.labelWidth = 120,
    this.height = 240,
    this.legend = true,
    this.ltr = false,
    this.allowDecimals = true,
    super.key,
  });

  final List<String> labels;
  final List<DashSeries> series;

  /// Tick text for the figures' axis (compact).
  final String Function(double) formatX;

  /// Tooltip figures (full); defaults to [formatX].
  final String Function(double)? formatValue;

  /// The names' axis (the web's `YAxis width`: 110 on the leaderboards,
  /// 120 on Basira).
  final double labelWidth;
  final double height;

  /// A legend under the plot when there is more than one series.
  final bool legend;

  /// Left to right in Arabic too, names on the left (the web's plots).
  final bool ltr;

  /// Ticks may fall between whole numbers (Recharts' `allowDecimals`).
  final bool allowDecimals;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final reading = Directionality.of(context);
    final dir = ltr ? TextDirection.ltr : reading;
    final style = _axisStyle(context);
    final colors = [
      for (var i = 0; i < series.length; i++)
        series[i].color ?? dashSeriesColor(context, i),
    ];
    double valueAt(int s, int i) {
      final v = i < series[s].values.length ? series[s].values[i] : 0.0;
      return v.isNaN ? 0 : v;
    }

    final ticks = _ticksOf(series.expand((s) => s.values), allowDecimals);
    final span = ticks.last - ticks.first;
    double frac(double v) => (v - ticks.first) / span;
    final zero = frac(0);
    final fmt = formatValue ?? formatX;
    final n = labels.length;
    final m = math.max(1, series.length);
    final reduced = DashMotion.reduced(context);
    const axisH = Space.xl;
    const gap = Space.sm;
    const r = Radius.circular(Space.xs);

    final chart = SizedBox(
      height: height,
      child: Directionality(
        textDirection: dir,
        child: DashChartSelection<int>(
          builder: (context, active, touch) => LayoutBuilder(
            builder: (context, box) {
              final start = labelWidth + gap;
              final plotW = math.max(1.0, box.maxWidth - start);
              final rowH = (height - axisH) / math.max(1, n);
              // Recharts: 10% of a row around its bars, 4 between them.
              final barH = ((rowH * 0.8 - Space.xs * (m - 1)) / m).clamp(
                1.0,
                _maxBar,
              );
              final tickText = [for (final t in ticks) dashFigure(formatX(t))];
              final tickW = [
                for (final s in tickText) _textWidth(context, s, style),
              ];
              final tickX = [for (final t in ticks) start + plotW * frac(t)];
              final shown = _thinLabels(tickX, tickW, box.maxWidth);

              Widget bar(int s, int i) {
                final v = valueAt(s, i);
                final w = plotW * (frac(v) - zero).abs();
                final below = v < 0;
                return SizedBox(
                  height: barH,
                  child: Stack(
                    children: [
                      PositionedDirectional(
                        start: below ? null : plotW * zero,
                        end: below ? plotW * (1 - zero) : null,
                        top: 0,
                        bottom: 0,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: reduced ? w : 0, end: w),
                          duration: DashMotion.of(context, DashMotion.slow),
                          curve: DashMotion.ease,
                          builder: (context, width, _) => Container(
                            width: width,
                            decoration: BoxDecoration(
                              color: colors[s],
                              borderRadius: BorderRadiusDirectional.horizontal(
                                start: below ? r : Radius.zero,
                                end: below ? Radius.zero : r,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }

              Widget row(int i) => MouseRegion(
                onHover: (e) => touch(FlPointerHoverEvent(e), i),
                onExit: (e) => touch(FlPointerExitEvent(e), null),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => touch(FlTapUpEvent(d), i),
                  child: Semantics(
                    label: [
                      labels[i],
                      for (var s = 0; s < series.length; s++)
                        '${series[s].label} ${fmt(valueAt(s, i))}',
                    ].join(', '),
                    excludeSemantics: true,
                    child: Container(
                      height: rowH,
                      color: active == i ? c.muted : null,
                      child: Row(
                        spacing: gap,
                        children: [
                          SizedBox(
                            width: labelWidth,
                            // Against the bars, in the reading direction.
                            child: MadarClippedText(
                              labels[i],
                              textDirection: reading,
                              textAlign: dir == TextDirection.ltr
                                  ? TextAlign.right
                                  : TextAlign.left,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: style,
                            ),
                          ),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              spacing: Space.xs,
                              children: [
                                for (var s = 0; s < series.length; s++)
                                  bar(s, i),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  PositionedDirectional(
                    start: start,
                    top: 0,
                    width: plotW,
                    bottom: axisH,
                    child: CustomPaint(
                      painter: _VGrid(
                        [for (final t in ticks) frac(t)],
                        c.hairline,
                        rtl: dir == TextDirection.rtl,
                      ),
                    ),
                  ),
                  Column(
                    children: [
                      for (var i = 0; i < n; i++) row(i),
                      const SizedBox(height: axisH),
                    ],
                  ),
                  for (var k = 0; k < ticks.length; k++)
                    if (shown.contains(k))
                      PositionedDirectional(
                        start: (tickX[k] - tickW[k] / 2).clamp(
                          0.0,
                          math.max(0.0, box.maxWidth - tickW[k]),
                        ),
                        top: height - axisH + Space.xs,
                        child: ExcludeSemantics(
                          child: Text(
                            tickText[k],
                            style: style,
                            maxLines: 1,
                            softWrap: false,
                          ),
                        ),
                      ),
                  if (active != null && active < n)
                    PositionedDirectional(
                      start: start + Space.sm,
                      top: math.min(
                        (active + 0.5) * rowH + Space.sm,
                        math.max(0.0, height - axisH - Space.xxl * 1.5),
                      ),
                      child: IgnorePointer(
                        child: Directionality(
                          textDirection: reading,
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 240),
                            padding: const EdgeInsets.symmetric(
                              horizontal: Space.md,
                              vertical: Space.sm,
                            ),
                            decoration: BoxDecoration(
                              color: c.card,
                              borderRadius: BorderRadius.circular(Radii.xs),
                              border: Border.all(color: c.hairline),
                              boxShadow: DashShadows.popover(context),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(labels[active], style: _tipTitle(context)),
                                for (var s = 0; s < series.length; s++)
                                  Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: '● ',
                                          style: _tipBody(
                                            context,
                                          ).copyWith(color: colors[s]),
                                        ),
                                        TextSpan(
                                          text: '${series[s].label}  ',
                                          style: _tipBody(context),
                                        ),
                                        TextSpan(
                                          text: dashFigure(
                                            fmt(valueAt(s, active)),
                                          ),
                                          style: _tipValue(context),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.md,
      children: [
        chart,
        if (legend && series.length > 1)
          DashChartLegend(
            items: [
              for (var i = 0; i < series.length; i++)
                DashLegendItem(label: series[i].label, color: colors[i]),
            ],
          ),
      ],
    );
  }
}

/// Dashed vertical lines (3 on, 3 off) at [fractions] of the width, from
/// the right when [rtl].
class _VGrid extends CustomPainter {
  _VGrid(this.fractions, this.color, {required this.rtl});

  final List<double> fractions;
  final Color color;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (final f in fractions) {
      final x = (rtl ? 1 - f : f) * size.width;
      for (var y = 0.0; y < size.height; y += 6) {
        canvas.drawLine(
          Offset(x, y),
          Offset(x, math.min(y + 3, size.height)),
          p,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_VGrid old) =>
      old.color != color ||
      old.rtl != rtl ||
      !listEquals(old.fractions, fractions);
}

/// One slice of a [DashDonutChart].
@immutable
class DashSlice {
  const DashSlice({required this.label, required this.value, this.color});
  final String label;
  final double value;
  final Color? color;
}

/// A donut (or [pie]) with a centre figure and a legend carrying each
/// slice's share — tap a slice to bring it forward.
class DashDonutChart extends StatelessWidget {
  const DashDonutChart({
    required this.slices,
    this.formatValue,
    this.centerLabel,
    this.centerValue,
    this.pie = false,
    this.size = 180,
    this.legend = true,
    super.key,
  });

  final List<DashSlice> slices;

  /// Each slice's figure in the legend; shares are shown when null.
  final String Function(double)? formatValue;
  final String? centerLabel;
  final String? centerValue;
  final bool pie;
  final double size;
  final bool legend;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final f = context.dashFormats;
    final total = slices.fold<double>(0, (a, s) => a + s.value);
    final colors = [
      for (var i = 0; i < slices.length; i++)
        slices[i].color ?? dashSeriesColor(context, i),
    ];
    final radius = size / 2;
    final ring = pie ? radius : radius * 0.28;
    final chart = DashChartSelection<int>(
      builder: (context, kept, touch) {
        // Kept across a change of slices only while it still names one.
        final touched = kept != null && kept < slices.length ? kept : null;
        return SizedBox.square(
          dimension: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Its own layer (as [DashLineChart]'s).
              RepaintBoundary(
                child: PieChart(
                  duration: DashMotion.of(context, DashMotion.slow),
                  PieChartData(
                    sectionsSpace: slices.length > 1 ? 2 : 0,
                    centerSpaceRadius: pie ? 0 : radius - ring,
                    startDegreeOffset: -90,
                    pieTouchData: PieTouchData(
                      touchCallback: (e, r) =>
                          touch(e, switch (r?.touchedSection) {
                            // The grey ring of an all-zero chart is no slice.
                            final t?
                                when total > 0 && t.touchedSectionIndex >= 0 =>
                              t.touchedSectionIndex,
                            _ => null,
                          }),
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
                        for (var i = 0; i < slices.length; i++)
                          PieChartSectionData(
                            value: slices[i].value,
                            color: colors[i],
                            radius: i == touched ? ring + Space.xs : ring,
                            showTitle: false,
                          ),
                    ],
                  ),
                ),
              ),
              if (!pie && (centerValue != null || centerLabel != null))
                // A tap on the hole reaches the chart: it clears the slice.
                IgnorePointer(
                  child: SizedBox(
                    width: (radius - ring) * 1.6,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (centerValue != null)
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              dashFigure(
                                touched != null && formatValue != null
                                    ? formatValue!(slices[touched].value)
                                    : centerValue!,
                              ),
                              maxLines: 1,
                              softWrap: false,
                              style: DashType.statFigure(
                                18,
                              ).copyWith(color: c.textPrimary),
                            ),
                          ),
                        if (centerLabel != null)
                          Text(
                            touched != null
                                ? slices[touched].label
                                : centerLabel!,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DashType.small.copyWith(
                              color: c.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
    if (!legend) return chart;
    final items = [
      for (var i = 0; i < slices.length; i++)
        DashLegendItem(
          label: slices[i].label,
          color: colors[i],
          value: formatValue != null
              ? formatValue!(slices[i].value)
              : f.percent(total <= 0 ? 0 : slices[i].value / total),
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < size * 2 + Space.xl) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.lg,
            children: [
              Center(child: chart),
              DashChartLegend(items: items, vertical: true),
            ],
          );
        }
        return Row(
          spacing: Space.xl,
          children: [
            chart,
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: DashMetrics.popover + Space.xxl,
                ),
                child: DashChartLegend(items: items, vertical: true),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A tiny trend line with no axes (a KPI's last 14 days).
class DashSparkline extends StatelessWidget {
  const DashSparkline({
    required this.values,
    this.color,
    this.height = Space.xxl,
    this.area = true,
    super.key,
  });
  final List<double> values;
  final Color? color;
  final double height;
  final bool area;

  @override
  Widget build(BuildContext context) {
    final col = color ?? dashSeriesColor(context, 0);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final n = values.length;
    if (n < 2) return SizedBox(height: height);
    final maxV = values.fold<double>(values.first, math.max);
    final minV = values.fold<double>(values.first, math.min);
    final pad = (maxV - minV) * 0.1 + 0.0001;
    return ExcludeSemantics(
      child: SizedBox(
        height: height,
        child: LineChart(
          duration: Duration.zero,
          LineChartData(
            minX: 0,
            maxX: (n - 1).toDouble(),
            minY: minV - pad,
            maxY: maxV + pad,
            titlesData: const FlTitlesData(show: false),
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            lineTouchData: const LineTouchData(enabled: false),
            lineBarsData: [
              LineChartBarData(
                spots: [
                  for (var i = 0; i < n; i++)
                    FlSpot(
                      rtl ? (n - 1 - i).toDouble() : i.toDouble(),
                      values[i],
                    ),
                ]..sort((a, b) => a.x.compareTo(b.x)),
                isCurved: true,
                preventCurveOverShooting: true,
                color: col,
                barWidth: 1.5,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: area,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      col.withValues(alpha: 0.2),
                      col.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
