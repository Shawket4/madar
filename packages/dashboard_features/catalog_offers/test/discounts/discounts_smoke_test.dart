// The discounts page mounts in the shell at /discounts, with its ?edit param.
import 'package:dashboard_catalog_offers/src/discounts/discounts_page.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  testWidgets('/discounts opens the discounts page', (tester) async {
    final h = await pumpDiscounts(tester);
    expect(page, findsOneWidget);
    expect(inPage(find.text(h.t('discounts.subtitle'))), findsOneWidget);
    expect(inPage(find.text('Staff Meal')), findsOneWidget);
  });

  testWidgets('?edit=<id> reaches the page', (tester) async {
    await pumpDiscounts(tester, path: '/discounts?edit=abc');
    expect(
      tester.widget<DiscountsPage>(find.byType(DiscountsPage)).edit,
      'abc',
    );
  });
}
