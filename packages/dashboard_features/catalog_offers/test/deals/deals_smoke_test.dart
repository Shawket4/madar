// The deals page mounts in the shell at /menu/deals, with its ?edit param.
import 'package:dashboard_catalog_offers/src/deals/deals_page.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  testWidgets('/menu/deals opens the deals page', (tester) async {
    final h = await pumpDeals(tester);
    expect(find.byType(DealsPage), findsOneWidget);
    expect(find.text(h.t('deals.subtitle')), findsOneWidget);
    await h.shot('deals/smoke');
  });

  testWidgets('phone ar dark smoke', (tester) async {
    final h = await pumpDeals(
      tester,
      size: DashSize.phone,
      locale: 'ar',
      dark: true,
    );
    expect(find.byType(DealsPage), findsOneWidget);
    await h.shot('deals/smoke');
  });

  testWidgets('?edit=new opens the dialog', (tester) async {
    final h = await pumpDeals(tester, path: '/menu/deals?edit=new');
    expect(tester.widget<DealsPage>(find.byType(DealsPage)).edit, 'new');
    expect(find.text(h.t('deals.dialogHint')), findsOneWidget);
    await h.shot('deals/smoke-new');
  });
}
