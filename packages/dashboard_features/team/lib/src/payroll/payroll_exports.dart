/// What leaves the Payroll page as a file: the pay lists workbook
/// (TEAM-PAY-008, TEAM-ALL-024), the server's CSV (TEAM-PAY-009) and a
/// payslip as a PDF (TEAM-PAY-036). The web opens a print window for the
/// payslip; here the PDF is built and handed to the file gateway.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show publicBrandProvider;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'money_errors.dart';
import 'payroll_logic.dart';

// ── pay lists ───────────────────────────────────────────────────────────

/// The pay lists workbook (`exportLists`): bank transfers (name, IBAN, net),
/// mobile wallets (name, wallet number, net) and cash envelopes (name, net);
/// each person by their pay method (cash by default), only payslips with a
/// net to hand over.
ExcelConfig payListsConfig({
  required Translator t,
  required DashFormat f,
  required List<SlipRow> rows,
  required Map<String, Employee> people,
  required PayrollPeriod? period,
  String? logoUrl,
}) {
  List<SlipRow> pick(String method) => [
    for (final r in rows)
      if (r.netPiastres > 0 &&
          (people[r.employeeId]?.payMethod ?? 'cash') == method)
        r,
  ];
  List<ExcelColumn<SlipRow>> cols(String? account) => [
    ExcelColumn<SlipRow>(
      header: t('staff.name'),
      accessor: (r) => r.name,
      type: ExcelColumnType.text,
      width: 26,
    ),
    if (account != null)
      ExcelColumn<SlipRow>(
        header: account,
        accessor: (r) => people[r.employeeId]?.payAccount ?? '',
        type: ExcelColumnType.text,
        width: 30,
      ),
    ExcelColumn<SlipRow>(
      header: t('dawam.net'),
      accessor: (r) => r.netPiastres,
      type: ExcelColumnType.money,
      width: 16,
      total: true,
    ),
  ];
  ExcelSheet<Object?> sheet(String name, String title, String method, String? account) =>
      _erase(
        ExcelSheet<SlipRow>(
          name: name,
          title: title,
          rows: pick(method),
          columns: cols(account),
          totals: true,
        ),
      );
  return ExcelConfig(
    filename: 'Madar-Payroll-Transfers',
    logoUrl: logoUrl,
    meta: period == null
        ? ''
        : '${f.fmtDate(period.startDate)} → ${f.fmtDate(period.endDate)}',
    sheets: [
      sheet(t('dawam.pay_bank'), t('dawam.bankList'), 'bank', t('dawam.iban')),
      sheet(
        t('dawam.pay_wallet'),
        t('dawam.walletList'),
        'wallet',
        t('dawam.walletNumber'),
      ),
      sheet(t('dawam.pay_cash'), t('dawam.cashList'), 'cash', null),
    ],
  );
}

/// A typed sheet as the config's `ExcelSheet<Object?>`.
ExcelSheet<Object?> _erase<T>(ExcelSheet<T> s) => ExcelSheet<Object?>(
  name: s.name,
  title: s.title,
  subtitle: s.subtitle,
  totals: s.totals,
  stats: s.stats,
  rows: s.rows,
  columns: [
    for (final c in s.columns)
      ExcelColumn<Object?>(
        header: c.header,
        key: c.key,
        type: c.type,
        width: c.width,
        total: c.total,
        accessor: (r) => c.accessor(r as T),
      ),
  ],
);

/// The shop's own logo on the branding tier, else Madar's (`useExportLogo`).
String? payrollExportLogo(WidgetRef ref) {
  final brand = ref.read(publicBrandProvider).value;
  return brand != null && brand.customBranding ? brand.logoUrl : null;
}

/// `exportToExcel`'s toasts: "Nothing to export" for no rows; otherwise a
/// loading toast that becomes "Exported N rows" or "Export failed".
Future<void> runPayrollExcel(
  BuildContext context,
  DashExporter exporter,
  Translator t,
  ExcelConfig config,
) async {
  if (config.sheets.every((s) => s.rowCount == 0)) {
    DashToast.error(context, const ExportNothing().message(t));
    return;
  }
  final toast = DashToast.loading(context, t('excel.generating'));
  final outcome = await exporter.exportToExcel(config);
  toast.update(
    outcome is ExportDone ? DashToastKind.success : DashToastKind.error,
    outcome.message(t),
  );
  Future<void>.delayed(DashToast.duration, toast.dismiss);
}

/// The server's CSV of an approved month, saved as `payroll-<start>.csv`.
Future<void> savePayrollCsv(
  BuildContext context,
  WidgetRef ref,
  PayrollPeriod period,
) async {
  final t = ref.read(tProvider);
  try {
    final csv = await ref
        .read(apiProvider)
        .staff
        .exportPeriodCsv(id: period.id);
    await saveText(
      ref.read(fileGatewayProvider),
      csv,
      'payroll-${period.startDate}.csv',
    );
  } on Object catch (e) {
    if (context.mounted) {
      DashToast.error(
        context,
        dawamErrorMessage(e, t, ref.read(formatProvider)),
      );
    }
  }
}

// ── the payslip PDF ─────────────────────────────────────────────────────

/// One line of the printed payslip.
class PayslipDocLine {
  const PayslipDocLine({
    required this.label,
    required this.amount,
    this.waived = false,
    this.note,
  });

  final String label;

  /// Signed money, formatted.
  final String amount;
  final bool waived;

  /// "Waived" / "Waived: <why>" on a waived line.
  final String? note;
}

