// AD-6: each bonus and deduction shows with its day, so two lines with the
// same reason ("Late by 55 minutes") can be told apart, on screen and in the
// PDF, in Arabic and English. AV-5 / DW3: a cap the server didn't send shows
// as "—", never a made-up 0.
import 'package:feature_dawam_pay/feature_dawam_pay.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staff_core/staff_core.dart';
import 'package:staff_core/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => words = (key) => coreWord(key, arabic: currentLang == 'ar'));
  tearDown(() => currentLang = 'en');

  final a = Line(
    'd|1',
    'Late by 55 minutes',
    'تأخير 55 دقيقة',
    -12500,
    rule: true,
    date: DateTime(2026, 9, 17),
  );
  final b = Line(
    'd|2',
    'Late by 55 minutes',
    'تأخير 55 دقيقة',
    -12500,
    rule: true,
    date: DateTime(2026, 8, 28),
  );
  final salary = Line('salary', 'Salary', 'المرتب', 650000);

  for (final lang in ['en', 'ar']) {
    test('a dated line names its day · $lang', () {
      currentLang = lang;
      expect(
        lineLabel(a),
        isNot(lineLabel(b)),
        reason: 'same reason, different days',
      );
      expect(lineLabel(a), '${loc(a)} · ${dayMonth(DateTime(2026, 9, 17))}');
      expect(lineLabel(a), contains(lang == 'ar' ? 'تأخير' : 'Late'));
      expect(lineLabel(salary), loc(salary), reason: 'no day on the salary');
      expect(egpOrDash(null), '—');
      expect(egpOrDash(50000), egp(50000));
    });
  }

  // Decision #9: a salary not set is "—" on the slip, never EGP 0.00, and
  // the Payroll tab says how many people have none and blocks approval.
  for (final lang in ['en', 'ar']) {
    test('a salary not set reads "—" and blocks approval · $lang', () {
      currentLang = lang;
      final zero = Line('salary', 'Salary', 'المرتب', 0);
      Slip slip({required bool missing}) => Slip(
        'e4',
        DateTime(2026, 8, 26),
        DateTime(2026, 9, 25),
        [zero, a],
        0,
        0,
        const {},
        salaryMissing: missing,
      );
      expect(slipLineValue(zero, slip(missing: true)), '—');
      expect(
        slipLineValue(a, slip(missing: true)),
        isNull,
        reason: 'only the salary line',
      );
      expect(
        slipLineValue(zero, slip(missing: false)),
        isNull,
        reason: 'a real 0 is shown as 0',
      );
      expect(missingSalaryBanner(0), isNull);
      final banner = missingSalaryBanner(13)!;
      expect(banner, contains('13'));
      expect(
        banner,
        coreWord(
          lang == 'ar'
              ? 'staff.payroll_salary_missing_many'
              : 'staff.payroll_salary_missing',
          arabic: lang == 'ar',
        ).replaceAll('{count}', '13'),
      );
    });

    // FINAL device check (run C2, D9): one person without a salary read
    // "1 people have no salary". One is one, and Arabic's two is its dual.
    test('one person, two people · $lang', () {
      currentLang = lang;
      String word(String key, int n) =>
          coreWord(key, arabic: lang == 'ar').replaceAll('{count}', '$n');
      expect(
        missingSalaryBanner(1),
        lang == 'en'
            ? '1 person has no salary: approval is blocked.'
            : word('staff.payroll_salary_missing_one', 1),
      );
      expect(
        missingSalaryBanner(2),
        lang == 'en'
            ? '2 people have no salary: approval is blocked.'
            : word('staff.payroll_salary_missing_two', 2),
      );
    });
  }

  test('the PDF lines carry the day too', () async {
    final slip = Slip(
      'e1',
      DateTime(2026, 8, 26),
      DateTime(2026, 9, 25),
      [salary, a, b],
      625000,
      0,
      const {},
      frozen: true,
    );
    for (final ar in [true, false]) {
      wordsIn = (lang, key) => coreWord(key, arabic: lang == 'ar');
      final bytes = await payslipPdf(
        slip: slip,
        person: 'Omar',
        business: 'Rue',
        arabic: ar,
      );
      expect(bytes.length, greaterThan(2000));
    }
    expect(
      payslipLineLabel(a, arabic: false),
      'Late by 55 minutes · 2026-09-17',
    );
    expect(payslipLineLabel(b, arabic: true), 'تأخير 55 دقيقة · 2026-08-28');
    expect(payslipLineLabel(salary, arabic: true), 'المرتب');
  });
}
