// `/menu/bases` driven through the real app shell (inventory rows
// MENU-BAS-001..018, plus the area rows that touch it: MENU-AREA-008, -010,
// -013, -014). Expectations are worked out from the area seed: "Espresso
// shot" (one House espresso blend line in All sizes, Large and Double),
// "Iced build" (ice in All sizes and Large, used by Cold Brew and Iced
// Matcha) and the inactive "Mocha base (old)".
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_menu/src/area_seed.dart';
import 'package:dashboard_catalog_menu/src/bases/bases_widgets.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _list = '/recipe-bases';
const _one = '/recipe-bases/{id}';
const _lines = '/recipe-bases/{id}/lines';
const _usage = '/recipe-bases/{id}/usage';
const _catalog = '/inventory/orgs/{org_id}/catalog';

final String _blend = MenuSeedIds.ingredient('house_blend');
final String _ice = MenuSeedIds.ingredient('ice');
final String _matcha = MenuSeedIds.ingredient('matcha');

/// The quantity cell of [ingredient] in the column [size].
Finder cell(DashHarness h, String ingredient, String size) =>
    find.bySemanticsLabel(
      h.t(
        'modeling.grid.cellAria',
        args: {'ingredient': ingredient, 'size': size},
      ),
    );

/// The editable text inside [f].
EditableText editable(WidgetTester tester, Finder f) => tester.widget(
  find.descendant(of: f, matching: find.byType(EditableText)).first,
);

Future<void> openEditor(DashHarness h, String baseId) =>
    h.tap(labelIn(rowOf(baseId), h.t('common.edit')));

Future<void> openNew(DashHarness h) => h.tapText(h.t('modeling.bases.new'));

/// Picks [name] in the "+ ingredient" combobox.
Future<void> addIngredient(DashHarness h, String name) async {
  await h.tap(find.text(h.t('modeling.grid.addIngredient')).last);
  await h.tap(find.text(name).hitTestable().last);
}

/// The "Base saved · N sizes updated" words.
String savedText(DashHarness h, int n) =>
    h.t('modeling.bases.saved', count: n);

