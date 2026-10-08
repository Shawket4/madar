/// What the Legal exports write (REP-LEG-012, REP-LEG-026): the Tax sheet
/// and the audit workbook — By reason (the tab's own axis), By staff member
/// and, when there is one, History. By kind and Discounted sales stay on
/// screen only (REP-LEG-038).
library;

import 'package:dashboard_api/dashboard_api.dart'
    show AuditBreakdownEntry, AuditReport, DeductionOverrideEvent;
import 'package:dashboard_core/dashboard_core.dart';

import 'legal_words.dart';

/// One Tax figure: its label and its amount in piastres.
typedef TaxFigure = ({String label, int value});

/// The Tax tab's one sheet (`tax:55-64`): named and titled "Tax", the rate
/// note as subtitle, one row per KPI. The web's column headers are
/// hard-coded English ("Figure" / "Amount"); here they go through the
/// tables (divergence REP-LEG-012).
ExcelSheet<TaxFigure> taxSheet(
  Translator t,
  String rateNote,
  List<TaxFigure> figures,
) {
  final title = t('reports.legal.tabs.tax');
  return ExcelSheet<TaxFigure>(
    name: title.length > 31 ? title.substring(0, 31) : title,
    title: title,
    subtitle: rateNote,
    rows: figures,
    columns: [
      ExcelColumn<TaxFigure>(
        header: t('reports.legal.taxColFigure'),
        accessor: (r) => r.label,
        type: ExcelColumnType.text,
        width: 24,
      ),
      ExcelColumn<TaxFigure>(
        header: t('reports.legal.colAmount'),
        accessor: (r) => r.value,
        type: ExcelColumnType.money,
        width: 16,
      ),
    ],
  );
}

/// A breakdown row as exported: its worded label, count and amount.
typedef AuditLine = ({String label, int count, int amount});

/// `auditCols`: Label, Events (integer, totalled) and, unless the tab has
/// no amount, Amount (money) or Points moved (integer), totalled.
List<ExcelColumn<AuditLine>> auditColumns(Translator t, AuditAmount amount) => [
  ExcelColumn<AuditLine>(
    header: t('reports.legal.colLabel'),
    accessor: (r) => r.label,
    type: ExcelColumnType.text,
    width: 28,
  ),
  ExcelColumn<AuditLine>(
    header: t('reports.legal.eventCount'),
    accessor: (r) => r.count,
    type: ExcelColumnType.integer,
    width: 12,
    total: true,
  ),
  if (amount != AuditAmount.none)
    ExcelColumn<AuditLine>(
      header: amount == AuditAmount.points
          ? t('reports.legal.eventPoints')
          : t('reports.legal.colAmount'),
      accessor: (r) => r.amount,
      type: amount == AuditAmount.points
          ? ExcelColumnType.integer
          : ExcelColumnType.money,
      width: 16,
      total: true,
    ),
];

/// The history's columns (`historyCols`, `aud:297-308`).
List<ExcelColumn<DeductionOverrideEvent>> historyColumns(Translator t) => [
  ExcelColumn<DeductionOverrideEvent>(
    header: t('reports.legal.historyWhen'),
    accessor: (e) => e.at,
    type: ExcelColumnType.dateTime,
    width: 22,
  ),
  ExcelColumn<DeductionOverrideEvent>(
    header: t('staff.employee'),
    accessor: (e) => e.employeeName ?? '',
    type: ExcelColumnType.text,
    width: 24,
  ),
  ExcelColumn<DeductionOverrideEvent>(
    header: t('reports.legal.historyAction'),
    accessor: (e) => historyActionText(t, e.action),
    type: ExcelColumnType.text,
    width: 16,
  ),
  ExcelColumn<DeductionOverrideEvent>(
    header: t('reports.legal.historyBy'),
    accessor: (e) => e.actorName ?? '',
    type: ExcelColumnType.text,
    width: 20,
  ),
  ExcelColumn<DeductionOverrideEvent>(
    header: t('staff.reason'),
    accessor: (e) => e.reason ?? '',
    type: ExcelColumnType.text,
    width: 30,
  ),
  ExcelColumn<DeductionOverrideEvent>(
    header: t('reports.legal.historyBefore'),
    accessor: (e) => e.amountBeforePiastres,
    type: ExcelColumnType.money,
    width: 14,
  ),
  ExcelColumn<DeductionOverrideEvent>(
    header: t('reports.legal.historyAfter'),
    accessor: (e) => e.amountAfterPiastres,
    type: ExcelColumnType.money,
    width: 14,
  ),
];

String _sheetName(String s) => s.length > 31 ? s.substring(0, 31) : s;

AuditLine _line(AuditBreakdownEntry e, String label) =>
    (label: label, count: e.count, amount: e.amountMinor);

/// The audit workbook (`buildSheets`, `aud:98-126`). [reasonLabel] names the
/// first sheet (the tab's second axis), [exportTitle] titles every sheet.
List<ExcelSheet<Object?>> auditSheets({
  required Translator t,
  required AuditReport report,
  required AuditAmount amount,
  required String reasonLabel,
  required String exportTitle,
}) {
  final cols = auditColumns(t, amount);
  final amountLabel = amount == AuditAmount.points
      ? t('reports.legal.eventPoints')
      : t('reports.legal.eventAmount');
  final byIssuer = t('reports.legal.byIssuer');
  final history = report.history ?? const <DeductionOverrideEvent>[];
  return [
    ExcelSheet<AuditLine>(
      name: _sheetName(reasonLabel),
      title: exportTitle,
      subtitle: reasonLabel,
      rows: [for (final r in report.byReason) _line(r, auditReasonText(t, r))],
      columns: cols,
      stats: [
        ExcelStat(
          label: t('reports.legal.eventCount'),
          value: report.totalCount,
          type: 'number',
        ),
        // A money pill is written in pounds, as the money columns are (the
        // web writes piastres under a pounds format: divergence REP-LEG-026).
        if (amount != AuditAmount.none)
          ExcelStat(
            label: amountLabel,
            value: amount == AuditAmount.points
                ? report.totalAmountMinor
                : report.totalAmountMinor / 100,
            type: amount == AuditAmount.points ? 'number' : 'money',
          ),
      ],
    ),
    ExcelSheet<AuditLine>(
      name: _sheetName(byIssuer),
      title: exportTitle,
      subtitle: byIssuer,
      rows: [for (final r in report.byIssuer) _line(r, r.label)],
      columns: cols,
    ),
    if (history.isNotEmpty)
      ExcelSheet<DeductionOverrideEvent>(
        name: _sheetName(t('reports.legal.history')),
        title: exportTitle,
        subtitle: t('reports.legal.history'),
        rows: history,
        columns: historyColumns(t),
      ),
  ];
}
