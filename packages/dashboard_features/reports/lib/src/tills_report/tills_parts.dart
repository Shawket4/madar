/// Pieces the three Till sessions tabs share: the one read's state as each
/// tab sees it ([TillsLoad]), the tab-level loading / failed / empty
/// states (REP-TIL-006, -007, -017), the web's outline `Badge`
/// ([TillOutlineBadge]) and the opens-and-closes chart ([TillHourChart],
/// REP-TIL-022).
library;

import 'dart:math' as math;

import 'package:dashboard_api/dashboard_api.dart' show TillSessionRow;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'tills_lib.dart';

/// The read as a tab sees it (the web's `rows`, `loading`, `error`,
/// `onRetry` props).
@immutable
class TillsLoad {
  const TillsLoad({
    required this.rows,
    this.loading = false,
    this.loaded = false,
    this.error,
    this.onRetry,
  });

  /// The sessions (empty until they arrive).
  final List<TillSessionRow> rows;

  /// The first load, nothing to show yet (React Query's `isLoading`).
  final bool loading;

  /// The answer is in (`q.data` is set): the subtitle may count.
  final bool loaded;

  /// The failure in words: the server's, or the refused-range sentence.
  final String? error;

  /// Null when retrying cannot help (a refused range).
  final VoidCallback? onRetry;
}

/// What a Sales or Open & close tab shows instead of its body: a 256-tall
/// skeleton while loading, the failure (never an empty period), the empty
/// sentence; null when the body should show.
Widget? tillTabState(BuildContext context, Translator t, TillsLoad load) {
  if (load.loading) {
    return const DashSkeleton(height: 256, radius: Radii.xs);
  }
  if (load.error != null) {
    return DashErrorState(message: load.error, onRetry: load.onRetry);
  }
  if (load.rows.isEmpty) {
    return DashEmptyState(title: t('reports.tills.empty'));
  }
  return null;
}

/// The web's `<Badge variant="outline">`: a hairline pill, 12/500 ink text.
class TillOutlineBadge extends StatelessWidget {
  const TillOutlineBadge(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm,
        vertical: DashMetrics.hair,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: c.border),
      ),
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        style: DashType.smallMedium.copyWith(color: c.textPrimary),
      ),
    );
  }
}

/// "Opens and closes by hour": 24 local-hour buckets, "Opened" in the lead
/// series hue and "Closed" in ink-grey (separates on lightness alone), a
/// label every third hour on the 12-hour clock, whole-number counts, a
/// tooltip naming the hour and both series, the legend under the plot.
///
/// The plot reads left to right in both languages, as the web's
/// (`.recharts-wrapper { direction: ltr }`). To a screen reader it is one
/// image described by [summary].
class TillHourChart extends ConsumerWidget {
  const TillHourChart({
    required this.buckets,
    required this.summary,
    super.key,
  });

  final List<TillHourBucket> buckets;
  final String summary;

  static const double _plotHeight = 252;
  static const double _yAxis = Space.xxl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final openedColor = dashSeriesColor(context, 0);
    final closedColor = c.textSecondary;
    final openedLabel = t('reports.tills.opened');
    final closedLabel = t('reports.tills.closed');

    final maxV = buckets.fold<int>(
      0,
      (m, b) => math.max(m, math.max(b.opened, b.closed)),
    );
    // Whole numbers only (`allowDecimals={false}`), about four steps.
    final step = maxV <= 4 ? 1 : (maxV / 4).ceil();
    final maxY = math.max(1, step * (maxV / step).ceil()).toDouble();

