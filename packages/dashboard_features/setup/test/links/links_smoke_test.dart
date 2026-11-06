// Smoke test: the links page section opens through the real app shell on
// the mock server, at its old address too (it redirects to Settings › Links
// & QR codes).
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

void main() {
  testWidgets('/settings/links opens Links & QR codes in the settings shell', (
    tester,
  ) async {
    final h = await pumpSetup(tester, path: '/settings/links');
    expect(h.location.path, '/settings/links-qr');
    expect(h.location.queryParameters, isEmpty);
    expect(find.text(h.t('nav.settings')), findsWidgets);
    expect(find.text(h.t('links.editor.desc')), findsOneWidget);
    await h.shot('smoke');
  });
}
