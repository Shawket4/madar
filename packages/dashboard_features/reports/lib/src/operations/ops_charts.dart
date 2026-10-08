/// The Operations charts, as the web draws them with Recharts:
///
/// - [OpsBarChart]: vertical bars over categories with EVERY label shown
///   (`interval={0}`; a label longer than its slot is cut, never skipped),
///   a dashed horizontal grid and a y axis of [OpsBarChart.yAxisWidth].
/// - [OpsHBarChart]: horizontal bars (`layout="vertical"`) with a 110 px
///   name axis, the Tellers and Waiters leaderboards.
/// - [OpsChartBody]: a chart card's body by state: a 288 px skeleton, a
///   frameless error with Retry (never drawn as empty), the page's empty
///   words, or the chart.
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

/// The web's `h-72` plot.
const double opsChartHeight = 288;

TextStyle _axisStyle(BuildContext context) => DashType.tableHeader.copyWith(
  letterSpacing: 0,
  fontWeight: FontWeight.w400,
  color: context.madarColors.textSecondary,
  fontFeatures: const [FontFeature.tabularFigures()],
);

/// A chart card's body: loading, failed, empty or the chart.
class OpsChartBody extends StatelessWidget {
  const OpsChartBody({
    required this.loading,
    required this.failed,
    required this.empty,
    required this.emptyTitle,
    required this.onRetry,
    required this.chart,
    this.height = opsChartHeight,
    super.key,
  });

  final bool loading;
  final bool failed;
  final bool empty;
  final String emptyTitle;
  final VoidCallback onRetry;
  final WidgetBuilder chart;

  /// The skeleton's and the states' height (null = their own).
  final double? height;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return DashSkeleton(height: height ?? opsChartHeight);
    }
    Widget sized(Widget w) => height == null
        ? w
        : SizedBox(height: height, child: Center(child: w));
    if (failed) {
      return sized(DashErrorState(framed: false, onRetry: onRetry));
    }
    if (empty) {
      return sized(DashEmptyState(title: emptyTitle, framed: false));
    }
    return chart(context);
  }
}

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
  final double maxBarWidth;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final textDir = Directionality.of(context);
    final maxV = values.fold<double>(0, math.max);
    final double maxY;
    final double step;
    if (integerAxis) {
      final top = math.max(1, maxV.ceil());
      final s = math.max(1, (top / 4).ceil());
      step = s.toDouble();
      maxY = (s * 4).toDouble();
    } else {
      maxY = dashNiceCeil(maxV);
      step = maxY / 4;
    }
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
              return BarChart(
                duration: DashMotion.of(context, DashMotion.slow),
                BarChartData(
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
                              i >= labels.length) {
                            return const SizedBox.shrink();
                          }
                          return SideTitleWidget(
                            meta: meta,
                            child: SizedBox(
                              width: slot,
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
class OpsHBarChart extends StatefulWidget {
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
  State<OpsHBarChart> createState() => _OpsHBarChartState();
}

class _OpsHBarChartState extends State<OpsHBarChart> {
  int? _active;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final textDir = Directionality.of(context);
    final style = _axisStyle(context);
    final maxV = widget.values.fold<double>(0, math.max);
    final maxX = dashNiceCeil(maxV);
    const axisHeight = Space.xl;
    const gap = Space.sm;
    final reduced = DashMotion.reduced(context);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        height: widget.height,
        child: LayoutBuilder(
          builder: (context, box) {
            final plotW = math.max(
              1.0,
              box.maxWidth - OpsHBarChart.nameAxis - gap - Space.md,
            );
            final n = math.max(1, widget.labels.length);
            final rowH = (widget.height - axisHeight) / n;
            final barH = math.min(rowH * 0.7, Space.xxl);
            Widget row(int i) {
              final v = i < widget.values.length ? widget.values[i] : 0.0;
              final w = maxX <= 0 ? 0.0 : plotW * (v / maxX);
              return MouseRegion(
                onEnter: (_) => setState(() => _active = i),
                onExit: (_) => setState(() => _active = null),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _active = _active == i ? null : i),
                  child: Semantics(
                    label: '${widget.labels[i]}: ${widget.tooltip(i)}',
                    excludeSemantics: true,
                    child: Container(
                      height: rowH,
                      color: _active == i ? c.muted.withValues(alpha: 0.6) : null,
                      child: Row(
                        children: [
                          SizedBox(
                            width: OpsHBarChart.nameAxis,
                            child: Directionality(
                              textDirection: textDir,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: MadarClippedText(
                                  widget.labels[i],
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
                              duration: reduced ? Duration.zero : DashMotion.slow,
                              curve: DashMotion.ease,
                              builder: (context, width, _) => Container(
                                width: width,
                                height: barH,
                                decoration: BoxDecoration(
                                  color: widget.color,
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

            final active = _active;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                // The dashed vertical grid.
                Positioned(
                  left: OpsHBarChart.nameAxis + gap,
                  top: 0,
                  width: plotW,
                  height: widget.height - axisHeight,
                  child: CustomPaint(painter: _VGrid(c.hairline)),
                ),
                Column(
                  children: [
                    for (var i = 0; i < widget.labels.length; i++) row(i),
                    const Spacer(),
                    SizedBox(
                      height: axisHeight,
                      child: Stack(
                        children: [
                          for (var k = 0; k <= 4; k++)
                            Positioned(
                              left:
                                  OpsHBarChart.nameAxis +
                                  gap +
                                  plotW * k / 4 -
                                  Space.xxl,
                              width: Space.xxl * 2,
                              bottom: 0,
                              child: Text(
                                dashFigure(widget.formatAxis(maxX * k / 4)),
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
                if (active != null && active < widget.labels.length)
                  Positioned(
                    left: OpsHBarChart.nameAxis + gap + Space.sm,
                    top: math.min(
                      (active + 0.5) * rowH + Space.sm,
                      widget.height - axisHeight - Space.xxl * 1.5,
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
                                widget.labels[active],
                                style: DashType.smallMedium.copyWith(
                                  color: c.textPrimary,
                                ),
                              ),
                              Text(
                                dashFigure(widget.tooltip(active)),
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
        canvas.drawLine(Offset(x, y), Offset(x, math.min(y + 3, size.height)), p);
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
      _RenderEqualRow(gap: gap, textDirection: Directionality.of(context));

  @override
  void updateRenderObject(BuildContext context, _RenderEqualRow renderObject) {
    renderObject
      ..gap = gap
      ..textDirection = Directionality.of(context);
  }
}

class _EqualRowParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderEqualRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _EqualRowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _EqualRowParentData> {
  _RenderEqualRow({required double gap, required TextDirection textDirection})
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
    if (child.parentData is! _EqualRowParentData) {
      child.parentData = _EqualRowParentData();
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
      (k.parentData! as _EqualRowParentData).offset = Offset(dx, 0);
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
