/// `/reports/tills` Till sessions (REP-TIL rows): tabs Sessions, Sales,
/// Open & close over one read (`features/reports/tills/till-sessions-page.tsx`,
/// `sales-tab.tsx`, `timing-tab.tsx`, `lib.ts`).
///
/// - Offered to holders of `till.read.branch` only: the route answers plain
///   `till.read` with the caller's OWN drawers, which under this title would
///   read as the branch's. Without it: `Restricted` with the reports words,
///   and the sessions are never asked for (REP-TIL-001).
/// - One read for the scope's branch (or every branch the person works at)
///   and range; all three tabs share it (REP-TIL-002, -005).
/// - A refused range (400) says to shorten the period, with no Retry; any
///   other failure shows the server's words and Retry — on every tab, never
///   as an empty period (REP-TIL-006, -007).
/// - The header's Export writes the sessions as one sheet (REP-TIL-004).
library;

import 'package:dashboard_api/dashboard_api.dart' show TillSessionRow;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show publicBrandProvider;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'tills_lib.dart';
import 'tills_parts.dart';
import 'tills_providers.dart';
import 'tills_sales_tab.dart';
import 'tills_sessions_table.dart';
import 'tills_timing_tab.dart';

/// The route's page (`DashRoute.builder`).
Widget tillsReportPageBuilder(BuildContext context, GoRouterState state) =>
    const TillsReportPage();

/// The tabs (REP-TIL-005), page state; all three share the one read.
const List<DashRouteTab> tillsReportTabs = [
  DashRouteTab(id: 'sessions', labelKey: 'reports.tills.tabSessions'),
  DashRouteTab(id: 'sales', labelKey: 'reports.tills.tabSales'),
  DashRouteTab(id: 'timing', labelKey: 'reports.tills.tabTiming'),
];

class TillsReportPage extends ConsumerStatefulWidget {
  const TillsReportPage({super.key});

  @override
  ConsumerState<TillsReportPage> createState() => _TillsReportPageState();
}

class _TillsReportPageState extends ConsumerState<TillsReportPage> {
  String _tab = tillsReportTabs.first.id;
  bool _exporting = false;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final authz = ref.watch(authzProvider);
    final canSee = authz.can(Cap.tillReadBranch);
    final title = t('reports.tills.title');
    if (authz.ready && !canSee) {
      return Restricted(title: title, who: t('reports.noAccess'));
    }

    final scope = ref.watch(currentScopeProvider);
    final key = tillSessionsKey(scope);
    // Off until the person's rights say they may (the web's `enabled`): a
    // disabled read is neither loading nor failed and has no rows.
    final q = canSee ? ref.watch(tillSessionsProvider(key)) : null;
    final error = q != null && q.hasError ? q.error : null;
    final refused = isRangeRefused(error);
    final load = TillsLoad(
      rows: q?.value ?? const <TillSessionRow>[],
      loading: q != null && q.isLoading && !q.hasValue && !q.hasError,
      loaded: q?.hasValue ?? false,
      error: error == null
          ? null
          : refused
          ? t('reports.tills.rangeRefused')
          : errorMessage(error, t),
      onRetry: error == null || refused
          ? null
          : () => ref.invalidate(tillSessionsProvider(key)),
    );

    final body = switch (_tab) {
      'sales' => TillSalesTab(load: load),
      'timing' => TillTimingTab(load: load),
      _ => TillSessionsTable(load: load),
    };

