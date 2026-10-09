// The Employees unit's browser-side rules as pure functions, against the
// web's own cases (`lib/phone_vectors.json`, `dawam/people.test.ts`,
// `dawam/salary-calc.test.ts`).
import 'package:dashboard_api/dashboard_api.dart' show Employee;
import 'package:dashboard_team/src/employees/employees_data.dart';
import 'package:flutter_test/flutter_test.dart';

const _branches = [(id: 'b1', name: 'Zamalek'), (id: 'b2', name: 'Maadi')];

Employee _employee({int? salary, required bool set}) => Employee(
  id: 'e',
  orgId: 'o',
  kind: 'app',
  name: 'A',
  appAccess: true,
  employmentStatus: 'active',
  baseSalaryPiastres: salary,
  salarySet: set,
  payMethod: 'cash',
  onPayroll: true,
  advanceWithinCap: true,
  cantWorkDays: const [],
  branchIds: const [],
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

void main() {
  group('canonicalPhone (the shared phone vectors)', () {
    const valid = [
      ('01001234567', '201001234567'),
      ('0100 123 4567', '201001234567'),
      ('0100-123-4567', '201001234567'),
      ('+201001234567', '201001234567'),
      ('+20 100 123 4567', '201001234567'),
      ('201001234567', '201001234567'),
      ('00201001234567', '201001234567'),
      ('1001234567', '201001234567'),
      ('(010) 0123-4567', '201001234567'),
      ('٠١٠٠١٢٣٤٥٦٧', '201001234567'),
      ('۰۱۰۰۱۲۳۴۵۶۷', '201001234567'),
      ('+2٠١٠٠١٢٣٤٥٦٧', '201001234567'),
      ('01112345678', '201112345678'),
      ('01212345678', '201212345678'),
      ('01512345678', '201512345678'),
      ('0221234567', '20221234567'),
      ('+966512345678', '966512345678'),
      ('00966512345678', '966512345678'),
      ('+14155552671', '14155552671'),
      ('+447911123456', '447911123456'),
      ('0132345678', '20132345678'),
    ];
    const invalid = [
      '',
      '   ',
      'abc',
      '12345',
      '010012345',
      '+20',
      '0000000000000000000',
      '01001234567890123456789012345678901234567890',
      '0100123456',
      '010012345678',
      '+20100123456',
      '1001234',
    ];
    for (final (raw, want) in valid) {
      test('"$raw" → $want', () => expect(canonicalPhone(raw), want));
    }
    for (final raw in invalid) {
      test('"$raw" is not a phone', () => expect(canonicalPhone(raw), isNull));
    }
  });

  test('phoneProblem: short, long, prefix, bad; fine or empty is null', () {
    expect(phoneProblem('0100123'), 'short');
    expect(phoneProblem('010012345678'), 'long');
    expect(phoneProblem('013001'), 'prefix');
    expect(phoneProblem('call me'), 'bad');
    expect(phoneProblem('01001234567'), isNull);
    expect(phoneProblem('  '), isNull);
  });

  test('formatPhoneDisplay and the table cell', () {
    expect(formatPhoneDisplay('01001234567'), '+20 100 123 4567');
    expect(formatPhoneDisplay('+966512345678'), '+966512345678');
    expect(formatPhoneDisplay('nope'), 'nope');
    expect(phoneCell('+201001234567'), '+201001234567');
    expect(phoneCell('201001234567'), '+201001234567');
  });

  test('salaryStateOf: not set, hidden, set', () {
    expect(salaryStateOf(_employee(set: false)), SalaryState.notSet);
    expect(salaryStateOf(_employee(set: true)), SalaryState.hidden);
    expect(salaryStateOf(_employee(salary: 900000, set: true)), SalaryState.set);
  });

  test('readPounds: Arabic digits and separators; above zero only', () {
    expect(readPounds('٩٬٠٠٠٫٥٠'), 900050);
    expect(readPounds('9,000'), 900000);
    expect(readPounds('0'), isNull);
    expect(readPounds(''), isNull);
    expect(readPounds('-5'), isNull);
    expect(readPounds('abc'), isNull);
    expect(egpText(650000), '6500');
    expect(egpText(3125), '31.25');
  });

  group('the salary calculator', () {
    test('roundDiv rounds half away from zero', () {
      expect(roundDiv(5, 2), 3);
      expect(roundDiv(-5, 2), -3);
      expect(roundDiv(4, 3), 1);
      expect(roundDiv(5, 3), 2);
      expect(roundDiv(0, 7), 0);
    });

    test('26 days of 480 minutes: EGP 6,500 is 250 a day, 31.25 an hour', () {
      expect(defaultPayBasis, (workingDays: 26, dayMinutes: 480));
      const want = (monthly: 650000, daily: 25000, hourly: 3125);
      expect(ratesFrom(defaultPayBasis, monthly: 650000), want);
      expect(ratesFrom(defaultPayBasis, daily: 25000), want);
      expect(ratesFrom(defaultPayBasis, hourly: 3125), want);
    });

    test('multiplies before dividing; the rules\' days and hours; half days', () {
      expect(
        ratesFrom(defaultPayBasis, monthly: 1000000),
        (monthly: 1000000, daily: 38462, hourly: 4808),
      );
      expect(
        ratesFrom((workingDays: 30, dayMinutes: 540), monthly: 900000),
        (monthly: 900000, daily: 30000, hourly: 3333),
      );
      expect(
        ratesFrom((workingDays: 26.5, dayMinutes: 480), daily: 20000).monthly,
        530000,
      );
    });

    test('periodOf: calendar months, 26th–25th, across the year', () {
      expect(periodOf('2026-10-16', 1), (
        start: '2026-10-01',
        end: '2026-10-31',
        days: 31,
      ));
      expect(periodOf('2026-10-27', 26), (
        start: '2026-10-26',
        end: '2026-11-25',
        days: 31,
      ));
      expect(periodOf('2026-10-10', 26), (
        start: '2026-09-26',
        end: '2026-10-25',
        days: 30,
      ));
      expect(periodOf('2027-01-05', 26), (
        start: '2026-12-26',
        end: '2027-01-25',
        days: 31,
      ));
    });

    test('firstPay: 310,000 × 16/31 = 160,000; a whole period; half up', () {
      expect(firstPay(310000, '2026-10-16', 1), (
        from: '2026-10-16',
        to: '2026-10-31',
        piastres: 160000,
      ));
      expect(firstPay(650000, '2026-09-26', 26).piastres, 650000);
      expect(firstPay(100001, '2026-10-11', 26).piastres, 50001);
    });
  });

  group('the import', () {
    test('English or Arabic headers, canonical phones, salaries in piastres', () {
      final r = parsePeople([
        ['الاسم', 'رقم الواتساب', 'الفرع', 'الراتب'],
        ['Sara Ahmed', '0100 123 4567', 'zamalek', '9,000'],
        ['Omar', '+20 101 234 5678', 'Maadi', ''],
      ], _branches);
      expect(r.errors, isEmpty);
      expect(
        [
          for (final p in r.people)
            (p.row, p.name, p.phone, p.branchId, p.salaryPiastres),
        ],
        [
          (2, 'Sara Ahmed', '201001234567', 'b1', 900000),
          (3, 'Omar', '201012345678', 'b2', null),
        ],
      );
    });

    test('names every row it cannot read and skips blank ones', () {
      final r = parsePeople([
        ['Name', 'WhatsApp', 'Branch', 'Salary'],
        ['', '01001234567', 'Zamalek', '1'],
        ['A', '12345', 'Zamalek', '1'],
        ['B', '01001234567', 'Nowhere', '1'],
        ['C', '01001234567', 'Zamalek', '-5'],
        ['', '', '', ''],
        ['D', '01001234567', 'Zamalek', '100'],
        ['E', '0100 123 4567', 'Zamalek', '100'],
      ], _branches);
      expect([for (final e in r.errors) (e.row, e.key)], [
        (2, 'importNoName'),
        (3, 'importBadPhone'),
        (4, 'importNoBranch'),
        (5, 'importBadSalary'),
        (8, 'importDuplicatePhone'),
      ]);
      expect([for (final p in r.people) p.name], ['D']);
    });

    test('a salary of 0 is refused; the only branch when none is named', () {
      final r = parsePeople([
        ['Name', 'Phone', 'Salary'],
        ['A', '01001234567', '0'],
        ['B', '01001234568', ''],
      ], [_branches.first]);
      expect([for (final e in r.errors) e.key], ['importBadSalary']);
      expect(r.people.single.branchId, 'b1');
    });

    test('cells read as shown: numbers, dates', () {
      expect(cellText(9000), '9000');
      expect(cellText(9000.0), '9000');
      expect(cellText(8500.5), '8500.5');
      expect(cellText(DateTime.utc(2026, 9)), '2026-09-01');
      expect(cellText(null), '');
      final r = parsePeople([
        ['Name', 'Phone', 'Salary'],
        ['Sara', 1001234567, 9000.0],
      ], [_branches.first]);
      expect(r.people.single.phone, '201001234567');
      expect(r.people.single.salaryPiastres, 900000);
    });

    test('CSV: quoted commas, doubled quotes, CRLF', () {
      expect(readCsv('Name,Salary\r\n"Ahmed, Jr",9000\n'), [
        ['Name', 'Salary'],
        ['Ahmed, Jr', '9000'],
      ]);
      expect(readCsv('a,"say ""hi"""\rb,c'), [
        ['a', 'say "hi"'],
        ['b', 'c'],
      ]);
    });

    test('an .xlsx is a zip', () {
      expect(looksLikeXlsx(const [0x50, 0x4b, 0x03, 0x04]), isTrue);
      expect(looksLikeXlsx('Name,Phone'.codeUnits), isFalse);
    });
  });
}
