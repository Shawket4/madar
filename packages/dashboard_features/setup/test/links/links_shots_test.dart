// The links page editor's screenshot matrix: the default state at every
// size in en-light and ar-dark, then each other state at desktop-en-light
// and phone-ar-light.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/shell.dart' show sidebarCollapsedProvider;
import 'package:dashboard_core/testing.dart';
import 'package:flutter/widgets.dart' show Offset, Size, ValueKey;
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
        final h = await pumpLinks(tester, size: size, locale: lang, dark: dark);
        await h.shot('default');
        for (final key in [
          'links-buttons',
          'links-socials',
          'links-visit',
          'links-preview-0',
          'menu-display-section',
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

      await _scrollTo(h, byKey('links-preview-0'));
      final frame = tester.getRect(byKey('links-preview-0'));
      await h.tester.dragFrom(
        frame.topCenter + const Offset(0, 120),
        const Offset(0, -1600),
      );
      await h.settle();
      await h.shot('preview-bottom');

      FakeClipboard(tester);
      await h.tap(byKey('links-qr'));
      await h.shot('qr-dialog');
      await h.tester.tapAt(Offset.zero);
      await h.settle();

      await h.tap(byKey('links-add'));
      // The new row itself, not the button under it.
      await _scrollTo(
        h,
        find
            .ancestor(
              of: inKey(
                'links-buttons',
                find.text(h.t('links.editor.newLink')),
              ),
              matching: find.byWidgetPredicate(
                (w) =>
                    w.key is ValueKey<String> &&
                    (w.key! as ValueKey<String>).value.startsWith(
                      'links-item-',
                    ),
              ),
            )
            .first,
      );
      await h.shot('new-link');
      await h.tap(byKey('links-save'));
      await h.shot('fix-links-toast');
      await h.flushTimers();
    });
  }

  for (final (lang, dark) in [('en', false), ('ar', true)]) {
    testWidgets('wide preview, $lang', (tester) async {
      // A 1000 px window with the sidebar on its rail: the frame passes 768.
      final h = await pumpLinks(tester, locale: lang, dark: dark);
      tester.view.physicalSize = const Size(1000, 900) * DashSize.pixelRatio;
      await h.container.read(sidebarCollapsedProvider.notifier).set(true);
      await h.settle();
      await _scrollTo(h, byKey('links-preview-0'));
      await h.shot('preview-wide');
      final frame = tester.getRect(byKey('links-preview-0'));
      await h.tester.dragFrom(
        frame.topCenter + const Offset(0, 120),
        const Offset(0, -400),
      );
      await h.settle();
      await h.shot('preview-wide-buttons');
    });
  }

  // Free: the menu without prices, usable, and the links page locked.
  for (final size in [DashSize.desktop, DashSize.phone]) {
    for (final (lang, dark) in [('en', false), ('ar', true)]) {
      testWidgets('free, ${size.name} $lang', (tester) async {
        // A Free shop has no host of its own: the generic one.
        final m = setupMockServer();
        m.db['orgs'].update(SeedIds.sabahOrg, {'custom_branding': false});
        final h = await pumpLinks(
          tester,
          backend: m,
          size: size,
          locale: lang,
          dark: dark,
          overrides: [freePlan],
        );
        await h.shot('free');
        await _scrollTo(h, byKey('paid-lock-branding'));
        await h.shot('free-locked');
      });
    }
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
