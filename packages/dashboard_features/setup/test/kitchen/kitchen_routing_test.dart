// `/settings/kitchen-routing`, driven through the real app shell
// (SET-KRT-001..021), with the intent warming of its tab and pager.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_setup/src/kitchen/kitchen_routing_page.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kitchen_support.dart';

String _cat(String key) => MockSeed.categoryId(key);
String _item(String key) => MockSeed.menuItemId(key);

Finder _catSelect(String key) => inRouting(
  find.descendant(
    of: byKey('routing-category-select-${_cat(key)}'),
    matching: find.byType(DashSelect<String>),
  ),
);

Finder _itemSelect(String key) => inRouting(
  find.descendant(
    of: byKey('routing-item-select-${_item(key)}'),
    matching: find.byType(DashSelect<String>),
  ),
);

DashSelect<String> _select(WidgetTester tester, Finder f) =>
    tester.widget<DashSelect<String>>(f);

/// The label the select shows (its option, else its placeholder).
String _shown(WidgetTester tester, Finder f) {
  final s = _select(tester, f);
  return s.options.where((o) => o.value == s.value).firstOrNull?.label ??
      s.placeholder!;
}

/// Opens [select] and picks [option] from its list.
Future<void> _pick(DashHarness h, Finder select, String option) async {
  await h.tap(select);
  await h.tap(
    find.descendant(
      of: find.byType(DashOptionList<String>),
      matching: find.text(option),
    ),
  );
}

Future<void> _perItem(DashHarness h) => h.tap(
  find.descendant(
    of: inRouting(byKey('routing-tabs')),
    matching: find.text(h.t('kitchen.byItem')),
  ),
);

Map<String, Object?> _body(MockCall c) => c.body! as Map<String, Object?>;

List<MockCall> _catalog(DashHarness h) =>
    h.server.callsTo(KitchenRoutes.catalog, method: 'GET');

/// Adds [n] items so the catalogue runs past one page of 50.
void _moreItems(MockDb db, int n) {
  final template = db['menu_items'].rows.first;
  for (var i = 1; i <= n; i++) {
    db['menu_items'].insert({
      ...template,
      'id': mockUuid('menu-item:extra-$i'),
      'name': 'Zaatar Manousheh $i',
      'name_translations': {
        'en': 'Zaatar Manousheh $i',
        'ar': 'منقوشة زعتر $i',
      },
      'category_id': _cat('breakfast'),
    });
  }
}

