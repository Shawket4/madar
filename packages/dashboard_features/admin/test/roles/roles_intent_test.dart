// Intent warming on Roles & Permissions: a control whose press reads warms
// that read first, so the press asks the server nothing more. The Access
// tabs warm the page they open; "New role" and "Rename" warm the dialog's
// read (the page's own roles list, so nothing new is asked).
import 'package:dashboard_admin/dashboard_admin.dart';
import 'package:dashboard_admin/src/roles/role_dialog.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Future<TestGesture> _mouse(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  return mouse;
}

/// The Access tab labelled [label] on the open page.
Finder _tab(String label) => find.descendant(
  of: find.byType(DashTabStrip<String>),
  matching: find.text(label),
);

void main() {
  testWidgets('ADM-ROL-001 the Users tab warms the Users list; pressing it '
      'asks nothing more', (tester) async {
    final h = await DashHarness.pump(
      tester,
      areas: const [adminArea],
      path: rolesPath,
    );
    List<MockCall> users() => h.server.callsTo('/users', method: 'GET');
    expect(users(), isEmpty);
    final mouse = await _mouse(tester);
    await mouse.moveTo(tester.getCenter(_tab('Users')));
    await h.settle();
    expect(users(), hasLength(1), reason: 'warmed');
    await h.tap(_tab('Users'));
    expect(h.location.path, '/access/users');
    expect(find.text('Adham Reda'), findsWidgets);
    expect(users(), hasLength(1), reason: 'served from the cache');
  });

  testWidgets('ADM-ROL-004/019 the Roles tab on Users warms the roles and the '
      'policy; pressing it asks nothing more', (tester) async {
    final h = await DashHarness.pump(
      tester,
      areas: const [adminArea],
      path: '/access/users',
    );
    expect(h.server.callsTo(rolesRoute), isEmpty);
    final mouse = await _mouse(tester);
    await mouse.moveTo(tester.getCenter(_tab('Roles & Permissions')));
    await h.settle();
    expect(h.server.callsTo(rolesRoute), hasLength(1), reason: 'warmed');
    expect(h.server.callsTo(policyRoute), hasLength(1), reason: 'warmed');
    await h.tap(_tab('Roles & Permissions'));
    expect(h.location.path, rolesPath);
    expect(roleRow(roleId('teller')), findsOneWidget);
    expect(policyControl('orders.void'), findsOneWidget);
    expect(h.server.callsTo(rolesRoute), hasLength(1), reason: 'cached');
    expect(h.server.callsTo(policyRoute), hasLength(1), reason: 'cached');
  });

  testWidgets('ADM-ROL-010/017 "New role" and "Rename" open their dialog '
      'from the cache', (tester) async {
    final h = await pumpRoles(tester);
    final mouse = await _mouse(tester);
    final reads = h.server.callsTo(rolesRoute).length;
    for (final key in ['roles-new', 'role-rename']) {
      final button = find.byKey(ValueKey(key));
      await mouse.moveTo(tester.getCenter(button));
      await h.settle();
      await h.tap(button);
      expect(find.byType(RoleDialog), findsOneWidget);
      expect(h.server.callsTo(rolesRoute), hasLength(reads), reason: key);
      await h.tap(inSurface('Cancel'));
    }
  });
}
