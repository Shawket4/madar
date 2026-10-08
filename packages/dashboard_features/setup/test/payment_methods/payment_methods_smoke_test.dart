// Smoke test: the payment methods unit's page(s) open through the real
// app shell on the mock server. The unit's builder replaces this with the
// driven tests of its inventory rows.
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

void main() {
  testWidgets('/settings/payment-methods opens in the settings shell', (
    tester,
  ) async {
    final h = await pumpSetup(tester, path: '/settings/payment-methods');
    expect(h.location.path, '/settings/payment-methods');
    expect(find.text(h.t('nav.settings')), findsWidgets);
    expect(find.text(h.t('settings.paymentMethodsHint')), findsOneWidget);
    await h.shot('smoke');
  });
}
