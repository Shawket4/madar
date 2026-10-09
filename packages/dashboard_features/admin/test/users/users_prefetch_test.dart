// The web's `prefetchRoute('/access/users')`: pointing at the sidebar row
// warms the org's users, so opening the page asks the server nothing more.
import 'package:dashboard_core/shell.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  testWidgets('ADM-USR-005 pointing at Users & Permissions warms the list; '
      'opening it refetches nothing', (tester) async {
    final h = await pumpUsers(tester, path: blankPath);
    List<Object> lists() => h.server.callsTo(listRoute, method: 'GET');
    expect(lists(), isEmpty);

    final row = find.descendant(
      of: find.byType(DashSidebar),
      matching: find.text('Users & Permissions'),
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
    expect(lists(), hasLength(1), reason: 'warmed on hover');
    expect(
      h.server.callsTo(listRoute).single.query['org_id'],
      isNotEmpty,
    );

    await h.tap(row);
    expect(h.location.path, usersPath);
    expect(onPage('Adham Reda'), findsOneWidget);
    expect(lists(), hasLength(1), reason: 'served from the cache');
  });
}
