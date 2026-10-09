// The kitchen screenshot matrix: both pages' default state at every size in
// {en light, ar dark}, and every other state (the editor, the delete
// confirm, the mode list, loading, failed, empty, no branch, Per item, an
// item's station list) at desktop-en-light and phone-ar-light. Writes PNGs
// only with FDASH_SHOTS set.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kitchen_support.dart';

/// Shoots [page] one screen at a time down the settings shell's scroll,
/// `<name>-1`, `<name>-2`, … (four at most).
Future<void> _shootPage(DashHarness h, Finder page, String name) async {
  ScrollableState? state;
  for (final e
      in find
          .ancestor(of: page, matching: find.byType(Scrollable))
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
    if (y >= position.maxScrollExtent || i >= 4) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
    i++;
  }
}

Finder _stations() => inStations(byKey('kitchen-stations-table'));

Future<void> _perItem(DashHarness h) => h.tap(
  find.descendant(
    of: inRouting(byKey('routing-tabs')),
    matching: find.text(h.t('kitchen.byItem')),
  ),
);

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in [('en', false), ('ar', true)]) {
      testWidgets('stations default, ${size.name} $lang', (tester) async {
        final h = await pumpKitchen(
          tester,
          size: size,
          locale: lang,
          dark: dark,
        );
        await _shootPage(h, _stations(), 'kitchen-stations/default');
      });
      testWidgets('routing default, ${size.name} $lang', (tester) async {
        final h = await pumpKitchen(
          tester,
          path: routingPath,
          size: size,
          locale: lang,
          dark: dark,
        );
        await _shootPage(
          h,
          inRouting(byKey('routing-categories')),
          'kitchen-routing/default',
        );
      });
    }
  }

  for (final (size, lang) in [
    (DashSize.desktop, 'en'),
    (DashSize.phone, 'ar'),
  ]) {
    final tag = '${size.name} $lang';
    Future<DashHarness> open(
      WidgetTester tester, {
      String path = stationsPath,
      String? query,
      ({MockServer server, MockDb db})? backend,
    }) => pumpKitchen(
      tester,
      path: path,
      query: query,
      size: size,
      locale: lang,
      backend: backend,
    );

    testWidgets('stations states, $tag', (tester) async {
      var h = await open(tester);
      await h.tap(inStations(byKey('kitchen-new-station')));
      await h.tap(byKey('station-brand'));
      await h.tap(
        find.descendant(
          of: find.byType(DashOptionList<String>),
          matching: find.text('Epson'),
        ),
      );
      await h.shot('kitchen-stations/new-station');
      await h.tap(byKey('station-cancel'));
      await h.tap(
        find.descendant(
          of: inStations(byKey('kitchen-stations-table')),
          matching: find.text('Bar'),
        ),
      );
      await h.shot('kitchen-stations/edit-station');
      await h.tap(byKey('station-cancel'));
      await h.tap(
        inStations(byKey('kitchen-delete-${stationId('zamalek', 'kitchen')}')),
      );
      await h.shot('kitchen-stations/delete-confirm');
      await h.tap(
        find.descendant(
          of: find.byType(DashConfirmDialog),
          matching: find.text(h.t('common.cancel')),
        ),
      );
      await h.tap(byKey('kitchen-mode'));
      await h.shot('kitchen-stations/mode-list');

      final m = setupMockServer();
      final gate = m.server.hold('GET', KitchenRoutes.stations);
      h = await open(tester, backend: m);
      await h.shot('kitchen-stations/loading');
      gate.release();
      await h.settle();

      final f = setupMockServer();
      f.server.fail(
        'GET',
        KitchenRoutes.stations,
        MockResponse.error(500, 'Database unavailable'),
      );
      h = await open(tester, backend: f);
      await h.shot('kitchen-stations/failed');

      h = await open(tester, query: maadi);
      await h.shot('kitchen-stations/empty');

      h = await open(tester, query: '');
      await h.shot('kitchen-stations/no-branch');
    });

    testWidgets('routing states, $tag', (tester) async {
      var h = await open(tester, path: routingPath);
      await _perItem(h);
      await h.shot('kitchen-routing/per-item');
      await h.tap(
        inRouting(
          find.descendant(
            of: byKey('routing-item-select-${mockUuid('menu-item:espresso')}'),
            matching: find.byType(DashSelect<String>),
          ),
        ),
      );
      await h.shot('kitchen-routing/item-stations');

      final m = setupMockServer();
      final gate = m.server.hold('GET', KitchenRoutes.routes);
      h = await open(tester, path: routingPath, backend: m);
      await h.shot('kitchen-routing/loading');
      gate.release();
      await h.settle();

      final f = setupMockServer();
      f.server.fail(
        'GET',
        KitchenRoutes.routes,
        MockResponse.error(500, 'Database unavailable'),
      );
      h = await open(tester, path: routingPath, backend: f);
      await h.shot('kitchen-routing/failed');

      h = await open(tester, path: routingPath, query: maadi);
      await h.shot('kitchen-routing/no-stations');

      h = await open(tester, path: routingPath, query: '');
      await h.shot('kitchen-routing/no-branch');

      final e = setupMockServer();
      h = await open(tester, path: routingPath, backend: e);
      await _perItem(h);
      await h.enterText(inRouting(byKey('routing-search')), 'pizza');
      await h.flushTimers();
      await h.shot('kitchen-routing/no-items');
    });
  }
}
