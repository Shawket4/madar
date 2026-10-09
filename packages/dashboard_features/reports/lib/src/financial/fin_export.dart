/// Financial's exports (REP-FIN-026…028, 065, 070; REP-ALL-010…014,
/// 025…027): the ledger and the inventory tabs from the rows already
/// loaded (no request, never throttled); Channel re-read with
/// `X-Madar-Export: 1` (counted against the export budget, may 429).
///
/// Excel shows "Gathering data…" then "Exported {{count}} rows" / "Export
/// failed"; CSV writes the first sheet and toasts the count; empty sheets
/// toast "Nothing to export" and write no file. Only Excel spins.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/report_shared.dart';
import 'fin_data.dart';

/// `exportToExcel` with the web's toasts. [sheets] may throw (a re-read):
/// its words are the toast.
Future<void> finExcel(
  BuildContext context,
  WidgetRef ref, {
  required String filename,
  required Future<List<ExcelSheet<Object?>>> Function() sheets,
  String? meta,
}) async {
  final t = ref.read(tProvider);
  final exporter = ref.read(exporterProvider);
  final logo = exportLogoUrl(ref);
  try {
    final s = await sheets();
    if (!context.mounted) return;
    if (s.every((x) => x.rows.isEmpty)) {
      DashToast.error(context, const ExportNothing().message(t));
      return;
    }
    final toast = DashToast.loading(context, t('excel.generating'));
    final outcome = await exporter.exportToExcel(
      ExcelConfig(filename: filename, logoUrl: logo, meta: meta, sheets: s),
    );
    toast.update(
      outcome is ExportDone ? DashToastKind.success : DashToastKind.error,
      outcome.message(t),
    );
  } on Object catch (e) {
    if (context.mounted) DashToast.error(context, errorMessage(e, t));
  }
}

/// `exportToCsv` (first sheet) with the web's toasts.
Future<void> finCsv(
  BuildContext context,
  WidgetRef ref, {
  required String filename,
  required Future<List<ExcelSheet<Object?>>> Function() sheets,
}) async {
  final t = ref.read(tProvider);
  final exporter = ref.read(exporterProvider);
  try {
    final s = await sheets();
    final outcome = await exporter.exportToCsv(
      ExcelConfig(filename: filename, sheets: s),
    );
    if (!context.mounted) return;
    if (outcome is ExportDone) {
      DashToast.success(context, outcome.message(t));
    } else {
      DashToast.error(context, outcome.message(t));
    }
  } on Object catch (e) {
    if (context.mounted) DashToast.error(context, errorMessage(e, t));
  }
}

/// REP-FIN-026/027 the ledger sheet ("Menu profitability"), the filtered
/// rows (CSV ignores the widths).
ExcelSheet<MarginLedgerRow> finLedgerSheet(
  Translator t,
  List<MarginLedgerRow> rows,
) {
  final title = t('insights.profitability.title');
  return ExcelSheet<MarginLedgerRow>(
    name: title,
    title: title,
    rows: rows,
    columns: [
      ExcelColumn(
        header: t('insights.columns.item'),
        accessor: (r) => r.itemName,
        type: ExcelColumnType.text,
        width: 28,
      ),
      ExcelColumn(
        header: t('insights.columns.size'),
        accessor: (r) => r.sizeLabel,
        type: ExcelColumnType.text,
        width: 10,
      ),
      ExcelColumn(
        header: t('insights.class.all'),
        accessor: (r) => r.class_ == null
            ? ''
            : t('insights.class.${r.class_}', defaultValue: r.class_),
        type: ExcelColumnType.text,
        width: 12,
      ),
      ExcelColumn(
        header: t('insights.columns.sold'),
        accessor: (r) => r.quantitySold,
        type: ExcelColumnType.number,
        width: 10,
      ),
      ExcelColumn(
        header: t('insights.columns.revenue'),
        accessor: (r) => r.revenue,
        type: ExcelColumnType.money,
        width: 14,
      ),
      ExcelColumn(
        header: t('insights.columns.cost'),
        accessor: (r) => r.cost,
        type: ExcelColumnType.money,
        width: 14,
      ),
      ExcelColumn(
        header: t('insights.columns.margin'),
        accessor: (r) => r.margin,
        type: ExcelColumnType.money,
        width: 14,
      ),
      ExcelColumn(
        header: t('insights.columns.marginPct'),
        accessor: (r) =>
            r.marginPct == null ? null : (r.marginPct! * 10).round() / 10,
        type: ExcelColumnType.number,
        width: 10,
      ),
      ExcelColumn(
        header: t('insights.columns.flags'),
        accessor: (r) => r.flags.map((f) => f.kind).join(', '),
        type: ExcelColumnType.text,
        width: 30,
      ),
    ],
  );
}

