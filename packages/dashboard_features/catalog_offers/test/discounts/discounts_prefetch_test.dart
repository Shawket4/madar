// The web's intent prefetch (`prefetchRoute('/discounts')`): pointing at the
// Discounts leaf warms the org's list with the page's own key, so opening
// the page asks the server nothing more.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/shell.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  testWidgets('pointing at Discounts warms its list; opening it refetches '
      'nothing', (tester) async {
    final h = await pumpDiscounts(tester, path: '/settings');
    h.allowUnmatched = true;
    List<MockCall> lists() => h.server.callsTo(listRoute, method: 'GET');
    expect(lists(), isEmpty);

    final row = find.descendant(
      of: find.byType(DashSidebar),
      matching: find.text(h.t('nav.discounts')),
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
    expect(lists().single.query['org_id'], [SeedIds.sabahOrg]);

    await h.tap(row);
    expect(h.location.path, '/discounts');
    expect(page, findsOneWidget);
    expect(lists(), hasLength(1), reason: 'served from the cache');
  });
}
