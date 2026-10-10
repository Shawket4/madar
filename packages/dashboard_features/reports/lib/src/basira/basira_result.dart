/// One answer's evidence (`result-block.tsx` and the page's `BlockCard` /
/// `Provenance`): a card with the block's title and scope, the result drawn
/// by its `viz` (REP-BAS-022–025, 032, the table of 034), and the resolved
/// query one tap away (REP-BAS-019–021).
///
/// Nothing here knows a metric: every column says how it is formatted, so a
/// preset the backend adds renders the day it ships.
library;

import 'dart:math' as math;

import 'package:dashboard_api/dashboard_api.dart' as wire;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'basira_charts.dart';
import 'basira_models.dart';

/// The web's `max-h`/`h-60` chart frame.
const double basiraChartHeight = 240;

/// One cell by its column's kind (`formatCell`). Null is "—", never zero: an
/// unknown cost is not a free one.
String basiraCell(
  Object? value,
  wire.ColumnKind kind,
  DashFormat fmt,
  Translator t,
) {
  if (value == null) return '—';
  if (!isMeasureKind(kind)) return rawText(value);
  final n = numOf(value);
  if (n == null) return '—';
  switch (kind) {
    case wire.ColumnKind.money:
      return fmt.fmtMoney(n);
    case wire.ColumnKind.count:
      return fmt.fmtNumber(n);
    case wire.ColumnKind.number:
      return fmt.fmtNumber(n, const NumberOptions(maximumFractionDigits: 1));
    default:
      // Minutes, rounded once (the web rounds the parts apart: "1h 60m").
      final total = n.round();
      if (total < 60) {
        return t('basira.minutesShort', args: {'m': fmt.fmtNumber(total)});
      }
      final h = total ~/ 60;
      final m = total % 60;
      return m == 0
          ? t('basira.hoursShort', args: {'h': h})
          : t('basira.hoursMinutesShort', args: {'h': h, 'm': m});
  }
}

/// A period end as the org's calendar day (`YYYY-MM-DD`).
String basiraDay(String iso, String timezone) {
  final d = parseJsDate(iso);
  if (d == null) return iso.length >= 10 ? iso.substring(0, 10) : iso;
  final z = inZone(d, timezone);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${z.year}-${two(z.month)}-${two(z.day)}';
}

/// The provenance's two lines (REP-BAS-021).
(String, String) basiraProvenance(
  wire.ResultBlock block, {
  required bool stale,
  required Translator t,
  required String timezone,
}) {
  final spec = block.spec;
  final dims = spec.dimensions ?? const [];
  final measures = spec.measures ?? const [];
  final filters = spec.filters ?? const {};
  // In Arabic each code-like part keeps its own direction, so the parts
  // read right to left without the tokens running into each other.
  String own(String s) => t.isRtl ? ownDirection(s) : s;
  final what = [
    own(spec.dataset),
    if (dims.isNotEmpty)
      t('basira.provenanceBy', args: {'dims': own(dims.join(' × '))}),
    if (measures.isNotEmpty) own(measures.join(', ')),
    if (filters.isNotEmpty)
      own([for (final e in filters.entries) '${e.key}=${e.value}'].join(' ')),
  ].join(' · ');
  final from = block.periodFrom, to = block.periodTo;
  final period = from != null && to != null
      ? own('${basiraDay(from, timezone)} → ${basiraDay(to, timezone)}')
      : t('basira.allTime');
  final where =
      '$period · ${own(block.scope.label)} · ${block.rowCount} '
      '${t('basira.rows')}${stale ? ' · ${t('basira.stored')}' : ''}';
  return (what, where);
}

/// A result card (`BlockCard`).
class BasiraBlockCard extends ConsumerStatefulWidget {
  const BasiraBlockCard({required this.block, this.stale = false, super.key});

  final wire.ResultBlock block;

  /// From history: the provenance says "stored".
  final bool stale;

  @override
  ConsumerState<BasiraBlockCard> createState() => _BasiraBlockCardState();
}

