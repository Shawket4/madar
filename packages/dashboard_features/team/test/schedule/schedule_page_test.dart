// The Schedule page (`/staff/schedule`): one driven test per TEAM-SCH row
// of the page itself (header, branch, week bar, grid, open shifts,
// suggestions, holidays, gating) plus the area rows that land on it
// (TEAM-ALL-011, 016, 017, 018, 022), on the real shell and the seeded mock.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart' show lri;
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_team/src/schedule/coverage_card.dart';
import 'package:dashboard_team/src/schedule/fairness_card.dart';
import 'package:dashboard_team/src/schedule/schedule_grid.dart';
import 'package:dashboard_team/src/schedule/schedule_page.dart';
import 'package:dashboard_team/src/shared/refresh_button.dart';
import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'schedule_support.dart';

/// The page's own button labelled [label].
Finder button(String label) => inPage(find.widgetWithText(DashButton, label));

bool enabled(WidgetTester tester, Finder f) =>
    tester.widget<DashButton>(f.first).onPressed != null;

final Finder weekBar = find.byKey(const Key('schedule-week-group'));

/// The suggestions section.
Finder inSuggestions(Finder f) => find.descendant(
  of: find.byKey(const Key('schedule-suggestions')),
  matching: f,
);

Finder inHolidays(Finder f) => find.descendant(
  of: find.byKey(const Key('schedule-holidays')),
  matching: f,
);

