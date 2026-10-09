// SELL-TIL prefetch: the web's `prefetchRoute('/tills')` warms the branch's
// open tills; opening the page then asks for them no second time.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/shell.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/sell_harness.dart';
import 'tills_support.dart';

void main() {
  testWidgets('pointing at Tills warms the open tills; opening it reads them '
      'from the cache', (tester) async {
    final h = await pumpSell(tester, '/nowhere', branchId: SeedIds.heliopolis);
    List<MockCall> open() => h.server.callsTo(tillsOpen, method: 'GET');
    expect(open(), isEmpty);
    final row = find.descendant(
      of: find.byType(DashSidebar),
      matching: find.text(h.t('nav.tills')),
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
    expect(open().single.path, '/tills/branches/${SeedIds.heliopolis}/open');

    await h.tap(row);
    expect(h.location.path, '/tills');
    expect(open(), hasLength(1), reason: 'served from the cache');
    expect(
      find.byKey(ValueKey('open-now-${TillIds.helioMorning}')),
      findsOneWidget,
    );
  });
}
