import 'dart:math' as math;

import 'package:design_system/design_system.dart';
import 'package:fl_chart/fl_chart.dart';
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

/// A "nice" axis ceiling for [max]: 1, 2, 2.5 or 5 × 10ⁿ.
double dashNiceCeil(double max) {
  if (max <= 0) return 1;
  final exp = math.pow(10, (math.log(max) / math.ln10).floor()).toDouble();
  for (final m in [1.0, 2.0, 2.5, 5.0, 10.0]) {
    if (m * exp >= max) return m * exp;
  }
  return 10 * exp;
}

/// Shared axis + grid + tooltip styling.
class _Axes {
  _Axes(
    this.context, {
    required this.labels,
    required this.formatY,
    required this.maxY,
    required this.width,
    double? yReserved,
  }) : yReserved = yReserved ?? _measure(context, formatY, maxY);

  final BuildContext context;
  final List<String> labels;
  final String Function(double) formatY;
  final double maxY;
  final double width;
  final double yReserved;

  /// Room for the widest y tick.
  static double _measure(
    BuildContext context,
    String Function(double) formatY,
    double maxY,
  ) {
    var w = 0.0;
    for (var i = 0; i <= 4; i++) {
      final tp = TextPainter(
        text: TextSpan(text: formatY(maxY * i / 4), style: _axisStyle(context)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      w = math.max(w, tp.width);
      tp.dispose();
    }
    return w + Space.md;
  }

  bool get rtl => Directionality.of(context) == TextDirection.rtl;

  /// Chart x for data index [i] — mirrored in Arabic so time runs from the
  /// right, the y axis sits on the right.
  double x(int i) => rtl ? (labels.length - 1 - i).toDouble() : i.toDouble();
  int index(double x) => rtl ? labels.length - 1 - x.round() : x.round();

  FlTitlesData titles({bool bars = false}) {
    final style = _axisStyle(context);
    final maxLabels = math.max(2, (width / 64).floor());
    final every = math.max(1, (labels.length / maxLabels).ceil());
    final y = AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: yReserved,
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
            final i = bars
                ? (rtl ? labels.length - 1 - v.round() : v.round())
                : index(v);
            if (i < 0 || i >= labels.length || i % every != 0) {
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
  }

  FlGridData grid() => FlGridData(
    drawVerticalLine: false,
    horizontalInterval: maxY / 4,
    getDrawingHorizontalLine: (_) => FlLine(
      color: context.madarColors.hairline,
      strokeWidth: 1,
      dashArray: const [3, 3],
    ),
  );

  TextStyle get tipTitle =>
      DashType.smallMedium.copyWith(color: context.madarColors.textPrimary);
  TextStyle get tipBody =>
      DashType.small.copyWith(color: context.madarColors.textSecondary);
  TextStyle get tipValue => DashType.monoMedium.copyWith(
    fontSize: 12,
    color: context.madarColors.textPrimary,
  );
}

/// A line or area chart over categories (days, hours) — the web's Recharts
/// `AreaChart` / `LineChart`. Theme-aware series colours, a dashed grid, y
/// ticks formatted by [formatY], a tooltip listing every series at the
/// touched x, and — in Arabic — the x axis running from the right with the
/// y axis on the right.
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
    super.key,
  });

  final List<String> labels;
  final List<DashSeries> series;

  /// Tick text for the y axis (compact).
  final String Function(double) formatY;

  /// Tooltip figures (full); defaults to [formatY].
  final String Function(double)? formatValue;

  /// Fill under the lines.
  final bool area;
  final bool curved;
  final double height;

  /// A legend under the plot when there is more than one series.
  final bool legend;

  /// Room for the y ticks; measured from them when null.
  final double? yReserved;

