// The recipe builder's arithmetic and the create-ingredient dialog's
// conversions, checked by hand against the web's `recipe-builder.tsx` and
// `create-ingredient-dialog.tsx`.
import 'package:dashboard_api/dashboard_api.dart' show IngredientCategory;
import 'package:dashboard_catalog_menu/src/recipes/create_ingredient_dialog.dart';
import 'package:dashboard_catalog_menu/src/recipes/recipe_model.dart';
import 'package:flutter_test/flutter_test.dart';

var _id = 0;

RecipeDraftRow row(
  String size,
  String name,
  String qty, {
  String? id,
  String unit = 'g',
}) => RecipeDraftRow(
  id: _id++,
  sizeLabel: size,
  orgIngredientId: id,
  ingredientName: name,
  ingredientUnit: unit,
  quantity: qty,
);

IngredientCategory cat(String id, String slug) => IngredientCategory(
  createdAt: DateTime.utc(2026),
  id: id,
  ingredientCount: 0,
  isPackaging: false,
  name: slug,
  orgId: 'org',
  slug: slug,
  sortOrder: 0,
  updatedAt: DateTime.utc(2026),
);

void main() {
  test('MENU-RCP-001 the seed key: size::name=qty, sorted; id and unit are '
      'not part of it', () {
    final a = recipeSeedKey([
      (sizeLabel: 'Large', ingredientName: 'Milk', quantityUsed: 240),
      (sizeLabel: 'Regular', ingredientName: 'Beans', quantityUsed: 18.5),
    ]);
    expect(a, 'Large::Milk=240|Regular::Beans=18.5');
    final reordered = recipeSeedKey([
      (sizeLabel: 'Regular', ingredientName: 'Beans', quantityUsed: 18.5),
      (sizeLabel: 'Large', ingredientName: 'Milk', quantityUsed: 240),
    ]);
    expect(reordered, a);
    expect(
      recipeSeedKey([
        (sizeLabel: 'Large', ingredientName: 'Milk', quantityUsed: 250),
        (sizeLabel: 'Regular', ingredientName: 'Beans', quantityUsed: 18.5),
      ]),
      isNot(a),
    );
  });

  test('MENU-RCP-014 rows that count: a name and a finite quantity > 0', () {
    final clean = cleanRecipeRows([
      row('Regular', 'Beans', '18'),
      row('Regular', '', '5'),
      row('Regular', 'Milk', ''),
      row('Regular', 'Sugar', '0'),
      row('Regular', 'Ice', '.'),
      row('Regular', 'Syrup', '12.5'),
    ]);
    expect(
      [for (final c in clean) (c.ingredientName, c.quantityUsed)],
      [('Beans', 18.0), ('Syrup', 12.5)],
    );
  });

  test('the standalone save lists initial rows no longer kept', () {
    final removed = removedRecipeRows([
      (sizeLabel: 'one_size', ingredientName: 'Beans'),
      (sizeLabel: 'one_size', ingredientName: 'Milk'),
    ], cleanRecipeRows([row('one_size', 'Beans', '20')]));
    expect(removed, [(sizeLabel: 'one_size', ingredientName: 'Milk')]);
  });

  test('MENU-RCP-007 a size costs Σ unit cost × qty; any unknown cost or '
      'quantity makes it unknown; no rows is unknown', () {
    double? cost(String? id) => switch (id) {
      'beans' => 95,
      'milk' => 4.2,
      _ => null,
    };
    // 18 g × 95 + 180 ml × 4.2 = 1710 + 756.
    expect(
      recipeSizeEstimate([
        row('Regular', 'Beans', '18', id: 'beans'),
        row('Regular', 'Milk', '180', id: 'milk'),
      ], cost),
      closeTo(2466, 1e-9),
    );
    expect(
      recipeSizeEstimate([
        row('Regular', 'Beans', '18', id: 'beans'),
        row('Regular', 'Pistachio', '15', id: 'pistachio'),
      ], cost),
      isNull,
    );
    expect(
      recipeSizeEstimate([row('Regular', 'Beans', '', id: 'beans')], cost),
      isNull,
    );
    expect(recipeSizeEstimate([], cost), isNull);
  });

  test('MENU-RCP-011 a line costs unit cost × qty, else unknown', () {
    expect(recipeLineCost(95, '18'), 1710);
    expect(recipeLineCost(null, '18'), isNull);
    expect(recipeLineCost(95, ''), isNull);
  });

  test(
    'MENU-RCP-008 margin = (price − cost) / price; tones at 60 % / 30 %',
    () {
      expect(recipeMargin(2466, 11500), closeTo(0.78557, 1e-5));
      expect(recipeMargin(null, 11500), isNull);
      expect(recipeMargin(2466, 0), isNull);
      expect(recipeMargin(2466, null), isNull);
      expect(recipeMarginTone(0.6), RecipeMarginTone.good);
      expect(recipeMarginTone(0.5999), RecipeMarginTone.fair);
      expect(recipeMarginTone(0.3), RecipeMarginTone.fair);
      expect(recipeMarginTone(0.2999), RecipeMarginTone.low);
      expect(recipeMarginTone(-0.5), RecipeMarginTone.low);
    },
  );

  test('MENU-RCP-005 scaling: base rows × factor (3 dp); untouched = × 1; '
      'a cleared or zero factor keeps that size as it was', () {
    var next = 1000;
    final rows = [
      row('Small', 'Beans', '14', id: 'beans'),
      row('Small', 'Milk', '150', id: 'milk', unit: 'ml'),
      row('Small', 'Sugar', ''),
      row('Medium', 'Old', '1'),
      row('Large', 'Kept', '2'),
      row('Double', 'Kept too', '3'),
    ];
    final out = scaleRecipeRows(
      rows,
      ['Small', 'Medium', 'Large', 'Double'],
      {'Large': '1.333', 'Double': ''},
      () => next++,
    );
    String show(RecipeDraftRow r) =>
        '${r.sizeLabel}:${r.ingredientName}=${r.quantity}';
    expect(out.map(show), [
      'Small:Beans=14',
      'Small:Milk=150',
      'Small:Sugar=',
      'Double:Kept too=3',
      'Medium:Beans=14',
      'Medium:Milk=150',
      'Medium:Sugar=',
      'Large:Beans=18.662',
      'Large:Milk=199.95',
      'Large:Sugar=',
    ]);
    // New rows get new ids; their unit and ingredient follow the base row.
    final large = out.where((r) => r.sizeLabel == 'Large').toList();
    expect(large.map((r) => r.id), everyElement(greaterThanOrEqualTo(1000)));
    expect(large[1].ingredientUnit, 'ml');
    expect(large[1].orgIngredientId, 'milk');
    // Zero is no factor either.
    final zero = scaleRecipeRows(
      rows,
      ['Small', 'Large'],
      {'Large': '0'},
      () => next++,
    );
    expect(zero.where((r) => r.sizeLabel == 'Large').map(show), [
      'Large:Kept=2',
    ]);
  });

  test('dirty: the rows differ from the baseline (order counts)', () {
    final a = row('one_size', 'Beans', '18');
    final b = row('one_size', 'Milk', '20');
    expect(recipeRowsDiffer([a, b], [a, b]), isFalse);
    expect(recipeRowsDiffer([a, b], [b, a]), isTrue);
    expect(recipeRowsDiffer([a], [a, b]), isTrue);
    expect(recipeRowsDiffer([a.copyWith(quantity: '19')], [a]), isTrue);
    expect(recipeRowsDiffer([a.copyWith(id: 99)], [a]), isFalse);
  });

  test('MENU-RCP-019 the default category: general, else the first', () {
    expect(
      defaultIngredientCategory([cat('a', 'milk'), cat('b', 'general')])?.id,
      'b',
    );
    expect(defaultIngredientCategory([cat('a', 'milk')])?.id, 'a');
    expect(defaultIngredientCategory([]), isNull);
  });

  test('MENU-RCP-021 the cost box: pounds to piastres; blank is unknown', () {
    expect(ingredientCostPiastres(''), isNull);
    expect(ingredientCostPiastres('   '), isNull);
    expect(ingredientCostPiastres('.'), isNull);
    expect(ingredientCostPiastres('0.95'), 95);
    expect(ingredientCostPiastres('18'), 1800);
    // Whole piastres, as everywhere on the web (`egpToPiastres`).
    expect(ingredientCostPiastres('0.042'), 4);
    expect(ingredientCostPiastres('0'), 0);
  });
}
