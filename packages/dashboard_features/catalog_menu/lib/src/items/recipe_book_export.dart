/// The recipe files (the web's `features/menu/recipe-book-export.ts`): fetch
/// the recipe book for the Items page's filters in ONE read, marked as an
/// export, and save it: the recipe workbook (with or without costs), or a
/// PDF or CSV of one of its sheets. The words and layout are
/// `recipe_book.dart`; the file is the shared engine's (`DashExporter`).
library;

import 'package:dashboard_api/dashboard_api.dart' show RecipeBook;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show publicBrandProvider;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'items_providers.dart' show CatalogQuery;
import 'recipe_book.dart';

/// Which file (`RecipeExportKind`).
enum RecipeExportKind {
  /// The tables with each size's cost, price and food cost.
  recipes,

  /// The same tables with no money at all.
  cards,
}

/// File names, as every export's: `<name>-<YYYY-MM-DD>.<ext>` (a PDF or CSV
/// of the lines adds the sheet's name: `Madar-Recipes-Ingredient-lines`).
const Map<RecipeExportKind, String> recipeExportFilenames = {
  RecipeExportKind.recipes: 'Madar-Recipes',
  RecipeExportKind.cards: 'Madar-Recipe-Cards',
};

/// The book's two sheets for the Export panel, in [recipeBookSheets]' order
/// (the web's `recipeBookSheetLabels`): the tables, which have no CSV, and
/// the flat ingredient lines.
List<DashExportSheet> recipeBookSheetLabels(Translator t) => [
  DashExportSheet(
    t('recipeBook.sheetTables', defaultValue: 'Recipe tables'),
    csv: false,
  ),
  DashExportSheet(t('recipeBook.linesSheet', defaultValue: 'Ingredient lines')),
];

/// Builds and saves [kind] for the page's [query] (its category, search and
/// recipe filter; the page is not walked: the book is one read), in the
/// format chosen in the Export panel: a PDF or CSV is the sheet [pick]
/// names. [meta] is the subtitle ([recipeBookMeta]). Toasts as every export
/// does: a failed read with its words, then "Gathering data…" turning into
/// "Exported N recipes" or "Export failed".
Future<void> exportRecipeBook(
  BuildContext context,
  WidgetRef ref, {
  required RecipeExportKind kind,
  required CatalogQuery query,
  String? meta,
  DashExportPick pick = const DashExportPick(),
}) async {
  final t = ref.read(tProvider);
  final api = apiWithHeaders(ref.read(transportProvider), exportRequestHeaders);
  final brand = ref.read(publicBrandProvider).value;
  final RecipeBook book;
  try {
    book = await api.recipes.getRecipeBook(
      orgId: query.orgId,
      categoryId: query.categoryId,
      search: query.search,
      hasRecipe: query.hasRecipe,
    );
  } on Object catch (e) {
    if (context.mounted) DashToast.error(context, errorMessage(e, t));
    return;
  }
  if (!context.mounted) return;
  final opts = RecipeBookOptions(costs: kind != RecipeExportKind.cards, t: t);
  final filename = recipeExportFilenames[kind]!;
  final config = ExcelConfig(
    filename: filename,
    meta: meta,
    logoUrl: exportLogoUrl(brand),
    sheets: recipeBookSheets(book, opts),
    doneMessage: t(
      'recipeBook.done',
      count: book.items.length,
      defaultValue: 'Exported {{count}} recipes',
    ),
  );
  if (config.sheets.every((s) => s.size == 0)) {
    DashToast.error(context, const ExportNothing().message(t));
    return;
  }
  final toast = DashToast.loading(context, t('excel.generating'));
  final exporter = ref.read(exporterProvider);
  final outcome = await exporter.exportFile(config, pick);
  toast.update(
    outcome is ExportDone ? DashToastKind.success : DashToastKind.error,
    outcome.message(t),
  );
}
