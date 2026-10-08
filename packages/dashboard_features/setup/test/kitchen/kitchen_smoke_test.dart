// Smoke test: the kitchen unit's page(s) open through the real
// app shell on the mock server. The unit's builder replaces this with the
// driven tests of its inventory rows.
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

void main() {
  testWidgets('/settings/kitchen-stations opens in the settings shell', (
    tester,
  ) async {
    final h = await pumpSetup(tester, path: '/settings/kitchen-stations');
    expect(h.location.path, '/settings/kitchen-stations');
    expect(find.text(h.t('nav.settings')), findsWidgets);
    expect(find.text(h.t('kitchen.stationsSubtitle')), findsOneWidget);
    await h.shot('smoke');
  });
  testWidgets('/settings/kitchen-routing opens in the settings shell', (
    tester,
  ) async {
    final h = await pumpSetup(tester, path: '/settings/kitchen-routing');
    expect(h.location.path, '/settings/kitchen-routing');
    expect(find.text(h.t('nav.settings')), findsWidgets);
    expect(find.text(h.t('kitchen.routingSubtitle')), findsOneWidget);
    await h.shot('smoke');
  });
}
