// Smoke test: the booking settings unit's page(s) open through the real
// app shell on the mock server. The unit's builder replaces this with the
// driven tests of its inventory rows.
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

void main() {
  testWidgets('/settings/bookings opens in the settings shell', (tester) async {
    final h = await pumpSetup(tester, path: '/settings/bookings');
    expect(h.location.path, '/settings/bookings');
    expect(find.text(h.t('nav.settings')), findsWidgets);
    expect(find.text(h.t('settings.bookingsDesc')), findsOneWidget);
    await h.shot('smoke');
  });
}
