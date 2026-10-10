// madar-shared's unit_vectors.json and inventory_vectors.json (the web's pinned
// copies, synced by tool/sync_web_vectors.py), purchase_vectors.json and
// count_vectors.json (copied from madar-shared, pinned by their .source.json)
// against the rules the dashboard calls: madar-units and madar-inventory
// themselves, through the core's bridge (the host library
// flutter_test_config.dart loads).
import 'package:dashboard_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge_dashboard/rules.dart' as rules;

void main() {
  test('unit conversions match madar-units (no density)', () {
    var n = 0;
    for (final v in (sharedVectors('unit')! as List).cast<Map>()) {
      if (v['same_without_density'] != true) continue;
      n++;
      final from = v['from'] as String, to = v['to'] as String;
      final why = '${v['qty']} $from -> $to';
      expect(
        rules.unitConvert(
          qty: (v['qty'] as num).toDouble(),
          fromUnit: from,
          toUnit: to,
        ),
        v['result'],
        reason: why,
      );
      if (v['result'] != null) {
        expect(
          rules.unitsOf(base: from),
          contains(to.trim().toLowerCase()),
          reason: why,
        );
      }
    }
    expect(n, greaterThan(0));
  });

  final inv = sharedVectors('inventory')! as Map;

  test('the transfer step table', () {
    for (final v in (inv['steps'] as List).cast<Map>()) {
      final step = rules.transferStep(
        status: v['status'] as String,
        action: v['action'] as String,
      );
      final want = v['side'] == null
          ? null
          : rules.TransferStep(
              side: v['side'] as String,
              cap: v['cap'] as String,
              next: v['next'] as String,
            );
      expect(step, want, reason: '${v['status']} / ${v['action']}');
    }
  });

  test('a received line', () {
    for (final v in (inv['receives'] as List).cast<Map>()) {
      final out = rules.checkReceiveLine(
        sent: (v['qty_sent'] as num).toDouble(),
        got: (v['qty_received'] as num).toDouble(),
        note: v['note'] as String?,
      );
      final ok = v['ok'] as Map?;
      expect(
        (out.arrival, out.refused),
        (ok?['arrival'] as String?, v['refused'] as String?),
        reason: '${v['qty_sent']} -> ${v['qty_received']}, note ${v['note']}',
      );
      if (ok != null) expect(out.difference, ok['difference']);
    }
  });

  test('the replenish suggestion', () {
    for (final v in (inv['replenish'] as List).cast<Map>()) {
      final i = v['input'] as Map, o = v['out'] as Map;
      double d(Object? x) => (x! as num).toDouble();
      final out = rules.replenishSuggest(
        onHand: d(i['on_hand']),
        parMin: d(i['par_min']),
        parMax: (i['par_max'] as num?)?.toDouble(),
        inTransit: d(i['in_transit']),
        openInbound: d(i['open_inbound']),
        warehouseOnHand: d(i['warehouse_on_hand']),
        warehouseDraftedOut: d(i['warehouse_drafted_out']),
      );
      expect(
        out,
        rules.Replenish(
          need: d(o['need']),
          available: d(o['available']),
          suggested: d(o['suggested']),
        ),
        reason: '$i',
      );
    }
  });

  final purchase = sharedVectors('purchase')! as Map;
  double? d(Object? x) => (x as num?)?.toDouble();

  test('a purchase quantity in thousandths, as the column stores it', () {
    final cases = (purchase['quantity'] as List).cast<Map>();
    expect(cases, isNotEmpty);
    for (final v in cases) {
      expect(
        rules.quantityMilli(q: d(v['q'])!),
        v['milli'],
        reason: '${v['name']}',
      );
    }
  });

  test("the order dialog's estimate", () {
    final cases = (purchase['estimate_line_total'] as List).cast<Map>();
    expect(cases, isNotEmpty);
    for (final v in cases) {
      expect(
        rules.estimateLineTotal(
          costPerStockUnit: d(v['cost_per_stock_unit']),
          qty: d(v['qty'])!,
          purchaseUnit: v['purchase_unit'] as String,
          stockUnit: v['stock_unit'] as String,
        ),
        v['expected'],
        reason: '${v['name']}',
      );
    }
  });

  test('the unit cost a total implies', () {
    final cases = (purchase['unit_cost_from_total'] as List).cast<Map>();
    expect(cases, isNotEmpty);
    for (final v in cases) {
      expect(
        rules.unitCostFromTotal(line: v['line'] as int, qty: d(v['qty'])!),
        v['expected'],
        reason: '${v['name']}',
      );
    }
  });

  test('what a delivery costs, in whole piastres (half away from zero)', () {
    final cases = (purchase['delivery_cost'] as List).cast<Map>();
    expect(cases, isNotEmpty);
    for (final v in cases) {
      final want = v['expected'] as String?;
      expect(
        rules.deliveryCost(
          quantityReceived: d(v['quantity_received'])!,
          lineCost: v['line_cost'] as int?,
          unitCost: v['unit_cost'] as int?,
          orderedLineCost: v['ordered_line_cost'] as int,
          quantityOrdered: double.parse(v['quantity_ordered'] as String),
        ),
        want == null ? null : double.parse(want).round(),
        reason: '${v['name']}',
      );
    }
  });

  test('a stock count row that needs a variance reason', () {
    final cases = ((sharedVectors('count')! as Map)['cases'] as List)
        .cast<Map>();
    expect(cases, isNotEmpty);
    for (final v in cases) {
      expect(
        rules.isVarianceFlagged(
          book: d(v['book'])!,
          counted: d(v['counted'])!,
          pct: d(v['pct'])!,
        ),
        v['expected'],
        reason: '${v['name']}',
      );
    }
  });
}
