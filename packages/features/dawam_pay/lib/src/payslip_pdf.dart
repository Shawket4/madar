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

/// The PDF's own words, in the language picked on its button (the core's
/// table, not the app's current language).
String _w(String key, bool ar) => trIn(ar ? 'ar' : 'en', key);

String _money(int minor, bool ar) {
  final neg = minor < 0;
  final v = (minor.abs() / 100).toStringAsFixed(minor % 100 == 0 ? 0 : 2);
  final grouped = v.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  final egp = _w('staff.pdf_egp', ar);
  final s = ar ? '$grouped $egp' : '$egp $grouped';
  return neg ? '−$s' : s;
}

/// How it was paid, in the PDF's language.
String _method(PayMethod m, bool ar) => trIn(ar ? 'ar' : 'en', switch (m) {
  PayMethod.cash => 'staff.cash',
  PayMethod.bank => 'staff.bank',
  PayMethod.wallet => 'staff.wallet',
});

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
                : '${_w('staff.pdf_paid', arabic)} · ${_method(paidWith, arabic)}',
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
            _w('staff.pdf_net_pay', arabic),
            _money(slip.net, arabic),
            strong: true,
          ),
          if (slip.carryOut > 0)
            row(
              _w('staff.pdf_carried', arabic),
              _money(-slip.carryOut, arabic),
            ),
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
