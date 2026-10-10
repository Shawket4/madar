// The web's `prefetchRoute('/inventory/purchasing')`: pointing at the
// sidebar's Purchasing row warms the org's suppliers and catalog and the
// page's first orders read, so opening the page asks for none of them again.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart' show allBranchesId;
import 'package:dashboard_core/shell.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Future<void> _hoverAndOpen(
  WidgetTester tester,
  DashHarness h,
  void Function() afterHover,
) async {
  final row = find.descendant(
    of: find.byType(DashSidebar),
    matching: find.text('Purchasing'),
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
  afterHover();
  await h.tap(row);
  expect(h.location.path, purchasingPath);
}

void main() {
  testWidgets('INV-PUR-003 (prefetch) with a branch: hovering Purchasing '
      'warms suppliers, catalog and the branch\'s orders; opening it '
      'refetches nothing', (tester) async {
    final h = await pumpPurchasing(
      tester,
      path: '/inventory/settings?branchId=${SeedIds.zamalek}',
    );
    int n(String r) => h.server.callsTo(r, method: 'GET').length;
    expect(n(PurT.orders), 0);
    final catalog = n(PurT.catalog);
    await _hoverAndOpen(tester, h, () {
      expect(n(PurT.suppliers), 1, reason: 'suppliers warmed on hover');
      expect(n(PurT.catalog), catalog + (catalog == 0 ? 1 : 0));
      final orders = h.server.callsTo(PurT.orders).single;
      expect(orders.path, '/purchasing/branches/${SeedIds.zamalek}/orders');
      expect(orders.query.containsKey('status'), isFalse);
    });
    expect(n(PurT.suppliers), 1, reason: 'served from the cache');
    expect(n(PurT.orders), 1, reason: 'served from the cache');
    expect(n(PurT.catalog), catalog == 0 ? 1 : catalog);
    expect(inOrders(find.text('PO-1042')), findsOneWidget);
  });

  testWidgets('INV-PUR-003 (prefetch, divergence) with All branches the '
      'orders are warmed with the all-branches id the page asks for', (
    tester,
  ) async {
    final h = await pumpPurchasing(tester, path: '/inventory/settings');
    int n(String r) => h.server.callsTo(r, method: 'GET').length;
    await _hoverAndOpen(tester, h, () {
      expect(
        h.server.callsTo(PurT.orders).single.path,
        '/purchasing/branches/$allBranchesId/orders',
      );
    });
    expect(n(PurT.orders), 1);
    expect(n(PurT.suppliers), 1);
    expect(inOrders(find.text('PO-1043')), findsOneWidget);
  });
}
