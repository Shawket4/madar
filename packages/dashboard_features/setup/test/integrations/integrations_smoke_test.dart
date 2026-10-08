// Smoke test: the integrations unit's page(s) open through the real
// app shell on the mock server. The unit's builder replaces this with the
// driven tests of its inventory rows.
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

void main() {
  testWidgets('/settings/integrations opens in the settings shell', (
    tester,
  ) async {
    final h = await pumpSetup(tester, path: '/settings/integrations');
    expect(h.location.path, '/settings/integrations');
    expect(find.text(h.t('nav.settings')), findsWidgets);
    expect(find.text(h.t('integrations.hintReadOnly')), findsOneWidget);
    await h.shot('smoke');
  });
}
