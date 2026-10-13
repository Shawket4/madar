// The Attendance page (`/staff/attendance`) driven through the real shell on
// the mock server: one test per inventory row (TEAM-ATT-001…022, 034, 038,
// 039 and the area-wide TEAM-ALL rows this page carries), with its refusal,
// loading, empty and error states. The dialogs are in
// attendance_dialogs_test.dart, the export in attendance_export_test.dart.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart'
    show DashFormat, orgIdProvider, transportProvider, webRetry;
import 'package:dashboard_core/shell.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_team/src/area_seed.dart';
import 'package:dashboard_team/src/attendance/attendance_dialogs.dart';
import 'package:dashboard_team/src/attendance/attendance_providers.dart';
import 'package:dashboard_team/src/shared/team_format.dart';
import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'attendance_support.dart';

/// Cards by label.
Finder card(String label) => inPage(
  find.ancestor(of: find.text(label), matching: find.byType(DashStatCard)),
);

Finder inCard(String label, Finder f) =>
    find.descendant(of: card(label), matching: f);

/// The table row holding [text] (desktop: the row's `Row`).
Finder rowOf(String text) =>
    find.ancestor(of: tableText(text).first, matching: find.byType(Row)).first;

/// The date range field.
Finder range(String s) => find.descendant(
  of: inPage(find.byType(DashDateRangeField)),
  matching: find.text(s),
);

Finder inRow(String name, Finder f) =>
    find.descendant(of: rowOf(name), matching: f);

final Finder correct = inPage(find.bySemanticsLabel('Correct'));

/// Six records the cell tests read: Laila late (09:00 start, left early),
/// Omar's manager punch with reasons, Hana corrected/offline, Youssef
/// auto-closed, Nada… (Ali) the till PIN, Adham's plain phone punch.
List<MockRow> cellRows() => [
  recordRow(
    id: 'r-laila',
    employeeKey: 'laila',
    date: day(-1),
    status: 'late',
    workShiftName: 'Morning',
    inAt: cairo(day(-1), '09:02'),
    outAt: cairo(day(-1), '17:00'),
    inMethod: 'mobile_gps',
    outMethod: 'mobile_gps',
    late: 2,
    early: 30,
    worked: 478,
    scheduledStart: cairo(day(-1), '09:00'),
    scheduledEnd: cairo(day(-1), '17:30'),
    distance: 14.2,
  ),
  recordRow(
    id: 'r-omar',
    employeeKey: 'omar',
    date: day(-1),
    branchId: SeedIds.newCairo,
    inAt: cairo(day(-1), '09:00'),
    outAt: cairo(day(-1), '17:00'),
    inMethod: 'manager',
    outMethod: 'manager',
    worked: 480,
    overtime: 45,
    punchReason: 'Phone died',
    outReason: 'Forgot to clock out',
  ),
  recordRow(
    id: 'r-hana',
    employeeKey: 'hana',
    date: day(-2),
    branchId: SeedIds.maadi,
    inAt: cairo(day(-2), '09:00'),
    outAt: cairo(day(-2), '17:00'),
    inMethod: 'correction',
    outMethod: 'offline',
    worked: 480,
  ),
  recordRow(
    id: 'r-youssef',
    employeeKey: 'youssef',
    date: day(-2),
    inAt: cairo(day(-2), '09:00'),
    outAt: cairo(day(-2), '17:00'),
    inMethod: 'mobile_gps',
    outMethod: 'auto',
    worked: 480,
  ),
  recordRow(
    id: 'r-ali',
    employeeKey: 'ali',
    date: day(-3),
    branchId: SeedIds.heliopolis,
    inAt: cairo(day(-3), '09:00'),
    outAt: cairo(day(-3), '17:00'),
    inMethod: 'mobile_gps',
    outMethod: 'till',
    worked: 480,
  ),
  recordRow(
    id: 'r-adham',
    employeeKey: 'adham',
    date: day(-3),
    status: 'on_leave',
    workShiftName: 'Evening',
  ),
];

