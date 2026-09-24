// Staying up to date: a pull on every tab (and on the list sheets) sends the
// queue and fetches the whole picture, and the screen shows what came back;
// offline, unreachable or refused, the toast says so and the saved picture
// stays; coming back to the front fetches too, unless a fetch ran in the
// last 15 seconds.
import 'dart:math' as math;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:staff_core/staff_core.dart';
import 'package:staff_core/testing.dart';

import 'support.dart';

/// What the server has now that the phone does not: every name, template,
/// note and line the tabs show, renamed.
void _newOnServer(Map<String, dynamic> v) {
  for (final p in v['people'] as List<dynamic>) {
    (p as Map<String, dynamic>)['name'] = 'Pulled ${p['name']}';
  }
  for (final t in v['templates'] as List<dynamic>) {
    (t as Map<String, dynamic>)['name'] = 'Pulled ${t['name']}';
  }
  for (final r in v['requests'] as List<dynamic>) {
    (r as Map<String, dynamic>)['note'] = 'Pulled note';
  }
  for (final n in v['notices'] as List<dynamic>) {
    (n as Map<String, dynamic>)['text'] = 'Pulled notice';
  }
  for (final s in v['slips'] as List<dynamic>) {
    for (final l in (s as Map<String, dynamic>)['lines'] as List<dynamic>) {
      (l as Map<String, dynamic>)['en'] = 'Pulled ${l['en']}';
    }
  }
}

final _pulled = find.textContaining('Pulled', findRichText: true);

