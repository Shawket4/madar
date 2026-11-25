/// The recipe export: every drink's recipe as its own table (the web's
/// `features/menu/recipe-book.ts`).
///
/// The data is ONE read, `GET /recipes/book`, which hands back each item
/// already laid out (sizes as columns, ingredients as rows in the Studio
/// grid's order, each size's cost and food cost from the server's own cost
/// math). This file only decides the words and the layout; the file is drawn
/// by the shared export engine (dashboard_core's `DashExporter`, the core's
/// xlsx writer), so the recipe book wears the same banner, palette and bands
/// as every other export. No figure is worked out here: a cost, a price and a
/// food cost are printed as the server sent them.
///
/// Two workbooks and a CSV come out of one book:
/// - **Recipes**: the tables with each size's cost, price and food cost under
///   them, plus an "Ingredient lines" sheet with every line's cost.
/// - **Recipe cards** (`costs: false`): the same tables with no money at all,
///   for printing at the bar.
/// - **CSV**: the "Ingredient lines" sheet alone, one row per item, size and
///   ingredient.
library;

import 'dart:math' as math;

import 'package:dashboard_api/dashboard_api.dart'
    show RecipeBook, RecipeCard, RecipeCardRow, RecipeCardSize, RecipeCardStep;
import 'package:dashboard_core/dashboard_core.dart';

import '../shared/menu_text.dart';
import 'items_data.dart' show RecipeFilter;

/// `RecipeBookOptions`; the language is [t]'s.
class RecipeBookOptions {
  const RecipeBookOptions({required this.costs, required this.t});

  /// With each size's cost, price and food cost, and each line's cost.
  final bool costs;
  final Translator t;

  String get lang => t.lang;
}

/// One line of the flat sheet (and the CSV).
class RecipeLine {
  const RecipeLine({
    required this.category,
    required this.item,
    required this.size,
    required this.ingredient,
    required this.from,
    required this.quantity,
    required this.unit,
    required this.lineCost,
  });

  final String category;
  final String item;
  final String size;
  final String ingredient;
  final String from;
  final double? quantity;
  final String unit;

  /// Piastres, as the server sent it; null = unknown.
  final int? lineCost;
}

/// Width of the label column, the unit column and each size column.
const double _labelWidth = 34;
const double _unitWidth = 9;
const double _sizeWidth = 15;

/// An item has a recipe to print when it has a line or a step.
bool _hasRecipe(RecipeCard card) =>
    card.rows.isNotEmpty || card.steps.isNotEmpty;

/// `sizeLabel`: the `one_size` sentinel reads "One size".
String recipeSizeLabel(RecipeCardSize s, Translator t) =>
    sizeLabelText(s.label, t('recipes.oneSize', defaultValue: 'One size'));

/// A size's column header: its label, and that it is off the menu when it is.
String _sizeHeader(RecipeCardSize s, Translator t) => s.isActive
    ? recipeSizeLabel(s, t)
    : '${recipeSizeLabel(s, t)} (${t('recipeBook.off', defaultValue: 'off')})';

/// Where a row came from, in words: the item itself says nothing.
String _fromLabel(String source, Translator t) => switch (source) {
  'base' => t('recipeBook.from.base', defaultValue: 'Recipe base'),
  'rule' => t('recipeBook.from.rule', defaultValue: 'Packaging rule'),
  'linked' => t('recipeBook.from.linked', defaultValue: 'Linked recipe'),
  _ => t('recipeBook.from.own', defaultValue: 'This item'),
};

/// A row's label in a table: a base's or a rule's line says so.
String _rowLabel(RecipeCardRow row, Translator t) =>
    row.source == 'base' || row.source == 'rule'
    ? '${row.ingredientName} (${_fromLabel(row.source, t)})'
    : row.ingredientName;

/// The words after an item's name: whose recipe it follows, that it is off
/// the menu.
String? _itemNote(RecipeCard card, Translator t) {
  final follows = _text(card.followsItemName);
  final parts = [
    if (follows != null)
      t(
        'recipeBook.follows',
        args: {'name': follows},
        defaultValue: 'Follows {{name}}',
      ),
    if (!card.isActive) t('common.inactive', defaultValue: 'Inactive'),
  ];
  return parts.isEmpty ? null : parts.join('  ·  ');
}

/// [text] unless it is null or empty (JavaScript's falsy string).
String? _text(String? text) => text == null || text.isEmpty ? null : text;

/// One step's line: its number, its name in the export's language (else the
/// other's), and its note after a dash.
String _stepLine(int index, RecipeCardStep s, bool ar) {
  final name = _text(ar ? s.nameAr : s.name) ?? _text(s.name) ?? s.nameAr;
  final note = _text(ar ? (s.noteAr ?? s.note) : (s.note ?? s.noteAr));
  return note == null ? '${index + 1}. $name' : '${index + 1}. $name — $note';
}

