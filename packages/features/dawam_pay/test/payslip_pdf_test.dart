// PAY-10: an approved payslip downloads as a PDF in Arabic or English, with
// the core's lines, a waived line struck through and not counted (AD-8).

import 'dart:convert';

import 'package:feature_dawam_pay/feature_dawam_pay.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staff_core/staff_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final slip = Slip(
    'e1',
    DateTime(2026, 8, 26),
    DateTime(2026, 9, 25),
    [
      Line('salary', 'Salary', 'المرتب', 600000),
      Line('d|1', 'Late arrival', 'تأخير', -5000, rule: true)..waived = true,
      Line('d|2', 'Broken cup', 'كوباية مكسورة', -2500),
    ],
    597500,
    0,
    const {},
    frozen: true,
  );

  test('a waived line counts for nothing', () {
    expect(slip.deducted, 2500);
    expect(slip.earned, 600000);
  });

  for (final arabic in [true, false]) {
    test('the PDF builds in ${arabic ? 'Arabic' : 'English'}', () async {
      final bytes = await payslipPdf(
        slip: slip,
        person: 'Amal',
        business: 'Cafe',
        arabic: arabic,
        paidWith: 'Bank',
      );
      expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
      expect(bytes.length, greaterThan(2000));
    });
  }
}
