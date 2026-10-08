// Smoke test: the delivery unit's page(s) open through the real
// app shell on the mock server. The unit's builder replaces this with the
// driven tests of its inventory rows.
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

void main() {
  testWidgets('/settings/delivery opens in the settings shell', (tester) async {
    final h = await pumpSetup(tester, path: '/settings/delivery');
    expect(h.location.path, '/settings/delivery');
    expect(find.text(h.t('nav.settings')), findsWidgets);
    expect(find.text(h.t('delivery.settingsSubtitle')), findsOneWidget);
    await h.shot('smoke');
  });
  testWidgets('/settings/delivery-zones opens in the settings shell', (
    tester,
  ) async {
    final h = await pumpSetup(tester, path: '/settings/delivery-zones');
    expect(h.location.path, '/settings/delivery-zones');
    expect(find.text(h.t('nav.settings')), findsWidgets);
    expect(find.text(h.t('delivery.zonesSubtitle')), findsOneWidget);
    await h.shot('smoke');
  });
}
