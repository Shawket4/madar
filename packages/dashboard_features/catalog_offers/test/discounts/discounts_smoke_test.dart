// The discounts page mounts in the shell at /discounts, with its ?edit param.
import 'package:dashboard_catalog_offers/dashboard_catalog_offers.dart';
import 'package:dashboard_catalog_offers/src/discounts/discounts_page.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('/discounts opens the discounts page', (tester) async {
    final h = await DashHarness.pump(
      tester,
      areas: const [catalogOffersArea],
      path: '/discounts',
    );
    expect(find.byType(DiscountsPage), findsOneWidget);
    expect(find.text(h.t('discounts.subtitle')), findsOneWidget);
    await h.shot('discounts/scaffold');
  });

  testWidgets('?edit=<id> reaches the page', (tester) async {
    await DashHarness.pump(
      tester,
      areas: const [catalogOffersArea],
      path: '/discounts?edit=abc',
    );
    expect(
      tester.widget<DiscountsPage>(find.byType(DiscountsPage)).edit,
      'abc',
    );
  });
}
