// The Work shift dialog (TEAM-SHF-011…024) and the input-kit behaviours it
// carries (TEAM-ALL-025), driven from the Work shifts page.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_team/src/shifts/shift_dialog.dart';
import 'package:dashboard_team/src/shifts/shift_inputs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shifts_support.dart';

Future<void> openNew(DashHarness h) =>
    h.tap(inPage(find.byKey(const ValueKey('shifts-new'))));

Future<void> openEdit(DashHarness h, String id) =>
    h.tap(inRow(id, find.bySemanticsLabel('Edit')));

Future<void> typeName(DashHarness h, String name) =>
    h.enterText(textNamed('Name'), name);

Future<void> tapSurfaceLabel(DashHarness h, String label) =>
    h.tap(inSurface(find.bySemanticsLabel(label)));

Finder switchNamed(String label) => inSurface(
  find.byWidgetPredicate((w) => w is DashSwitch && w.semanticLabel == label),
);

/// Picks [label] in the dialog's Branch select (currently showing [from]).
Future<void> pickBranch(DashHarness h, String from, String label) async {
  await h.tap(inSurface(find.text(from)));
  await h.tap(find.text(label).hitTestable().last);
}

Map<String, Object?> lastBody(DashHarness h, String method) =>
    (h.server.callsTo(method == 'POST' ? shiftsT : shiftT, method: method).last.body!
            as Map)
        .cast<String, Object?>();

Future<void> openSection(DashHarness h, String title) =>
    h.tap(inSurface(find.text(title)));