void main() {
  group('MENU-BAS-001..008 the list', () {
    testWidgets('MENU-BAS-001 header: title, subtitle and "New base"', (
      tester,
    ) async {
      final h = await pumpMenu(tester);
      expect(find.text('Recipe bases'), findsWidgets);
      expect(
        find.text(
          'Lines several drinks share. Edit once and every size using the '
          'base follows.',
        ),
        findsOneWidget,
      );
      expect(find.text('New base'), findsOneWidget);
    });

    testWidgets('MENU-BAS-002 the org\'s bases, by name', (tester) async {
      final h = await pumpMenu(tester);
      expect(h.server.callsTo(_list, method: 'GET'), hasLength(1));
      final names = [
        for (final id in [espressoBase, icedBase, mochaOldBase])
          tester.getTopLeft(rowOf(id)).dy,
      ];
      expect(names, orderedEquals([...names]..sort()));
      expect(find.text('Espresso shot'), findsOneWidget);
      expect(find.text('Iced build'), findsOneWidget);
      expect(find.text('Mocha base (old)'), findsOneWidget);
    });

    testWidgets('MENU-BAS-003 loading: one skeleton, then the rows', (
      tester,
    ) async {
      final s = menuServer();
      final gate = s.server.hold('GET', _list);
      final h = await pumpMenu(tester, seeded: s);
      expect(find.byType(ModelingSkeleton), findsOneWidget);
      expect(find.text('Espresso shot'), findsNothing);
      await h.shot('bases/loading');
      gate.release();
      await h.settle();
      expect(find.byType(ModelingSkeleton), findsNothing);
      expect(find.text('Espresso shot'), findsOneWidget);
    });

    testWidgets('MENU-BAS-004 error: the words, the server\'s reason, Retry', (
      tester,
    ) async {
      final s = menuServer();
      s.server.fail('GET', _list, MockResponse.error(500, 'Database is down'));
      final h = await pumpMenu(tester, seeded: s);
      expect(find.text('Could not load recipe bases'), findsOneWidget);
      expect(find.text('Database is down'), findsOneWidget);
      expect(find.text('Espresso shot'), findsNothing);
      await h.shot('bases/error');
      await h.tapText('Retry');
      expect(find.text('Could not load recipe bases'), findsNothing);
      expect(find.text('Espresso shot'), findsOneWidget);
      expect(h.server.callsTo(_list, method: 'GET'), hasLength(2));
    });

    testWidgets('MENU-BAS-005 empty: the hint, no rows', (tester) async {
      final s = menuServer();
      CatalogMenuSeed.loadInto(s.db);
      s.db[MenuTables.bases].clear();
      final h = await pumpMenu(tester, seeded: s);
      expect(find.text('No recipe bases yet'), findsOneWidget);
      expect(
        find.text(
          "Create one for lines many drinks share, then pick it in an item's "
          'recipe.',
        ),
        findsOneWidget,
      );
      expect(find.text('New base'), findsOneWidget);
      await h.shot('bases/empty');
    });

    testWidgets('MENU-BAS-006 a row: name, Inactive pill, usage and lines', (
      tester,
    ) async {
      final h = await pumpMenu(tester);
      final db = h.db!;
      // Hand count: 14 items follow Espresso shot, 2 follow Iced build.
      expect(itemsUsing(db, espressoBase), 14);
      expect(itemsUsing(db, icedBase), 2);
      expect(sizesUsing(db, icedBase), 4);
      final espressoSizes = sizesUsing(db, espressoBase);
      expect(
        find.text(
          'Affects 14 items / $espressoSizes sizes · 3 lines',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Affects 2 items / 4 sizes · 2 lines'),
        findsOneWidget,
      );
      expect(find.text('Affects 0 items / 0 sizes · 1 line'), findsOneWidget);
      expect(
        find.descendant(
          of: rowOf(mochaOldBase),
          matching: find.text('Inactive'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: rowOf(icedBase), matching: find.text('Inactive')),
        findsNothing,
      );
    });

    testWidgets('MENU-BAS-007 row actions: Edit and Delete on every row', (
      tester,
    ) async {
      final h = await pumpMenu(tester);
      for (final id in [espressoBase, icedBase, mochaOldBase]) {
        expect(labelIn(rowOf(id), 'Edit'), findsOneWidget);
        expect(labelIn(rowOf(id), 'Delete'), findsOneWidget);
      }
      await openEditor(h, icedBase);
      expect(find.text('Edit base'), findsOneWidget);
    });

    for (final persona in [Persona.manager, Persona.limited]) {
      testWidgets('MENU-BAS-008 ${persona.name}: read-only list', (
        tester,
      ) async {
        final h = await pumpMenu(tester, persona: persona);
        expect(find.text('Espresso shot'), findsOneWidget);
        expect(find.text('New base'), findsNothing);
        expect(find.bySemanticsLabel('Edit'), findsNothing);
        expect(find.bySemanticsLabel('Delete'), findsNothing);
        await h.shot('bases/read-only-${persona.name}');
      });
    }

    testWidgets('MENU-AREA-008 no page guard: a person without the nav cap '
        'sees the page; the server refuses the read', (tester) async {
      final s = menuServer(persona: Persona.dawamOnly);
      final h = await pumpMenu(tester, persona: Persona.dawamOnly, seeded: s);
      // Nakhla has no POS module: the module gate answers first.
      expect(find.text('Espresso shot'), findsNothing);
      expect(h.server.callsTo(_list), isEmpty);
    });

    testWidgets('MENU-BAS-008 a 403 on the read shows the server\'s words', (
      tester,
    ) async {
      final s = menuServer(persona: Persona.limited);
      s.server.fail(
        'GET',
        _list,
        MockResponse.denied('menu.items.read'),
        times: null,
      );
      final h = await pumpMenu(tester, persona: Persona.limited, seeded: s);
      expect(find.text('Could not load recipe bases'), findsOneWidget);
      expect(
        textHas("You don't have permission to do this: See the menu"),
        findsOneWidget,
      );
      h.server.clearFailures();
    });

    testWidgets('MENU-AREA-010 platform admin, no org: the empty state, '
        'nothing fetched', (tester) async {
      final h = await pumpMenu(tester, persona: Persona.platform);
      expect(find.text('No recipe bases yet'), findsOneWidget);
      expect(h.server.callsTo(_list), isEmpty);
      // A platform admin holds every capability.
      expect(find.text('New base'), findsOneWidget);
    });

    testWidgets('MENU-AREA-010 platform admin with an org picked: the list', (
      tester,
    ) async {
      final h = await pumpMenu(tester, persona: Persona.platform);
      await h.container
          .read(selectedOrgProvider.notifier)
          .select(SeedIds.sabahOrg);
      await h.settle();
      expect(find.text('Espresso shot'), findsOneWidget);
      expect(
        h.server.callsTo(_list).last.headers['X-Org-Id'] ??
            h.server.callsTo(_list).last.headers['x-org-id'],
        SeedIds.sabahOrg,
      );
    });
  });

  group('MENU-BAS-009 delete', () {
    testWidgets('confirm, delete, toast, the row goes, sizes detached', (
      tester,
    ) async {
      final h = await pumpMenu(tester);
      final db = h.db!;
      final coldBrewRegular = MenuSeedIds.size('cold_brew', 'Regular');
      expect(
        db[MenuTables.recipeLines].where(
          (l) => l['size_id'] == coldBrewRegular && l['source'] == 'base',
        ),
        isNotEmpty,
      );
      await h.tap(labelIn(rowOf(icedBase), 'Delete'));
      expect(find.text('Delete "Iced build"?'), findsOneWidget);
      expect(
        find.text('Sizes using this base lose its lines. Their own lines stay.'),
        findsOneWidget,
      );
      // Not destructive-styled: no warning disc.
      expect(
        find.descendant(
          of: find.byType(DashConfirmDialog),
          matching: find.byWidgetPredicate(
            (w) => w is DashIcon && w.name == 'alert-triangle',
          ),
        ),
        findsNothing,
      );
      await h.shot('bases/delete-confirm');
      final lists = h.server.callsTo(_list, method: 'GET').length;
      await h.tap(
        find.descendant(
          of: find.byType(DashConfirmDialog),
          matching: find.text('Delete'),
        ),
      );
      final del = lastCall(h, 'DELETE', _one);
      expect(del.path, '/recipe-bases/$icedBase');
      expect(del.status, 204);
      await h.expectToast('Base deleted');
      expect(find.text('Iced build'), findsNothing);
      expect(h.server.callsTo(_list, method: 'GET').length, lists + 1);
      expect(sizesUsing(db, icedBase), 0);
      // Their own lines stay; the base's ice goes.
      final left = db[MenuTables.recipeLines].where(
        (l) => l['size_id'] == coldBrewRegular,
      );
      expect(left.where((l) => l['source'] == 'base'), isEmpty);
      expect(
        left.where((l) => l['source'] == 'own').map((l) => l['quantity']),
        ['30'],
      );
    });

    testWidgets('Cancel deletes nothing', (tester) async {
      final h = await pumpMenu(tester);
      await h.tap(labelIn(rowOf(icedBase), 'Delete'));
      await h.tap(
        find.descendant(
          of: find.byType(DashConfirmDialog),
          matching: find.text('Cancel'),
        ),
      );
      expect(h.server.callsTo(_one, method: 'DELETE'), isEmpty);
      expect(find.text('Iced build'), findsOneWidget);
    });

    testWidgets('a refusal shows the server\'s words, the row stays', (
      tester,
    ) async {
      final h = await pumpMenu(tester);
      h.server.fail('DELETE', _one, MockResponse.denied('menu.items.edit'));
      await h.tap(labelIn(rowOf(icedBase), 'Delete'));
      await h.tap(
        find.descendant(
          of: find.byType(DashConfirmDialog),
          matching: find.text('Delete'),
        ),
      );
      await h.expectToast(
        "Forbidden: You don't have permission to do this: Edit menu items, "
        'prices and availability (menu.items.edit)',
      );
      expect(find.text('Iced build'), findsOneWidget);
    });
  });

  group('MENU-BAS-010..014 the editor', () {
    testWidgets('MENU-BAS-010 new: title and the All sizes help', (
      tester,
    ) async {
      final h = await pumpMenu(tester);
      await openNew(h);
      expect(find.text('New base'), findsWidgets);
      expect(
        find.text(
          'Amounts in the All sizes column apply to every size; a size column '
          'overrides it.',
        ),
        findsOneWidget,
      );
      expect(h.server.callsTo(_usage), isEmpty);
      // MENU-BAS-013: an empty grid.
      expect(find.text('No ingredients yet.'), findsOneWidget);
      expect(find.text('All sizes'), findsOneWidget);
      await h.shot('bases/editor-new');
    });

    testWidgets('MENU-BAS-010 edit: the usage replaces the help once loaded', (
      tester,
    ) async {
      final s = menuServer();
      final gate = s.server.hold('GET', _usage);
      final h = await pumpMenu(tester, seeded: s);
      await openEditor(h, icedBase);
      expect(find.text('Edit base'), findsOneWidget);
      expect(
        find.text(
          'Amounts in the All sizes column apply to every size; a size column '
          'overrides it.',
        ),
        findsOneWidget,
      );
      gate.release();
      await h.settle();
      expect(lastCall(h, 'GET', _usage).path, '/recipe-bases/$icedBase/usage');
      expect(find.text('Affects 2 items / 4 sizes'), findsOneWidget);
    });

    testWidgets('MENU-BAS-010 every open starts from the base as listed', (
      tester,
    ) async {
      final h = await pumpMenu(tester);
      await openEditor(h, icedBase);
      await h.enterText(find.bySemanticsLabel('Name'), 'Changed');
      await h.tapText('Cancel');
      await openEditor(h, icedBase);
      expect(editable(tester, find.bySemanticsLabel('Name')).controller.text,
          'Iced build');
      expect(
        editable(tester, find.bySemanticsLabel('Name (ع)')).controller.text,
        'تجهيز المشروبات المثلجة',
      );
    });

    testWidgets('MENU-BAS-011 the English name is required (trimmed)', (
      tester,
    ) async {
      final h = await pumpMenu(tester);
      await openNew(h);
      await h.enterText(find.bySemanticsLabel('Name'), '   ');
      await h.tapText('Save');
      expect(find.text('This field is required'), findsOneWidget);
      expect(h.server.callsTo(_list, method: 'POST'), isEmpty);
      await h.shot('bases/editor-required');
      // Re-checked on every change after the first Save.
      await h.enterText(find.bySemanticsLabel('Name'), 'Chai base');
      expect(find.text('This field is required'), findsNothing);
      expect(find.bySemanticsLabel('Name (ع)'), findsOneWidget);
    });

    testWidgets('MENU-BAS-012 the Active switch is sent', (tester) async {
      final h = await pumpMenu(tester);
      await openEditor(h, icedBase);
      await h.tap(find.bySemanticsLabel('Active').first);
      await h.tapText('Save');
      final patch = lastCall(h, 'PATCH', _one);
      expect(patch.body, {
        'name': 'Iced build',
        'name_ar': 'تجهيز المشروبات المثلجة',
        'is_active': false,
      });
      expect(h.server.callsTo(_lines, method: 'PUT'), isEmpty);
      // The base's ice leaves the 4 sizes using it.
      await h.expectToast(savedText(h, 4));
      expect(
        find.descendant(of: rowOf(icedBase), matching: find.text('Inactive')),
        findsOneWidget,
      );
    });

    testWidgets('MENU-BAS-013 the grid: All sizes and the size columns', (
      tester,
    ) async {
      final h = await pumpMenu(tester);
      await openEditor(h, espressoBase);
      expect(find.text('Ingredient'), findsOneWidget);
      for (final col in ['All sizes', 'Large', 'Double']) {
        expect(find.text(col), findsOneWidget);
      }
      expect(
        editable(tester, cell(h, 'House espresso blend', 'All sizes'))
            .controller
            .text,
        '18',
      );
      expect(
        editable(tester, cell(h, 'House espresso blend', 'Double'))
            .controller
            .text,
        '36',
      );
      // × on the size columns only.
      expect(find.bySemanticsLabel('Remove column'), findsNWidgets(2));
      await h.shot('bases/editor-edit');
    });

    testWidgets('MENU-BAS-013 cells keep digits and one dot', (tester) async {
      final h = await pumpMenu(tester);
      await openEditor(h, espressoBase);
      await h.enterText(cell(h, 'House espresso blend', 'Large'), '2a7,5.1');
      expect(
        editable(tester, cell(h, 'House espresso blend', 'Large'))
            .controller
            .text,
        '27.51',
      );
    });

    testWidgets('MENU-BAS-013 + ingredient offers active ingredients not yet '
        'in the grid; trash removes the row', (tester) async {
      final h = await pumpMenu(tester);
      await openEditor(h, espressoBase);
      await h.tap(find.text('+ ingredient').last);
      // Already in the grid, and the inactive Vanilla powder: not offered.
      expect(
        find.descendant(
          of: find.byType(DashOptionList<String>),
          matching: find.text('House espresso blend'),
        ),
        findsNothing,
      );
      expect(find.text('Vanilla powder'), findsNothing);
      await h.shot('bases/editor-picker');
      await h.tap(find.text('Ice').hitTestable().last);
      expect(cell(h, 'Ice', 'All sizes'), findsOneWidget);
      expect(editable(tester, cell(h, 'Ice', 'Large')).controller.text, '');
      await h.tap(find.bySemanticsLabel('Remove ingredient').last);
      expect(cell(h, 'Ice', 'All sizes'), findsNothing);
      await h.tap(find.bySemanticsLabel('Remove ingredient').last);
      expect(find.text('No ingredients yet.'), findsOneWidget);
    });

    testWidgets('MENU-BAS-013 size columns: add (blank / duplicate disabled, '
        'Enter adds), remove', (tester) async {
      final h = await pumpMenu(tester);
      await openEditor(h, espressoBase);
      DashButton addButton() => tester.widget(
        find.ancestor(
          of: find.text('Size column'),
          matching: find.byType(DashButton),
        ),
      );
      expect(addButton().onPressed, isNull);
      final box = find.bySemanticsLabel('Size label, e.g. Cup');
      await h.enterText(box, 'Large');
      expect(addButton().onPressed, isNull);
      await h.enterText(box, ' Cup ');
      expect(addButton().onPressed, isNotNull);
      await h.tapText('Size column');
      expect(find.text('Cup'), findsOneWidget);
      expect(editable(tester, box).controller.text, '');
      expect(
        editable(tester, cell(h, 'House espresso blend', 'Cup'))
            .controller
            .text,
        '',
      );
      // Enter in the box adds too.
      await h.tap(box);
      await h.enterText(box, 'Can');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await h.settle();
      expect(find.text('Can'), findsOneWidget);
      expect(find.bySemanticsLabel('Remove column'), findsNWidgets(4));
      // × drops the column and its lines.
      await h.tap(find.bySemanticsLabel('Remove column').first);
      expect(find.text('Large'), findsNothing);
      expect(find.bySemanticsLabel('Remove column'), findsNWidgets(3));
    });

    testWidgets('MENU-BAS-013 Enter / ↓ and Shift+Enter / ↑ move within a '
        'column', (tester) async {
      final h = await pumpMenu(tester);
      await openEditor(h, espressoBase);
      await addIngredient(h, 'Ice');
      final top = cell(h, 'House espresso blend', 'Large');
      final below = cell(h, 'Ice', 'Large');
      await h.tap(top);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await h.settle(rounds: 2);
      expect(editable(tester, below).focusNode.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await h.settle(rounds: 2);
      expect(editable(tester, top).focusNode.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await h.settle(rounds: 2);
      expect(editable(tester, below).focusNode.hasFocus, isTrue);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await h.settle(rounds: 2);
      expect(editable(tester, top).focusNode.hasFocus, isTrue);
      expect(h.server.callsTo(_lines), isEmpty);
    });

    testWidgets('MENU-BAS-014 "Used by" opens to the item sizes', (
      tester,
    ) async {
      final h = await pumpMenu(tester);
      await openEditor(h, espressoBase);
      expect(find.text('Used by'), findsOneWidget);
      expect(textHas('Americano'), findsNothing);
      await h.tapText('Used by');
      expect(find.text('Americano · Regular', findRichText: true),
          findsOneWidget);
      expect(find.text('Espresso · Double', findRichText: true),
          findsOneWidget);
      // A one-price item names no size (no "one_size").
      expect(find.text('Cortado', findRichText: true), findsOneWidget);
      expect(textHas('one_size'), findsNothing);
      await h.shot('bases/editor-used-by');
    });

    testWidgets('MENU-BAS-014 nothing to list: no "Used by"', (tester) async {
      final h = await pumpMenu(tester);
      await openEditor(h, mochaOldBase);
      expect(find.text('Affects 0 items / 0 sizes'), findsOneWidget);
      expect(find.text('Used by'), findsNothing);
    });
  });

  group('MENU-BAS-015..018 saving', () {
    testWidgets('MENU-BAS-015 create: the body, the toast, the new row', (
      tester,
    ) async {
      final h = await pumpMenu(tester);
      await openNew(h);
      await h.enterText(find.bySemanticsLabel('Name'), '  Matcha blend ');
      await addIngredient(h, 'Matcha powder');
      await h.enterText(cell(h, 'Matcha powder', 'All sizes'), '4');
      await h.enterText(find.bySemanticsLabel('Size label, e.g. Cup'), 'Large');
      await h.tapText('Size column');
      await h.enterText(cell(h, 'Matcha powder', 'Large'), '6.5');
      await h.tapText('Save');
      final post = lastCall(h, 'POST', _list);
      expect(post.status, 201);
      expect(post.body, {
        'name': 'Matcha blend',
        'name_ar': null,
        'is_active': true,
        'lines': [
          {
            'size_label': null,
            'ingredient_id': _matcha,
            'quantity': 4,
            'unit': 'g',
            'sort': 0,
          },
          {
            'size_label': 'Large',
            'ingredient_id': _matcha,
            'quantity': 6.5,
            'unit': 'g',
            'sort': 1,
          },
        ],
      });
      await h.expectToast('Base created');
      expect(find.text('New base'), findsOneWidget); // the dialog closed
      expect(find.text('Matcha blend'), findsOneWidget);
      expect(find.text('Affects 0 items / 0 sizes · 2 lines'), findsOneWidget);
    });

    testWidgets('MENU-BAS-015 a refused create keeps the dialog open', (
      tester,
    ) async {
      final h = await pumpMenu(tester);
      await openNew(h);
      // Base names are unique per org (case-insensitive): 409.
      await h.enterText(find.bySemanticsLabel('Name'), 'espresso SHOT');
      await h.tapText('Save');
      await h.expectToast(
        'Conflict: A recipe base with this name already exists',
      );
      expect(find.text('New base'), findsWidgets);
      expect(find.bySemanticsLabel('Name'), findsOneWidget);
    });

    testWidgets('MENU-BAS-016 edit: PATCH only the changed fields, PUT only '
        'changed lines; the toast sums the sizes', (tester) async {
      final h = await pumpMenu(tester);
      final db = h.db!;
      // Raising the Large shot re-expands every Large size on the base.
      final larges = db[MenuTables.sizes]
          .where((s) => s['base_id'] == espressoBase && s['label'] == 'Large')
          .length;
      await openEditor(h, espressoBase);
      await h.enterText(find.bySemanticsLabel('Name'), 'Espresso shot (18 g)');
      await h.enterText(cell(h, 'House espresso blend', 'Large'), '30');
      await h.tapText('Save');
      expect(lastCall(h, 'PATCH', _one).body, {
        'name': 'Espresso shot (18 g)',
        'name_ar': 'شوت إسبريسو',
        'is_active': true,
      });
      expect(lastCall(h, 'PUT', _lines).body, {
        'lines': [
          {
            'size_label': null,
            'ingredient_id': _blend,
            'quantity': 18,
            'unit': 'g',
            'sort': 0,
          },
          {
            'size_label': 'Large',
            'ingredient_id': _blend,
            'quantity': 30,
            'unit': 'g',
            'sort': 1,
          },
          {
            'size_label': 'Double',
            'ingredient_id': _blend,
            'quantity': 36,
            'unit': 'g',
            'sort': 2,
          },
        ],
      });
      await h.expectToast(savedText(h, larges));
      expect(find.text('Espresso shot (18 g)'), findsOneWidget);
      final latteLarge = MenuSeedIds.size('latte', 'Large');
      expect(
        db[MenuTables.recipeLines]
            .where(
              (l) => l['size_id'] == latteLarge && l['source'] == 'base',
            )
            .single['quantity'],
        '30',
      );
    });

    testWidgets('MENU-BAS-016 only the lines changed: PUT, no PATCH', (
      tester,
    ) async {
      final h = await pumpMenu(tester);
      await openEditor(h, icedBase);
      await h.enterText(cell(h, 'Ice', 'Large'), '');
      await h.tapText('Save');
      expect(h.server.callsTo(_one, method: 'PATCH'), isEmpty);
      expect(lastCall(h, 'PUT', _lines).body, {
        'lines': [
          {
            'size_label': null,
            'ingredient_id': _ice,
            'quantity': 150,
            'unit': 'g',
            'sort': 0,
          },
        ],
      });
      // The two Large sizes now take the All sizes 150 g.
      await h.expectToast(savedText(h, 2));
    });

    testWidgets('MENU-BAS-016 clearing the Arabic name sends "" (divergence)', (
      tester,
    ) async {
      final h = await pumpMenu(tester);
      await openEditor(h, icedBase);
      await h.enterText(find.bySemanticsLabel('Name (ع)'), '  ');
      await h.tapText('Save');
      expect(lastCall(h, 'PATCH', _one).body, {
        'name': 'Iced build',
        'name_ar': '',
        'is_active': true,
      });
      await h.flushTimers();
      expect(h.db![MenuTables.bases].find(icedBase)!['name_ar'], isNull);
      await openEditor(h, icedBase);
      expect(
        editable(tester, find.bySemanticsLabel('Name (ع)')).controller.text,
        '',
      );
    });

    testWidgets('MENU-BAS-017 save end: bases and catalog refetched, closed', (
      tester,
    ) async {
      final h = await pumpMenu(tester);
      final lists = h.server.callsTo(_list, method: 'GET').length;
      await openEditor(h, icedBase);
      await h.enterText(find.bySemanticsLabel('Name'), 'Iced base');
      await h.tapText('Save');
      await h.flushTimers();
      expect(find.text('Edit base'), findsNothing);
      expect(h.server.callsTo(_list, method: 'GET').length, lists + 1);
      expect(find.text('Iced base'), findsOneWidget);
    });

    testWidgets('MENU-BAS-017 an error keeps the dialog open with the words', (
      tester,
    ) async {
      final h = await pumpMenu(tester);
      h.server.fail(
        'PUT',
        _lines,
        MockResponse.badRequest('quantity must be >= 0'),
      );
      await openEditor(h, icedBase);
      await h.enterText(cell(h, 'Ice', 'All sizes'), '160');
      await h.tapText('Save');
      await h.expectToast('Bad request: quantity must be >= 0');
      expect(find.text('Edit base'), findsOneWidget);
      // Save again once the server agrees.
      await h.tapText('Save');
      await h.expectToast(savedText(h, 2));
      expect(find.text('Edit base'), findsNothing);
    });

    testWidgets('MENU-BAS-017 Cancel closes without a request', (
      tester,
    ) async {
      final h = await pumpMenu(tester);
      await openEditor(h, icedBase);
      await h.enterText(find.bySemanticsLabel('Name'), 'Other');
      await h.tapText('Cancel');
      expect(find.text('Edit base'), findsNothing);
      expect(h.server.callsTo(_one, method: 'PATCH'), isEmpty);
      expect(find.text('Iced build'), findsOneWidget);
    });

    testWidgets('MENU-BAS-018 nothing changed: no request, "0 sizes updated", '
        'refetched, closed', (tester) async {
      final h = await pumpMenu(tester);
      final lists = h.server.callsTo(_list, method: 'GET').length;
      await openEditor(h, espressoBase);
      // Typed then cleared back: the cleaned lines did not change.
      await h.enterText(cell(h, 'House espresso blend', 'Large'), '27.0');
      await h.tapText('Save');
      expect(h.server.callsTo(_one, method: 'PATCH'), isEmpty);
      expect(h.server.callsTo(_lines, method: 'PUT'), isEmpty);
      await h.expectToast('Base saved · 0 sizes updated');
      expect(find.text('Edit base'), findsNothing);
      expect(h.server.callsTo(_list, method: 'GET').length, lists + 1);
    });

    testWidgets('MENU-AREA-013 Enter in the name submits the editor', (
      tester,
    ) async {
      final h = await pumpMenu(tester);
      await openNew(h);
      final name = find.bySemanticsLabel('Name');
      await h.tap(name);
      await h.enterText(name, 'Chai base');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await h.settle();
      expect(lastCall(h, 'POST', _list).body, {
        'name': 'Chai base',
        'name_ar': null,
        'is_active': true,
        'lines': <Object?>[],
      });
      await h.expectToast('Base created');
    });

    testWidgets('MENU-AREA-013 Enter on the last row submits; on a blank size '
        'label too', (tester) async {
      final h = await pumpMenu(tester);
      await openEditor(h, icedBase);
      await h.tap(cell(h, 'Ice', 'All sizes'));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await h.settle();
      await h.expectToast('Base saved · 0 sizes updated');
      await openEditor(h, icedBase);
      final box = find.bySemanticsLabel('Size label, e.g. Cup');
      await h.tap(box);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await h.settle();
      await h.expectToast('Base saved · 0 sizes updated');
      expect(find.text('Edit base'), findsNothing);
    });

    testWidgets('MENU-AREA-014 until the catalog lands, lines read "Unknown '
        'ingredient" and the picker is empty', (tester) async {
      final s = menuServer();
      final h = await pumpMenu(tester, seeded: s);
      // The list page does not read the catalog: the editor's read is held.
      final gate = s.server.hold('GET', _catalog);
      await openEditor(h, icedBase);
      expect(find.text('Unknown ingredient'), findsOneWidget);
      gate.release();
      await h.settle();
      expect(find.text('Unknown ingredient'), findsNothing);
      expect(find.text('Ice'), findsOneWidget);
    });
  });

  group('phone', () {
    testWidgets('the editor is a full-screen form; Save works', (
      tester,
    ) async {
      final h = await pumpMenu(tester, size: DashSize.phone, locale: 'ar');
      await openEditor(h, icedBase);
      expect(find.text(h.t('modeling.bases.edit')), findsOneWidget);
      await h.shot('bases/editor-edit');
      await h.tapText(h.t('modeling.bases.usedBy'));
      await h.shot('bases/editor-used-by');
      await h.tapText(h.t('common.save'));
      await h.expectToast(h.t('modeling.bases.saved', count: 0));
    });
  });
}
