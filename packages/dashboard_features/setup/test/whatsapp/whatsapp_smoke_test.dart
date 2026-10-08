// Smoke test: the whatsapp unit's page(s) open through the real
// app shell on the mock server. The unit's builder replaces this with the
// driven tests of its inventory rows.
import 'package:dashboard_api/mock.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

void main() {
  testWidgets('/settings/whatsapp opens in the settings shell', (tester) async {
    final h = await pumpSetup(
      tester,
      path: '/settings/whatsapp',
      persona: Persona.platform,
    );
    expect(h.location.path, '/settings/whatsapp');
    expect(find.text(h.t('nav.settings')), findsWidgets);
    expect(find.text(h.t('whatsapp.subtitle')), findsOneWidget);
    await h.shot('smoke');
  });
}
