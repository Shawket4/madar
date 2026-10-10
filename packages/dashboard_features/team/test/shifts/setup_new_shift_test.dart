// Set-up step 3's "New shift" (TEAM-SET-030/038) opens this unit's Work
// shift dialog for a new block and saves through it.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_team/src/shifts/shift_dialog.dart';
import 'package:dashboard_team/src/team_setup/team_setup_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shifts_support.dart';

/// No active block at Sabah: step 3 is the step to do.
void _noActiveShifts(MockDb db) {
  for (final s in db['work_shifts'].where(
    (r) => r['org_id'] == SeedIds.sabahOrg,
  )) {
    s['is_active'] = false;
  }
}

Map<String, Object?> _posted(DashHarness h) =>
    (h.server.callsTo(shiftsT, method: 'POST').single.body! as Map)
        .cast<String, Object?>();

Finder _inSetup(Finder f) =>
    find.descendant(of: find.byType(TeamSetupPage), matching: f);

Future<void> _openStep3(DashHarness h) async {
  await h.tapKey(const ValueKey('setup-step-shifts'));
  await h.tap(_inSetup(find.byKey(const ValueKey('setup-new-shift'))));
}

void main() {
  testWidgets('TEAM-SET-030/038 step 3 "New shift" opens the shift dialog '
      'for a new block; Save creates it and the step sees it', (tester) async {
    final h = await pumpShifts(
      tester,
      path: '/staff/setup',
      edit: _noActiveShifts,
    );
    final reads = h.server.callsTo(shiftsT, method: 'GET').length;
    await _openStep3(h);
    expect(find.byType(WorkShiftDialog), findsOneWidget);
    expect(surfaceText('New shift'), findsOneWidget);
    // A new block: the presets, and "Every branch" for the owner.
    expect(surfaceText(h.t('staff.startFrom')), findsOneWidget);
    expect(surfaceText('Every branch'), findsOneWidget);
    await h.tap(inSurface(find.bySemanticsLabel(RegExp('^Night'))));
    await h.tap(save());
    expect(_posted(h), containsPair('name', 'Night'));
    expect(_posted(h)['branch_id'], isNull);
    expect(_posted(h)['start_time'], '22:00:00');
    expect(_posted(h)['end_time'], '06:00:00');
    await h.expectToast('Work shift saved');
    expect(find.byType(WorkShiftDialog), findsNothing);
    // The checklist's shared read is invalidated and shows the new block.
    expect(h.server.callsTo(shiftsT, method: 'GET').length, reads + 1);
    expect(_inSetup(find.textContaining('Night')), findsWidgets);
  });

  testWidgets('TEAM-SET-038 without the right everywhere the new block '
      'starts at the first branch', (tester) async {
    final s = shiftsServer(edit: _noActiveShifts);
    answerAuthz(
      s.server,
      const [
        'hr.rules.edit',
        'hr.staff.read',
        'hr.schedule.read',
        'hr.schedule.create',
        'branches.read',
      ],
      everywhere: const ['hr.rules.edit', 'hr.staff.read', 'branches.read'],
    );
    final h = await pumpShifts(tester, s: s, path: '/staff/setup');
    await _openStep3(h);
    expect(surfaceText('Every branch'), findsNothing);
    expect(surfaceText('Heliopolis'), findsOneWidget);
    await h.enterText(textNamed('Name'), 'Opening');
    await h.tap(save());
    expect(_posted(h)['branch_id'], SeedIds.heliopolis);
    await h.flushTimers();
  });
}
