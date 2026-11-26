// The Items page's Export panel (menu-items-page.tsx `handleRecipeExport`):
// the recipe files only with recipes.read, one book read with the page's own
// filters; Excel is the workbook, a PDF or CSV one sheet of it.
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

/// The Export button.
Finder get _trigger => inPage(
  find.descendant(
    of: find.byType(DashExportButton),
    matching: find.byType(DashButton),
  ),
);

/// Exports [file] in [format] (and [sheet], when the panel asks).
Future<void> _export(
  DashHarness h,
  String file, {
  String format = 'Excel',
  String? sheet,
}) async {
  await h.exportVia(format, null, file, sheet);
  await h.settle();
}

void main() {
  testWidgets('the recipe files are offered only with recipes.read', (
    tester,
  ) async {
    final h = await pumpItems(tester);
    await h.tap(_trigger);
    for (final word in [
      // The format at the top, as every Export panel.
      'Format',
      'Excel',
      'PDF',
      'CSV',
      'File',
      'Recipes with costs',
      'Recipe cards, no costs',
    ]) {
      expect(find.text(word), findsOneWidget, reason: word);
    }
    // "Menu" names the page's own file (the sidebar reads it too).
    expect(find.text('Menu'), findsWidgets);
    expect(find.text('Recipe lines (CSV)'), findsNothing);
    await h.flushTimers();
  });

  testWidgets('without recipes.read: one file, no file list', (tester) async {
    final h = await pumpItems(tester, persona: Persona.limited);
    final control = tester.widget<DashExportButton>(
      find.byType(DashExportButton),
    );
    expect(control.more, isEmpty);
    expect(control.fileLabel, isNull);
    expect(control.label, isNull);
    await h.tap(_trigger);
    expect(find.text('Format'), findsOneWidget);
    expect(find.text('File'), findsNothing);
    expect(find.text('Recipes with costs'), findsNothing);
    await h.tap(find.byKey(const ValueKey('export-download')));
    await h.settle();
    expect(h.files.saved.single.filename, startsWith('Madar-Menu-'));
    expect(callsOf(h, 'GET', _bookPath), isEmpty);
    await h.flushTimers();
  });

  testWidgets('Menu is the menu export, unchanged', (tester) async {
    final h = await pumpItems(tester);
    await _export(h, 'Menu');
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
    await _export(h, 'Recipes with costs');

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
    await _export(h, 'Recipe cards, no costs');
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

  testWidgets('Recipes as CSV: the ingredient lines, without asking (the '
      'tables have no CSV)', (tester) async {
    final h = await pumpItems(tester);
    await h.tap(_trigger);
    await pickMenu(h, 'Recipes with costs');
    await pickMenu(h, 'PDF');
    expect(find.text('Recipe tables'), findsOneWidget);
    await pickMenu(h, 'CSV');
    expect(find.text('Sheet'), findsNothing);
    await h.tap(find.byKey(const ValueKey('export-download')));
    await h.settle();
    expect(h.exports.built, isEmpty, reason: 'no workbook for a CSV');
    final saved = h.files.saved.single;
    expect(
      saved.filename,
      matches(
        RegExp(r'^Madar-Recipes-Ingredient-lines-\d{4}-\d{2}-\d{2}\.csv$'),
      ),
    );
    // UTF-8's mark first, so Excel opens Arabic as Arabic.
    expect(saved.bytes.take(3), [0xEF, 0xBB, 0xBF]);
    expect(
      saved.asString.split('\r\n').first,
      'Category,Item,Size,Ingredient,From,Quantity,Unit,Line cost',
    );
    await h.flushTimers();
  });

  testWidgets('Recipes as PDF: the sheet picked, the tables or the lines', (
    tester,
  ) async {
    final h = await pumpItems(tester);
    await _export(
      h,
      'Recipes with costs',
      format: 'PDF',
      sheet: 'Ingredient lines',
    );
    final printed = h.server.callsTo('/exports/pdf', method: 'POST').single;
    final body = printed.body! as Map;
    expect((body['sheets'] as List).single['title'], 'Ingredient lines');
    expect(
      h.files.saved.single.filename,
      matches(
        RegExp(r'^Madar-Recipes-Ingredient-lines-\d{4}-\d{2}-\d{2}\.pdf$'),
      ),
    );
    await h.flushTimers();
    await _export(
      h,
      'Recipes with costs',
      format: 'PDF',
      sheet: 'Recipe tables',
    );
    final tables = h.server.callsTo('/exports/pdf', method: 'POST').last;
    expect(
      ((tables.body! as Map)['sheets'] as List).single['title'],
      'Recipes',
    );
    expect(
      h.files.saved.last.filename,
      matches(RegExp(r'^Madar-Recipes-\d{4}-\d{2}-\d{2}\.pdf$')),
    );
    await h.flushTimers();
  });

  testWidgets('the menu as CSV asks which sheet', (tester) async {
    final h = await pumpItems(tester);
    await _export(h, 'Menu', format: 'CSV', sheet: 'Categories');
    final saved = h.files.saved.single;
    expect(
      saved.filename,
      matches(RegExp(r'^Madar-Menu-Categories-\d{4}-\d{2}-\d{2}\.csv$')),
    );
    expect(saved.bytes.take(3), [0xEF, 0xBB, 0xBF]);
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
    await _export(h, 'Recipes with costs');
    await h.expectToast(
      'That is 6000 items, and a recipe book holds at most 5000. '
      'Pick a category or search, and try again.',
    );
    expect(h.exports.built, isEmpty);
    expect(h.files.saved, isEmpty);
  });

  testWidgets('in Arabic: the menu and the book in Arabic', (tester) async {
    final h = await pumpItems(tester, locale: 'ar');
    await h.tap(_trigger);
    // "القائمة" names the page too: the panel's own file.
    expect(find.text(h.t('common.exportFormat.file')), findsOneWidget);
    expect(find.text(h.t('recipeBook.menuFile')), findsWidgets);
    await pickMenu(h, h.t('recipeBook.exportRecipes'));
    await h.tap(find.byKey(const ValueKey('export-download')));
    await h.settle();
    final tables = h.exports.built.single.allSheets.first as BlockSheetSpec;
    expect(tables.title, h.t('recipeBook.title'));
    expect(tables.rows.first.text, 'قهوة ساخنة');
    await h.flushTimers();
  });
}
