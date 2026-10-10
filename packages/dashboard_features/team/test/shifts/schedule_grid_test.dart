// Work shifts' standing roster grid (TEAM-SHF-025…033): everyone down the
// side, the week across, Saturday first; a cell's menu assigns a block or
// makes the day a rest day.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_team/src/area_seed.dart';
import 'package:dashboard_team/src/shifts/schedule_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shifts_support.dart';

final String _morning = sabahShift('morning');
final String _evening = sabahShift('evening');

/// Adds a standing roster row for [employee] ([dow] null = every day).
MockRow addRow(
  MockDb db,
  String employee,
  String shift, {
  int? dow,
  String from = '2026-09-01',
}) => db[TeamTables.assignments].insert({
  'id': mockUuid('assignment:test:$employee:${dow ?? 'all'}:$from'),
  'org_id': SeedIds.sabahOrg,
  'employee_id': emp(employee),
  'work_shift_id': shift,
  'work_shift_name': db['work_shifts'].find(shift)!['name'],
  'day_of_week': dow,
  'effective_from': from,
  'effective_to': null,
  'created_at': '2026-09-01T09:00:00Z',
  'branch_id': null,
}, timestamps: false);

/// The demo blocks, nobody rostered, then Karim (Zamalek): Morning every
/// day and Evening on Saturday.
void karimRoster(MockDb db) {
  addDemoShifts(db);
  noRoster(db);
  addRow(db, 'karim', _morning);
  addRow(db, 'karim', _evening, dow: 6);
}

RosterCell rosterCell(WidgetTester tester, int? dow) =>
    tester.widget<RosterCell>(cell('karim', dow));

Finder inCell(int? dow, Finder f) =>
    find.descendant(of: cell('karim', dow), matching: f);

/// Opens Karim's cell menu on [dow].
Future<void> openCell(DashHarness h, int? dow) => h.tap(cell('karim', dow));

Finder menuItem(String id) => find.byKey(ValueKey('assign-$id'));

/// What a person reads on the menu row of block [id].
String menuLabel(WidgetTester tester, String id) =>
    tester.widget<DashPressable>(menuItem(id)).semanticLabel!;