/// REP-FIN-065 the Channel sheet, re-read for the export.
Future<List<ExcelSheet<Object?>>> finChannelSheets(
  DashboardApi api,
  Translator t,
  FinRange k,
) async {
  final rows = await api.reports.branchChannelBreakdown(
    branchId: k.id,
    from: DateTime.parse(k.from),
    to: DateTime.parse(k.to),
  );
  final title = t('analytics.channelDetails');
  return [
    ExcelSheet<ChannelBreakdownRow>(
      name: title,
      title: title,
      totals: true,
      rows: rows,
      columns: [
        ExcelColumn(
          header: t('orders.channel'),
          accessor: (r) => channelLabel(t, r.channel),
          type: ExcelColumnType.text,
          width: 20,
        ),
        ExcelColumn(
          header: t('dashboard.orders'),
          accessor: (r) => r.orders,
          type: ExcelColumnType.integer,
          width: 12,
          total: true,
        ),
        ExcelColumn(
          header: t('dashboard.revenue'),
          accessor: (r) => r.revenue,
          type: ExcelColumnType.money,
          width: 16,
          total: true,
        ),
        ExcelColumn(
          header: t('analytics.aov'),
          accessor: (r) => r.avgOrderValue,
          type: ExcelColumnType.money,
          width: 14,
        ),
      ],
    ),
  ];
}

/// REP-FIN-070 the inventory tab's sheet from what is loaded; its title is
/// also the file name (`Madar-<title>`) and [branch] picks the subtitle.
ExcelSheet<Object?> finInventorySheet(
  Translator t, {
  required String tab,
  required bool branch,
  List<(String, int)> byCategory = const [],
  List<SupplierSpendRow> spend = const [],
  List<MaterialCostTrendRow> trend = const [],
}) {
  final subtitle = t(
    branch ? 'inventory.reports.branch' : 'inventory.reports.org',
  );
  switch (tab) {
    case 'valuation':
      final title = t('inventory.reports.valuation');
      return ExcelSheet<(String, int)>(
        name: title,
        title: title,
        subtitle: subtitle,
        rows: byCategory,
        columns: [
          ExcelColumn(
            header: t('inventory.reports.byCategory'),
            accessor: (r) => r.$1,
            type: ExcelColumnType.text,
            width: 24,
          ),
          ExcelColumn(
            header: t('inventory.reports.totalValue'),
            accessor: (r) => r.$2,
            type: ExcelColumnType.money,
            width: 16,
          ),
        ],
      );
    case 'supplierSpend':
      final title = t('inventory.reports.supplierSpend');
      return ExcelSheet<SupplierSpendRow>(
        name: title,
        title: title,
        subtitle: subtitle,
        rows: spend,
        columns: [
          ExcelColumn(
            header: t('inventory.reports.supplier'),
            accessor: (r) => r.supplierName,
            type: ExcelColumnType.text,
            width: 28,
          ),
          ExcelColumn(
            header: t('inventory.reports.orders'),
            accessor: (r) => r.orders,
            type: ExcelColumnType.number,
            width: 12,
          ),
          ExcelColumn(
            header: t('inventory.reports.totalSpend'),
            accessor: (r) => r.totalSpend,
            type: ExcelColumnType.money,
            width: 16,
          ),
        ],
      );
    default:
      final title = t('reports.financial.tabs.materialCostTrend');
      return ExcelSheet<MaterialCostTrendRow>(
        name: title,
        title: title,
        subtitle: subtitle,
        rows: trend,
        columns: [
          ExcelColumn(
            header: t('inventory.reports.ingredient'),
            accessor: (r) => r.ingredientName,
            type: ExcelColumnType.text,
            width: 26,
          ),
          ExcelColumn(
            header: t('inventory.reports.supplier'),
            accessor: (r) => r.currentSupplierName,
            type: ExcelColumnType.text,
            width: 22,
          ),
          ExcelColumn(
            header: t('inventory.reports.currentCost'),
            accessor: (r) => r.currentCost,
            type: ExcelColumnType.money,
            width: 14,
          ),
          ExcelColumn(
            header: t('inventory.reports.priceStreak'),
            accessor: (r) => '+${_jsNum(r.pctIncrease)}%',
            type: ExcelColumnType.text,
            width: 14,
          ),
          ExcelColumn(
            header: t('inventory.reports.suggestion'),
            accessor: (r) => r.cheaperSupplierName ?? '',
            type: ExcelColumnType.text,
            width: 22,
          ),
        ],
      );
  }
}

/// JavaScript's `${n}` for a number (12.0 → "12").
String _jsNum(num v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';
