// FINAL device check (run C2, D9): the owner's Payroll read "1 people have
// no salary". A phrase with a count picks the form its number takes: English
// one / other; Arabic one, two, 3–10, 11–99 and the rest (CLDR). The forms
// are the core's words, `<key>_one`, `_two`, `_few`, `_many` beside `<key>`.
import 'package:flutter_test/flutter_test.dart';
import 'package:staff_core/staff_core.dart';
import 'package:staff_core/testing.dart';

/// Every phrase with a count on Payroll, Pay, Requests and Approvals.
const _counted = [
  'staff.payroll_salary_missing',
  'staff.unsettled_draft',
  'staff.shortfall_list',
  'staff.installment_s',
  'staff.installment_s_left',
  'staff.months',
  'staff.installments_count',
];

void main() {
  setUp(() => words = (key) => coreWord(key, arabic: currentLang == 'ar'));
  tearDown(() => currentLang = 'ar');

  test("a count's plural category, English and Arabic", () {
    expect(
      [
        for (final n in [0, 1, 2, 5, 11]) pluralOf(n, 'en'),
      ],
      ['other', 'one', 'other', 'other', 'other'],
    );
    expect(
      [
        for (final n in [0, 1, 2, 3, 10, 11, 99, 100, 101, 102, 103, 111, 200])
          pluralOf(n, 'ar'),
      ],
      [
        'zero',
        'one',
        'two',
        'few',
        'few',
        'many',
        'many',
        'other',
        'other',
        'other',
        'few',
        'many',
        'other',
      ],
    );
  });

  test('English: one person, two people', () {
    currentLang = 'en';
    String s(int n) => trCount('staff.payroll_salary_missing', n, {'count': n});
    expect(s(1), '1 person has no salary: approval is blocked.');
    expect(s(2), '2 people have no salary: approval is blocked.');
    expect(s(13), '13 people have no salary: approval is blocked.');
  });

  test('Arabic: its own words for 1, 2, 3–10, 11–99 and 100', () {
    currentLang = 'ar';
    String s(int n) => trCount('staff.payroll_salary_missing', n, {'count': n});
    String form(String suffix, int n) => coreWord(
      'staff.payroll_salary_missing$suffix',
      arabic: true,
    ).replaceAll('{count}', '$n');
    expect(s(1), form('_one', 1));
    expect(s(2), form('_two', 2));
    expect(s(3), form('_few', 3));
    expect(s(10), form('_few', 10));
    expect(s(11), form('_many', 11));
    expect(s(100), form('', 100));
    expect({s(1), s(2), s(3), s(11)}, hasLength(4), reason: 'four forms');
    expect(s(3), contains('3'));
    expect(s(13), contains('13'));
  });

  test('a phrase with no forms reads as it is', () {
    currentLang = 'en';
    expect(trCount('staff.people', 1), tr('staff.people'));
    currentLang = 'ar';
    expect(trCount('staff.people', 2), tr('staff.people'));
  });

  test('every counted phrase has its forms in both languages', () {
    final en = coreWordTable('en');
    final ar = coreWordTable('ar');
    final missing = [
      for (final k in _counted) ...[
        for (final f in [k, '${k}_one'])
          if (en[f] == null) '$f (en)',
        for (final f in [k, '${k}_one', '${k}_two', '${k}_few', '${k}_many'])
          if (ar[f] == null) '$f (ar)',
      ],
    ];
    expect(missing, isEmpty);
    // "payslip(s)", "installment(s)": the form is chosen, never hedged.
    for (final k in _counted) {
      expect(en[k], isNot(contains('(s)')), reason: k);
      expect(en['${k}_one'], isNot(contains('(s)')), reason: k);
    }
  });
}
