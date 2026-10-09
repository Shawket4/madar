// A refresh by hand on every page (owner rule, beyond the web): pulled down,
// Cmd+R (Ctrl+R off Apple), or the header's action on a page that owns its
// gestures. Everything the open page shows is read again from the server,
// fresh or not; a page left behind in the cache is not; a failure keeps the
// page and says why.
import 'dart:convert';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shell/support.dart';

final _heliopolis = {
  ScopePrefKeys.branch: jsonEncode({
    'org': SeedIds.sabahOrg,
    'branch': SeedIds.heliopolis,
  }),
};

List<String> _reads(DashHarness h, int from) => [
  for (final c in h.server.calls.skip(from))
    if (c.method == 'GET') c.path,
];

Future<void> _shortcut(WidgetTester tester) async {
  final apple = defaultTargetPlatform == TargetPlatform.macOS;
  final mod = apple
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(mod);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
  await tester.sendKeyUpEvent(mod);
}

void main() {
  testWidgets('a pull on a list page reads it again though fresh, the '
      'indicator up meanwhile', (tester) async {
    final h = await pumpShell(tester, path: '/orders', prefs: _heliopolis);
    final mark = h.server.calls.length;
    final gate = h.server.hold('GET', '/orders');

    await tester.fling(
      find.byType(DashPageHeader),
      const Offset(0, 400),
      1000,
      warnIfMissed: false,
    );
    await h.settle(rounds: 12);
    expect(find.byType(RefreshProgressIndicator), findsOneWidget);
    expect(_reads(h, mark), contains('/orders'));

    gate.release();
    h.server.clearFailures();
    await h.settle(rounds: 20);
    expect(find.byType(RefreshProgressIndicator), findsNothing);
    expect(find.byKey(const ValueKey('orders-table')), findsOneWidget);
  });

  testWidgets('Cmd+R (Ctrl+R off Apple) does the same', (tester) async {
    final h = await pumpShell(tester, path: '/orders', prefs: _heliopolis);
    final mark = h.server.calls.length;
    await _shortcut(tester);
    await h.settle(rounds: 20);
    expect(_reads(h, mark), contains('/orders'));
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('Ctrl+R off Apple', (tester) async {
    final h = await pumpShell(tester, path: '/orders', prefs: _heliopolis);
    final mark = h.server.calls.length;
    await _shortcut(tester);
    await h.settle(rounds: 20);
    expect(_reads(h, mark), contains('/orders'));
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('a page left behind in the cache is not read again', (
    tester,
  ) async {
    final h = await pumpShell(tester, path: '/discounts', prefs: _heliopolis);
    expect(_reads(h, 0), contains('/discounts'));
    await h.go('/orders');
    final mark = h.server.calls.length;
    await _shortcut(tester);
    await h.settle(rounds: 20);
    expect(_reads(h, mark), contains('/orders'));
    expect(_reads(h, mark), isNot(contains('/discounts')));
  });

  testWidgets('a failed refresh says why', (tester) async {
    final h = await pumpShell(tester, path: '/orders', prefs: _heliopolis);
    h.server.fail(
      'GET',
      '/orders',
      MockResponse.json(500, {'error': 'The orders store is down.'}),
    );
    await _shortcut(tester);
    await h.settle(rounds: 20);
    expect(find.text('The orders store is down.'), findsWidgets);
    await tester.pump(DashToast.duration);
  });

  testWidgets('a page that owns its gestures keeps them: no pull, a refresh '
      'action in its header', (tester) async {
    final h = await pumpShell(tester, path: '/floor', prefs: _heliopolis);
    expect(find.byType(RefreshIndicator), findsNothing);

    // A drag on the room pans it; it never refreshes.
    var mark = h.server.calls.length;
    await tester.drag(
      find.byType(DashPageScaffold),
      const Offset(0, 300),
      warnIfMissed: false,
    );
    await h.settle();
    expect(_reads(h, mark), isEmpty);

    mark = h.server.calls.length;
    await h.tapLabel(h.t('common.refresh'));
    await h.settle(rounds: 12);
    expect(_reads(h, mark), isNotEmpty);
  });
}
