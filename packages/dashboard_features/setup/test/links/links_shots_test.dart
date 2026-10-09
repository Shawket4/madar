// The links page editor's screenshot matrix: the default state at every
// size in en-light and ar-dark, then each other state at desktop-en-light
// and phone-ar-light.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';
import 'support.dart';

Future<void> _scrollTo(DashHarness h, Finder f) async {
  await h.tester.ensureVisible(f);
  await h.settle();
}

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in [('en', false), ('ar', true)]) {
      testWidgets('default, ${size.name} $lang', (tester) async {
        final h = await pumpLinks(
          tester,
          size: size,
          locale: lang,
          dark: dark,
        );
        await h.shot('default');
        for (final key in [
          'links-buttons',
          'links-socials',
          'links-visit',
          'links-preview-0',
        ]) {
          await _scrollTo(h, byKey(key));
          await h.shot('default-$key');
        }
      });
    }
  }

  for (final (size, lang) in [
    (DashSize.desktop, 'en'),
    (DashSize.phone, 'ar'),
  ]) {
    testWidgets('states, ${size.name} $lang', (tester) async {
      final m = setupMockServer();
      final gate = m.server.hold('GET', LinksRoutes.page);
      final h = await pumpLinks(tester, size: size, locale: lang, backend: m);
      await h.shot('loading');
      gate.release();
      await h.settle();

      FakeClipboard(tester);
      await h.tap(byKey('links-qr'));
      await h.shot('qr-dialog');
      await h.tester.tapAt(Offset.zero);
      await h.settle();

      await h.tap(byKey('links-add'));
      await _scrollTo(h, byKey('links-add'));
      await h.shot('new-link');
      await h.tap(byKey('links-save'));
      await h.shot('fix-links-toast');
      await h.flushTimers();
    });
  }

  testWidgets('no address, no org, failed', (tester) async {
    final m = setupMockServer();
    m.db['orgs'].update(SeedIds.sabahOrg, {'custom_branding': false});
    final h = await pumpLinks(tester, backend: m);
    await h.shot('no-address');

    final h2 = await pumpLinks(tester, persona: Persona.platform);
    await h2.shot('no-org');

    final f = setupMockServer();
    f.server.fail(
      'GET',
      LinksRoutes.page,
      MockResponse.error(500, 'Database is down'),
      times: null,
    );
    final h3 = await pumpLinks(tester, backend: f);
    await h3.shot('failed');
  });
}