  @override
  Widget build(BuildContext context) {
    final colors = [
      for (var i = 0; i < series.length; i++)
        series[i].color ?? dashSeriesColor(context, i),
    ];
    final maxV = series.expand((s) => s.values).fold<double>(0, math.max);
    final maxY = dashNiceCeil(maxV);
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
                maxY: maxY,
                width: constraints.maxWidth,
                yReserved: yReserved,
              );
              final c = context.madarColors;
              return LineChart(
                duration: DashMotion.of(context, DashMotion.slow),
                LineChartData(
                  minX: 0,
                  maxX: math.max(1, labels.length - 1).toDouble(),
                  minY: 0,
                  maxY: maxY,
                  titlesData: ax.titles(),
                  gridData: ax.grid(),
                  borderData: FlBorderData(show: false),
                  lineTouchData: LineTouchData(
                    getTouchedSpotIndicator: (bar, spots) => [
                      for (final _ in spots)
                        TouchedSpotIndicatorData(
                          FlLine(color: c.input, strokeWidth: 1),
                          FlDotData(
                            getDotPainter: (spot, p, b, i) =>
                                FlDotCirclePainter(
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
                          for (
                            var i = 0;
                            i < series[si].values.length && i < labels.length;
                            i++
                          )
                            FlSpot(ax.x(i), series[si].values[i]),
                        ]..sort((a, b) => a.x.compareTo(b.x)),
                        isCurved: curved,
                        preventCurveOverShooting: true,
                        color: colors[si],
                        barWidth: 2,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: area,
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              colors[si].withValues(alpha: 0.22),
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
/// Recharts `BarChart`), with the same axes, tooltip and Arabic mirroring
/// as [DashLineChart].
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

  @override
  Widget build(BuildContext context) {
    final colors = [
      for (var i = 0; i < series.length; i++)
        series[i].color ?? dashSeriesColor(context, i),
    ];
    double valueAt(int s, int i) =>
        i < series[s].values.length ? series[s].values[i] : 0;
    final maxV = stacked
        ? [
            for (var i = 0; i < labels.length; i++)
              [
                for (var s = 0; s < series.length; s++) valueAt(s, i),
              ].fold<double>(0, (a, b) => a + b),
          ].fold<double>(0, math.max)
        : series.expand((s) => s.values).fold<double>(0, math.max);
    final maxY = dashNiceCeil(maxV);
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
                maxY: maxY,
                width: constraints.maxWidth,
                yReserved: yReserved,
              );
              final rtl = ax.rtl;
              final n = labels.length;
              final groupWidth =
                  (constraints.maxWidth - ax.yReserved) / math.max(1, n);
              final rodWidth = stacked
                  ? (groupWidth * 0.55).clamp(4.0, 32.0)
                  : (groupWidth * 0.7 / math.max(1, series.length)).clamp(
                      3.0,
                      20.0,
                    );
              final order = [for (var k = 0; k < n; k++) rtl ? n - 1 - k : k];
              return BarChart(
                duration: DashMotion.of(context, DashMotion.slow),
                BarChartData(
                  minY: 0,
                  maxY: maxY,
                  alignment: BarChartAlignment.spaceAround,
                  titlesData: ax.titles(bars: true),
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
                            : [ri];
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
                                  top: Radius.circular(Space.xs),
                                ),
                              ),
                            ],
                          );
                        }
                        return BarChartGroupData(
                          x: k,
                          barsSpace: 2,
                          barRods: [
                            for (final s
                                in (rtl
                                    ? [
                                        for (
                                          var q = series.length - 1;
                                          q >= 0;
                                          q--
                                        )
                                          q,
                                      ]
                                    : [
                                        for (var q = 0; q < series.length; q++)
                                          q,
                                      ]))
                              BarChartRodData(
                                toY: valueAt(s, i),
                                width: rodWidth,
                                color: colors[s],
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(Space.xs),
                                ),
                              ),
                          ],
                        );
                      }(),
                  ],
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
class DashDonutChart extends StatefulWidget {
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
  State<DashDonutChart> createState() => _DashDonutChartState();
}

class _DashDonutChartState extends State<DashDonutChart> {
  int _touched = -1;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final f = context.dashFormats;
    final total = widget.slices.fold<double>(0, (a, s) => a + s.value);
    final colors = [
      for (var i = 0; i < widget.slices.length; i++)
        widget.slices[i].color ?? dashSeriesColor(context, i),
    ];
    final radius = widget.size / 2;
    final ring = widget.pie ? radius : radius * 0.28;
    final chart = SizedBox.square(
      dimension: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            duration: DashMotion.of(context, DashMotion.slow),
            PieChartData(
              sectionsSpace: widget.slices.length > 1 ? 2 : 0,
              centerSpaceRadius: widget.pie ? 0 : radius - ring,
              startDegreeOffset: -90,
              pieTouchData: PieTouchData(
                touchCallback: (event, resp) {
                  if (!event.isInterestedForInteractions ||
                      resp?.touchedSection == null) {
                    if (_touched != -1) setState(() => _touched = -1);
                    return;
                  }
                  setState(
                    () => _touched = resp!.touchedSection!.touchedSectionIndex,
                  );
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
                  for (var i = 0; i < widget.slices.length; i++)
                    PieChartSectionData(
                      value: widget.slices[i].value,
                      color: colors[i],
                      radius: i == _touched ? ring + Space.xs : ring,
                      showTitle: false,
                    ),
              ],
            ),
          ),
          if (!widget.pie &&
              (widget.centerValue != null || widget.centerLabel != null))
            SizedBox(
              width: (radius - ring) * 1.6,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.centerValue != null)
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        dashFigure(
                          _touched >= 0 && widget.formatValue != null
                              ? widget.formatValue!(
                                  widget.slices[_touched].value,
                                )
                              : widget.centerValue!,
                        ),
                        maxLines: 1,
                        softWrap: false,
                        style: DashType.statFigure(
                          18,
                        ).copyWith(color: c.textPrimary),
                      ),
                    ),
                  if (widget.centerLabel != null)
                    Text(
                      _touched >= 0
                          ? widget.slices[_touched].label
                          : widget.centerLabel!,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DashType.small.copyWith(color: c.textSecondary),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
    if (!widget.legend) return chart;
    final items = [
      for (var i = 0; i < widget.slices.length; i++)
        DashLegendItem(
          label: widget.slices[i].label,
          color: colors[i],
          value: widget.formatValue != null
              ? widget.formatValue!(widget.slices[i].value)
              : f.percent(total <= 0 ? 0 : widget.slices[i].value / total),
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < widget.size * 2 + Space.xl) {
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
