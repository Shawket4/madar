// The web's `prefetchRoute('/inventory/today')`: pointing at the sidebar's
// Today row warms the branch's valuation, low stock, stock and waste (or the
// org roll-ups) and the org's suppliers and catalog, so opening the page asks
// for none of them again. The org's orders (keyed by a wall-clock cutoff) and
// the branch's counts are left to the page, as on the web.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/shell.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Future<void> _hoverThenOpen(
  WidgetTester tester,
  DashHarness h, {
  required List<String> warmed,
  required List<String> pageOwn,
}) async {
  int n(String r) => h.server.callsTo(r, method: 'GET').length;
  for (final r in [...warmed, ...pageOwn]) {
    expect(n(r), 0, reason: '$r before the hover');
  }
  final row = find.descendant(
    of: find.byType(DashSidebar),
    matching: find.text('Today'),
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
  for (final r in warmed) {
    expect(n(r), 1, reason: '$r warmed on hover');
  }
  for (final r in pageOwn) {
    expect(n(r), 0, reason: '$r is left to the page');
  }

  await h.tap(row);
  expect(h.location.path, todayPath);
  for (final r in warmed) {
    expect(n(r), 1, reason: '$r served from the cache');
  }
  for (final r in pageOwn) {
    expect(n(r), 1, reason: '$r asked once by the page');
  }
}

void main() {
  testWidgets('INV-TOD-003 (prefetch) a branch: hovering Today warms its '
      'reads; opening it refetches nothing', (tester) async {
    final h = await pumpToday(
      tester,
      path: '/inventory/settings',
      branch: SeedIds.zamalek,
    );
    await _hoverThenOpen(
      tester,
      h,
      warmed: [
        branchValuation,
        branchLow,
        stockRoute,
        wasteRoute,
        suppliersRoute,
        catalogRoute,
      ],
      pageOwn: [orgOrders, stocktakesRoute],
    );
  });

  testWidgets('INV-TOD-003 (prefetch) all branches: the org roll-ups', (
    tester,
  ) async {
    final h = await pumpToday(tester, path: '/inventory/settings');
    await _hoverThenOpen(
      tester,
      h,
      warmed: [orgValuation, orgLow, suppliersRoute, catalogRoute],
      pageOwn: [orgOrders],
    );
    for (final r in [branchValuation, branchLow, stockRoute, wasteRoute]) {
      expect(h.server.callsTo(r), isEmpty, reason: r);
    }
  });
}
