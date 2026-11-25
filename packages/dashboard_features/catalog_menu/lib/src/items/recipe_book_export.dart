/// The recipe files (the web's `features/menu/recipe-book-export.ts`): fetch
/// the recipe book for the Items page's filters in ONE read, marked as an
/// export, and save it: the recipe workbook (with or without costs) or its
/// CSV. The words and layout are `recipe_book.dart`; the file is the shared
/// engine's (`DashExporter`).
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

  /// The flat lines.
  csv,
}

/// File names, as every export's: `<name>-<YYYY-MM-DD>.<ext>`.
const Map<RecipeExportKind, String> recipeExportFilenames = {
  RecipeExportKind.recipes: 'Madar-Recipes',
  RecipeExportKind.cards: 'Madar-Recipe-Cards',
  RecipeExportKind.csv: 'Madar-Recipe-Lines',
};

/// Builds and saves [kind] for the page's [query] (its category, search and
/// recipe filter; the page is not walked: the book is one read). [meta] is
/// the subtitle ([recipeBookMeta]). Toasts as every export does: a failed
/// read with its words, then "Gathering data…" turning into "Exported N
/// recipes" (rows, for the CSV) or "Export failed".
Future<void> exportRecipeBook(
  BuildContext context,
  WidgetRef ref, {
  required RecipeExportKind kind,
  required CatalogQuery query,
  String? meta,
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
  final config = kind == RecipeExportKind.csv
      ? ExcelConfig(filename: filename, sheets: [recipeLinesSheet(book, opts)])
      : ExcelConfig(
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
  final outcome = kind == RecipeExportKind.csv
      ? await exporter.exportToCsv(config)
      : await exporter.exportToExcel(config);
  toast.update(
    outcome is ExportDone ? DashToastKind.success : DashToastKind.error,
    outcome.message(t),
  );
}
