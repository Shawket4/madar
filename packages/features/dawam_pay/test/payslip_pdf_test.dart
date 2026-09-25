// PAY-10: an approved payslip downloads as a PDF in Arabic or English, with
// the core's lines, a waived line struck through and not counted (AD-8), and
// every label from the core's word table in the PDF's language — never the
// phone's, and never a string outside i18n (AT-13).

import 'dart:convert';

import 'package:feature_dawam_pay/feature_dawam_pay.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staff_core/staff_core.dart';
import 'package:staff_core/testing.dart';

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
    1000,
    const {},
    frozen: true,
  );

  test('a waived line counts for nothing', () {
    expect(slip.deducted, 2500);
    expect(slip.earned, 600000);
  });

  test('every word the PDF uses exists in the core table, in EN and AR', () {
    for (final key in payslipPdfKeys) {
      expect(coreWordTable('en')[key], isNotNull, reason: '$key (en)');
      expect(coreWordTable('ar')[key], isNotNull, reason: '$key (ar)');
      expect(coreWordTable('ar')[key], isNotEmpty, reason: '$key (ar)');
    }
  });

  for (final arabic in [true, false]) {
    test('the PDF builds in ${arabic ? 'Arabic' : 'English'}', () async {
      // The phone is in the OTHER language: the PDF still asks for its own.
      currentLang = arabic ? 'en' : 'ar';
      final asked = <(String, String)>{};
      wordsIn = (lang, key) {
        asked.add((lang, key));
        return coreWord(key, arabic: lang == 'ar');
      };
      addTearDown(() => wordsIn = (lang, key) => key);
      final bytes = await payslipPdf(
        slip: slip,
        person: 'Amal',
        business: 'Cafe',
        arabic: arabic,
        paidWith: PayMethod.bank,
      );
      expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
      expect(bytes.length, greaterThan(2000));
      final lang = arabic ? 'ar' : 'en';
      expect(asked.map((a) => a.$1).toSet(), {lang}, reason: 'one language');
      expect(
        asked.map((a) => a.$2),
        containsAll([
          'staff.pdf_payslip',
          'staff.pdf_period',
          'staff.pdf_net',
          'staff.pdf_waived',
          'staff.pdf_carry',
          'staff.paid_with_method',
          'staff.bank',
        ]),
      );
      expect(
        asked.map((a) => a.$2),
        isNot(contains('staff.pdf_approved')),
        reason: 'paid, so not "approved"',
      );
    });
  }

  test('an unpaid payslip says approved, in the asked language', () async {
    final asked = <String>[];
    wordsIn = (lang, key) {
      asked.add(key);
      return coreWord(key, arabic: lang == 'ar');
    };
    addTearDown(() => wordsIn = (lang, key) => key);
    await payslipPdf(
      slip: slip,
      person: 'Amal',
      business: 'Cafe',
      arabic: true,
    );
    expect(asked, contains('staff.pdf_approved'));
    expect(asked, isNot(contains('staff.paid_with_method')));
  });
}
