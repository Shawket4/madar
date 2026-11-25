// The Items page's export menu (menu-items-page.tsx `handleRecipeExport`):
// the Recipes section only with recipes.read, one book read with the page's
// own filters, the three files.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_menu/src/mock/recipes_mock.dart'
    show recipeBook;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const String _bookPath = '/recipes/book';

/// The export control reading [words].
Finder _triggerReading(String words) => inPage(
  find.ancestor(of: find.text(words), matching: find.byType(DashButton)),
);

/// The export control with the Recipes section: "Export"
/// (`recipeBook.exportMenu`).
Finder get _trigger => _triggerReading('Export');

/// The menu the export control opens, when it is one.
Finder _menuOf(Finder trigger) =>
    find.ancestor(of: trigger, matching: find.byType(DashMenu));

/// Opens the export menu and picks [file].
Future<void> _export(DashHarness h, String file) async {
  await h.tap(_trigger);
  await pickMenu(h, file);
  await h.settle();
}

void main() {
  testWidgets('the Recipes section is offered only with recipes.read', (
    tester,
  ) async {
    final h = await pumpItems(tester);
    expect(_menuOf(_trigger), findsOneWidget);
    expect(_triggerReading('Export Excel'), findsNothing);
    await h.tap(_trigger);
    for (final word in [
      'Menu (Excel)',
      'Recipes',
      'Recipes with costs (Excel)',
      'Recipe cards, no costs (Excel)',
      'Recipe lines (CSV)',
    ]) {
      expect(find.text(word), findsOneWidget, reason: word);
    }
    await h.flushTimers();
  });

  testWidgets('without recipes.read: the one button, exporting the menu as '
      'before', (tester) async {
    final h = await pumpItems(tester, persona: Persona.limited);
    final button = _triggerReading('Export Excel');
    expect(button, findsOneWidget);
    expect(_trigger, findsNothing);
    expect(_menuOf(button), findsNothing);
    final control = tester.widget<DashExportButton>(
      find.byType(DashExportButton),
    );
    expect(control.more, isEmpty);
    expect(control.excelLabel, isNull);
    expect(control.label, isNull);
    expect(find.text('Recipes with costs (Excel)'), findsNothing);
    expect(callsOf(h, 'GET', _bookPath), isEmpty);
  });

  testWidgets('Menu (Excel) is the menu export, unchanged', (tester) async {
    final h = await pumpItems(tester);
    await _export(h, 'Menu (Excel)');
    expect(h.files.saved.single.filename, startsWith('Madar-Menu-'));
    expect(callsOf(h, 'GET', _bookPath), isEmpty);
    await h.flushTimers();
  });

  testWidgets('Recipes with costs: one book read with the page\'s filters, '
      'marked as an export; the tables, then the lines', (tester) async {
    final s = itemsServer();
    final h = await pumpItems(tester, seeded: s);
    await h.tap(find.byKey(const ValueKey('filter-category')));
    await pickOption(h, 'Hot Coffee');
    await h.tap(find.byKey(const ValueKey('filter-recipe')));
    await pickOption(h, 'Has a recipe');
    await _export(h, 'Recipes with costs (Excel)');

    final read = callsOf(h, 'GET', _bookPath).single;
    expect(read.query, {
      'org_id': [sabahOrg],
      'category_id': [category('hot')],
      'has_recipe': ['true'],
    });
    expect(read.headers['X-Madar-Export'], '1');

    final spec = h.exports.built.single;
    final tables = spec.allSheets.first as BlockSheetSpec;
    expect(tables.title, 'Recipes');
    expect(
      tables.subtitle,
      startsWith('Hot Coffee  ·  Has a recipe  ·  Generated: '),
    );
    expect(tables.rows.first.kind, BlockRowKind.group);
    expect(tables.rows.first.text, 'Hot Coffee');
    expect(
      tables.rows.where((r) => r.kind == BlockRowKind.footer),
      isNotEmpty,
      reason: 'cost, price and food cost under each table',
    );
    expect(spec.sheets.single.title, 'Ingredient lines');
    expect(spec.sheets.single.columns.last.header, 'Line cost');
    expect(
      h.files.saved.single.filename,
      matches(RegExp(r'^Madar-Recipes-\d{4}-\d{2}-\d{2}\.xlsx$')),
    );
    final n =
        (recipeBook(
                  s.db,
                  org: sabahOrg,
                  categoryId: category('hot'),
                  hasRecipe: true,
                )['items']!
                as List)
            .length;
    expect(n, greaterThan(1));
    await h.expectToast('Exported $n recipes');
  });

  testWidgets('Recipe cards: the same tables, no money at all', (tester) async {
    final h = await pumpItems(tester);
    await _export(h, 'Recipe cards, no costs (Excel)');
    final spec = h.exports.built.single;
    final tables = spec.allSheets.first as BlockSheetSpec;
    expect(tables.title, 'Recipe cards');
    expect(tables.rows.where((r) => r.kind == BlockRowKind.footer), isEmpty);
    expect(tables.rows.where((r) => r.kind == BlockRowKind.title), isNotEmpty);
    expect(
      spec.sheets.single.columns.map((c) => c.header),
      isNot(contains('Line cost')),
    );
    expect(
      h.files.saved.single.filename,
      matches(RegExp(r'^Madar-Recipe-Cards-\d{4}-\d{2}-\d{2}\.xlsx$')),
    );
    await h.flushTimers();
  });

  testWidgets('Recipe lines: the flat sheet as a CSV', (tester) async {
    final h = await pumpItems(tester);
    await _export(h, 'Recipe lines (CSV)');
    expect(h.exports.built, isEmpty, reason: 'no workbook for a CSV');
    final saved = h.files.saved.single;
    expect(
      saved.filename,
      matches(RegExp(r'^Madar-Recipe-Lines-\d{4}-\d{2}-\d{2}\.csv$')),
    );
    expect(
      saved.asString.split('\r\n').first,
      'Category,Item,Size,Ingredient,From,Quantity,Unit,Line cost',
    );
    await h.flushTimers();
  });

  testWidgets('a refused read says why, and nothing is written', (
    tester,
  ) async {
    final s = itemsServer();
    final h = await pumpItems(tester, seeded: s);
    s.server.fail(
      'GET',
      _bookPath,
      MockResponse.badRequest(
        'That is 6000 items, and a recipe book holds at most 5000. '
        'Pick a category or search, and try again.',
      ),
    );
    await _export(h, 'Recipes with costs (Excel)');
    await h.expectToast(
      'That is 6000 items, and a recipe book holds at most 5000. '
      'Pick a category or search, and try again.',
    );
    expect(h.exports.built, isEmpty);
    expect(h.files.saved, isEmpty);
  });

  testWidgets('in Arabic: the menu and the book in Arabic', (tester) async {
    final h = await pumpItems(tester, locale: 'ar');
    await h.tap(
      inPage(
        find.ancestor(
          of: find.text(h.t('recipeBook.exportMenu')),
          matching: find.byType(DashButton),
        ),
      ),
    );
    expect(find.text(h.t('recipeBook.menuExcel')), findsOneWidget);
    await pickMenu(h, h.t('recipeBook.exportRecipes'));
    await h.settle();
    final tables = h.exports.built.single.allSheets.first as BlockSheetSpec;
    expect(tables.title, h.t('recipeBook.title'));
    expect(tables.rows.first.text, 'قهوة ساخنة');
    await h.flushTimers();
  });
}
