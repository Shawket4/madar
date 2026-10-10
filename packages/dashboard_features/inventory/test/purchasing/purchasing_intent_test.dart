// Intent warming on Purchasing (owner rule, SPEC 6.1): pointing at a control
// warms the read its press makes, so the press asks the server nothing more.
// An order's row, its Receive / Receive remaining and its ⋯ View order all
// warm the same order read; the row's own hover fires first, so the button
// and menu tests let the warmed read go stale before pointing at them.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart' show allBranchesId;
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:dashboard_inventory/src/purchasing/purchasing_data.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

final String _po1042 = PurIds.po('po-1042'); // Zamalek, ordered
final String _po1041 = PurIds.po('po-1041'); // Maadi, partially received
final String _po1039 = PurIds.po('po-1039'); // Zamalek, received

/// A mouse resting at [at] for longer than the intent dwell.
Future<TestGesture> restMouse(DashHarness h, Offset at) async {
  final mouse = await h.tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await mouse.moveTo(at);
  await h.settle();
  return mouse;
}

/// GETs of the order [id].
int orderReads(DashHarness h, String id) => [
  for (final c in h.server.callsTo(PurT.order, method: 'GET'))
    if (c.path == '/purchasing/orders/$id') c,
].length;

void main() {
  testWidgets('INV-PUR-014 (intent) a row warms its order; opening it asks '
      'nothing more', (tester) async {
    final h = await pumpPurchasing(tester);
    expect(orderReads(h, _po1042), 0);
    await restMouse(h, tester.getCenter(exactText(ordersTable, 'PO-1042')));
    expect(orderReads(h, _po1042), 1, reason: 'warmed');
    await h.tap(exactText(ordersTable, 'PO-1042'));
    expect(receiveDialog, findsOneWidget);
    expect(orderReads(h, _po1042), 1, reason: 'opened from the cache');
  });

  testWidgets('INV-PUR-011 (intent) Receive and Receive remaining warm the '
      'order; pressing them asks nothing more', (tester) async {
    final h = await pumpPurchasing(tester);
    final mouse = await restMouse(h, Offset.zero);
    for (final (id, ref) in [(_po1042, 'PO-1042'), (_po1041, 'PO-1041')]) {
      await mouse.moveTo(tester.getCenter(exactText(ordersTable, ref)));
      await h.settle();
      expect(orderReads(h, id), 1, reason: 'the row warmed it');
      // Stale again, so only the button's own intent can warm it now.
      h.container.invalidate(purchaseOrderProvider(id));
      await h.settle();
      expect(orderReads(h, id), 1);
      final receive = inPage(byKey('po-receive-$id'));
      await mouse.moveTo(tester.getCenter(receive));
      await h.settle();
      expect(orderReads(h, id), 2, reason: 'the button warmed it');
      await h.tap(receive);
      expect(receiveDialog, findsOneWidget);
      expect(orderReads(h, id), 2, reason: 'opened from the cache');
      await h.tap(inReceive(find.text('Cancel')));
    }
  });

  testWidgets('INV-PUR-012 (intent) ⋯ View order warms the order; choosing '
      'it asks nothing more', (tester) async {
    final h = await pumpPurchasing(tester);
    final mouse = await restMouse(
      h,
      tester.getCenter(exactText(ordersTable, 'PO-1039')),
    );
    await h.tap(inPage(byKey('po-menu-$_po1039')));
    expect(orderReads(h, _po1039), 1, reason: 'the row warmed it');
    h.container.invalidate(purchaseOrderProvider(_po1039));
    await h.settle();
    expect(orderReads(h, _po1039), 1);
    final item = find.text('View order').hitTestable();
    await mouse.moveTo(tester.getCenter(item));
    await h.settle();
    expect(orderReads(h, _po1039), 2, reason: 'the menu item warmed it');
    await h.tap(item);
    expect(receiveDialog, findsOneWidget);
    expect(orderReads(h, _po1039), 2, reason: 'opened from the cache');
  });

  testWidgets('INV-PUR-008 (intent) a status option warms that list; '
      'picking it asks nothing more', (tester) async {
    final h = await pumpPurchasing(tester);
    int received() => [
      for (final c in h.server.callsTo(PurT.orders, method: 'GET'))
        if (c.query['status']?.single == 'received') c,
    ].length;
    await h.tap(inPage(byKey('po-status-filter')));
    final option = find.descendant(
      of: find.byType(DashOptionList<String>),
      matching: find.text('Received'),
    );
    expect(received(), 0);
    await restMouse(h, tester.getCenter(option));
    expect(received(), 1, reason: 'warmed');
    expect(
      h.server.callsTo(PurT.orders).last.path,
      '/purchasing/branches/$allBranchesId/orders',
    );
    await h.tap(option);
    expect(received(), 1, reason: 'shown from the cache');
    expect(inOrders(find.text('PO-1039')), findsOneWidget);
    expect(inOrders(find.text('PO-1042')), findsNothing);
  });

  testWidgets('INV-PUR-022 (intent) the Reorder tab warms the suggestions; '
      'opening it asks nothing more', (tester) async {
    final h = await pumpPurchasing(tester, path: purchasingAt(SeedIds.zamalek));
    final tab = find.descendant(of: tabStrip, matching: find.text('Reorder'));
    expect(h.server.callsTo(PurT.reorder), isEmpty);
    await restMouse(h, tester.getCenter(tab));
    expect(
      h.server.callsTo(PurT.reorder, method: 'GET').single.path,
      '/purchasing/branches/${SeedIds.zamalek}/reorder-suggestions',
    );
    await h.tap(tab);
    expect(inPage(find.text('Create draft PO')), findsWidgets);
    expect(h.server.callsTo(PurT.reorder, method: 'GET'), hasLength(1));
  });

  testWidgets('INV-PUR-048 (intent) the Delivery history tab asks for the '
      'receipts afresh on intent; opening it asks nothing more', (
    tester,
  ) async {
    final h = await pumpPurchasing(tester);
    await orderMenu(h, _po1039, 'View order');
    final tab = find.descendant(
      of: byKey('receive-tabs'),
      matching: find.text('Delivery history'),
    );
    expect(h.server.callsTo(PurT.receipts), isEmpty);
    await restMouse(h, tester.getCenter(tab));
    expect(
      h.server.callsTo(PurT.receipts, method: 'GET').single.path,
      '/purchasing/orders/$_po1039/receipts',
    );
    await h.tap(tab);
    expect(byKey('receipt-${InvIds.receipt('r-1039-a')}'), findsOneWidget);
    expect(h.server.callsTo(PurT.receipts, method: 'GET'), hasLength(1));
  });
}
