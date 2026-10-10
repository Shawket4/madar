// The Staff drinks screenshot matrix: the default state at every size in
// {en light, ar dark}, and every other state (loading, failed, refusal,
// read-only, inherited, pool off, field error, the picker, the revert
// confirmation) at desktop-en-light and phone-ar-light. Writes PNGs only
// with FDASH_SHOTS set.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_setup/src/staff_pool/staff_pool_settings_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Shoots the pane one screen at a time down the settings shell's scroll,
/// `<name>-1`, `<name>-2`, …
Future<void> _shootPage(DashHarness h, String name) async {
  ScrollableState? state;
  for (final e
      in find
          .ancestor(
            of: find.byType(StaffPoolSettingsPage),
            matching: find.byType(Scrollable),
          )
          .evaluate()) {
    final s = (e as StatefulElement).state as ScrollableState;
    if (s.position.axis == Axis.vertical) {
      state = s;
      break;
    }
  }
  if (state == null) return h.shot('staff-pool/$name-1');
  final position = state.position;
  var i = 1;
  var y = 0.0;
  while (true) {
    position.jumpTo(y);
    await h.settle(rounds: 2);
    await h.shot('staff-pool/$name-$i');
    if (y >= position.maxScrollExtent || i >= 4) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
    i++;
  }
}

Finder _key(String k) => find.byKey(ValueKey(k));

const _states = [
  ('en', false, DashSize.desktop),
  ('ar', false, DashSize.phone),
];

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in [('en', false), ('ar', true)]) {
      testWidgets('default, ${size.name} $lang', (tester) async {
        final h = await pumpStaffPool(
          tester,
          query: atBranch(SeedIds.heliopolis),
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
      String query = '',
      ({MockServer server, MockDb db})? backend,
      Persona persona = Persona.owner,
    }) => pumpStaffPool(
      tester,
      query: query,
      size: size,
      locale: lang,
      dark: dark,
      backend: backend,
      persona: persona,
    );

    testWidgets('loading, $tag', (tester) async {
      final m = splServer();
      final gate = m.server.hold('GET', splSettings);
      final h = await pump(tester, backend: m);
      await h.shot('staff-pool/loading');
      gate.release();
      await h.settle();
    });

    testWidgets('failed, $tag', (tester) async {
      final m = splServer();
      m.server.fail(
        'GET',
        splSettings,
        MockResponse.error(500, 'Database is resting'),
        times: null,
      );
      final h = await pump(tester, backend: m);
      await h.shot('staff-pool/failed');
    });

    testWidgets('refused, $tag', (tester) async {
      final h = await pump(tester, persona: Persona.limited);
      await h.shot('staff-pool/refused');
    });

    testWidgets('read-only, $tag', (tester) async {
      final m = splServer();
      grantOnly(m.server, const [
        'org.settings.read',
        'orders.staff_drink.record',
      ]);
      final h = await pump(tester, backend: m);
      await _shootPage(h, 'read-only');
    });

    testWidgets('inherited, $tag', (tester) async {
      final m = splServer();
      final h = await pump(tester, backend: m, query: atBranch(SeedIds.maadi));
      await _shootPage(h, 'inherited');
    });

    testWidgets('pool off with no items, field error, $tag', (tester) async {
      final m = splServer();
      savedRow(m.db, null)!['eligible_item_ids'] = <String>[];
      final h = await pump(tester, backend: m);
      await h.enterText(_key('spl-allowance'), '1.5');
      await h.tap(_key('spl-save'));
      await _shootPage(h, 'off-error');
    });

    testWidgets('picker, $tag', (tester) async {
      final h = await pump(tester, query: atBranch(SeedIds.newCairo));
      await h.tap(_key('spl-items-trigger'));
      await h.shot('staff-pool/picker');
    });

    testWidgets('revert confirmation, $tag', (tester) async {
      final h = await pump(tester, query: atBranch(SeedIds.zamalek));
      await h.tap(_key('spl-revert'));
      await h.shot('staff-pool/revert');
    });
  }
}
