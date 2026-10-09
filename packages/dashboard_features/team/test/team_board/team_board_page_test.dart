// The Team board page (`/staff/team`, TEAM-TEM-001…011, 023…028, 031 and the
// area rows it carries): driven through the real shell on the mock server.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart' show ltr;
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_team/src/area_seed.dart';
import 'package:dashboard_team/src/team_board/team_board_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'team_board_support.dart';

const List<String> _reader = ['hr.attendance.read'];

void _noRules(MockDb db) {
  for (final r in db['attendance_settings'].rows) {
    r['rules_saved_at'] = null;
  }
}

/// Adds a pending cover of [coveredKey]'s day today by [covererKey].
void _cover(
  MockDb db,
  String covererKey,
  String coveredKey, {
  String status = 'pending',
}) {
  final by = db['employees'].find(SeedIds.employee(covererKey))!;
  db[TeamTables.attendance].put({
    'id': 'cover-$covererKey-$coveredKey',
    'org_id': by['org_id'],
    'branch_id': (by['branch_ids']! as List).first,
    'employee_id': by['id'],
    'employee_name': by['name'],
    'business_date': today,
    'status': 'present',
    'late_minutes': 0,
    'early_leave_minutes': 0,
    'overtime_minutes': 0,
    'worked_minutes': 0,
    'is_manual': false,
    'tracking_off': false,
    'month_closed': false,
    'covered_employee_id': SeedIds.employee(coveredKey),
    'cover_status': status,
    'created_at': '2026-10-08T04:00:00.000Z',
    'updated_at': '2026-10-08T04:00:00.000Z',
  });
}

/// The flags' and the team's loading blocks (not the cards' own).
Finder _blocks() => inBoard(
  find.byWidgetPredicate(
    (w) =>
        w is DashSkeleton &&
        (w.height == TeamBoardMetrics.flagsSkeleton ||
            w.height == TeamBoardMetrics.teamSkeleton),
  ),
);