void main() {
  group('header and states', () {
    testWidgets('SET-KRT-001 title and subtitle', (tester) async {
      final h = await pumpKitchen(tester, path: routingPath);
      expect(inRouting(find.text('Order routing')), findsOneWidget);
      expect(
        inRouting(find.text(h.t('kitchen.routingSubtitle'))),
        findsOneWidget,
      );
    });

    testWidgets('SET-KRT-002 "All branches": "Select a branch…", nothing '
        'read, no tabs or export', (tester) async {
      final h = await pumpKitchen(tester, path: routingPath, query: '');
      expect(
        inRouting(
          find.text('Select a branch in the top bar to manage its kitchen'),
        ),
        findsOneWidget,
      );
      expect(inRouting(byKey('routing-tabs')), findsNothing);
      expect(inRouting(byKey('routing-export')), findsNothing);
      for (final r in [
        KitchenRoutes.stations,
        KitchenRoutes.routes,
        KitchenRoutes.categories,
      ]) {
        expect(h.server.callsTo(r), isEmpty, reason: r);
      }
    });

    testWidgets('SET-KRT-003 loading the stations or the routes: six '
        'skeleton rows', (tester) async {
      for (final route in [KitchenRoutes.stations, KitchenRoutes.routes]) {
        final m = setupMockServer();
        final gate = m.server.hold('GET', route);
        final h = await pumpKitchen(tester, path: routingPath, backend: m);
        final skeleton = inRouting(byKey('routing-skeleton'));
        expect(skeleton, findsOneWidget, reason: route);
        expect(
          find.descendant(of: skeleton, matching: find.byType(DashSkeleton)),
          findsNWidgets(12),
        );
        expect(inRouting(byKey('routing-no-stations')), findsNothing);
        gate.release();
        await h.settle();
        expect(inRouting(byKey('routing-categories')), findsOneWidget);
      }
    });

    for (final route in [
      KitchenRoutes.stations,
      KitchenRoutes.categories,
      KitchenRoutes.routes,
    ]) {
      testWidgets('SET-KRT-004 $route fails: "Couldn\'t load kitchen '
          'routing", its words, Retry reads all three again', (tester) async {
        final m = setupMockServer();
        final boom = MockResponse.error(500, 'Database unavailable');
        m.server.fail('GET', route, boom);
        final h = await pumpKitchen(tester, path: routingPath, backend: m);
        final err = inRouting(byKey('routing-error'));
        expect(
          find.descendant(
            of: err,
            matching: find.text("Couldn't load kitchen routing"),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: err, matching: find.text(h.refusalWords(boom))),
          findsOneWidget,
        );
        await h.tap(find.descendant(of: err, matching: find.text('Retry')));
        for (final r in [
          KitchenRoutes.stations,
          KitchenRoutes.categories,
          KitchenRoutes.routes,
        ]) {
          expect(h.server.callsTo(r), hasLength(2), reason: r);
        }
        expect(inRouting(byKey('routing-categories')), findsOneWidget);
      });
    }

    testWidgets('SET-KRT-005 no station at the branch: "Create a station '
        'first", no tabs, no export', (tester) async {
      final h = await pumpKitchen(tester, path: routingPath, query: maadi);
      final empty = inRouting(byKey('routing-no-stations'));
      expect(
        find.descendant(
          of: empty,
          matching: find.text('Create a station first'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: empty,
          matching: find.text(h.t('kitchen.noStationsForRoutingHint')),
        ),
        findsOneWidget,
      );
      expect(inRouting(byKey('routing-tabs')), findsNothing);
      expect(inRouting(byKey('routing-export')), findsNothing);
    });

    testWidgets('SET-KRT-005 only inactive stations count as none', (
      tester,
    ) async {
      final m = setupMockServer();
      for (final s in m.db[KitchenSeed.stationsTable].rows) {
        s['is_active'] = false;
      }
      await pumpKitchen(tester, path: routingPath, backend: m);
      expect(inRouting(byKey('routing-no-stations')), findsOneWidget);
    });

    testWidgets('SET-KRT-006 with stations: By category (default) / Per item '
        'and Export Excel', (tester) async {
      await pumpKitchen(tester, path: routingPath);
      final seg = tester.widget<DashSegmentedControl<KitchenRoutingTab>>(
        inRouting(find.byType(DashSegmentedControl<KitchenRoutingTab>)),
      );
      expect(seg.value, KitchenRoutingTab.categories);
      expect(
        [for (final o in seg.options) o.label],
        ['By category', 'Per item'],
      );
      final export = tester.widget<DashButton>(
        find.descendant(
          of: inRouting(byKey('routing-export')),
          matching: find.byType(DashButton),
        ),
      );
      expect(export.label, 'Export Excel');
      expect(inRouting(byKey('routing-search')), findsNothing);
    });
  });

  group('by category', () {
    testWidgets('SET-KRT-007 a row per category with its station; the '
        'choices are "Default / unassigned" and the active stations', (
      tester,
    ) async {
      final h = await pumpKitchen(tester, path: routingPath);
      final rows = tester
          .widgetList<DashListRow>(
            find.descendant(
              of: inRouting(byKey('routing-categories')),
              matching: find.byType(DashListRow),
            ),
          )
          .map((r) => r.title)
          .toList();
      expect(rows, [
        'Hot Coffee',
        'Iced Coffee',
        'Tea & More',
        'Fresh Juice',
        'Bakery',
        'Desserts',
        'Breakfast',
      ]);
      expect(_shown(tester, _catSelect('hot')), 'Bar');
      expect(_shown(tester, _catSelect('breakfast')), 'Kitchen');
      expect(_shown(tester, _catSelect('dessert')), 'Default / unassigned');
      final s = _select(tester, _catSelect('hot'));
      expect(
        [for (final o in s.options) o.label],
        ['Default / unassigned', 'Bar', 'Kitchen'],
      );
      expect(s.width, 208);
      expect(
        h.server.callsTo(KitchenRoutes.categories).single.query['org_id'],
        [SeedIds.sabahOrg],
      );
      expect(_catalog(h), isEmpty, reason: 'items only on their tab');
    });

    testWidgets('SET-KRT-007 Arabic names; 160 wide under 640', (tester) async {
      await pumpKitchen(
        tester,
        path: routingPath,
        size: DashSize.phone,
        locale: 'ar',
      );
      expect(inRouting(find.text('قهوة ساخنة')), findsOneWidget);
      expect(_select(tester, _catSelect('hot')).width, 160);
    });

    testWidgets('SET-KRT-007 categories loading: skeleton rows; none: "No '
        'categories to route yet."', (tester) async {
      final m = setupMockServer();
      final gate = m.server.hold('GET', KitchenRoutes.categories);
      final h = await pumpKitchen(tester, path: routingPath, backend: m);
      expect(inRouting(byKey('routing-skeleton')), findsOneWidget);
      expect(inRouting(byKey('routing-tabs')), findsOneWidget);
      gate.release();
      await h.settle();
      expect(inRouting(byKey('routing-categories')), findsOneWidget);

      final e = setupMockServer();
      e.db['categories'].clear();
      await pumpKitchen(tester, path: routingPath, backend: e);
      expect(
        find.descendant(
          of: inRouting(byKey('routing-no-categories')),
          matching: find.text('No categories to route yet.'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('SET-KRT-008 choosing a station saves at once, no toast, '
        'routes read again', (tester) async {
      final h = await pumpKitchen(tester, path: routingPath);
      final seen = watchInvalidations(h);
      await _pick(h, _catSelect('dessert'), 'Kitchen');
      final put = h.server.callsTo(KitchenRoutes.categoryRoute, method: 'PUT');
      expect(_body(put.single), {
        'branch_id': SeedIds.zamalek,
        'category_id': _cat('dessert'),
        'station_id': stationId('zamalek', 'kitchen'),
      });
      expect(seen, [
        ['/kitchen/routes', '/kitchen/routing-mode'],
      ]);
      expect(h.server.callsTo(KitchenRoutes.routes), hasLength(2));
      expect(_shown(tester, _catSelect('dessert')), 'Kitchen');
    });

    testWidgets('SET-KRT-009 "Default / unassigned" removes the route', (
      tester,
    ) async {
      final h = await pumpKitchen(tester, path: routingPath);
      await _pick(h, _catSelect('hot'), 'Default / unassigned');
      final del = h.server.callsTo(
        KitchenRoutes.categoryRoute,
        method: 'DELETE',
      );
      expect(del.single.query, {
        'branch_id': [SeedIds.zamalek],
        'category_id': [_cat('hot')],
      });
      expect(_shown(tester, _catSelect('hot')), 'Default / unassigned');
      expect(
        h.db![KitchenSeed.categoryRoutesTable].rows.where(
          (r) =>
              r['branch_id'] == SeedIds.zamalek &&
              r['category_id'] == _cat('hot'),
        ),
        isEmpty,
      );
    });

    testWidgets('SET-KRT-015 a refused write toasts the server\'s words', (
      tester,
    ) async {
      final m = setupMockServer();
      final refusal = MockResponse.badRequest(KitchenRefusals.otherBranch);
      m.server.fail('PUT', KitchenRoutes.categoryRoute, refusal);
      final h = await pumpKitchen(tester, path: routingPath, backend: m);
      await _pick(h, _catSelect('dessert'), 'Bar');
      await h.expectToast(h.refusalWords(refusal));
      expect(h.server.callsTo(KitchenRoutes.routes), hasLength(1));
      expect(_shown(tester, _catSelect('dessert')), 'Default / unassigned');
    });

    testWidgets('SET-KRT-019 a category routed to an inactive station shows '
        'an empty select', (tester) async {
      final h = await pumpKitchen(tester, path: routingPath);
      final s = _select(tester, _catSelect('bakery'));
      expect(s.value, isNull);
      expect(s.placeholder, '');
      expect(s.options.map((o) => o.label), isNot(contains('Pastry')));
      // Choosing "unassigned" from it removes the stale route.
      await _pick(h, _catSelect('bakery'), 'Default / unassigned');
      expect(
        h.server.callsTo(KitchenRoutes.categoryRoute, method: 'DELETE'),
        hasLength(1),
      );
    });
  });

  group('per item', () {
    testWidgets('SET-KRT-010 the search box (256 wide) and the note', (
      tester,
    ) async {
      final h = await pumpKitchen(tester, path: routingPath);
      await _perItem(h);
      final search = tester.widget<DashSearchInput>(
        inRouting(byKey('routing-search')),
      );
      expect(search.placeholder, 'Search');
      expect(search.width, 256);
      expect(inRouting(find.text(h.t('kitchen.byItemHint'))), findsOneWidget);
    });

    testWidgets('SET-KRT-011 read only on this tab: 50 a page, then the '
        'search 300 ms after typing', (tester) async {
      final h = await pumpKitchen(tester, path: routingPath);
      expect(_catalog(h), isEmpty);
      await _perItem(h);
      expect(_catalog(h).single.query, {
        'org_id': [SeedIds.sabahOrg],
        'page': ['1'],
        'per_page': ['50'],
      });
      expect(
        find.descendant(
          of: inRouting(byKey('routing-items')),
          matching: find.byType(DashListRow),
        ),
        findsNWidgets(40),
      );
      await h.enterText(inRouting(byKey('routing-search')), 'croiss');
      expect(_catalog(h), hasLength(1), reason: 'debounced');
      await tester.pump(const Duration(milliseconds: 300));
      await h.settle();
      expect(_catalog(h).last.query['search'], ['croiss']);
      final rows = tester
          .widgetList<DashListRow>(
            find.descendant(
              of: inRouting(byKey('routing-items')),
              matching: find.byType(DashListRow),
            ),
          )
          .map((r) => r.title);
      expect(rows, contains('Butter Croissant'));
      expect(rows.every((n) => n.toLowerCase().contains('croiss')), isTrue);
    });

    testWidgets('SET-KRT-011 the last page stays on screen while the next '
        'one loads', (tester) async {
      final m = setupMockServer();
      _moreItems(m.db, 15);
      final h = await pumpKitchen(tester, path: routingPath, backend: m);
      await _perItem(h);
      final gate = m.server.hold('GET', KitchenRoutes.catalog);
      await h.tap(inRouting(find.bySemanticsLabel('Next')));
      expect(inRouting(byKey('routing-items')), findsOneWidget);
      expect(inRouting(byKey('routing-skeleton')), findsNothing);
      expect(inRouting(find.text('Page 2 of 2')), findsOneWidget);
      gate.release();
      await h.settle();
      expect(
        find.descendant(
          of: inRouting(byKey('routing-items')),
          matching: find.byType(DashListRow),
        ),
        findsNWidgets(5),
      );
    });

    testWidgets('SET-KRT-012 item rows: Overridden / Inherits <station> / No '
        'category station, and the override select', (tester) async {
      final h = await pumpKitchen(tester, path: routingPath);
      await _perItem(h);
      String meta(String key) => tester
          .widget<DashListRow>(inRouting(byKey('routing-item-${_item(key)}')))
          .meta!;
      expect(meta('croissant'), 'Overridden');
      expect(meta('halloumi'), 'Inherits Kitchen');
      expect(meta('espresso'), 'Inherits Bar');
      expect(meta('cheesecake'), 'No category station');
      expect(_shown(tester, _itemSelect('croissant')), 'Kitchen');
      final s = _select(tester, _itemSelect('espresso'));
      expect(_shown(tester, _itemSelect('espresso')), 'Inherit (category)');
      expect(
        [for (final o in s.options) o.label],
        ['Inherit (category)', 'Bar', 'Kitchen'],
      );
      expect(h.server.callsTo(KitchenRoutes.routes), hasLength(1));
    });

    testWidgets('SET-KRT-013 choosing a station for an item saves at once', (
      tester,
    ) async {
      final h = await pumpKitchen(tester, path: routingPath);
      await _perItem(h);
      await _pick(h, _itemSelect('espresso'), 'Kitchen');
      expect(
        _body(h.server.callsTo(KitchenRoutes.itemRoute, method: 'PUT').single),
        {
          'branch_id': SeedIds.zamalek,
          'menu_item_id': _item('espresso'),
          'station_id': stationId('zamalek', 'kitchen'),
        },
      );
      expect(h.server.callsTo(KitchenRoutes.routes), hasLength(2));
      expect(
        tester
            .widget<DashListRow>(
              inRouting(byKey('routing-item-${_item('espresso')}')),
            )
            .meta,
        'Overridden',
      );
    });

    testWidgets('SET-KRT-014 "Inherit (category)" removes the override', (
      tester,
    ) async {
      final h = await pumpKitchen(tester, path: routingPath);
      await _perItem(h);
      await _pick(h, _itemSelect('croissant'), 'Inherit (category)');
      expect(
        h.server
            .callsTo(KitchenRoutes.itemRoute, method: 'DELETE')
            .single
            .query,
        {
          'branch_id': [SeedIds.zamalek],
          'menu_item_id': [_item('croissant')],
        },
      );
      expect(
        tester
            .widget<DashListRow>(
              inRouting(byKey('routing-item-${_item('croissant')}')),
            )
            .meta,
        'No category station',
      );
    });

    testWidgets('SET-KRT-015 a refused item write toasts', (tester) async {
      final m = setupMockServer();
      final refusal = MockResponse.denied('kitchen.stations.edit');
      m.server.fail('DELETE', KitchenRoutes.itemRoute, refusal);
      final h = await pumpKitchen(tester, path: routingPath, backend: m);
      await _perItem(h);
      await _pick(h, _itemSelect('croissant'), 'Inherit (category)');
      await h.expectToast(h.refusalWords(refusal));
      expect(_shown(tester, _itemSelect('croissant')), 'Kitchen');
    });

    testWidgets('SET-KRT-016 catalogue: skeleton while loading, "Couldn\'t '
        'load menu items" + Retry, "No items match"', (tester) async {
      final m = setupMockServer();
      final gate = m.server.hold('GET', KitchenRoutes.catalog);
      final h = await pumpKitchen(tester, path: routingPath, backend: m);
      await _perItem(h);
      expect(inRouting(byKey('routing-skeleton')), findsOneWidget);
      expect(inRouting(byKey('routing-no-items')), findsNothing);
      gate.release();
      await h.settle();
      expect(inRouting(byKey('routing-items')), findsOneWidget);

      final f = setupMockServer();
      final boom = MockResponse.error(500, 'Database unavailable');
      f.server.fail('GET', KitchenRoutes.catalog, boom, times: null);
      final h2 = await pumpKitchen(tester, path: routingPath, backend: f);
      await _perItem(h2);
      final err = inRouting(byKey('routing-items-error'));
      expect(
        find.descendant(
          of: err,
          matching: find.text("Couldn't load menu items"),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: err, matching: find.text(h2.refusalWords(boom))),
        findsOneWidget,
      );
      final routes = h2.server.callsTo(KitchenRoutes.routes).length;
      final reads = _catalog(h2).length;
      f.server.clearFailures();
      await h2.tap(find.descendant(of: err, matching: find.text('Retry')));
      expect(_catalog(h2), hasLength(reads + 1));
      expect(h2.server.callsTo(KitchenRoutes.routes), hasLength(routes));
      expect(inRouting(byKey('routing-items')), findsOneWidget);

      await h2.enterText(inRouting(byKey('routing-search')), 'pizza');
      await h2.flushTimers();
      expect(
        find.descendant(
          of: inRouting(byKey('routing-no-items')),
          matching: find.text('No items match'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('SET-KRT-017 past 50 items: "Page 1 of 2", Previous / Next '
        'disabled at the ends; a new search goes back to page 1', (
      tester,
    ) async {
      final m = setupMockServer();
      _moreItems(m.db, 15);
      final h = await pumpKitchen(tester, path: routingPath, backend: m);
      await _perItem(h);
      final pager = inRouting(byKey('routing-pager'));
      expect(
        find.descendant(of: pager, matching: find.text('Page 1 of 2')),
        findsOneWidget,
      );
      DashIconButton btn(String label) => tester.widget<DashIconButton>(
        find.descendant(
          of: pager,
          matching: find.byWidgetPredicate(
            (w) => w is DashIconButton && w.semanticLabel == label,
          ),
        ),
      );
      expect(btn('Previous').onPressed, isNull);
      await h.tap(
        find.descendant(of: pager, matching: find.bySemanticsLabel('Next')),
      );
      expect(_catalog(h).last.query['page'], ['2']);
      expect(btn('Next').onPressed, isNull);
      expect(btn('Previous').onPressed, isNotNull);
      await h.enterText(inRouting(byKey('routing-search')), 'Zaatar');
      await h.flushTimers();
      expect(_catalog(h).last.query['page'], ['1']);
      expect(_catalog(h).last.query['search'], ['Zaatar']);
      expect(inRouting(byKey('routing-pager')), findsNothing);
    });

    testWidgets('SET-KRT-017 a new branch goes back to page 1', (tester) async {
      final m = setupMockServer();
      _moreItems(m.db, 15);
      final h = await pumpKitchen(tester, path: routingPath, backend: m);
      await _perItem(h);
      await h.tap(inRouting(find.bySemanticsLabel('Next')));
      expect(_catalog(h).last.query['page'], ['2']);
      await h.go('$routingPath$heliopolis');
      expect(
        find.descendant(
          of: inRouting(byKey('routing-pager')),
          matching: find.text('Page 1 of 2'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('SET-KRT-019 an override to an inactive station reads '
        '"Overridden" with an empty select; an item whose category routes '
        'to one reads "No category station"', (tester) async {
      final h = await pumpKitchen(tester, path: routingPath);
      await _perItem(h);
      expect(
        tester
            .widget<DashListRow>(
              inRouting(byKey('routing-item-${_item('cookie')}')),
            )
            .meta,
        'Overridden',
      );
      expect(_select(tester, _itemSelect('cookie')).value, isNull);
      expect(_select(tester, _itemSelect('cookie')).placeholder, '');
      expect(
        tester
            .widget<DashListRow>(
              inRouting(byKey('routing-item-${_item('almond_croissant')}')),
            )
            .meta,
        'No category station',
      );
      expect(h.server.calls.where((c) => c.method != 'GET'), isEmpty);
    });

    testWidgets('SET-KRT-021 the search and the page survive a trip to By '
        'category', (tester) async {
      final m = setupMockServer();
      _moreItems(m.db, 15);
      final h = await pumpKitchen(tester, path: routingPath, backend: m);
      await _perItem(h);
      await h.tap(inRouting(find.bySemanticsLabel('Next')));
      await h.tap(
        find.descendant(
          of: inRouting(byKey('routing-tabs')),
          matching: find.text('By category'),
        ),
      );
      expect(inRouting(byKey('routing-categories')), findsOneWidget);
      await _perItem(h);
      expect(
        find.descendant(
          of: inRouting(byKey('routing-pager')),
          matching: find.text('Page 2 of 2'),
        ),
        findsOneWidget,
      );
    });
  });

  group('export', () {
    testWidgets('SET-KRT-018 two sheets; the item sheet walks every page '
        'under the search, marked as an export', (tester) async {
      final m = setupMockServer();
      _moreItems(m.db, 15);
      final h = await pumpKitchen(tester, path: routingPath, backend: m);
      final before = _catalog(h).length;
      await h.tap(inRouting(byKey('routing-export')));
      await h.expectToast('Exported 62 rows');
      final walk = _catalog(h).skip(before).toList();
      // 55 items arrive in one page of 500: the walk stops at the total.
      expect(walk, hasLength(1));
      expect(walk.first.query, {
        'org_id': [SeedIds.sabahOrg],
        'page': ['1'],
        'per_page': ['500'],
      });
      expect(walk.first.headers['X-Madar-Export'], '1');
      final file = h.files.saved.single.filename;
      expect(
        RegExp(r'^Madar-Order-Routing-\d{4}-\d{2}-\d{2}\.xlsx$').hasMatch(file),
        isTrue,
        reason: file,
      );
      final book = h.exports.built.single;
      final cats = book.sheets[0];
      expect(cats.name, 'By category');
      expect(cats.title, 'Order routing');
      expect(cats.subtitle, startsWith('By category'));
      expect([for (final c in cats.columns) c.header], ['Category', 'Station']);
      expect(cats.rows, [
        ['Hot Coffee', 'Bar'],
        ['Iced Coffee', 'Bar'],
        ['Tea & More', 'Bar'],
        ['Fresh Juice', 'Bar'],
        ['Bakery', 'Default / unassigned'],
        ['Desserts', 'Default / unassigned'],
        ['Breakfast', 'Kitchen'],
      ]);
      final items = book.sheets[1];
      expect(items.name, 'Per item');
      expect(items.title, 'Order routing');
      expect(items.subtitle, startsWith('Per item'));
      expect(
        [for (final c in items.columns) c.header],
        ['Item', 'Inherited station', 'Override', 'Routed to'],
      );
      expect(items.rows, hasLength(55));
      List<Object?> row(String name) =>
          items.rows.firstWhere((r) => r.first == name);
      expect(row('Butter Croissant'), [
        'Butter Croissant',
        '—',
        'Kitchen',
        'Kitchen',
      ]);
      expect(row('Chocolate Chip Cookie'), [
        'Chocolate Chip Cookie',
        '—',
        '—',
        'Default / unassigned',
      ]);
      expect(row('Halloumi Sandwich'), [
        'Halloumi Sandwich',
        'Kitchen',
        '—',
        'Kitchen',
      ]);
    });

    testWidgets('SET-KRT-018 the item sheet follows the search; Arabic '
        'names in Arabic', (tester) async {
      final h = await pumpKitchen(tester, path: routingPath, locale: 'ar');
      await _perItem(h);
      await h.enterText(inRouting(byKey('routing-search')), 'Croissant');
      await h.flushTimers();
      await h.tap(inRouting(byKey('routing-export')));
      await h.flushTimers();
      final walk = h.server
          .callsTo(KitchenRoutes.catalog)
          .where((c) => c.headers['X-Madar-Export'] == '1')
          .toList();
      expect(walk.first.query['search'], ['Croissant']);
      final items = h.exports.built.single.sheets[1];
      expect(items.subtitle, startsWith('Croissant'));
      expect(items.name, 'لكل صنف');
      expect(items.rows.map((r) => r.first), contains('كرواسون زبدة'));
      // A station is named as it was typed.
      expect(h.exports.built.single.sheets[0].rows.first, [
        'قهوة ساخنة',
        'Bar',
      ]);
    });

    testWidgets('SET-KRT-018 a failed walk toasts the server\'s words, no '
        'file', (tester) async {
      final m = setupMockServer();
      final h = await pumpKitchen(tester, path: routingPath, backend: m);
      final boom = MockResponse.error(503, 'Try again later');
      m.server.fail('GET', KitchenRoutes.catalog, boom);
      await h.tap(inRouting(byKey('routing-export')));
      await h.expectToast(h.refusalWords(boom));
      expect(h.files.saved, isEmpty);
      final export = tester.widget<DashButton>(
        find.descendant(
          of: inRouting(byKey('routing-export')),
          matching: find.byType(DashButton),
        ),
      );
      expect(export.loading, isFalse);
    });

    testWidgets('SET-KRT-021 Export shows while the categories still load '
        'and writes what has loaded', (tester) async {
      final m = setupMockServer();
      final gate = m.server.hold('GET', KitchenRoutes.categories);
      final h = await pumpKitchen(tester, path: routingPath, backend: m);
      expect(inRouting(byKey('routing-export')), findsOneWidget);
      await h.tap(inRouting(byKey('routing-export')));
      await h.flushTimers();
      final book = h.exports.built.single;
      expect(book.sheets[0].rows, isEmpty);
      expect(book.sheets[0].subtitle, startsWith('By category'));
      expect(book.sheets[1].rows, hasLength(40));
      gate.release();
      await h.settle();
    });
  });

  group('live, refusals, intent', () {
    testWidgets('SET-KRT-020 a kitchen.* event reads the stations and routes '
        'again', (tester) async {
      final h = await pumpKitchen(tester, path: routingPath);
      h.db![KitchenSeed.categoryRoutesTable].insert({
        'branch_id': SeedIds.zamalek,
        'category_id': _cat('dessert'),
        'station_id': stationId('zamalek', 'kitchen'),
      }, timestamps: false);
      h.realtime.current!.emit('kitchen.routes_changed', data: '{}');
      await h.settle();
      expect(h.server.callsTo(KitchenRoutes.stations), hasLength(2));
      expect(h.server.callsTo(KitchenRoutes.routes), hasLength(2));
      expect(h.server.callsTo(KitchenRoutes.categories), hasLength(1));
      expect(_shown(tester, _catSelect('dessert')), 'Kitchen');
    });

    testWidgets('SET-KRT-004 without kitchen.stations.read the reads refuse '
        'into the page\'s error', (tester) async {
      final h = await pumpKitchen(
        tester,
        path: routingPath,
        query: maadi,
        persona: Persona.limited,
      );
      expect(
        find.descendant(
          of: inRouting(byKey('routing-error')),
          matching: find.text(
            h.refusalWords(MockResponse.denied('kitchen.stations.read')),
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('SET-KRT-008 a branch manager routes their own branch', (
      tester,
    ) async {
      final h = await pumpKitchen(
        tester,
        path: routingPath,
        persona: Persona.manager,
      );
      await _pick(h, _catSelect('dessert'), 'Bar');
      expect(
        h.server.callsTo(KitchenRoutes.categoryRoute, method: 'PUT'),
        hasLength(1),
      );
      expect(_shown(tester, _catSelect('dessert')), 'Bar');
    });

    testWidgets('intent: pointing at "Per item" warms its page; pointing at '
        'Next warms page 2; the presses ask nothing more', (tester) async {
      final m = setupMockServer();
      _moreItems(m.db, 15);
      final h = await pumpKitchen(tester, path: routingPath, backend: m);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);

      final perItem = find.descendant(
        of: inRouting(byKey('routing-tabs')),
        matching: find.text('Per item'),
      );
      await mouse.moveTo(tester.getCenter(perItem));
      await h.settle();
      expect(_catalog(h), hasLength(1), reason: 'page 1 is warmed');
      await h.tap(perItem);
      expect(_catalog(h), hasLength(1), reason: 'the tab opened from cache');

      final next = inRouting(find.bySemanticsLabel('Next'));
      await tester.ensureVisible(next);
      await h.settle();
      await mouse.moveTo(tester.getCenter(next));
      await h.settle();
      expect(_catalog(h), hasLength(2), reason: 'page 2 is warmed');
      expect(_catalog(h).last.query['page'], ['2']);
      await h.tap(next);
      expect(_catalog(h), hasLength(2), reason: 'page 2 came from the cache');
      expect(inRouting(find.text('Page 2 of 2')), findsOneWidget);
    });
  });
}
