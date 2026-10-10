// The area seed: loaded once per db, and its numbers computed the backend's
// way (own lines, then base, then the most specific packaging rule).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_menu/src/area_seed.dart';
import 'package:dashboard_catalog_menu/src/shared/menu_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MockDb db;
  late CatalogMenuData data;

  setUp(() {
    db = MockDb.seeded();
    CatalogMenuSeed.loadInto(db);
    data = CatalogMenuData(db);
  });

  test('loading twice changes nothing', () {
    final lines = db[MenuTables.recipeLines].length;
    final sizes = db[MenuTables.sizes].length;
    CatalogMenuSeed.loadInto(db);
    expect(db[MenuTables.recipeLines].length, lines);
    expect(db[MenuTables.sizes].length, sizes);
    expect(data.applyRules()['sizes_changed'], 0);
  });

  test('every item has sizes; a simple item has its one_size row', () {
    for (final m in seedMenu) {
      expect(data.sizesOf(MenuSeedIds.item(m.key)), isNotEmpty, reason: m.key);
    }
    final cortado = data.sizesOf(MenuSeedIds.item('cortado'));
    expect(cortado.single['label'], oneSize);
    expect(cortado.single['price_override'], 9500);
  });

  test('a Regular latte costs its beans, milk, cup and lid', () {
    final latte = db[MenuTables.menuItems].get(MenuSeedIds.item('latte'));
    final regular = data
        .linesOf(MenuSeedIds.size('latte', 'Regular'))
        .map(
          (l) =>
              '${l['source']}:${data.ingredientName(l['ingredient_id']! as String)}',
        )
        .toList();
    expect(regular, [
      'own:Full cream milk',
      'base:House espresso blend',
      'rule:12oz paper cup',
      'rule:Hot cup lid',
    ]);
    final sku = data.skuCosts(latte).first;
    // 18 g × 95 + 180 ml × 4.2 + 180 + 60.
    expect(sku['cost'], 2706);
    expect(sku['cost_missing'], isFalse);
    expect(sku['food_cost_pct'], closeTo(2706 / 11500, 1e-9));
  });

  test('an unpriced ingredient makes the cost partial and ungraded', () {
    final item = db[MenuTables.menuItems].get(
      MenuSeedIds.item('pistachio_latte'),
    );
    final sku = data.skuCosts(item).first;
    expect(sku['cost_missing'], isTrue);
    expect(sku['cost'], isNotNull);
    expect(sku['food_cost_pct'], isNull);
  });

  test('a label-specific base line wins over the all-sizes one', () {
    final large = data.linesOf(MenuSeedIds.size('latte', 'Large'));
    final beans = large.firstWhere(
      (l) => l['ingredient_id'] == MenuSeedIds.ingredient('house_blend'),
    );
    expect(beans['quantity'], '27');
    expect(beans['source'], 'base');
  });

  test('add-ons are the shared groups\' options, by type', () {
    final addons = data.addonItems();
    expect(addons, hasLength(11));
    expect(addons.first['addon_type'], 'extra');
    expect(
      addons.map((a) => a['id']),
      contains(MenuSeedIds.option('milk', 'oat')),
    );
    final shot = data.addonCosts().firstWhere(
      (a) => a['addon_item_id'] == MenuSeedIds.option('extras', 'shot'),
    );
    expect(shot['cost'], 18 * 95);
  });

  test('apply counts the hand-entered packaging', () {
    final r = data.applyRules();
    expect(r['sizes_with_manual_packaging'], 1);
    expect(r['sizes_seen'], db[MenuTables.sizes].length);
  });
}
