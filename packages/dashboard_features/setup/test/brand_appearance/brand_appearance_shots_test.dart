// The screenshot matrix for Appearance, Brand and the settings shell. Run with
// FDASH_SHOTS set to write PNGs under <FDASH_SHOTS>/setup/<page>/.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_setup/src/brand_appearance/appearance_page.dart';
import 'package:dashboard_setup/src/brand_appearance/brand_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';
import 'support.dart';

/// Scrolls the page's own scroller a screen at a time, one PNG a screen.
Future<void> _shootPage(DashHarness h, Type page, String name) async {
  ScrollableState? state;
  for (final e
      in find
          .ancestor(of: find.byType(page), matching: find.byType(Scrollable))
          .evaluate()) {
    final s = (e as StatefulElement).state as ScrollableState;
    if (s.position.axis == Axis.vertical) {
      state = s;
      break;
    }
  }
  if (state == null) return h.shot('$name-1');
  final position = state.position;
  var i = 1;
  var y = 0.0;
  while (true) {
    position.jumpTo(y);
    await h.settle(rounds: 2);
    await h.shot('$name-$i');
    if (y >= position.maxScrollExtent || i >= 6) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
    i++;
  }
}

String _logo() => 'data:image/png;base64,${base64Of(samplePng)}';

const _states = [
  ('en', false, DashSize.desktop),
  ('ar', false, DashSize.phone),
];

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in [('en', false), ('ar', true)]) {
      testWidgets('appearance default, ${size.name} $lang', (tester) async {
        final h = await pumpBrand(
          tester,
          path: appearancePath,
          size: size,
          locale: lang,
          dark: dark,
        );
        await _shootPage(h, AppearancePage, 'appearance/default');
      });

      testWidgets('brand default, ${size.name} $lang', (tester) async {
        final m = setupMockServer();
        m.db['orgs'].update(SeedIds.sabahOrg, {'logo_url': _logo()});
        final h = await pumpBrand(
          tester,
          size: size,
          locale: lang,
          dark: dark,
          backend: m,
        );
        await _shootPage(h, BrandPage, 'brand/default');
      });
    }
  }

  for (final (lang, dark, size) in _states) {
    testWidgets('brand loading, ${size.name} $lang', (tester) async {
      final m = setupMockServer();
      final gate = m.server.hold('GET', orgRoute);
      final h = await pumpBrand(
        tester,
        size: size,
        locale: lang,
        dark: dark,
        backend: m,
      );
      await h.shot('brand/loading');
      gate.release();
      await h.settle();
    });

    testWidgets('brand tier off, no logo, ${size.name} $lang', (tester) async {
      final m = setupMockServer();
      m.db['orgs'].update(SeedIds.sabahOrg, {
        'custom_branding': false,
        'brand_background': null,
        'brand_foreground': null,
        'brand_accent': null,
      });
      final h = await pumpBrand(
        tester,
        size: size,
        locale: lang,
        dark: dark,
        backend: m,
      );
      await _shootPage(h, BrandPage, 'brand/tier-off');
    });

    testWidgets('brand upload refused and links invalid, ${size.name} $lang', (
      tester,
    ) async {
      final m = setupMockServer(persona: Persona.platform);
      m.server.fail(
        'PUT',
        cardImageRoute,
        MockResponse.error(413, 'The image is too large to store'),
      );
      final h = await pumpBrand(
        tester,
        size: size,
        locale: lang,
        dark: dark,
        backend: m,
        persona: Persona.platform,
        prefs: pickedSabah,
      );
      queueImage(h);
      await h.tap(inKey('brand-card-image', find.text(h.t('uploader.choose'))));
      final fields = find.descendant(
        of: inBrand(byKey('brand-links-${SeedIds.sabahOrg}')),
        matching: find.byType(EditableText),
      );
      await h.enterText(fields.at(7), 'http://sabah.coffee');
      await h.tap(byKey('brand-links-save'));
      await _shootPage(h, BrandPage, 'brand/errors');
      await h.flushTimers();
    });

    testWidgets('brand address copied, ${size.name} $lang', (tester) async {
      FakeClipboard(tester);
      final h = await pumpBrand(tester, size: size, locale: lang, dark: dark);
      await tester.ensureVisible(byKey('brand-address'));
      await h.settle();
      await h.tap(byKey('brand-copy-menu'));
      await h.shot('brand/copied');
      await h.flushTimers();
    });
  }

  testWidgets('settings picker open, phone ar', (tester) async {
    final h = await pumpBrand(
      tester,
      path: appearancePath,
      size: DashSize.phone,
      locale: 'ar',
    );
    await h.tap(byKey('settings-picker'));
    await h.shot('appearance/picker');
  });

  testWidgets('settings picker, 800 wide en', (tester) async {
    final h = await pumpBrand(tester, path: appearancePath);
    tester.view.physicalSize = const Size(800, 900) * DashSize.pixelRatio;
    await h.settle();
    await h.shot('appearance/picker-800');
  });

  testWidgets('brand, platform admin with no org, desktop en', (tester) async {
    final h = await pumpBrand(tester, persona: Persona.platform);
    await _shootPage(h, BrandPage, 'brand/no-org');
  });
}
