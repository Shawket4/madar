// Smoke test: the QR codes open through the real app shell on the mock
// server, at their old addresses too: both redirect to Settings › Links & QR
// codes, landing on the codes.
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

void main() {
  for (final old in ['/settings/qr', '/qr']) {
    testWidgets('$old opens Links & QR codes on its codes', (tester) async {
      final h = await pumpSetup(tester, path: old);
      expect(h.location.path, '/settings/links-qr');
      expect(h.location.queryParameters, {'section': 'codes'});
      expect(find.text(h.t('nav.settings')), findsWidgets);
      expect(find.text(h.t('qr.output.title')), findsOneWidget);
      await h.shot('smoke');
    });
  }
}