void main() {
  testWidgets('TEAM-SHF-011 New: title, description; the form starts over '
      'each time it opens', (tester) async {
    final h = await pumpShifts(tester);
    await openNew(h);
    expect(surfaceText('New shift'), findsOneWidget);
    expect(surfaceText(h.t('staff.shiftDialogHintV2')), findsOneWidget);
    expect(find.byKey(const ValueKey('shift-over-cap')), findsNothing);
    await h.shot('shifts/new-dialog');
    await typeName(h, 'Brunch');
    await h.tap(inSurface(find.text('Cancel')));
    expect(find.byType(WorkShiftDialog), findsNothing);
    await openNew(h);
    expect(shownIn(tester, textNamed('Name')), '');
  });

  testWidgets('TEAM-SHF-011 Edit: title, and a block already over the cap '
      'says so (a warning only)', (tester) async {
    final h = await pumpShifts(tester, edit: addDemoShifts);
    await openEdit(h, oldNight);
    expect(surfaceText('Edit work shift'), findsOneWidget);
    expect(find.byKey(const ValueKey('shift-over-cap')), findsOneWidget);
    expect(surfaceText(h.t('staff.overPresenceCap')), findsOneWidget);
    // Editing has no presets.
    expect(surfaceText(h.t('staff.startFrom')), findsNothing);
    await h.shot('shifts/edit-over-cap');
  });

  testWidgets('TEAM-SHF-012 presets: a pick sets both times and the name '
      'when empty or another preset\'s; the matching one shows pressed', (
    tester,
  ) async {
    final h = await pumpShifts(tester);
    await openNew(h);
    // The default 09:00–17:00 is the Day preset.
    bool pressed(String label) => tester
        .widget<DashPressable>(
          find.ancestor(
            of: surfaceText(label),
            matching: find.byType(DashPressable),
          ).first,
        )
        .checked!;
    expect(pressed('Day'), isTrue);
    expect(surfaceText('08:00 AM – 04:00 PM'), findsOneWidget);
    await h.tap(surfaceText('Evening'));
    expect(shownIn(tester, textNamed('Name')), 'Evening');
    expect(shownIn(tester, timeNamed('Start')), '04:00 PM');
    expect(shownIn(tester, timeNamed('End')), '12:00 AM');
    expect(pressed('Evening'), isTrue);
    expect(pressed('Day'), isFalse);
    await h.tap(surfaceText('Night'));
    expect(shownIn(tester, textNamed('Name')), 'Night');
    await typeName(h, 'Late bar');
    await h.tap(surfaceText('Morning'));
    expect(shownIn(tester, textNamed('Name')), 'Late bar');
    expect(shownIn(tester, timeNamed('Start')), '08:00 AM');
  });

  testWidgets('TEAM-SHF-013/023 a nameless save is refused out loud: the '
      'field says why, a toast says so, nothing is sent', (tester) async {
    final h = await pumpShifts(tester);
    await openNew(h);
    expect(surfaceText('e.g. Morning, Evening'), findsOneWidget);
    await h.tap(save());
    expect(surfaceText('Give the shift a name'), findsOneWidget);
    await h.expectToast(h.t('staff.fixShiftErrors'));
    expect(h.server.callsTo(shiftsT, method: 'POST'), isEmpty);
    // Re-checked on change once Save was pressed.
    await typeName(h, 'Brunch');
    expect(surfaceText('Give the shift a name'), findsNothing);
  });

  testWidgets('TEAM-SHF-014 Branch: "Every branch" then every branch, the '
      'hint; a pick is sent as its id', (tester) async {
    final h = await pumpShifts(tester);
    await openNew(h);
    expect(surfaceText(h.t('staff.shiftBranchHint')), findsOneWidget);
    await h.tap(inSurface(find.text('Every branch')));
    for (final b in ['Heliopolis', 'Maadi', 'New Cairo', 'Zamalek']) {
      expect(find.text(b).hitTestable(), findsWidgets, reason: b);
    }
    await h.tap(find.text('Maadi').hitTestable().last);
    await typeName(h, 'Brunch');
    await h.tap(save());
    expect(lastBody(h, 'POST')['branch_id'], SeedIds.maadi);
    await h.flushTimers();
  });

  testWidgets('TEAM-SHF-014/038 without the right everywhere a new block '
      'starts at the first branch, "Every branch" not offered', (tester) async {
    final s = shiftsServer();
    answerAuthz(
      s.server,
      const ['hr.schedule.read', 'hr.schedule.edit', 'hr.schedule.create'],
      everywhere: const ['hr.schedule.read'],
    );
    final h = await pumpShifts(tester, s: s);
    await openNew(h);
    expect(surfaceText('Every branch'), findsNothing);
    await h.tap(inSurface(find.text('Heliopolis')));
    expect(find.text('Every branch'), findsNothing);
    await h.tap(find.text('Heliopolis').hitTestable().last);
    await typeName(h, 'Brunch');
    await h.tap(save());
    expect(lastBody(h, 'POST')['branch_id'], SeedIds.heliopolis);
    await h.flushTimers();
  });

  testWidgets('TEAM-SHF-014 a business-wide block keeps "Every branch" '
      'offered to its editor', (tester) async {
    final h = await pumpShifts(tester, edit: addDemoShifts);
    await openEdit(h, brunch);
    expect(surfaceText('Every branch'), findsOneWidget);
  });

  testWidgets('TEAM-SHF-015/TEAM-ALL-025 times: an end before the start '
      'ends the next day; same start and end is refused; unreadable text '
      'says so and the save refuses it', (tester) async {
    final h = await pumpShifts(tester);
    await openNew(h);
    await typeName(h, 'Late');
    expect(surfaceText('8 h'), findsOneWidget);
    await typeIn(h, timeNamed('Start'), '22:00');
    await typeIn(h, timeNamed('End'), '6');
    expect(surfaceText('8 h'), findsOneWidget);
    expect(surfaceText('Ends the next day'), findsOneWidget);
    await typeIn(h, timeNamed('End'), '10pm');
    expect(surfaceText(h.t('inputs.sameTime')), findsOneWidget);
    await h.tap(save());
    expect(
      surfaceText("A shift can't start and end at the same time"),
      findsOneWidget,
    );
    await h.flushTimers();
    await typeIn(h, timeNamed('Start'), '9x');
    expect(
      surfaceText(h.t('inputs.timeUnreadable', args: {'text': '9x'})),
      findsOneWidget,
    );
    expect(surfaceText('Pick a time'), findsOneWidget);
    await h.tap(save());
    expect(h.server.callsTo(shiftsT, method: 'POST'), isEmpty);
    await h.flushTimers();
  });

  testWidgets('TEAM-ALL-025 the "9 to 5" slip: a one-tap fix', (tester) async {
    final h = await pumpShifts(tester);
    await openNew(h);
    await typeIn(h, timeNamed('End'), '5');
    expect(surfaceText("That's 20 h, overnight."), findsOneWidget);
    await h.tap(surfaceText('End at 05:00 PM instead'));
    expect(shownIn(tester, timeNamed('End')), '05:00 PM');
    expect(surfaceText("That's 20 h, overnight."), findsNothing);
  });

  testWidgets('TEAM-SHF-016/TEAM-ALL-011/025 days it runs: Saturday first, '
      'shortcuts, at least one day', (tester) async {
    final h = await pumpShifts(tester);
    await openNew(h);
    final chips = tester
        .widgetList<DashPressable>(
          find.descendant(
            of: find.byType(ShiftWeekdayPicker),
            matching: find.byType(DashPressable),
          ),
        )
        .map((p) => p.semanticLabel)
        .toList();
    expect(chips.take(7), [
      'Saturday',
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
    ]);
    // "Every day" is off with all seven on.
    final every = find.descendant(
      of: find.byType(ShiftWeekdayPicker),
      matching: find.widgetWithText(DashButton, 'Every day'),
    );
    expect(tester.widget<DashButton>(every).onPressed, isNull);
    await h.tap(
      find.descendant(
        of: find.byType(ShiftWeekdayPicker),
        matching: find.widgetWithText(DashButton, 'Clear'),
      ),
    );
    await typeName(h, 'Day');
    await h.tap(save());
    expect(surfaceText('Pick at least one day'), findsOneWidget);
    expect(h.server.callsTo(shiftsT, method: 'POST'), isEmpty);
    await h.flushTimers();
    await h.tap(every);
    await tapSurfaceLabel(h, 'Friday');
    await h.tap(save());
    expect(lastBody(h, 'POST')['valid_days'], [0, 1, 2, 3, 4, 6]);
    await h.flushTimers();
  });

  testWidgets('TEAM-SHF-017 own times on some days: summary, one range per '
      'valid day, a half-set day refused, only full days sent', (
    tester,
  ) async {
    final h = await pumpShifts(tester);
    await openNew(h);
    await typeName(h, 'Day');
    expect(surfaceText(h.t('staff.dayTimesNone')), findsOneWidget);
    await tapSurfaceLabel(h, 'Friday');
    await openSection(h, 'Its own times on some days');
    expect(surfaceText(h.t('staff.dayTimesHintV2')), findsOneWidget);
    expect(timeNamed('Fri start'), findsNothing);
    expect(timeNamed('Sat start'), findsOneWidget);
    await typeIn(h, timeNamed('Mon start'), '09:00');
    await h.tap(save());
    expect(surfaceText('Set both times, or neither'), findsOneWidget);
    expect(h.server.callsTo(shiftsT, method: 'POST'), isEmpty);
    await h.flushTimers();
    await typeIn(h, timeNamed('Mon start'), '');
    await typeIn(h, timeNamed('Thu start'), '16:00');
    await typeIn(h, timeNamed('Thu end'), '01:00');
    expect(surfaceText('Different on Thu'), findsOneWidget);
    await h.shot('shifts/day-times');
    await h.tap(save());
    expect(lastBody(h, 'POST')['day_times'], [
      {'day_of_week': 4, 'start_time': '16:00:00', 'end_time': '01:00:00'},
    ]);
    await h.flushTimers();
  });

  testWidgets('TEAM-SHF-023 an invalid save opens the section holding the '
      'problem', (tester) async {
    final h = await pumpShifts(tester, edit: addDemoShifts);
    await openEdit(h, brunch);
    expect(surfaceText(h.t('staff.otThreshold')), findsNothing);
    expect(timeNamed('Sat start'), findsNothing);
    await typeIn(h, numberNamed('Grace before late'), 'abc');
    await h.tap(save());
    expect(surfaceText('Type a number'), findsOneWidget);
    await h.flushTimers();
    // A problem inside "Overtime and check-in" opens it.
    await typeIn(h, numberNamed('Grace before late'), '5');
    await openSection(h, 'Overtime and check-in');
    await typeIn(h, numberNamed('Overtime multiplier'), '0');
    await openSection(h, 'Overtime and check-in');
    expect(surfaceText(h.t('staff.otThreshold')), findsNothing);
    await h.tap(save());
    expect(surfaceText(h.t('staff.otThreshold')), findsOneWidget);
    expect(surfaceText('Must be above 0'), findsOneWidget);
    await h.expectToast(h.t('staff.fixShiftErrors'));
    expect(h.server.callsTo(shiftT, method: 'PATCH'), isEmpty);
  });

  testWidgets('TEAM-SHF-018/TEAM-ALL-025 grace and break: presets, steppers, '
      'minutes past an hour read as hours, a refused number never sent', (
    tester,
  ) async {
    final h = await pumpShifts(tester);
    await openNew(h);
    await typeName(h, 'Day');
    expect(surfaceText(h.t('staff.graceHint')), findsOneWidget);
    await h.tap(surfaceText('30 min').first);
    await h.tap(surfaceText('1 h'));
    expect(surfaceText('= 1 h'), findsOneWidget);
    await typeIn(h, numberNamed('Break'), '90');
    expect(surfaceText('= 1 h 30 min'), findsOneWidget);
    await typeIn(h, numberNamed('Break'), 'x');
    expect(surfaceText(h.t('staff.errNumber')), findsNothing);
    await h.tap(save());
    expect(surfaceText('Type a number'), findsOneWidget);
    await h.flushTimers();
    await typeIn(h, numberNamed('Break'), '45');
    await h.tap(save());
    final body = lastBody(h, 'POST');
    expect((body['grace_minutes'], body['break_minutes']), (30, 45));
    await h.flushTimers();
  });

  testWidgets('TEAM-SHF-019/021 Paid break and Active switches', (
    tester,
  ) async {
    final h = await pumpShifts(tester);
    await openNew(h);
    await typeName(h, 'Day');
    expect(surfaceText(h.t('staff.paidBreakHint')), findsOneWidget);
    expect(surfaceText(h.t('staff.activeShiftHint')), findsOneWidget);
    await h.tap(switchNamed('Paid break'));
    await h.tap(switchNamed('Active'));
    await h.tap(save());
    final body = lastBody(h, 'POST');
    expect((body['paid_break'], body['is_active']), (false, false));
    await h.flushTimers();
  });

  testWidgets('TEAM-SHF-020 overtime and check-in: closed until opened; '
      'empty rates read "Branch rules"; rates typed are sent', (tester) async {
    final h = await pumpShifts(tester);
    await openNew(h);
    await typeName(h, 'Day');
    expect(surfaceText(h.t('staff.moreShiftSettingsHint')), findsOneWidget);
    await openSection(h, 'Overtime and check-in');
    expect(surfaceText(h.t('staff.otThresholdHint')), findsOneWidget);
    expect(surfaceText("Empty = the branch's rules."), findsNWidgets(2));
    expect(surfaceText('Branch rules'), findsNWidgets(2));
    expect(surfaceText('Half the shift'), findsOneWidget);
    await h.shot('shifts/more-open');
    await typeIn(h, numberNamed('Day overtime rate'), '1.75');
    await typeIn(h, numberNamed('Half day below (minutes)'), '240');
    await h.tap(surfaceText('1 h'));
    await h.tap(save());
    final body = lastBody(h, 'POST');
    expect(body['ot_day_multiplier'], 1.75);
    expect(body['ot_night_multiplier'], isNull);
    expect(body.containsKey('ot_night_multiplier'), isTrue);
    expect(body['half_day_threshold_minutes'], 240);
    expect(body['checkin_window_minutes'], 60);
    expect(body['overtime_multiplier'], 1.5);
    await h.flushTimers();
  });

  testWidgets('TEAM-SHF-020 a block with its own rates opens the section, '
      'and clearing the night rate sends null', (tester) async {
    final h = await pumpShifts(tester, edit: addDemoShifts);
    await openEdit(h, eveningZ);
    expect(surfaceText(h.t('staff.otThreshold')), findsOneWidget);
    // Its own times opened too.
    expect(shownIn(tester, timeNamed('Thu end')), '01:00 AM');
    await typeIn(h, numberNamed('Night overtime rate'), '');
    await h.tap(save());
    final call = h.server.callsTo(shiftT, method: 'PATCH').single;
    expect(call.path, '/staff/work-shifts/$eveningZ');
    final body = (call.body! as Map).cast<String, Object?>();
    expect(body['ot_day_multiplier'], 1.75);
    expect(body['ot_night_multiplier'], isNull);
    expect(body.containsKey('ot_night_multiplier'), isTrue);
    expect(body['valid_days'], [0, 1, 2, 3, 4, 5, 6]);
    await h.expectToast('Work shift saved');
    expect(h.db!['work_shifts'].find(eveningZ)!['ot_night_multiplier'], isNull);
  });

  testWidgets('TEAM-SHF-022/024 a new block straight from its defaults: '
      'POST with the defaults, toast, closed, the list shows it', (
    tester,
  ) async {
    final h = await pumpShifts(tester);
    final lists = h.server.callsTo(shiftsT).length;
    final roster = h.server.callsTo(rosterT).length;
    await openNew(h);
    expect(shownIn(tester, timeNamed('Start')), '09:00 AM');
    expect(shownIn(tester, timeNamed('End')), '05:00 PM');
    await typeName(h, 'Day');
    await h.tap(save());
    final body = lastBody(h, 'POST');
    expect(body, {
      'branch_id': null,
      'name': 'Day',
      'start_time': '09:00:00',
      'end_time': '17:00:00',
      'grace_minutes': 15,
      'break_minutes': 0,
      'paid_break': true,
      'half_day_threshold_minutes': null,
      'overtime_threshold_minutes': 15,
      'overtime_multiplier': 1.5,
      'ot_day_multiplier': null,
      'ot_night_multiplier': null,
      'checkin_window_minutes': 120,
      'is_active': true,
      'valid_days': [0, 1, 2, 3, 4, 5, 6],
      'day_times': <Object?>[],
    });
    await h.expectToast('Work shift saved');
    expect(find.byType(WorkShiftDialog), findsNothing);
    expect(pageText('Day'), findsOneWidget);
    // invalidateStaff: the list and the roster read again.
    expect(h.server.callsTo(shiftsT).length, lists + 1);
    expect(h.server.callsTo(rosterT).length, roster + 1);
  });

  testWidgets('TEAM-SHF-024 the web test: a branch\'s block on some days '
      'with its own Thursday times and a day rate', (tester) async {
    final h = await pumpShifts(tester);
    await openNew(h);
    await typeName(h, 'Evening');
    await typeIn(h, timeNamed('Start'), '16:00');
    await typeIn(h, timeNamed('End'), '00:00');
    expect(surfaceText('Ends the next day'), findsOneWidget);
    await pickBranch(h, 'Every branch', 'Zamalek');
    await tapSurfaceLabel(h, 'Friday');
    await openSection(h, 'Its own times on some days');
    expect(timeNamed('Fri start'), findsNothing);
    await typeIn(h, timeNamed('Thu start'), '16:00');
    await typeIn(h, timeNamed('Thu end'), '01:00');
    await openSection(h, 'Overtime and check-in');
    await typeIn(h, numberNamed('Day overtime rate'), '1.75');
    await h.tap(save());
    final body = lastBody(h, 'POST');
    expect(body['branch_id'], SeedIds.zamalek);
    expect(body['name'], 'Evening');
    expect((body['start_time'], body['end_time']), ('16:00:00', '00:00:00'));
    expect(body['valid_days'], [0, 1, 2, 3, 4, 6]);
    expect(body['day_times'], [
      {'day_of_week': 4, 'start_time': '16:00:00', 'end_time': '01:00:00'},
    ]);
    expect(body['ot_day_multiplier'], 1.75);
    expect(body['ot_night_multiplier'], isNull);
    await h.expectToast('Work shift saved');
  });

  testWidgets('TEAM-SHF-024 past the presence cap: saved, and warned', (
    tester,
  ) async {
    final h = await pumpShifts(tester);
    await openNew(h);
    await typeName(h, 'Double');
    await typeIn(h, timeNamed('Start'), '06:00');
    await typeIn(h, timeNamed('End'), '22:00');
    await h.tap(save());
    expect(h.server.callsTo(shiftsT, method: 'POST').single.status, 201);
    expect(find.text('Work shift saved'), findsOneWidget);
    await h.expectToast(h.t('staff.overPresenceCap'));
    expect(find.byType(WorkShiftDialog), findsNothing);
  });

  testWidgets('TEAM-SHF-024/TEAM-ALL-019 taking away a rostered day: the '
      'named refusal, the dialog stays open', (tester) async {
    final h = await pumpShifts(tester);
    await openEdit(h, sabahShift('morning'));
    await tapSurfaceLabel(h, 'Friday');
    await h.tap(save());
    final call = h.server.callsTo(shiftT, method: 'PATCH').single;
    expect(call.status, 409);
    final n = h.db!['schedule_assignments']
        .where(
          (a) =>
              a['work_shift_id'] == sabahShift('morning') &&
              a['day_of_week'] == 5,
        )
        .length;
    expect(n, greaterThan(0));
    await h.expectToast(
      h.t(
        'errors.codes.SHIFT_DAYS_IN_USE_named',
        args: {'name': 'Morning', 'days': 'Fri'},
      ),
    );
    expect(find.byType(WorkShiftDialog), findsOneWidget);
    expect(
      tester.widget<DashButton>(save()).loading,
      isFalse,
    );
  });

  testWidgets('TEAM-ALL-019 a refused number names the field by its label', (
    tester,
  ) async {
    final s = shiftsServer();
    s.server.fail(
      'POST',
      shiftsT,
      MockResponse.error(
        400,
        'checkin_window_minutes must be positive',
        code: 'SHIFT_SETTING_INVALID',
        vars: {'field': 'checkin_window_minutes'},
      ),
    );
    final h = await pumpShifts(tester, s: s);
    await openNew(h);
    await typeName(h, 'Day');
    await h.tap(save());
    await h.expectToast(
      h.t(
        'errors.codes.SHIFT_SETTING_INVALID',
        args: {'field': h.t('staff.checkinWindow')},
      ),
    );
  });

  testWidgets('TEAM-SHF-024 Save shows its spinner while busy; a manager '
      'saving a business-wide block is refused in words', (tester) async {
    final s = shiftsServer();
    final gate = s.server.hold('POST', shiftsT);
    final h = await pumpShifts(tester, s: s);
    await openNew(h);
    await typeName(h, 'Day');
    await h.tap(save());
    expect(tester.widget<DashButton>(save()).loading, isTrue);
    gate.release();
    await h.settle();
    await h.expectToast('Work shift saved');
  });

  testWidgets('TEAM-SHF-024 a refusal from the server for the whole '
      'business: the dialog stays, its words toast', (tester) async {
    final s = shiftsServer();
    answerAuthz(
      s.server,
      const ['hr.schedule.read', 'hr.schedule.edit', 'hr.schedule.create'],
    );
    final h = await pumpShifts(tester, persona: Persona.manager, s: s);
    // The client was told "everywhere", the server knows better.
    s.server.fail(
      'POST',
      shiftsT,
      MockResponse.forbidden(
        'This needs Add shifts to the roster for every branch '
        '(hr.schedule.create).',
      ),
    );
    await openNew(h);
    await typeName(h, 'Day');
    await h.tap(save());
    await h.expectToast(h.t('errors.unauthorized'));
    expect(find.byType(WorkShiftDialog), findsOneWidget);
  });

  testWidgets('TEAM-SHF-011 (re-seed) a refresh that lands before any edit '
      'refreshes the form; after an edit it does not', (tester) async {
    final h = await pumpShifts(tester, edit: addDemoShifts);
    await openEdit(h, brunch);
    expect(shownIn(tester, textNamed('Name')), 'Brunch');
    h.db!['work_shifts'].update(brunch, {'name': 'Late brunch'});
    h.server.clock.advance(const Duration(seconds: 31));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await h.settle();
    expect(shownIn(tester, textNamed('Name')), 'Late brunch');
    await typeIn(h, numberNamed('Grace before late'), '20');
    h.db!['work_shifts'].update(brunch, {'name': 'Brunch again'});
    h.server.clock.advance(const Duration(seconds: 31));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await h.settle();
    expect(shownIn(tester, textNamed('Name')), 'Late brunch');
  });

  testWidgets('TEAM-SHF-033 Arabic: the dialog\'s words, the week from '
      'Saturday, times on ص/م with Latin digits', (tester) async {
    final h = await pumpShifts(tester, locale: 'ar');
    await h.tap(inPage(find.byKey(const ValueKey('shifts-new'))));
    expect(surfaceText('وردية جديدة'), findsWidgets);
    expect(
      find.descendant(
        of: find.byType(ShiftWeekdayPicker),
        matching: find.bySemanticsLabel('الجمعة'),
      ),
      findsOneWidget,
    );
    expect(shownIn(tester, timeNamed('البداية')), '09:00 ص');
    await openSection(h, 'الإضافي وتسجيل الحضور');
    expect(numberNamed('معدل الإضافي الليلي'), findsOneWidget);
    await h.shot('shifts/new-dialog');
  });

  testWidgets('phone: the dialog is a full-screen sheet', (tester) async {
    final h = await pumpShifts(tester, size: DashSize.phone);
    await h.tap(inPage(find.byKey(const ValueKey('shifts-new'))));
    expect(
      tester.widget<DashSurfaceScope>(find.byType(DashSurfaceScope).last).mode,
      DashSurfaceMode.fullScreen,
    );
    await h.shot('shifts/new-dialog');
  });
}
