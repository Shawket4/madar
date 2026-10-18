/// The Operations charts, as the web draws them with Recharts:
///
/// - [OpsBarChart]: vertical bars over categories with EVERY label shown
///   (`interval={0}`; a label longer than its slot is cut, never skipped),
///   a dashed horizontal grid and a y axis of [OpsBarChart.yAxisWidth].
/// - [OpsHBarChart]: horizontal bars (`layout="vertical"`) with a 110 px
///   name axis, the Tellers and Waiters leaderboards.
/// - [OpsEqualRow]: two cards side by side at the taller one's height
///   (the report kit's chart grid, `ops_report_kit.dart`).
///
/// The plot area reads left to right in both languages (REP-ALL-020); the
/// bars animate unless reduced motion is on. The kit's bar chart mirrors in
/// Arabic and thins its labels, hence these (reported as kit candidates).
library;

import 'dart:math' as math;

import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// The web's `h-72` plot.
const double opsChartHeight = 288;

/// Recharts' tick step for a `[0, max]` axis of five ticks
/// (`recharts-scale` `getFormatStep`): the rough step `max / 4` rounded up
/// to a multiple of 0.05 × 10ⁿ (0.1 × 10ⁿ for a one-digit step), whole
/// for an [integer] axis. 272 → 70 (0…280); 2,489,300 → 650,000.
double opsNiceStep(double max, {bool integer = false}) {
  if (!(max > 0)) return 1;
  final rough = max / 4;
  final digits = (math.log(rough) / math.ln10).floor() + 1;
  final unit = math.pow(10, digits).toDouble();
  final scale = digits == 1 ? 0.1 : 0.05;
  // Round away float noise before the ceiling (0.7 / 0.05 is 13.999…).
  final ratio = (rough / unit / scale * 1e9).round() / 1e9;
  final step = ratio.ceil() * scale * unit;
  final clean = double.parse(step.toStringAsPrecision(12));
  return integer ? clean.ceilToDouble() : clean;
}

TextStyle _axisStyle(BuildContext context) => DashType.tableHeader.copyWith(
  letterSpacing: 0,
  fontWeight: FontWeight.w400,
  color: context.madarColors.textSecondary,
  fontFeatures: const [FontFeature.tabularFigures()],
);

/// Vertical bars, every category labelled.
class OpsBarChart extends StatelessWidget {
  const OpsBarChart({
    required this.labels,
    required this.values,
    required this.color,
    required this.formatAxis,
    required this.tooltip,
    this.tooltipTitle,
    this.yAxisWidth = 64,
    this.integerAxis = false,
    this.thinLabels = false,
    this.maxBarWidth = 56,
    this.height = opsChartHeight,
    super.key,
  });

  final List<String> labels;
  final List<double> values;
  final Color color;

  /// A y tick's words (compact money, a count).
  final String Function(double v) formatAxis;

  /// The tooltip's line for bar [i] ("Revenue: EGP 1,234.00").
  final String Function(int i) tooltip;

  /// The tooltip's header for bar [i]; defaults to its label.
  final String Function(int i)? tooltipTitle;
  final double yAxisWidth;

  /// Whole-number ticks only (`allowDecimals={false}`).
  final bool integerAxis;