    final axis = DashType.tableHeader.copyWith(
      letterSpacing: 0,
      fontWeight: FontWeight.w400,
      color: c.textSecondary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final tipTitle = DashType.smallMedium.copyWith(color: c.textPrimary);
    final tipBody = DashType.small.copyWith(color: c.textSecondary);
    final tipValue = DashType.monoMedium.copyWith(
      fontSize: 12,
      color: c.textPrimary,
    );

    return Semantics(
      container: true,
      image: true,
      label: summary,
      excludeSemantics: true,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: Space.md,
          children: [
            SizedBox(
              height: _plotHeight,
              child: LayoutBuilder(
                builder: (context, box) {
                  final groupW = (box.maxWidth - _yAxis) / 24;
                  // A label every third hour; on a narrow plot every sixth
                  // or twelfth instead of letting the labels overlap.
                  final tp = TextPainter(
                    text: TextSpan(text: f.fmtHour(0), style: axis),
                    textDirection: TextDirection.ltr,
                    maxLines: 1,
                  )..layout();
                  final labelW = tp.width + Space.sm;
                  tp.dispose();
                  var stride = 3;
                  while (stride < 12 && stride * groupW < labelW) {
                    stride *= 2;
                  }
                  final gap = math.min(Space.xs, groupW * 0.1);
                  final rod = math.max(1.5, (groupW * 0.8 - gap) / 2);
                  final radius = Radius.circular(math.min(Space.xs, rod / 2));
                  return BarChart(
                    duration: DashMotion.of(context, DashMotion.slow),
                    BarChartData(
                      minY: 0,
                      maxY: maxY,
                      alignment: BarChartAlignment.spaceAround,
                      borderData: FlBorderData(show: false),
                      gridData: FlGridData(
                        drawVerticalLine: false,
                        horizontalInterval: step.toDouble(),
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
                            reservedSize: _yAxis,
                            interval: step.toDouble(),
                            getTitlesWidget: (v, meta) => SideTitleWidget(
                              meta: meta,
                              child: Text(
                                f.fmtNumber(v.round()),
                                style: axis,
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
                              final h = v.round();
                              if ((v - h).abs() > 0.01 ||
                                  h < 0 ||
                                  h > 23 ||
                                  h % stride != 0) {
                                return const SizedBox.shrink();
                              }
                              return SideTitleWidget(
                                meta: meta,
                                child: Text(
                                  f.fmtHour(h),
                                  style: axis,
                                  maxLines: 1,
                                  softWrap: false,
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
                          maxContentWidth: 220,
                          getTooltipItem: (group, gi, rod, ri) {
                            final b = buckets[group.x];
                            return BarTooltipItem(
                              '${f.fmtHour(b.hour)}\n',
                              tipTitle,
                              textAlign: TextAlign.start,
                              textDirection: Directionality.of(context),
                              children: [
                                TextSpan(
                                  text: '● ',
                                  style: tipBody.copyWith(color: openedColor),
                                ),
                                TextSpan(
                                  text: '$openedLabel  ',
                                  style: tipBody,
                                ),
                                TextSpan(
                                  text: f.fmtNumber(b.opened),
                                  style: tipValue,
                                ),
                                const TextSpan(text: '\n'),
                                TextSpan(
                                  text: '● ',
                                  style: tipBody.copyWith(color: closedColor),
                                ),
                                TextSpan(
                                  text: '$closedLabel  ',
                                  style: tipBody,
                                ),
                                TextSpan(
                                  text: f.fmtNumber(b.closed),
                                  style: tipValue,
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      barGroups: [
                        for (final b in buckets)
                          BarChartGroupData(
                            x: b.hour,
                            barsSpace: gap,
                            barRods: [
                              BarChartRodData(
                                toY: b.opened.toDouble(),
                                width: rod,
                                color: openedColor,
                                borderRadius: BorderRadius.vertical(
                                  top: radius,
                                ),
                              ),
                              BarChartRodData(
                                toY: b.closed.toDouble(),
                                width: rod,
                                color: closedColor,
                                borderRadius: BorderRadius.vertical(
                                  top: radius,
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
            Center(
              child: DashChartLegend(
                items: [
                  DashLegendItem(label: openedLabel, color: openedColor),
                  DashLegendItem(label: closedLabel, color: closedColor),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
