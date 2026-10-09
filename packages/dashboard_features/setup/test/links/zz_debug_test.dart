import 'package:dashboard_api/mock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';
import 'support.dart';

void main() {
  testWidgets('debug qr failure', (tester) async {
    final m = setupMockServer();
    m.server.fail('GET', LinksRoutes.qr, MockResponse.error(500, 'The link shortener did not answer'));
    final h = await pumpLinks(tester, backend: m);
    await h.tap(byKey('links-qr'));
    // ignore: avoid_print
    print('CALLS ${h.server.callsTo(LinksRoutes.qr).length}');
    for (final t in tester.widgetList<Text>(find.byType(Text))) {
      final d = t.data ?? '';
      if (d.contains('shortener') || d.contains('error') || d.contains('rror')) print('TEXT $d');
    }
    await h.flushTimers();
  });
}
