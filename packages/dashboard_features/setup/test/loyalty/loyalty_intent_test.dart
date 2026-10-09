// Intent warming on Loyalty: pointing at a tab warms what it reads, at a
// member row its card, at a "Came from" option the list under it; the press
// then asks the server nothing more.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Finder _tab(String label) => find.descendant(
  of: find.byKey(const ValueKey('loyalty-tabs')),
  matching: find.text(label),
);

Future<TestGesture> _mouse(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  return mouse;
}

Future<void> _rest(DashHarness h, TestGesture mouse, Finder f) async {
  await h.tester.ensureVisible(f);
  await h.settle(rounds: 2);
  await mouse.moveTo(h.tester.getCenter(f));
  await h.settle();
}

int _count(MockServer s, String route) =>
    s.callsTo(route, method: 'GET').length;

void main() {
  testWidgets('tabs: Rewards, Members and Overview warm their reads; the '
      'press asks nothing more', (tester) async {
    final h = await pumpLoyalty(tester);
    final mouse = await _mouse(tester);
    final s = h.server;

    expect(_count(s, LoyaltyRoutes.rewards), 0);
    expect(_count(s, LoyaltyRoutes.earning), 0);
    await _rest(h, mouse, _tab('Rewards'));
    expect(_count(s, LoyaltyRoutes.rewards), 1);
    expect(_count(s, LoyaltyRoutes.menu), 1);
    // The seeded programme collects stamps, so the earning card's read too.
    expect(_count(s, LoyaltyRoutes.earning), 1);
    await h.tap(_tab('Rewards'));
    expect(_count(s, LoyaltyRoutes.rewards), 1);
    expect(_count(s, LoyaltyRoutes.menu), 1);
    expect(_count(s, LoyaltyRoutes.earning), 1);

    expect(_count(s, LoyaltyRoutes.customers), 0);
    await _rest(h, mouse, _tab('Members'));
    expect(_count(s, LoyaltyRoutes.customers), 1);
    await h.tap(_tab('Members'));
    expect(_count(s, LoyaltyRoutes.customers), 1);

    await _rest(h, mouse, _tab('Overview'));
    expect(_count(s, LoyaltyRoutes.analytics), 1);
    expect(_count(s, LoyaltyRoutes.members), 1);
    await h.tap(_tab('Overview'));
    expect(_count(s, LoyaltyRoutes.analytics), 1);
    expect(_count(s, LoyaltyRoutes.members), 1);
  });

  testWidgets('a member row warms its card; opening it asks nothing more',
      (tester) async {
    final h = await pumpLoyalty(tester);
    await openTab(h, 'Members');
    await h.enterText(inPage(find.byType(DashSearchInput)), 'Nada Kamal');
    await tester.pump(const Duration(milliseconds: 350));
    await h.settle();
    final mouse = await _mouse(tester);
    final row = inPage(
      find.byWidgetPredicate(
        (w) => w is DashPressable && w.semanticLabel == 'Nada Kamal',
      ),
    );
    expect(_count(h.server, LoyaltyRoutes.member), 0);
    await _rest(h, mouse, row);
    expect(_count(h.server, LoyaltyRoutes.member), 1);
    await h.tap(row);
    expect(_count(h.server, LoyaltyRoutes.member), 1);
    expect(inSheet(find.text('Balance')), findsOneWidget);
  });

  testWidgets('a "Came from" option warms the list under it', (tester) async {
    final h = await pumpLoyalty(tester);
    await openTab(h, 'Members');
    await h.tap(inPage(find.byType(DashFilterSelect<String>)));
    final option = find.descendant(
      of: find.byWidgetPredicate((w) => w is DashOptionList),
      matching: find.text('Online order'),
    );
    int online() => [
      for (final c in h.server.callsTo(LoyaltyRoutes.customers))
        if (c.query['source']?.single == 'online') c,
    ].length;
    final mouse = await _mouse(tester);
    expect(online(), 0);
    await _rest(h, mouse, option);
    expect(online(), 1);
    await h.tap(option);
    expect(online(), 1);
  });

  testWidgets('SET-LOY-004 the code button warms the code; the press asks '
      'nothing more', (tester) async {
    final h = await pumpLoyalty(tester, query: atBranch(SeedIds.zamalek));
    final mouse = await _mouse(tester);
    final button = find.byKey(const ValueKey('loyalty-code'));
    expect(_count(h.server, LoyaltyRoutes.branchQr), 0);
    await _rest(h, mouse, button);
    expect(_count(h.server, LoyaltyRoutes.branchQr), 1);
    await h.tap(button);
    expect(_count(h.server, LoyaltyRoutes.branchQr), 1);
    expect(find.text(h.t('loyalty.joinQr')), findsWidgets);
  });
}
