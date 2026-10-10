// madar-shared's cost_vectors.json and recipe_qty_vectors.json (copied into
// dashboard_core/test/vectors/, pinned by their .source.json) against the
// rules the recipe editors call: madar-money `cost` and madar-units' recipe
// quantity, through the core's bridge (the host library
// flutter_test_config.dart loads).
import 'package:dashboard_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge_dashboard/rules.dart' as rules;

List<Map> _cases(Object? v) => (v! as List).cast<Map>();

double? _d(Object? x) => (x as num?)?.toDouble();

void main() {
  final cost = sharedVectors('cost')! as Map;

  test('line_cost', () {
    final cases = _cases(cost['line_cost']);
    expect(cases, isNotEmpty);
    for (final v in cases) {
      expect(
        rules.lineCost(
          qty: _d(v['qty'])!,
          costPerUnit: _d(v['cost_per_unit'])!,
        ),
        v['expected'],
        reason: '${v['name']}',
      );
    }
  });

  test('recipe_cost', () {
    final cases = _cases(cost['recipe_cost']);
    expect(cases, isNotEmpty);
    for (final v in cases) {
      final want = v['expected'] as Map;
      expect(
        rules.recipeCost(
          lines: [
            for (final l in _cases(v['lines']))
              rules.CostLine(
                qty: _d(l['qty'])!,
                costPerUnit: _d(l['cost_per_unit']),
              ),
          ],
        ),
        rules.RecipeCost(
          piastres: want['piastres'] as int,
          complete: want['complete'] as bool,
        ),
        reason: '${v['name']}',
      );
    }
  });

  test('margin', () {
    final cases = _cases(cost['margin']);
    expect(cases, isNotEmpty);
    for (final v in cases) {
      expect(
        rules.margin(price: v['price'] as int, cost: v['cost'] as int),
        v['expected'],
        reason: '${v['name']}',
      );
    }
  });

  test('food_cost_band', () {
    final cases = _cases(cost['food_cost_band']);
    expect(cases, isNotEmpty);
    for (final v in cases) {
      expect(
        rules.foodCostBand(cost: v['cost'] as int, price: v['price'] as int),
        v['expected'],
        reason: '${v['name']}',
      );
    }
  });

  final qty = sharedVectors('recipe_qty')! as Map;

  double? baseQty(Map v) => rules.recipeBaseQty(
    qty: _d(v['qty'])!,
    unit: v['unit'] as String,
    baseUnit: v['base_unit'] as String,
    density: _d(v['density']),
    yieldPct: _d(v['yield_pct']),
  );

  test('recipe_base_qty (an error is no figure)', () {
    final cases = _cases(qty['recipe_base_qty']);
    expect(cases, isNotEmpty);
    for (final v in cases) {
      expect(baseQty(v), v['expected'], reason: '${v['name']}');
    }
  });

  test('usable_qty', () {
    final cases = _cases(qty['usable_qty']);
    expect(cases, isNotEmpty);
    for (final v in cases) {
      expect(
        rules.usableQty(stored: _d(v['stored'])!, yieldPct: _d(v['yield_pct'])),
        v['expected'],
        reason: '${v['name']}',
      );
    }
  });

  test('round trips: typed → stored → usable', () {
    final cases = _cases(qty['round_trips']);
    expect(cases, isNotEmpty);
    for (final v in cases) {
      final stored = baseQty(v);
      expect(stored, v['stored'], reason: '${v['name']}');
      final usable = rules.usableQty(
        stored: stored!,
        yieldPct: _d(v['yield_pct']),
      );
      expect(usable, v['usable'], reason: '${v['name']}');
      expect(
        usable == _d(v['typed_in_base']),
        v['round_trips'],
        reason: '${v['name']}',
      );
    }
  });
}
