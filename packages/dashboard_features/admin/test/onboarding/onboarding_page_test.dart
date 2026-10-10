// Driven tests of the wizard's frame (ADM-ONB-001..011, 023..031): the
// first-run gate, the top bar and Skip, the progress and its cheer, the
// states, both layouts, the step navigator, the panel's Back / Continue, the
// finale and the celebration, the live mirror.
import 'package:dashboard_admin/src/onboarding/celebration.dart';
import 'package:dashboard_admin/src/onboarding/dashboard_mirror.dart';
import 'package:dashboard_admin/src/onboarding/step_navigator.dart';
import 'package:dashboard_admin/src/onboarding/step_panel.dart';
import 'dart:convert';

import 'package:dashboard_admin/src/mock/onboarding_mock.dart';
import 'package:dashboard_api/dashboard_api.dart' show ApiException, ApiRequest;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show DashSidebar;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Finder get _nav => find.byType(OnbStepNavigator);
Finder get _mirror => find.byType(OnbDashboardMirror);

/// The navigator's button for the step titled [title].
DashPressable _stepButton(String title) =>
    find
            .ancestor(of: _inNav(title), matching: find.byType(DashPressable))
            .evaluate()
            .first
            .widget
        as DashPressable;

/// The glyph the step titled [title] draws in its disc.
String _glyph(String title) =>
    (find
                .descendant(
                  of: find.ancestor(
                    of: _inNav(title),
                    matching: find.byType(DashPressable),
                  ),
                  matching: find.byType(DashIcon),
                )
                .evaluate()
                .first
                .widget
            as DashIcon)
        .name;

Finder _inNav(String text) =>
    find.descendant(of: _nav, matching: find.text(text));
Finder _inMirror(String text) =>
    find.descendant(of: _mirror, matching: find.text(text));