  /// Skip labels that would not fit their slot (Recharts' default
  /// `interval`), where the default shows every one (`interval={0}`).
  final bool thinLabels;
  final double maxBarWidth;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final textDir = Directionality.of(context);
    final step = opsNiceStep(
      values.fold<double>(0, math.max),
      integer: integerAxis,
    );
    final maxY = step * 4;
    final style = _axisStyle(context);
    return Semantics(
      container: true,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (context, box) {
              final n = math.max(1, labels.length);
              final slot = (box.maxWidth - yAxisWidth) / n;
              final bar = math.min(maxBarWidth, slot * 0.8);
              var every = 1;
              if (thinLabels && labels.isNotEmpty) {
                final widest = labels
                    .map((l) {
                      final tp = TextPainter(
                        text: TextSpan(text: l, style: style),
                        textDirection: textDir,
                        maxLines: 1,
                      )..layout();
                      final w = tp.width;
                      tp.dispose();
                      return w;
                    })
                    .fold<double>(0, math.max);
                every = math.max(1, ((widest + Space.sm) / slot).ceil());
              }
              final data = BarChartData(
                minY: 0,
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
                      reservedSize: yAxisWidth,
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
                            i % every != 0) {
                          return const SizedBox.shrink();
                        }
                        return SideTitleWidget(
                          meta: meta,
                          child: SizedBox(
                            width: slot * every,
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
                      '${(tooltipTitle ?? (i) => labels[i])(gi)}\n',
                      DashType.smallMedium.copyWith(color: c.textPrimary),
                      textAlign: TextAlign.start,
                      textDirection: textDir,
                      children: [
                        TextSpan(
                          text: dashFigure(tooltip(gi)),
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
                          toY: i < values.length ? values[i] : 0,
                          width: bar,
                          color: color,
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
      ),
    );
  }
}

/// Horizontal bars with the names on a 110 px axis (the Tellers and
/// Waiters leaderboards); a tap or hover on a row shows its figure.
class OpsHBarChart extends StatelessWidget {
  const OpsHBarChart({
    required this.labels,
    required this.values,
    required this.color,
    required this.formatAxis,
    required this.tooltip,
    this.height = opsChartHeight,
    super.key,
  });

  final List<String> labels;
  final List<double> values;
  final Color color;
  final String Function(double v) formatAxis;

  /// The tooltip's line for row [i].
  final String Function(int i) tooltip;
  final double height;

  /// The web's `YAxis width={110}`.
  static const double nameAxis = 110;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final textDir = Directionality.of(context);
    final style = _axisStyle(context);
    final maxX = opsNiceStep(values.fold<double>(0, math.max)) * 4;
    const axisHeight = Space.xl;
    const gap = Space.sm;
    final reduced = DashMotion.reduced(context);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        height: height,
        child: DashChartSelection<int>(
          builder: (context, active, touch) => LayoutBuilder(
            builder: (context, box) {
              final plotW = math.max(
                1.0,
                box.maxWidth - OpsHBarChart.nameAxis - gap - Space.md,
              );
              final n = math.max(1, labels.length);
              final rowH = (height - axisHeight) / n;
              // Ticks that would touch are skipped (every other, then the
              // ends), as Recharts thins its axis.
              final widest =
                  [
                        for (var k = 0; k <= 4; k++)
                          dashFigure(formatAxis(maxX * k / 4)),
                      ]
                      .map((l) {
                        final tp = TextPainter(
                          text: TextSpan(text: l, style: style),
                          textDirection: textDir,
                          maxLines: 1,
                        )..layout();
                        final w = tp.width;
                        tp.dispose();
                        return w;
                      })
                      .fold<double>(0, math.max);
              final tickStep = plotW / 4 >= widest + Space.sm
                  ? 1
                  : plotW / 2 >= widest + Space.sm
                  ? 2
                  : 4;
              final barH = math.min(rowH * 0.7, Space.xxl);
              Widget row(int i) {
                final v = i < values.length ? values[i] : 0.0;
                final w = maxX <= 0 ? 0.0 : plotW * (v / maxX);
                return MouseRegion(
                  onHover: (e) => touch(FlPointerHoverEvent(e), i),
                  onExit: (e) => touch(FlPointerExitEvent(e), null),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) => touch(FlTapUpEvent(d), i),
                    child: Semantics(
                      label: '${labels[i]}: ${tooltip(i)}',
                      excludeSemantics: true,
                      child: Container(
                        height: rowH,
                        color: active == i
                            ? c.muted.withValues(alpha: 0.6)
                            : null,
                        child: Row(
                          children: [
                            SizedBox(
                              width: OpsHBarChart.nameAxis,
                              child: Directionality(
                                textDirection: textDir,
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: MadarClippedText(
                                    labels[i],
                                    style: style,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.right,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: gap),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TweenAnimationBuilder<double>(
                                tween: Tween(begin: reduced ? w : 0, end: w),
                                duration: reduced
                                    ? Duration.zero
                                    : DashMotion.slow,
                                curve: DashMotion.ease,
                                builder: (context, width, _) => Container(
                                  width: width,
                                  height: barH,
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: const BorderRadius.horizontal(
                                      right: Radius.circular(Space.xs),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // The dashed vertical grid.
                  Positioned(
                    left: OpsHBarChart.nameAxis + gap,
                    top: 0,
                    width: plotW,
                    height: height - axisHeight,
                    child: CustomPaint(painter: _VGrid(c.hairline)),
                  ),
                  Column(
                    children: [
                      for (var i = 0; i < labels.length; i++) row(i),
                      const Spacer(),
                      SizedBox(
                        height: axisHeight,
                        child: Stack(
                          children: [
                            for (var k = 0; k <= 4; k += tickStep)
                              Positioned(
                                // Centred on its tick, kept inside the card.
                                left:
                                    (OpsHBarChart.nameAxis +
                                            gap +
                                            plotW * k / 4 -
                                            Space.xxl)
                                        .clamp(0, box.maxWidth - Space.xxl * 2),
                                width: Space.xxl * 2,
                                bottom: 0,
                                child: Text(
                                  dashFigure(formatAxis(maxX * k / 4)),
                                  style: style,
                                  maxLines: 1,
                                  softWrap: false,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (active != null && active < labels.length)
                    Positioned(
                      left: OpsHBarChart.nameAxis + gap + Space.sm,
                      top: math.min(
                        (active + 0.5) * rowH + Space.sm,
                        height - axisHeight - Space.xxl * 1.5,
                      ),
                      child: IgnorePointer(
                        child: Directionality(
                          textDirection: textDir,
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
                                Text(
                                  labels[active],
                                  style: DashType.smallMedium.copyWith(
                                    color: c.textPrimary,
                                  ),
                                ),
                                Text(
                                  dashFigure(tooltip(active)),
                                  style: DashType.small.copyWith(
                                    color: c.textSecondary,
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
  }
}

class _VGrid extends CustomPainter {
  _VGrid(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var k = 0; k <= 4; k++) {
      final x = size.width * k / 4;
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
  bool shouldRepaint(_VGrid old) => old.color != color;
}

/// Cards side by side sharing one height (the web's grid row, whose cards
/// stretch to the tallest): equal widths, the row as tall as its tallest
/// card, every card stretched to it. Mirrors in Arabic.
class OpsEqualRow extends MultiChildRenderObjectWidget {
  const OpsEqualRow({required super.children, this.gap = Space.lg, super.key});

  final double gap;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderOpsEqualRow(gap: gap, textDirection: Directionality.of(context));

  @override
  void updateRenderObject(
    BuildContext context,
    RenderOpsEqualRow renderObject,
  ) {
    renderObject
      ..gap = gap
      ..textDirection = Directionality.of(context);
  }
}

class OpsEqualRowParentData extends ContainerBoxParentData<RenderBox> {}

class RenderOpsEqualRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, OpsEqualRowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, OpsEqualRowParentData> {
  RenderOpsEqualRow({required double gap, required TextDirection textDirection})
    : _gap = gap,
      _textDirection = textDirection;

  double _gap;
  set gap(double v) {
    _gap = v;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection v) {
    _textDirection = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! OpsEqualRowParentData) {
      child.parentData = OpsEqualRowParentData();
    }
  }

  @override
  void performLayout() {
    final kids = <RenderBox>[];
    var child = firstChild;
    while (child != null) {
      kids.add(child);
      child = childAfter(child);
    }
    final width = constraints.maxWidth;
    if (kids.isEmpty) {
      size = constraints.constrain(Size(width, 0));
      return;
    }
    final w = (width - _gap * (kids.length - 1)) / kids.length;
    var tallest = 0.0;
    for (final k in kids) {
      k.layout(BoxConstraints.tightFor(width: w), parentUsesSize: true);
      tallest = math.max(tallest, k.size.height);
    }
    var x = 0.0;
    for (final k in kids) {
      k.layout(BoxConstraints.tight(Size(w, tallest)), parentUsesSize: true);
      final dx = _textDirection == TextDirection.rtl ? width - x - w : x;
      (k.parentData! as OpsEqualRowParentData).offset = Offset(dx, 0);
      x += w + _gap;
    }
    size = constraints.constrain(Size(width, tallest));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