/// The printed payslip (`payslipHtml`'s content): pure, so it is tested
/// without a file.
class PayslipDoc {
  const PayslipDoc({
    required this.company,
    required this.title,
    required this.employeeLabel,
    required this.person,
    required this.periodLabel,
    required this.period,
    required this.lines,
    required this.netLabel,
    required this.net,
    required this.rtl,
    this.carryLabel,
    this.carry,
  });

  final String company;
  final String title;
  final String employeeLabel;
  final String person;
  final String periodLabel;

  /// "d1 – d2", or empty.
  final String period;
  final List<PayslipDocLine> lines;
  final String netLabel;
  final String net;

  /// "Carries to next month" and its signed figure when deductions went
  /// past what was earned.
  final String? carryLabel;
  final String? carry;
  final bool rtl;
}

/// The payslip of [row] as the reader sees it, in their language.
PayslipDoc payslipDoc({
  required Translator t,
  required DashFormat f,
  required SlipRow row,
  required PayrollPeriod? period,
  required String company,
}) {
  final lines = payslipLines(row, f);
  return PayslipDoc(
    company: company,
    title: t('dawam.payslip'),
    employeeLabel: t('staff.employee'),
    person: row.name,
    periodLabel: t('dawam.period'),
    period: period == null
        ? ''
        : '${f.fmtDate(period.startDate)} – ${f.fmtDate(period.endDate)}',
    lines: [
      for (final l in lines)
        PayslipDocLine(
          label: lineLabel(l, t),
          amount: f.fmtMoneySigned(l.amount),
          waived: l.waived,
          note: l.waived ? waivedText(l, t) : null,
        ),
    ],
    netLabel: t('dawam.net'),
    net: f.fmtMoney(row.netPiastres),
    carryLabel: row.carryOutPiastres > 0 ? t('dawam.lineCarryOut') : null,
    carry: row.carryOutPiastres > 0
        ? f.fmtMoneySigned(-row.carryOutPiastres)
        : null,
    rtl: t.isRtl,
  );
}

Future<pw.Font> _font(String name) async => pw.Font.ttf(
  await rootBundle.load('packages/design_system/assets/fonts/$name.ttf'),
);

/// [doc] as an A4 PDF, in the reader's direction, set in IBM Plex Sans
/// Arabic (its Latin too).
Future<List<int>> payslipPdf(PayslipDoc doc) async {
  final base = await _font('IBMPlexSansArabic-Regular');
  final bold = await _font('IBMPlexSansArabic-Bold');
  const ink = PdfColor.fromInt(0xFF111111);
  const muted = PdfColor.fromInt(0xFF666666);
  const struck = PdfColor.fromInt(0xFF888888);
  const rule = PdfColor.fromInt(0xFFDDDDDD);
  final pdf = pw.Document(
    title: '${doc.title} · ${doc.person}',
    theme: pw.ThemeData.withFont(base: base, bold: bold),
  );
  pw.Widget cell(
    String text, {
    bool end = false,
    pw.TextStyle? style,
  }) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 6),
    child: pw.Text(
      text,
      textAlign: end ? pw.TextAlign.right : pw.TextAlign.left,
      style: style,
    ),
  );
  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(18 * PdfPageFormat.mm),
      textDirection: doc.rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            doc.company,
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            doc.title,
            style: pw.TextStyle(fontSize: 15, color: muted),
          ),
          pw.SizedBox(height: 20),
          pw.Table(
            columnWidths: const {
              0: pw.IntrinsicColumnWidth(),
              1: pw.FlexColumnWidth(),
            },
            children: [
              for (final (k, v) in [
                (doc.employeeLabel, doc.person),
                (doc.periodLabel, doc.period),
              ])
                pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsetsDirectional.only(
                        end: 16,
                        bottom: 4,
                      ),
                      child: pw.Text(k, style: const pw.TextStyle(color: muted)),
                    ),
                    pw.Text(v),
                  ],
                ),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Table(
            border: const pw.TableBorder(
              horizontalInside: pw.BorderSide(color: rule),
              bottom: pw.BorderSide(color: rule),
            ),
            columnWidths: const {
              0: pw.FlexColumnWidth(),
              1: pw.IntrinsicColumnWidth(),
            },
            children: [
              for (final l in doc.lines)
                pw.TableRow(
                  children: [
                    cell(
                      l.waived ? '${l.label} (${l.note})' : l.label,
                      style: l.waived
                          ? const pw.TextStyle(
                              color: struck,
                              decoration: pw.TextDecoration.lineThrough,
                            )
                          : null,
                    ),
                    cell(
                      l.amount,
                      end: true,
                      style: l.waived
                          ? const pw.TextStyle(
                              color: struck,
                              decoration: pw.TextDecoration.lineThrough,
                            )
                          : null,
                    ),
                  ],
                ),
            ],
          ),
          pw.Container(height: 2, color: ink),
          pw.Table(
            columnWidths: const {
              0: pw.FlexColumnWidth(),
              1: pw.IntrinsicColumnWidth(),
            },
            children: [
              pw.TableRow(
                children: [
                  cell(
                    doc.netLabel,
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  cell(
                    doc.net,
                    end: true,
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
              if (doc.carryLabel != null)
                pw.TableRow(
                  children: [
                    cell(doc.carryLabel!),
                    cell(doc.carry!, end: true),
                  ],
                ),
            ],
          ),
        ],
      ),
    ),
  );
  return pdf.save();
}

/// The payslip's file name: `payslip-<start>-<name>.pdf`.
String payslipFileName(PayslipDoc doc, PayrollPeriod? period) {
  final who = doc.person.trim().replaceAll(RegExp(r'[\s/\\:*?"<>|]+'), '-');
  final when = period?.startDate;
  return ['payslip', ?when, who].join('-').toLowerCase().replaceAll('--', '-') +
      '.pdf';
}
