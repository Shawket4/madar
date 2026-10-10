// A page's "leave?" (DashLeaveGuard, the web's useBlocker): every in-app way
// out (the sidebar, the palette and the header all go through the router)
// asks while there is something to lose; signing out never asks.
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show DashLeaveGuard;
import 'package:dashboard_core/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final _dirty = ValueNotifier(false);
var _asked = 0;
var _answer = false;

final _area = DashArea(
  key: 'leave_guard_test',
  routes: [
    DashRoute(
      path: '/guarded',
      titleFallback: 'Guarded',
      builder: (_, _) => DashLeaveGuard(
        when: _dirty,
        ask: () async {
          _asked++;
          return _answer;
        },
        child: const Text('editor'),
      ),
    ),
    DashRoute(
      path: '/other',
      titleFallback: 'Other',
      builder: (_, _) => const Text('other'),
    ),
  ],
);

void main() {
  setUp(() {
    _dirty.value = false;
    _asked = 0;
    _answer = false;
  });

  testWidgets('nothing to lose: no question; something to lose: No stays, '
      'Yes goes', (tester) async {
    final h = await DashHarness.pump(tester, areas: [_area], path: '/guarded');
    h.router.go('/other');
    await h.settle();
    expect(_asked, 0);
    expect(h.location.path, '/other');
    h.router.go('/guarded');
    await h.settle();
    _dirty.value = true;
    h.router.go('/other');
    await h.settle();
    expect(_asked, 1);
    expect(h.location.path, '/guarded');
    expect(find.text('editor'), findsOneWidget);
    _answer = true;
    h.router.go('/other');
    await h.settle();
    expect(_asked, 2);
    expect(h.location.path, '/other');
  });

  testWidgets('signing out never asks', (tester) async {
    final h = await DashHarness.pump(tester, areas: [_area], path: '/guarded');
    _dirty.value = true;
    await h.container.read(sessionProvider.notifier).signOut();
    await h.settle();
    expect(_asked, 0);
    expect(h.location.path, '/login');
  });
}
