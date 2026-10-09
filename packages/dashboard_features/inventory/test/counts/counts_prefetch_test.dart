// The web's `prefetchRoute('/inventory/counts')`: pointing at the sidebar's
// Stock counts row warms the picked branch's counts list, so opening the page
// asks for it no second time. With All branches nothing is warmed.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Future<void> hoverRow(DashHarness h, Finder row) async {
  await h.tester.scrollUntilVisible(
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
  final mouse = await h.tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await mouse.moveTo(h.tester.getCenter(row));
  await h.settle();
}

void main() {
  final row = find.descendant(
    of: find.byType(DashSidebar),
    matching: find.text('Stock counts'),
  );

  testWidgets('INV-CNT-002 (prefetch) hovering Stock counts warms the '
      'branch\'s list; opening it reads nothing again', (tester) async {
    final h = await pumpCounts(
      tester,
      path: '/inventory/settings',
      branch: SeedIds.zamalek,
    );
    int n() => h.server.callsTo(listRoute, method: 'GET').length;
    expect(n(), 0);
    await hoverRow(h, row);
    expect(n(), 1, reason: 'warmed on hover');
    expect(
      h.server.callsTo(listRoute).single.path,
      '/stocktakes/branches/${SeedIds.zamalek}',
    );
    await h.tap(row);
    expect(h.location.path, countsPath);
    expect(n(), 1, reason: 'served from the cache');
    expect(inTable(find.text('Karim Adel')), findsNWidgets(3));
  });

  testWidgets('INV-CNT-002 (prefetch) All branches: nothing is warmed', (
    tester,
  ) async {
    final h = await pumpCounts(tester, path: '/inventory/settings');
    await hoverRow(h, row);
    expect(h.server.callsTo(listRoute), isEmpty);
    expect(h.container.read(currentScopeProvider).branchId, isNull);
  });
}