void main() {
  testWidgets('TEAM-TEM-001 without attendance rights the page is closed and '
      'asks for nothing', (tester) async {
    final h = await pumpTeam(tester, persona: Persona.limited);
    expect(find.text(h.t('dawam.teamNoAccess')), findsOneWidget);
    expect(find.text(h.t('dawam.team')), findsWidgets);
    expect(board, findsNothing);
    expect(h.server.callsTo(presenceT), isEmpty);
    expect(h.server.callsTo(flagsT), isEmpty);
  });

  testWidgets('TEAM-TEM-002 header: title, description and the owner\'s five '
      'actions', (tester) async {
    final h = await pumpTeam(tester);
    expect(boardText('Team'), findsOneWidget);
    expect(boardText(h.t('dawam.teamSubtitle')), findsOneWidget);
    for (final k in [
      'dawam.addPayLineHere',
      'dawam.logExpense',
      'dawam.importTitle',
      'dawam.addEmployee',
    ]) {
      expect(boardButton(h.t(k)), findsOneWidget, reason: k);
    }
    expect(inBoard(find.bySemanticsLabel('Refresh')), findsWidgets);
  });

  testWidgets('TEAM-TEM-003 "Add a bonus or deduction" opens the pay-line '
      'dialog', (tester) async {
    final h = await pumpTeam(tester);
    await h.tap(boardButton(h.t('dawam.addPayLineHere')));
    expect(surfaceText(h.t('dawam.addPayLine')), findsOneWidget);
    expect(surfaceText(h.t('dawam.addPayLineHint')), findsOneWidget);
    await h.tap(surfaceButton('Cancel'));
    expect(find.byType(DashSurface), findsNothing);
  });

  testWidgets('TEAM-TEM-003 the deduction right alone shows it', (
    tester,
  ) async {
    final s = teamServer();
    answerAuthz(s.server, [..._reader, 'hr.deductions.create']);
    final h = await pumpTeam(tester, s: s);
    expect(boardButton(h.t('dawam.addPayLineHere')), findsOneWidget);
  });

  testWidgets('TEAM-TEM-003 / 004 / 005 a reader sees no money or people '
      'actions', (tester) async {
    final s = teamServer();
    answerAuthz(s.server, _reader);
    final h = await pumpTeam(tester, s: s);
    for (final k in [
      'dawam.addPayLineHere',
      'dawam.logExpense',
      'dawam.importTitle',
      'dawam.addEmployee',
    ]) {
      expect(boardButton(h.t(k)), findsNothing, reason: k);
    }
  });

  testWidgets('TEAM-TEM-004 "Log an expense advance" opens its dialog', (
    tester,
  ) async {
    final h = await pumpTeam(tester);
    await h.tap(boardButton(h.t('dawam.logExpense')));
    expect(surfaceText(h.t('dawam.logExpenseHint')), findsOneWidget);
    await h.tap(surfaceButton('Cancel'));
    expect(find.byType(DashSurface), findsNothing);
  });

  testWidgets('TEAM-TEM-005 import and add employee open their dialogs', (
    tester,
  ) async {
    final h = await pumpTeam(tester);
    await h.tap(boardButton(h.t('dawam.addEmployee')));
    expect(find.byType(DashSurface), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
    expect(find.byType(DashSurface), findsNothing);
    await h.tap(boardButton(h.t('dawam.importTitle')));
    expect(find.byType(DashSurface), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
  });

  testWidgets('TEAM-TEM-006 / TEAM-ALL-016 rules never saved: the banner sits '
      'under the header and sends to the rules', (tester) async {
    final h = await pumpTeam(tester, edit: _noRules);
    expect(boardText(h.t('dawam.rulesFirstTitle')), findsOneWidget);
    expect(boardText(h.t('dawam.rulesFirstHint')), findsOneWidget);
    h.allowUnmatched = true;
    await h.tap(boardButton(h.t('dawam.rulesFirstAction')));
    expect(h.location.path, '/staff/rules');
  });

  testWidgets('TEAM-ALL-016 saved rules show no banner', (tester) async {
    final h = await pumpTeam(tester);
    expect(boardText(h.t('dawam.rulesFirstTitle')), findsNothing);
  });

  testWidgets('TEAM-ALL-016 a failed settings read shows no banner', (
    tester,
  ) async {
    final s = teamServer(edit: _noRules);
    s.server.fail(
      'GET',
      '/staff/attendance/settings',
      MockResponse.error(500, 'boom'),
      times: null,
    );
    final h = await pumpTeam(tester, s: s);
    expect(boardText(h.t('dawam.rulesFirstTitle')), findsNothing);
  });

  testWidgets('TEAM-TEM-007 the presence is asked again every 60 s, the flags '
      'are not; both refetch on return after 30 s', (tester) async {
    final h = await pumpTeam(tester);
    expect(h.server.callsTo(presenceT), hasLength(1));
    expect(h.server.callsTo(flagsT), hasLength(1));
    await tester.pump(const Duration(seconds: 60));
    await h.settle();
    expect(h.server.callsTo(presenceT), hasLength(2));
    expect(h.server.callsTo(flagsT), hasLength(1));
    // Back to the app: stale (over 30 s) reads are asked again.
    h.server.clock.advance(const Duration(seconds: 45));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await h.settle();
    expect(h.server.callsTo(presenceT), hasLength(3));
    expect(h.server.callsTo(flagsT), hasLength(2));
  });

  testWidgets('TEAM-ALL-008 Refresh asks the page\'s reads again', (
    tester,
  ) async {
    final h = await pumpTeam(tester);
    await h.tap(inBoard(find.bySemanticsLabel('Refresh')).first);
    expect(h.server.callsTo(presenceT), hasLength(2));
    expect(h.server.callsTo(flagsT), hasLength(2));
  });

  testWidgets('TEAM-ALL-022 a failed poll keeps the board and toasts once', (
    tester,
  ) async {
    final h = await pumpTeam(tester);
    h.server.fail(
      'GET',
      presenceT,
      MockResponse.error(500, 'boom'),
      times: null,
    );
    await tester.pump(const Duration(seconds: 60));
    await h.settle();
    expect(boardText('Adham Reda'), findsOneWidget);
    await h.expectToast(h.refusalWords(MockResponse.error(500, 'boom')));
  });

  testWidgets('TEAM-ALL-018 the scope\'s branch is sent; All branches sends '
      'none', (tester) async {
    final h = await pumpTeam(tester);
    expect(
      h.server.callsTo(presenceT).single.query.containsKey('branch_id'),
      isFalse,
    );
    await h.tap(find.text('All branches'));
    await h.tap(find.text('Zamalek').hitTestable());
    expect(h.server.callsTo(presenceT).last.query['branch_id'], [
      SeedIds.zamalek,
    ]);
    expect(h.server.callsTo(flagsT).last.query['branch_id'], [SeedIds.zamalek]);
    expect(h.server.callsTo(attendanceT).last.query['branch_id'], [
      SeedIds.zamalek,
    ]);
    expect(boardText('Dina Fouad'), findsNothing);
    expect(boardText('Adham Reda'), findsOneWidget);
  });

  testWidgets('TEAM-TEM-008 the cards count In, Late, Absent and open flags', (
    tester,
  ) async {
    final h = await pumpTeam(tester);
    int? value(String k) =>
        tester.widget<DashStatCard>(statCard(h.t(k))).value?.toInt();
    expect(value('dawam.stateIn'), 5);
    expect(value('dawam.stateLate'), 1);
    expect(value('dawam.stateAbsent'), 2);
    expect(value('dawam.openFlags'), 2);
  });

  testWidgets('TEAM-TEM-008 a failed presence shows a dash, never 0', (
    tester,
  ) async {
    final s = teamServer();
    s.server.fail(
      'GET',
      presenceT,
      MockResponse.error(500, 'boom'),
      times: null,
    );
    final h = await pumpTeam(tester, s: s);
    for (final k in ['dawam.stateIn', 'dawam.stateLate', 'dawam.stateAbsent']) {
      expect(tester.widget<DashStatCard>(statCard(h.t(k))).valueText, '—');
    }
    expect(
      tester.widget<DashStatCard>(statCard(h.t('dawam.openFlags'))).value,
      2,
    );
  });

  testWidgets('TEAM-TEM-008 failed flags show a dash, never 0', (tester) async {
    final s = teamServer();
    s.server.fail('GET', flagsT, MockResponse.error(500, 'boom'), times: null);
    final h = await pumpTeam(tester, s: s);
    expect(
      tester.widget<DashStatCard>(statCard(h.t('dawam.openFlags'))).valueText,
      '—',
    );
    expect(
      tester.widget<DashStatCard>(statCard(h.t('dawam.stateIn'))).value,
      5,
    );
  });

  testWidgets('TEAM-TEM-008 / TEAM-TEM-010 / TEAM-TEM-024 skeletons while '
      'loading, never "no flags" or "nobody rostered"', (tester) async {
    final s = teamServer();
    final a = s.server.hold('GET', presenceT);
    final b = s.server.hold('GET', flagsT);
    final h = await pumpTeam(tester, s: s);
    expect(_blocks(), findsNWidgets(2));
    for (final c in tester.widgetList<DashStatCard>(
      inBoard(find.byType(DashStatCard)),
    )) {
      expect(c.loading, isTrue);
    }
    expect(boardText(h.t('dawam.noFlags')), findsNothing);
    expect(boardText(h.t('dawam.nobodyRostered')), findsNothing);
    a.release();
    b.release();
    await h.settle();
    expect(_blocks(), findsNothing);
  });

  testWidgets('TEAM-TEM-009 only open flags are listed under "Flags"', (
    tester,
  ) async {
    final h = await pumpTeam(tester);
    expect(boardText(h.t('dawam.flags')), findsOneWidget);
    expect(boardHas('Hana Mostafa · '), findsNothing);
    expect(
      boardText('Karim Adel · ${h.t('dawam.flag_left_mid_shift')}'),
      findsOneWidget,
    );
    expect(
      boardText('Dina Fouad · ${h.t('dawam.flag_new_phone')}'),
      findsOneWidget,
    );
  });

  testWidgets('TEAM-TEM-010 flags error with Retry, never "No open flags"; '
      'Retry asks only the flags', (tester) async {
    final s = teamServer();
    s.server.fail('GET', flagsT, MockResponse.error(500, 'boom'));
    final h = await pumpTeam(tester, s: s);
    expect(boardText(h.t('dawam.flagsLoadError')), findsOneWidget);
    expect(boardText(h.t('dawam.noFlags')), findsNothing);
    final presence = h.server.callsTo(presenceT).length;
    await h.tap(inBoard(find.text('Retry')));
    expect(boardText(h.t('dawam.flagsLoadError')), findsNothing);
    expect(
      boardText('Dina Fouad · ${h.t('dawam.flag_new_phone')}'),
      findsOneWidget,
    );
    expect(h.server.callsTo(presenceT), hasLength(presence));
  });

  testWidgets('TEAM-TEM-010 no open flags: the empty state', (tester) async {
    final h = await pumpTeam(
      tester,
      edit: (db) => db[TeamTables.flags].clear(),
    );
    expect(boardText(h.t('dawam.noFlags')), findsOneWidget);
    expect(boardText(h.t('dawam.noFlagsHint')), findsOneWidget);
  });

  testWidgets('TEAM-TEM-011 a flag row: kind glyph, "name · kind", detected '
      'time and minutes away; a dead phone is named as that', (tester) async {
    final h = await pumpTeam(
      tester,
      edit: (db) =>
          addFlag(db, 'died', kind: 'phone_died', employeeKey: 'ziad'),
    );
    final row = rowOf('Karim Adel · ${h.t('dawam.flag_left_mid_shift')}');
    final w = tester.widget<DashListRow>(row);
    expect(w.icon, 'map-pin-off');
    expect(w.variant, DashListRowVariant.nav);
    expect(w.meta, contains(h.t('dawam.minutesAway', args: {'m': 25})));
    final died = tester.widget<DashListRow>(
      rowOf('Ziad Amr · ${h.t('dawam.flag_phone_died')}'),
    );
    expect(died.icon, 'battery-low');
    expect(died.meta, isNot(contains('away')));
  });

  testWidgets('TEAM-TEM-011 without hr.attendance.edit a flag row opens '
      'nothing', (tester) async {
    final s = teamServer();
    answerAuthz(s.server, _reader);
    final h = await pumpTeam(tester, s: s);
    final row = rowOf('Karim Adel · ${h.t('dawam.flag_left_mid_shift')}');
    expect(tester.widget<DashListRow>(row).onTap, isNull);
  });

  testWidgets('TEAM-TEM-023 "Right now · <the server\'s business date>"', (
    tester,
  ) async {
    final h = await pumpTeam(tester);
    expect(
      boardText('${h.t('dawam.rightNow')} · ${ltr(today)}'),
      findsOneWidget,
    );
  });

  testWidgets('TEAM-TEM-024 presence error with Retry; Retry asks only the '
      'presence', (tester) async {
    final s = teamServer();
    s.server.fail('GET', presenceT, MockResponse.error(500, 'boom'));
    final h = await pumpTeam(tester, s: s);
    expect(boardText(h.t('dawam.teamLoadError')), findsOneWidget);
    expect(boardText(h.t('dawam.rightNow')), findsOneWidget);
    final flags = h.server.callsTo(flagsT).length;
    await h.tap(inBoard(find.text('Retry')));
    expect(boardText('Adham Reda'), findsOneWidget);
    expect(h.server.callsTo(flagsT), hasLength(flags));
  });

  testWidgets('TEAM-TEM-025 nobody rostered: the Schedule hint, not a list of '
      '"Off"', (tester) async {
    final h = await pumpTeam(
      tester,
      edit: (db) {
        db[TeamTables.assignments].clear();
        db[TeamTables.attendance].removeWhere(
          (r) => r['business_date'] == today,
        );
      },
    );
    expect(boardText(h.t('dawam.nobodyRostered')), findsOneWidget);
    expect(boardText(h.t('dawam.nobodyRosteredHint')), findsOneWidget);
  });

  testWidgets('TEAM-TEM-025 someone rostered later today keeps the list', (
    tester,
  ) async {
    final h = await pumpTeam(
      tester,
      edit: (db) {
        db[TeamTables.attendance].removeWhere(
          (r) => r['business_date'] == today,
        );
        // Only the evening people stay rostered: off now, due at 15:00.
        db[TeamTables.assignments].removeWhere(
          (r) =>
              r['work_shift_id'] == TeamSeedIds.workShift('sabah', 'morning'),
        );
      },
    );
    expect(boardText(h.t('dawam.nobodyRostered')), findsNothing);
    expect(boardText('Ali Hassan'), findsOneWidget);
  });

  testWidgets('TEAM-TEM-026 a row: branch, in time, lateness and its state '
      'pill', (tester) async {
    final h = await pumpTeam(tester);
    final adham = tester.widget<DashListRow>(rowOf('Adham Reda'));
    expect(adham.meta, startsWith('Zamalek · in '));
    expect(adham.meta, contains('07:33'));
    expect(adham.meta, contains('late '));
    Finder pill(String name, String label) => inRow(
      name,
      find.byWidgetPredicate((w) => w is DashStatusPill && w.label == label),
    );
    expect(pill('Adham Reda', 'Late'), findsOneWidget);
    expect(pill('Dina Fouad', 'In'), findsOneWidget);
    expect(pill('Tarek Saber', 'Absent'), findsOneWidget);
    expect(pill('Ali Hassan', 'Off'), findsOneWidget);
    expect(
      tester.widget<DashStatusPill>(pill('Tarek Saber', 'Absent')).tone,
      DashTone.danger,
    );
  });

  testWidgets('TEAM-TEM-026 / TEAM-TEM-027 a shift a colleague covers says '
      'who, and its punch is disabled with why', (tester) async {
    final h = await pumpTeam(tester, edit: (db) => _cover(db, 'ziad', 'tarek'));
    expect(
      inRow(
        'Tarek Saber',
        find.text(h.t('dawam.coveredBy', args: {'name': 'Ziad Amr'})),
      ),
      findsOneWidget,
    );
    final punch = inRow('Tarek Saber', boardButton(h.t('dawam.punchIn')));
    expect(enabled(tester, punch), isFalse);
    expect(
      tester.widget<DashButton>(punch).tooltip,
      h.t('dawam.punchCoveredWhy', args: {'name': 'Ziad Amr'}),
    );
  });

  testWidgets('TEAM-TEM-026 / TEAM-TEM-027 a rejected cover blocks nothing', (
    tester,
  ) async {
    final h = await pumpTeam(
      tester,
      edit: (db) => _cover(db, 'ziad', 'tarek', status: 'rejected'),
    );
    expect(inRow('Tarek Saber', find.textContaining('Ziad Amr')), findsNothing);
    expect(
      enabled(tester, inRow('Tarek Saber', boardButton(h.t('dawam.punchIn')))),
      isTrue,
    );
  });

  testWidgets('TEAM-TEM-027 punch in for the absent, out for whoever is in, '
      'none for the off', (tester) async {
    final h = await pumpTeam(tester);
    expect(
      inRow('Tarek Saber', boardButton(h.t('dawam.punchIn'))),
      findsOneWidget,
    );
    expect(
      inRow('Adham Reda', boardButton(h.t('dawam.punchOut'))),
      findsOneWidget,
    );
    expect(inRow('Ali Hassan', find.byType(DashButton)), findsNothing);
  });

  testWidgets('TEAM-TEM-027 the check-in window open before the shift offers '
      'Punch in', (tester) async {
    // 14:30 Cairo: the evening shift (15:00) opens at 14:00.
    final s = teamServer();
    s.db.clock.advance(const Duration(hours: 4, minutes: 30));
    final h = await pumpTeam(tester, s: s);
    expect(
      inRow('Ali Hassan', boardButton(h.t('dawam.punchIn'))),
      findsOneWidget,
    );
  });

  testWidgets('TEAM-TEM-027 no punch without hr.attendance.punch_others', (
    tester,
  ) async {
    final s = teamServer();
    answerAuthz(s.server, _reader);
    final h = await pumpTeam(tester, s: s);
    expect(inRow('Tarek Saber', find.byType(DashButton)), findsNothing);
    expect(h.server.callsTo(attendanceT), isEmpty);
  });

  testWidgets('TEAM-TEM-028 today in an approved month: said once, no punch '
      'buttons', (tester) async {
    final h = await pumpTeam(
      tester,
      edit: (db) => db[TeamTables.payrollPeriods].put({
        'id': 'october',
        'org_id': SeedIds.sabahOrg,
        'start_date': '2026-10-01',
        'end_date': '2026-10-31',
        'status': 'generated',
      }),
    );
    expect(boardText(h.t('dawam.todayMonthClosed')), findsOneWidget);
    expect(
      inRow('Tarek Saber', boardButton(h.t('dawam.punchIn'))),
      findsNothing,
    );
    expect(
      inRow('Adham Reda', boardButton(h.t('dawam.punchOut'))),
      findsNothing,
    );
  });

  testWidgets('TEAM-TEM-031 phone: cards 2×2, actions wrap, rows keep the '
      'name beside the pill and punch', (tester) async {
    final h = await pumpTeam(tester, size: DashSize.phone);
    final cards = inBoard(find.byType(DashStatCard));
    final ys = {
      for (final e in cards.evaluate())
        tester.getTopLeft(find.byWidget(e.widget)).dy,
    };
    expect(ys, hasLength(2));
    expect(boardText('Adham Reda'), findsOneWidget);
    expect(boardButton(h.t('dawam.addEmployee')), findsOneWidget);
  });
}