void main() {
  testWidgets('TEAM-ATT-001 header: title, words, Refresh, Export Excel and '
      'Add record', (tester) async {
    final h = await pumpAttendance(tester);
    expect(pageText('Attendance'), findsOneWidget);
    expect(pageText(h.t('staff.attendanceSubtitle')), findsOneWidget);
    expect(inPage(find.bySemanticsLabel('Refresh')), findsOneWidget);
    expect(pageText('Export Excel'), findsOneWidget);
    expect(pageText('Add record'), findsOneWidget);
  });

  testWidgets('TEAM-ATT-002 the last 7 days by default; records and summary '
      'ask the same window; a new end refetches', (tester) async {
    final h = await pumpAttendance(tester);
    expect(pageText('From'), findsOneWidget);
    expect(pageText('To'), findsOneWidget);
    expect(range('02 Oct 2026'), findsOneWidget);
    expect(range('08 Oct 2026'), findsOneWidget);
    final window = {
      'from': [day(-6)],
      'to': [day()],
    };
    expect(pageListCalls(h).single.query, window);
    expect(h.server.callsTo(summaryT).single.query, window);
    await h.tap(range('08 Oct 2026'));
    await h.tap(find.text('5').hitTestable().last);
    expect(pageListCalls(h).last.query, {
      'from': [day(-6)],
      'to': ['2026-10-05'],
    });
    expect(h.server.callsTo(summaryT).last.query['to'], ['2026-10-05']);
  });

  testWidgets('TEAM-ATT-002 an end before the start says so, and the server\'s '
      'refusal shows in the table', (tester) async {
    final h = await pumpAttendance(tester);
    await h.tap(range('02 Oct 2026'));
    await h.tap(find.text('7').hitTestable().last);
    await h.tap(range('08 Oct 2026'));
    await h.tap(find.text('5').hitTestable().last);
    expect(pageText('The end is before the start.'), findsOneWidget);
    expect(pageListCalls(h).last.status, 400);
    expect(tableText(h.t('errors.codes.RANGE_BACKWARDS')), findsOneWidget);
  });

  testWidgets('TEAM-ATT-003 quick ranges: this and last week (Saturday '
      'first), this and last pay period from period_start_day', (tester) async {
    final h = await pumpAttendance(
      tester,
      edit: (db) => db['attendance_settings'].firstWhere(
        (r) => r['org_id'] == SeedIds.sabahOrg,
      )!['period_start_day'] = 26,
    );
    Future<void> pick(String name, String from, String to) async {
      await h.tap(pageText(name));
      expect(pageListCalls(h).last.query, {
        'from': [from],
        'to': [to],
      }, reason: name);
      final chip = tester.widget<DashChoiceChip>(
        inPage(find.widgetWithText(DashChoiceChip, name)),
      );
      expect(chip.selected, isTrue, reason: name);
    }

    expect(
      find.descendant(
        of: inPage(find.bySemanticsLabel('Quick ranges')),
        matching: find.byType(DashChoiceChip),
      ),
      findsNWidgets(4),
    );
    await pick('This week', '2026-10-03', '2026-10-09');
    await pick('Last week', '2026-09-26', '2026-10-02');
    await pick('This pay period', '2026-09-26', '2026-10-25');
    await pick('Last pay period', '2026-08-26', '2026-09-25');
  });

  testWidgets('TEAM-ATT-004 / TEAM-ALL-025 the employee picker: Everyone and '
      'every person of every status, searched by name; sends employee_id', (
    tester,
  ) async {
    final h = await pumpAttendance(
      tester,
      edit: (db) => db['employees'].find(emp('ziad'))!['employment_status'] =
          'terminated',
    );
    expect(
      h.server.callsTo(employeesT).where((c) => c.query.isEmpty),
      hasLength(1),
    );
    await h.tap(pageText('Everyone'));
    expect(find.text('Type a name'), findsOneWidget);
    final box = find.descendant(
      of: find.byType(DashOptionList<String>),
      matching: find.byType(EditableText),
    );
    await h.enterText(box, 'ziad');
    await h.settle();
    expect(find.text('Ziad Amr').hitTestable(), findsOneWidget);
    await h.enterText(box, 'zzz');
    await h.settle();
    expect(find.text('No one by that name'), findsOneWidget);
    await h.enterText(box, 'mari');
    await h.settle();
    expect(find.text('Adham Reda').hitTestable(), findsNothing);
    await h.tap(find.text('Mariam Fathy').hitTestable());
    final q = {
      'from': [day(-6)],
      'to': [day()],
      'employee_id': [emp('mariam')],
    };
    expect(pageListCalls(h).last.query, q);
    expect(h.server.callsTo(summaryT).last.query, q);
    expect(tableText('Adham Reda'), findsNothing);
    expect(tableText('Mariam Fathy'), findsWidgets);
    expect(find.text('Type a name'), findsNothing);
  });

  testWidgets('TEAM-ATT-005 status filter: All statuses and the five, sends '
      'status', (tester) async {
    final h = await pumpAttendance(tester);
    await h.tap(pageText('All statuses'));
    for (final s in ['Present', 'Late', 'Half day', 'Absent', 'On leave']) {
      expect(find.text(s).hitTestable(), findsOneWidget, reason: s);
    }
    await h.tap(find.text('Late').hitTestable());
    expect(pageListCalls(h).last.query['status'], ['late']);
    expect(h.server.callsTo(summaryT).last.query['status'], ['late']);
    expect(inTable(find.text('Present')), findsNothing);
    expect(inTable(find.widgetWithText(DashStatusPill, 'Late')), findsWidgets);
  });

  testWidgets('TEAM-ATT-006 / TEAM-ALL-018 the scope bar\'s branch is sent '
      'to both reads; All branches sends none', (tester) async {
    final h = await pumpAttendance(tester);
    expect(pageListCalls(h).single.query.containsKey('branch_id'), isFalse);
    await h.tap(find.text('All branches'));
    await h.tap(find.text('Zamalek').hitTestable());
    expect(pageListCalls(h).last.query['branch_id'], [SeedIds.zamalek]);
    expect(h.server.callsTo(summaryT).last.query['branch_id'], [
      SeedIds.zamalek,
    ]);
    expect(tableText('Dina Fouad'), findsNothing);
  });

  testWidgets('TEAM-ATT-007 cards sum the window\'s summary: present, late, '
      'absent days and overtime in hours; four across on a desktop', (
    tester,
  ) async {
    final h = await pumpAttendance(tester);
    final rows = windowRows(h.db!);
    int count(String s) => rows.where((r) => r['status'] == s).length;
    final overtime = rows.fold<int>(
      0,
      (s, r) => s + (r['overtime_minutes']! as int),
    );
    expect(
      inCard('Present days', find.text('${count('present')}')),
      findsOneWidget,
    );
    expect(inCard('Late days', find.text('${count('late')}')), findsOneWidget);
    expect(
      inCard('Absent days', find.text('${count('absent')}')),
      findsOneWidget,
    );
    expect(
      inCard('Overtime', find.text(fmtHours('en', overtime))),
      findsOneWidget,
    );
    final tops = {
      for (final e in card(
        'Present days',
      ).evaluate().followedBy(card('Overtime').evaluate()))
        tester.getTopLeft(find.byWidget(e.widget)).dy,
    };
    expect(tops, hasLength(1));
  });

  testWidgets('TEAM-ATT-007 the cards are skeletons while the summary loads', (
    tester,
  ) async {
    final s = attendanceServer();
    final gate = s.server.hold('GET', summaryT);
    final h = await pumpAttendance(tester, s: s);
    expect(
      tester
          .widgetList<DashStatCard>(inPage(find.byType(DashStatCard)))
          .every((c) => c.loading),
      isTrue,
    );
    gate.release();
    await h.settle();
    expect(
      tester
          .widgetList<DashStatCard>(inPage(find.byType(DashStatCard)))
          .any((c) => c.loading),
      isFalse,
    );
  });

  testWidgets('TEAM-ATT-008 a failed summary reads "—" in every card, never '
      'a reassuring 0', (tester) async {
    final s = attendanceServer();
    s.server.fail('GET', summaryT, MockResponse.error(500, 'boom'));
    await pumpAttendance(tester, s: s);
    for (final c in ['Present days', 'Late days', 'Absent days', 'Overtime']) {
      expect(inCard(c, find.text('—')), findsOneWidget, reason: c);
      expect(inCard(c, find.text('0')), findsNothing, reason: c);
    }
    expect(tableText('Adham Reda'), findsWidgets);
  });

  testWidgets('TEAM-ATT-009 what the words mean: closed, opens on a tap with '
      'four terms, closes again', (tester) async {
    final h = await pumpAttendance(tester);
    final title = pageText('What late, left early and absent mean');
    expect(title, findsOneWidget);
    expect(pageText(h.t('dawamOps.wordLate')), findsNothing);
    await h.tap(title);
    for (final k in [
      'dawamOps.wordLate',
      'dawamOps.wordEarly',
      'dawamOps.wordAbsent',
      'dawamOps.wordHalf',
    ]) {
      expect(pageText(h.t(k)), findsOneWidget, reason: k);
    }
    expect(pageText('Left early'), findsOneWidget);
    expect(pageText('Half day'), findsWidgets);
    await h.tap(title);
    expect(pageText(h.t('dawamOps.wordLate')), findsNothing);
  });

  testWidgets('TEAM-ATT-010/011/016/018 name and shift (or Unscheduled), the '
      'date, worked and overtime', (tester) async {
    await pumpAttendance(tester, edit: (db) => onlyRecords(db, cellRows()));
    expect(inRow('Laila Ehab', find.text('Morning')), findsOneWidget);
    expect(inRow('Omar Khaled', find.text('Unscheduled')), findsOneWidget);
    expect(inRow('Laila Ehab', find.text('07 Oct 2026')), findsOneWidget);
    expect(inRow('Laila Ehab', textHas('7h 58m')), findsOneWidget);
    expect(inRow('Omar Khaled', find.text('45m')), findsOneWidget);
    expect(inRow('Laila Ehab', find.text('—')), findsWidgets);
  });

  testWidgets('TEAM-ATT-012 status pills; Month closed; Covered by on the '
      'owner\'s own day of a covered shift', (tester) async {
    final morning = TeamSeedIds.workShift('sabah', 'morning');
    final h = await pumpAttendance(
      tester,
      edit: (db) {
        // Mariam absent yesterday on the morning Youssef covers (seed).
        records(db).insert(
          recordRow(
            id: 'r-mariam',
            employeeKey: 'mariam',
            date: day(-1),
            status: 'absent',
            workShiftId: morning,
            workShiftName: 'Morning',
          ),
        );
      },
    );
    await h.enterText(inPage(find.byType(DashSearchInput)), 'mariam');
    await h.settle();
    expect(inRow('Mariam Fathy', find.text('Absent')), findsOneWidget);
    expect(
      inRow('Mariam Fathy', find.text('Covered by Youssef Samir')),
      findsOneWidget,
    );
    expect(tableText('Covered by Youssef Samir'), findsOneWidget);
    expect(tableText('Month closed'), findsNothing);
    // Last pay period (September) is paid: every row says its month closed.
    await h.enterText(inPage(find.byType(DashSearchInput)), '');
    await h.tap(pageText('Last pay period'));
    expect(tableText('Month closed'), findsWidgets);
  });

  testWidgets('TEAM-ATT-013 In on the RECORD\'s branch clock under All '
      'branches, its distance and why it was punched', (tester) async {
    await pumpAttendance(
      tester,
      edit: (db) {
        db['branches'].find(SeedIds.heliopolis)!['timezone'] = 'Asia/Tokyo';
        onlyRecords(db, [
          ...cellRows(),
          recordRow(
            id: 'r-farida',
            employeeKey: 'farida',
            date: day(-4),
            branchId: SeedIds.heliopolis,
            inAt: '${day(-4)}T00:00:00.000Z',
            outAt: '${day(-4)}T08:00:00.000Z',
            inMethod: 'manual',
            outMethod: 'manual',
            worked: 480,
          ),
        ]);
      },
    );
    // 00:00Z is 09:00 in Tokyo, not 03:00 on the business's Cairo clock.
    expect(inRow('Farida Wael', textHas('09:00 AM')), findsOneWidget);
    expect(inRow('Farida Wael', textHas('05:00 PM')), findsOneWidget);
    expect(inRow('Farida Wael', textHas('03:00 AM')), findsNothing);
    expect(inRow('Laila Ehab', textHas('09:02 AM')), findsOneWidget);
    expect(inRow('Laila Ehab', find.text('14m')), findsOneWidget);
    expect(
      find.ancestor(
        of: inRow('Laila Ehab', find.text('14m')),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Tooltip &&
              w.message == 'Distance from the branch when clocking in',
        ),
      ),
      findsOneWidget,
    );
    expect(inRow('Omar Khaled', find.text('Phone died')), findsOneWidget);
    expect(inRow('Laila Ehab', find.text('Phone died')), findsNothing);
  });

  testWidgets('TEAM-ATT-014/015 Out: "auto" once when auto-closed, else how '
      'it was made; every method but the phone\'s own has a badge', (
    tester,
  ) async {
    await pumpAttendance(tester, edit: (db) => onlyRecords(db, cellRows()));
    expect(inRow('Omar Khaled', find.text('by a manager')), findsNWidgets(2));
    expect(
      inRow('Omar Khaled', find.text('Forgot to clock out')),
      findsOneWidget,
    );
    expect(inRow('Ali Hassan', find.text('till PIN')), findsOneWidget);
    expect(inRow('Hana Mostafa', find.text('corrected')), findsOneWidget);
    expect(inRow('Hana Mostafa', find.text('queued offline')), findsOneWidget);
    expect(inRow('Youssef Samir', find.text('auto')), findsOneWidget);
    expect(inRow('Youssef Samir', find.text('auto-closed')), findsNothing);
    for (final m in [
      'by a manager',
      'till PIN',
      'corrected',
      'queued offline',
      'entered by hand',
    ]) {
      expect(inRow('Laila Ehab', find.text(m)), findsNothing, reason: m);
    }
  });

  testWidgets('TEAM-ATT-015 / TEAM-ALL-013 in Arabic: the method words and '
      'the distance unit, figures in Latin digits', (tester) async {
    await pumpAttendance(
      tester,
      locale: 'ar',
      edit: (db) => onlyRecords(db, cellRows()),
    );
    expect(tableText('من المدير'), findsNWidgets(2));
    expect(tableText('رقم سري على الكاشير'), findsOneWidget);
    expect(tableText('14 م'), findsOneWidget);
    expect(inCard('أيام الحضور', find.text('4')), findsOneWidget);
  });

  testWidgets('TEAM-ATT-017 late and left early, each with what it is '
      'measured from on the branch clock; "—" when neither', (tester) async {
    await pumpAttendance(tester, edit: (db) => onlyRecords(db, cellRows()));
    expect(inRow('Laila Ehab', find.text('2m')), findsOneWidget);
    expect(inRow('Laila Ehab', find.text('after 09:00 AM')), findsOneWidget);
    expect(inRow('Laila Ehab', find.text('30m')), findsOneWidget);
    expect(inRow('Laila Ehab', find.text('before 05:30 PM')), findsOneWidget);
    expect(inRow('Ali Hassan', textHas('after')), findsNothing);
  });

  testWidgets('TEAM-ATT-019/039 search: the name, the ISO date and the '
      'status KEY; not the shift nor the word; no hits shows the page\'s own '
      'empty state', (tester) async {
    final h = await pumpAttendance(
      tester,
      edit: (db) => onlyRecords(db, cellRows()),
    );
    final box = inPage(find.byType(DashSearchInput));
    expect(inPage(find.text('Search employees…')), findsOneWidget);
    Future<void> search(String q) async {
      await h.enterText(box, q);
      await h.settle();
    }

    await search('laila');
    expect(tableText('Laila Ehab'), findsOneWidget);
    expect(tableText('Omar Khaled'), findsNothing);
    await search(day(-2));
    expect(tableText('Hana Mostafa'), findsOneWidget);
    expect(tableText('Youssef Samir'), findsOneWidget);
    expect(tableText('Laila Ehab'), findsNothing);
    await search('on_leave');
    expect(tableText('Adham Reda'), findsOneWidget);
    expect(tableText('Laila Ehab'), findsNothing);
    await search('On leave'); // the word, not the key
    expect(tableText('Adham Reda'), findsNothing);
    expect(pageText('No attendance in this range'), findsOneWidget);
    expect(pageText(h.t('common.noResults')), findsNothing);
    await search('Morning'); // the shift is not searched
    expect(tableText('Laila Ehab'), findsNothing);
    // Export follows the loaded rows, not the searched ones.
    expect(
      tester
          .widget<DashExportButton>(inPage(find.byType(DashExportButton)))
          .enabled,
      isTrue,
    );
  });

  testWidgets('TEAM-ATT-020 loading: skeleton rows, never "no attendance"', (
    tester,
  ) async {
    final s = attendanceServer();
    final gate = s.server.hold('GET', listT);
    final h = await pumpAttendance(tester, s: s);
    expect(inTable(find.byType(DashSkeleton)), findsWidgets);
    expect(pageText('No attendance in this range'), findsNothing);
    gate.release();
    await h.settle();
    expect(inTable(find.byType(DashSkeleton)), findsNothing);
    expect(tableText('Adham Reda'), findsWidgets);
  });

  testWidgets('TEAM-ATT-020 error: the words and Retry, which asks only the '
      'records again', (tester) async {
    final s = attendanceServer();
    s.server.fail(
      'GET',
      listT,
      MockResponse.error(500, 'Database error: boom'),
    );
    final h = await pumpAttendance(tester, s: s);
    expect(tableText(h.t('common.loadFailed')), findsOneWidget);
    expect(tableText('boom'), findsOneWidget);
    final summaries = h.server.callsTo(summaryT).length;
    await h.tap(inTable(find.text('Retry')));
    expect(tableText('Adham Reda'), findsWidgets);
    expect(h.server.callsTo(summaryT).length, summaries);
  });

  testWidgets('TEAM-ATT-020 empty: "No attendance in this range" and its '
      'hint; Export Excel disabled', (tester) async {
    final h = await pumpAttendance(tester, edit: (db) => onlyRecords(db, []));
    expect(pageText('No attendance in this range'), findsOneWidget);
    expect(pageText(h.t('staff.noAttendanceHint')), findsOneWidget);
    expect(
      tester
          .widget<DashExportButton>(inPage(find.byType(DashExportButton)))
          .enabled,
      isFalse,
    );
    expect(inCard('Present days', find.text('0')), findsOneWidget);
  });

  testWidgets('TEAM-ATT-022/034 a reader gets neither Add record nor Correct', (
    tester,
  ) async {
    final s = attendanceServer();
    answerAuthz(s.server, const ['hr.attendance.read']);
    await pumpAttendance(tester, s: s);
    expect(tableText('Adham Reda'), findsWidgets);
    expect(pageText('Add record'), findsNothing);
    expect(correct, findsNothing);
  });

  testWidgets(
    'TEAM-ATT-022/034 hr.attendance.edit alone: Correct but not Add',
    (tester) async {
      final s = attendanceServer();
      answerAuthz(s.server, const ['hr.attendance.read', 'hr.attendance.edit']);
      final h = await pumpAttendance(tester, s: s);
      expect(pageText('Add record'), findsNothing);
      expect(correct, findsWidgets);
      await h.tap(correct.first);
      expect(find.byType(AttendanceCorrectDialog), findsOneWidget);
    },
  );

  testWidgets('TEAM-ATT-022 Add record opens the add dialog', (tester) async {
    final h = await pumpAttendance(tester);
    await h.tap(pageText('Add record'));
    expect(find.byType(AttendanceAddDialog), findsOneWidget);
  });

  testWidgets('TEAM-ATT-034 a record in a closed month offers no Correct', (
    tester,
  ) async {
    final h = await pumpAttendance(tester);
    expect(correct, findsNWidgets(10));
    await h.tap(pageText('Last pay period'));
    expect(tableText('Month closed'), findsWidgets);
    expect(correct, findsNothing);
  });

  testWidgets('TEAM-ATT-038 phone: filters wrap, cards two by two, each '
      'record a card titled by name with its punches and Correct', (
    tester,
  ) async {
    final h = await pumpAttendance(
      tester,
      size: DashSize.phone,
      edit: (db) => onlyRecords(db, cellRows()),
    );
    final cards = inPage(find.byType(DashStatCard));
    final rows = {
      for (final e in cards.evaluate())
        tester.getTopLeft(find.byWidget(e.widget)).dy,
    };
    expect(rows, hasLength(2));
    expect(inTable(find.byType(DashCard)), findsNWidgets(6));
    expect(tableText('Omar Khaled'), findsOneWidget);
    expect(tableText('Phone died'), findsOneWidget);
    expect(inPage(find.bySemanticsLabel('Correct')), findsNWidgets(6));
    expect(pageText('Columns'), findsNothing);
    // The picker sits under the dates, not beside them.
    expect(
      tester.getTopLeft(pageText('Everyone')).dy,
      greaterThan(tester.getTopLeft(pageText('This week')).dy),
    );
    await h.tap(inPage(find.bySemanticsLabel('Correct')).first);
    expect(find.byType(AttendanceCorrectDialog), findsOneWidget);
    expectPhoneDialog(tester, primary: 'Save', secondary: 'Cancel');
  });

  // ── area-wide rows on this page ─────────────────────────────────────────

  testWidgets('TEAM-ALL-002 the Attendance leaf shows with hr.attendance.read, '
      'hidden without', (tester) async {
    var h = await pumpAttendance(tester);
    Finder leaf() => find.descendant(
      of: find.byType(DashSidebar),
      matching: find.text('Attendance'),
    );
    expect(leaf(), findsOneWidget);
    h = await pumpAttendance(tester, persona: Persona.limited);
    expect(leaf(), findsNothing);
    expect(h.location.path, attendancePath);
  });

  testWidgets('TEAM-ALL-005 module off: the module refusal, nothing asked', (
    tester,
  ) async {
    final s = attendanceServer(
      edit: (db) => db['orgs'].update(SeedIds.sabahOrg, {
        'modules': ['pos'],
      }),
    );
    final h = await pumpAttendance(tester, s: s);
    expect(find.text(h.t('dawam.moduleOffTitle')), findsOneWidget);
    expect(page, findsNothing);
    expect(pageListCalls(h), isEmpty);
    expect(h.server.callsTo(summaryT), isEmpty);
  });

  testWidgets('TEAM-ALL-007 no in-page guard: without hr.attendance.read the '
      'page opens, the table says the refusal, the cards "—"', (tester) async {
    final h = await pumpAttendance(tester, persona: Persona.limited);
    expect(pageText('Attendance'), findsOneWidget);
    expect(tableText(h.t('errors.unauthorized')), findsOneWidget);
    expect(pageListCalls(h).last.status, 403);
    expect(inCard('Present days', find.text('—')), findsOneWidget);
    expect(pageText('Add record'), findsNothing);
  });

  testWidgets('TEAM-ALL-008 Refresh refetches the page\'s reads and spins '
      'while they are in flight', (tester) async {
    final h = await pumpAttendance(tester);
    final lists = pageListCalls(h).length;
    final summaries = h.server.callsTo(summaryT).length;
    final people = h.server.callsTo(employeesT).length;
    final gate = h.server.hold('GET', summaryT);
    await h.tap(inPage(find.bySemanticsLabel('Refresh')));
    expect(inPage(find.bySemanticsLabel('Refreshing…')), findsOneWidget);
    gate.release();
    await h.settle();
    expect(inPage(find.bySemanticsLabel('Refresh')), findsOneWidget);
    expect(pageListCalls(h).length, lists + 1);
    expect(h.server.callsTo(summaryT).length, summaries + 1);
    expect(h.server.callsTo(employeesT).length, greaterThan(people));
  });

  testWidgets('TEAM-ALL-009 back to the app after 30 s refetches the reads; '
      'sooner does nothing', (tester) async {
    final h = await pumpAttendance(tester);
    final before = pageListCalls(h).length;
    final summaries = h.server.callsTo(summaryT).length;
    h.server.clock.advance(const Duration(seconds: 10));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await h.settle();
    expect(pageListCalls(h).length, before);
    h.server.clock.advance(const Duration(seconds: 30));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await h.settle();
    expect(pageListCalls(h).length, before + 1);
    expect(h.server.callsTo(summaryT).length, summaries + 1);
  });

  testWidgets('TEAM-ALL-010/022 a failed refresh replaces the rows with the '
      'error, the cards keep their figures, and one toast says it', (
    tester,
  ) async {
    final h = await pumpAttendance(tester);
    final present =
        '${windowRows(h.db!).where((r) => r['status'] == 'present').length}';
    h.server.fail(
      'GET',
      listT,
      MockResponse.error(429, 'Too many requests'),
      times: null,
    );
    await h.tap(inPage(find.bySemanticsLabel('Refresh')));
    expect(tableText('Adham Reda'), findsNothing);
    expect(tableText(h.t('common.loadFailed')), findsOneWidget);
    expect(inCard('Present days', find.text(present)), findsOneWidget);
    await h.expectToast(h.t('errors.tooManyRequests'));
  });

  testWidgets('TEAM-ALL-012 "today" is the business\'s day: at 01:30 in Cairo '
      'the window ends on the Cairo date, not UTC\'s', (tester) async {
    final s = attendanceServer();
    s.db.clock.set(DateTime.utc(2026, 10, 8, 22, 30));
    final h = await pumpAttendance(tester, s: s);
    expect(pageListCalls(h).single.query, {
      'from': ['2026-10-03'],
      'to': ['2026-10-09'],
    });
  });

  testWidgets('TEAM-ALL-020 pages of 10: "Page 1 of n", Next/Previous; the '
      'Columns menu lists every column', (tester) async {
    final h = await pumpAttendance(tester);
    final pages = (windowRows(h.db!).length / 10).ceil();
    expect(pageText('Page 1 of $pages'), findsOneWidget);
    await h.tap(inPage(find.bySemanticsLabel('Next')));
    expect(pageText('Page 2 of $pages'), findsOneWidget);
    await h.tap(inPage(find.bySemanticsLabel('Previous')));
    expect(pageText('Page 1 of $pages'), findsOneWidget);
    await h.tap(pageText('Columns'));
    for (final c in [
      'Name',
      'Date',
      'Status',
      'In',
      'Out',
      'Worked',
      'Late / left early',
      'Overtime',
    ]) {
      expect(find.text(c), findsWidgets, reason: c);
    }
  });

  testWidgets('TEAM-ALL-021 filters live in the page, not the URL, and are '
      'kept when it is left', (tester) async {
    final h = await pumpAttendance(tester);
    await h.tap(pageText('All statuses'));
    await h.tap(find.text('Absent').hitTestable());
    expect(h.location.query, isEmpty);
    h.allowUnmatched = true;
    await h.go('/staff/employees');
    await h.go(attendancePath);
    expect(pageText('All statuses'), findsNothing);
    expect(
      inTable(find.widgetWithText(DashStatusPill, 'Present')),
      findsNothing,
    );
  });

  testWidgets('TEAM-ALL-023 the records read: a 403 once, a 500 twice, a '
      '429 four times', (tester) async {
    Future<int> asks(MockResponse answer) async {
      final s = attendanceServer();
      s.server.fail('GET', listT, answer, times: null);
      final c = ProviderContainer(
        retry: webRetry,
        overrides: [
          transportProvider.overrideWithValue(s.server),
          orgIdProvider.overrideWithValue(SeedIds.sabahOrg),
        ],
      );
      final key = attendanceWindow(day(-6), day());
      final sub = c.listen(attendanceListProvider(key), (_, _) {});
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      sub.close();
      c.dispose();
      return s.server.callsTo(listT).length;
    }

    expect(await asks(MockResponse.denied('hr.attendance.read')), 1);
    expect(await asks(MockResponse.error(500, 'boom')), 2);
    expect(await asks(MockResponse.error(429, 'Slow down')), 4);
  });

  test('fmtMinutes reads like the web', () {
    const f = DashFormat();
    expect(fmtMinutes(f, 478), '7h 58m');
    expect(fmtMinutes(f, 0), '0m');
  });
}