void main() {
  testWidgets('TEAM-SHF-025 the section: "Roster", its hint, and the whole '
      'org\'s roster in one request with the active people', (tester) async {
    final h = await pumpShifts(tester);
    expect(inGrid(find.text('Roster')), findsOneWidget);
    expect(inGrid(find.text(h.t('staff.gridHint'))), findsOneWidget);
    expect(h.server.callsTo(rosterT).single.query, isEmpty);
    expect(
      h.server
          .callsTo(employeesT)
          .where((c) => c.query['employment_status']?.single == 'active'),
      hasLength(1),
    );
  });

  testWidgets('TEAM-SHF-026 loading: four skeleton bars', (tester) async {
    final s = shiftsServer();
    final gate = s.server.hold('GET', rosterT);
    final h = await pumpShifts(tester, s: s);
    final loading = inGrid(find.byKey(const ValueKey('roster-loading')));
    expect(loading, findsOneWidget);
    expect(
      find.descendant(of: loading, matching: find.byType(DashSkeleton)),
      findsNWidgets(4),
    );
    expect(inGrid(find.text(h.t('staff.noShiftsToRoster'))), findsNothing);
    gate.release();
    await h.settle();
    expect(loading, findsNothing);
    expect(inGrid(find.byKey(const ValueKey('roster-table'))), findsOneWidget);
  });

  testWidgets('TEAM-SHF-027 error: the words, and Retry asks both reads '
      'again', (tester) async {
    final s = shiftsServer();
    s.server.fail('GET', rosterT, MockResponse.error(500, 'boom'), times: null);
    final h = await pumpShifts(tester, s: s);
    expect(inGrid(find.text("Couldn't load the roster")), findsOneWidget);
    // The shift list above still shows.
    expect(shiftRow(_morning), findsOneWidget);
    int active() => h.server
        .callsTo(employeesT)
        .where((c) => c.query['employment_status']?.single == 'active')
        .length;
    final people = active();
    final roster = h.server.callsTo(rosterT).length;
    final shifts = h.server.callsTo(shiftsT).length;
    h.server.clearFailures();
    await h.tap(inGrid(find.text('Retry')));
    expect(active(), people + 1);
    expect(h.server.callsTo(rosterT).length, roster + 1);
    expect(h.server.callsTo(shiftsT).length, shifts, reason: 'only its own');
    expect(inGrid(find.byKey(const ValueKey('roster-table'))), findsOneWidget);
  });

  testWidgets('TEAM-SHF-028 nobody active: "No active employees to '
      'roster."', (tester) async {
    final h = await pumpShifts(
      tester,
      edit: (db) {
        for (final e in db['employees'].where(
          (r) => r['org_id'] == SeedIds.sabahOrg,
        )) {
          e['employment_status'] = 'terminated';
        }
      },
    );
    expect(inGrid(find.text(h.t('staff.noEmployeesYet'))), findsOneWidget);
    expect(inGrid(find.byKey(const ValueKey('roster-table'))), findsNothing);
  });

  testWidgets('TEAM-SHF-028 no active block: "Create a work shift first"', (
    tester,
  ) async {
    final h = await pumpShifts(
      tester,
      edit: (db) {
        for (final s in db['work_shifts'].where(
          (r) => r['org_id'] == SeedIds.sabahOrg,
        )) {
          s['is_active'] = false;
        }
      },
    );
    expect(inGrid(find.text(h.t('staff.noShiftsToRoster'))), findsOneWidget);
    // The blocks themselves are still listed, muted.
    expect(shiftRow(_morning), findsOneWidget);
  });

  testWidgets('TEAM-SHF-029 the grid: Employee, Every day, then Saturday to '
      'Friday; own rows filled, inherited dashed, none "Rest"', (tester) async {
    await pumpShifts(
      tester,
      edit: (db) {
        karimRoster(db);
        // Older history for the same slot loses to the newest row.
        addRow(db, 'karim', _morning, dow: 6, from: '2026-08-01');
      },
    );
    final heads = [
      'Employee',
      'Every day',
      'Sat',
      'Sun',
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
    ];
    final table = find.byKey(const ValueKey('roster-table'));
    final xs = [
      for (final w in heads)
        tester
            .getTopLeft(
              find.descendant(of: table, matching: find.text(w)).first,
            )
            .dx,
    ];
    for (var i = 1; i < xs.length; i++) {
      expect(xs[i], greaterThan(xs[i - 1]), reason: heads[i]);
    }
    expect(inCell(null, find.text('Morning')), findsOneWidget);
    expect(rosterCell(tester, null).assignment, isNotNull);
    // Saturday's own row (the newest) beats the every-day one.
    expect(inCell(6, find.text('Evening')), findsOneWidget);
    expect(rosterCell(tester, 6).assignment!.effectiveFrom, '2026-09-01');
    // Monday only inherits the every-day row.
    expect(inCell(1, find.text('Morning')), findsOneWidget);
    expect(rosterCell(tester, 1).assignment, isNull);
    expect(rosterCell(tester, 1).inherited, isNotNull);
    // Someone with no row at all rests.
    final other = find.byKey(ValueKey('roster-${emp('nour')}-1'));
    expect(
      find.descendant(of: other, matching: find.text('Rest')),
      findsOneWidget,
    );
  });

  testWidgets('TEAM-SHF-030 a weekday cell offers only the blocks that run '
      'that day at their own branch, at that day\'s times', (tester) async {
    final h = await pumpShifts(tester, edit: karimRoster);
    // Friday: Brunch does not run, Maadi late is another branch's, Old
    // night is switched off.
    await openCell(h, 5);
    expect(find.text('Assign shift'), findsOneWidget);
    expect(menuItem(_morning), findsOneWidget);
    expect(menuItem(_evening), findsOneWidget);
    expect(menuLabel(tester, eveningZ), 'Late evening 16:00–01:00');
    expect(menuItem(brunch), findsNothing);
    expect(menuItem(maadiLate), findsNothing);
    expect(menuItem(oldNight), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
    expect(find.text('Assign shift'), findsNothing);
    // The every-day cell offers every block of theirs.
    await openCell(h, null);
    expect(menuLabel(tester, brunch), 'Brunch 10:00–14:00');
    expect(menuLabel(tester, eveningZ), 'Late evening 16:00–00:00');
    expect(menuItem(maadiLate), findsNothing);
  });

  testWidgets('TEAM-SHF-031 replacing a day: DELETE its row, then POST the '
      'block for that weekday; the cell shows it', (tester) async {
    final h = await pumpShifts(tester, edit: karimRoster);
    final own = rosterCell(tester, 6).assignment!;
    final reads = h.server.callsTo(rosterT).length;
    await openCell(h, 6);
    await h.tap(menuItem(eveningZ));
    final del = h.server.callsTo(rosterRowT, method: 'DELETE').single;
    expect(del.path, '/staff/schedules/${own.id}');
    final post = h.server.callsTo(rosterT, method: 'POST').single;
    expect(post.body, {
      'employee_id': emp('karim'),
      'work_shift_id': eveningZ,
      'day_of_week': 6,
    });
    expect(h.server.callsTo(rosterT, method: 'GET').length, reads + 1);
    expect(inCell(6, find.text('Late evening')), findsOneWidget);
  });

  testWidgets('TEAM-SHF-031 the every-day cell sends day_of_week null; an '
      'empty slot posts without deleting', (tester) async {
    final h = await pumpShifts(
      tester,
      edit: (db) {
        addDemoShifts(db);
        noRoster(db);
      },
    );
    await openCell(h, null);
    await h.tap(menuItem(brunch));
    expect(h.server.callsTo(rosterRowT, method: 'DELETE'), isEmpty);
    final post = h.server.callsTo(rosterT, method: 'POST').single;
    expect(post.body, containsPair('day_of_week', null));
    expect(inCell(null, find.text('Brunch')), findsOneWidget);
    // Every weekday Brunch runs on now inherits it; Friday rests.
    expect(inCell(1, find.text('Brunch')), findsOneWidget);
  });

  testWidgets('TEAM-SHF-031 a spinner in the cell while busy', (tester) async {
    final h = await pumpShifts(tester, edit: karimRoster);
    final gate = h.server.hold('POST', rosterT);
    await openCell(h, 6);
    await tester.tap(menuItem(eveningZ));
    await tester.pump();
    await tester.pump();
    expect(inCell(6, find.byType(CircularProgressIndicator)), findsOneWidget);
    expect(rosterCell(tester, 6).busy, isTrue);
    gate.release();
    await h.settle();
    expect(inCell(6, find.byType(CircularProgressIndicator)), findsNothing);
  });

  testWidgets('TEAM-SHF-031/TEAM-ALL-019 a refused replace: the coded words, '
      'and the roster is read again (the old row is already gone)', (
    tester,
  ) async {
    final h = await pumpShifts(tester, edit: karimRoster);
    final r = MockResponse.error(
      409,
      'Late evening on 2026-10-08 and Morning on 2026-10-09 overlap.',
      code: 'SHIFTS_OVERLAP',
      vars: {'a': 'Late evening', 'b': 'Morning', 'date': '2026-10-08'},
    );
    h.server.fail('POST', rosterT, r);
    final reads = h.server.callsTo(rosterT, method: 'GET').length;
    await openCell(h, 6);
    await h.tap(menuItem(eveningZ));
    expect(h.server.callsTo(rosterRowT, method: 'DELETE'), hasLength(1));
    expect(h.server.callsTo(rosterT, method: 'GET').length, reads + 1);
    // Saturday falls back to the every-day row.
    expect(inCell(6, find.text('Morning')), findsOneWidget);
    expect(rosterCell(tester, 6).assignment, isNull);
    // The date is worded by the coded-vars rules; the names lead.
    expect(
      textHas('Late evening and Morning would overlap on'),
      findsOneWidget,
    );
    await h.flushTimers();
  });

  testWidgets('TEAM-SHF-031 a manager refused by the server reads the '
      'refusal', (tester) async {
    final h = await pumpShifts(
      tester,
      persona: Persona.manager,
      edit: karimRoster,
    );
    final r = MockResponse.denied('hr.schedule.edit');
    h.server.fail('POST', rosterT, r);
    await openCell(h, 5);
    await h.tap(menuItem(_evening));
    // A 403 without a code reads as no right (TEAM-ALL-014).
    await h.expectToast(h.t('errors.unauthorized'));
  });

  testWidgets('TEAM-SHF-032 "Rest day" deletes the cell\'s own row', (
    tester,
  ) async {
    final h = await pumpShifts(tester, edit: karimRoster);
    final own = rosterCell(tester, 6).assignment!;
    await openCell(h, 6);
    await h.tap(menuItem('rest'));
    expect(
      h.server.callsTo(rosterRowT, method: 'DELETE').single.path,
      '/staff/schedules/${own.id}',
    );
    expect(h.server.callsTo(rosterT, method: 'POST'), isEmpty);
    expect(inCell(6, find.text('Morning')), findsOneWidget);
  });

  testWidgets('TEAM-SHF-032 "Rest day" is disabled on a cell that only '
      'inherits', (tester) async {
    final h = await pumpShifts(tester, edit: karimRoster);
    await openCell(h, 1);
    expect(tester.widget<DashPressable>(menuItem('rest')).enabled, isFalse);
    await tester.tap(menuItem('rest'), warnIfMissed: false);
    await h.settle();
    expect(h.server.callsTo(rosterRowT, method: 'DELETE'), isEmpty);
  });

  testWidgets('TEAM-SHF-033/TEAM-ALL-011 Arabic: translated, the week runs '
      'from Saturday (right to left)', (tester) async {
    final h = await pumpShifts(tester, locale: 'ar', edit: karimRoster);
    final table = find.byKey(const ValueKey('roster-table'));
    double x(String key) => tester
        .getTopRight(
          find.descendant(of: table, matching: find.text(h.t(key))).first,
        )
        .dx;
    expect(x('staff.employee'), greaterThan(x('staff.everyDay')));
    expect(x('staff.everyDay'), greaterThan(x('staff.sat')));
    expect(x('staff.sat'), greaterThan(x('staff.sun')));
    expect(x('staff.thu'), greaterThan(x('staff.fri')));
    expect(inGrid(find.text(h.t('staff.roster'))), findsOneWidget);
  });

  testWidgets('TEAM-SHF-033 phone: the grid scrolls sideways under a name '
      'column that stays put', (tester) async {
    await pumpShifts(tester, size: DashSize.phone, edit: karimRoster);
    final name = find.descendant(
      of: find.byKey(const ValueKey('roster-table')),
      matching: find.text('Karim Adel'),
    );
    await tester.ensureVisible(name);
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(name);
    final friday = tester.getTopLeft(cell('karim', 5)).dx;
    final sideways = find.descendant(
      of: find.byKey(const ValueKey('roster-table')),
      matching: find.byType(Scrollable),
    );
    await tester.drag(sideways.first, const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(name), before);
    expect(tester.getTopLeft(cell('karim', 5)).dx, lessThan(friday));
  });
}
