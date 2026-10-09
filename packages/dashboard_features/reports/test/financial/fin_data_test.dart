// What Financial computes in the browser, against hand-made inputs
// (REP-FIN-011, 022, 034…036, 038, 043, 066).
import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_reports/src/financial/fin_data.dart';
import 'package:dashboard_reports/src/financial/fin_quadrant.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

MarginLedgerRow row(
  String name, {
  int qty = 0,
  int revenue = 0,
  int? margin,
  String? klass,
  List<Signal> flags = const [],
  String size = 'one_size',
}) => MarginLedgerRow(
  menuItemId: name,
  sizeLabel: size,
  itemName: name,
  onMenu: true,
  quantitySold: qty,
  revenue: revenue,
  margin: margin,
  prevQuantity: 0,
  class_: klass,
  flags: flags,
);

void main() {
  setUpAll(ensureTimeZones);

  test('REP-FIN-011 the trend ratio; none when prev is 0 or missing', () {
    expect(finTrend(120, 100), closeTo(0.2, 1e-12));
    expect(finTrend(80, 100), closeTo(-0.2, 1e-12));
    expect(finTrend(100, 0), isNull);
    expect(finTrend(100, null), isNull);
  });

  test('REP-FIN-022 class and Flagged only combine', () {
    const flag = Signal(kind: 'below_target', link: 'pricing', params: {});
    final rows = [
      row('a', klass: 'star', flags: [flag]),
      row('b', klass: 'star'),
      row('c', klass: 'dog', flags: [flag]),
    ];
    expect(finFilterRows(rows).length, 3);
    expect(finFilterRows(rows, klass: 'star').map((r) => r.itemName), [
      'a',
      'b',
    ]);
    expect(finFilterRows(rows, flaggedOnly: true).map((r) => r.itemName), [
      'a',
      'c',
    ]);
    expect(
      finFilterRows(
        rows,
        klass: 'star',
        flaggedOnly: true,
      ).map((r) => r.itemName),
      ['a'],
    );
  });

  test('REP-FIN-034 tones by kind; an unknown kind is neutral', () {
    expect(finSignalTone('below_cost'), DashTone.danger);
    expect(finSignalTone('below_target'), DashTone.warning);
    expect(finSignalTone('cost_spike'), DashTone.warning);
    expect(finSignalTone('price_candidate'), DashTone.info);
    expect(finSignalTone('removal_candidate'), DashTone.neutral);
    expect(finSignalTone('recipe_incomplete'), DashTone.neutral);
    expect(finSignalTone('mystery'), DashTone.neutral);
  });

  test('REP-FIN-038 a target: empty or 0 < v < 100', () {
    for (final ok in ['', '  ', '1', '55.5', '99.9']) {
      expect(finPctValid(ok), isTrue, reason: ok);
    }
    for (final bad in ['0', '100', '-1', 'abc', '1e9']) {
      expect(finPctValid(bad), isFalse, reason: bad);
    }
    expect(finPctString(68.0), '68');
    expect(finPctString(55.5), '55.5');
  });

  test('REP-FIN-043 the split lines over the whole classified set: 70/n % '
      'and the weighted margin per unit', () {
    final rows = [
      row('a', qty: 60, margin: 6000, klass: 'star'),
      row('b', qty: 30, margin: 900, klass: 'workhorse'),
      row('c', qty: 10, margin: 1500, klass: 'challenge'),
      row('unsold', klass: null),
      row('no cost', qty: 4, revenue: 100),
    ];
    final m = FinQuadrant(rows);
    expect(m.plotted, 3);
    expect(m.popularityThresholdPct, closeTo(70 / 3, 1e-9));
    expect(m.unitMarginThreshold, closeTo(8400 / 100, 1e-9));
    final a = m.dots['star']!.single;
    expect((a.x, a.y), (60.0, 100.0));
    expect(m.count('dog'), 0);
  });

  test('REP-FIN-066 by category: summed, unknown values skipped, the '
      'uncategorized named, largest first', () {
    final v = InventoryValuationReport(
      totalValue: 0,
      unknownCostCount: 1,
      items: const [
        ValuationRow(
          orgIngredientId: 'milk',
          ingredientName: 'Milk',
          unit: 'L',
          onHand: 1,
          value: 300,
        ),
        ValuationRow(
          orgIngredientId: 'cream',
          ingredientName: 'Cream',
          unit: 'L',
          onHand: 1,
          value: 200,
        ),
        ValuationRow(
          orgIngredientId: 'beans',
          ingredientName: 'Beans',
          unit: 'kg',
          onHand: 1,
          value: 400,
        ),
        ValuationRow(
          orgIngredientId: 'old',
          ingredientName: 'Old',
          unit: 'kg',
          onHand: 1,
          value: 50,
        ),
        ValuationRow(
          orgIngredientId: 'x',
          ingredientName: 'X',
          unit: 'kg',
          onHand: 1,
        ),
      ],
    );
    OrgIngredient ing(String id, String cat) => OrgIngredient(
      id: id,
      orgId: 'o',
      name: id,
      unit: 'L',
      categoryId: cat,
      categorySlug: cat,
      categoryName: cat,
      isActive: true,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    final out = finByCategory(v, [
      ing('milk', 'Dairy'),
      ing('cream', 'Dairy'),
      ing('beans', 'Coffee'),
      ing('x', 'Dairy'),
    ], 'Uncategorized');
    expect(out, [('Dairy', 500), ('Coffee', 400), ('Uncategorized', 50)]);
  });

  testWidgets('REP-FIN-034/035/036/051 the words: labels, reasons, the '
      'target trigger, the actions', (tester) async {
    final h = await pumpFin(tester);
    final t = h.container.read(tProvider);
    final f = h.container.read(formatProvider);
    String reason(String kind, Map<String, Object?> p) =>
        finSignalReason(t, f, Signal(kind: kind, link: 'pricing', params: p));

    expect(finSignalLabel(t, 'below_cost'), 'Below cost');
    expect(finSignalLabel(t, 'price_candidate'), 'Price check');
    expect(finSignalLabel(t, 'removal_candidate'), 'No sales');
    expect(finSignalLabel(t, 'mystery'), 'mystery');

    expect(
      reason('below_cost', {'margin': -1250}),
      'Sells below cost — margin ${f.fmtMoney(-1250)}',
    );
    expect(
      reason('below_target', {'margin_pct': 58.34, 'target_pct': 68}),
      'Margin 58.3% is under the 68% target',
    );
    expect(
      reason('below_target', {
        'margin_pct': 58,
        'target_pct': 68,
        'adaptive_bar': 2.5,
      }),
      'Margin 58% is under the 68% target (bar raised 2.5 pts — these are '
      'often dismissed)',
    );
    expect(
      reason('cost_spike', {'ingredient': 'Whole milk', 'pct': 13.25}),
      'Whole milk cost moved 13.3% this period',
    );
    expect(
      reason('price_candidate', {
        'caution': true,
        'last_margin_per_day_delta': -4500,
      }),
      'Still under target, but the last price change cost '
      '${f.fmtMoney(4500)}/day in margin — consider holding or reverting',
    );
    expect(
      reason('price_candidate', {
        'suggested_price': 9500,
        'elasticity': -1.2,
        'expected_margin_per_day_delta': -10,
      }),
      'Top seller under target — ${f.fmtMoney(9500)} is the best measured '
      'price (≈+${f.fmtMoney(0)}/day expected, from this item\'s own sales '
      'response)',
    );
    expect(
      reason('price_candidate', {'suggested_price': 9500}),
      'Top seller under target — suggested price ${f.fmtMoney(9500)}',
    );
    expect(reason('removal_candidate', {}), 'No sales this period');
    expect(reason('recipe_incomplete', {}), 'Recipe incomplete — cost unknown');
    expect(reason('mystery', {}), 'mystery');

    expect(finTargetText(t, f, 72, 'branch'), 'Branch target 72%');
    expect(finTargetText(t, f, 68.25, 'org'), 'Org target 68.3%');
    expect(finTargetText(t, f, 60, 'default'), 'Default 60% — set yours');

    expect(finActionLabel(t, 'acted'), 'Fixed');
    expect(finActionLabel(t, 'dismissed'), 'Dismissed');
    expect(finActionLabel(t, 'snoozed'), 'Snoozed');
    expect(finActionLabel(t, 'reverted'), 'reverted');
  });

  testWidgets('REP-FIN-044 a dot\'s tooltip: name, size, class, the two '
      'placing figures in bold, then Qty, Revenue, Margin', (tester) async {
    final h = await pumpFin(tester);
    final t = h.container.read(tProvider);
    final f = h.container.read(formatProvider);
    final r = row(
      'Latte',
      qty: 40,
      revenue: 340000,
      margin: 250000,
      klass: 'star',
      size: 'Large',
    );
    final tip = finQuadrantTip(t, f, (x: 12.5, y: 6250, row: r));
    expect(tip.title, 'Latte');
    expect(tip.size, 'Large');
    expect(tip.klass, 'Star');
    expect(
      [for (final l in tip.lines) (l.$1, l.$3)],
      [
        ('Margin per unit', true),
        ('Popularity', true),
        ('Qty', false),
        ('Revenue', false),
        ('Margin', false),
      ],
    );
    expect(tip.lines[0].$2, f.fmtMoney(6250));
    expect(tip.lines[1].$2, f.fmtPercent(0.125));
    expect(tip.lines[2].$2, '40');
    final one = finQuadrantTip(t, f, (
      x: 1,
      y: 1,
      row: row('Tea', qty: 1, margin: 1),
    ));
    expect(one.size, isNull);
  });
}
