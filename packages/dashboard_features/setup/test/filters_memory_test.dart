// The owner's rule (2026-10-11): a filter carries through navigation. The
// settings panes' tabs, searches and filters come back after another page
// (`DashRememberedState`, `DashListMemory`).
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_setup/src/payment_methods/availability_tab.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kitchen/kitchen_support.dart' as kitchen;
import 'loyalty/support.dart' as loyalty;
import 'payment_methods/pm_support.dart' as pm;

void main() {
  testWidgets('loyalty: the Members tab, its search and source come back', (
    tester,
  ) async {
    final h = await loyalty.pumpLoyalty(tester);
    await loyalty.openTab(h, 'Members');
    await h.enterText(loyalty.inPage(find.byType(DashSearchInput)), 'Nada');
    await tester.pump(const Duration(milliseconds: 350));
    await h.settle();
    await h.tap(loyalty.inPage(find.byType(DashFilterSelect<String>)));
    await h.tap(
      find.descendant(
        of: find.byWidgetPredicate((w) => w is DashOptionList),
        matching: find.text('Loyalty sign-up'),
      ),
    );
    await h.go('/settings/qr');
    await h.go(loyalty.loyaltyPath);
    expect(
      loyalty.inPage(find.byKey(const ValueKey('loyalty-members'))),
      findsOneWidget,
    );
    final search = tester.widget<DashSearchInput>(
      loyalty.inPage(find.byType(DashSearchInput)),
    );
    expect(search.value, 'Nada');
    final select = tester.widget<DashFilterSelect<String>>(
      loyalty.inPage(find.byType(DashFilterSelect<String>)),
    );
    expect(select.value, 'loyalty');
  });

  testWidgets('kitchen routing: per item, its search come back', (
    tester,
  ) async {
    final h = await kitchen.pumpKitchen(tester, path: kitchen.routingPath);
    await h.tap(
      find.descendant(
        of: kitchen.inRouting(kitchen.byKey('routing-tabs')),
        matching: find.text(h.t('kitchen.byItem')),
      ),
    );
    await h.enterText(
      kitchen.inRouting(kitchen.byKey('routing-search')),
      'croiss',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await h.settle();
    await h.go(kitchen.stationsPath + kitchen.zamalek);
    await h.go(kitchen.routingPath + kitchen.zamalek);
    final search = tester.widget<DashSearchInput>(
      kitchen.inRouting(kitchen.byKey('routing-search')),
    );
    expect(search.value, 'croiss');
  });

  testWidgets('payment methods: the Availability tab comes back', (
    tester,
  ) async {
    final h = await pm.pumpPm(tester, query: pm.zamalek);
    await h.tap(
      find.descendant(
        of: find.byKey(const ValueKey('pm-tabs')),
        matching: find.text(h.t('paymentMethods.availability.title')),
      ),
    );
    expect(find.byType(AvailabilityTab), findsOneWidget);
    await h.go('/settings/qr');
    await h.go(pm.pmPath);
    expect(find.byType(AvailabilityTab), findsOneWidget);
  });

  testWidgets('another org forgets them', (tester) async {
    final h = await loyalty.pumpLoyalty(tester);
    await loyalty.openTab(h, 'Members');
    final memory = h.container.read(dashListMemoryProvider);
    expect(memory.recall('setup.loyalty').string('tab'), 'members');
    await h.container.read(sessionProvider.notifier).signOut();
    await h.settle();
    // Forgotten: at most the page's defaults are kept (a mounted page
    // resets itself on the org change and saves that).
    expect(memory.recall('setup.loyalty').string('tab'), isNot('members'));
  });
}
