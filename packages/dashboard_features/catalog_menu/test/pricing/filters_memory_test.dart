// The owner's rule (2026-10-11): a filter carries through navigation. The
// pricing page's tab, search and page come back from another page
// (`DashRememberedState`).
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Future<void> _search(WidgetTester tester, String q) async {
  await tester.enterText(inPage(find.byType(EditableText)).first, q);
  await tester.pump(DashSearchInput.listDelay);
}

String? _shownSearch(WidgetTester tester) =>
    tester.widget<DashSearchInput>(inPage(find.byType(DashSearchInput))).value;

void main() {
  testWidgets('the items search comes back from another page', (tester) async {
    final h = await pumpPricing(tester);
    await _search(tester, 'latte');
    await h.settle();
    expect(pageText('Americano'), findsNothing);
    await h.go('/menu/groups');
    await h.go(pricingPath);
    expect(_shownSearch(tester), 'latte');
    expect(h.server.callsTo(catalogT).last.query['search'], ['latte']);
    expect(pageText('Caffè Latte'), findsOneWidget);
    expect(pageText('Americano'), findsNothing);
  });

  testWidgets('the items page comes back from another page', (tester) async {
    final h = await pumpPricing(tester);
    await h.tap(inPage(find.bySemanticsLabel('Next')));
    expect(h.server.callsTo(catalogT).last.query['page'], ['2']);
    await h.go('/menu/items');
    await h.go(pricingPath);
    expect(h.server.callsTo(catalogT).last.query['page'], ['2']);
  });

  testWidgets('the Add-ons tab and its search come back', (tester) async {
    final h = await pumpPricing(tester);
    await h.tap(pageText('Add-ons'));
    await _search(tester, 'oat');
    await h.settle();
    expect(h.server.callsTo(addonCatalogT).last.query['search'], ['oat']);
    await h.go('/menu/groups');
    await h.go(pricingPath);
    final seg = tester.widget<DashSegmentedControl<String>>(
      inPage(find.byType(DashSegmentedControl<String>)),
    );
    expect(seg.value, 'addons');
    expect(_shownSearch(tester), 'oat');
  });
}
