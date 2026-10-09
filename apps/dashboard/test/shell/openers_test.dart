// The cross-area seams (dashboard_core's areaOpenersProvider) in the
// assembled app: a page whose package cannot depend on sell or team opens
// the REAL sheet or dialog, and its intent warms that sheet's first read.
// - reports/operations: a sitting's customer → sell's customer sheet
//   (read-only), and an order chosen in it → sell's order sheet;
// - reports/staff-pool: "View order" → sell's order sheet;
// - setup/loyalty: a member row → sell's customer sheet, which stays open
//   after "Remove from loyalty programme";
// - admin/users: "Make employee" → team's Add employee dialog, preset.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madar_dashboard/areas.dart';

import 'support.dart';

/// A widget of the area-private class [name] (the app cannot import an
/// area's `src`).
Finder _type(String name) =>
    find.byWidgetPredicate((w) => w.runtimeType.toString() == name);

Finder _pressable(String label) => find.byWidgetPredicate(
  (w) => w is DashPressable && w.semanticLabel == label,
);

Future<void> _rest(WidgetTester tester, DashHarness h, Finder f) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await tester.ensureVisible(f);
  await h.settle();
  await mouse.moveTo(tester.getCenter(f));
  await h.settle();
}

Map<String, String> _at(String branchId) => {
  ScopePrefKeys.branch: '{"org":"${SeedIds.sabahOrg}","branch":"$branchId"}',
};

void main() {
  setUpAll(ensureTimeZones);

  testWidgets('operations: a sitting\'s customer opens sell\'s read-only '
      'customer sheet, warmed; an order in it opens sell\'s order sheet', (
    tester,
  ) async {
    final h = await pumpShell(
      tester,
      path: '/reports/operations',
      prefs: _at(SeedIds.heliopolis),
    );
    h.allowUnmatched = true; // the order sheet's own extra reads
    await h.tap(
      find
          .descendant(
            of: find.byKey(const ValueKey('ops-table-name')),
            matching: find.text('T1'),
          )
          .first,
    );
    final customer = MockSeed.instance.customers[0];
    final link = _pressable(customer.name);
    expect(link, findsOneWidget);
    await _rest(tester, h, link);
    expect(h.server.callsTo('/customers/{id}'), hasLength(1));
    await h.tap(link);
    expect(_type('CustomerSheet'), findsOneWidget);
    expect(_type('OpsCustomerSheet'), findsNothing);
    expect(
      h.server.callsTo('/customers/{id}'),
      hasLength(1),
      reason: 'opened from the warmed read',
    );
    // Read-only: no Edit.
    expect(
      find.descendant(of: _type('CustomerSheet'), matching: find.text('Edit')),
      findsNothing,
    );
    final order = find.descendant(
      of: _type('CustomerSheet'),
      matching: find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('customer-order-'),
      ),
    );
    await h.tap(order.first);
    expect(_type('CustomerSheet'), findsNothing);
    expect(_type('OrderSheet'), findsOneWidget);
  });

  testWidgets('staff pool: View order opens sell\'s order sheet, warmed', (
    tester,
  ) async {
    final h = await pumpShell(
      tester,
      path: '/reports/staff-pool?branchId=${SeedIds.heliopolis}&preset=today',
    );
    h.allowUnmatched = true; // the order sheet's own extra reads
    final view = find.text('View order').first;
    await _rest(tester, h, view);
    expect(h.server.callsTo('/orders/{order_id}'), hasLength(1));
    await h.tap(view);
    expect(_type('OrderSheet'), findsOneWidget);
    expect(_type('StaffDrinkOrderSheet'), findsNothing);
    expect(
      h.server.callsTo('/orders/{order_id}'),
      hasLength(1),
      reason: 'opened from the warmed read',
    );
  });

  testWidgets('loyalty: a member row opens sell\'s customer sheet, warmed; '
      'it stays open after "Remove from loyalty programme"', (tester) async {
    final h = await pumpShell(
      tester,
      path: '/settings/loyalty?branchId=${SeedIds.zamalek}',
    );
    await h.tap(
      find.descendant(
        of: find.byKey(const ValueKey('loyalty-tabs')),
        matching: find.text(h.t('loyalty.tabMembers')),
      ),
    );
    final nada = _pressable('Nada Kamal');
    if (nada.evaluate().isEmpty) {
      await h.enterText(find.byType(DashSearchInput).last, 'Nada');
      await tester.pump(const Duration(milliseconds: 350));
      await h.settle();
    }
    final reads = h.server.callsTo('/customers/{id}').length;
    await _rest(tester, h, nada);
    expect(h.server.callsTo('/customers/{id}'), hasLength(reads + 1));
    await h.tap(nada);
    final sheet = _type('CustomerSheet');
    expect(sheet, findsOneWidget);
    expect(_type('MemberSheet'), findsNothing);
    expect(h.server.callsTo('/customers/{id}'), hasLength(reads + 1));

    await h.tap(
      find.descendant(
        of: sheet,
        matching: find.text('Remove from loyalty programme'),
      ),
    );
    await h.tap(find.widgetWithText(DashButton, 'Remove from programme'));
    expect(
      h.server.callsTo('/loyalty/members/{id}', method: 'DELETE'),
      hasLength(1),
    );
    expect(sheet, findsOneWidget);
    await h.flushTimers();
  });

  testWidgets('users: Make employee opens team\'s Add employee dialog for '
      'that person, warmed', (tester) async {
    final db = MockDb.seeded();
    final server = MockServer(persona: Persona.owner, clock: db.clock);
    registerAppMocks(server, db);
    // Mariam is not an employee yet.
    final mariam = db['users'].rows.firstWhere((u) => u['name'] == 'Mariam Fathy');
    db['employees'].removeWhere((e) => e['user_id'] == mariam['id']);
    final h = await DashHarness.pump(
      tester,
      areas: dashboardAreas,
      path: '/access/users',
      server: server,
      db: db,
      shotArea: 'shell',
      overrides: [areaOpenersProvider.overrideWithValue(dashboardOpeners)],
    );
    final action = find.descendant(
      of: find.ancestor(
        of: find.text('Mariam Fathy'),
        matching: find.byType(DashPressable),
      ).first,
      matching: find.bySemanticsLabel('Make employee'),
    );
    expect(action, findsOneWidget);
    final reads = h.server.callsTo('/staff/employees/linkable').length;
    await _rest(tester, h, action);
    expect(
      h.server.callsTo('/staff/employees/linkable'),
      hasLength(reads + 1),
      reason: 'the dialog\'s list is warmed',
    );
    await h.tap(action);
    final dialog = _type('AddEmployeeDialog');
    expect(dialog, findsOneWidget);
    expect(
      (tester.widget(dialog) as dynamic).userId,
      mariam['id'],
    );
    expect(
      h.server.callsTo('/staff/employees/linkable'),
      hasLength(reads + 1),
      reason: 'opened from the warmed read',
    );
  });
}
