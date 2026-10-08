// Set-up (`/staff/setup`): the page frame, the stepper, the footer and steps
// 2–4, driven through the real shell on the mock server. One test per
// TEAM-SET row (the row id is in the test name); the branch pins (step 1)
// are in setup_branches_test.dart.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'setup_support.dart';

/// The four checklist reads.
const _reads = [
  '/branches',
  '/staff/employees',
  '/staff/work-shifts',
  '/staff/attendance/settings',
];

int _calls(DashHarness h, String template) =>
    h.server.callsTo(template, method: 'GET').length;

DashButton _button(WidgetTester tester, String key) =>
    tester.widget<DashButton>(byKey(key));

/// Sabah with nothing done but its shifts: Maadi unpinned, nobody active,
/// rules never saved.
void _oneOfFour(MockDb db) {
  unpin(db, maadi, keepCoordinates: true);
  noActivePeople(db);
  rulesNeverSaved(db);
}

void main() {
  // ── Access ────────────────────────────────────────────────────────────

  group('TEAM-SET-001 refused without hr.rules.edit', () {
    for (final persona in [Persona.manager, Persona.limited]) {
      testWidgets('${persona.name}: Restricted with the page\'s own words, '
          'nothing requested', (tester) async {
        final h = await pumpSetup(tester, persona: persona);
        expect(find.text(h.t('dawam.setup')), findsWidgets);
        expect(find.text(h.t('common.restrictedTitle')), findsOneWidget);
        expect(find.text(h.t('dawam.setupNoAccess')), findsOneWidget);
        expect(byKey('setup-ready'), findsNothing);
        for (final path in _reads.skip(1)) {
          expect(_calls(h, path), 0, reason: path);
        }
        await h.shot('refused');
      });
    }

    testWidgets('an owner who gave the right away is refused; a non-owner '
        'who holds it is not (a capability, not a role)', (tester) async {
      var s = setupServer();
      answerAuthz(s.server, const ['branches.read', 'hr.staff.read']);
      var h = await pumpSetup(tester, s: s);
      expect(find.text(h.t('dawam.setupNoAccess')), findsOneWidget);

      s = setupServer(persona: Persona.manager);
      answerAuthz(s.server, const [
        'hr.rules.edit',
        'hr.staff.read',
        'hr.schedule.read',
        'branches.read',
      ], owner: false);
      // The mock server still answers as the manager, who may read these.
      h = await pumpSetup(tester, persona: Persona.manager, s: s);
      expect(find.text(h.t('dawam.setupNoAccess')), findsNothing);
      expect(byKey('setup-step-branches'), findsOneWidget);
    });
  });

  // ── Reads, header, loading, error ─────────────────────────────────────

  testWidgets('TEAM-SET-002 asks the four answers once an org is in scope',
      (tester) async {
    final h = await pumpSetup(tester);
    for (final path in _reads) {
      expect(_calls(h, path), greaterThanOrEqualTo(1), reason: path);
    }
    final employees = h.server.callsTo('/staff/employees', method: 'GET');
    expect(employees.last.query['employment_status'], ['active']);
    final branches = h.server.callsTo('/branches', method: 'GET');
    expect(branches.last.query['org_id'], [SeedIds.sabahOrg]);
  });

  testWidgets('TEAM-SET-002 asks nothing while no organization is in scope',
      (tester) async {
    final s = setupServer(persona: Persona.platform);
    final h = await pumpSetup(tester, persona: Persona.platform, s: s);
    h.allowUnmatched = true;
    for (final path in _reads.skip(1)) {
      expect(_calls(h, path), 0, reason: path);
    }
  });

  testWidgets('TEAM-SET-003 header: title, "n of 4 done", Refresh asks the '
      'four again (/staff and /branches)', (tester) async {
    final h = await pumpSetup(tester, edit: _oneOfFour);
    expect(find.text(h.t('dawam.setupTitle')), findsWidgets);
    expect(
      find.text(h.t('dawam.setupProgress', args: {'n': 1, 'total': 4})),
      findsOneWidget,
    );
    final before = {for (final p in _reads) p: _calls(h, p)};
    await h.tapKey(const ValueKey('setup-refresh'));
    for (final p in _reads) {
      expect(_calls(h, p), before[p]! + 1, reason: p);
    }
    // Still the same page and step.
    expect(byKey('setup-ready'), findsOneWidget);
  });

  testWidgets('TEAM-SET-003/004 while loading: the subtitle and two '
      'skeletons, never a step', (tester) async {
    final s = setupServer();
    final gate = s.server.hold('GET', '/staff/work-shifts');
    final h = await pumpSetup(tester, s: s);
    expect(find.text(h.t('dawam.setupSubtitle')), findsOneWidget);
    expect(byKey('setup-loading'), findsOneWidget);
    expect(
      find.descendant(
        of: byKey('setup-loading'),
        matching: find.byType(DashSkeleton),
      ),
      findsNWidgets(2),
    );
    expect(byKey('setup-step-branches'), findsNothing);
    await h.shot('loading');
    gate.release();
    await h.settle();
    expect(byKey('setup-loading'), findsNothing);
    expect(byKey('setup-ready'), findsOneWidget);
  });

  testWidgets('TEAM-SET-005 a read that failed: error words, the server\'s '
      'message, Retry asks only that read again', (tester) async {
    final s = setupServer();
    s.server.fail(
      'GET',
      '/staff/work-shifts',
      MockResponse.error(500, 'Internal server error: shifts unavailable'),
    );
    final h = await pumpSetup(tester, s: s);
    expect(byKey('setup-error'), findsOneWidget);
    expect(find.text(h.t('dawam.setupLoadError')), findsOneWidget);
    expect(
      find.text('Internal server error: shifts unavailable'),
      findsOneWidget,
    );
    expect(byKey('setup-step-branches'), findsNothing);
    await h.shot('error');
    final before = {for (final p in _reads) p: _calls(h, p)};
    await h.tapText(h.t('common.retry'));
    expect(_calls(h, '/staff/work-shifts'), before['/staff/work-shifts']! + 1);
    for (final p in _reads.where((p) => p != '/staff/work-shifts')) {
      expect(_calls(h, p), before[p], reason: '$p is not asked again');
    }
    expect(byKey('setup-error'), findsNothing);
    expect(byKey('setup-ready'), findsOneWidget);
  });

  testWidgets('TEAM-SET-005 a failed refresh keeps the checklist on screen '
      'and toasts once (TEAM-ALL-022)', (tester) async {
    final h = await pumpSetup(tester, edit: _oneOfFour);
    h.server.fail(
      'GET',
      '/staff/work-shifts',
      MockResponse.error(429, 'Too many requests', retryAfterSeconds: 2),
    );
    await h.tapKey(const ValueKey('setup-refresh'));
    expect(byKey('setup-ready'), findsOneWidget);
    expect(byKey('setup-error'), findsNothing);
    await h.expectToast('Too many requests');
  });

  // ── Done rules, opening step ─────────────────────────────────────────

  testWidgets('TEAM-SET-006 each tick comes from the data', (tester) async {
    final h = await pumpSetup(
      tester,
      edit: (db) {
        // Coordinates but no radius: not pinned.
        unpin(db, zamalek, keepCoordinates: true);
        noActiveShifts(db);
      },
    );
    String state(String step) => find
        .descendant(
          of: byKey('setup-step-$step'),
          matching: find.text(h.t('dawam.setupDone')),
        )
        .evaluate()
        .isEmpty
        ? 'todo'
        : 'done';
    expect(state('branches'), 'todo');
    expect(state('employees'), 'done');
    expect(state('shifts'), 'todo');
    expect(state('rules'), 'done');
    expect(
      find.text(h.t('dawam.setupProgress', args: {'n': 2, 'total': 4})),
      findsOneWidget,
    );
  });

  testWidgets('TEAM-SET-007 opens on the first step not done', (tester) async {
    final h = await pumpSetup(tester, edit: noActiveShifts);
    expect(find.text(h.t('dawam.setupShiftsV2')), findsOneWidget);
    expect(
      find.text(h.t('dawam.setupStepOf', args: {'n': 3, 'total': 4})),
      findsOneWidget,
    );
  });

  testWidgets('TEAM-SET-007 all done: opens on Rules', (tester) async {
    final h = await pumpSetup(tester);
    expect(find.text(h.t('dawam.setupRulesV2')), findsOneWidget);
  });

  // ── Stepper ──────────────────────────────────────────────────────────

  testWidgets('TEAM-SET-008 stepper: four steps, number or tick, Done / To '
      'do, any step opens any time', (tester) async {
    final h = await pumpSetup(tester, edit: _oneOfFour);
    expect(
      find.bySemanticsLabel(
        '1. ${h.t('dawam.stepBranches')}, ${h.t('dawam.setupToDo')}',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        '3. ${h.t('dawam.stepShifts')}, ${h.t('dawam.setupDone')}',
      ),
      findsOneWidget,
    );
    // The done step shows a tick, the others their number.
    expect(
      find.descendant(
        of: byKey('setup-step-shifts'),
        matching: find.text('3'),
      ),
      findsNothing,
    );
    expect(textIn('setup-step-branches', '1'), findsOneWidget);
    expect(textIn('setup-step-rules', '4'), findsOneWidget);
    for (final (step, title) in [
      ('rules', 'dawam.setupRulesV2'),
      ('employees', 'dawam.setupEmployeesV2'),
      ('shifts', 'dawam.setupShiftsV2'),
      ('branches', 'dawam.setupBranchesV2'),
    ]) {
      await h.tapKey(ValueKey('setup-step-$step'));
      expect(find.text(h.t(title)), findsOneWidget, reason: step);
    }
  });

  testWidgets('TEAM-SET-008/039 phone: four columns, the label under the '
      'circle', (tester) async {
    final h = await pumpSetup(tester, edit: _oneOfFour, size: DashSize.phone);
    final steps = [
      for (final s in ['branches', 'employees', 'shifts', 'rules'])
        tester.getRect(byKey('setup-step-$s')),
    ];
    // One row of four.
    for (final r in steps.skip(1)) {
      expect(r.top, steps.first.top);
    }
    final circle = tester.getRect(textIn('setup-step-branches', '1'));
    final label = tester.getRect(
      textIn('setup-step-branches', h.t('dawam.stepBranches')),
    );
    expect(label.top, greaterThan(circle.bottom - 1));
  });

  testWidgets('TEAM-SET-009 all done: the status panel and its two links',
      (tester) async {
    final h = await pumpSetup(tester);
    expect(
      find.text(h.t('dawam.setupProgress', args: {'n': 4, 'total': 4})),
      findsOneWidget,
    );
    expect(byKey('setup-complete'), findsOneWidget);
    expect(find.text(h.t('dawam.setupComplete')), findsOneWidget);
    expect(find.text(h.t('dawam.setupGoTeam')), findsOneWidget);
    // Out of this unit: whatever the next page asks is its own concern.
    h.allowUnmatched = true;
    await h.tapKey(const ValueKey('setup-go-schedule'));
    expect(h.location.path, '/staff/schedule');
  });

  testWidgets('TEAM-SET-009 "See who\'s in" goes to the Team board',
      (tester) async {
    final h = await pumpSetup(tester);
    h.allowUnmatched = true;
    await h.tapKey(const ValueKey('setup-go-team'));
    expect(h.location.path, '/staff/team');
  });

  testWidgets('TEAM-SET-009 not all done: no panel', (tester) async {
    await pumpSetup(tester, edit: _oneOfFour);
    expect(byKey('setup-complete'), findsNothing);
  });

  // ── Step card and footer ─────────────────────────────────────────────

  testWidgets('TEAM-SET-010 each step\'s header: "Step n of 4", title and '
      'hint', (tester) async {
    final h = await pumpSetup(tester, edit: _oneOfFour);
    for (final (i, step, title, hint) in [
      (1, 'branches', 'dawam.setupBranchesV2', 'dawam.setupBranchesHintV2'),
      (2, 'employees', 'dawam.setupEmployeesV2', 'dawam.setupEmployeesHint'),
      (3, 'shifts', 'dawam.setupShiftsV2', 'dawam.setupShiftsHintV2'),
      (4, 'rules', 'dawam.setupRulesV2', 'dawam.setupRulesHint'),
    ]) {
      await h.tapKey(ValueKey('setup-step-$step'));
      final card = byKey('setup-step-card');
      for (final text in [
        h.t('dawam.setupStepOf', args: {'n': i, 'total': 4}),
        h.t(title),
        h.t(hint),
      ]) {
        expect(
          find.descendant(of: card, matching: find.text(text)),
          findsOneWidget,
          reason: '$step: $text',
        );
      }
    }
  });

  testWidgets('TEAM-SET-011 Back: the previous step\'s name; none on step 1',
      (tester) async {
    final h = await pumpSetup(tester, edit: _oneOfFour);
    expect(byKey('setup-back'), findsNothing);
    await h.tapKey(const ValueKey('setup-step-shifts'));
    expect(_button(tester, 'setup-back').label, h.t('dawam.stepEmployees'));
    expect(_button(tester, 'setup-back').variant, DashButtonVariant.ghost);
    expect(_button(tester, 'setup-back').icon, 'arrow-left');
    await h.tapKey(const ValueKey('setup-back'));
    expect(find.text(h.t('dawam.setupEmployeesV2')), findsOneWidget);
  });

  testWidgets('TEAM-SET-011 Back\'s arrow is mirrored in Arabic',
      (tester) async {
    final h = await pumpSetup(tester, edit: _oneOfFour, locale: 'ar');
    await h.tapKey(const ValueKey('setup-step-rules'));
    expect(_button(tester, 'setup-back').icon, 'arrow-right');
    expect(_button(tester, 'setup-back').label, h.t('dawam.stepShifts'));
  });

  testWidgets('TEAM-SET-012 Next: outline + "You can come back to this." on '
      'a step not done, filled on a done one, none on the last',
      (tester) async {
    final h = await pumpSetup(tester, edit: _oneOfFour);
    // Step 1 is not done.
    expect(
      _button(tester, 'setup-next').label,
      h.t('dawam.setupNext', args: {'step': h.t('dawam.stepEmployees')}),
    );
    expect(_button(tester, 'setup-next').variant, DashButtonVariant.outline);
    expect(find.text(h.t('dawam.setupComeBack')), findsOneWidget);
    await h.tapKey(const ValueKey('setup-next'));
    await h.tapKey(const ValueKey('setup-next'));
    // Step 3 (shifts) is done.
    expect(find.text(h.t('dawam.setupShiftsV2')), findsOneWidget);
    expect(_button(tester, 'setup-next').variant, DashButtonVariant.primary);
    expect(find.text(h.t('dawam.setupComeBack')), findsNothing);
    await h.tapKey(const ValueKey('setup-next'));
    expect(find.text(h.t('dawam.setupRulesV2')), findsOneWidget);
    expect(byKey('setup-next'), findsNothing);
  });

  // ── Step 2: people ───────────────────────────────────────────────────

  testWidgets('TEAM-SET-024 nobody active: the empty state with the step\'s '
      'actions', (tester) async {
    final h = await pumpSetup(tester, edit: _oneOfFour);
    await h.tapKey(const ValueKey('setup-step-employees'));
    expect(byKey('setup-no-people'), findsOneWidget);
    expect(find.text(h.t('dawam.setupNoEmployees')), findsOneWidget);
    expect(find.text(h.t('dawam.setupNoEmployeesHint')), findsOneWidget);
    expect(byKey('setup-add-employee'), findsOneWidget);
    expect(byKey('setup-import-people'), findsOneWidget);
    await h.shot('people-empty');
  });

  testWidgets('TEAM-SET-025 the count and the first 24 names, then "+N"',
      (tester) async {
    late int active;
    final h = await pumpSetup(
      tester,
      edit: (db) {
        for (var i = 0; i < 20; i++) {
          db['employees'].insert({
            'org_id': SeedIds.sabahOrg,
            'name': 'Temp Barista ${(i + 1).toString().padLeft(2, '0')}',
            'kind': 'manual',
            'employment_status': 'active',
            'salary_set': true,
            'branch_ids': [SeedIds.heliopolis],
            'app_access': false,
            'on_payroll': true,
            'pay_method': 'cash',
            'advance_within_cap': true,
            'cant_work_days': <int>[],
          });
        }
        // Someone who left does not count.
        db['employees'].insert({
          'org_id': SeedIds.sabahOrg,
          'name': 'Former Waiter',
          'kind': 'manual',
          'employment_status': 'terminated',
          'salary_set': true,
          'branch_ids': [SeedIds.heliopolis],
          'app_access': false,
          'on_payroll': false,
          'pay_method': 'cash',
          'advance_within_cap': true,
          'cant_work_days': <int>[],
        });
        active = activeStaff(db).length;
      },
    );
    expect(active, greaterThan(24));
    await h.tapKey(const ValueKey('setup-step-employees'));
    expect(
      find.text(h.t('dawam.setupEmployeeCount', count: active)),
      findsOneWidget,
    );
    expect(find.text('+${active - 24}'), findsOneWidget);
    expect(find.text('Former Waiter'), findsNothing);
    final names = (activeStaff(h.db!)).map((e) => e['name']! as String);
    // GET sorts by name: the first 24 show, the rest are counted.
    expect(find.text(names.first), findsOneWidget);
    expect(find.text(names.last), findsNothing);
  });

  testWidgets('TEAM-SET-026 people with no salary set: a warning with the '
      'count', (tester) async {
    late int missing;
    final h = await pumpSetup(
      tester,
      edit: (db) => missing = activeStaff(
        db,
      ).where((e) => e['salary_set'] == false).length,
    );
    expect(missing, greaterThan(0));
    await h.tapKey(const ValueKey('setup-step-employees'));
    expect(
      textIn('setup-no-salary', h.t('dawam.setupNoSalary', count: missing)),
      findsOneWidget,
    );
    await h.shot('people-list');
  });

  testWidgets('TEAM-SET-026 everyone paid: no warning', (tester) async {
    final h = await pumpSetup(
      tester,
      edit: (db) {
        for (final e in activeStaff(db)) {
          e['salary_set'] = true;
        }
      },
    );
    await h.tapKey(const ValueKey('setup-step-employees'));
    expect(byKey('setup-no-salary'), findsNothing);
  });

  testWidgets('TEAM-SET-027 without hr.staff.create: the words, no buttons',
      (tester) async {
    final s = setupServer(edit: noActivePeople);
    answerAuthz(s.server, const [
      'hr.rules.edit',
      'hr.staff.read',
      'hr.schedule.read',
      'branches.read',
      'branches.edit',
    ]);
    final h = await pumpSetup(tester, s: s);
    await h.tapKey(const ValueKey('setup-step-employees'));
    expect(find.text(h.t('dawam.setupNoCreate')), findsOneWidget);
    expect(byKey('setup-add-employee'), findsNothing);
    expect(byKey('setup-import-people'), findsNothing);
  });

  // ── Step 3: shifts ───────────────────────────────────────────────────

  testWidgets('TEAM-SET-028 no active shift: the empty state with New shift',
      (tester) async {
    final h = await pumpSetup(tester, edit: noActiveShifts);
    expect(byKey('setup-no-shifts'), findsOneWidget);
    expect(find.text(h.t('dawam.setupNoShifts')), findsOneWidget);
    expect(find.text(h.t('dawam.setupNoShiftsHint')), findsOneWidget);
    expect(byKey('setup-new-shift'), findsOneWidget);
    await h.shot('shifts-empty');
  });

  testWidgets('TEAM-SET-029 the active shifts: times, span, next-day pill, '
      'days and branch; Open work shifts', (tester) async {
    final h = await pumpSetup(
      tester,
      edit: (db) {
        db['work_shifts'].insert({
          'org_id': SeedIds.sabahOrg,
          'branch_id': SeedIds.zamalek,
          'name': 'Late night',
          'start_time': '22:00:00',
          'end_time': '06:30:00',
          'crosses_midnight': true,
          'break_minutes': 0,
          'paid_break': true,
          'grace_minutes': 10,
          'checkin_window_minutes': 60,
          'overtime_threshold_minutes': 15,
          'overtime_multiplier': 1.5,
          'valid_days': [4, 5],
          'is_active': true,
        });
        db['work_shifts'].insert({
          'org_id': SeedIds.sabahOrg,
          'name': 'Retired split',
          'start_time': '10:00:00',
          'end_time': '14:00:00',
          'valid_days': [0, 1, 2, 3, 4, 5, 6],
          'is_active': false,
        });
      },
    );
    await h.tapKey(const ValueKey('setup-step-shifts'));
    expect(find.text('Morning'), findsOneWidget);
    expect(find.text('Late night'), findsOneWidget);
    expect(find.text('Retired split'), findsNothing);
    expect(textHas('7:00 AM – 3:00 PM'), findsOneWidget);
    expect(textHas('10:00 PM – 6:30 AM'), findsOneWidget);
    expect(textHas('8 h'), findsWidgets);
    expect(textHas('8 h 30 min'), findsOneWidget);
    expect(find.text(h.t('inputs.endsNextDay')), findsOneWidget);
    expect(
      find.text('${h.t('inputs.everyDay')} · ${h.t('staff.wholeBusiness')}'),
      findsNWidgets(2),
    );
    expect(find.text('Thu, Fri · Zamalek'), findsOneWidget);
    await h.shot('shifts-list');
    h.allowUnmatched = true;
    await h.tapKey(const ValueKey('setup-open-shifts'));
    expect(h.location.path, '/staff/shifts');
  });

  testWidgets('TEAM-SET-029 Arabic: the span and days in Arabic words',
      (tester) async {
    final h = await pumpSetup(tester, locale: 'ar');
    await h.tapKey(const ValueKey('setup-step-shifts'));
    expect(textHas('8 س'), findsWidgets);
    expect(
      find.text('${h.t('inputs.everyDay')} · ${h.t('staff.wholeBusiness')}'),
      findsNWidgets(2),
    );
  });

  testWidgets('TEAM-SET-030 without hr.schedule.create: the words, no New '
      'shift', (tester) async {
    final s = setupServer(edit: noActiveShifts);
    answerAuthz(s.server, const [
      'hr.rules.edit',
      'hr.staff.read',
      'hr.schedule.read',
      'branches.read',
    ]);
    final h = await pumpSetup(tester, s: s);
    expect(find.text(h.t('dawam.setupNoShiftCreate')), findsOneWidget);
    expect(byKey('setup-new-shift'), findsNothing);
  });

  // ── Step 4: rules ────────────────────────────────────────────────────

  testWidgets('TEAM-SET-031/032/033/035 saved rules: the words, the stored '
      'ladder in money, the facts, "Open the rules"', (tester) async {
    final h = await pumpSetup(tester);
    expect(find.text(h.t('dawam.setupRulesAreSaved')), findsOneWidget);
    final ladder = byKey('setup-ladder');
    for (final head in [
      'dawam.setupLateBy',
      'staff.deduct',
      'dawam.setupOnSalary',
    ]) {
      expect(
        find.descendant(of: ladder, matching: find.text(h.t(head))),
        findsOneWidget,
      );
    }
    // Sabah: 15–30 min = 30 minutes of pay; 30–60 = 0.25 day; 60+ = 0.5 day,
    // on EGP 12,000 over its 26 working days and a 480-minute shift.
    expect(
      find.text(h.t('staff.tierRange', args: {'from': 15, 'to': 30})),
      findsOneWidget,
    );
    expect(
      find.text(h.t('staff.tierCostMinutes', args: {'n': '30'})),
      findsOneWidget,
    );
    expect(find.text('EGP 28.85'), findsOneWidget); // 1,200,000×30/(26×480)
    expect(find.text('EGP 115.38'), findsOneWidget); // 1,200,000×0.25/26
    expect(
      find.text(h.t('staff.tierFromOnly', args: {'from': 60})),
      findsOneWidget,
    );
    expect(find.text('EGP 230.77'), findsOneWidget); // 1,200,000×0.5/26
    expect(
      find.text(h.t('dawam.setupAbsence', args: {'n': '1'})),
      findsOneWidget,
    );
    expect(find.text(h.t('dawam.setupOtOn')), findsOneWidget);
    expect(
      find.text(h.t('dawam.setupPayDay', args: {'n': 1})),
      findsOneWidget,
    );
    expect(find.text(h.t('dawam.setupGrace')), findsOneWidget);
    expect(byKey('setup-save-rules'), findsNothing);
    expect(_button(tester, 'setup-open-rules').label, h.t('dawam.setupOpenRules'));
    expect(
      _button(tester, 'setup-open-rules').variant,
      DashButtonVariant.primary,
    );
    h.allowUnmatched = true;
    await h.tapKey(const ValueKey('setup-open-rules'));
    expect(h.location.path, '/staff/rules');
  });

  testWidgets('TEAM-SET-031/032/035 never saved: the suggested ladder, '
      '"Adjust them first"', (tester) async {
    final h = await pumpSetup(tester, edit: rulesNeverSaved);
    expect(find.text(h.t('dawam.setupRulesSuggested')), findsOneWidget);
    expect(find.text(h.t('dawam.setupOtOff')), findsOneWidget);
    expect(
      _button(tester, 'setup-open-rules').label,
      h.t('dawam.setupAdjustRules'),
    );
    expect(
      _button(tester, 'setup-open-rules').variant,
      DashButtonVariant.outline,
    );
    // The server's suggestion, worked on EGP 12,000 / 26 days.
    final settings = h.server.callsTo(
      '/staff/attendance/settings',
      method: 'GET',
    );
    expect(settings, isNotEmpty);
    expect(
      find.descendant(
        of: byKey('setup-ladder'),
        matching: find.textContaining('EGP'),
      ),
      findsWidgets,
    );
    await h.shot('rules-suggested');
  });

  testWidgets('TEAM-SET-032 no rungs: "No penalties"', (tester) async {
    final h = await pumpSetup(
      tester,
      edit: (db) {
        final row = db['attendance_settings'].firstWhere(
          (r) => r['org_id'] == SeedIds.sabahOrg,
        )!;
        row['late_deduction_tiers'] = <Object?>[];
      },
    );
    expect(textIn('setup-ladder', h.t('staff.noTiers')), findsOneWidget);
  });

  testWidgets('TEAM-SET-034 "Save these rules" PUTs the suggested rules, '
      'toasts, and the step ticks', (tester) async {
    final h = await pumpSetup(tester, edit: rulesNeverSaved);
    expect(
      find.text(h.t('dawam.setupProgress', args: {'n': 3, 'total': 4})),
      findsOneWidget,
    );
    await h.tapKey(const ValueKey('setup-save-rules'));
    final put = h.server.callsTo('/staff/attendance/settings', method: 'PUT');
    expect(put, hasLength(1));
    final body = put.single.body! as Map<String, Object?>;
    final suggested = h.server
        .callsTo('/staff/attendance/settings', method: 'GET')
        .first;
    expect(suggested, isNotNull);
    expect(body['late_deduction_tiers'], isA<List<Object?>>());
    expect((body['late_deduction_tiers']! as List).isNotEmpty, isTrue);
    expect(body['absence_deduction_days'], 1);
    expect(body['working_days_per_month'], 26);
    expect(body['overtime_mode'], 'off');
    expect(body['night_start'], '22:00:00');
    expect(body['gender_mode'], 'soft');
    await h.expectToast(h.t('dawam.setupRulesSaved'));
    // The step ticks and the button goes.
    expect(find.text(h.t('dawam.setupRulesAreSaved')), findsOneWidget);
    expect(byKey('setup-save-rules'), findsNothing);
    expect(
      find.text(h.t('dawam.setupProgress', args: {'n': 4, 'total': 4})),
      findsOneWidget,
    );
    expect(byKey('setup-complete'), findsOneWidget);
  });

  testWidgets('TEAM-SET-034 without hr.roster.settings the gender mode is '
      'not sent', (tester) async {
    final s = setupServer(edit: rulesNeverSaved);
    answerAuthz(s.server, const [
      'hr.rules.edit',
      'hr.staff.read',
      'hr.schedule.read',
      'branches.read',
    ]);
    final h = await pumpSetup(tester, s: s);
    await h.tapKey(const ValueKey('setup-step-rules'));
    await h.tapKey(const ValueKey('setup-save-rules'));
    final body =
        h.server
                .callsTo('/staff/attendance/settings', method: 'PUT')
                .single
                .body!
            as Map<String, Object?>;
    expect(body.containsKey('gender_mode'), isFalse);
    await h.flushTimers();
  });

  testWidgets('TEAM-SET-034 a refused save says why and keeps the step',
      (tester) async {
    final h = await pumpSetup(tester, edit: rulesNeverSaved);
    h.server.fail(
      'PUT',
      '/staff/attendance/settings',
      MockResponse.denied('hr.rules.edit'),
    );
    await h.tapKey(const ValueKey('setup-save-rules'));
    await h.expectToast(
      "Forbidden: You don't have permission to do this: "
      'Change attendance and pay rules (hr.rules.edit)',
      keep: true,
    );
    expect(byKey('setup-save-rules'), findsOneWidget);
    expect(_button(tester, 'setup-save-rules').loading, isFalse);
    expect(find.text(h.t('dawam.setupRulesSuggested')), findsOneWidget);
    await h.flushTimers();
  });

  // ── Live ─────────────────────────────────────────────────────────────

  testWidgets('TEAM-ALL-009 coming back after 30 s refetches the checklist; '
      'sooner does nothing', (tester) async {
    final h = await pumpSetup(tester, edit: _oneOfFour);
    final clock = h.db!.clock;
    Future<void> background() async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await h.settle();
    }

    final before = {for (final p in _reads) p: _calls(h, p)};
    clock.advance(const Duration(seconds: 10));
    await background();
    for (final p in _reads) {
      expect(_calls(h, p), before[p], reason: '$p: <30 s');
    }
    clock.advance(const Duration(seconds: 25));
    await background();
    for (final p in _reads) {
      expect(_calls(h, p), before[p]! + 1, reason: '$p: ≥30 s');
    }
  });

  testWidgets('TEAM-SET-005 a 403 on a read speaks the server\'s refusal',
      (tester) async {
    final s = setupServer();
    s.server.fail(
      'GET',
      '/staff/attendance/settings',
      MockResponse.denied('hr.rules.view'),
    );
    final h = await pumpSetup(tester, s: s);
    expect(find.text(h.t('dawam.setupLoadError')), findsOneWidget);
    expect(find.textContaining('(hr.rules.view)'), findsOneWidget);
  });
}