/// How it's made, one step a line, in the export's language.
String? _stepsCaption(RecipeCard card, String lang, Translator t) {
  if (card.steps.isEmpty) return null;
  final ar = lang.startsWith('ar');
  return [
    t('recipeBook.howItsMade', defaultValue: "How it's made"),
    for (final (i, s) in card.steps.indexed) _stepLine(i, s, ar),
  ].join('\n');
}

/// The money under a table: cost, price and food cost per size, as the
/// server sent them.
List<List<Object?>> _costFooter(RecipeCard card, Translator t) {
  final cost = <Object?>[t('recipeBook.cost', defaultValue: 'Cost'), null];
  final price = <Object?>[t('common.price', defaultValue: 'Price'), null];
  final food = <Object?>[
    t('recipeBook.foodCost', defaultValue: 'Food cost'),
    null,
  ];
  for (final s in card.sizes) {
    // A partial cost is still the sum of what is known; the food cost row
    // says it is partial.
    final c = s.costPiastres;
    cost.add(c == null ? '—' : ExcelCell(c, ExcelColumnType.money));
    price.add(ExcelCell(s.price, ExcelColumnType.money));
    final pct = s.foodCostPct;
    food.add(
      pct != null
          ? ExcelCell(pct, ExcelColumnType.percent)
          : s.costIncomplete
          ? t('recipeBook.missingCosts', defaultValue: 'Missing costs')
          : '—',
    );
  }
  return [cost, price, food];
}

/// One item's table.
ExcelBlock recipeBlock(RecipeCard card, RecipeBookOptions o) {
  final t = o.t;
  return ExcelBlock(
    title: translatedName(card.name, card.nameTranslations, o.lang),
    note: _itemNote(card, t),
    header: card.rows.isEmpty
        ? const []
        : [
            t('recipeBook.ingredient', defaultValue: 'Ingredient'),
            t('recipeBook.unit', defaultValue: 'Unit'),
            for (final s in card.sizes) _sizeHeader(s, t),
          ],
    rows: [
      for (final row in card.rows)
        [
          _rowLabel(row, t),
          unitWord(t, row.unit),
          for (final c in row.cells)
            c.quantity == null
                ? null
                : ExcelCell(c.quantity, ExcelColumnType.quantity),
        ],
    ],
    footer: o.costs && card.rows.isNotEmpty ? _costFooter(card, t) : null,
    caption: _stepsCaption(card, o.lang, t),
  );
}

/// The flat sheet: every item × size × ingredient, in the book's order.
ExcelSheet<RecipeLine> recipeLinesSheet(RecipeBook book, RecipeBookOptions o) {
  final t = o.t;
  final categoryName = {
    for (final c in book.categories)
      c.id: translatedName(c.name, c.nameTranslations, o.lang),
  };
  final uncategorised = t('menu.uncategorised', defaultValue: 'Uncategorised');
  final rows = <RecipeLine>[];
  for (final card in book.items) {
    final item = translatedName(card.name, card.nameTranslations, o.lang);
    final category = _text(categoryName[card.categoryId]) ?? uncategorised;
    for (final (col, size) in card.sizes.indexed) {
      for (final row in card.rows) {
        final cell = col < row.cells.length ? row.cells[col] : null;
        final quantity = cell?.quantity;
        if (quantity == null) continue;
        rows.add(
          RecipeLine(
            category: category,
            item: item,
            size: recipeSizeLabel(size, t),
            ingredient: row.ingredientName,
            from: _fromLabel(row.source, t),
            quantity: quantity,
            unit: unitWord(t, row.unit),
            lineCost: cell?.lineCostPiastres,
          ),
        );
      }
    }
  }
  return ExcelSheet<RecipeLine>(
    name: t('recipeBook.linesSheet', defaultValue: 'Ingredient lines'),
    title: t('recipeBook.linesTitle', defaultValue: 'Ingredient lines'),
    rows: rows,
    columns: [
      ExcelColumn(
        header: t('common.category', defaultValue: 'Category'),
        accessor: (r) => r.category,
        type: ExcelColumnType.text,
        width: 20,
      ),
      ExcelColumn(
        header: t('recipeBook.item', defaultValue: 'Item'),
        accessor: (r) => r.item,
        type: ExcelColumnType.text,
        width: 26,
      ),
      ExcelColumn(
        header: t('recipeBook.size', defaultValue: 'Size'),
        accessor: (r) => r.size,
        type: ExcelColumnType.text,
        width: 14,
      ),
      ExcelColumn(
        header: t('recipeBook.ingredient', defaultValue: 'Ingredient'),
        accessor: (r) => r.ingredient,
        type: ExcelColumnType.text,
        width: 26,
      ),
      ExcelColumn(
        header: t('recipeBook.fromHeader', defaultValue: 'From'),
        accessor: (r) => r.from,
        type: ExcelColumnType.text,
        width: 16,
      ),
      ExcelColumn(
        header: t('recipeBook.quantity', defaultValue: 'Quantity'),
        accessor: (r) => r.quantity,
        type: ExcelColumnType.quantity,
        width: 12,
      ),
      ExcelColumn(
        header: t('recipeBook.unit', defaultValue: 'Unit'),
        accessor: (r) => r.unit,
        type: ExcelColumnType.text,
        width: 9,
      ),
      if (o.costs)
        ExcelColumn(
          header: t('recipeBook.lineCost', defaultValue: 'Line cost'),
          accessor: (r) => r.lineCost,
          type: ExcelColumnType.money,
          width: 14,
        ),
    ],
  );
}

