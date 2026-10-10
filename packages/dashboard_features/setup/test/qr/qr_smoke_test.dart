// Smoke test: the qr unit's page(s) open through the real
// app shell on the mock server. The unit's builder replaces this with the
// driven tests of its inventory rows.
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

void main() {
  testWidgets('/settings/qr opens in the settings shell', (tester) async {
    final h = await pumpSetup(tester, path: '/settings/qr');
    expect(h.location.path, '/settings/qr');
    expect(find.text(h.t('nav.settings')), findsWidgets);
    expect(find.text(h.t('qr.subtitle')), findsOneWidget);
    await h.shot('smoke');
  });
}
