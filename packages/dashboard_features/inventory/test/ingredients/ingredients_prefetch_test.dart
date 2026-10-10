// The web's `prefetchRoute('/inventory/ingredients')`: pointing at the
// sidebar's Ingredients row warms the catalog, the org's branches and the
// picked branch's stock, so opening the page asks for none of them again.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/shell.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  testWidgets('INV-ING-003 (prefetch) hovering Ingredients warms its reads; '
      'opening it refetches nothing', (tester) async {
    final h = await pumpIngredients(
      tester,
      path: '/inventory/settings',
      branch: SeedIds.zamalek,
    );
    int n(String r) => h.server.callsTo(r, method: 'GET').length;
    expect(n(catalogRoute), 0);
    expect(n(stockRoute), 0);
    final branches = n(branchesRoute);

    final row = find.descendant(
      of: find.byType(DashSidebar),
      matching: find.text('Ingredients'),
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
    expect(n(catalogRoute), 1, reason: 'catalog warmed on hover');
    expect(n(stockRoute), 1, reason: 'branch stock warmed on hover');
    expect(n(branchesRoute), branches, reason: 'branches already held');

    await h.tap(row);
    expect(h.location.path, ingredientsPath);
    expect(n(catalogRoute), 1, reason: 'catalog served from the cache');
    expect(n(stockRoute), 1, reason: 'stock served from the cache');
    expect(n(branchesRoute), branches);
    expect(cellText('Almond Milk'), findsOneWidget);
  });
}
