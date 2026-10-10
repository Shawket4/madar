// The Reports page's browser-side rules (TEAM-RPT-007/020/021/031), as pure
// functions against hand-computed answers.
import 'package:dashboard_team/src/team_reports/team_reports_data.dart';
import 'package:dashboard_team/src/team_reports/team_reports_page.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Row = ({String name, int pay, String note});

final _cols = <ReportCol<_Row>>[
  ReportCol('name', 'Name', (r) => r.name),
  ReportCol('pay', 'Pay (EGP)', (r) => r.pay, money: true),
  ReportCol('note', 'Note', (r) => r.note),
];

void main() {
  test('TEAM-RPT-007 CSV: headers first, CRLF, money in pounds, RFC 4180 '
      'quoting, no bidi isolates or direction marks', () {
    final csv = reportCsv(_cols, [
      (name: 'Omar Said', pay: 1250050, note: 'plain'),
      (name: 'Laila, "Lulu"', pay: 120000, note: 'two\nlines'),
      (name: '\u2066Hana\u2069', pay: 5, note: '\u200f7h 25m\u200e'),
    ]);
    expect(
      csv,
      'Name,Pay (EGP),Note\r\n'
      'Omar Said,12500.5,plain\r\n'
      '"Laila, ""Lulu""",1200,"two\nlines"\r\n'
      'Hana,0.05,7h 25m',
    );
  });

  test('TEAM-RPT-007 an empty report is its header line only', () {
    expect(reportCsv(_cols, const []), 'Name,Pay (EGP),Note');
  });

  test('jsNumber reads like JavaScript\'s String(n)', () {
    expect(jsNumber(1200), '1200');
    expect(jsNumber(1200.0), '1200');
    expect(jsNumber(12.5), '12.5');
    expect(jsNumber(-0.25), '-0.25');
  });

  test('TEAM-RPT-031 a period\'s phase: generated is approved, paid and '
      'closed are paid, anything else is open', () {
    expect(reportPhase('generated'), 'approved');
    expect(reportPhase('paid'), 'paid');
    expect(reportPhase('closed'), 'paid');
    expect(reportPhase('draft'), 'open');
    expect(reportPhase('open'), 'open');
  });

  test('TEAM-RPT-020 labour share: labour / sales to one decimal; "—" '
      'without sales', () {
    expect(labourShare(2500, 10000), '25.0%');
    expect(labourShare(1, 3), '33.3%');
    expect(labourShare(500, 0), '—');
  });

  test('TEAM-RPT-021 the table\'s share from basis points; "—" when null', () {
    expect(labourShareBp(1234), '12.3%');
    expect(labourShareBp(0), '0.0%');
    expect(labourShareBp(null), '—');
  });

  test('TEAM-RPT-005 tabs in the web\'s order, each by its right', () {
    expect(reportTabs(attendance: true, payroll: true, pos: true), [
      'attendance',
      'labour',
      'payroll',
      'advances',
    ]);
    expect(reportTabs(attendance: true, payroll: false, pos: true), [
      'attendance',
    ]);
    expect(reportTabs(attendance: false, payroll: true, pos: false), [
      'payroll',
      'advances',
    ]);
    expect(reportTabs(attendance: false, payroll: false, pos: true), isEmpty);
  });
}
