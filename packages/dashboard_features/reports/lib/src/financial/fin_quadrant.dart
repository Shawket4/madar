/// The menu-engineering quadrant (`features/insights/quadrant-view.tsx`,
/// REP-FIN-043…045): popularity against margin per unit, one hue AND one
/// shape per class (never colour alone), the two dashed split lines, LTR
/// in both languages, an image to a screen reader with a one-sentence
/// verdict.
library;

import 'dart:math' as math;

import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'fin_data.dart';

/// The web's `h-[420px]`.
const double finQuadrantHeight = 420;

const double _yWidth = 64;
const double _xHeight = Space.xl + Space.xs;
const EdgeInsets _margin = EdgeInsets.only(top: 10, right: 20, bottom: 10);

enum FinShape { star, square, triangle, circle }

/// A class's mark: star = success star, workhorse = info square, challenge
/// = warning triangle, dog = destructive circle.
(Color, FinShape) finClassMark(MadarColors c, String klass) => switch (klass) {
  'star' => (c.success, FinShape.star),
  'workhorse' => (c.info, FinShape.square),
  'challenge' => (c.warning, FinShape.triangle),
  _ => (c.danger, FinShape.circle),
};

void _drawShape(Canvas canvas, Offset o, double r, FinShape s, Paint p) {
  switch (s) {
    case FinShape.circle:
      canvas.drawCircle(o, r, p);
    case FinShape.square:
      canvas.drawRect(Rect.fromCircle(center: o, radius: r * 0.9), p);
    case FinShape.triangle:
      canvas.drawPath(
        Path()
          ..moveTo(o.dx, o.dy - r * 1.1)
          ..lineTo(o.dx + r * 1.1, o.dy + r * 0.9)
          ..lineTo(o.dx - r * 1.1, o.dy + r * 0.9)
          ..close(),
        p,
      );
    case FinShape.star:
      final path = Path();
      for (var i = 0; i < 10; i++) {
        final rad = i.isEven ? r * 1.25 : r * 0.55;
        final a = -math.pi / 2 + i * math.pi / 5;
        final pt = o + Offset(math.cos(a) * rad, math.sin(a) * rad);
        i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(path..close(), p);
  }
}

class _ShapePainter extends FlDotPainter {
  const _ShapePainter(this.color, this.shape);

  final Color color;
  final FinShape shape;

  @override
  void draw(Canvas canvas, FlSpot spot, Offset offsetInCanvas) =>
      _drawShape(canvas, offsetInCanvas, 4.5, shape, Paint()..color = color);

  @override
  Size getSize(FlSpot spot) => const Size(12, 12);

  @override
  Color get mainColor => color;

  @override
  FlDotPainter lerp(FlDotPainter a, FlDotPainter b, double t) => b;

  @override
  List<Object?> get props => [color, shape];
}

/// `[0, auto]`-style bounds: a nice ceiling, and a nice floor below zero.
(double, double) _bounds(Iterable<double> v, {bool zeroFloor = false}) {
  final hi = v.fold<double>(0, math.max);
  final lo = v.fold<double>(0, math.min);
  return (
    zeroFloor || lo >= 0 ? 0 : -dashNiceCeil(-lo),
    hi <= 0 ? 0 : dashNiceCeil(hi),
  );
}

/// REP-FIN-044 a dot's tooltip: the item (· its size unless `one_size`),
/// its class, the two figures it is placed by (bold), then Qty, Revenue and
/// Margin.
({
  String title,
  String? size,
  String? klass,
  List<(String, String, bool)> lines,
})
finQuadrantTip(Translator t, DashFormat f, FinDot d) {
  final r = d.row;
  final unit = r.margin != null && r.quantitySold > 0
      ? (r.margin! / r.quantitySold).round()
      : null;
  return (
    title: r.itemName,
    size: r.sizeLabel == 'one_size' ? null : r.sizeLabel,
    klass: r.class_ == null
        ? null
        : t('insights.class.${r.class_}', defaultValue: r.class_),
    lines: [
      (t('insights.quadrant.unitMargin'), f.fmtMoney(unit), true),
      (t('insights.profitability.popularity'), f.fmtPercent(d.x / 100), true),
      (
        t('insights.profitability.quantity'),
        f.fmtNumber(r.quantitySold),
        false,
      ),
      (t('insights.profitability.revenue'), f.fmtMoney(r.revenue), false),
      (t('insights.profitability.margin'), f.fmtMoney(r.margin), false),
    ],
  );
}

class FinQuadrantView extends ConsumerWidget {
  const FinQuadrantView({required this.rows, super.key});

  /// The WHOLE ledger (the split lines belong to the full classified set).
  final List<MarginLedgerRow> rows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final m = FinQuadrant(rows);
    final summary = t(
      'insights.quadrant.summary',
      count: m.plotted,
      args: {
        'stars': f.fmtNumber(m.count('star')),
        'workhorses': f.fmtNumber(m.count('workhorse')),
        'challenges': f.fmtNumber(m.count('challenge')),
        'dogs': f.fmtNumber(m.count('dog')),
      },
    );
    final caption = DashType.small.copyWith(color: c.textSecondary);
    return DashChartCard(
      title: t('insights.quadrant.title'),
      description: t(
        'insights.quadrant.description',
        args: {
          'popularity': f.fmtPercent(m.popularityThresholdPct / 100),
          'margin': f.fmtMoney(m.unitMarginThreshold.round()),
        },
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.sm,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: Space.xxl * 2, right: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      t('insights.quadrant.challengesDogs'),
                      style: caption,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      t('insights.quadrant.starsWorkhorses'),
                      style: caption,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
            ),
            Semantics(
              image: true,
              label: summary,
              excludeSemantics: true,
              child: SizedBox(
                key: const ValueKey('fin-quadrant-plot'),
                height: finQuadrantHeight,
                child: _Plot(model: m),
              ),
            ),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: Space.lg,
              runSpacing: Space.xs,
              children: [
                for (final k in finClasses)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: Space.xs + DashMetrics.hair,
                    children: [
                      CustomPaint(
                        size: const Size(12, 12),
                        painter: _LegendMark(finClassMark(c, k)),
                      ),
                      Text(
                        t('insights.class.$k'),
                        style: DashType.small.copyWith(color: c.textSecondary),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendMark extends CustomPainter {
  const _LegendMark(this.mark);

  final (Color, FinShape) mark;

  @override
  void paint(Canvas canvas, Size size) => _drawShape(
    canvas,
    size.center(Offset.zero),
    size.width / 2.6,
    mark.$2,
    Paint()..color = mark.$1,
  );

  @override
  bool shouldRepaint(_LegendMark old) => old.mark != mark;
}

class _Plot extends ConsumerWidget {
  const _Plot({required this.model});

  final FinQuadrant model;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final dir = ref.watch(localeProvider).startsWith('ar')
        ? TextDirection.rtl
        : TextDirection.ltr;
    final c = context.madarColors;
    final m = model;
    final all = [for (final k in finClasses) ...m.dots[k]!];
    final (minX, maxX) = _bounds([
      ...all.map((d) => d.x),
      m.popularityThresholdPct,
    ], zeroFloor: true);
    final (minY, maxY) = _bounds([
      ...all.map((d) => d.y),
      m.unitMarginThreshold,
    ]);
    final spanY = math.max(1.0, maxY - minY);
    final spanX = math.max(1.0, maxX - minX);
    final byKey = <ScatterSpot, FinDot>{};
    final spots = <ScatterSpot>[];
    for (final k in finClasses) {
      final (color, shape) = finClassMark(c, k);
      for (final d in m.dots[k]!) {
        final s = ScatterSpot(
          d.x,
          d.y,
          dotPainter: _ShapePainter(color, shape),
        );
        byKey[s] = d;
        spots.add(s);
      }
    }
    final axis = DashType.tableHeader.copyWith(
      letterSpacing: 0,
      fontWeight: FontWeight.w400,
      color: c.textSecondary,
    );
    final line = FlLine(
      color: c.hairline,
      strokeWidth: 1,
      dashArray: const [3, 3],
    );
    final tipMuted = DashType.small.copyWith(color: c.textSecondary);
    final tipFig = DashType.mono.copyWith(fontSize: 12, color: c.textPrimary);
    final tipStrong = DashType.monoMedium.copyWith(
      fontSize: 12,
      color: c.textPrimary,
    );
    List<TextSpan> tip(FinDot d) {
      final q = finQuadrantTip(t, f, d);
      return [
        if (q.size != null) TextSpan(text: ' · ${q.size}', style: tipMuted),
        if (q.klass != null) TextSpan(text: '\n${q.klass}', style: tipMuted),
        for (final (label, value, strong) in q.lines)
          TextSpan(
            children: [
              TextSpan(text: '\n$label  ', style: tipMuted),
              TextSpan(
                text: dashFigure(value),
                style: strong ? tipStrong : tipFig,
              ),
            ],
          ),
      ];
    }

    return Padding(
      padding: _margin,
      child: Stack(
        children: [
          DashChartSelection<int>(
            builder: (context, at, touch) => ScatterChart(
              duration: DashMotion.of(context, DashMotion.slow),
              ScatterChartData(
                scatterSpots: spots,
                showingTooltipIndicators: [?at],
                minX: minX,
                maxX: maxX,
                minY: minY,
                maxY: maxY,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  horizontalInterval: spanY / 4,
                  verticalInterval: spanX / 4,
                  getDrawingHorizontalLine: (_) => line,
                  getDrawingVerticalLine: (_) => line,
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: _yWidth,
                      interval: spanY / 4,
                      getTitlesWidget: (v, meta) => SideTitleWidget(
                        meta: meta,
                        child: Text(
                          dashFigure(
                            f.fmtMoney(
                              v,
                              maxFractionDigits: 0,
                              currency: false,
                            ),
                          ),
                          style: axis,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: _xHeight,
                      interval: spanX / 4,
                      getTitlesWidget: (v, meta) => SideTitleWidget(
                        meta: meta,
                        child: Text(
                          dashFigure(f.fmtPercent(v / 100)),
                          style: axis,
                        ),
                      ),
                    ),
                  ),
                ),
                scatterTouchData: ScatterTouchData(
                  handleBuiltInTouches: false,
                  // A finger's reach around a 12 px mark.
                  touchSpotThreshold: Space.sm,
                  touchCallback: (e, r) => touch(e, r?.touchedSpot?.spotIndex),
                  touchTooltipData: ScatterTouchTooltipData(
                    getTooltipColor: (_) => c.card,
                    tooltipBorder: BorderSide(color: c.hairline),
                    tooltipBorderRadius: BorderRadius.circular(Radii.sm),
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    maxContentWidth: 240,
                    getTooltipItems: (s) {
                      final d = byKey[s];
                      if (d == null) return null;
                      return ScatterTooltipItem(
                        d.row.itemName,
                        textStyle: DashType.bodyStrong.copyWith(
                          color: c.textPrimary,
                        ),
                        textAlign: TextAlign.start,
                        textDirection: dir,
                        children: tip(d),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _SplitLines(
                  x: (m.popularityThresholdPct - minX) / spanX,
                  y: (m.unitMarginThreshold - minY) / spanY,
                  color: c.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The two dashed split lines (`ReferenceLine`s), at fractions of the plot.
class _SplitLines extends CustomPainter {
  const _SplitLines({required this.x, required this.y, required this.color});

  final double x;
  final double y;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(_yWidth, 0, size.width, size.height - _xHeight);
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    void dashed(Offset a, Offset b) {
      final len = (b - a).distance;
      final dir = (b - a) / len;
      for (var d = 0.0; d < len; d += 8) {
        canvas.drawLine(a + dir * d, a + dir * math.min(d + 4, len), p);
      }
    }

    final px = plot.left + plot.width * x;
    final py = plot.bottom - plot.height * y;
    dashed(Offset(px, plot.top), Offset(px, plot.bottom));
    dashed(Offset(plot.left, py), Offset(plot.right, py));
  }

  @override
  bool shouldRepaint(_SplitLines old) =>
      old.x != x || old.y != y || old.color != color;
}
