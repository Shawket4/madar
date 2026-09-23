/// A frozen payslip as an A4 PDF, in Arabic or English whatever the app's
/// language (PAY-10). The figures and lines are the core's; this only lays
/// them out, in IBM Plex Sans Arabic so both scripts shape correctly.
library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:staff_core/staff_core.dart';

const _words = {
  'title': ('Payslip', 'قسيمة المرتب'),
  'period': ('Period', 'الفترة'),
  'net': ('Net pay', 'الصافي'),
  'waived': ('Waived', 'متنازل عنه'),
  'paid': ('Paid', 'اتدفع'),
  'approved': ('Approved', 'معتمد'),
  'carry': ('Carried to the next payslip', 'مرحّل للقسيمة الجاية'),
};

String _w(String k, bool ar) => ar ? _words[k]!.$2 : _words[k]!.$1;

String _money(int minor, bool ar) {
  final neg = minor < 0;
  final v = (minor.abs() / 100).toStringAsFixed(minor % 100 == 0 ? 0 : 2);
  final grouped = v.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  final s = ar ? '$grouped ج.م' : 'EGP $grouped';
  return neg ? '−$s' : s;
}

String _day(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The PDF bytes.
Future<Uint8List> payslipPdf({
  required Slip slip,
  required String person,
  required String business,
  required bool arabic,
  String? paidWith,
}) async {
  final regular = pw.Font.ttf(
    await rootBundle.load(
      'packages/design_system/assets/fonts/IBMPlexSansArabic-Regular.ttf',
    ),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load(
      'packages/design_system/assets/fonts/IBMPlexSansArabic-Bold.ttf',
    ),
  );
  final dir = arabic ? pw.TextDirection.rtl : pw.TextDirection.ltr;
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
  );
  pw.Widget row(
    String label,
    String value, {
    bool strong = false,
    bool struck = false,
  }) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 4),
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontWeight: strong ? pw.FontWeight.bold : null,
              decoration: struck ? pw.TextDecoration.lineThrough : null,
              color: struck ? PdfColors.grey600 : null,
            ),
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontWeight: strong ? pw.FontWeight.bold : null,
            decoration: struck ? pw.TextDecoration.lineThrough : null,
            color: struck ? PdfColors.grey600 : null,
          ),
        ),
      ],
    ),
  );
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      textDirection: dir,
      margin: const pw.EdgeInsets.all(40),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            business,
            style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            _w('title', arabic),
            style: const pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 16),
          row(
            person,
            paidWith == null
                ? _w('approved', arabic)
                : '${_w('paid', arabic)} · $paidWith',
            strong: true,
          ),
          row(_w('period', arabic), '${_day(slip.start)} – ${_day(slip.end)}'),
          pw.Divider(),
          for (final l in slip.lines)
            row(
              l.waived
                  ? '${arabic ? l.ar : l.en} (${_w('waived', arabic)})'
                  : (arabic ? l.ar : l.en),
              _money(l.amount, arabic),
              struck: l.waived,
            ),
          pw.Divider(),
          row(_w('net', arabic), _money(slip.net, arabic), strong: true),
          if (slip.carryOut > 0)
            row(_w('carry', arabic), _money(-slip.carryOut, arabic)),
        ],
      ),
    ),
  );
  return await doc.save();
}

/// Build it and hand it to the OS share/save sheet.
Future<void> sharePayslipPdf({
  required Slip slip,
  required String person,
  required String business,
  required bool arabic,
  String? paidWith,
}) async {
  final bytes = await payslipPdf(
    slip: slip,
    person: person,
    business: business,
    arabic: arabic,
    paidWith: paidWith,
  );
  await Printing.sharePdf(
    bytes: bytes,
    filename: 'payslip-${_day(slip.start)}-${arabic ? 'ar' : 'en'}.pdf',
  );
}
