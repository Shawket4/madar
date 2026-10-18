// Intent warming on Today (owner rule, SPEC 6.1): pointing at a control warms
// the read its press makes, so the press asks the server nothing more.
import 'package:dashboard_api/mock.dart' show SeedIds;
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:dashboard_inventory/src/purchasing/receive_dialog.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const String _orderRoute = '/purchasing/orders/{id}';

/// A mouse resting on [target] for longer than the intent dwell.
Future<void> restOn(DashHarness h, Finder target) async {
  await h.tester.ensureVisible(target);
  await h.settle();
  final mouse = await h.tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await mouse.moveTo(h.tester.getCenter(target));
  await h.settle();
}

int _gets(DashHarness h, String route) =>
    h.server.callsTo(route, method: 'GET').length;

void main() {
  testWidgets('INV-TOD-018 (intent) Receive warms its order; the dialog opens '
      'from the cache', (tester) async {
    final h = await pumpToday(tester);
    final po = InvIds.purchaseOrder('po-1042');
    final receive = byKey('today-receive-$po');
    expect(_gets(h, _orderRoute), 0);
    await restOn(h, receive);
    final warmed = h.server.callsTo(_orderRoute, method: 'GET');
    expect(warmed, hasLength(1), reason: 'warmed');
    expect(warmed.single.path, '/purchasing/orders/$po');
    await h.tap(receive);
    expect(find.byType(ReceiveDialog), findsOneWidget);
    expect(_gets(h, _orderRoute), 1, reason: 'opened from the cache');
  });

  testWidgets('INV-TOD-005 (intent) the first-count button warms Stock '
      'counts; opening it asks nothing more', (tester) async {
    final h = await pumpToday(tester, branch: SeedIds.heliopolis);
    final button = byKey('today-first-count');
    expect(tester.widget<DashButton>(button).to, '/inventory/counts');
    await restOn(h, button);
    final counts = _gets(h, stocktakesRoute);
    expect(counts, greaterThan(0));
    await h.tap(button);
    expect(h.location.path, '/inventory/counts');
    expect(_gets(h, stocktakesRoute), counts, reason: 'from the cache');
  });

  testWidgets('INV-TOD-011 (intent) View all warms Ingredients; opening it '
      'asks nothing more', (tester) async {
    final h = await pumpToday(tester, branch: SeedIds.zamalek);
    final link = byKey('today-view-all');
    expect(tester.widget<DashButton>(link).to, '/inventory/ingredients');
    await restOn(h, link);
    final catalog = _gets(h, catalogRoute);
    final stock = _gets(h, stockRoute);
    await h.tap(link);
    expect(h.location.path, '/inventory/ingredients');
    expect(_gets(h, catalogRoute), catalog, reason: 'from the cache');
    expect(_gets(h, stockRoute), stock, reason: 'from the cache');
  });
}
