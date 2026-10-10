// Driven tests for each Reports tab: its cards, its table, its CSV
// (TEAM-RPT-007/010/011/020/021/030/031/040/041/042/051).
import 'package:dashboard_api/dashboard_api.dart'
    show AttendanceSummary, LabourDay, PayrollHistoryRow;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart'
    show DashFormat, MimeTypes, formatProvider, ltr;
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_team/src/area_seed.dart';
import 'package:dashboard_team/src/shared/team_format.dart';
import 'package:dashboard_team/src/team_reports/team_reports_data.dart';
import 'package:dashboard_team/src/team_reports/team_reports_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'reports_support.dart';

DashFormat _fmt(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(StaffReportsPage)),
).read(formatProvider);

List<R> _rows<R>(WidgetTester tester) =>
    tester.widget<DashDataTable<R>>(find.byType(DashDataTable<R>)).rows;

int _sum<R>(List<R> rows, int Function(R r) f) =>
    rows.fold(0, (a, r) => a + f(r));

/// Taps the [index]th CSV button on the page.
Future<void> _csv(DashHarness h, [int index = 0]) =>
    h.tap(inPage(find.widgetWithText(DashButton, 'CSV')).at(index));

/// Mariam's approved advance, decided this pay period.
void _mariamThisMonth(MockDb db) {
  db[TeamTables.advances].rows.firstWhere(
    (a) => a['id'] == TeamSeedIds.advance('mariam'),
  )['decided_at'] = '2026-10-02T09:00:00Z';
}