/// A pull from the top of what is under [refresh] (the tab's body, or an
/// open sheet): a fling down, the ring's snap, the answer, the ring's exit.
Future<void> _pull(WidgetTester tester, {Finder? on}) async {
  final area = on ?? find.byType(RefreshIndicator).first;
  final box = tester.getRect(area);
  // Near the leading edge: a two-pane tablet tab has a gutter in the middle.
  await tester.flingFrom(
    Offset(box.left + math.min(box.width / 4, 120), box.top + 24),
    const Offset(0, 400),
    1200,
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await frames(tester);
}

Future<void> _lifecycle(WidgetTester tester, List<AppLifecycleState> s) async {
  for (final state in s) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await frames(tester);
}

/// To the background and back.
Future<void> _resume(WidgetTester tester) => _lifecycle(tester, const [
  AppLifecycleState.inactive,
  AppLifecycleState.hidden,
  AppLifecycleState.paused,
  AppLifecycleState.hidden,
  AppLifecycleState.inactive,
  AppLifecycleState.resumed,
]);

String _word(String key) => coreWord(key);

void main() {
  useCoreWords();

  setUpAll(() async {
    await loadFonts();
    await initializeDateFormatting();
  });

  // who, manager side?, tab, its name
  const tabs = [
    ('e1', false, 0, 'home'),
    ('e1', false, 1, 'timesheet'),
    ('e1', false, 2, 'shifts'),
    ('e1', false, 3, 'requests'),
    ('e1', false, 4, 'pay'),
    ('e2', true, 0, 'team'),
    ('e2', true, 1, 'approvals'),
    ('e2', true, 2, 'schedule'),
    ('e3', true, 3, 'payroll'),
  ];
  const devices = {'phone': Size(390, 844), 'tablet': Size(1180, 820)};
  for (final (who, manage, tab, label) in tabs) {
    for (final MapEntry(key: device, value: size) in devices.entries) {
      testWidgets('a pull on $label ($device) fetches and shows the answer', (
        tester,
      ) async {
        await pumpApp(
          tester,
          lang: 'en',
          who: who,
          manage: manage,
          tab: tab,
          size: size,
        );
        await frames(tester);
        // The tab's own body, not the chrome (the rail shows my name).
        final body = find.descendant(
          of: find.byType(RefreshIndicator).first,
          matching: _pulled,
        );
        expect(body, findsNothing);
        final before = testCore.syncs;
        testCore.edit = _newOnServer;

        await _pull(tester);

        expect(testCore.syncs, before + 1, reason: 'one fetch per pull');
        expect(body, findsWidgets, reason: 'the fresh picture shows');
        expect(find.byType(RefreshProgressIndicator), findsNothing);
        await finish(tester);
      });
    }
  }

  testWidgets('offline: the toast says so and the saved picture stays', (
    tester,
  ) async {
    await pumpApp(tester, lang: 'en', who: 'e1');
    await frames(tester);
    testCore
      ..edit = _newOnServer
      ..online = false;

    await _pull(tester);

    expect(testCore.syncs, 1);
    expect(find.text(_word('staff.refresh_offline')), findsOneWidget);
    expect(_pulled, findsNothing, reason: 'nothing new reached the phone');
    expect(find.textContaining('Sara'), findsWidgets, reason: 'still shown');
    await finish(tester);
  });

  testWidgets('offline in Arabic: the toast is in Arabic', (tester) async {
    await pumpApp(tester, lang: 'ar', who: 'e1', tab: 1);
    await frames(tester);
    testCore.online = false;
    await _pull(tester);
    expect(
      find.text(coreWord('staff.refresh_offline', arabic: true)),
      findsOneWidget,
    );
    await finish(tester);
  });

  testWidgets('the server never answered: the toast says so', (tester) async {
    await pumpApp(tester, lang: 'en', who: 'e2', manage: true);
    await frames(tester);
    testCore
      ..edit = _newOnServer
      ..unreachable = true;

    await _pull(tester);

    expect(find.text(_word('staff.refresh_failed')), findsOneWidget);
    expect(_pulled, findsNothing);
    await finish(tester);
  });

  testWidgets('refused: the server\'s words, and the saved picture stays', (
    tester,
  ) async {
    await pumpApp(tester, lang: 'en', who: 'e1', tab: 3);
    await frames(tester);
    testCore
      ..edit = _newOnServer
      ..refuseFetch = DawamError(
        'Dawam is off for this business.',
        'دوام مقفول للشغل ده.',
      );

    await _pull(tester);

    expect(find.text('Dawam is off for this business.'), findsOneWidget);
    expect(_pulled, findsNothing);
    expect(find.textContaining('Doctor', findRichText: true), findsWidgets);
    await finish(tester);
  });

  testWidgets('a second pull while the first is out shares it', (tester) async {
    await pumpApp(tester, lang: 'en', who: 'e1');
    await frames(tester);
    final store = testContainer.read(dawamProvider);
    await Future.wait([store.pull(), store.pull(), store.pull()]);
    expect(testCore.syncs, 1);
    await finish(tester);
  });

  group('the list sheets pull too', () {
    testWidgets('the inbox', (tester) async {
      await pumpApp(tester, lang: 'en', who: 'e1');
      await frames(tester);
      await tester.tap(find.byTooltip(_word('staff.inbox')));
      await frames(tester);
      expect(find.text('Pulled notice'), findsNothing);
      testCore.edit = _newOnServer;

      await _pull(tester, on: find.byType(RefreshIndicator).last);

      expect(testCore.syncs, 1);
      expect(find.text('Pulled notice'), findsWidgets);
      await finish(tester);
    });

    testWidgets('a person\'s payslip on Payroll', (tester) async {
      await pumpApp(tester, lang: 'en', who: 'e3', manage: true, tab: 3);
      await frames(tester);
      await tester.tap(find.textContaining('Sara').first);
      await frames(tester);
      final sheet = find.byType(RefreshIndicator).last;
      expect(
        find.descendant(of: sheet, matching: find.textContaining('Pulled')),
        findsNothing,
      );
      testCore.edit = _newOnServer;

      await _pull(tester, on: sheet);

      expect(testCore.syncs, 1);
      expect(
        find.descendant(
          of: find.byType(RefreshIndicator).last,
          matching: find.text('Pulled Salary'),
        ),
        findsOneWidget,
      );
      await finish(tester);
    });
  });

  group('coming back to the front', () {
    testWidgets('fetches and shows the answer', (tester) async {
      await pumpApp(tester, lang: 'en', who: 'e1');
      await frames(tester);
      final store = testContainer.read(dawamProvider);
      var now = DateTime(2026, 9, 23, 10);
      store
        ..clock = (() => now)
        ..lastFetch = now;
      final before = testCore.syncs;
      testCore.edit = _newOnServer;

      now = now.add(const Duration(minutes: 5));
      await _resume(tester);

      expect(testCore.syncs, before + 1);
      expect(_pulled, findsWidgets);
      expect(store.lastFetch, now);
      await finish(tester);
    });

    testWidgets('within 15 s of a fetch: no second fetch', (tester) async {
      await pumpApp(tester, lang: 'en', who: 'e2', manage: true, tab: 1);
      await frames(tester);
      final store = testContainer.read(dawamProvider);
      var now = DateTime(2026, 9, 23, 10);
      store
        ..clock = (() => now)
        ..lastFetch = now;
      final before = testCore.syncs;

      now = now.add(const Duration(seconds: 10));
      await _resume(tester);
      expect(testCore.syncs, before, reason: 'a quick app switch');

      // A pull counts as a fetch: resuming right after it skips too.
      await _pull(tester);
      expect(testCore.syncs, before + 1);
      now = now.add(const Duration(seconds: 14));
      await _resume(tester);
      expect(testCore.syncs, before + 1);

      // Past the quiet window it fetches again.
      now = now.add(const Duration(seconds: 2));
      await _resume(tester);
      expect(testCore.syncs, before + 2);
      await finish(tester);
    });

    testWidgets('offline: quiet, the pill already says so', (tester) async {
      await pumpApp(tester, lang: 'en', who: 'e1');
      await frames(tester);
      final store = testContainer.read(dawamProvider);
      var now = DateTime(2026, 9, 23, 10);
      store
        ..clock = (() => now)
        ..lastFetch = now;
      testCore.online = false;

      now = now.add(const Duration(minutes: 1));
      await _resume(tester);

      expect(testCore.syncs, 1);
      expect(find.text(_word('staff.refresh_offline')), findsNothing);
      expect(store.offline, isTrue);
      expect(find.byType(MadarOutboxPill), findsOneWidget);
      await finish(tester);
    });

    testWidgets('signed out: nothing is fetched', (tester) async {
      await pumpApp(tester, lang: 'en');
      await frames(tester);
      await _resume(tester);
      expect(testCore.syncs, 0);
      await finish(tester);
    });
  });
}
