// The web's `prefetchRoute('/access/roles')`: pointing at a link to Roles &
// Permissions warms the page's mount reads (the roles and the policy card),
// so opening it asks the server nothing more.
import 'package:dashboard_api/mock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  Future<TestGesture> hover(WidgetTester tester, Finder target) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(target));
    return mouse;
  }

  testWidgets('ADM-ROL-004/019 pointing at the page warms the roles and the '
      'policy; opening it refetches nothing', (tester) async {
    final h = await pumpRoles(tester, path: linkPath);
    expect(h.server.callsTo(rolesRoute), isEmpty);
    expect(h.server.callsTo(policyRoute), isEmpty);

    final link = find.byKey(const ValueKey('roles-link'));
    await hover(tester, link);
    await h.settle();
    expect(h.server.callsTo(rolesRoute), hasLength(1), reason: 'warmed');
    expect(h.server.callsTo(policyRoute), hasLength(1), reason: 'warmed');

    await h.tap(link);
    expect(h.location.path, rolesPath);
    expect(roleRow(roleId('teller')), findsOneWidget);
    expect(policyControl('orders.void'), findsOneWidget);
    expect(h.server.callsTo(rolesRoute), hasLength(1), reason: 'cached');
    expect(h.server.callsTo(policyRoute), hasLength(1), reason: 'cached');
  });

  testWidgets('ADM-ROL-001 a refused warm-up leaves nothing cached', (
    tester,
  ) async {
    final s = rolesServer();
    s.server.fail(
      'GET',
      rolesRoute,
      MockResponse.denied('staff.permissions.read'),
    );
    final h = await pumpRoles(
      tester,
      path: linkPath,
      server: s.server,
      db: s.db,
    );
    final link = find.byKey(const ValueKey('roles-link'));
    await hover(tester, link);
    await h.settle();
    expect(h.server.callsTo(rolesRoute), hasLength(1));
    await h.tap(link);
    expect(h.server.callsTo(rolesRoute), hasLength(2));
    expect(roleRow(roleId('teller')), findsOneWidget);
  });
}