class _BasiraBlockCardState extends ConsumerState<BasiraBlockCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final block = widget.block;
    final wide = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm;
    final side = wide ? Space.lg : Space.md;
    final head = [
      if (block.title != null)
        Text(
          ownDirection(block.title!),
          style: DashType.meta.copyWith(
            fontWeight: FontWeight.w500,
            color: c.textPrimary,
          ),
        ),
      ?BasiraScopeBadge.maybe(block, t),
    ];
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: c.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (head.isNotEmpty)
            Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                side,
                side - Space.xs,
                side,
                0,
              ),
              child: Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: head,
              ),
            ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: side, vertical: Space.md),
            child: BasiraResultView(block: block),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.hairline)),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: side,
                vertical: Space.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: _ProvenanceToggle(
                      open: _open,
                      label: t('basira.provenance'),
                      onTap: () => setState(() => _open = !_open),
                    ),
                  ),
                  if (_open)
                    _Provenance(
                      lines: basiraProvenance(
                        block,
                        stale: widget.stale,
                        t: t,
                        timezone: ref.watch(formatProvider).timezone,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProvenanceToggle extends StatelessWidget {
  const _ProvenanceToggle({
    required this.open,
    required this.label,
    required this.onTap,
  });

  final bool open;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return DashPressable(
      onTap: onTap,
      expanded: open,
      semanticLabel: label,
      excludeChildSemantics: true,
      pressScale: false,
      builder: (context, s) {
        final fg = s.highlighted ? c.textPrimary : c.textSecondary;
        return ConstrainedBox(
          constraints: const BoxConstraints(minHeight: DashMetrics.target),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: Space.xs,
            children: [
              AnimatedRotation(
                turns: open ? 0.5 : 0,
                duration: DashMotion.of(context, DashMotion.base),
                child: DashIcon('chevron-down', size: IconSize.xs, color: fg),
              ),
              Text(label, style: DashType.small.copyWith(color: fg)),
            ],
          ),
        );
      },
    );
  }
}

class _Provenance extends StatelessWidget {
  const _Provenance({required this.lines});

  final (String, String) lines;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final style = DashType.mono.copyWith(
      fontSize: BasiraMetrics.caption,
      color: c.textSecondary,
    );
    return Container(
      margin: const EdgeInsets.only(top: Space.sm),
      padding: const EdgeInsets.all(BasiraMetrics.snug),
      decoration: BoxDecoration(
        color: c.muted.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(Radii.xs),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(lines.$1, style: style),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: BasiraMetrics.tight),
            child: Divider(height: 1, thickness: 1, color: c.hairline),
          ),
          Text(lines.$2, style: style),
        ],
      ),
    );
  }
}

/// The scope an answer covers, when it is worth saying (`ScopeBadge`).
class BasiraScopeBadge extends StatelessWidget {
  const BasiraScopeBadge(this.label, {super.key});

  final String label;

  /// The badge for [block], or nothing when it covers every branch and
  /// nothing went unmatched (REP-BAS-020).
  static BasiraScopeBadge? maybe(wire.ResultBlock block, Translator t) {
    final s = block.scope;
    final unmatched = s.unmatchedBranch;
    if (unmatched == null && s.allBranches) return null;
    return BasiraScopeBadge(
      unmatched != null
          ? t('basira.unmatchedBranch', args: {'name': unmatched})
          : s.label,
    );
  }

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
        border: Border.all(color: c.hairline),
      ),
      child: Text(
        label,
        style: DashType.small.copyWith(
          fontSize: BasiraMetrics.caption,
          color: c.textPrimary,
        ),
      ),
    );
  }
}

/// Any result, whatever its shape (`ResultView`).
class BasiraResultView extends ConsumerWidget {
  const BasiraResultView({required this.block, super.key});

  final wire.ResultBlock block;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    // An empty result is not a zero (REP-BAS-022).
    if (block.rowCount == 0) {
      return DashEmptyState(title: t('basira.noActivity'), framed: false);
    }
    final dims = dimensionsOf(block.columns);
    final measures = measuresOf(block.columns);
    final axis = dims.firstOrNull;
    final labels = [
      for (final r in block.rows)
        axis == null ? '' : dimensionText(r[axis.key]),
    ];
    List<double?> plotted(wire.Column m) => [
      for (final r in block.rows) plotValue(r[m.key], m.kind),
    ];
    // A tooltip figure: the plotted pounds back to piastres for money.
    String tip(wire.Column m, double v) => basiraCell(
      m.kind == wire.ColumnKind.money ? v * 100 : v,
      m.kind,
      fmt,
      t,
    );
    final series = [
      for (final m in measures)
        BasiraSeries(
          label: m.label,
          values: plotted(m),
          format: (v) => tip(m, v),
        ),
    ];

    final Widget body = switch (block.viz) {
      wire.Viz.kpi => _Kpis(block: block, measures: measures),
      wire.Viz.line || wire.Viz.area => BasiraAreaChart(
        labels: labels,
        series: series,
        height: basiraChartHeight,
      ),
      wire.Viz.bar || wire.Viz.row => BasiraBarChart(
        labels: labels,
        series: series.take(2).toList(),
        horizontal: block.viz == wire.Viz.row,
        height: basiraChartHeight,
      ),
      wire.Viz.pie || wire.Viz.donut when measures.isNotEmpty => BasiraPieChart(
        labels: labels,
        values: [for (final v in series.first.values) v ?? 0],
        format: series.first.format,
        donut: block.viz == wire.Viz.donut,
        height: basiraChartHeight,
      ),
      wire.Viz.heatmap => BasiraHeatmap(block: block),
      _ => BasiraTable(block: block),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.sm,
      children: [
        body,
        if (block.truncated)
          Text(
            t('basira.truncated', args: {'count': block.rows.length}),
            style: DashType.small.copyWith(
              fontSize: BasiraMetrics.caption,
              color: c.textSecondary,
            ),
          ),
      ],
    );
  }
}

