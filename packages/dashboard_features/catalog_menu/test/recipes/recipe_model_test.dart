// The recipe builder's arithmetic and the create-ingredient dialog's
// conversions, checked by hand against the web's `recipe-builder.tsx` and
// `create-ingredient-dialog.tsx`.
import 'package:dashboard_api/dashboard_api.dart'
    show IngredientCategory, OrgIngredient;
import 'package:dashboard_catalog_menu/src/recipes/create_ingredient_dialog.dart';
import 'package:dashboard_catalog_menu/src/recipes/recipe_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge_dashboard/rules.dart' as rules;

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

OrgIngredient ingr(
  String id,
  double? cost, {
  String unit = 'g',
  double? yieldPct,
  double? density,
}) => OrgIngredient.fromJson({
  'id': id,
  'org_id': 'o1',
  'name': id,
  'category_id': 'c',
  'category_name': 'c',
  'category_slug': 'c',
  'unit': unit,
  'cost_per_unit': cost,
  'yield_pct': yieldPct,
  'density_g_per_ml': density,
  'is_active': true,
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
});

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

  test('MENU-RCP-007 a size costs Σ unit cost × qty (madar-money): rounded '
      'once; an unknown cost or quantity leaves its partial sum, marked '
      'incomplete (D4); no rows is unknown', () {
    final byId = {
      'beans': ingr('beans', 95),
      'milk': ingr('milk', 4.2, unit: 'ml'),
      'pistachio': ingr('pistachio', null),
    };
    OrgIngredient? of(String? id) => byId[id];
    // 18 g × 95 + 180 ml × 4.2 = 1710 + 756.
    expect(
      recipeSizeEstimate([
        row('Regular', 'Beans', '18', id: 'beans'),
        row('Regular', 'Milk', '180', id: 'milk', unit: 'ml'),
      ], of),
      const rules.RecipeCost(piastres: 2466, complete: true),
    );
    expect(
      recipeSizeEstimate([
        row('Regular', 'Beans', '18', id: 'beans'),
        row('Regular', 'Pistachio', '15', id: 'pistachio'),
      ], of),
      const rules.RecipeCost(piastres: 1710, complete: false),
    );
    expect(
      recipeSizeEstimate([row('Regular', 'Beans', '', id: 'beans')], of),
      const rules.RecipeCost(piastres: 0, complete: false),
    );
    expect(recipeSizeEstimate([], of), isNull);
  });

  test('D2 a cost of 0 is known: free, not "cost incomplete"', () {
    final water = ingr('water', 0);
    expect(recipeLineCost(water, '250', 'g'), 0);
    expect(
      recipeSizeEstimate([
        row('Regular', 'Water', '250', id: 'water'),
      ], (_) => water),
      const rules.RecipeCost(piastres: 0, complete: true),
    );
  });

  test('D3 the amount typed is costed as the server stores it: through the '
      "ingredient's yield and density", () {
    // 100 g at yield 80 % stores 125 g: 125 × 2.
    expect(recipeLineCost(ingr('fruit', 2, yieldPct: 80), '100', 'g'), 250);
    // 250 ml of a g ingredient at 1.03 g/ml is 257.5 g: × 2.
    expect(recipeLineCost(ingr('syrup', 2, density: 1.03), '250', 'ml'), 515);
    // No density: ml does not convert into g, so the cost is unknown.
    expect(recipeLineCost(ingr('syrup', 2), '250', 'ml'), isNull);
  });

  test('MENU-RCP-011 a line costs unit cost × qty in whole piastres, else '
      'unknown', () {
    expect(recipeLineCost(ingr('beans', 95), '18', 'g'), 1710);
    expect(recipeLineCost(ingr('beans', 0.35), '10', 'g'), 4);
    expect(recipeLineCost(ingr('x', null), '18', 'g'), isNull);
    expect(recipeLineCost(ingr('beans', 95), '', 'g'), isNull);
    expect(recipeLineCost(null, '18', 'g'), isNull);
  });

  test('MENU-RCP-008 margin = (price − cost) / price over the cost in whole '
      'piastres (D4); tones are the food-cost bands (D5)', () {
    const known = rules.RecipeCost(piastres: 2466, complete: true);
    expect(recipeMargin(known, 11500), closeTo(0.78557, 1e-5));
    // 230.4 + 170 = 400.4 rounds to 400 first: exactly 0.6.
    final d4 = recipeSizeEstimate([
      row('R', 'Beans', '18', id: 'b'),
      row('R', 'Milk', '170', id: 'm'),
    ], (id) => id == 'b' ? ingr('b', 12.8) : ingr('m', 1));
    expect(d4, const rules.RecipeCost(piastres: 400, complete: true));
    expect(recipeMargin(d4, 1000), 0.6);
    expect(
      recipeMargin(const rules.RecipeCost(piastres: 7, complete: false), 1000),
      isNull,
    );
    expect(recipeMargin(null, 11500), isNull);
    expect(recipeMargin(known, 0), isNull);
    expect(recipeMargin(known, null), isNull);
    expect(recipeMarginTone(299, 1000), RecipeMarginTone.good);
    expect(recipeMarginTone(300, 1000), RecipeMarginTone.fair);
    // Margin 65 % is food cost 35 %: amber, as the food-cost chip.
    expect(recipeMarginTone(350, 1000), RecipeMarginTone.fair);
    expect(recipeMarginTone(400, 1000), RecipeMarginTone.fair);
    expect(recipeMarginTone(401, 1000), RecipeMarginTone.poor);
    expect(recipeMarginTone(100, 0), isNull);
  });

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
