// The Categories tab, its reorder list and the category dialog
// (MENU-ITEMS-056..071, MENU-AREA-013) driven through the real shell.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_menu/src/area_seed.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/material.dart' show ReorderableListView;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const String _categories = '/categories';
const String _category = '/categories/{id}';
const String _order = '/categories/order';

const List<String> _seedOrder = [
  'hot',
  'iced',
  'tea',
  'juice',
  'bakery',
  'dessert',
  'breakfast',
];

Future<DashHarness> _open(
  WidgetTester tester, {
  Persona persona = Persona.owner,
  ({MockServer server, MockDb db})? seeded,
  String locale = 'en',
}) async {
  final h = await pumpItems(
    tester,
    persona: persona,
    seeded: seeded,
    locale: locale,
  );
  await openTab(h, 'categories');
  return h;
}

Finder get _reorderList => find.byType(ReorderableListView);

void main() {
  testWidgets('MENU-ITEMS-056 every category, in POS order', (tester) async {
    final h = await _open(tester);
    expect(lastCall(h, 'GET', _categories).query, {
      'org_id': [sabahOrg],
    });
    final tops = [
      for (final n in [
        'Hot Coffee',
        'Iced Coffee',
        'Tea & More',
        'Fresh Juice',
      ])
        tester.getTopLeft(cardOf(n)),
    ];
    expect(tops.sublist(0, 3).map((o) => o.dy).toSet(), hasLength(1));
    expect(tops[0].dx, lessThan(tops[1].dx));
    expect(tops[3].dy, greaterThan(tops[0].dy));
    expect(inPage(find.text('Breakfast')), findsOneWidget);
  });

  testWidgets('MENU-ITEMS-057 loading skeletons, then cards', (tester) async {
    final s = itemsServer();
    final gate = s.server.hold('GET', _categories);
    final h = await _open(tester, seeded: s);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('menu-grid-categories')),
        matching: find.byType(DashSkeleton),
      ),
      findsNWidgets(8),
    );
    gate.release();
    await h.settle();
    expect(inPage(find.text('Hot Coffee')), findsOneWidget);
  });

  testWidgets('MENU-ITEMS-057 empty: "No categories yet"', (tester) async {
    final s = itemsServer();
    for (final k in _seedOrder) {
      s.db[MenuTables.categories].update(category(k), {
        'deleted_at': '2026-09-01T09:00:00Z',
      });
    }
    await _open(tester, seeded: s);
    expect(inPage(find.text('No categories yet')), findsOneWidget);
  });

  testWidgets('MENU-ITEMS-057 (divergence) a failed read: words and Retry', (
    tester,
  ) async {
    final s = itemsServer();
    s.server.fail(
      'GET',
      _categories,
      MockResponse.error(500, 'boom'),
      times: null,
    );
    final h = await _open(tester, seeded: s);
    expect(inPage(find.text("Couldn't load this")), findsOneWidget);
    expect(inPage(find.text('No categories yet')), findsNothing);
    s.server.clearFailures();
    await h.tap(inPage(find.text('Retry')));
    expect(inPage(find.text('Hot Coffee')), findsOneWidget);
  });

  testWidgets('MENU-ITEMS-058 search: the name or the Arabic name', (
    tester,
  ) async {
    final h = await _open(tester, locale: 'ar');
    await h.enterText(labelIn(page, h.t('common.search')), 'مخبوزات');
    await tester.pump(const Duration(milliseconds: 350));
    await h.settle();
    expect(inPage(find.text('مخبوزات')), findsWidgets);
    expect(inPage(find.text('قهوة ساخنة')), findsNothing);
    await h.enterText(labelIn(page, h.t('common.search')), 'iced');
    await tester.pump(const Duration(milliseconds: 350));
    await h.settle();
    expect(inPage(find.text('قهوة مثلجة')), findsOneWidget);
  });

  testWidgets('MENU-ITEMS-059 card: tile, title, Active; no footer', (
    tester,
  ) async {
    await _open(tester);
    final card = cardOf('Bakery');
    expect(
      find.descendant(of: card, matching: find.text('Active')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('Price')),
      findsNothing,
    );
  });

  testWidgets('MENU-ITEMS-060 inline rename', (tester) async {
    final h = await _open(tester);
    await h.tap(labelIn(cardOf('Bakery'), 'Name: Bakery'));
    await typeAndSubmit(h, labelIn(page, 'Name'), 'Bakery & Pastry');
    final call = lastCall(h, 'PATCH', _category);
    expect(call.path, '/categories/${category('bakery')}');
    expect(call.body, {'name': 'Bakery & Pastry'});
    await h.expectToast('Changes saved');
    expect(inPage(find.text('Bakery & Pastry')), findsOneWidget);
  });

  testWidgets('MENU-ITEMS-061 inline Active', (tester) async {
    final h = await _open(tester);
    await h.tap(switchIn(cardOf('Bakery'), 'Active'));
    expect(lastCall(h, 'PATCH', _category).body, {'is_active': false});
    await h.expectToast('Changes saved');
  });

  testWidgets('MENU-ITEMS-062 New category opens the dialog', (tester) async {
    final h = await _open(tester);
    await h.tapText('New category');
    expect(inSurface(find.text('New category')), findsOneWidget);
  });

  testWidgets('MENU-ITEMS-063 actions: Edit, Delete', (tester) async {
    final h = await _open(tester);
    await openCardMenu(h, 'Bakery');
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    await pickMenu(h, 'Edit');
    expect(inSurface(find.text('Edit category')), findsOneWidget);
  });

  testWidgets('MENU-ITEMS-064 delete: confirm, DELETE, items keep going', (
    tester,
  ) async {
    final s = itemsServer();
    final h = await _open(tester, seeded: s);
    await openCardMenu(h, 'Desserts');
    await pickMenu(h, 'Delete');
    expect(find.text('Delete "Desserts"?'), findsOneWidget);
    expect(
      find.text(
        'The category and its kitchen routing are removed. Its items '
        'stay on the menu without a category.',
      ),
      findsOneWidget,
    );
    await h.tap(
      find.descendant(
        of: find.byType(DashConfirmDialog),
        matching: find.text('Delete'),
      ),
    );
    expect(
      lastCall(h, 'DELETE', _category).path,
      '/categories/${category('dessert')}',
    );
    await h.expectToast('Changes saved');
    expect(inPage(find.text('Desserts')), findsNothing);
    expect(
      s.db[MenuTables.menuItems].find(item('fudge'))!['category_id'],
      isNull,
    );
  });

  testWidgets('MENU-ITEMS-065 Reorder shows with more than one category', (
    tester,
  ) async {
    await _open(tester);
    expect(inPage(find.text('Reorder')), findsOneWidget);
  });

  testWidgets('MENU-ITEMS-065 one category: no Reorder', (tester) async {
    final s = itemsServer();
    for (final k in _seedOrder.skip(1)) {
      s.db[MenuTables.categories].update(category(k), {
        'deleted_at': '2026-09-01T09:00:00Z',
      });
    }
    await _open(tester, seeded: s);
    expect(inPage(find.text('Reorder')), findsNothing);
  });

  testWidgets('MENU-ITEMS-066 reorder mode: Done, hint, rows, ends disabled', (
    tester,
  ) async {
    final h = await _open(tester);
    await h.tapText('Reorder');
    expect(inPage(find.text('Done')), findsOneWidget);
    expect(
      inPage(
        find.text(
          'Drag to reorder — this is the order the POS shows categories in.',
        ),
      ),
      findsOneWidget,
    );
    expect(
      labelIn(_reorderList, 'Drag "Hot Coffee" to reorder'),
      findsOneWidget,
    );
    DashIconButton btn(String name, String label) =>
        tester.widget<DashIconButton>(
          find
              .ancestor(
                of: find.descendant(
                  of: find
                      .ancestor(of: find.text(name), matching: find.byType(Row))
                      .first,
                  matching: find.bySemanticsLabel(label),
                ),
                matching: find.byType(DashIconButton),
              )
              .first,
        );
    expect(btn('Hot Coffee', 'Move up').onPressed, isNull);
    expect(btn('Hot Coffee', 'Move down').onPressed, isNotNull);
    expect(btn('Breakfast', 'Move down').onPressed, isNull);
    await h.tapText('Done');
    expect(find.byKey(const ValueKey('menu-grid-categories')), findsOneWidget);
  });

  testWidgets('MENU-ITEMS-067 move down: optimistic, the whole order saved', (
    tester,
  ) async {
    final s = itemsServer();
    final h = await _open(tester, seeded: s);
    await h.tapText('Reorder');
    await h.tap(
      find.descendant(
        of: find
            .ancestor(of: find.text('Hot Coffee'), matching: find.byType(Row))
            .first,
        matching: find.bySemanticsLabel('Move down'),
      ),
    );
    final call = lastCall(h, 'PUT', _order);
    expect(call.body, {
      'org_id': sabahOrg,
      'ordered_ids': [
        category('iced'),
        category('hot'),
        for (final k in _seedOrder.skip(2)) category(k),
      ],
    });
    await h.expectToast('Changes saved');
    expect(
      tester
          .getTopLeft(
            find.descendant(
              of: _reorderList,
              matching: find.text('Iced Coffee'),
            ),
          )
          .dy,
      lessThan(
        tester
            .getTopLeft(
              find.descendant(
                of: _reorderList,
                matching: find.text('Hot Coffee'),
              ),
            )
            .dy,
      ),
    );
  });

  testWidgets('MENU-ITEMS-067 by drag, with the handle', (tester) async {
    final h = await _open(tester);
    await h.tapText('Reorder');
    final handle = labelIn(_reorderList, 'Drag "Hot Coffee" to reorder');
    final rowHeight = tester
        .getSize(
          find
              .ancestor(
                of: find.text('Iced Coffee'),
                matching: find.byType(Row),
              )
              .first,
        )
        .height;
    final g = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 50));
    await g.moveBy(Offset(0, rowHeight * 1.6));
    await tester.pump(const Duration(milliseconds: 50));
    await g.moveBy(Offset(0, rowHeight * 0.4));
    await tester.pump(const Duration(milliseconds: 50));
    await g.up();
    await h.settle();
    final ids =
        (lastCall(h, 'PUT', _order).body! as Map)['ordered_ids'] as List;
    expect(ids.first, isNot(category('hot')));
    await h.flushTimers();
  });

  testWidgets('MENU-ITEMS-067 a failed save rolls back with the words', (
    tester,
  ) async {
    final s = itemsServer();
    final bad = MockResponse.badRequest(
      "ordered_ids must contain exactly the org's live categories",
    );
    s.server.fail('PUT', _order, bad);
    final h = await _open(tester, seeded: s);
    await h.tapText('Reorder');
    await h.tap(
      find.descendant(
        of: find
            .ancestor(of: find.text('Hot Coffee'), matching: find.byType(Row))
            .first,
        matching: find.bySemanticsLabel('Move down'),
      ),
    );
    await h.expectToast(h.refusalWords(bad));
    expect(
      tester
          .getTopLeft(
            find.descendant(
              of: _reorderList,
              matching: find.text('Hot Coffee'),
            ),
          )
          .dy,
      lessThan(
        tester
            .getTopLeft(
              find.descendant(
                of: _reorderList,
                matching: find.text('Iced Coffee'),
              ),
            )
            .dy,
      ),
    );
  });

  group('category dialog', () {
    testWidgets('MENU-ITEMS-068 titles, description, Cancel; reset per open', (
      tester,
    ) async {
      final h = await _open(tester);
      await h.tapText('New category');
      expect(
        inSurface(find.text('Categories group your menu items.')),
        findsOneWidget,
      );
      await h.enterText(labelIn(surface, 'Name'), 'Smoothies');
      await h.tap(inSurface(find.text('Cancel')));
      expect(find.byType(DashSurface), findsNothing);
      await h.tapText('New category');
      expect(
        tester
            .widget<EditableText>(
              find
                  .descendant(
                    of: labelIn(surface, 'Name'),
                    matching: find.byType(EditableText),
                  )
                  .first,
            )
            .controller
            .text,
        '',
      );
      await h.tap(inSurface(find.text('Cancel')));
      await openCardMenu(h, 'Bakery');
      await pickMenu(h, 'Edit');
      expect(inSurface(find.text('Edit category')), findsOneWidget);
      expect(
        tester
            .widget<EditableText>(
              find
                  .descendant(
                    of: labelIn(surface, 'Name (ع)'),
                    matching: find.byType(EditableText),
                  )
                  .first,
            )
            .controller
            .text,
        'مخبوزات',
      );
    });

    testWidgets('MENU-ITEMS-068 (re-seed) opened on a list older than 30 s: '
        'the fresh row shows; once edited, a refetch keeps the edit; Save '
        'sends the fresh name and the edit', (tester) async {
      final s = itemsServer();
      final h = await _open(tester, seeded: s);
      s.db[MenuTables.categories].update(category('bakery'), {
        'name': 'Bakery & Pastry',
        'name_translations': {'en': 'Bakery & Pastry', 'ar': 'مخبوزات ومعجنات'},
      });
      s.db.clock.advance(const Duration(seconds: 31));
      final gets = callsOf(h, 'GET', _categories).length;
      await openCardMenu(h, 'Bakery');
      await pickMenu(h, 'Edit');
      expect(callsOf(h, 'GET', _categories), hasLength(gets + 1));
      String text(String label) => tester
          .widget<EditableText>(
            find
                .descendant(
                  of: fieldIn(surface, label),
                  matching: find.byType(EditableText),
                )
                .first,
          )
          .controller
          .text;
      expect(text('Name'), 'Bakery & Pastry');
      expect(text('Name (ع)'), 'مخبوزات ومعجنات');

      await h.tap(switchIn(surface, 'Active'));
      s.db[MenuTables.categories].update(category('bakery'), {
        'name': 'Renamed elsewhere',
      });
      h.container.read(realtimeBusProvider).invalidate(const ['/categories']);
      await h.settle();
      expect(callsOf(h, 'GET', _categories), hasLength(gets + 2));
      expect(text('Name'), 'Bakery & Pastry');
      await h.tap(inSurface(find.text('Save')));
      expect(lastCall(h, 'PATCH', _category).body, {
        'is_active': false,
        'name': 'Bakery & Pastry',
        'name_translations': {'ar': 'مخبوزات ومعجنات'},
      });
      await h.flushTimers();
    });

    testWidgets('MENU-ITEMS-069 name required; Arabic optional', (
      tester,
    ) async {
      final h = await _open(tester);
      await h.tapText('New category');
      await h.tap(inSurface(find.text('Save')));
      expect(inSurface(find.text('This field is required')), findsOneWidget);
      expect(callsOf(h, 'POST', _categories), isEmpty);
      expect(labelIn(surface, 'Name (ع)'), findsWidgets);
    });

    testWidgets('MENU-ITEMS-070 / 071 create: no is_active, {ar} only when '
        'typed; toast; listed', (tester) async {
      final s = itemsServer();
      final h = await _open(tester, seeded: s);
      await h.tapText('New category');
      await h.enterText(labelIn(surface, 'Name'), 'Smoothies');
      await h.tap(switchIn(surface, 'Active'));
      await h.tap(inSurface(find.text('Save')));
      expect(lastCall(h, 'POST', _categories).body, {
        'name': 'Smoothies',
        'org_id': sabahOrg,
      });
      await h.expectToast('Changes saved');
      expect(find.byType(DashSurface), findsNothing);
      expect(inPage(find.text('Smoothies')), findsOneWidget);
      final row = s.db[MenuTables.categories].firstWhere(
        (c) => c['name'] == 'Smoothies',
      )!;
      expect(row['is_active'], isTrue, reason: 'created active anyway');
      await h.tapText('New category');
      await h.enterText(labelIn(surface, 'Name'), 'Bowls');
      await h.enterText(labelIn(surface, 'Name (ع)'), 'أطباق');
      await h.tap(inSurface(find.text('Save')));
      expect(lastCall(h, 'POST', _categories).body, {
        'name': 'Bowls',
        'name_translations': {'ar': 'أطباق'},
        'org_id': sabahOrg,
      });
      await h.flushTimers();
    });

    testWidgets('MENU-ITEMS-070 / 071 edit sends is_active; MENU-ITEMS-115 '
        'an emptied Arabic box omits translations', (tester) async {
      final h = await _open(tester);
      await openCardMenu(h, 'Bakery');
      await pickMenu(h, 'Edit');
      await h.enterText(labelIn(surface, 'Name (ع)'), '');
      await h.tap(switchIn(surface, 'Active'));
      await h.tap(inSurface(find.text('Save')));
      expect(lastCall(h, 'PATCH', _category).body, {
        'is_active': false,
        'name': 'Bakery',
      });
      await h.expectToast('Changes saved');
    });

    testWidgets('MENU-ITEMS-071 a refused save keeps the dialog', (
      tester,
    ) async {
      final h = await _open(tester, persona: Persona.manager);
      await h.tapText('New category');
      await h.enterText(labelIn(surface, 'Name'), 'Smoothies');
      await h.tap(inSurface(find.text('Save')));
      await h.expectToast(
        h.refusalWords(MockResponse.denied('menu.categories.create')),
      );
      expect(inSurface(find.text('New category')), findsOneWidget);
    });

    testWidgets('MENU-AREA-013 Enter in the name submits', (tester) async {
      final h = await _open(tester);
      await h.tapText('New category');
      await typeAndSubmit(h, labelIn(surface, 'Name'), 'Smoothies');
      expect(lastCall(h, 'POST', _categories).body, {
        'name': 'Smoothies',
        'org_id': sabahOrg,
      });
      await h.flushTimers();
    });
  });
}
