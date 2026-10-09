// Intent warming on Orders: pointing at a row warms the order sheet's reads,
// pointing at the pager warms that page, so the press asks nothing more.
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_api/mock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'orders_support.dart';

int _pages(MockServer s, String page) => [
  for (final c in s.callsTo(listRoute, method: 'GET'))
    if (c.query['page']?.single == page) c,
].length;

void main() {
  testWidgets('a row warms its sheet and the pager its page; pressing them '
      'asks the server nothing more', (tester) async {
    final h = await pumpOrders(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    // The first row: the table's pressables with an intent, less the pager.
    final next = h.t('common.next');
    final previous = h.t('common.previous');
    final row = tester
        .widgetList<DashPressable>(inTable(find.byType(DashPressable)))
        .firstWhere(
          (p) =>
              p.onIntent != null &&
              p.semanticLabel != next &&
              p.semanticLabel != previous,
        );
    final rowFinder = find.byWidget(row);
    final catalogBefore = h.server.callsTo(catalogRoute).length;
    expect(h.server.callsTo(orderRoute), isEmpty);

    await mouse.moveTo(tester.getCenter(rowFinder));
    await h.settle();
    final warmed = h.server.callsTo(orderRoute, method: 'GET');
    expect(warmed, hasLength(1), reason: 'the sheet read is warmed');
    final id = warmed.single.path.split('/').last;
    final catalogWarm = h.server.callsTo(catalogRoute).length;

    await h.tap(rowFinder);
    expect(h.location.queryParameters['order'], id);
    expect(h.server.callsTo(orderRoute, method: 'GET'), hasLength(1),
        reason: 'the sheet opened from the cache');
    expect(h.server.callsTo(catalogRoute).length, catalogWarm);
    expect(catalogWarm, greaterThanOrEqualTo(catalogBefore));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();

    expect(_pages(h.server, '2'), 0);
    final nextButton = find.bySemanticsLabel(next);
    await tester.ensureVisible(nextButton);
    await h.settle();
    await mouse.moveTo(tester.getCenter(nextButton));
    await h.settle();
    expect(_pages(h.server, '2'), 1, reason: 'page 2 is warmed');
    await h.tap(nextButton);
    expect(_pages(h.server, '2'), 1, reason: 'page 2 came from the cache');
    final page2 = h.t('common.page', args: {'current': 2, 'total': '#'});
    expect(find.textContaining(page2.split('#').first), findsOneWidget);
  });
}
