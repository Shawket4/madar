/// Printing codes: only the codes, at a size that prints true
/// (`features/qr/print.ts` and the print rules in `globals.css`).
///
/// The web copies the codes into a print-only root; here they become an A4
/// PDF handed to the system print dialog (`printing`). What goes on the paper
/// follows the output: an unbranded code prints as the code alone, the image
/// the server made (it carries its own white quiet zone) and nothing else: no
/// label, no title, no cut line, no frame. A branded sheet keeps what it has
/// always had: each card with its table's label under it and a dashed cut
/// line.
///
/// Sizes are physical. One code prints at its real size: the A6 card 105 mm
/// wide, the unbranded code 70 mm (its size on the card), a receipt code
/// 50 mm. A sheet of many fits A4: unbranded codes three a row at 60 mm,
/// receipt codes three a row at 50 mm, cards two a row at 92 mm.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'qr_output.dart';

/// One code to print.
typedef QrPrintItem = ({
  /// The server's image (`qr_data_url`).
  String src,

  /// Printed under the code on a branded sheet; never on an unbranded one.
  String? label,
});

/// Hands a PDF to the system print dialog (the web's `window.print()`).
// ponytail: a seam tests replace; becomes a print gateway in dashboard_core
// once a second area prints.
@visibleForTesting
Future<void> Function(Uint8List pdf, String name) qrPrintPdf = (pdf, name) =>
    Printing.layoutPdf(onLayout: (_) async => pdf, name: name);

/// The paper layout for [count] codes of [shape]: how many a row, each
/// cell's width, and what goes in it.
typedef QrPrintLayout = ({
  int columns,
  double cellMm,

  /// A dashed cut line round each cell (a branded sheet of many).
  bool cut,

  /// The label under each code (branded only).
  bool labels,
});

/// The print rules (`#qr-print-root` in `globals.css`).
QrPrintLayout qrPrintLayout(QrShape shape, int count) {
  final one = count == 1;
  final branded = shape != QrShape.plain;
  final (columns, cell) = switch (shape) {
    QrShape.plain => one ? (1, 70.0) : (3, 60.0),
    QrShape.card => one ? (1, 105.0) : (2, 92.0),
    QrShape.receipt => one ? (1, 50.0) : (3, 50.0),
  };
  return (
    columns: columns,
    cellMm: cell,
    cut: branded && !one,
    labels: branded,
  );
}

/// The codes in [items] as an A4 PDF laid out by [qrPrintLayout]. [compress]
/// off leaves the page's drawing readable (tests read it).
Future<Uint8List> qrPrintSheetPdf(
  List<QrPrintItem> items,
  QrShape shape, {
  bool rtl = false,
  bool compress = true,
}) async {
  final layout = qrPrintLayout(shape, items.length);
  final labelled =
      layout.labels && items.any((i) => (i.label ?? '').isNotEmpty);
  // A font only when there is a word to print: an unbranded sheet has none.
  final font = labelled
      ? pw.Font.ttf(
          await rootBundle.load(
            'packages/design_system/assets/fonts/IBMPlexSansArabic-Bold.ttf',
          ),
        )
      : null;
  final doc = pw.Document(
    compress: compress,
    theme: font == null ? null : pw.ThemeData.withFont(base: font, bold: font),
  );
  const mm = PdfPageFormat.mm;
  final cell = layout.cellMm * mm;
  const rowGap = 8 * mm;
  const columnGap = 6 * mm;
  const cutPad = 2 * mm;
  const cutLine = 0.3 * mm;

  pw.Widget image(QrPrintItem item, double width) {
    final data = UriData.parse(item.src);
    if (data.mimeType.startsWith('image/svg')) {
      // An SVG has no pixel size to read: the shape's own proportions.
      final aspect = shape == QrShape.card ? 105 / 148 : 1.0;
      return pw.SizedBox(
        width: width,
        height: width / aspect,
        child: pw.SvgImage(svg: utf8.decode(data.contentAsBytes())),
      );
    }
    final img = pw.MemoryImage(data.contentAsBytes());
    final w = img.width ?? 1;
    final h = img.height ?? 1;
    return pw.SizedBox(
      width: width,
      height: width * h / w,
      child: pw.Image(img, fit: pw.BoxFit.fill),
    );
  }

  pw.Widget tile(QrPrintItem item) {
    final inner = layout.cut ? cell - 2 * (cutPad + cutLine) : cell;
    final label = item.label ?? '';
    final body = layout.labels && label.isNotEmpty
        ? pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              image(item, inner),
              pw.SizedBox(height: 2 * mm),
              pw.SizedBox(
                width: inner,
                child: pw.Text(
                  label,
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(
                    fontSize: 14,
                    color: PdfColors.black,
                    lineSpacing: 1.1,
                  ),
                ),
              ),
            ],
          )
        : image(item, inner);
    if (!layout.cut) return pw.SizedBox(width: cell, child: body);
    return pw.Container(
      width: cell,
      padding: const pw.EdgeInsets.all(cutPad),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(
          color: PdfColor.fromHex('#9ca3af'),
          width: cutLine,
          style: pw.BorderStyle.dashed,
        ),
      ),
      child: body,
    );
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(8 * mm),
      textDirection: rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
      build: (context) => [
        for (var i = 0; i < items.length; i += layout.columns)
          pw.Padding(
            padding: pw.EdgeInsets.only(
              bottom: i + layout.columns < items.length ? rowGap : 0,
            ),
            // A row is one block: never split across two pages.
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                for (var j = i; j < i + layout.columns; j++) ...[
                  if (j > i) pw.SizedBox(width: columnGap),
                  if (j < items.length)
                    tile(items[j])
                  else
                    pw.SizedBox(width: cell),
                ],
              ],
            ),
          ),
      ],
    ),
  );
  return doc.save();
}

/// Prints [items] as [shape] under the print dialog's [name].
Future<void> printQrCodes(
  List<QrPrintItem> items,
  QrShape shape, {
  required String name,
  bool rtl = false,
}) async {
  if (items.isEmpty) return;
  await qrPrintPdf(await qrPrintSheetPdf(items, shape, rtl: rtl), name);
}
