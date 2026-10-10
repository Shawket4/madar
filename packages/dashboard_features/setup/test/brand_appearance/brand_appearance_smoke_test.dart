// Smoke test: the brand appearance unit's page(s) open through the real
// app shell on the mock server. The unit's builder replaces this with the
// driven tests of its inventory rows.
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

void main() {
  testWidgets('/settings opens in the settings shell', (tester) async {
    final h = await pumpSetup(tester, path: '/settings');
    expect(h.location.path, '/settings');
    expect(find.text(h.t('nav.settings')), findsWidgets);
    expect(find.text(h.t('settings.appearanceDesc')), findsOneWidget);
    await h.shot('smoke');
  });
  testWidgets('/settings/brand opens in the settings shell', (tester) async {
    final h = await pumpSetup(tester, path: '/settings/brand');
    expect(h.location.path, '/settings/brand');
    expect(find.text(h.t('nav.settings')), findsWidgets);
    expect(find.text(h.t('settings.brandDesc')), findsOneWidget);
    await h.shot('smoke');
  });
}
