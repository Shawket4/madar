// Work shifts (`/staff/shifts`): the page, its list of blocks and their row
// actions (TEAM-SHF-001…010) and the area-wide rows that land on it.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/shell.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_team/src/shifts/shift_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shifts_support.dart';

void main() {
  testWidgets('TEAM-SHF-001 header: title, description, Refresh and New '
      'shift for someone who may create', (tester) async {
    final h = await pumpShifts(tester);
    expect(pageText('Work shifts'), findsWidgets);
    expect(pageText(h.t('staff.workShiftsSubtitle')), findsOneWidget);
    expect(inPage(find.bySemanticsLabel('Refresh')), findsOneWidget);
    expect(inPage(find.byKey(const ValueKey('shifts-new'))), findsOneWidget);
    await h.shot('shifts/default');
  });

  testWidgets('TEAM-SHF-001 a branch manager is not offered New', (
    tester,
  ) async {
    await pumpShifts(tester, persona: Persona.manager);
    expect(pageText('New shift'), findsNothing);
    expect(inPage(find.bySemanticsLabel('Refresh')), findsOneWidget);
  });

  testWidgets('TEAM-SHF-002 the section counts the blocks', (tester) async {
    final h = await pumpShifts(tester, edit: addDemoShifts);
    final header = find.ancestor(
      of: pageText(h.t('staff.shiftsSection')),
      matching: find.byType(DashSectionHeader),
    );
    expect(tester.widget<DashSectionHeader>(header.first).count, 6);
    expect(h.server.callsTo(shiftsT).length, 1);
    expect(h.server.callsTo(shiftsT).single.query, isEmpty);
  });

  testWidgets('TEAM-SHF-003 loading: three skeleton rows, no count', (
    tester,
  ) async {
    final s = shiftsServer();
    final gate = s.server.hold('GET', shiftsT);
    final h = await pumpShifts(tester, s: s);
    expect(inPage(find.byKey(const ValueKey('shifts-loading'))), findsOneWidget);
    expect(pageText(h.t('staff.noShifts')), findsNothing);
    // The grid waits for the shift list too: never "nothing to assign".
    expect(find.byKey(const ValueKey('roster-loading')), findsOneWidget);
    expect(inGrid(find.text(h.t('staff.noShiftsToRoster'))), findsNothing);
    final header = find.ancestor(
      of: pageText(h.t('staff.shiftsSection')),
      matching: find.byType(DashSectionHeader),
    );
    expect(tester.widget<DashSectionHeader>(header.first).count, isNull);
    await h.shot('shifts/loading');
    gate.release();
    await h.settle();
    expect(shiftRow(sabahShift('morning')), findsOneWidget);
  });

  testWidgets('TEAM-SHF-004 error: the words and Retry, which asks again '
      'only the list', (tester) async {
    final s = shiftsServer();
    s.server.fail('GET', shiftsT, MockResponse.error(500, 'boom'), times: 1);
    final h = await pumpShifts(tester, s: s);
    expect(pageText(h.t('staff.shiftsLoadError')), findsOneWidget);
    final header = find.ancestor(
      of: pageText(h.t('staff.shiftsSection')),
      matching: find.byType(DashSectionHeader),
    );
    expect(tester.widget<DashSectionHeader>(header.first).count, isNull);
    await h.shot('shifts/error');
    final roster = h.server.callsTo(rosterT).length;
    await h.tap(
      find.descendant(
        of: find.byKey(const ValueKey('shifts-error')),
        matching: find.text('Retry'),
      ),
    );
    expect(h.server.callsTo(shiftsT).length, 2);
    expect(h.server.callsTo(rosterT).length, roster);
    expect(shiftRow(sabahShift('morning')), findsOneWidget);
  });

  testWidgets('TEAM-SHF-005 empty with create: the hint and New shift', (
    tester,
  ) async {
    final h = await pumpShifts(
      tester,
      edit: (db) => db['work_shifts'].removeWhere(
        (w) => w['org_id'] == SeedIds.sabahOrg,
      ),
    );
    expect(pageText(h.t('staff.noShifts')), findsOneWidget);
    expect(pageText(h.t('staff.noShiftsHintV2')), findsOneWidget);
    final empty = find.byKey(const ValueKey('shifts-empty'));
    expect(
      find.descendant(of: empty, matching: find.text('New shift')),
      findsOneWidget,
    );
    await h.shot('shifts/empty');
    await h.tap(find.descendant(of: empty, matching: find.text('New shift')));
    expect(surfaceText('New shift'), findsWidgets);
  });

  testWidgets('TEAM-SHF-005 empty without create: ask the owner', (
    tester,
  ) async {
    final h = await pumpShifts(
      tester,
      persona: Persona.manager,
      edit: (db) => db['work_shifts'].removeWhere(
        (w) => w['org_id'] == SeedIds.sabahOrg,
      ),
    );
    expect(pageText(h.t('staff.noShiftsNoAccess')), findsOneWidget);
    expect(pageText('New shift'), findsNothing);
  });

  testWidgets('TEAM-SHF-006 a row: glyph, times, length, next day, grace, '
      'OT, branch, days, own times', (tester) async {
    final h = await pumpShifts(tester, edit: addDemoShifts);
    final row = tester.widget<DashListRow>(
      find.descendant(
        of: shiftRow(eveningZ),
        matching: find.byType(DashListRow),
      ),
    );
    expect(row.title, 'Late evening');
    expect(row.icon, 'moon');
    expect(
      row.meta,
      '\u206804:00 PM – 12:00 AM\u2069 (8 h) · Ends the next day · '
      '15 min grace · OT ×1.5 · Zamalek · Every day · own times on 2 days',
    );
    final b = tester.widget<DashListRow>(
      find.descendant(of: shiftRow(brunch), matching: find.byType(DashListRow)),
    );
    expect(b.icon, 'clock');
    expect(
      b.meta,
      '\u206810:00 AM – 02:00 PM\u2069 (4 h) · 5 min grace · OT ×1.5 · '
      'Every branch · Sat – Thu',
    );
    expect(h.server.callsTo(shiftsT).length, 1);
  });

  testWidgets('TEAM-SHF-007 an inactive block reads muted with "Inactive"; '
      'over the presence cap a warning pill', (tester) async {
    await pumpShifts(tester, edit: addDemoShifts);
    final row = tester.widget<DashListRow>(
      find.descendant(of: shiftRow(oldNight), matching: find.byType(DashListRow)),
    );
    expect(row.enabled, isFalse);
    expect(inRow(oldNight, find.text('Inactive')), findsOneWidget);
    expect(inRow(oldNight, find.text('Over the presence limit')), findsOneWidget);
    expect(inRow(eveningZ, find.text('Inactive')), findsNothing);
    expect(inRow(eveningZ, find.text('Over the presence limit')), findsNothing);
  });

  testWidgets('TEAM-SHF-008 Edit: a branch\'s block with hr.schedule.edit; a '
      'business-wide one only for a manager without the right everywhere '
      'not', (tester) async {
    await pumpShifts(tester, persona: Persona.manager, edit: addDemoShifts);
    // The manager sees Zamalek's blocks and the business's, not Maadi's.
    expect(shiftRow(maadiLate), findsNothing);
    expect(inRow(eveningZ, find.bySemanticsLabel('Edit')), findsOneWidget);
    expect(inRow(brunch, find.bySemanticsLabel('Edit')), findsNothing);
    expect(inRow(sabahShift('morning'), find.bySemanticsLabel('Edit')), findsNothing);
    // No delete for a manager.
    expect(inPage(find.bySemanticsLabel('Delete work shift')), findsNothing);
  });

  testWidgets('TEAM-SHF-008/009 the rights at one branch only: that '
      'branch\'s block is theirs, a business-wide one is not', (tester) async {
    final s = shiftsServer(edit: addDemoShifts);
    answerAuthz(
      s.server,
      const [
        'hr.schedule.read',
        'hr.schedule.edit',
        'hr.schedule.create',
        'hr.schedule.delete',
      ],
      everywhere: const ['hr.schedule.read'],
    );
    final h = await pumpShifts(tester, s: s);
    expect(inRow(eveningZ, find.bySemanticsLabel('Edit')), findsOneWidget);
    expect(inRow(eveningZ, find.bySemanticsLabel('Delete work shift')), findsOneWidget);
    expect(inRow(brunch, find.bySemanticsLabel('Edit')), findsNothing);
    expect(inRow(brunch, find.bySemanticsLabel('Delete work shift')), findsNothing);
    // A new block is their branch's: "Every branch" is not offered.
    await h.tap(inPage(find.byKey(const ValueKey('shifts-new'))));
    await h.tap(inSurface(find.text('Heliopolis')));
    expect(find.text('Every branch'), findsNothing);
  });

  testWidgets('TEAM-SHF-008 the owner edits any block; Edit opens the '
      'dialog with the shift and "Every branch" offered', (tester) async {
    final h = await pumpShifts(tester, edit: addDemoShifts);
    await h.tap(inRow(brunch, find.bySemanticsLabel('Edit')));
    expect(surfaceText('Edit work shift'), findsOneWidget);
    final dialog = tester.widget<WorkShiftDialog>(find.byType(WorkShiftDialog));
    expect(dialog.shift!.id, brunch);
    expect(dialog.wholeBusiness, isTrue);
    expect(surfaceText('Every branch'), findsOneWidget);
  });

  testWidgets('TEAM-SHF-009 Delete: confirm, DELETE, toast, the list '
      'refreshes', (tester) async {
    final h = await pumpShifts(
      tester,
      edit: (db) {
        addDemoShifts(db);
        noRoster(db);
      },
    );
    final lists = h.server.callsTo(shiftsT).length;
    final rosters = h.server.callsTo(rosterT).length;
    await h.tap(inRow(brunch, find.bySemanticsLabel('Delete work shift')));
    expect(confirmText('Delete the Brunch shift?'), findsOneWidget);
    expect(confirmText(h.t('staff.deleteShiftHint')), findsOneWidget);
    await h.shot('shifts/delete-confirm');
    await h.tap(confirmText('Delete'));
    expect(h.server.callsTo(shiftT, method: 'DELETE').single.path,
        '/staff/work-shifts/$brunch');
    await h.expectToast('Work shift deleted');
    expect(shiftRow(brunch), findsNothing);
    // invalidateStaff: the list and the roster read again.
    expect(h.server.callsTo(shiftsT).length, lists + 1);
    expect(h.server.callsTo(rosterT).length, rosters + 1);
  });

  testWidgets('TEAM-SHF-009 Cancel sends nothing', (tester) async {
    final h = await pumpShifts(tester, edit: addDemoShifts);
    await h.tap(inRow(brunch, find.bySemanticsLabel('Delete work shift')));
    await h.tap(confirmText('Cancel'));
    expect(h.server.callsTo(shiftT, method: 'DELETE'), isEmpty);
    expect(shiftRow(brunch), findsOneWidget);
  });

  testWidgets('TEAM-SHF-009/TEAM-ALL-014 a block still rostered: the coded '
      'refusal in the person\'s words, nothing removed', (tester) async {
    final h = await pumpShifts(tester);
    await h.tap(
      inRow(sabahShift('morning'), find.bySemanticsLabel('Delete work shift')),
    );
    await h.tap(confirmText('Delete'));
    final res = h.server.callsTo(shiftT, method: 'DELETE').single;
    expect(res.status, 409);
    final n = h.db![
      'schedule_assignments'
    ].where((a) => a['work_shift_id'] == sabahShift('morning')).length;
    await h.expectToast(
      h.t('errors.codes.SHIFT_IN_USE', args: {'n': n, 'name': 'Morning'}),
    );
    expect(shiftRow(sabahShift('morning')), findsOneWidget);
  });

  testWidgets('TEAM-SHF-009 a refusal without a code reads as no right', (
    tester,
  ) async {
    final s = shiftsServer(
      edit: (db) {
        addDemoShifts(db);
        noRoster(db);
      },
    );
    s.server.fail(
      'DELETE',
      shiftT,
      MockResponse.denied('hr.schedule.delete'),
    );
    final h = await pumpShifts(tester, s: s);
    await h.tap(inRow(brunch, find.bySemanticsLabel('Delete work shift')));
    await h.tap(confirmText('Delete'));
    await h.expectToast(h.t('errors.unauthorized'));
  });

  testWidgets('TEAM-SHF-010 New shift opens the dialog for a new block; '
      '"Every branch" follows the right everywhere', (tester) async {
    final h = await pumpShifts(tester);
    await h.tap(inPage(find.byKey(const ValueKey('shifts-new'))));
    final dialog = tester.widget<WorkShiftDialog>(find.byType(WorkShiftDialog));
    expect(dialog.shift, isNull);
    expect(dialog.wholeBusiness, isTrue);
    expect(surfaceText('Every branch'), findsOneWidget);
    expect(surfaceText(h.t('staff.startFrom')), findsOneWidget);
  });

  // ── area-wide rows on this page ─────────────────────────────────────────

  testWidgets('TEAM-ALL-001/002 the Work shifts leaf shows with '
      'hr.schedule.read, hidden without', (tester) async {
    var h = await pumpShifts(tester);
    expect(
      find.descendant(
        of: find.byType(DashSidebar),
        matching: find.text('Work shifts'),
      ),
      findsOneWidget,
    );
    h = await pumpShifts(tester, persona: Persona.limited);
    expect(
      find.descendant(
        of: find.byType(DashSidebar),
        matching: find.text('Work shifts'),
      ),
      findsNothing,
    );
    expect(h.location.path, shiftsPath);
  });

  testWidgets('TEAM-ALL-005 module off: the module refusal, nothing asked', (
    tester,
  ) async {
    final s = shiftsServer(
      edit: (db) => db['orgs'].update(SeedIds.sabahOrg, {
        'modules': ['pos'],
      }),
    );
    final h = await pumpShifts(tester, s: s);
    expect(find.text(h.t('dawam.moduleOffTitle')), findsOneWidget);
    expect(page, findsNothing);
    expect(h.server.callsTo(rosterT), isEmpty);
  });

  testWidgets('TEAM-ALL-007 no in-page guard: without hr.schedule.read the '
      'lists say their refusals', (tester) async {
    final h = await pumpShifts(tester, persona: Persona.limited);
    expect(pageText('Work shifts'), findsWidgets);
    expect(pageText(h.t('staff.shiftsLoadError')), findsOneWidget);
    expect(pageText(h.t('staff.rosterLoadError')), findsOneWidget);
    expect(h.server.callsTo(shiftsT).last.status, 403);
    expect(pageText('New shift'), findsNothing);
  });

  testWidgets('TEAM-ALL-008 Refresh refetches the page\'s reads and spins '
      'while they are in flight', (tester) async {
    final h = await pumpShifts(tester);
    final shifts = h.server.callsTo(shiftsT).length;
    final roster = h.server.callsTo(rosterT).length;
    final gate = h.server.hold('GET', rosterT);
    await h.tap(inPage(find.bySemanticsLabel('Refresh')));
    expect(inPage(find.bySemanticsLabel('Refreshing…')), findsOneWidget);
    gate.release();
    await h.settle();
    expect(inPage(find.bySemanticsLabel('Refresh')), findsOneWidget);
    expect(h.server.callsTo(shiftsT).length, shifts + 1);
    expect(h.server.callsTo(rosterT).length, roster + 1);
  });

  testWidgets('TEAM-ALL-009 back to the app after 30 s refetches the lists; '
      'sooner does nothing', (tester) async {
    final h = await pumpShifts(tester);
    final before = h.server.callsTo(shiftsT).length;
    final roster = h.server.callsTo(rosterT).length;
    h.server.clock.advance(const Duration(seconds: 10));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await h.settle();
    expect(h.server.callsTo(shiftsT).length, before);
    h.server.clock.advance(const Duration(seconds: 30));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await h.settle();
    expect(h.server.callsTo(shiftsT).length, before + 1);
    expect(h.server.callsTo(rosterT).length, roster + 1);
  });

  testWidgets('TEAM-ALL-010/022 a failed refresh keeps the rows and toasts '
      'once', (tester) async {
    final h = await pumpShifts(tester);
    h.server.fail(
      'GET',
      shiftsT,
      MockResponse.error(429, 'Too many requests'),
      times: null,
    );
    await h.tap(inPage(find.bySemanticsLabel('Refresh')));
    expect(shiftRow(sabahShift('morning')), findsOneWidget);
    expect(pageText(h.t('staff.shiftsLoadError')), findsNothing);
    await h.expectToast(h.t('errors.tooManyRequests'));
  });

  testWidgets('TEAM-ALL-013 times read on the 12-hour clock with Latin '
      'digits in Arabic, isolated', (tester) async {
    await pumpShifts(tester, locale: 'ar', edit: addDemoShifts);
    final row = tester.widget<DashListRow>(
      find.descendant(of: shiftRow(brunch), matching: find.byType(DashListRow)),
    );
    expect(row.meta, startsWith('\u206810:00 ص – 02:00 م\u2069 (4 س)'));
    expect(row.meta, contains('السبت – الخميس'));
  });

  testWidgets('TEAM-ALL-018 the scope bar\'s branch is not sent', (
    tester,
  ) async {
    final h = await pumpShifts(tester);
    await h.tap(find.text('All branches'));
    await h.tap(find.text('Zamalek').hitTestable());
    await h.tap(inPage(find.bySemanticsLabel('Refresh')));
    for (final t in [shiftsT, rosterT]) {
      expect(h.server.callsTo(t).every((c) => c.query.isEmpty), isTrue);
    }
  });

  testWidgets('TEAM-ALL-021 no URL state; the dialog closes on Escape '
      'sending nothing', (tester) async {
    final h = await pumpShifts(tester);
    await h.tap(inPage(find.byKey(const ValueKey('shifts-new'))));
    expect(find.byType(WorkShiftDialog), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
    expect(find.byType(WorkShiftDialog), findsNothing);
    expect(h.server.callsTo(shiftsT, method: 'POST'), isEmpty);
    expect(h.location.toString(), shiftsPath);
  });

  testWidgets('TEAM-ALL-026 a write invalidates every key under "/staff", '
      'the shared set-up reads included', (tester) async {
    final h = await pumpShifts(
      tester,
      edit: (db) {
        addDemoShifts(db);
        noRoster(db);
      },
    );
    final employees = h.server
        .callsTo(employeesT)
        .where((c) => c.query['employment_status']?.first == 'active')
        .length;
    await h.tap(inRow(brunch, find.bySemanticsLabel('Delete work shift')));
    await h.tap(confirmText('Delete'));
    await h.flushTimers();
    expect(
      h.server
          .callsTo(employeesT)
          .where((c) => c.query['employment_status']?.first == 'active')
          .length,
      employees + 1,
    );
  });

  testWidgets('phone: the list stays single-column rows with their pills '
      'and actions', (tester) async {
    final h = await pumpShifts(
      tester,
      size: DashSize.phone,
      edit: addDemoShifts,
    );
    expect(inRow(oldNight, find.text('Inactive')), findsOneWidget);
    expect(inRow(oldNight, find.bySemanticsLabel('Edit')), findsOneWidget);
    await h.tap(inRow(brunch, find.bySemanticsLabel('Edit')));
    expect(
      tester.widget<DashSurfaceScope>(find.byType(DashSurfaceScope).last).mode,
      DashSurfaceMode.fullScreen,
    );
  });
}
