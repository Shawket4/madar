// Intent warming on Orders: pointing at a row warms the order sheet's reads,
// pointing at the pager warms that page, so the press asks nothing more.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_sell/src/orders/order_sheet.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'orders_support.dart';

int _pages(MockServer s, String page) => [
  for (final c in s.callsTo(listRoute, method: 'GET'))
    if (c.query['page']?.single == page) c,
].length;

int _statuses(MockServer s, String status) => [
  for (final c in s.callsTo(listRoute, method: 'GET'))
    if (c.query['status']?.single == status) c,
].length;

/// An option in the open select's list.
Finder _option(String text) => find.descendant(
  of: find.byWidgetPredicate(
    (w) => w.runtimeType.toString().startsWith('DashOptionList'),
  ),
  matching: find.text(text),
);

/// A mouse resting on [target] long enough to count as intent.
Future<TestGesture> _rest(WidgetTester tester, DashHarness h, Finder target) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await tester.ensureVisible(target);
  await h.settle();
  await mouse.moveTo(tester.getCenter(target));
  await h.settle();
  return mouse;
}

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

    // Scrolled first: the tap below scrolls the row to the top, and a resting
    // pointer would then warm whichever row slid under it.
    await tester.ensureVisible(rowFinder);
    await h.settle();
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

  testWidgets('a filter option warms the page it picks; picking it asks '
      'nothing more', (tester) async {
    final h = await pumpOrders(tester);
    await h.tap(find.byKey(const ValueKey('orders-status')));
    expect(_statuses(h.server, 'voided'), 0);
    await _rest(tester, h, _option('Voided'));
    expect(_statuses(h.server, 'voided'), 1, reason: 'warmed on intent');
    await h.tap(_option('Voided'));
    expect(_statuses(h.server, 'voided'), 1, reason: 'came from the cache');
  });

  testWidgets("the row menu's Details warms the sheet", (tester) async {
    final h = await pumpOrders(tester);
    final actions = find.byWidgetPredicate(
      (w) => w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('order-actions-'),
    );
    await h.tap(actions.first);
    final details = find.text('Details').last;
    await _rest(tester, h, details);
    final warmed = h.server.callsTo(orderRoute, method: 'GET').length;
    expect(warmed, greaterThanOrEqualTo(1), reason: 'the sheet read is warmed');
    await h.tap(details);
    expect(find.byType(OrderSheet), findsOneWidget);
    expect(h.server.callsTo(orderRoute, method: 'GET'), hasLength(warmed));
  });

  testWidgets('the export button warms the branch name; the excluded-items '
      'trigger the menu', (tester) async {
    final h = await pumpOrders(tester);
    final branches = h.server.callsTo('/branches/{id}').length;
    final export = find.byKey(const ValueKey('orders-export'));
    final mouse = await _rest(tester, h, export);
    expect(h.server.callsTo('/branches/{id}'), hasLength(branches + 1));
    await h.tap(export);
    expect(h.server.callsTo('/branches/{id}'), hasLength(branches + 1));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
    await mouse.moveTo(Offset.zero);
    await h.settle();

    expect(h.server.callsTo(menuItemsRoute), isEmpty);
    final trigger = find.byKey(const ValueKey('orders-exclude-trigger'));
    await tester.ensureVisible(trigger);
    await h.settle();
    await mouse.moveTo(tester.getCenter(trigger));
    await h.settle();
    expect(h.server.callsTo(menuItemsRoute), hasLength(1));
    await h.tap(trigger);
    expect(h.server.callsTo(menuItemsRoute), hasLength(1));
  });

  testWidgets("the sheet's member name warms the member's sheet",
      (tester) async {
    final id = OrderSeedIds.showcase('reward');
    final h = await pumpOrders(tester, query: '?order=$id');
    final member = find.byKey(const ValueKey('order-sheet-member'));
    final before = h.server.callsTo('/customers/{id}').length;
    await _rest(tester, h, member);
    expect(h.server.callsTo('/customers/{id}'), hasLength(before + 1));
    await h.tap(member);
    expect(h.server.callsTo('/customers/{id}'), hasLength(before + 1));
  });
}