void main() {
  group('gate and frame', () {
    testWidgets('ADM-ONB-001 signed out: sign-in first, then back here', (
      tester,
    ) async {
      final h = await pumpOnboarding(tester, persona: null);
      expect(h.location.path, '/login');
      expect(h.location.queryParameters['redirect'], onboardingPath);
    });

    testWidgets('ADM-ONB-001 full screen: no sidebar, no header', (
      tester,
    ) async {
      final h = await pumpOnboarding(tester);
      expect(h.location.path, onboardingPath);
      expect(page, findsOneWidget);
      expect(find.byType(DashSidebar), findsNothing);
    });

    testWidgets('ADM-ONB-002 top bar: title, sub-line, Skip for now', (
      tester,
    ) async {
      await pumpOnboarding(tester);
      expect(inPage("Let's open your café"), findsOneWidget);
      expect(
        inPage(
          'A few quick steps — watch your dashboard come to life as you go.',
        ),
        findsOneWidget,
      );
      expect(buttonOf('Skip for now'), findsOneWidget);
    });

    testWidgets('ADM-ONB-003/029 Skip ends the gate for the session; Back '
        'without it lands here again', (tester) async {
      final s = onboardingServer();
      freshCafe(s.db);
      final h = await pumpOnboarding(tester, server: s.server, db: s.db);
      h.allowUnmatched = true;
      // ADM-ONB-029: the shell page the gate came from sends them back.
      await h.go('/');
      expect(h.location.path, onboardingPath);
      await h.tap(buttonOf('Skip for now'));
      expect(h.location.path, '/');
      expect(h.container.read(onboardingSkippedProvider), isTrue);
      await h.go('/');
      expect(h.location.path, '/');
    });
  });

  group('progress', () {
    testWidgets('ADM-ONB-004 nothing done: 0% and Let\'s go!', (tester) async {
      final s = onboardingServer();
      freshCafe(s.db);
      await pumpOnboarding(tester, server: s.server, db: s.db);
      expect(inPage('0% ready to open'), findsOneWidget);
      expect(inPage("Let's go!"), findsOneWidget);
    });

    for (final (n, pct, cheer) in [
      (1, 25, 'Nice start!'),
      (2, 50, 'Halfway there!'),
      (3, 75, 'Almost there!'),
      (4, 100, 'Ready to open!'),
    ]) {
      testWidgets('ADM-ONB-004 $n of 4 required: $pct% and $cheer', (
        tester,
      ) async {
        final s = onboardingServer();
        freshCafe(s.db);
        if (n >= 1) addBranch(s.db);
        if (n >= 2) addPaymentMethod(s.db);
        final cat = n >= 3 ? addCategory(s.db) : null;
        if (n >= 4) addItem(s.db, cat!);
        // Optional steps never move it.
        addIngredient(s.db);
        await pumpOnboarding(tester, server: s.server, db: s.db);
        expect(inPage('$pct% ready to open'), findsOneWidget);
        expect(inPage(cheer), findsOneWidget);
        final fill = tester.widget<FractionallySizedBox>(
          find.byKey(const ValueKey('onb-progress-fill')),
        );
        expect(fill.widthFactor, closeTo(pct / 100, 1e-9));
      });
    }
  });

  group('states', () {
    testWidgets('ADM-ONB-005 loading: three skeleton panels', (tester) async {
      final s = onboardingServer();
      final gate = s.server.hold('GET', statusRoute);
      final h = await pumpOnboarding(tester, server: s.server, db: s.db);
      final loading = find.byKey(const ValueKey('onb-loading'));
      expect(loading, findsOneWidget);
      expect(
        find.descendant(of: loading, matching: find.byType(DashSkeleton)),
        findsNWidgets(3),
      );
      gate.release();
      await h.settle();
      expect(loading, findsNothing);
      expect(_nav, findsOneWidget);
    });

    testWidgets('ADM-ONB-005 loading on a phone: two panels', (tester) async {
      final s = onboardingServer();
      final gate = s.server.hold('GET', statusRoute);
      final h = await pumpOnboarding(
        tester,
        server: s.server,
        db: s.db,
        size: DashSize.phone,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('onb-loading')),
          matching: find.byType(DashSkeleton),
        ),
        findsNWidgets(2),
      );
      gate.release();
      await h.settle();
    });

    testWidgets('ADM-ONB-005 a platform admin with no org picked: the '
        'skeletons, nothing asked', (tester) async {
      final h = await pumpOnboarding(tester, persona: Persona.platform);
      expect(find.byKey(const ValueKey('onb-loading')), findsOneWidget);
      expect(h.server.callsTo(statusRoute), isEmpty);
    });

    testWidgets('ADM-ONB-006 error: the red panel and Refresh asks again', (
      tester,
    ) async {
      final s = onboardingServer();
      s.server.fail(
        'GET',
        statusRoute,
        MockResponse.error(500, 'boom'),
        times: null,
      );
      final h = await pumpOnboarding(tester, server: s.server, db: s.db);
      expect(inPage("Couldn't load your setup"), findsOneWidget);
      expect(_nav, findsNothing);
      final before = statusReads(h.server);
      s.server.clearFailures();
      await h.tap(buttonOf('Refresh'));
      expect(statusReads(h.server), before + 1);
      expect(inPage("Couldn't load your setup"), findsNothing);
      expect(_nav, findsOneWidget);
    });

    for (final persona in [Persona.manager, Persona.limited]) {
      testWidgets(
        'ADM-ONB-006 (refusal) ${persona.name}: the server refuses the '
        'checklist, the page says so',
        (tester) async {
          final h = await pumpOnboarding(tester, persona: persona);
          expect(h.location.path, onboardingPath);
          expect(h.server.callsTo(statusRoute).last.status, 403);
          expect(inPage("Couldn't load your setup"), findsOneWidget);
        },
      );
    }
  });

  group('layout and steps', () {
    testWidgets('ADM-ONB-007 from 1024: navigator · panel · mirror', (
      tester,
    ) async {
      await pumpOnboarding(tester, size: DashSize.tablet);
      expect(_nav, findsOneWidget);
      expect(_mirror, findsOneWidget);
    });

    testWidgets('ADM-ONB-007 phone: no navigator; panel above the mirror', (
      tester,
    ) async {
      final s = onboardingServer();
      freshCafe(s.db);
      await pumpOnboarding(
        tester,
        server: s.server,
        db: s.db,
        size: DashSize.phone,
      );
      expect(_nav, findsNothing);
      expect(_mirror, findsOneWidget);
      final panelTop = tester.getTopLeft(inPage('Name your café').first).dy;
      expect(panelTop, lessThan(tester.getTopLeft(_mirror).dy));
    });

    testWidgets('ADM-ONB-008 opens on the first unfinished step', (
      tester,
    ) async {
      final s = onboardingServer();
      freshCafe(s.db);
      s.db['orgs'].get(sabah)['logo_url'] = 'data:image/png;base64,AA==';
      addBranch(s.db);
      await pumpOnboarding(tester, server: s.server, db: s.db);
      expect(inPage('How you get paid'), findsWidgets);
      expect(
        inPage(
          'Cash, card, wallet — set up the ways customers pay so the '
          'drawer balances.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('ADM-ONB-008 a fresh café opens on Name your café; a '
        'finished one on Open your café', (tester) async {
      final s = onboardingServer();
      freshCafe(s.db);
      await pumpOnboarding(tester, server: s.server, db: s.db);
      expect(inPage('Name your café'), findsWidgets);
    });

    testWidgets('ADM-ONB-008 every step done: the finale', (tester) async {
      final s = onboardingServer();
      everythingDone(s.db);
      await pumpOnboarding(tester, server: s.server, db: s.db);
      expect(inPage('Ready to open your café'), findsOneWidget);
    });

    testWidgets('ADM-ONB-009 navigator: stages, Optional, counts, lock', (
      tester,
    ) async {
      final s = onboardingServer();
      freshCafe(s.db);
      addCategory(s.db);
      addCategory(s.db, name: 'Pastries', ar: 'مخبوزات');
      final h = await pumpOnboarding(tester, server: s.server, db: s.db);
      for (final stage in [
        'YOUR CAFÉ',
        'YOUR BRANCH',
        'GET PAID',
        'YOUR MENU',
        'YOUR TEAM',
        'GO LIVE',
      ]) {
        expect(_inNav(stage), findsOneWidget, reason: stage);
      }
      // Required steps carry no badge; the optional ones do (not go_live).
      expect(_inNav('Optional'), findsNWidgets(5));
      // Categories are done: a check, no "added" line.
      expect(_inNav('2 added'), findsNothing);
      expect(_glyph('Organize your menu'), 'check');
      // Not done: the step's own glyph; the finale: a lock.
      expect(_glyph('Stock your pantry'), 'sprout');
      expect(_glyph('Open your café'), 'lock');
      // The current step (the first unfinished one) is marked, only it.
      expect(_stepButton('Name your café').selected, isTrue);
      expect(_stepButton('Organize your menu').selected, isFalse);
      expect(
        tester
            .widgetList<DashPressable>(
              find.descendant(of: _nav, matching: find.byType(DashPressable)),
            )
            .where((p) => p.selected ?? false)
            .length,
        1,
      );
      // Go live is locked until the server allows it.
      final goLive = find.descendant(
        of: _nav,
        matching: find.bySemanticsLabel(RegExp('Open your café')),
      );
      await tester.tap(goLive, warnIfMissed: false);
      await h.settle();
      expect(inPage('Ready to open your café'), findsNothing);
      // Tapping a step selects it.
      await h.tap(
        find.descendant(
          of: _nav,
          matching: find.bySemanticsLabel(RegExp('Stock your pantry')),
        ),
      );
      expect(inPage('Add an ingredient'), findsOneWidget);
      expect(_stepButton('Stock your pantry').selected, isTrue);
      expect(_stepButton('Name your café').selected, isFalse);
    });

    testWidgets('ADM-ONB-009 a step with some but not done shows N added', (
      tester,
    ) async {
      final s = onboardingServer();
      freshCafe(s.db);
      final status = onboardingStatus(s.db, sabah);
      for (final step
          in (status['steps']! as List).cast<Map<String, Object?>>()) {
        if (step['key'] == 'ingredients') step['count'] = 3;
      }
      s.server.fail('GET', statusRoute, MockResponse.ok(status), times: null);
      await pumpOnboarding(tester, server: s.server, db: s.db);
      expect(_inNav('3 added'), findsOneWidget);
    });

    testWidgets('ADM-ONB-010/011 panel: title, description, Back and '
        'Continue', (tester) async {
      final s = onboardingServer();
      freshCafe(s.db);
      final h = await pumpOnboarding(tester, server: s.server, db: s.db);
      expect(
        inPage(
          "Add your name, logo and currency — they show up across the "
          "dashboard and your customers' menu.",
        ),
        findsOneWidget,
      );
      // `min-h-[28rem]`: the panel never shrinks below 448.
      expect(
        tester.getSize(find.byType(OnbStepPanel)).height,
        greaterThanOrEqualTo(448),
      );
      // The first step: Back is off.
      expect(button(tester, 'Back').onPressed, isNull);
      await h.tap(buttonOf('Continue'));
      expect(inPage('Add your first branch'), findsWidgets);
      expect(button(tester, 'Back').onPressed, isNotNull);
      // ADM-ONB-031: the step is page state, never in the address.
      expect(h.location.toString(), onboardingPath);
      await h.tap(buttonOf('Back'));
      expect(inPage('Name your café'), findsWidgets);
    });

    testWidgets('ADM-ONB-011 Continue from Invite your team opens the '
        'finale even while it is locked', (tester) async {
      final s = onboardingServer();
      freshCafe(s.db);
      final h = await pumpOnboarding(tester, server: s.server, db: s.db);
      await h.tap(
        find.descendant(
          of: _nav,
          matching: find.bySemanticsLabel(RegExp('Invite your team')),
        ),
      );
      await h.tap(buttonOf('Continue'));
      expect(inPage('Ready to open your café'), findsOneWidget);
      // No footer on the finale.
      expect(buttonOf('Continue'), findsNothing);
      expect(buttonOf('Back'), findsNothing);
    });
  });

  group('go live', () {
    testWidgets('ADM-ONB-023 not ready: the sentence, Open my café off', (
      tester,
    ) async {
      final s = onboardingServer();
      freshCafe(s.db);
      final h = await pumpOnboarding(tester, server: s.server, db: s.db);
      await h.tap(
        find.descendant(
          of: _nav,
          matching: find.bySemanticsLabel(RegExp('Invite your team')),
        ),
      );
      await h.tap(buttonOf('Continue'));
      expect(
        inPage(
          'Finish the required steps (branch, payments, a category and a '
          'menu item) to open your café.',
        ),
        findsOneWidget,
      );
      expect(button(tester, 'Open my café').onPressed, isNull);
    });

    testWidgets('ADM-ONB-023/024/031 Open my café: the celebration, then '
        'the dashboard', (tester) async {
      final s = onboardingServer();
      readyCafe(s.db);
      final h = await pumpOnboarding(tester, server: s.server, db: s.db);
      h.allowUnmatched = true;
      expect(inPage('Name your café'), findsWidgets);
      await h.tap(
        find.descendant(
          of: _nav,
          matching: find.bySemanticsLabel(RegExp('Open your café')),
        ),
      );
      expect(
        inPage(
          'The essentials are in place. Open your café and start taking '
          'orders — you can keep refining anytime.',
        ),
        findsOneWidget,
      );
      await h.tap(buttonOf('Open my café'));
      expect(h.server.callsTo(completeRoute).last.status, 200);
      expect(find.byType(OnbCelebration), findsOneWidget);
      // Reduced motion: the card without the confetti.
      expect(
        find.byWidgetPredicate((w) => w.runtimeType.toString() == '_Confetti'),
        findsNothing,
      );
      expect(find.text('Your café is open! 🎉'), findsOneWidget);
      expect(find.text('Taking you to your dashboard…'), findsOneWidget);
      // ADM-ONB-031: the button stays off while the celebration plays.
      expect(button(tester, 'Open my café').onPressed, isNull);
      expect(h.location.path, onboardingPath);
      await tester.pump(const Duration(milliseconds: 1800));
      await h.settle();
      expect(h.location.path, '/');
      expect(s.db[onboardingTable].find(sabah)!['completed_at'], isNotNull);
    });

    testWidgets('ADM-ONB-024 with motion on, the confetti falls', (
      tester,
    ) async {
      final s = onboardingServer();
      readyCafe(s.db);
      final h = await pumpOnboarding(
        tester,
        server: s.server,
        db: s.db,
        reducedMotion: false,
      );
      h.allowUnmatched = true;
      await h.tap(
        find.descendant(
          of: _nav,
          matching: find.bySemanticsLabel(RegExp('Open your café')),
        ),
      );
      await h.tap(buttonOf('Open my café'));
      expect(
        find.byWidgetPredicate((w) => w.runtimeType.toString() == '_Confetti'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 3));
      await h.settle();
      expect(h.location.path, '/');
    });

    testWidgets('ADM-ONB-023 while it opens: the button spins and waits', (
      tester,
    ) async {
      final s = onboardingServer();
      readyCafe(s.db);
      final h = await pumpOnboarding(tester, server: s.server, db: s.db);
      h.allowUnmatched = true;
      await h.tap(
        find.descendant(
          of: _nav,
          matching: find.bySemanticsLabel(RegExp('Open your café')),
        ),
      );
      final gate = s.server.hold('POST', completeRoute);
      await h.tap(buttonOf('Open my café'));
      expect(button(tester, 'Open my café').loading, isTrue);
      expect(button(tester, 'Open my café').onPressed, isNull);
      expect(find.byType(OnbCelebration), findsNothing);
      gate.release();
      await h.settle();
      expect(find.byType(OnbCelebration), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await h.settle();
    });

    testWidgets('ADM-ONB-024 a slow gate read after Open my café never '
        'sends the owner back: the dashboard after 1.8 s', (tester) async {
      final s = onboardingServer();
      readyCafe(s.db);
      final h = await pumpOnboarding(tester, server: s.server, db: s.db);
      h.allowUnmatched = true;
      await h.tap(
        find.descendant(
          of: _nav,
          matching: find.bySemanticsLabel(RegExp('Open your café')),
        ),
      );
      // Every checklist read from here on hangs (the gate's included).
      final gate = s.server.hold('GET', statusRoute);
      await h.tap(buttonOf('Open my café'));
      expect(find.byType(OnbCelebration), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1800));
      await h.settle();
      expect(h.location.path, '/');
      expect(find.byType(OnbCelebration), findsNothing);
      gate.release();
      await h.settle();
      await tester.pump(const Duration(seconds: 2));
      await h.settle();
      expect(h.location.path, '/');
    });

    testWidgets('ADM-ONB-024 a failed gate read after Open my café: still '
        'the dashboard', (tester) async {
      final s = onboardingServer();
      readyCafe(s.db);
      final h = await pumpOnboarding(tester, server: s.server, db: s.db);
      h.allowUnmatched = true;
      await h.tap(
        find.descendant(
          of: _nav,
          matching: find.bySemanticsLabel(RegExp('Open your café')),
        ),
      );
      s.server.fail(
        'GET',
        statusRoute,
        MockResponse.error(500, 'boom'),
        times: null,
      );
      await h.tap(buttonOf('Open my café'));
      await tester.pump(const Duration(milliseconds: 1800));
      await h.settle();
      expect(h.location.path, '/');
    });

    testWidgets('ADM-ONB-024 a refusal toasts the server\'s words and '
        'gives the button back', (tester) async {
      final s = onboardingServer();
      readyCafe(s.db);
      final refusal = MockResponse.conflict(
        'Onboarding cannot be completed: required steps missing '
        '(menu_items)',
      );
      s.server.fail('POST', completeRoute, refusal);
      final h = await pumpOnboarding(tester, server: s.server, db: s.db);
      await h.tap(
        find.descendant(
          of: _nav,
          matching: find.bySemanticsLabel(RegExp('Open your café')),
        ),
      );
      await h.tap(buttonOf('Open my café'));
      await h.expectToast(h.refusalWords(refusal));
      expect(find.byType(OnbCelebration), findsNothing);
      expect(button(tester, 'Open my café').onPressed, isNotNull);
      expect(h.location.path, onboardingPath);
    });

    testWidgets('ADM-ONB-024 the server refuses an unfinished café', (
      tester,
    ) async {
      final s = onboardingServer();
      freshCafe(s.db);
      addBranch(s.db);
      await expectLater(
        s.server.send(
          ApiRequest(method: 'POST', path: '/orgs/$sabah/onboarding/complete'),
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.status, 'status', 409)
              .having(
                (e) => e.message,
                'message',
                'Conflict: Onboarding cannot be completed: required steps '
                    'missing (payment_methods, categories, menu_items)',
              ),
        ),
      );
      // Finished, it answers its status unchanged (idempotent).
      readyCafe(s.db);
      final r = await s.server.send(
        ApiRequest(method: 'POST', path: '/orgs/$sabah/onboarding/complete'),
      );
      expect(r.status, 200);
      final again = await s.server.send(
        ApiRequest(method: 'POST', path: '/orgs/$sabah/onboarding/complete'),
      );
      expect(utf8.decode(again.bodyBytes), utf8.decode(r.bodyBytes));
    });
  });

  group('mirror', () {
    testWidgets('ADM-ONB-025 header: the café name, Dashboard, Live preview', (
      tester,
    ) async {
      await pumpOnboarding(tester);
      expect(_inMirror('Sabah Coffee'), findsOneWidget);
      expect(_inMirror('Dashboard'), findsOneWidget);
      expect(_inMirror('Live preview'), findsOneWidget);
    });

    testWidgets('ADM-ONB-025 a café with no name yet reads Your café', (
      tester,
    ) async {
      final s = onboardingServer();
      freshCafe(s.db);
      s.db['orgs'].get(sabah)['name'] = '  ';
      await pumpOnboarding(tester, server: s.server, db: s.db);
      expect(_inMirror('Your café'), findsOneWidget);
    });

    testWidgets('ADM-ONB-026/027/028 locked tiles, counts, coverage, sales', (
      tester,
    ) async {
      final s = onboardingServer();
      freshCafe(s.db);
      final cat = addCategory(s.db);
      addCategory(s.db, name: 'Pastries', ar: 'مخبوزات');
      addItem(s.db, cat);
      await pumpOnboarding(tester, server: s.server, db: s.db);
      // Not done: dashed "—" tiles (branches, payments, ingredients, add-ons,
      // team).
      expect(_inMirror('—'), findsNWidgets(5));
      expect(_inMirror('2'), findsOneWidget);
      expect(_inMirror('1'), findsOneWidget);
      expect(_inMirror('0%'), findsOneWidget);
      expect(_inMirror('Unlocks with your first order'), findsOneWidget);
      expect(_inMirror('First sale in!'), findsNothing);
    });

    testWidgets('ADM-ONB-027 the ring: half the items have a recipe', (
      tester,
    ) async {
      final s = onboardingServer();
      everythingDone(s.db);
      addItem(
        s.db,
        s.db[OnbTables.categories].rows.firstWhere((c) => c['org_id'] == sabah),
        name: 'Mocha',
        ar: 'موكا',
      );
      await pumpOnboarding(tester, server: s.server, db: s.db);
      expect(_inMirror('50%'), findsOneWidget);
      expect(_inMirror('Recipe cost coverage'), findsOneWidget);
      expect(
        _inMirror("Add recipes to know every item's margin."),
        findsOneWidget,
      );
    });

    testWidgets('ADM-ONB-026 a count climbs from its last value (motion on)', (
      tester,
    ) async {
      final s = onboardingServer();
      freshCafe(s.db);
      addCategory(s.db);
      final h = await pumpOnboarding(
        tester,
        server: s.server,
        db: s.db,
        reducedMotion: false,
      );
      expect(_inMirror('1'), findsOneWidget);
      for (var i = 0; i < 10; i++) {
        addCategory(s.db, name: 'Category $i', ar: 'فئة $i');
      }
      h.container.read(realtimeBusProvider).invalidate([
        '/orgs/$sabah/onboarding',
      ]);
      await h.settle();
      expect(_inMirror('11'), findsNothing);
      await tester.pump(const Duration(milliseconds: 1200));
      expect(_inMirror('11'), findsOneWidget);
      await h.flushTimers();
    });

    testWidgets('ADM-ONB-028 the first order unlocks the sales tile', (
      tester,
    ) async {
      await pumpOnboarding(tester);
      expect(_inMirror('First sale in!'), findsOneWidget);
      expect(_inMirror('Unlocks with your first order'), findsNothing);
    });
  });
}
