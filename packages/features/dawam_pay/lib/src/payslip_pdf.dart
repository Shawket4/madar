/// A frozen payslip as an A4 PDF, in Arabic or English whatever the app's
/// language (PAY-10). The figures and lines are the core's, and so are the
/// words: every label is `wordsIn(lang, key)` from the core's table (AT-13),
/// in the PDF's language, not the phone's. Laid out in IBM Plex Sans Arabic
/// so both scripts shape correctly.
library;

import 'dart:typed_data';

import 'package:design_system/design_system.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:staff_core/staff_core.dart';

/// The core's keys the PDF reads (tests check each exists in EN and AR).
const payslipPdfKeys = [
  'staff.pdf_payslip',
  'staff.pdf_period',
  'staff.pdf_net',
  'staff.pdf_waived',
  'staff.pdf_paid',
  'staff.pdf_approved',
  'staff.pdf_carry',
  'staff.paid_with_method',
  'staff.cash',
  'staff.bank',
  'staff.wallet',
];

String _w(String key, bool ar) => wordsIn(ar ? 'ar' : 'en', key);

/// Money in the PDF's language (piastres in, pounds out — AT-2).
String _money(int minor, bool ar) {
  final s = MadarFormat.money(
    minor.abs(),
    currency: 'EGP',
    locale: ar ? 'ar' : 'en',
  );
  return minor < 0 ? '−$s' : s;
}

String _method(PayMethod m, bool ar) => _w(switch (m) {
  PayMethod.cash => 'staff.cash',
  PayMethod.bank => 'staff.bank',
  PayMethod.wallet => 'staff.wallet',
}, ar);

String _day(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The PDF bytes.
Future<Uint8List> payslipPdf({
  required Slip slip,
  required String person,
  required String business,
  required bool arabic,
  PayMethod? paidWith,
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
            _w('staff.pdf_payslip', arabic),
            style: const pw.TextStyle(
              fontSize: 22,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 16),
          row(
            person,
            paidWith == null
                ? _w('staff.pdf_approved', arabic)
                : _w('staff.paid_with_method', arabic).replaceAll(
                    '{method}',
                    _method(paidWith, arabic),
                  ),
            strong: true,
          ),
          row(
            _w('staff.pdf_period', arabic),
            '${_day(slip.start)} – ${_day(slip.end)}',
          ),
          pw.Divider(),
          for (final l in slip.lines)
            row(
              l.waived
                  ? '${arabic ? l.ar : l.en} (${_w('staff.pdf_waived', arabic)})'
                  : (arabic ? l.ar : l.en),
              _money(l.amount, arabic),
              struck: l.waived,
            ),
          pw.Divider(),
          row(
            _w('staff.pdf_net', arabic),
            _money(slip.net, arabic),
            strong: true,
          ),
          if (slip.carryOut > 0)
            row(_w('staff.pdf_carry', arabic), _money(-slip.carryOut, arabic)),
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
  PayMethod? paidWith,
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