    return DashPageScaffold(
      title: title,
      // No count until there is one: "0 till sessions" while loading would
      // be a false report (REP-TIL-003).
      subtitleWidget: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Space.xs + DashMetrics.hair,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: DashMetrics.hair + 1),
            child: DashIcon(
              'calendar-range',
              size: IconSize.xs,
              color: c.textSecondary,
            ),
          ),
          Flexible(
            child: Text(
              load.loaded
                  ? t('reports.tills.subtitle', count: load.rows.length)
                  : t('reports.tills.subtitleIdle'),
              style: DashType.body.copyWith(color: c.textSecondary),
            ),
          ),
        ],
      ),
      actions: [
        DashExportButton(
          compact: true,
          loading: _exporting,
          enabled: load.rows.isNotEmpty,
          onExport: () => _export(load.rows, excel: true),
          onExportCsv: () => _export(load.rows, excel: false),
        ),
      ],
      tabs: DashPageTabs<String>(
        tabs: [
          for (final tab in tillsReportTabs)
            DashTab(value: tab.id, label: t(tab.labelKey)),
        ],
        value: _tab,
        onChanged: (v) => setState(() => _tab = v),
      ),
      body: body,
    );
  }

  /// One sheet, "Till sessions": the figures the table shows, 18 columns,
  /// no period line, no totals (REP-TIL-004, -024). Both paths spin.
  Future<void> _export(List<TillSessionRow> rows, {required bool excel}) async {
    final t = ref.read(tProvider);
    final exporter = ref.read(exporterProvider);
    final brand = ref.read(publicBrandProvider).value;
    final logo = brand?.logoUrl?.trim();
    final ownLogo =
        (brand?.customBranding ?? false) && logo != null && logo.isNotEmpty
        ? logo
        : null;
    final title = t('reports.tills.title');
    final config = ExcelConfig(
      filename: 'Madar-$title',
      logoUrl: ownLogo,
      sheets: [
        ExcelSheet<TillSessionRow>(
          name: title,
          title: title,
          rows: rows,
          columns: tillsExportColumns(t),
        ),
      ],
    );
    setState(() => _exporting = true);
    try {
      if (config.sheets.every((s) => s.rows.isEmpty)) {
        DashToast.error(context, const ExportNothing().message(t));
        return;
      }
      if (excel) {
        final toast = DashToast.loading(context, t('excel.generating'));
        final out = await exporter.exportToExcel(config);
        switch (out) {
          case ExportDone(savedTo: null):
            // The save was cancelled: nothing was written.
            toast.dismiss();
          case ExportDone():
            toast.update(DashToastKind.success, out.message(t));
          case ExportFailed():
          case ExportNothing():
            toast.update(DashToastKind.error, out.message(t));
        }
      } else {
        final out = await exporter.exportToCsv(config);
        if (!mounted) return;
        switch (out) {
          case ExportDone(savedTo: null):
            break;
          case ExportDone():
            DashToast.success(context, out.message(t));
          case ExportNothing():
            DashToast.error(context, out.message(t));
          case ExportFailed(:final error):
            DashToast.error(context, errorMessage(error, t));
        }
      }
    } on Object catch (e) {
      if (mounted) DashToast.error(context, errorMessage(e, t));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}

/// The export's columns, in the table's order plus Status.
List<ExcelColumn<TillSessionRow>> tillsExportColumns(Translator t) => [
  ExcelColumn(
    header: t('reports.tills.businessDate'),
    accessor: (r) => r.businessDate,
    type: ExcelColumnType.text,
  ),
  ExcelColumn(
    header: t('reports.tills.branch'),
    accessor: (r) => r.branchName,
    type: ExcelColumnType.text,
  ),
  ExcelColumn(
    header: t('reports.tills.branchRef'),
    accessor: (r) => r.branchCode,
    type: ExcelColumnType.text,
  ),
  ExcelColumn(
    header: t('reports.tills.user'),
    accessor: (r) => r.tellerName,
    type: ExcelColumnType.text,
  ),
  ExcelColumn(
    header: t('reports.tills.openedAt'),
    accessor: (r) => r.openedAt,
    type: ExcelColumnType.dateTime,
  ),
  ExcelColumn(
    header: t('reports.tills.openingAmount'),
    accessor: (r) => r.openingCash,
    type: ExcelColumnType.money,
  ),
  ExcelColumn(
    header: t('reports.tills.netCash'),
    accessor: (r) => r.netCashPayment,
    type: ExcelColumnType.money,
  ),
  ExcelColumn(
    header: t('reports.tills.payIns'),
    accessor: (r) => r.payIns,
    type: ExcelColumnType.money,
  ),
  ExcelColumn(
    header: t('reports.tills.payOuts'),
    accessor: (r) => r.payOuts,
    type: ExcelColumnType.money,
  ),
  ExcelColumn(
    header: t('reports.tills.cashDrops'),
    accessor: (r) => r.cashDrops,
    type: ExcelColumnType.money,
  ),
  ExcelColumn(
    header: t('reports.tills.adjustments'),
    accessor: (r) => r.cashAdjustments,
    type: ExcelColumnType.money,
  ),
  ExcelColumn(
    header: t('reports.tills.closingAmount'),
    accessor: (r) => r.closingCashDeclared,
    type: ExcelColumnType.money,
  ),
  ExcelColumn(
    header: t('reports.tills.expectedAmount'),
    accessor: (r) => r.closingCashSystem,
    type: ExcelColumnType.money,
  ),
  ExcelColumn(
    header: t('reports.tills.variance'),
    accessor: (r) => r.cashDiscrepancy,
    type: ExcelColumnType.money,
  ),
  ExcelColumn(
    header: t('reports.tills.orders'),
    accessor: (r) => r.ordersCount,
    type: ExcelColumnType.integer,
  ),
  ExcelColumn(
    header: t('reports.tills.sales'),
    accessor: (r) => r.netSales,
    type: ExcelColumnType.money,
  ),
  ExcelColumn(
    header: t('reports.tills.closedAt'),
    accessor: (r) => r.closedAt,
    type: ExcelColumnType.dateTime,
  ),
  ExcelColumn(
    header: t('reports.tills.status'),
    accessor: (r) => tillStatusLabel(t, r),
    type: ExcelColumnType.text,
  ),
];
