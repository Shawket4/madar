/// Operations › Tables (`features/insights/tables-page.tsx`, REP-OPS-006…033,
/// 067, 069): which tables turn, how long parties stay, and what each table
/// and each guest is worth — from the metrics layer's `tables` dataset.
///
/// A full page nested in Operations: its header is a sub-heading (REP-ALL-021)
/// with the section filter under it; then the KPI strip, Busiest hours beside
/// Revenue by table (two columns from 1024 px), and the per-table ledger.
/// A row opens the table's history in a side panel.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show
        MetricsQueryResponse,
        WidgetOutcome,
        WidgetOutcomeError,
        WidgetOutcomeOk;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/report_shared.dart';
import 'ops_charts.dart';
import 'ops_data.dart';
import 'ops_support.dart';
import 'ops_table_sheet.dart';

// ── shaping (tables-util.ts) ──────────────────────────────────────────────

num _num(Object? v) => v is num && v.isFinite ? v : 0;
String _str(Object? v) => v is String ? v : '';

/// The rows of a widget that succeeded; none for one that failed.
List<Map<String, Object?>> _rowsOf(WidgetOutcome? o) =>
    o is WidgetOutcomeOk ? o.rows : const [];

/// One table's line of the ledger.
class OpsTableRow {
  const OpsTableRow({
    required this.branch,
    required this.section,
    required this.table,
    required this.turns,
    required this.turnsPerDay,
    required this.covers,
    required this.tableRevenue,
    required this.revenuePerCover,
    required this.avgDwellMinutes,
  });

  factory OpsTableRow.fromWire(Map<String, Object?> r) => OpsTableRow(
    branch: _str(r['branch']),
    section: _str(r['section']),
    table: _str(r['table']),
    turns: _num(r['turns']),
    turnsPerDay: _num(r['turns_per_day']),
    covers: _num(r['covers']),
    tableRevenue: _num(r['table_revenue']),
    revenuePerCover: _num(r['revenue_per_cover']),
    avgDwellMinutes: _num(r['avg_dwell_minutes']),
  );

  final String branch;
  final String section;
  final String table;
  final num turns;
  final num turnsPerDay;
  final num covers;
  final num tableRevenue;
  final num revenuePerCover;
  final num avgDwellMinutes;

  /// `[branch, section, table].join("|")`.
  String get key => '$branch|$section|$table';
}

/// The summary widget's figures.
class OpsTableSummary {
  const OpsTableSummary(this.r);

  final Map<String, Object?> r;

  num get turns => _num(r['turns']);
  num get turnsPerDay => _num(r['turns_per_day']);
  num get covers => _num(r['covers']);
  num get tableRevenue => _num(r['table_revenue']);
  num get revenuePerCover => _num(r['revenue_per_cover']);
  num get avgDwellMinutes => _num(r['avg_dwell_minutes']);
  num get activeTables => _num(r['active_tables']);
  num get revenuePerTable => _num(r['revenue_per_table']);
}

/// Hours of the day in order ("HH:00"), the gaps between the first and the
/// last filled with zero so the axis is honest.
List<(String, num)> opsHourSeries(WidgetOutcome? o) {
  final byHour = <String, Map<String, Object?>>{
    for (final r in _rowsOf(o)) _str(r['hour']): r,
  };
  final hours = byHour.keys.where((h) => h.isNotEmpty).toList()..sort();
  if (hours.isEmpty) return const [];
  final first = int.tryParse(hours.first.substring(0, 2)) ?? 0;
  final last = int.tryParse(hours.last.substring(0, 2)) ?? 23;
  return [
    for (var h = first; h <= last; h++)
      () {
        final key = '${h.toString().padLeft(2, '0')}:00';
        return (key, _num(byHour[key]?['turns']));
      }(),
  ];
}

/// Distinct sections, sorted, for the section filter.
List<String> opsSectionsOf(List<OpsTableRow> rows) =>
    {for (final r in rows) r.section}.toList()..sort();

/// Whether the request failed or any widget came back as an error.
bool opsTablesFailed(AsyncValue<MetricsQueryResponse> q) =>
    q.hasError ||
    (q.value?.results.values.any((r) => r is WidgetOutcomeError) ?? false);

// ── the tab ───────────────────────────────────────────────────────────────

const String _allSections = '__all__';

/// The web's `sm:max-w-md` side sheet.
const double opsTableSheetWidth = 448;

class OpsTablesView extends ConsumerStatefulWidget {
  const OpsTablesView({super.key});

  @override
  ConsumerState<OpsTablesView> createState() => _OpsTablesViewState();
}

class _OpsTablesViewState extends ConsumerState<OpsTablesView> {
  String _section = _allSections;