void main() {
  testWidgets('TEAM-RPT-010 attendance cards: people, Σ late days, Σ absent '
      'days, overtime in hours', (tester) async {
    final h = await pumpReports(tester);
    final rows = _rows<AttendanceSummary>(tester);
    expect(rows, isNotEmpty);
    expect(inCard('People', find.text('${rows.length}')), findsOneWidget);
    expect(
      inCard('Late', find.text('${_sum(rows, (r) => r.lateDays)}')),
      findsOneWidget,
    );
    expect(
      inCard('Absent', find.text('${_sum(rows, (r) => r.absentDays)}')),
      findsOneWidget,
    );
    final ot = fmtHours('en', _sum(rows, (r) => r.totalOvertimeMinutes));
    expect(inCard('Overtime', find.text(ot)), findsOneWidget);
    expect(h.location.path, reportsPath);
  });

  testWidgets('TEAM-RPT-011 attendance columns; worked, late time and '
      'overtime in hours, never days', (tester) async {
    await pumpReports(tester);
    for (final c in [
      'Name',
      'Present',
      'Late',
      'Absent',
      'On leave',
      'Worked',
      'Late time',
      'Overtime',
    ]) {
      expect(tableText(c.toUpperCase()), findsOneWidget, reason: c);
    }
    final r = _rows<AttendanceSummary>(tester).first;
    expect(tableText(r.employeeName), findsOneWidget);
    final worked = fmtHours('en', r.totalWorkedMinutes);
    expect(worked, isNot(contains('d')));
    expect(tableText(dashFigure(worked)), findsWidgets);
  });

  testWidgets('TEAM-RPT-007 the attendance CSV: attendance.csv, a BOM, the '
      'headers, each row as shown', (tester) async {
    final h = await pumpReports(tester);
    await _csv(h);
    final saved = h.files.saved.last;
    expect(saved.filename, 'attendance.csv');
    expect(saved.mimeType, MimeTypes.csv);
    expect(saved.bytes.take(3), [0xEF, 0xBB, 0xBF], reason: 'a UTF-8 BOM');
    final lines = lastSaved(h).split('\r\n');
    expect(
      lines.first,
      'Name,Present,Late,Absent,On leave,Worked,Late time,Overtime',
    );
    final rows = _rows<AttendanceSummary>(tester);
    expect(lines, hasLength(rows.length + 1), reason: 'every row, not a page');
    final r = rows.first;
    expect(
      lines[1],
      [
        r.employeeName,
        r.presentDays,
        r.lateDays,
        r.absentDays,
        r.leaveDays,
        fmtHours('en', r.totalWorkedMinutes),
        fmtHours('en', r.totalLateMinutes),
        fmtHours('en', r.totalOvertimeMinutes),
      ].join(','),
    );
  });

  testWidgets('TEAM-RPT-020/021 labour vs sales: money cards, the share to '
      'one decimal; rows by day with the branch\'s name', (tester) async {
    final h = await pumpReports(tester);
    await openTab(h, 'Labour vs sales');
    final f = _fmt(tester);
    final rows = _rows<LabourDay>(tester);
    expect(rows, isNotEmpty);
    final sales = _sum(rows, (r) => r.salesPiastres);
    final labour = _sum(rows, (r) => r.labourPiastres);
    expect(inCard('Sales', find.text(f.fmtMoney(sales))), findsOneWidget);
    expect(
      inCard('Labour cost', find.text(f.fmtMoney(labour))),
      findsOneWidget,
    );
    expect(
      inCard('Labour share', find.text(ltr(labourShare(labour, sales)))),
      findsOneWidget,
    );
    for (final c in [
      'Date',
      'Branch',
      'Sales',
      'Labour cost',
      'Labour share',
    ]) {
      expect(tableText(c.toUpperCase()), findsOneWidget, reason: c);
    }
    final r = rows.first;
    expect(tableText(f.fmtDate(r.date)), findsWidgets);
    expect(tableText(dashFigure(labourShareBp(r.labourShareBp))), findsWidgets);
    final branch =
        h.db!['branches'].rows.firstWhere((b) => b['id'] == r.branchId)['name']!
            as String;
    expect(tableText(branch), findsWidgets);
    await _csv(h);
    expect(h.files.saved.last.filename, 'labour-vs-sales.csv');
    expect(
      lastSaved(h).split('\r\n')[1],
      [
        f.fmtDate(r.date),
        branch,
        jsNumber(r.salesPiastres / 100),
        jsNumber(r.labourPiastres / 100),
        labourShareBp(r.labourShareBp),
      ].join(','),
    );
  });

  testWidgets('TEAM-RPT-030/031 overtime & payroll: last month\'s paid '
      'period, its totals, the phase in words; the CSV in pounds', (
    tester,
  ) async {
    final h = await pumpReports(tester);
    await openTab(h, 'Overtime & payroll');
    expect(pageText('Nothing in this period'), findsOneWidget);
    await h.tap(pageText('Last month'));
    final f = _fmt(tester);
    final r = _rows<PayrollHistoryRow>(tester).single;
    expect(r.name, 'September 2026');
    expect(inCard('Net pay', find.text(f.fmtMoney(r.netPiastres))), findsOne);
    expect(inCard('Overtime', find.text(f.fmtMoney(0))), findsOneWidget);
    expect(inCard('Deductions', find.text(f.fmtMoney(0))), findsOneWidget);
    for (final c in [
      'Period',
      'People',
      'Salary',
      'Overtime hours',
      'Overtime',
      'Bonuses',
      'Deductions',
      'Advances collected',
      'Net',
      'Status',
    ]) {
      expect(tableText(c.toUpperCase()), findsOneWidget, reason: c);
    }
    final period = '${f.fmtDate('2026-09-01')} – ${f.fmtDate('2026-09-30')}';
    expect(tableText(period), findsOneWidget);
    expect(tableText('Paid'), findsOneWidget);
    await _csv(h);
    expect(h.files.saved.last.filename, 'payroll-history.csv');
    expect(
      lastSaved(h).split('\r\n')[1],
      '$period,${r.people},${jsNumber(r.basePiastres / 100)},0m,0,0,0,0,'
      '${jsNumber(r.netPiastres / 100)},Paid',
    );
  });

  testWidgets('TEAM-RPT-031 / TEAM-RPT-007 (ar) the phase in the reader\'s '
      'language in the CSV too, with no direction marks', (tester) async {
    final h = await pumpReports(tester, locale: 'ar');
    await openTab(h, h.t('dawam.rPayroll'));
    await h.tap(pageText(h.t('inputs.lastMonth')));
    expect(tableText('مصروف'), findsOneWidget);
    await _csv(h);
    final line = lastSaved(h).split('\r\n')[1];
    expect(line.endsWith(',مصروف'), isTrue, reason: line);
    expect(line, isNot(matches(RegExp('[\u2066-\u2069\u200e\u200f]'))));
  });

  testWidgets('TEAM-RPT-040/041/042 advances: the three totals, salary '
      'advances with what is left, the expense log with where it came from', (
    tester,
  ) async {
    final h = await pumpReports(tester, edit: _mariamThisMonth);
    await openTab(h, 'Salary advances');
    final f = _fmt(tester);
    expect(
      inCard('Salary advances given', find.text(f.fmtMoney(400000))),
      findsOneWidget,
    );
    expect(inCard('Still owed', find.text(f.fmtMoney(300000))), findsOne);
    expect(
      inCard('Expense advances given', find.text(f.fmtMoney(185000))),
      findsOneWidget,
    );
    expect(pageText('Expense advances'), findsOneWidget);
    for (final c in [
      'Amount (EGP)',
      'Monthly installments',
      'Left to pay',
      'What it\'s for',
      'From',
    ]) {
      expect(tableText(c.toUpperCase()), findsWidgets, reason: c);
    }
    expect(tableText('Mariam Fathy'), findsOneWidget);
    expect(tableText('Approved'), findsOneWidget);
    expect(tableText(dashFigure(f.fmtMoney(300000))), findsOneWidget);
    expect(tableText('Karim Adel'), findsOneWidget);
    expect(tableText('Till pay-out'), findsOneWidget);
    expect(tableText('Dina Fouad'), findsOneWidget);
    expect(tableText('From the safe'), findsOneWidget);
    expect(tableText('Reem Mostafa'), findsNothing, reason: 'another org');
    await _csv(h);
    expect(h.files.saved.last.filename, 'salary-advances.csv');
    await _csv(h, 1);
    expect(h.files.saved.last.filename, 'expense-advances.csv');
    expect(
      lastSaved(h).split('\r\n')[1],
      'Karim Adel,${f.fmtDate('2026-10-06')},'
      'Milk and ice from the market (supplier late),Till pay-out,1200',
    );
  });

  testWidgets('TEAM-RPT-041/042 nothing given: "No salary advances" and '
      '"Nothing logged", each CSV disabled', (tester) async {
    final h = await pumpReports(
      tester,
      edit: (db) => db[TeamTables.expenseAdvances].removeWhere((_) => true),
    );
    await openTab(h, 'Salary advances');
    expect(pageText('No salary advances'), findsOneWidget);
    expect(pageText('Nothing logged'), findsOneWidget);
    for (final b in tester.widgetList<DashButton>(
      inPage(find.widgetWithText(DashButton, 'CSV')),
    )) {
      expect(b.onPressed, isNull);
    }
  });

  testWidgets('TEAM-RPT-051 a failed report: the table says so and every '
      'card on the 4 tabs reads "—", never 0 (as the web)', (tester) async {
    final s = reportsServer();
    for (final read in reportReads) {
      s.server.fail('GET', read, MockResponse.error(500, 'boom'), times: null);
    }
    final h = await pumpReports(tester, s: s);
    final f = _fmt(tester);
    void dashes(List<String> labels) {
      final cards = inPage(find.byType(DashStatCard));
      expect(cards, findsNWidgets(labels.length));
      for (final label in labels) {
        expect(inCard(label, find.text('—')), findsOneWidget, reason: label);
      }
      for (final zero in ['0', '0m', f.fmtMoney(0)]) {
        expect(
          find.descendant(of: cards, matching: find.text(zero)),
          findsNothing,
        );
      }
    }

    expect(pageText(h.t('dawam.reportLoadError')), findsOneWidget);
    dashes(['People', 'Late', 'Absent', 'Overtime']);
    await openTab(h, 'Labour vs sales');
    dashes(['Sales', 'Labour cost', 'Labour share']);
    expect(pageText('CSV'), findsNothing);
    await openTab(h, 'Overtime & payroll');
    dashes(['Net pay', 'Overtime', 'Deductions']);
    await openTab(h, 'Salary advances');
    dashes(['Salary advances given', 'Still owed', 'Expense advances given']);
    expect(pageText(h.t('dawam.reportLoadError')), findsNWidgets(2));
  });

  testWidgets('TEAM-RPT-042 an advances failure shows on both tables', (
    tester,
  ) async {
    final s = reportsServer();
    s.server.fail(
      'GET',
      advancesT,
      MockResponse.error(500, 'boom'),
      times: null,
    );
    final h = await pumpReports(tester, s: s);
    await openTab(h, 'Salary advances');
    expect(pageText(h.t('dawam.reportLoadError')), findsNWidgets(2));
  });
}
