// The Rules page (TEAM-RUL-001…015, 040, 045 and the area rows on it),
// driven through the real shell on the seeded mock.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_team/src/rules/rules_cards.dart';
import 'package:dashboard_team/src/rules/rules_page.dart';
import 'package:dashboard_team/src/rules/rules_preview_card.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'rules_support.dart';

void main() {
  testWidgets('TEAM-RUL-001 / TEAM-ALL-007 without hr.rules.edit or view: the '
      'page\'s own Restricted, nothing asked', (tester) async {
    final h = await pumpRules(tester, persona: Persona.limited);
    expect(find.text(h.t('staff.rulesNoAccess')), findsOneWidget);
    expect(find.text('Attendance rules'), findsWidgets);
    expect(h.server.callsTo(settingsT), isEmpty);
    expect(h.server.callsTo(branchesT), isEmpty);
  });

  testWidgets('TEAM-RUL-002 the header: title, description, Refresh, and the '
      'scope select below', (tester) async {
    final h = await pumpRules(tester);
    expect(pageText('Attendance rules'), findsOneWidget);
    expect(pageText(h.t('staff.rulesSubtitle')), findsOneWidget);
    expect(inPage(find.bySemanticsLabel('Refresh')), findsOneWidget);
    expect(pageText('The business (every branch)'), findsOneWidget);
    // The business's rules: no query, one shared read.
    expect(h.server.callsTo(settingsT).single.query, isEmpty);
  });

  testWidgets('TEAM-RUL-003 / TEAM-ALL-018/021 the scope select: the business, '
      'then each branch ("· own rules" when it overrides); a branch reads its '
      'own rules and the form resets', (tester) async {
    final h = await pumpRules(tester);
    await h.tap(find.byKey(RulesKeys.scope));
    for (final b in ['Heliopolis', 'Maadi', 'New Cairo']) {
      expect(find.text(b), findsWidgets, reason: b);
    }
    expect(find.text('Zamalek · own rules'), findsOneWidget);
    await h.tap(find.text('Zamalek · own rules').hitTestable().last);
    expect(
      h.server.callsTo(settingsT).last.query,
      {
        'branch_id': [SeedIds.zamalek],
      },
    );
    // Zamalek's own day limit (10 h) and auto-close (90 min).
    expect(shown(tester, RulesKeys.autoBuffer), '90');
    expect(pageText("This branch's own rules"), findsOneWidget);
    // The scope bar's branch is not sent: the page keeps its own scope.
    expect(h.location.path, rulesPath);
  });

  testWidgets('TEAM-RUL-004 loading: two skeleton cards under the header',
      (tester) async {
    final s = rulesServer();
    final gate = s.server.hold('GET', settingsT);
    final h = await pumpRules(tester, s: s);
    expect(find.byKey(const ValueKey('rules-skeleton')), findsOneWidget);
    expect(pageText('Attendance rules'), findsOneWidget);
    expect(pageText(h.t('staff.lateLadder')), findsNothing);
    gate.release();
    await h.settle();
    expect(pageText(h.t('staff.lateLadder')), findsOneWidget);
  });

  testWidgets('TEAM-RUL-004 error: "Couldn\'t load attendance rules", the '
      'words, and Retry asks only that read again', (tester) async {
    final s = rulesServer();
    final boom = MockResponse.error(500, 'boom');
    s.server.fail('GET', settingsT, boom, times: 1);
    final h = await pumpRules(tester, s: s);
    expect(pageText("Couldn't load attendance rules"), findsOneWidget);
    expect(pageText(h.refusalWords(boom)), findsOneWidget);
    final lists = h.server.callsTo(branchesT).length;
    await h.tap(inPage(find.text('Retry')));
    expect(pageText(h.t('staff.lateLadder')), findsOneWidget);
    expect(h.server.callsTo(branchesT).length, lists);
  });

  testWidgets('TEAM-RUL-005 read-only (hr.rules.view): the note, every '
      'control off, no rung buttons, no save bar', (tester) async {
    final h = await pumpRules(tester, persona: Persona.manager);
    expect(pageText(h.t('staff.rulesReadOnly')), findsOneWidget);
    expect(find.byKey(RulesKeys.saveBar), findsNothing);
    expect(find.byKey(RulesKeys.addTier), findsNothing);
    expect(find.byKey(RulesKeys.tierRemove(0)), findsNothing);
    final n = tester.widget<DashNumberInput>(
      find.byKey(RulesKeys.tierFrom(0)),
    );
    expect(n.enabled, isFalse);
    expect(
      tester.widget<DashSwitch>(find.byKey(RulesKeys.excused)).enabled,
      isFalse,
    );
    // A branch: chips without buttons, no "Follow the business".
    await pickIn(h, RulesKeys.scope, 'Zamalek · own rules');
    expect(find.byKey(RulesKeys.chip('limit_day_hours')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp("Use the business's")), findsNothing);
    expect(find.byKey(RulesKeys.follow), findsNothing);
  });

  testWidgets('TEAM-RUL-006 never saved: the warning, the suggested ladder '
      'filled in, "Not saved yet" on the bar', (tester) async {
    final h = await pumpRules(tester, edit: neverSaved);
    expect(pageText(h.t('dawam.rulesFirstTitle')), findsOneWidget);
    expect(pageText(h.t('staff.rulesSuggested')), findsOneWidget);
    // The server's suggestion: 1–15 min → 15 minutes of pay, …
    expect(shown(tester, RulesKeys.tierFrom(0)), '1');
    expect(shown(tester, RulesKeys.tierTo(3)), '');
    expect(find.text(h.t('staff.rulesNotSavedYet')), findsOneWidget);
  });

  testWidgets('TEAM-RUL-006 a viewer of never-saved rules gets the warning '
      'without the suggestion', (tester) async {
    final h = await pumpRules(
      tester,
      persona: Persona.manager,
      edit: neverSaved,
    );
    expect(pageText(h.t('dawam.rulesFirstTitle')), findsOneWidget);
    expect(pageText(h.t('staff.rulesSuggested')), findsNothing);
    expect(pageText(h.t('staff.noTiers')), findsOneWidget);
  });

  testWidgets('TEAM-RUL-007 a branch that follows the business says so; one '
      'that overrides lists a chip per rule', (tester) async {
    final h = await pumpRules(tester);
    await pickIn(h, RulesKeys.scope, 'Maadi');
    expect(pageText(h.t('staff.rulesBranchHint')), findsOneWidget);
    expect(pageText(h.t('staff.rulesBranchNone')), findsOneWidget);
    expect(find.byKey(RulesKeys.follow), findsNothing);
    await pickIn(h, RulesKeys.scope, 'Zamalek · own rules');
    expect(
      find.descendant(
        of: find.byKey(RulesKeys.chip('limit_day_hours')),
        matching: find.text('Hours a day'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(RulesKeys.chip('auto_checkout_buffer_minutes')),
        findsOneWidget);
  });

  testWidgets('TEAM-RUL-008 a chip hands its rule back (struck through) and '
      '"Keep" undoes it; the bar says unsaved', (tester) async {
    final h = await pumpRules(tester);
    await pickIn(h, RulesKeys.scope, 'Zamalek · own rules');
    expect(find.text(h.t('staff.rulesAllSaved')), findsOneWidget);
    await h.tap(find.bySemanticsLabel("Use the business's Hours a day"));
    final struck = tester.widget<Text>(
      find.descendant(
        of: find.byKey(RulesKeys.chip('limit_day_hours')),
        matching: find.text('Hours a day'),
      ),
    );
    expect(struck.style?.decoration, TextDecoration.lineThrough);
    expect(find.text(h.t('staff.rulesUnsaved')), findsOneWidget);
    await h.tap(find.bySemanticsLabel('Keep Hours a day'));
    expect(find.text(h.t('staff.rulesAllSaved')), findsOneWidget);
  });

  testWidgets('TEAM-RUL-010 the ladder card; no rungs → "No penalties"', (
    tester,
  ) async {
    final h = await pumpRules(tester);
    expect(pageText('Late arrival penalties'), findsOneWidget);
    expect(pageText(h.t('staff.lateLadderHint')), findsOneWidget);
    for (var i = 2; i >= 0; i--) {
      await tapKey(h, RulesKeys.tierRemove(i));
    }
    expect(pageText(h.t('staff.noTiers')), findsOneWidget);
  });

  testWidgets('TEAM-RUL-011/012 a rung\'s fields and read-back; changing the '
      'kind resets the amount (15 min / 0.25 day / EGP 50)', (tester) async {
    final h = await pumpRules(tester);
    // The seed's first rung: 15–30 min → 30 minutes of pay; 26 working
    // days, 8 h: 1,200,000 × 30 / (26 × 480) = 2,884.6 → EGP 28.85.
    expect(shown(tester, RulesKeys.tierFrom(0)), '15');
    expect(shown(tester, RulesKeys.tierTo(0)), '30');
    expect(
      pageText(
        '15–30 min late → 30 minutes of pay · about EGP 28.85 on the example '
        'salary',
      ),
      findsOneWidget,
    );
    // The open-ended last rung: 61+ → half a day = EGP 230.77.
    expect(
      pageText(
        "61+ min late → 0.5 of a day's pay · about EGP 230.77 on the example "
        'salary',
      ),
      findsOneWidget,
    );
    await pickIn(h, RulesKeys.tierKind(0), 'Fraction of a day');
    expect(shown(tester, RulesKeys.tierAmount(0)), '0.25');
    await pickIn(h, RulesKeys.tierKind(0), 'Fixed amount');
    expect(shown(tester, RulesKeys.tierAmount(0)), '50.00');
    expect(pageText('15–30 min late → EGP 50.00'), findsOneWidget);
    await pickIn(h, RulesKeys.tierKind(0), 'Minutes of pay');
    expect(shown(tester, RulesKeys.tierAmount(0)), '15');
  });

  testWidgets('TEAM-RUL-013/014 remove a rung; add one from the last end + 1, '
      '15 minutes long, 15 minutes of pay', (tester) async {
    final h = await pumpRules(tester);
    await tapKey(h, RulesKeys.tierRemove(2));
    expect(find.byKey(RulesKeys.tier(2)), findsNothing);
    await tapKey(h, RulesKeys.addTier);
    expect(shown(tester, RulesKeys.tierFrom(2)), '61');
    expect(shown(tester, RulesKeys.tierTo(2)), '75');
    expect(shown(tester, RulesKeys.tierAmount(2)), '15');
    expect(find.text(h.t('staff.rulesUnsaved')), findsOneWidget);
  });

  testWidgets('TEAM-RUL-015 ladder checks on change: overlap, inverted, not a '
      'number; Save off while one stands', (tester) async {
    final h = await pumpRules(tester);
    await typeIn(h, RulesKeys.tierFrom(1), '20');
    expect(pageText('Rungs overlap at 20 minutes'), findsOneWidget);
    expect(find.text(h.t('staff.rulesFixFirst')), findsOneWidget);
    expect(
      tester.widget<DashButton>(find.byKey(RulesKeys.save)).onPressed,
      isNull,
    );
    await typeIn(h, RulesKeys.tierFrom(1), '31');
    expect(pageText('Rungs overlap at 20 minutes'), findsNothing);
    await typeIn(h, RulesKeys.tierTo(1), '25');
    expect(pageText(h.t('staff.tierInverted')), findsOneWidget);
    await typeIn(h, RulesKeys.tierTo(1), 'abc');
    expect(pageText(h.t('staff.tierNotANumber')), findsOneWidget);
  });

  testWidgets('TEAM-RUL-040 the bar: unsaved → Discard resets to the loaded '
      'rules; all saved has no Discard', (tester) async {
    final h = await pumpRules(tester);
    expect(find.text(h.t('staff.rulesAllSaved')), findsOneWidget);
    expect(find.byKey(RulesKeys.discard), findsNothing);
    await typeIn(h, RulesKeys.workingDays, '22');
    expect(find.text(h.t('staff.rulesUnsaved')), findsOneWidget);
    await h.tap(find.byKey(RulesKeys.discard));
    expect(shown(tester, RulesKeys.workingDays), '26');
    expect(find.text(h.t('staff.rulesAllSaved')), findsOneWidget);
    expect(puts(h), isEmpty);
  });

  testWidgets('TEAM-RUL-045 phone: fields stack one per row, the save bar '
      'stays on screen', (tester) async {
    final h = await pumpRules(tester, size: DashSize.phone);
    final from = tester.getRect(find.byKey(RulesKeys.tierFrom(0)));
    final to = tester.getRect(find.byKey(RulesKeys.tierTo(0)));
    expect(to.top, greaterThan(from.bottom));
    final bar = tester.getRect(find.byKey(RulesKeys.saveBar));
    expect(bar.bottom, tester.getRect(page).bottom);
    expect(h.location.path, rulesPath);
  });

  testWidgets('TEAM-RUL-045 desktop: a rung\'s four fields on one line', (
    tester,
  ) async {
    await pumpRules(tester);
    final from = tester.getRect(find.byKey(RulesKeys.tierFrom(0)));
    final amount = tester.getRect(find.byKey(RulesKeys.tierAmount(0)));
    expect(amount.top, from.top);
    expect(amount.left, greaterThan(from.right));
  });

  testWidgets('TEAM-ALL-002 the Rules leaf shows for the owner and a '
      'view-only manager, hidden otherwise', (tester) async {
    Finder leaf() => find.descendant(
      of: find.byType(DashSidebar),
      matching: find.text('Rules'),
    );
    await pumpRules(tester);
    expect(leaf(), findsOneWidget);
    await pumpRules(tester, persona: Persona.manager);
    expect(leaf(), findsOneWidget);
    await pumpRules(tester, persona: Persona.limited);
    expect(leaf(), findsNothing);
  });

  testWidgets('TEAM-ALL-005 module off: the module refusal, nothing asked', (
    tester,
  ) async {
    final h = await pumpRules(
      tester,
      edit: (db) => db['orgs'].update(SeedIds.sabahOrg, {
        'modules': ['pos'],
      }),
    );
    expect(find.text(h.t('dawam.moduleOffTitle')), findsOneWidget);
    expect(page, findsNothing);
    expect(h.server.callsTo(branchesT), isEmpty);
  });

  testWidgets('TEAM-ALL-008 Refresh asks both reads again and spins while '
      'they are in flight', (tester) async {
    final h = await pumpRules(tester);
    final gets = settingsGets(h);
    final lists = h.server.callsTo(branchesT).length;
    final gate = h.server.hold('GET', branchesT);
    await h.tap(inPage(find.bySemanticsLabel('Refresh')));
    expect(inPage(find.bySemanticsLabel('Refreshing…')), findsOneWidget);
    gate.release();
    await h.settle();
    expect(settingsGets(h), gets + 1);
    expect(h.server.callsTo(branchesT).length, lists + 1);
  });

  testWidgets('TEAM-ALL-009 back after 30 s: an editor\'s form is never '
      'refetched, the branch list is', (tester) async {
    final h = await pumpRules(tester);
    final gets = settingsGets(h);
    final lists = h.server.callsTo(branchesT).length;
    h.server.clock.advance(const Duration(seconds: 31));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await h.settle();
    expect(settingsGets(h), gets);
    expect(h.server.callsTo(branchesT).length, lists + 1);
  });

  testWidgets('TEAM-ALL-009 a viewer\'s rules refetch on focus after 30 s, '
      'not sooner', (tester) async {
    final h = await pumpRules(tester, persona: Persona.manager);
    final gets = settingsGets(h);
    h.server.clock.advance(const Duration(seconds: 10));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await h.settle();
    expect(settingsGets(h), gets);
    h.server.clock.advance(const Duration(seconds: 30));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await h.settle();
    expect(settingsGets(h), gets + 1);
  });

  testWidgets('TEAM-ALL-009 a background refresh re-seeds an untouched form '
      'and keeps an edited one', (tester) async {
    final s = rulesServer();
    final h = await pumpRules(tester, s: s);
    s.db['attendance_settings'].rows.first['working_days_per_month'] = 24.0;
    await h.tap(inPage(find.bySemanticsLabel('Refresh')));
    expect(shown(tester, RulesKeys.workingDays), '24');
    await typeIn(h, RulesKeys.absenceDays, '2');
    s.db['attendance_settings'].rows.first['working_days_per_month'] = 22.0;
    await h.tap(inPage(find.bySemanticsLabel('Refresh')));
    expect(shown(tester, RulesKeys.absenceDays), '2');
    expect(shown(tester, RulesKeys.workingDays), '24');
  });

  testWidgets('TEAM-ALL-010/022 a failed refresh swaps the form for the '
      'skeleton (the web\'s `isLoading || error`) and one toast says it', (
    tester,
  ) async {
    final h = await pumpRules(tester);
    h.server.fail(
      'GET',
      settingsT,
      MockResponse.error(429, 'Too many requests'),
      times: 1,
    );
    await h.tap(inPage(find.bySemanticsLabel('Refresh')));
    expect(find.byKey(const ValueKey('rules-skeleton')), findsOneWidget);
    await h.expectToast(h.t('errors.tooManyRequests'));
    await h.tap(inPage(find.bySemanticsLabel('Refresh')));
    expect(pageText(h.t('staff.lateLadder')), findsOneWidget);
  });

  testWidgets('TEAM-ALL-010 a refresh Riverpod still retries keeps the form: '
      'a 500 then a 200', (tester) async {
    final s = rulesServer();
    final c = ProviderContainer(
      retry: webRetry,
      overrides: [
        transportProvider.overrideWithValue(s.server),
        orgIdProvider.overrideWithValue(SeedIds.sabahOrg),
      ],
    );
    addTearDown(c.dispose);
    final seen = <AsyncValue<Object?>>[];
    final sub = c.listen(
      staffAttendanceSettingsProvider,
      (_, next) => seen.add(next),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(rulesFormHidden(sub.read()), isFalse);
    s.server.fail(
      'GET',
      settingsT,
      MockResponse.error(500, 'boom'),
      times: 1,
    );
    seen.clear();
    c.invalidate(staffAttendanceSettingsProvider);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(seen.any((q) => q.hasError && q.retrying), isTrue);
    expect(seen.where(rulesFormHidden), isEmpty);
    expect(sub.read().hasError, isFalse);
    expect(s.server.callsTo(settingsT).length, 3);
    sub.close();
  });

  testWidgets('TEAM-ALL-013 (divergence) in Arabic: Latin digits, the read-back arrow '
      'points the way the line reads', (tester) async {
    final h = await pumpRules(tester, locale: 'ar');
    expect(shown(tester, RulesKeys.tierFrom(0)), '15');
    expect(
      find.textContaining(RegExp('15–30.*←')),
      findsWidgets,
    );
    expect(h.location.path, rulesPath);
  });

  testWidgets('TEAM-ALL-023 the settings read: a 403 once, a 500 twice, a '
      '429 four times', (tester) async {
    Future<int> asks(MockResponse answer) async {
      final s = rulesServer();
      s.server.fail('GET', settingsT, answer, times: null);
      final c = ProviderContainer(
        retry: webRetry,
        overrides: [
          transportProvider.overrideWithValue(s.server),
          orgIdProvider.overrideWithValue(SeedIds.sabahOrg),
        ],
      );
      final sub = c.listen(staffAttendanceSettingsProvider, (_, _) {});
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      sub.close();
      c.dispose();
      return s.server.callsTo(settingsT).length;
    }

    expect(await asks(MockResponse.denied('hr.rules.view')), 1);
    expect(await asks(MockResponse.error(500, 'boom')), 2);
    expect(await asks(MockResponse.error(429, 'Slow down')), 4);
  });

  testWidgets('TEAM-ALL-018 the scope bar\'s branch is ignored: the page '
      'opens on the business, its read names no branch', (tester) async {
    final h = await pumpRules(
      tester,
      prefs: {
        ScopePrefKeys.branch: jsonEncode({
          'org': SeedIds.sabahOrg,
          'branch': SeedIds.zamalek,
        }),
      },
    );
    expect(pageText('The business (every branch)'), findsOneWidget);
    expect(h.server.callsTo(settingsT).single.query, isEmpty);
    expect(h.server.callsTo(branchesT).single.query, isEmpty);
  });

  testWidgets('TEAM-ALL-025 a number the field can\'t read says so and the '
      'form refuses to save', (tester) async {
    final h = await pumpRules(tester);
    // A field with no form check of its own shows the kit's words …
    await typeIn(h, RulesPreviewKeys.late, 'abc');
    expect(find.textContaining("isn't a number"), findsOneWidget);
    // … one the form checks shows the form's.
    await typeIn(h, RulesKeys.workingDays, 'abc');
    expect(pageText(h.t('staff.workingDaysPositive')), findsOneWidget);
    expect(find.text(h.t('staff.rulesFixFirst')), findsOneWidget);
    await tapKey(h, RulesKeys.save);
    await h.expectToast(h.t('staff.workingDaysPositive'));
    expect(puts(h), isEmpty);
  });
}
