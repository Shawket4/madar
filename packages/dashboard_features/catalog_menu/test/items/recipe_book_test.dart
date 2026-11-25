// The recipe export's words and layout (the web's recipe-book.test.ts), in
// both languages through the synced tables.
import 'dart:io';

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_catalog_menu/src/items/items_data.dart';
import 'package:dashboard_catalog_menu/src/items/recipe_book.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// The core tables, as the app loads them.
Strings _strings() => Strings({
  for (final lang in supportedLanguages)
    lang: parseStringTable(
      File('../../dashboard_core/assets/i18n/$lang.json').readAsStringSync(),
    ),
});

const _coffee = 'c-coffee';

RecipeCard _card({
  String id = 'i-latte',
  String name = 'Latte',
  Object? translations = const {'ar': 'لاتيه'},
  String? categoryId = _coffee,
  bool isActive = true,
  String? follows,
  List<RecipeCardSize> sizes = _latteSizes,
  List<RecipeCardRow> rows = _latteRows,
  List<RecipeCardStep> steps = _latteSteps,
}) => RecipeCard(
  menuItemId: id,
  name: name,
  nameTranslations: translations,
  categoryId: categoryId,
  isActive: isActive,
  followsItemName: follows,
  sizes: sizes,
  rows: rows,
  steps: steps,
);

const _latteSizes = [
  RecipeCardSize(
    sizeId: 's1',
    label: 'Small',
    price: 4000,
    isActive: true,
    costPiastres: 205,
    costIncomplete: false,
    foodCostPct: 0.05125,
    marginPct: 0.94875,
  ),
  RecipeCardSize(
    sizeId: 's2',
    label: 'Large',
    price: 5000,
    isActive: false,
    costPiastres: 285,
    costIncomplete: true,
  ),
];

const _latteRows = [
  RecipeCardRow(
    ingredientId: 'g1',
    ingredientName: 'Espresso beans',
    unit: 'g',
    source: 'own',
    cells: [
      RecipeCardCell(quantity: 18, lineCostPiastres: 45),
      RecipeCardCell(quantity: 18, lineCostPiastres: 45),
    ],
  ),
  RecipeCardRow(
    ingredientId: 'g2',
    ingredientName: 'Vanilla syrup',
    unit: 'ml',
    source: 'own',
    cells: [RecipeCardCell(), RecipeCardCell(quantity: 20)],
  ),
  RecipeCardRow(
    ingredientId: 'g3',
    ingredientName: 'Cup',
    unit: 'pcs',
    source: 'rule',
    cells: [
      RecipeCardCell(quantity: 1, lineCostPiastres: 150),
      RecipeCardCell(quantity: 1, lineCostPiastres: 150),
    ],
  ),
];

const _latteSteps = [
  RecipeCardStep(
    position: 1,
    name: 'Pull a double shot',
    nameAr: 'استخلص جرعتين',
  ),
  RecipeCardStep(
    position: 2,
    name: 'Steam the milk',
    nameAr: 'بخّر الحليب',
    note: 'To 60 °C',
    noteAr: 'حتى 60 °م',
  ),
];

final _latte = _card();

final _water = _card(
  id: 'i-water',
  name: 'Water',
  translations: const <String, Object?>{},
  categoryId: null,
  sizes: const [
    RecipeCardSize(
      sizeId: 's3',
      label: 'one_size',
      price: 1000,
      isActive: true,
      costIncomplete: false,
    ),
  ],
  rows: const [],
  steps: const [],
);

final _book = RecipeBook(
  categories: const [
    RecipeBookCategory(
      id: _coffee,
      name: 'Coffee',
      nameTranslations: {'ar': 'قهوة'},
    ),
  ],
  items: [_latte, _water],
);

