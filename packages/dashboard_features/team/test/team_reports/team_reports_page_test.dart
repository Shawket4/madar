// Driven tests for /staff/reports (TEAM-RPT rows + the TEAM-ALL rows the page
// carries), through the real shell on the mock server.
import 'dart:ui' show AppLifecycleState;

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_team/src/area_seed.dart';
import 'package:flutter/widgets.dart' show Text;
import 'package:flutter_test/flutter_test.dart';

import 'reports_support.dart';

Map<String, List<String>> _q(String from, String to, [String? branch]) => {
  'from': [from],
  'to': [to],
  'branch_id': ?(branch == null ? null : [branch]),
};

/// Opens the From field's calendar and picks [day] of the month shown.
Future<void> _pickFrom(DashHarness h, String day) async {
  await h.tap(inPage(find.byType(DashDateField)).first);
  await h.tap(find.text(day).hitTestable().last);
}

void main() {
  testWidgets('TEAM-RPT-001 / TEAM-ALL-007 no attendance or payroll rights: '
      'the page is refused with its own words and asks for nothing', (
    tester,
  ) async {
    final h = await pumpReports(tester, persona: Persona.limited);
    expect(pageText(h.t('common.restrictedTitle')), findsOneWidget);
    expect(pageText(h.t('dawam.reportsNoAccess')), findsOneWidget);
    expect(reportCalls(h), 0);
    expect(gets(h, settingsT), isEmpty);
  });

  testWidgets('TEAM-RPT-002 header: title, the subtitle and Refresh', (
    tester,
  ) async {
    final h = await pumpReports(tester);
    expect(pageText('Reports'), findsOneWidget);
    expect(pageText(h.t('dawamOps.reportsSubtitle')), findsOneWidget);
    expect(inPage(find.bySemanticsLabel('Refresh')), findsOneWidget);
  });

  testWidgets('TEAM-RPT-003 opens on this pay period from the business\'s '
      'period start day; each quick range asks for its own dates', (
    tester,
  ) async {
    final h = await pumpReports(
      tester,
      edit: (db) => db['attendance_settings'].rows
          .where((r) => r['org_id'] == SeedIds.sabahOrg)
          .forEach((r) => r['period_start_day'] = 26),
    );
    // 8 Oct with a 26th start: 26 Sept – 25 Oct.
    expect(gets(h, summaryT).last.query, _q('2026-09-26', '2026-10-25'));
    for (final (label, from, to) in [
      ('Last pay period', '2026-08-26', '2026-09-25'),
      ('This month', '2026-10-01', '2026-10-31'),
      ('Last month', '2026-09-01', '2026-09-30'),
      ('This week', '2026-10-03', '2026-10-09'),
    ]) {
      await h.tap(pageText(label));
      expect(gets(h, summaryT).last.query, _q(from, to), reason: label);
    }
    // Back on a range already asked for: answered from the cache.
    final asked = gets(h, summaryT).length;
    await h.tap(pageText('This pay period'));
    expect(gets(h, summaryT).length, asked);
    expect(pageText('From'), findsOneWidget);
    expect(pageText('To'), findsOneWidget);
  });

  testWidgets('TEAM-RPT-003 / TEAM-ALL-018 the scope bar\'s branch is sent; '
      'All branches sends none', (tester) async {
    final h = await pumpReports(tester);
    expect(gets(h, summaryT).single.query, _q(thisPeriod.from, thisPeriod.to));
    await h.tap(find.text('All branches'));
    await h.tap(find.text('Zamalek').hitTestable());
    expect(
      gets(h, summaryT).last.query,
      _q(thisPeriod.from, thisPeriod.to, SeedIds.zamalek),
    );
  });

  testWidgets('TEAM-RPT-004 an end before the start: "The end is before the '
      'start", no tab content, no request', (tester) async {
    final h = await pumpReports(tester);
    await h.tap(pageText('This week'));
    final before = reportCalls(h);
    await _pickFrom(h, '14');
    expect(pageText(h.t('dawamOps.rangeBackwards')), findsOneWidget);
    expect(pageText(h.t('dawamOps.rangeBackwardsHint')), findsOneWidget);
    expect(inPage(tables), findsNothing);
    expect(inPage(find.byType(DashStatCard)), findsNothing);
    expect(reportCalls(h), before);
    // The tabs stay, and a quick range puts it right.
    expect(pageText('Attendance & discipline'), findsOneWidget);
    await h.tap(pageText('This pay period'));
    expect(pageText(h.t('dawamOps.rangeBackwards')), findsNothing);
    expect(inPage(tables), findsOneWidget);
  });

  testWidgets('TEAM-RPT-005 the owner sees four tabs in order, opens on the '
      'first, and only the open tab is asked for', (tester) async {
    final h = await pumpReports(tester);
    final labels = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(DashPageTabs<String>),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data)
        .toList();
    expect(labels, [
      'Attendance & discipline',
      'Labour vs sales',
      'Overtime & payroll',
      'Salary advances',
    ]);
    expect(gets(h, summaryT), hasLength(1));
    expect(gets(h, labourT), isEmpty);
    expect(gets(h, historyT), isEmpty);
    expect(gets(h, advancesT), isEmpty);
    await openTab(h, 'Overtime & payroll');
    expect(gets(h, historyT), hasLength(1));
    expect(gets(h, labourT), isEmpty);
    expect(gets(h, advancesT), isEmpty);
  });

  testWidgets('TEAM-RPT-005 attendance rights only: one tab, no payroll '
      'tabs, nothing of payroll asked', (tester) async {
    final h = await pumpReports(tester, persona: Persona.manager);
    expect(pageText('Attendance & discipline'), findsOneWidget);
    expect(pageText('Overtime & payroll'), findsNothing);
    expect(pageText('Labour vs sales'), findsNothing);
    expect(pageText('Salary advances'), findsNothing);
    expect(gets(h, summaryT), hasLength(1));
    expect(gets(h, historyT), isEmpty);
  });

  testWidgets('TEAM-RPT-005 without POS there is no labour tab; payroll '
      'rights only open on Overtime & payroll', (tester) async {
    await pumpReports(tester, persona: Persona.dawamOnly);
    expect(pageText('Labour vs sales'), findsNothing);
    expect(pageText('Attendance & discipline'), findsOneWidget);
    expect(pageText('Overtime & payroll'), findsOneWidget);
    expect(pageText('Salary advances'), findsWidgets);

    final s = reportsServer();
    answerAuthz(s.server, const ['hr.payroll.read']);
    final h2 = await pumpReports(tester, s: s);
    expect(pageText('Attendance & discipline'), findsNothing);
    expect(gets(h2, summaryT), isEmpty);
    expect(gets(h2, labourT), hasLength(1));
  });

  testWidgets('TEAM-RPT-006 a refused report says so with Retry, the CSV '
      'button goes with it; Retry asks again', (tester) async {
    final s = reportsServer();
    s.server.fail(
      'GET',
      summaryT,
      MockResponse.denied('hr.attendance.read'),
      times: 1,
    );
    final h = await pumpReports(tester, s: s);
    expect(pageText(h.t('dawam.reportLoadError')), findsOneWidget);
    expect(pageText(h.t('errors.unauthorized')), findsOneWidget);
    expect(pageText('CSV'), findsNothing);
    await h.tap(inPage(find.widgetWithText(DashButton, 'Retry')));
    expect(gets(h, summaryT), hasLength(2));
    expect(pageText(h.t('dawam.reportLoadError')), findsNothing);
    expect(pageText('CSV'), findsOneWidget);
  });

  testWidgets('TEAM-RPT-006 loading: skeleton cards and rows, the CSV '
      'button disabled; never "Nothing in this period"', (tester) async {
    final s = reportsServer();
    final gate = s.server.hold('GET', summaryT);
    final h = await pumpReports(tester, s: s);
    expect(pageText('Nothing in this period'), findsNothing);
    final csv = tester.widget<DashButton>(
      inPage(find.widgetWithText(DashButton, 'CSV')),
    );
    expect(csv.onPressed, isNull);
    expect(
      tester
          .widgetList<DashStatCard>(inPage(find.byType(DashStatCard)))
          .every((c) => c.loading),
      isTrue,
    );
    expect(tester.widget<DashDataTable>(inPage(tables)).loading, isTrue);
    gate.release();
    await h.settle();
    expect(tester.widget<DashDataTable>(inPage(tables)).loading, isFalse);
  });

  testWidgets('TEAM-RPT-006 / TEAM-RPT-011 empty: "Nothing in this period" '
      'and the CSV button disabled', (tester) async {
    await pumpReports(
      tester,
      edit: (db) => db[TeamTables.attendance].removeWhere((_) => true),
    );
    expect(pageText('Nothing in this period'), findsOneWidget);
    final csv = tester.widget<DashButton>(
      inPage(find.widgetWithText(DashButton, 'CSV')),
    );
    expect(csv.onPressed, isNull);
    expect(inCard('People', find.text('0')), findsOneWidget);
  });

  testWidgets('TEAM-ALL-008 Refresh asks the open report again and spins '
      'while it is in flight', (tester) async {
    final h = await pumpReports(tester);
    final before = gets(h, summaryT).length;
    final gate = h.server.hold('GET', summaryT);
    await h.tap(inPage(find.bySemanticsLabel('Refresh')));
    expect(inPage(find.bySemanticsLabel('Refreshing…')), findsOneWidget);
    gate.release();
    await h.settle();
    expect(inPage(find.bySemanticsLabel('Refresh')), findsOneWidget);
    expect(gets(h, summaryT).length, before + 1);
    expect(gets(h, labourT), isEmpty, reason: 'only what the page shows');
  });

  testWidgets('TEAM-ALL-009 back to the app after 30 s asks the open report '
      'again; sooner does nothing', (tester) async {
    final h = await pumpReports(tester);
    final before = gets(h, summaryT).length;
    h.server.clock.advance(const Duration(seconds: 10));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await h.settle();
    expect(gets(h, summaryT).length, before);
    h.server.clock.advance(const Duration(seconds: 30));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await h.settle();
    expect(gets(h, summaryT).length, before + 1);
  });

  testWidgets('TEAM-ALL-010/022 a failed refresh replaces the rows with the '
      'report\'s error, the cards keep their figures, one toast says it', (
    tester,
  ) async {
    final h = await pumpReports(tester);
    final people = find
        .descendant(of: card('People'), matching: find.byType(Text))
        .evaluate()
        .map((e) => (e.widget as Text).data)
        .whereType<String>()
        .toList();
    h.server.fail(
      'GET',
      summaryT,
      MockResponse.error(429, 'Too many requests'),
      times: null,
    );
    await h.tap(inPage(find.bySemanticsLabel('Refresh')));
    expect(inPage(tables), findsNothing);
    expect(pageText(h.t('dawam.reportLoadError')), findsOneWidget);
    for (final w in people) {
      expect(inCard('People', find.text(w)), findsWidgets);
    }
    await h.expectToast(h.t('errors.tooManyRequests'));
  });

  testWidgets('TEAM-ALL-020 / TEAM-RPT-051 pages of 10, no search box and no '
      'Columns menu', (tester) async {
    final h = await pumpReports(tester);
    final table = tester.widget<DashDataTable>(inPage(tables));
    expect(table.pageSize, 10);
    expect(table.hideViewOptions, isTrue);
    expect(table.searchPlaceholder, isNull);
    expect(pageText('Columns'), findsNothing);
    expect(table.rows.length, greaterThan(10));
    final pages = (table.rows.length / 10).ceil();
    expect(pageText('Page 1 of $pages'), findsOneWidget);
    await h.tap(inPage(find.bySemanticsLabel('Next')));
    expect(pageText('Page 2 of $pages'), findsOneWidget);
    await h.tap(inPage(find.bySemanticsLabel('Previous')));
    expect(pageText('Page 1 of $pages'), findsOneWidget);
  });

  testWidgets('TEAM-RPT-050 / TEAM-ALL-020 phone: stat cards two across, '
      'rows become cards titled by the first column', (tester) async {
    await pumpReports(tester, size: DashSize.phone);
    final cards = inPage(find.byType(DashStatCard));
    final ys = {
      for (final e in cards.evaluate())
        tester.getTopLeft(find.byWidget(e.widget)).dy,
    };
    expect(ys, hasLength(2), reason: '4 cards, 2 rows of 2');
    final table = tester.widget<DashDataTable>(inPage(tables));
    final first = table.rows.first as dynamic;
    expect(pageText(first.employeeName as String), findsOneWidget);
    expect(pageText('Name'), findsNothing, reason: 'no header row on cards');
  });
}
