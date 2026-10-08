// The web's intent prefetch (`useRoutePrefetch`): pointing at a sidebar row
// warms the page's mount reads, so opening it asks the server nothing more
// (the cached read is younger than the 30 s stale time).
import 'package:dashboard_admin/dashboard_admin.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/shell.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('pointing at Branches warms its list; opening it refetches '
      'nothing', (tester) async {
    final h = await DashHarness.pump(
      tester,
      areas: const [adminArea],
      path: '/users',
      persona: Persona.owner,
    );
    List<MockCall> lists() => h.server.callsTo('/branches', method: 'GET');
    final before = lists().length;

    final row = find.descendant(
      of: find.byType(DashSidebar),
      matching: find.text(h.t('nav.branches')),
    );
    await tester.scrollUntilVisible(
      row,
      200,
      scrollable: find
          .descendant(
            of: find.byType(DashSidebar),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await h.settle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(row));
    await h.settle();
    expect(lists().length, before + 1, reason: 'warmed on hover');

    await h.tap(row);
    expect(h.location.path, '/branches');
    expect(lists().length, before + 1, reason: 'served from the cache');
  });
}