void main() {
  final strings = _strings();
  final en = Translator(strings, 'en');
  final ar = Translator(strings, 'ar');
  final opts = RecipeBookOptions(costs: true, t: en);
  const quantity = ExcelColumnType.quantity;
  const money = ExcelColumnType.money;

  group("a drink's table", () {
    test('has a column per size, a row per ingredient, the steps under it', () {
      final b = recipeBlock(_latte, opts);
      expect(b.title, 'Latte');
      expect(b.header, ['Ingredient', 'Unit', 'Small', 'Large (off)']);
      expect(b.rows[0], [
        'Espresso beans',
        'g',
        const ExcelCell(18, quantity),
        const ExcelCell(18, quantity),
      ]);
      expect(b.rows[1][2], isNull, reason: 'no vanilla in the small one');
      expect(b.rows[2][0], 'Cup (Packaging rule)');
      expect(
        b.caption,
        "How it's made\n1. Pull a double shot\n2. Steam the milk — To 60 °C",
      );
    });

    test('puts cost, price and food cost under it, and never grades a '
        'partial cost', () {
      final [cost, price, food] = recipeBlock(_latte, opts).footer!;
      expect(cost, [
        'Cost',
        null,
        const ExcelCell(205, money),
        const ExcelCell(285, money),
      ]);
      expect(price, [
        'Price',
        null,
        const ExcelCell(4000, money),
        const ExcelCell(5000, money),
      ]);
      expect(food, [
        'Food cost',
        null,
        const ExcelCell(0.05125, ExcelColumnType.percent),
        'Missing costs',
      ]);
    });

    test('an unknown cost is a dash, never 0', () {
      final [cost, _, food] = recipeBlock(
        _card(
          sizes: const [
            RecipeCardSize(
              sizeId: 's1',
              label: 'Small',
              price: 4000,
              isActive: true,
              costIncomplete: false,
            ),
          ],
          rows: [
            RecipeCardRow(
              ingredientId: 'g1',
              ingredientName: 'Espresso beans',
              unit: 'g',
              source: 'own',
              cells: const [RecipeCardCell(quantity: 18)],
            ),
          ],
        ),
        opts,
      ).footer!;
      expect(cost, ['Cost', null, '—']);
      expect(food, ['Food cost', null, '—']);
    });

    test('carries no money at all on a recipe card', () {
      final cards = RecipeBookOptions(costs: false, t: en);
      expect(recipeBlock(_latte, cards).footer, isNull);
      final lines = recipeLinesSheet(_book, cards);
      expect(lines.columns.map((c) => c.header), isNot(contains('Line cost')));
    });

    test('reads in Arabic when the dashboard does', () {
      final b = recipeBlock(_latte, RecipeBookOptions(costs: true, t: ar));
      expect(b.title, 'لاتيه');
      expect(
        b.caption,
        '${ar('recipeBook.howItsMade')}\n'
        '1. استخلص جرعتين\n'
        '2. بخّر الحليب — حتى 60 °م',
      );
      expect(b.header, [
        ar('recipeBook.ingredient'),
        ar('recipeBook.unit'),
        'Small',
        'Large (${ar('recipeBook.off')})',
      ]);
      expect(b.rows[0][1], ar('units.g'));
    });

    test('says whose recipe a linked copy follows, and that an item is off '
        'the menu', () {
      final b = recipeBlock(
        _card(follows: 'Flat white', isActive: false),
        opts,
      );
      expect(b.note, 'Follows Flat white  ·  Inactive');
      expect(recipeBlock(_latte, opts).note, isNull);
    });

    test('a step with only the other language still has a name', () {
      final b = recipeBlock(
        _card(
          steps: const [
            RecipeCardStep(position: 1, name: '', nameAr: 'اخفق'),
            RecipeCardStep(position: 2, name: 'Pour', nameAr: '', note: ''),
          ],
        ),
        opts,
      );
      expect(b.caption, "How it's made\n1. اخفق\n2. Pour");
    });
  });

  group('the recipe workbook', () {
    test('groups the tables by category, and lists the items with no recipe '
        'at the end', () {
      final [tables, lines] = recipeBookSheets(_book, opts);
      final sheet = tables as ExcelBlockSheet;
      expect(sheet.name, 'Recipes');
      expect(sheet.groups.map((g) => g.group), ['Coffee', 'No recipe yet']);
      expect(sheet.groups[0].blocks.map((b) => b.title), ['Latte']);
      expect(sheet.groups[1].blocks[0].title, '1 item');
      expect(sheet.groups[1].blocks[0].header, ['Item']);
      expect(sheet.groups[1].blocks[0].rows, [
        ['Water'],
      ]);
      // Label, unit, then the widest item's sizes.
      expect(sheet.widths, [34, 9, 15, 15]);
      expect(sheet.stats.map((s) => s.label), [
        'Items',
        'With a recipe',
        'No recipe yet',
        'Sizes missing costs',
      ]);
      expect(sheet.stats.map((s) => s.value), [2, 1, 1, 1]);
      expect(sheet.stats.map((s) => s.type), everyElement('number'));
      // 2 small + 3 large lines.
      expect((lines as ExcelSheet<Object?>).rows, hasLength(5));
      expect(lines.name, 'Ingredient lines');
    });

    test('a recipe card book: its own title, no money pill', () {
      final [tables, _] = recipeBookSheets(
        _book,
        RecipeBookOptions(costs: false, t: en),
      );
      final sheet = tables as ExcelBlockSheet;
      expect(sheet.title, 'Recipe cards');
      expect(sheet.stats, hasLength(3));
    });

    test('files an uncategorised drink under Uncategorised, after the '
        'categories', () {
      final loose = _card(id: 'i-2', name: 'Cold brew', categoryId: null);
      final [tables, _] = recipeBookSheets(
        RecipeBook(categories: _book.categories, items: [_latte, loose]),
        opts,
      );
      expect((tables as ExcelBlockSheet).groups.map((g) => g.group), [
        'Coffee',
        'Uncategorised',
      ]);
    });

    test('an item with no recipe names its category in the list', () {
      final plain = _card(
        id: 'i-3',
        name: 'Tonic',
        translations: const <String, Object?>{},
        rows: [],
        steps: [],
      );
      final [tables, _] = recipeBookSheets(
        RecipeBook(categories: _book.categories, items: [plain, _water]),
        RecipeBookOptions(costs: true, t: ar),
      );
      final sheet = tables as ExcelBlockSheet;
      expect(sheet.groups.single.group, ar('recipeBook.noRecipe'));
      expect(sheet.groups.single.blocks.single.rows, [
        ['Tonic  ·  قهوة'],
        ['Water'],
      ]);
      expect(sheet.groups.single.blocks.single.title, 'صنفان');
      expect(sheet.widths, [34, 9, 15], reason: 'one size column at least');
    });

    test('names the one-size column', () {
      final tea = _card(
        sizes: _water.sizes,
        rows: const [
          RecipeCardRow(
            ingredientId: 't',
            ingredientName: 'Tea',
            unit: 'g',
            source: 'own',
            cells: [RecipeCardCell(quantity: 3, lineCostPiastres: 30)],
          ),
        ],
      );
      expect(recipeBlock(tea, opts).header, ['Ingredient', 'Unit', 'One size']);
    });
  });

  group('the flat lines', () {
    test('is one row per item, size and ingredient a size actually has', () {
      final sheet = recipeLinesSheet(_book, opts);
      expect(sheet.rawRows(), [
        [
          'Coffee',
          'Latte',
          'Small',
          'Espresso beans',
          'This item',
          18,
          'g',
          45,
        ],
        ['Coffee', 'Latte', 'Small', 'Cup', 'Packaging rule', 1, 'pcs', 150],
        [
          'Coffee',
          'Latte',
          'Large',
          'Espresso beans',
          'This item',
          18,
          'g',
          45,
        ],
        [
          'Coffee',
          'Latte',
          'Large',
          'Vanilla syrup',
          'This item',
          20,
          'ml',
          null,
        ],
        ['Coffee', 'Latte', 'Large', 'Cup', 'Packaging rule', 1, 'pcs', 150],
      ]);
      expect(sheet.columnTypes, [
        ExcelColumnType.text,
        ExcelColumnType.text,
        ExcelColumnType.text,
        ExcelColumnType.text,
        ExcelColumnType.text,
        quantity,
        ExcelColumnType.text,
        money,
      ]);
      expect(sheet.columns.map((c) => c.width), [
        20,
        26,
        14,
        26,
        16,
        12,
        9,
        14,
      ]);
    });
  });

  group('the subtitle', () {
    test('says what the Items page was filtered to', () {
      expect(
        recipeBookMeta(
          en,
          category: 'Coffee',
          search: 'iced',
          recipe: RecipeFilter.has,
        ),
        'Coffee  ·  “iced”  ·  Has a recipe',
      );
      expect(recipeBookMeta(en, recipe: RecipeFilter.missing), 'No recipe');
      expect(recipeBookMeta(en, recipe: RecipeFilter.all), isNull);
      expect(recipeBookMeta(en, search: ''), isNull);
    });
  });
}
