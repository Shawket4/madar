// Intent warming on Pricing & availability: resting on a collapsed item warms
// its studio read, resting on Next warms that page, so the press asks the
// server nothing more.
import 'package:dashboard_catalog_menu/src/area_seed.dart';
import 'package:dashboard_catalog_menu/src/pricing/pricing_widgets.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  testWidgets('MENU-PRC-012 / MENU-PRC-023 an item warms its studio and Next '
      'its page; pressing them asks the server nothing more', (tester) async {
    final h = await pumpPricing(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    final head = find.ancestor(
      of: pageText('Iced Latte'),
      matching: find.byType(PricingItemHead),
    );
    await reveal(h, head);
    expect(h.server.callsTo(studioT), isEmpty);
    await mouse.moveTo(tester.getCenter(head));
    await h.settle();
    expect(
      h.server.callsTo(studioT, method: 'GET').single.path,
      '/menu-items/${MenuSeedIds.item('iced_latte')}/studio',
      reason: 'the studio read is warmed',
    );
    await h.tap(head);
    expect(cellOf(sizeId('iced_latte', 'Regular'), 'in_store'),
        findsOneWidget);
    expect(h.server.callsTo(studioT, method: 'GET'), hasLength(1),
        reason: 'the row opened from the cache');

    int page2() => [
      for (final c in h.server.callsTo(catalogT, method: 'GET'))
        if (c.query['page']?.single == '2') c,
    ].length;
    final pager = inPage(find.byType(DashPagination));
    final next = find.descendant(
      of: pager,
      matching: find.bySemanticsLabel('Next'),
    );
    await reveal(h, pager);
    expect(page2(), 0);
    await mouse.moveTo(tester.getCenter(next));
    await h.settle();
    expect(page2(), 1, reason: 'page 2 is warmed');
    await h.tap(next);
    expect(pageText('Spanish Latte'), findsOneWidget);
    expect(page2(), 1, reason: 'page 2 came from the cache');
  });
}
