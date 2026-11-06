// Printing codes (SET-QR-023, SET-QR-036): only the codes, at a size that
// prints true. An unbranded sheet is the server's images and nothing else (no
// label, no title, no cut line, no frame, not even a font); a branded sheet
// keeps each card's label and its dashed cut line.
import 'package:flutter_test/flutter_test.dart';

import 'qr_support.dart';

List<QrPrintItem> _items(int n, {MockQrLook look = MockQrLook.plain}) => [
  for (var i = 1; i <= n; i++)
    (
      src: qrPngDataUrl('https://s.madar-pos.cloud/t$i', look: look),
      label: 'T$i',
    ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('qrPrintLayout', () {
    test('SET-QR-036 one code prints at its real size', () {
      expect(qrPrintLayout(QrShape.plain, 1), (
        columns: 1,
        cellMm: 70.0,
        cut: false,
        labels: false,
      ));
      expect(qrPrintLayout(QrShape.card, 1), (
        columns: 1,
        cellMm: 105.0,
        cut: false,
        labels: true,
      ));
      expect(qrPrintLayout(QrShape.receipt, 1), (
        columns: 1,
        cellMm: 50.0,
        cut: false,
        labels: true,
      ));
    });

    test('SET-QR-036 a sheet of many fits A4; only a branded one is cut', () {
      expect(qrPrintLayout(QrShape.plain, 9), (
        columns: 3,
        cellMm: 60.0,
        cut: false,
        labels: false,
      ));
      expect(qrPrintLayout(QrShape.card, 9), (
        columns: 2,
        cellMm: 92.0,
        cut: true,
        labels: true,
      ));
      expect(qrPrintLayout(QrShape.receipt, 9), (
        columns: 3,
        cellMm: 50.0,
        cut: true,
        labels: true,
      ));
    });
  });

  group('qrPrintSheetPdf', () {
    test('SET-QR-036 unbranded: the images and nothing else', () async {
      for (final compress in [false, true]) {
        final pdf = await qrPrintSheetPdf(
          _items(9),
          QrShape.plain,
          compress: compress,
        );
        expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
        final facts = pdfFacts(pdf);
        expect(facts.images, 9);
        expect(facts.text, isFalse, reason: 'no label, no title');
        expect(facts.dashed, isFalse, reason: 'no cut line');
        expect(facts.fonts, isFalse, reason: 'not a word on the paper');
      }
    });

    test('SET-QR-036 one unbranded code: one image, nothing else', () async {
      final facts = pdfFacts(
        await qrPrintSheetPdf(_items(1), QrShape.plain, rtl: true),
      );
      expect(facts, (images: 1, text: false, dashed: false, fonts: false));
    });

    test(
      'SET-QR-023 branded: each card with its label and a cut line',
      () async {
        final facts = pdfFacts(
          await qrPrintSheetPdf(
            _items(4, look: MockQrLook.card),
            QrShape.card,
            compress: false,
          ),
        );
        expect(facts.images, 4);
        expect(facts.text, isTrue);
        expect(facts.dashed, isTrue);
        expect(facts.fonts, isTrue);
      },
    );

    test('SET-QR-036 one branded card: labelled, never cut', () async {
      final facts = pdfFacts(
        await qrPrintSheetPdf([
          (src: _items(1, look: MockQrLook.card).single.src, label: null),
        ], QrShape.card),
      );
      expect(facts, (images: 1, text: false, dashed: false, fonts: false));
    });
  });
}