/// The recipe workbook's sheets: the tables, then the flat lines.
List<AnyExcelSheet> recipeBookSheets(RecipeBook book, RecipeBookOptions o) {
  final t = o.t;
  String name(String n, Object? tr) => translatedName(n, tr, o.lang);
  final withRecipe = book.items.where(_hasRecipe).toList();
  final without = book.items.where((c) => !_hasRecipe(c)).toList();
  final categoryName = {
    for (final c in book.categories) c.id: name(c.name, c.nameTranslations),
  };

  // Categories in menu order, then the uncategorised, as the server sorts.
  final byCategory = <String?, List<ExcelBlock>>{};
  for (final card in withRecipe) {
    (byCategory[card.categoryId] ??= []).add(recipeBlock(card, o));
  }
  final groups = <ExcelGroup>[
    for (final c in book.categories)
      if (byCategory[c.id] case final blocks?)
        ExcelGroup(group: name(c.name, c.nameTranslations), blocks: blocks),
    if (byCategory[null] case final loose?)
      ExcelGroup(
        group: t('menu.uncategorised', defaultValue: 'Uncategorised'),
        blocks: loose,
      ),
    // Items still without a recipe are a list at the end, not a page of
    // empty tables.
    if (without.isNotEmpty)
      ExcelGroup(
        group: t('recipeBook.noRecipe', defaultValue: 'No recipe yet'),
        blocks: [
          ExcelBlock(
            title: t(
              'recipeBook.noRecipeTitle',
              count: without.length,
              defaultValue: '{{count}} items',
            ),
            header: [t('recipeBook.item', defaultValue: 'Item')],
            rows: [
              for (final c in without)
                [
                  switch (_text(categoryName[c.categoryId])) {
                    final cat? =>
                      '${name(c.name, c.nameTranslations)}  ·  $cat',
                    null => name(c.name, c.nameTranslations),
                  },
                ],
            ],
          ),
        ],
      ),
  ];

  final maxSizes = withRecipe.fold(1, (n, c) => math.max(n, c.sizes.length));
  final stats = [
    ExcelStat(
      label: t('recipeBook.stats.items', defaultValue: 'Items'),
      value: book.items.length,
      type: 'number',
    ),
    ExcelStat(
      label: t('recipeBook.stats.withRecipe', defaultValue: 'With a recipe'),
      value: withRecipe.length,
      type: 'number',
    ),
    ExcelStat(
      label: t('recipeBook.stats.noRecipe', defaultValue: 'No recipe yet'),
      value: without.length,
      type: 'number',
    ),
    if (o.costs)
      ExcelStat(
        label: t(
          'recipeBook.stats.missingCosts',
          defaultValue: 'Sizes missing costs',
        ),
        value: withRecipe.fold<int>(
          0,
          (n, c) => n + c.sizes.where((s) => s.costIncomplete).length,
        ),
        type: 'number',
      ),
  ];

  final title = o.costs
      ? t('recipeBook.title', defaultValue: 'Recipes')
      : t('recipeBook.cardsTitle', defaultValue: 'Recipe cards');
  return [
    ExcelBlockSheet(
      name: title,
      title: title,
      stats: stats,
      widths: [
        _labelWidth,
        _unitWidth,
        for (var i = 0; i < maxSizes; i++) _sizeWidth,
      ],
      groups: groups,
    ),
    recipeLinesSheet(book, o),
  ];
}

/// The subtitle line: what the Items page was filtered to.
String? recipeBookMeta(
  Translator t, {
  String? category,
  String? search,
  RecipeFilter recipe = RecipeFilter.all,
}) {
  final parts = [
    if (category != null && category.isNotEmpty) category,
    if (search != null && search.isNotEmpty) '“$search”',
    if (recipe == RecipeFilter.has)
      t('menu.recipeHas', defaultValue: 'Has a recipe')
    else if (recipe == RecipeFilter.missing)
      t('menu.recipeMissing', defaultValue: 'No recipe'),
  ];
  return parts.isEmpty ? null : parts.join('  ·  ');
}