  @override
  void initState() {
    super.initState();
    // Back on the tab after the stale time: refetch quietly (REP-OPS-062).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final scope = ref.read(currentScopeProvider);
      final locale = ref.read(localeProvider);
      if (ref.read(opsCacheProvider).isStale(tablesKey(scope, locale))) {
        ref.invalidate(opsTablesProvider((scope, locale)));
      }
    });
  }

  Future<void> _open(OpsTableRow row) => showDashSidePanel<void>(
    context,
    width: opsTableSheetWidth,
    builder: (_) => OpsTableSheet(row: row),
  );

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final scope = ref.watch(currentScopeProvider);
    final locale = ref.watch(localeProvider) == 'ar' ? 'ar' : 'en';
    final key = (scope, locale);
    final q = ref.watch(opsTablesProvider(key));
    final data = q.value;
    final loading = q.firstLoad;
    final failed = opsTablesFailed(q);

    final summaryRows = _rowsOf(data?.results['summary']);
    final summary = summaryRows.isEmpty
        ? null
        : OpsTableSummary(summaryRows.first);
    final allRows = [
      for (final r in _rowsOf(data?.results['byTable']))
        OpsTableRow.fromWire(r),
    ];
    final sections = opsSectionsOf(allRows);
    // A section the new scope no longer has falls back to All sections, so
    // the ledger never hides behind a filter with no control (REP-OPS-067,
    // docs/fdash/divergences/reports-operations.md).
    final section = _section != _allSections && !sections.contains(_section)
        ? _allSections
        : _section;
    final rows = section == _allSections
        ? allRows
        : [
            for (final r in allRows)
              if (r.section == section) r,
          ];
    final hours = opsHourSeries(data?.results['byHour']);
    final topRevenue = [...rows]
      ..sort((a, b) => b.tableRevenue.compareTo(a.tableRevenue));
    final top = topRevenue.take(12).toList();

    final header = DashEmbeddedPages(
      child: DashPageHeader(
        title: t('tablesInsights.title'),
        subtitleWidget: const ReportPeriodSubtitle(),
        filters: sections.length > 1
            ? Align(
                alignment: AlignmentDirectional.centerStart,
                child: DashSelect<String>(
                  key: const ValueKey('ops-section-filter'),
                  expand: false,
                  minWidth: 160,
                  semanticLabel: t('tablesInsights.section'),
                  value: section,
                  options: [
                    DashOption(
                      value: _allSections,
                      label: t('tablesInsights.allSections'),
                    ),
                    for (final s in sections) DashOption(value: s, label: s),
                  ],
                  onChanged: (v) => setState(() => _section = v),
                ),
              )
            : null,
      ),
    );

    if (failed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.xl,
        children: [
          header,
          DashErrorState(
            title: t('tablesInsights.loadFailed'),
            retrying: q.isLoading,
            onRetry: () => ref.invalidate(opsTablesProvider(key)),
          ),
        ],
      );
    }

    final kpis = DashLedgerStrip(
      items: [
        DashLedgerItem(
          key: 'turns',
          label: t('tablesInsights.turns'),
          icon: 'rotate-ccw',
          value: summary?.turns ?? 0,
          format: DashStatFormat.number,
          loading: loading,
          hint: t(
            'tablesInsights.perDay',
            args: {'value': fmtNum(f, summary?.turnsPerDay ?? 0, maxDp: 2)},
          ),
        ),
        DashLedgerItem(
          key: 'covers',
          label: t('tablesInsights.covers'),
          icon: 'users',
          value: summary?.covers ?? 0,
          format: DashStatFormat.number,
          loading: loading,
        ),
        DashLedgerItem(
          key: 'revenue',
          label: t('tablesInsights.revenue'),
          icon: 'coins',
          value: summary?.tableRevenue ?? 0,
          format: DashStatFormat.money,
          loading: loading,
        ),
        DashLedgerItem(
          key: 'per_table',
          label: t('tablesInsights.revenuePerTable'),
          icon: 'armchair',
          value: summary?.revenuePerTable ?? 0,
          format: DashStatFormat.money,
          loading: loading,
          hint: t(
            'tablesInsights.tablesUsed',
            count: summary?.activeTables ?? 0,
          ),
        ),
        DashLedgerItem(
          key: 'per_cover',
          label: t('tablesInsights.revenuePerCover'),
          icon: 'user-round',
          value: summary?.revenuePerCover ?? 0,
          format: DashStatFormat.money,
          loading: loading,
        ),
        DashLedgerItem(
          key: 'dwell',
          label: t('tablesInsights.avgDwell'),
          icon: 'clock',
          valueText: fmtDwell(summary?.avgDwellMinutes ?? 0),
          loading: loading,
        ),
      ],
    );

    final empty = t('tablesInsights.empty');
    final busiest = DashChartCard(
      title: t('tablesInsights.busiestHours'),
      description: t('tablesInsights.busiestHoursHint'),
      child: OpsChartBody(
        loading: loading,
        failed: false,
        empty: hours.isEmpty,
        emptyTitle: empty,
        onRetry: () => ref.invalidate(opsTablesProvider(key)),
        chart: (_) => OpsBarChart(
          key: const ValueKey('ops-busiest-hours'),
          labels: [for (final (h, _) in hours) f.fmtWireTime(h)],
          values: [for (final (_, v) in hours) v.toDouble()],
          color: opsChartColor(c, 0),
          integerAxis: true,
          yAxisWidth: Space.xxl,
          formatAxis: (v) => fmtNum(f, v),
          tooltip: (i) =>
              '${t('tablesInsights.turns')}: ${fmtNum(f, hours[i].$2)}',
        ),
      ),
    );
    final byTable = DashChartCard(
      title: t('tablesInsights.topRevenue'),
      child: OpsChartBody(
        loading: loading,
        failed: false,
        empty: top.isEmpty,
        emptyTitle: empty,
        onRetry: () => ref.invalidate(opsTablesProvider(key)),
        chart: (_) => OpsBarChart(
          key: const ValueKey('ops-revenue-by-table'),
          labels: [for (final r in top) r.table],
          values: [for (final r in top) r.tableRevenue.toDouble()],
          color: opsChartColor(c, 1),
          formatAxis: f.fmtMoneyCompact,
          tooltip: (i) =>
              '${t('tablesInsights.revenue')}: ${f.fmtMoney(top[i].tableRevenue)}',
        ),
      ),
    );
    final wide = MediaQuery.sizeOf(context).width >= DashBreakpoints.lg;

    final table = DashDataTable<OpsTableRow>(
      key: const ValueKey('ops-tables-table'),
      rows: rows,
      rowKey: (r) => r.key,
      loading: loading,
      empty: DashEmptyState(title: empty),
      searchPlaceholder: t('tablesInsights.search'),
      onRowTap: _open,
      rowSemanticLabel: (r) => r.table,
      columns: [
        DashColumn<OpsTableRow>(
          id: 'table',
          label: t('tablesInsights.table'),
          phone: DashPhoneRole.title,
          text: (r) => r.table,
          cell: (context, r) => MadarClippedText(
            r.table,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DashType.bodyMedium.copyWith(color: c.textPrimary),
          ),
        ),
        DashColumn<OpsTableRow>(
          id: 'section',
          label: t('tablesInsights.section'),
          hideable: false,
          text: (r) => r.section,
        ),
        if (scope.branchId == null)
          DashColumn<OpsTableRow>(
            id: 'branch',
            label: t('tablesInsights.branch'),
            hideable: false,
            text: (r) => r.branch,
          ),
        // Search matches the raw values each column reads (REP-ALL-015).
        DashColumn<OpsTableRow>(
          id: 'turns',
          label: t('tablesInsights.turns'),
          numeric: true,
          hideable: false,
          minWidth: 80,
          text: (r) => '${r.turns}',
          cell: (context, r) => Text(dashFigure(fmtNum(f, r.turns))),
        ),
        DashColumn<OpsTableRow>(
          id: 'turns_per_day',
          label: t('tablesInsights.turnsPerDay'),
          numeric: true,
          hideable: false,
          minWidth: 96,
          text: (r) => '${r.turnsPerDay}',
          cell: (context, r) =>
              Text(dashFigure(fmtNum(f, r.turnsPerDay, maxDp: 2))),
        ),
        DashColumn<OpsTableRow>(
          id: 'covers',
          label: t('tablesInsights.covers'),
          numeric: true,
          hideable: false,
          minWidth: 80,
          text: (r) => '${r.covers}',
          cell: (context, r) => Text(dashFigure(fmtNum(f, r.covers))),
        ),
        DashColumn<OpsTableRow>(
          id: 'table_revenue',
          label: t('tablesInsights.revenue'),
          numeric: true,
          hideable: false,
          text: (r) => '${r.tableRevenue}',
          cell: (context, r) => Text(
            dashFigure(f.fmtMoney(r.tableRevenue)),
            style: DashType.monoStrong.copyWith(color: c.textPrimary),
          ),
        ),
        DashColumn<OpsTableRow>(
          id: 'revenue_per_cover',
          label: t('tablesInsights.revenuePerCover'),
          numeric: true,
          hideable: false,
          text: (r) => '${r.revenuePerCover}',
          cell: (context, r) => Text(dashFigure(f.fmtMoney(r.revenuePerCover))),
        ),
        DashColumn<OpsTableRow>(
          id: 'avg_dwell_minutes',
          label: t('tablesInsights.avgDwell'),
          numeric: true,
          hideable: false,
          minWidth: 96,
          text: (r) => '${r.avgDwellMinutes}',
          cell: (context, r) => Text(fmtDwell(r.avgDwellMinutes)),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: Space.sm),
          child: header,
        ),
        kpis,
        if (wide)
          OpsEqualRow(children: [busiest, byTable])
        else ...[
          busiest,
          byTable,
        ],
        table,
      ],
    );
  }
}