void main() {
  // ── gating and header ────────────────────────────────────────────────

  testWidgets('TEAM-SCH-001 without hr.schedule.read: Restricted with the '
      'page\'s own words, nothing asked', (tester) async {
    final h = await pumpSchedule(tester, persona: Persona.limited);
    expect(find.text(h.t('dawam.scheduleNoAccess')), findsOneWidget);
    expect(page, findsNothing);
    expect(calls(h, rosterT), isEmpty);
    expect(calls(h, suggestionsT), isEmpty);
  });

  testWidgets('TEAM-SCH-002 header: title, subtitle, Refresh and the coverage '
      'toggle; no branch select with a branch scoped', (tester) async {
    final h = await pumpSchedule(tester);
    expect(pageText('Schedule'), findsWidgets);
    expect(pageText(h.t('dawam.scheduleSubtitle')), findsOneWidget);
    expect(inPage(find.byType(DawamRefreshButton)), findsOneWidget);
    expect(button('Coverage needs'), findsOneWidget);
    expect(find.byKey(const Key('schedule-branch')), findsNothing);
  });

  testWidgets('TEAM-SCH-003 TEAM-ALL-016 rules never saved: the banner sends '
      'to the rules (3 steps done)', (tester) async {
    final h = await pumpSchedule(
      tester,
      edit: (db) {
        for (final s in db['attendance_settings'].rows) {
          s['rules_saved_at'] = null;
        }
      },
    );
    expect(pageText(h.t('dawam.rulesFirstTitle')), findsOneWidget);
    expect(pageText(h.t('dawam.rulesFirstHint')), findsOneWidget);
    await h.tap(button(h.t('dawam.rulesFirstAction')));
    expect(h.location.path, '/staff/rules');
  });

  testWidgets('TEAM-ALL-016 fewer than 3 steps done: "Finish set-up" goes to '
      'the checklist; saved rules show no banner', (tester) async {
    final h = await pumpSchedule(
      tester,
      edit: (db) {
        for (final s in db['attendance_settings'].rows) {
          s['rules_saved_at'] = null;
        }
        db['work_shifts'].removeWhere((w) => w['org_id'] == SeedIds.sabahOrg);
      },
    );
    await h.tap(button(h.t('dawam.setupFinish')));
    expect(h.location.path, '/staff/setup');
  });

  testWidgets('TEAM-ALL-016 saved rules: no banner', (tester) async {
    final h = await pumpSchedule(tester);
    expect(pageText(h.t('dawam.rulesFirstTitle')), findsNothing);
  });

  testWidgets('TEAM-ALL-016 never while loading or on error', (tester) async {
    final s = scheduleServer(
      edit: (db) {
        for (final r in db['attendance_settings'].rows) {
          r['rules_saved_at'] = null;
        }
      },
    );
    s.server.fail(
      'GET',
      '/staff/attendance/settings',
      MockResponse.error(500, 'boom'),
      times: null,
    );
    final h = await pumpSchedule(tester, s: s);
    expect(pageText(h.t('dawam.rulesFirstTitle')), findsNothing);
    expect(inGrid(find.text('Adham Reda')), findsOneWidget);
  });

  // ── branch ───────────────────────────────────────────────────────────

  testWidgets('TEAM-SCH-004 TEAM-ALL-018 All branches: the page\'s own select '
      'defaults to the first branch and picks another', (tester) async {
    final h = await pumpSchedule(tester, allBranches: true);
    final select = find.byKey(const Key('schedule-branch'));
    expect(select, findsOneWidget);
    final first = calls(h, rosterT).first.query['branch_id']!.single;
    expect(
      calls(h, rosterT).every((c) => c.query['branch_id']!.single == first),
      isTrue,
    );
    await h.tap(select);
    await h.tap(find.text('Maadi').hitTestable().last);
    expect(
      weekCalls(
        h,
        week,
      ).where((c) => c.query['branch_id']!.single == SeedIds.maadi),
      hasLength(1),
    );
  });

  testWidgets(
    'TEAM-ALL-018 a scoped branch is the board: every read names it',
    (tester) async {
      final h = await pumpSchedule(tester);
      for (final c in [...calls(h, rosterT), ...calls(h, suggestionsT)]) {
        expect(c.query['branch_id'], [SeedIds.zamalek]);
      }
    },
  );

  testWidgets('TEAM-SCH-005 branches failed: the error with Retry, never a '
      'skeleton for ever', (tester) async {
    final s = scheduleServer();
    s.server.fail(
      'GET',
      '/branches',
      MockResponse.error(500, 'boom'),
      times: null,
    );
    final h = await pumpSchedule(tester, s: s, allBranches: true);
    h.allowUnmatched = true;
    expect(pageText(h.t('dawam.branchesLoadError')), findsOneWidget);
    expect(find.byKey(const Key('schedule-skeleton')), findsNothing);
    s.server.clearFailures();
    await h.tap(inPage(find.text('Retry')));
    expect(pageText(h.t('dawam.branchesLoadError')), findsNothing);
  });

  testWidgets('TEAM-SCH-005 no branch at all: "Add a branch first"', (
    tester,
  ) async {
    final s = scheduleServer();
    s.server.on('GET', '/branches', (req) => MockResponse.ok(const []));
    final h = await pumpSchedule(tester, s: s, allBranches: true);
    expect(pageText(h.t('dawam.noBranchYet')), findsOneWidget);
    expect(calls(h, rosterT), isEmpty);
  });

  // ── the week bar ─────────────────────────────────────────────────────

  testWidgets('TEAM-SCH-006 TEAM-ALL-011 the week bar: Saturday to Friday, '
      'the distance word, arrows ask for that week', (tester) async {
    final h = await pumpSchedule(tester);
    expect(pageText('03 Oct 2026 – 09 Oct 2026'), findsOneWidget);
    expect(pageText('This week'), findsOneWidget);
    expect(weekCalls(h, week), hasLength(1));

    await h.tap(pressable('Next week'));
    expect(pageText('Next week'), findsWidgets);
    expect(weekCalls(h, wd(7)), hasLength(1));
    await h.tap(pressable('Next week'));
    expect(pageText('In 2 weeks'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await h.tap(pressable('Previous week'));
    }
    expect(pageText('Last week'), findsOneWidget);
    await h.tap(pressable('Previous week'));
    expect(pageText('2 weeks ago'), findsOneWidget);
    expect(weekCalls(h, wd(-14)), hasLength(1));
  });

  testWidgets('TEAM-SCH-007 "Back to this week" only away from this week', (
    tester,
  ) async {
    final h = await pumpSchedule(tester);
    expect(button('Back to this week'), findsNothing);
    await h.tap(pressable('Next week'));
    await h.tap(button('Back to this week'));
    expect(pageText('This week'), findsOneWidget);
    expect(button('Back to this week'), findsNothing);
  });

  testWidgets('TEAM-SCH-008 "Go to a date": one pick jumps to that week', (
    tester,
  ) async {
    final h = await pumpSchedule(tester);
    await h.tap(find.byKey(const Key('schedule-go-to-date')));
    await h.tap(find.text('28').hitTestable().last);
    expect(weekCalls(h, '2026-10-24'), hasLength(1));
    expect(pageText('In 3 weeks'), findsOneWidget);
  });

  testWidgets('TEAM-SCH-009 a published week: the pill and the changed-days '
      'line', (tester) async {
    final h = await pumpSchedule(tester);
    expect(pageText('Published'), findsOneWidget);
    expect(
      pageText(h.t('dawamOps.publishedChanged', count: 2, args: {'count': 2})),
      findsOneWidget,
    );
    expect(button('Publish this week'), findsNothing);
  });

  testWidgets('TEAM-SCH-009 a draft week: "Draft" and the hint for who may '
      'publish it', (tester) async {
    final h = await pumpSchedule(tester);
    await h.tap(pressable('Next week'));
    expect(pageText('Draft'), findsOneWidget);
    expect(pageText(h.t('dawamOps.draftHint')), findsOneWidget);
  });

  testWidgets('TEAM-SCH-009 a draft week without the publish right', (
    tester,
  ) async {
    final s = scheduleServer();
    answerAuthz(s.server, ['hr.schedule.read', 'hr.schedule.edit']);
    final h = await pumpSchedule(tester, s: s);
    await h.tap(pressable('Next week'));
    expect(pageText(h.t('dawamOps.draftHintNoRight')), findsOneWidget);
    expect(button('Publish this week'), findsNothing);
  });

  testWidgets('TEAM-SCH-010 publish a draft week: confirm, POST, toast, then '
      'Published', (tester) async {
    final h = await pumpSchedule(tester, persona: Persona.manager);
    await h.tap(pressable('Next week'));
    await h.tap(button('Publish this week'));
    expect(
      inConfirm(find.text('Publish the week of 10 Oct 2026?')),
      findsOneWidget,
    );
    expect(inConfirm(find.text(h.t('dawam.publishHint'))), findsOneWidget);
    await h.tap(inConfirm(find.text('Publish')));
    final post = calls(h, publishT, 'POST').single;
    expect(bodyOf(post), {'branch_id': SeedIds.zamalek, 'week_start': wd(7)});
    await h.expectToast('Week published');
    expect(pageText('Published'), findsOneWidget);
    expect(button('Publish this week'), findsNothing);
  });

  testWidgets('TEAM-SCH-010 cancelling the confirm sends nothing', (
    tester,
  ) async {
    final h = await pumpSchedule(tester);
    await h.tap(pressable('Next week'));
    await h.tap(button('Publish this week'));
    await h.tap(inConfirm(find.text('Cancel')));
    expect(calls(h, publishT, 'POST'), isEmpty);
  });

  testWidgets('TEAM-SCH-073 while the week loads: Draft, and Publish shown '
      'but disabled', (tester) async {
    final h = await pumpSchedule(tester);
    final gate = h.server.hold('GET', rosterT);
    await h.tap(pressable('Next week'));
    expect(pageText('Draft'), findsOneWidget);
    expect(pageText(h.t('dawamOps.draftHint')), findsOneWidget);
    expect(enabled(tester, button('Publish this week')), isFalse);
    expect(find.byKey(const Key('schedule-skeleton')), findsOneWidget);
    gate.release();
    await h.settle();
    expect(enabled(tester, button('Publish this week')), isTrue);
  });

  testWidgets('TEAM-SCH-073 the fairness month is the viewed Saturday\'s', (
    tester,
  ) async {
    final h = await pumpSchedule(tester);
    expect(calls(h, fairnessT).last.query['month'], ['2026-10-01']);
    await h.tap(pressable('Previous week'));
    expect(calls(h, fairnessT).last.query['month'], ['2026-09-01']);
  });

  // ── notes above the grid ─────────────────────────────────────────────

  testWidgets('TEAM-SCH-011 the pattern note, its link to Work shifts with the '
      'edit right', (tester) async {
    final h = await pumpSchedule(tester);
    expect(pageHas(h.t('dawamOps.patternNote')), findsOneWidget);
    await h.tap(pressable(h.t('dawamOps.editPattern')));
    expect(h.location.path, '/staff/shifts');
  });

  testWidgets('TEAM-SCH-012 staff but no work shifts: the banner opens Work '
      'shifts', (tester) async {
    final h = await pumpSchedule(
      tester,
      edit: (db) =>
          db['work_shifts'].removeWhere((w) => w['org_id'] == SeedIds.sabahOrg),
    );
    expect(pageHas(h.t('dawamOps.noBlocksTitle')), findsOneWidget);
    await h.tap(button('Open Work shifts'));
    expect(h.location.path, '/staff/shifts');
  });

  testWidgets('TEAM-SCH-013 the labour note: unconfirmed limits, or a plain '
      'warning', (tester) async {
    final h = await pumpSchedule(tester);
    expect(pageText(h.t('dawam.warningsUnconfirmed')), findsOneWidget);
  });

  testWidgets('TEAM-SCH-013 confirmed limits: the plain warning', (
    tester,
  ) async {
    final h2 = await pumpSchedule(
      tester,
      edit: (db) {
        for (final s in db['attendance_settings'].rows) {
          s['limits_confirmed'] = true;
        }
      },
    );
    expect(pageText(h2.t('dawam.warningsNote')), findsOneWidget);
    expect(pageText(h2.t('dawam.warningsUnconfirmed')), findsNothing);
  });

  // ── roster states ────────────────────────────────────────────────────

  testWidgets('TEAM-SCH-014 loading: the skeleton, never empty or failed', (
    tester,
  ) async {
    final s = scheduleServer();
    final gate = s.server.hold('GET', rosterT);
    final h = await pumpSchedule(tester, s: s);
    expect(find.byKey(const Key('schedule-skeleton')), findsOneWidget);
    expect(pageText(h.t('staff.noEmployeesYet')), findsNothing);
    expect(pageText(h.t('staff.rosterLoadError')), findsNothing);
    gate.release();
    await h.settle();
    expect(grid, findsOneWidget);
  });

  testWidgets('TEAM-SCH-014 failed: the error, Retry asks only the roster', (
    tester,
  ) async {
    final s2 = scheduleServer();
    s2.server.fail('GET', rosterT, MockResponse.error(500, 'boom'), times: 2);
    final h2 = await pumpSchedule(tester, s: s2);
    expect(pageText(h2.t('staff.rosterLoadError')), findsOneWidget);
    final sg = calls(h2, suggestionsT).length;
    await h2.tap(inPage(find.text('Retry')));
    expect(grid, findsOneWidget);
    expect(calls(h2, suggestionsT), hasLength(sg));
  });

  testWidgets('TEAM-SCH-015 no active staff: the empty state opens Employees', (
    tester,
  ) async {
    final h = await pumpSchedule(
      tester,
      edit: (db) {
        for (final e in db['employees'].rows) {
          if ((e['branch_ids'] as List?)?.contains(SeedIds.zamalek) ?? false) {
            e['employment_status'] = 'terminated';
          }
        }
      },
    );
    expect(pageText(h.t('staff.noEmployeesYet')), findsOneWidget);
    expect(pageText(h.t('dawamOps.noStaffHint')), findsOneWidget);
    expect(pageHas(h.t('dawamOps.patternNote')), findsNothing);
    await h.tap(button('Open Employees'));
    expect(h.location.path, '/staff/employees');
  });

  // ── the grid ─────────────────────────────────────────────────────────

  testWidgets('TEAM-SCH-016 TEAM-ALL-011 the grid: Employee, then Sat → Fri '
      'with dates, today marked', (tester) async {
    final h = await pumpSchedule(tester);
    expect(inGrid(find.text('Employee')), findsOneWidget);
    final names = ['Sat', 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri'];
    final xs = [
      for (final n in names) tester.getCenter(inGrid(find.text(n))).dx,
    ];
    for (var i = 1; i < xs.length; i++) {
      expect(xs[i], greaterThan(xs[i - 1]), reason: names[i]);
    }
    expect(inGrid(find.text('03 Oct 2026')), findsOneWidget);
    expect(inGrid(find.text('Today')), findsOneWidget);
    expect(
      tester.getCenter(inGrid(find.text('Today'))).dx,
      moreOrLessEquals(xs[5], epsilon: 1),
    );
    expect(h.t('dawamOps.today'), 'Today');
  });

  testWidgets('TEAM-SCH-017 the person cell: preferences line and the '
      'preferences button', (tester) async {
    final h = await pumpSchedule(tester);
    expect(
      inGrid(find.text('Prefers evenings · set by a manager')),
      findsOneWidget,
    );
    expect(inGrid(pressable("Hassan Ibrahim's preferences")), findsOneWidget);
    await h.tap(inGrid(pressable("Hassan Ibrahim's preferences")));
    expect(surfaceText("Hassan Ibrahim's preferences"), findsOneWidget);
  });

  testWidgets('TEAM-SCH-018 day cells: Off, Day off, edited times past '
      'midnight, the changed dot', (tester) async {
    final h = await pumpSchedule(tester);
    expect(dayCell('Adham Reda', 2), findsOneWidget);
    Finder cell(String name, int day) => dayCell(name, day);
    Finder inCell(String name, int day, Finder f) =>
        find.descendant(of: cell(name, day), matching: f);
    expect(inCell('Adham Reda', 2, find.text('Off')), findsOneWidget);
    expect(inCell('Mariam Fathy', 6, find.text('Day off')), findsOneWidget);
    expect(inCell('Laila Ehab', 4, plainHas('16:00–00:00')), findsWidgets);
    expect(inCell('Laila Ehab', 4, find.text('Edited')), findsOneWidget);
    expect(inCell('Laila Ehab', 4, find.text('+1')), findsOneWidget);
    expect(inCell('Laila Ehab', 4, find.byType(ChangedDot)), findsOneWidget);
    expect(inCell('Adham Reda', 0, plainHas('07:00–15:00')), findsWidgets);
    expect(h.t('dawam.off'), 'Off');
  });

  testWidgets('TEAM-SCH-018 on leave: struck through and "On leave"', (
    tester,
  ) async {
    final h = await pumpSchedule(
      tester,
      edit: (db) => db['staff_requests'].insert({
        'org_id': SeedIds.sabahOrg,
        'employee_id': emp('adham'),
        'kind': 'leave',
        'status': 'approved',
        'on_date': wd(1),
        'end_date': wd(1),
      }),
    );
    final cell = dayCell('Adham Reda', 1);
    expect(
      find.descendant(of: cell, matching: find.text('On leave')),
      findsOneWidget,
    );
    final name = tester.widget<Text>(
      find.descendant(of: cell, matching: find.text('Morning')),
    );
    expect(name.style?.decoration, TextDecoration.lineThrough);
    expect(h.location.path, schedulePath);
  });

  testWidgets('TEAM-SCH-019 shifts at another branch: muted, "at <branch>", '
      'never "Off"', (tester) async {
    final h = await pumpSchedule(
      tester,
      edit: (db) {
        final adham = db['employees'].find(emp('adham'))!;
        adham['branch_ids'] = [SeedIds.zamalek, SeedIds.maadi];
        db['roster_day_sets'].put({
          'id': '${emp('adham')}|${wd(2)}',
          'employee_id': emp('adham'),
          'on_date': wd(2),
          'blocks': [
            {
              'work_shift_id': morningId,
              'start_time': null,
              'end_time': null,
              'branch_id': SeedIds.maadi,
            },
          ],
        });
      },
    );
    final cell = dayCell('Adham Reda', 2);
    expect(
      find.descendant(of: cell, matching: find.text('at Maadi')),
      findsOneWidget,
    );
    expect(find.descendant(of: cell, matching: find.text('Off')), findsNothing);
    expect(h.location.path, schedulePath);
  });

  testWidgets('TEAM-SCH-020 labour warnings: a chip per limit on the person '
      'and day, never a block', (tester) async {
    await pumpSchedule(tester);
    final cell = dayCell('Youssef Samir', 2);
    expect(
      find.descendant(of: cell, matching: find.text('Hours a day')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cell, matching: find.text('Presence a day')),
      findsOneWidget,
    );
    final tip = tester.widget<Tooltip>(
      find
          .ancestor(
            of: find.descendant(of: cell, matching: find.text('Hours a day')),
            matching: find.byType(Tooltip),
          )
          .first,
    );
    expect(tip.message, 'Hours a day: 16h / 12h');
  });

  testWidgets('TEAM-SCH-021 a day cell is a button with the edit right and '
      'opens the day editor', (tester) async {
    final h = await pumpSchedule(tester);
    expect(dayCells('Adham Reda'), findsNWidgets(7));
    await h.tap(dayCell('Adham Reda', 0));
    expect(inSurface(plainHas('Adham Reda, 03 Oct 2026')), findsWidgets);
  });

  testWidgets('TEAM-SCH-022 the legend under the grid', (tester) async {
    final h = await pumpSchedule(tester);
    for (final k in [
      'dawamOps.legend',
      'dawamOps.legendOff',
      'dawamOps.legendDayOff',
      'staff.endsNextDay',
      'dawamOps.legendEdited',
      'dawam.changedAfterPublish',
      'dawamOps.legendWarning',
    ]) {
      expect(inGrid(find.text(h.t(k))), findsOneWidget, reason: k);
    }
  });

  // ── open shifts ──────────────────────────────────────────────────────

  testWidgets('TEAM-SCH-023 the open-shifts row: a badge per open shift, the '
      'claimer named', (tester) async {
    final h = await pumpSchedule(
      tester,
      edit: (db) => db['open_shifts'].insert({
        'branch_id': SeedIds.zamalek,
        'work_shift_id': morningId,
        'shift_name': 'Morning',
        'on_date': wd(6),
        'status': 'claimed',
        'claimed_by': emp('karim'),
        'claimed_by_name': 'Karim Adel',
      }, timestamps: false),
    );
    expect(inGrid(find.text('Open shifts')), findsOneWidget);
    expect(inGrid(find.text('Evening')), findsWidgets);
    expect(inGrid(find.text('Morning · Karim Adel')), findsOneWidget);
    expect(h.location.path, schedulePath);
  });

  testWidgets('TEAM-SCH-024 take back an open shift: confirm, POST, toast', (
    tester,
  ) async {
    final h = await pumpSchedule(tester);
    final x = inGrid(pressable('Take back the open Evening on 09 Oct 2026'));
    await h.tap(x);
    expect(
      inConfirm(find.text('Take back the open Evening on 09 Oct 2026?')),
      findsOneWidget,
    );
    expect(inConfirm(find.text(h.t('dawam.cancelOpenHint'))), findsOneWidget);
    await h.tap(inConfirm(find.text('Take it back')));
    final post = calls(h, cancelOpenT, 'POST').single;
    expect(post.path, contains('/cancel'));
    await h.expectToast('Open shift taken back');
    expect(x, findsNothing);
  });

  testWidgets('TEAM-SCH-024 a claimed one says who will be told', (
    tester,
  ) async {
    final h = await pumpSchedule(
      tester,
      edit: (db) {
        final o = db['open_shifts'].rows.firstWhere(
          (o) => o['branch_id'] == SeedIds.zamalek && o['on_date'] == wd(6),
        );
        o['status'] = 'claimed';
        o['claimed_by_name'] = 'Karim Adel';
      },
    );
    await h.tap(inGrid(pressable('Take back the open Evening on 09 Oct 2026')));
    expect(
      inConfirm(find.text('Karim Adel claimed it and will be told.')),
      findsOneWidget,
    );
    await h.tap(inConfirm(find.text('Cancel')));
    expect(calls(h, cancelOpenT, 'POST'), isEmpty);
  });

  testWidgets('TEAM-SCH-025 post an open shift: the blocks that run that day '
      'at its times; a draft week says staff see it once published', (
    tester,
  ) async {
    final h = await pumpSchedule(tester);
    await h.tap(pressable('Next week'));
    await h.tap(inGrid(pressable('Post an open shift on 16 Oct 2026')));
    expect(find.text('Post an open shift'), findsOneWidget);
    await h.tap(find.text('Morning').hitTestable().last);
    final post = calls(h, openT, 'POST').single;
    expect(bodyOf(post), {
      'branch_id': SeedIds.zamalek,
      'on_date': wd(13),
      'work_shift_id': morningId,
    });
    await h.expectToast(h.t('dawam.openPostedUnpublished'));
    expect(inGrid(find.text('Morning')), findsWidgets);
  });

  testWidgets('TEAM-SCH-025 a published week: "Open shift posted"; a day no '
      'block runs: "No other shift runs that day"', (tester) async {
    final h = await pumpSchedule(
      tester,
      edit: (db) {
        for (final w in db['work_shifts'].rows) {
          if (w['org_id'] == SeedIds.sabahOrg) {
            w['valid_days'] = [0, 1, 2, 3, 4, 5];
          }
        }
      },
    );
    await h.tap(inGrid(pressable('Post an open shift on 09 Oct 2026')));
    await h.tap(find.text('Morning').hitTestable().last);
    await h.expectToast('Open shift posted');

    await h.tap(pressable('Next week'));
    await h.tap(inGrid(pressable('Post an open shift on 10 Oct 2026')));
    expect(find.text(h.t('dawam.noShiftThatDay')), findsOneWidget);
  });

  testWidgets('TEAM-SCH-026 a refusal toasts the server\'s words in the '
      'person\'s language; the button is back', (tester) async {
    final s = scheduleServer();
    final refusal = MockResponse.error(
      409,
      'That shift was already filled or cancelled.',
      code: 'OPEN_SHIFT_CLOSED',
    );
    s.server.fail('POST', cancelOpenT, refusal);
    final h = await pumpSchedule(tester, s: s);
    final x = inGrid(pressable('Take back the open Evening on 09 Oct 2026'));
    await h.tap(x);
    await h.tap(inConfirm(find.text('Take it back')));
    await h.expectToast(h.t('errors.codes.OPEN_SHIFT_CLOSED'));
    expect(tester.widget<DashPressable>(x).onTap, isNotNull);
  });

  testWidgets('TEAM-SCH-026 the busy action\'s own button waits', (
    tester,
  ) async {
    final h = await pumpSchedule(tester);
    final gate = h.server.hold('POST', cancelOpenT);
    final x = inGrid(pressable('Take back the open Evening on 09 Oct 2026'));
    await h.tap(x);
    await h.tap(inConfirm(find.text('Take it back')));
    expect(tester.widget<DashPressable>(x).onTap, isNull);
    gate.release();
    await h.settle();
    await h.flushTimers();
  });

  // ── suggestions ──────────────────────────────────────────────────────

  testWidgets('TEAM-SCH-030 suggestions loading: a skeleton', (tester) async {
    final s = scheduleServer();
    final gate = s.server.hold('GET', suggestionsT);
    final h = await pumpSchedule(tester, s: s);
    expect(inSuggestions(find.byType(DashSkeleton)), findsOneWidget);
    expect(inSuggestions(find.text(h.t('dawam.noSuggestions'))), findsNothing);
    gate.release();
    await h.settle();
  });

  testWidgets('TEAM-SCH-030 suggestions failed: the error (never "nothing"), '
      'Retry', (tester) async {
    final s2 = scheduleServer();
    s2.server.fail('GET', suggestionsT, MockResponse.error(500, 'boom'));
    final h2 = await pumpSchedule(tester, s: s2);
    expect(
      inSuggestions(find.text(h2.t('dawam.suggestionsLoadError'))),
      findsOneWidget,
    );
    expect(inSuggestions(find.text(h2.t('dawam.noSuggestions'))), findsNothing);
    await h2.tap(inSuggestions(find.text('Retry')));
    expect(
      inSuggestions(find.text(h2.t('dawam.suggestionsLoadError'))),
      findsNothing,
    );
  });

  testWidgets('TEAM-SCH-030 nothing to suggest', (tester) async {
    final s3 = scheduleServer();
    s3.server.on('GET', suggestionsT, (req) => MockResponse.ok(const []));
    final h3 = await pumpSchedule(tester, s: s3);
    expect(
      inSuggestions(find.text(h3.t('dawam.noSuggestions'))),
      findsOneWidget,
    );
  });

  testWidgets('TEAM-SCH-031 a suggestion row: who and what, when and why, '
      'confidence, Accept / Reject', (tester) async {
    await pumpSchedule(tester);
    final row = inSuggestions(find.text('Mariam Fathy → Evening'));
    expect(row, findsOneWidget);
    expect(
      inSuggestions(
        find.text(
          '09 Oct 2026 · Mariam Fathy has been off this day for 4 weeks: '
          'make it their standing day off',
        ),
      ),
      findsOneWidget,
    );
    expect(inSuggestions(plainHas('81%')), findsWidgets);
    expect(inSuggestions(find.text('Accept')), findsWidgets);
    expect(inSuggestions(find.text('Reject')), findsWidgets);
  });

  testWidgets('TEAM-SCH-032 a pattern suggestion confirms first, then POSTs; '
      'toast', (tester) async {
    final h = await pumpSchedule(tester);
    final row = find.ancestor(
      of: inSuggestions(find.text('Mariam Fathy → Evening')),
      matching: find.byType(ScheduleListRow),
    );
    await h.tap(find.descendant(of: row, matching: find.text('Accept')));
    expect(
      inConfirm(find.text("Change Mariam Fathy's standing pattern?")),
      findsOneWidget,
    );
    await h.tap(inConfirm(find.text('Accept')));
    final post = calls(h, decideT, 'POST').single;
    expect(bodyOf(post), {
      'branch_id': SeedIds.zamalek,
      'id': 'pattern|2026-10-09|off|${emp('mariam')}',
      'accept': true,
    });
    await h.expectToast('Suggestion accepted');
    expect(inSuggestions(find.text('Mariam Fathy → Evening')), findsNothing);
  });

  testWidgets('TEAM-SCH-032 reject: no confirm, accept false, toast', (
    tester,
  ) async {
    final h = await pumpSchedule(tester);
    final row = find.ancestor(
      of: inSuggestions(find.text('Mariam Fathy → Evening')),
      matching: find.byType(ScheduleListRow),
    );
    await h.tap(find.descendant(of: row, matching: find.text('Reject')));
    expect(confirm(), findsNothing);
    expect(bodyOf(calls(h, decideT, 'POST').single)['accept'], false);
    await h.expectToast('Suggestion rejected');
  });

  // ── holidays ─────────────────────────────────────────────────────────

  testWidgets('TEAM-SCH-033 public holidays: the next 45 days, named in the '
      'language, the hint with its date', (tester) async {
    final h = await pumpSchedule(tester);
    expect(inHolidays(find.text('Public holidays')), findsOneWidget);
    expect(inHolidays(find.text('Armed Forces Day')), findsOneWidget);
    expect(
      inHolidays(
        find.text(h.t('dawam.holidayHint', args: {'date': '06 Oct 2026'})),
      ),
      findsOneWidget,
    );
    final upcoming = calls(
      h,
      rosterT,
    ).where((c) => c.query['from']!.single == today);
    expect(upcoming.single.query['to'], ['2026-11-22']);
  });

  testWidgets('TEAM-SCH-033 no holiday around: no section', (tester) async {
    await pumpSchedule(
      tester,
      edit: (db) => db['public_holidays'].removeWhere((_) => true),
    );
    expect(find.byKey(const Key('schedule-holidays')), findsNothing);
  });

  testWidgets('TEAM-SCH-034 a manager reads them: "Not decided yet" and the '
      'owner-only note', (tester) async {
    final h = await pumpSchedule(tester, persona: Persona.manager);
    expect(inHolidays(find.text('Not decided yet')), findsOneWidget);
    expect(
      inHolidays(find.text(h.t('dawam.holidaysOwnerOnly'))),
      findsOneWidget,
    );
    expect(inHolidays(find.text('Make it a holiday')), findsNothing);
  });

  testWidgets('TEAM-SCH-034 decided ones keep their pill; the note stays '
      'without the right', (tester) async {
    final h = await pumpSchedule(
      tester,
      persona: Persona.manager,
      edit: (db) {
        for (final r in db['public_holidays'].rows) {
          r['decision'] = 'holiday';
        }
      },
    );
    expect(inHolidays(find.text('Holiday')), findsOneWidget);
    expect(
      inHolidays(find.text(h.t('dawam.holidaysOwnerOnly'))),
      findsOneWidget,
    );
  });

  testWidgets('TEAM-SCH-034/035 the owner decides: "Make it a holiday" PUTs; '
      'the pill follows', (tester) async {
    final h = await pumpSchedule(tester);
    expect(inHolidays(find.text(h.t('dawam.holidaysOwnerOnly'))), findsNothing);
    await h.tap(inHolidays(find.text('Make it a holiday')));
    final put = calls(h, holidayT, 'PUT').single;
    expect(put.path, '/staff/holidays/2026-10-06');
    expect(bodyOf(put), {'decision': 'holiday'});
    await h.expectToast('Set as a holiday');
    expect(inHolidays(find.text('Holiday')), findsOneWidget);
  });

  testWidgets('TEAM-SCH-035 "Normal day" dismisses it', (tester) async {
    final h = await pumpSchedule(tester);
    await h.tap(inHolidays(find.widgetWithText(DashButton, 'Normal day')));
    expect(bodyOf(calls(h, holidayT, 'PUT').single), {'decision': 'dismissed'});
    await h.expectToast('Kept as a normal day');
    expect(
      inHolidays(find.widgetWithText(DashButton, 'Normal day')),
      findsNothing,
    );
    expect(inHolidays(find.text('Normal day')), findsOneWidget);
  });

  testWidgets('TEAM-ALL-017 a refusal coded RULES_NOT_SET reads in Arabic', (
    tester,
  ) async {
    final s = scheduleServer();
    s.server.fail(
      'PUT',
      holidayT,
      MockResponse.error(409, 'Rules not set', code: 'RULES_NOT_SET'),
    );
    final h = await pumpSchedule(tester, s: s, locale: 'ar');
    await h.tap(inHolidays(find.text(h.t('dawam.makeHoliday'))));
    await h.expectToast(h.t('errors.codes.RULES_NOT_SET'));
  });

  // ── read-only, language, layout ──────────────────────────────────────

  testWidgets('TEAM-SCH-070 read only: no day buttons, no open-shift '
      'controls, no suggestions, no coverage, no pattern link', (tester) async {
    final s = scheduleServer();
    answerAuthz(s.server, ['hr.schedule.read']);
    final h = await pumpSchedule(tester, s: s);
    expect(inGrid(find.text('Adham Reda')), findsOneWidget);
    expect(dayCells('Adham Reda'), findsNothing);
    expect(inGrid(pressableStarting('Post an open shift')), findsNothing);
    expect(inGrid(pressableStarting('Take back the open')), findsNothing);
    expect(find.byKey(const Key('schedule-suggestions')), findsNothing);
    expect(calls(h, suggestionsT), isEmpty);
    expect(button('Coverage needs'), findsNothing);
    expect(pressable(h.t('dawamOps.editPattern')), findsNothing);
    expect(inHolidays(find.text('Not decided yet')), findsOneWidget);
    expect(find.byType(FairnessCard), findsNothing);
    expect(calls(h, fairnessT), isEmpty);
  });

  testWidgets('TEAM-SCH-071 Arabic: weekdays, dates and pills translated, '
      'times left to right, arrows mirrored', (tester) async {
    final h = await pumpSchedule(tester, locale: 'ar');
    expect(inGrid(find.text('السبت')), findsOneWidget);
    expect(pageText(h.t('dawam.isPublished')), findsOneWidget);
    final times = tester
        .widgetList<Text>(inGrid(plainHas('07:00–15:00')))
        .first
        .data!;
    expect(times.startsWith(lri), isTrue);
    final prev = tester.getCenter(pressable(h.t('dawam.prevWeek'))).dx;
    final next = tester.getCenter(pressable(h.t('dawam.nextWeek'))).dx;
    expect(prev, greaterThan(next), reason: 'previous sits on the right');
    final sat = tester.getCenter(inGrid(find.text('السبت'))).dx;
    final fri = tester.getCenter(inGrid(find.text('الجمعة'))).dx;
    expect(sat, greaterThan(fri));
  });

  testWidgets('TEAM-SCH-072 phone: the toolbar wraps without splitting the '
      'arrows and the range; the grid scrolls under a pinned name', (
    tester,
  ) async {
    final h = await pumpSchedule(tester, size: DashSize.phone);
    final group = tester.getRect(weekBar);
    for (final f in [
      pressable('Previous week'),
      pressable('Next week'),
      find.text('This week'),
    ]) {
      final r = tester.getRect(find.descendant(of: weekBar, matching: f));
      expect(group.contains(r.center), isTrue);
    }
    expect(
      tester.getCenter(pressable('Previous week')).dy,
      moreOrLessEquals(tester.getCenter(pressable('Next week')).dy, epsilon: 1),
    );
    final name = inGrid(find.text('Adham Reda'));
    final before = tester.getCenter(name).dx;
    final fri = inGrid(find.text('Fri'));
    final friBefore = tester.getCenter(fri).dx;
    await tester.ensureVisible(dayCell('Adham Reda', 0));
    await h.settle();
    final before2 = tester.getCenter(name).dx;
    await tester.dragFrom(
      tester.getCenter(dayCell('Adham Reda', 1)),
      const Offset(-300, 0),
    );
    await h.settle();
    expect(tester.getCenter(name).dx, moreOrLessEquals(before2, epsilon: 1));
    expect(before2, moreOrLessEquals(before, epsilon: 1));
    expect(tester.getCenter(fri).dx, lessThan(friBefore));
    expect(
      tester.getSize(inGrid(pressable("Adham Reda's preferences"))).width,
      greaterThanOrEqualTo(44),
    );
  });

  // ── refresh and live ─────────────────────────────────────────────────

  testWidgets('TEAM-ALL-008 Refresh asks again what the page shows', (
    tester,
  ) async {
    final h = await pumpSchedule(tester);
    final week0 = weekCalls(h, week).length;
    final sg = calls(h, suggestionsT).length;
    await h.tap(inPage(find.byType(DawamRefreshButton)));
    expect(weekCalls(h, week), hasLength(week0 + 1));
    expect(calls(h, suggestionsT), hasLength(sg + 1));
  });

  testWidgets('TEAM-ALL-008 Refresh spins while the coverage, fairness or '
      'audits read is fetching', (tester) async {
    final h = await pumpSchedule(tester);
    await h.tap(button('Coverage needs'));
    final refresh = inPage(find.byType(DawamRefreshButton));
    bool spinning() => tester.widget<DawamRefreshButton>(refresh).busy;
    for (final path in [coverageT, fairnessT, auditsT]) {
      final gate = h.server.hold('GET', path);
      await h.tap(refresh);
      expect(spinning(), isTrue, reason: path);
      gate.release();
      await h.settle();
      expect(spinning(), isFalse, reason: path);
    }
  });

  testWidgets('TEAM-ALL-022 a failed background refresh keeps the grid and '
      'toasts once', (tester) async {
    final h = await pumpSchedule(tester);
    h.server.fail('GET', rosterT, MockResponse.error(500, 'boom'), times: null);
    await h.tap(inPage(find.byType(DawamRefreshButton)));
    expect(grid, findsOneWidget);
    expect(pageText(h.t('staff.rosterLoadError')), findsNothing);
    await h.expectToast(h.refusalWords(MockResponse.error(500, 'boom')));
  });

  testWidgets('TEAM-ALL-009 back in the app after 30 s refetches the week; '
      'sooner does nothing; the coverage editor never', (tester) async {
    final h = await pumpSchedule(tester);
    await h.tap(button('Coverage needs'));
    Future<void> resume() async {
      for (final s in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
      await h.settle();
    }

    final n = weekCalls(h, week).length;
    final cov = calls(h, coverageT).length;
    await resume();
    expect(weekCalls(h, week), hasLength(n));
    h.db!.clock.advance(const Duration(seconds: 31));
    await resume();
    expect(weekCalls(h, week), hasLength(n + 1));
    expect(calls(h, coverageT), hasLength(cov));
  });

  testWidgets('TEAM-ALL-021 the week is page state: leaving resets it', (
    tester,
  ) async {
    final h = await pumpSchedule(tester);
    await h.tap(pressable('Next week'));
    expect(pageText('Next week'), findsWidgets);
    await h.go('/staff/employees');
    await h.go(schedulePath);
    expect(pageText('This week'), findsOneWidget);
    expect(h.location.queryParameters, isEmpty);
  });

  testWidgets('TEAM-SCH-055 the coverage toggle shows the card, pressed', (
    tester,
  ) async {
    final h = await pumpSchedule(tester);
    expect(find.byType(CoverageCard), findsNothing);
    await h.tap(button('Coverage needs'));
    expect(find.byType(CoverageCard), findsOneWidget);
    expect(calls(h, coverageT).single.query['branch_id'], [SeedIds.zamalek]);
    expect(
      tester.widget<DashButton>(button('Coverage needs')).variant,
      DashButtonVariant.secondary,
    );
    await h.tap(button('Coverage needs'));
    expect(find.byType(CoverageCard), findsNothing);
  });
}
