// The Delivery settings and zones screenshot matrix: each page's default
// state at every size in {en light, ar dark}, and every other state (no
// branch, loading, failed, refusal, every channel on, field errors; empty
// zones, the editor, the delete confirmation) at desktop-en-light and
// phone-ar-light. Writes PNGs only with FDASH_SHOTS set.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_setup/src/delivery/delivery_settings_page.dart';
import 'package:dashboard_setup/src/delivery/delivery_zones_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';
import 'support.dart';

final String _helio = atBranch(SeedIds.heliopolis);
final String _newCairo = atBranch(SeedIds.newCairo);
final String _zamalek = atBranch(SeedIds.zamalek);

/// Shoots [page] one screen at a time down the settings shell's scroll,
/// `<name>-1`, `<name>-2`, …
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
    if (y >= position.maxScrollExtent || i >= 5) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
    i++;
  }
}

const _states = [
  ('en', false, DashSize.desktop),
  ('ar', false, DashSize.phone),
];

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in [('en', false), ('ar', true)]) {
      testWidgets('settings default, ${size.name} $lang', (tester) async {
        final h = await pumpDelivery(
          tester,
          query: _newCairo,
          size: size,
          locale: lang,
          dark: dark,
        );
        await _shootPage(h, DeliverySettingsPage, 'delivery/default');
      });
      testWidgets('zones default, ${size.name} $lang', (tester) async {
        final h = await pumpDelivery(
          tester,
          path: zonesPath,
          query: _helio,
          size: size,
          locale: lang,
          dark: dark,
        );
        await _shootPage(h, DeliveryZonesPage, 'delivery-zones/default');
      });
    }
  }

  for (final (lang, dark, size) in _states) {
    final tag = '${size.name} $lang';

    testWidgets('settings no branch, $tag', (tester) async {
      final h = await pumpDelivery(
        tester,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.shot('delivery/no-branch');
    });

    testWidgets('settings loading, $tag', (tester) async {
      final m = setupMockServer();
      final gate = m.server.hold('GET', DeliveryRoutes.settings);
      final h = await pumpDelivery(
        tester,
        query: _helio,
        size: size,
        locale: lang,
        dark: dark,
        backend: m,
      );
      await h.shot('delivery/loading');
      gate.release();
      await h.settle();
    });

    testWidgets('settings failed, $tag', (tester) async {
      final m = setupMockServer();
      m.server.fail(
        'GET',
        DeliveryRoutes.settings,
        MockResponse.error(500, 'Database unavailable'),
      );
      final h = await pumpDelivery(
        tester,
        query: _helio,
        size: size,
        locale: lang,
        dark: dark,
        backend: m,
      );
      await h.shot('delivery/failed');
    });

    testWidgets('settings refused, $tag', (tester) async {
      final h = await pumpDelivery(
        tester,
        query: atBranch(SeedIds.maadi),
        persona: Persona.limited,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.shot('delivery/refused');
    });

    testWidgets('settings every channel on, with errors, $tag', (tester) async {
      final h = await pumpDelivery(
        tester,
        query: _zamalek,
        size: size,
        locale: lang,
        dark: dark,
      );
      for (final k in ['dlv-in-mall', 'dlv-outside', 'dlv-umbrella']) {
        final sw = inKey(k, find.byType(DashSwitch));
        await tester.ensureVisible(sw);
        await h.tap(sw);
      }
      await typeIn(h, 'dlv-umbrella-fee', '-5');
      await typeIn(h, 'dlv-distance', '0');
      await tester.ensureVisible(byKey('dlv-save'));
      await h.tap(byKey('dlv-save'));
      await _shootPage(h, DeliverySettingsPage, 'delivery/all-on');
    });

    testWidgets('settings discount list, $tag', (tester) async {
      final h = await pumpDelivery(
        tester,
        query: _helio,
        size: size,
        locale: lang,
        dark: dark,
      );
      await tester.ensureVisible(byKey('dlv-outside-discount'));
      await h.tap(
        inKey('dlv-outside-discount', find.byType(DashSelectTrigger)),
      );
      await h.shot('delivery/discounts');
    });

    testWidgets('zones empty, $tag', (tester) async {
      final h = await pumpDelivery(
        tester,
        path: zonesPath,
        query: _zamalek,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.shot('delivery-zones/empty');
    });

    testWidgets('zones no branch, $tag', (tester) async {
      final h = await pumpDelivery(
        tester,
        path: zonesPath,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.shot('delivery-zones/no-branch');
    });

    testWidgets('zones loading, $tag', (tester) async {
      final m = setupMockServer();
      final gate = m.server.hold('GET', DeliveryRoutes.zones);
      final h = await pumpDelivery(
        tester,
        path: zonesPath,
        query: _helio,
        size: size,
        locale: lang,
        dark: dark,
        backend: m,
      );
      await h.shot('delivery-zones/loading');
      gate.release();
      await h.settle();
    });

    testWidgets('zones failed, $tag', (tester) async {
      final m = setupMockServer();
      m.server.fail(
        'GET',
        DeliveryRoutes.zones,
        MockResponse.error(500, 'Database unavailable'),
      );
      final h = await pumpDelivery(
        tester,
        path: zonesPath,
        query: _helio,
        size: size,
        locale: lang,
        dark: dark,
        backend: m,
      );
      await h.shot('delivery-zones/failed');
    });

    testWidgets('zones new-zone dialog with errors, $tag', (tester) async {
      final h = await pumpDelivery(
        tester,
        path: zonesPath,
        query: _helio,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.tap(inZones(byKey('dzn-new')));
      await h.shot('delivery-zones/new');
      await typeIn(h, 'dzn-km', '0');
      await typeIn(h, 'dzn-fee', '-1');
      await h.tap(inDialog(byKey('dzn-save')));
      await h.shot('delivery-zones/new-errors');
    });

    testWidgets('zones edit dialog, $tag', (tester) async {
      final h = await pumpDelivery(
        tester,
        path: zonesPath,
        query: _helio,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.tap(inZones(find.text('Korba & Merghany')));
      await h.shot('delivery-zones/edit');
    });

    testWidgets('zones delete confirmation, $tag', (tester) async {
      final h = await pumpDelivery(
        tester,
        path: zonesPath,
        query: _helio,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.tap(
        inZones(byKey('dzn-delete-${DeliverySeed.zoneId('heliopolis', 3)}')),
      );
      await h.shot('delivery-zones/delete');
    });
  }
}
