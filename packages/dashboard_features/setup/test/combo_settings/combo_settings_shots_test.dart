// The Combos and deals settings screenshot matrix: the default state at
// every size in {en light, ar dark}, and every other state (loading,
// failed, refused, no org, read-only, margin error, a branch cell open) at
// desktop-en-light and phone-ar-light. Writes PNGs only with FDASH_SHOTS set.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_setup/src/combo_settings/combo_settings_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Shoots the pane one screen at a time down the settings shell's scroll,
/// `<name>-1`, `<name>-2`, …
Future<void> _shootPage(DashHarness h, String name) async {
  ScrollableState? state;
  for (final e in find
      .ancestor(
        of: find.byType(ComboSettingsPage),
        matching: find.byType(Scrollable),
      )
      .evaluate()) {
    final s = (e as StatefulElement).state as ScrollableState;
    if (s.position.axis == Axis.vertical) {
      state = s;
      break;
    }
  }
  if (state == null) return h.shot('combos/$name-1');
  final position = state.position;
  var i = 1;
  var y = 0.0;
  while (true) {
    position.jumpTo(y);
    await h.settle(rounds: 2);
    await h.shot('combos/$name-$i');
    if (y >= position.maxScrollExtent || i >= 4) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
    i++;
  }
}

const _states = [('en', false, DashSize.desktop), ('ar', false, DashSize.phone)];

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in [('en', false), ('ar', true)]) {
      testWidgets('default, ${size.name} $lang', (tester) async {
        final h = await pumpCombos(
          tester,
          size: size,
          locale: lang,
          dark: dark,
        );
        await _shootPage(h, 'default');
      });
    }
  }

  for (final (lang, dark, size) in _states) {
    final tag = '${size.name} $lang';
    Future<DashHarness> pump(
      WidgetTester tester, {
      ({MockServer server, MockDb db})? backend,
      Persona persona = Persona.owner,
      bool pickOrg = true,
    }) => pumpCombos(
      tester,
      size: size,
      locale: lang,
      dark: dark,
      backend: backend,
      persona: persona,
      pickOrg: pickOrg,
    );

    testWidgets('loading, $tag', (tester) async {
      final m = cmbServer();
      final gate = m.server.hold('GET', cmbSettings);
      final h = await pump(tester, backend: m);
      await h.shot('combos/loading');
      gate.release();
      await h.settle();
    });

    testWidgets('failed, $tag', (tester) async {
      final m = cmbServer();
      m.server.fail(
        'GET',
        cmbSettings,
        MockResponse.error(500, 'Database is resting'),
        times: null,
      );
      final h = await pump(tester, backend: m);
      await h.shot('combos/failed');
    });

    testWidgets('refused, $tag', (tester) async {
      final h = await pump(tester, persona: Persona.limited);
      await h.shot('combos/refused');
    });

    testWidgets('no org, $tag', (tester) async {
      final h = await pump(tester, persona: Persona.platform, pickOrg: false);
      await h.shot('combos/no-org');
    });

    testWidgets('read-only, $tag', (tester) async {
      final m = cmbServer();
      grantOnly(m.server, const ['org.settings.read']);
      final h = await pump(tester, backend: m);
      await _shootPage(h, 'read-only');
    });

    testWidgets('margin error, $tag', (tester) async {
      final h = await pump(tester);
      await h.enterText(byKey('cmb-margin'), '120');
      await h.tap(byKey('cmb-save'));
      await tester.ensureVisible(byKey('cmb-margin-card'));
      await h.settle(rounds: 2);
      await h.shot('combos/margin-error');
    });

    testWidgets('a branch cell open, $tag', (tester) async {
      final h = await pump(tester);
      await h.tap(cell(SeedIds.zamalek, ComboChannel.qr));
      await h.shot('combos/cell-open');
    });
  }
}
