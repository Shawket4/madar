// Customers (SELL-CUS rows). The customers unit's builder fills this file.
import 'package:dashboard_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/sell_harness.dart';

void main() {
  testWidgets('/customers opens inside the shell', (tester) async {
    final h = await pumpSell(tester, '/customers');
    expect(find.text(h.t('customers.subtitle')), findsOneWidget);
    await h.shot('customers/smoke');
    await h.tapText('Nada Kamal');
    await h.shot('customers/sheet');
  });
  testWidgets('/customers phone ar', (tester) async {
    final h = await pumpSell(tester, '/customers', size: DashSize.phone, locale: 'ar', dark: true);
    await h.shot('customers/smoke');
    await h.tapText('Nada Kamal');
    await h.shot('customers/sheet');
  });
}