class _Kpis extends ConsumerWidget {
  const _Kpis({required this.block, required this.measures});

  final wire.ResultBlock block;
  final List<wire.Column> measures;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    final row = block.rows.firstOrNull ?? const <String, Object?>{};
    return Wrap(
      spacing: Space.xl,
      runSpacing: Space.lg,
      children: [
        for (final m in measures)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            spacing: Space.xs,
            children: [
              Text(
                m.label,
                style: DashType.meta.copyWith(
                  fontWeight: FontWeight.w500,
                  color: c.textSecondary,
                ),
              ),
              Text(
                ltr(basiraCell(row[m.key], m.kind, fmt, t)),
                style: DashType.statFigure(24).copyWith(color: c.textPrimary),
              ),
            ],
          ),
      ],
    );
  }
}

/// Every column as a table, 25 rows a page, no Columns menu (row 034).
class BasiraTable extends ConsumerWidget {
  const BasiraTable({required this.block, super.key});

  final wire.ResultBlock block;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    return DashDataTable<Map<String, Object?>>(
      columns: [
        for (final col in block.columns)
          DashColumn<Map<String, Object?>>(
            id: col.key,
            label: col.label,
            numeric: isMeasureKind(col.kind),
            text: (r) => basiraCell(r[col.key], col.kind, fmt, t),
          ),
      ],
      rows: block.rows,
      rowKey: (r) => r,
      pageSize: 25,
      hideViewOptions: true,
    );
  }
}

/// Two dimensions and a measure as an intensity grid (REP-BAS-032); any
/// other shape is the table.
class BasiraHeatmap extends ConsumerWidget {
  const BasiraHeatmap({required this.block, super.key});

  final wire.ResultBlock block;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dims = dimensionsOf(block.columns);
    final measure = measuresOf(block.columns).firstOrNull;
    if (dims.length < 2 || measure == null) return BasiraTable(block: block);
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    final hue = dashSeriesColor(context, 0);
    final grid = basiraHeatmapGrid(
      block.rows,
      dims[0].key,
      dims[1].key,
      measure.key,
    );
    final label = DashType.mono.copyWith(
      fontSize: BasiraMetrics.micro,
      color: c.textSecondary,
    );
    const cell = Space.xl;
    // The grid fills the card (`w-full`) and scrolls sideways once its
    // cells would go under their 24 minimum. Left to right in Arabic too,
    // like the charts (REP-ALL-020): labels on the left, hours left to right.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: math.max(
              box.maxWidth,
              Space.xxl * 2 + grid.cols.length * (cell + DashMetrics.hair),
            ),
            child: Table(
              columnWidths: const {0: IntrinsicColumnWidth()},
              defaultColumnWidth: const FlexColumnWidth(),
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(
                  children: [
                    const SizedBox.shrink(),
                    for (final col in grid.cols)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Space.xs),
                        child: Text(
                          col,
                          textAlign: TextAlign.center,
                          style: label,
                        ),
                      ),
                  ],
                ),
                for (final row in grid.rows)
                  TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          end: Space.sm,
                        ),
                        child: Text(
                          row,
                          textAlign: TextAlign.end,
                          style: label,
                        ),
                      ),
                      for (final col in grid.cols)
                        Builder(
                          builder: (context) {
                            final v = grid.value(row, col);
                            final words =
                                '$row · $col · ${basiraCell(v, measure.kind, fmt, t)}';
                            return Tooltip(
                              message: words,
                              child: Semantics(
                                label: words,
                                child: Container(
                                  margin: const EdgeInsets.all(
                                    DashMetrics.hair / 2,
                                  ),
                                  constraints: const BoxConstraints(
                                    minWidth: cell,
                                    minHeight: cell,
                                  ),
                                  decoration: BoxDecoration(
                                    color: hue.withValues(
                                      alpha: grid.opacity(v),
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      DashMetrics.hair,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The heatmap's grid: rows in first-seen order, columns sorted, each cell's
/// value (0 when absent) and its opacity.
({
  List<String> rows,
  List<String> cols,
  num Function(String row, String col) value,
  double Function(num v) opacity,
})
basiraHeatmapGrid(
  List<Map<String, Object?>> data,
  String rowKey,
  String colKey,
  String measureKey,
) {
  final rows = <String>{for (final r in data) rawText(r[rowKey])}.toList();
  final cols = <String>{for (final r in data) rawText(r[colKey])}.toList()
    ..sort();
  final lookup = <String, num>{
    for (final r in data)
      '${rawText(r[rowKey])}|${rawText(r[colKey])}': numOf(r[measureKey]) ?? 0,
  };
  final max = [1, ...lookup.values].reduce((a, b) => a > b ? a : b);
  return (
    rows: rows,
    cols: cols,
    value: (r, c) => lookup['$r|$c'] ?? 0,
    // Opacity carries the value; a hue ramp would imply categories.
    opacity: (v) => v == 0 ? 0.06 : 0.15 + (v / max) * 0.85,
  );
}
