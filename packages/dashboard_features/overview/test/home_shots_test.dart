// The home's screenshot matrix: the default state at {phone, tablet,
// desktop} x {en light, ar dark}, scrolled through the whole page; and its
// other states (a branch picked, loading, failed, no shop, the figure
// popovers) at desktop-en-light and phone-ar-light. Written only with
// FDASH_SHOTS set; the pages still render (and must not overflow) without.
import 'dart:convert';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_overview/src/home/home_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _modes = [('en', false), ('ar', true)];

/// Shoots the page top to bottom: `<name>-1`, `<name>-2`, …
Future<void> shootPage(DashHarness h, String name) async {
  final scroll = find
      .descendant(of: find.byType(HomePage), matching: find.byType(Scrollable))
      .first;
  final position = h.tester.state<ScrollableState>(scroll).position;
  var i = 1;
  var y = 0.0;
  while (true) {
    position.jumpTo(y);
    await h.settle(rounds: 2);
    await h.shot('home/$name-$i');
    if (y >= position.maxScrollExtent) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
    i++;
  }
}

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in _modes) {
      final tag = '${size.name} $lang ${dark ? 'dark' : 'light'}';
      testWidgets('default, $tag', (tester) async {
        final h = await pumpHome(tester, size: size, locale: lang, dark: dark);
        await shootPage(h, 'default');
      });
    }
  }

  for (final (size, lang) in [(DashSize.desktop, 'en'), (DashSize.phone, 'ar')]) {
    final tag = '${size.name} $lang';
    testWidgets('a branch picked, $tag', (tester) async {
      final h = await pumpHome(
        tester,
        size: size,
        locale: lang,
        path: '/?branchId=${SeedIds.maadi}&preset=today',
      );
      await shootPage(h, 'branch-today');
    });

    testWidgets('loading, $tag', (tester) async {
      final s = homeServer();
      final gates = [
        for (final t in [
          '/reports/orgs/{orgId}/comparison',
          '/reports/branches/{branchId}/sales/timeseries',
          '/reports/branches/{branchId}/delivery-sales',
          '/insights/branches/{branchId}/margin-watch',
        ])
          s.server.hold('GET', t),
      ];
      final h = await pumpHome(
        tester,
        server: s.server,
        db: s.db,
        size: size,
        locale: lang,
      );
      await shootPage(h, 'loading');
      for (final g in gates) {
        g.release();
      }
      await h.settle();
    });

    testWidgets('failed, $tag', (tester) async {
      final s = homeServer();
      for (final t in [
        '/reports/orgs/{orgId}/comparison',
        '/reports/branches/{branchId}/sales/timeseries',
        '/reports/branches/{branchId}/delivery-sales',
        '/insights/branches/{branchId}/margin-watch',
      ]) {
        s.server.fail('GET', t, MockResponse.error(500, 'boom'), times: null);
      }
      final h = await pumpHome(
        tester,
        server: s.server,
        db: s.db,
        size: size,
        locale: lang,
      );
      await shootPage(h, 'failed');
    });

    testWidgets('no shop picked, $tag', (tester) async {
      final h = await pumpHome(
        tester,
        persona: Persona.platform,
        size: size,
        locale: lang,
      );
      await shootPage(h, 'no-shop');
    });

    testWidgets('a quiet day, $tag', (tester) async {
      final s = homeServer();
      s.db['orders'].clear();
      final h = await pumpHome(
        tester,
        server: s.server,
        db: s.db,
        size: size,
        locale: lang,
        prefs: {ScopePrefKeys.preset: 'today'},
      );
      await shootPage(h, 'empty');
    });

    testWidgets('platform admin in a shop, $tag', (tester) async {
      final h = await pumpHome(
        tester,
        persona: Persona.platform,
        size: size,
        locale: lang,
        prefs: {
          ScopePrefKeys.org: jsonEncode({'id': SeedIds.sabahOrg}),
        },
      );
      await h.shot('home/platform-shop');
    });
  }
}
