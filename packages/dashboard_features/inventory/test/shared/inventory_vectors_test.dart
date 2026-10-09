// madar-shared's unit_vectors.json and inventory_vectors.json (the web's pinned
// copies, synced by tool/sync_web_vectors.py) against the Dart ports, as the
// web's `features/inventory/lib.test.ts` runs them.
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_inventory/src/mock/transfers_mock.dart';
import 'package:dashboard_inventory/src/shared/inventory_lib.dart';
import 'package:dashboard_inventory/src/transfers/transfers_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unit conversions match madar-units (no density)', () {
    // The server rounds to 3 dp, half away from zero.
    double round3(num v) => (v.abs() * 1000).round() * v.sign / 1000;
    var n = 0;
    for (final v in (sharedVectors('unit')! as List).cast<Map>()) {
      if (v['same_without_density'] != true) continue;
      n++;
      final from = v['from'] as String, to = v['to'] as String;
      final per = stockUnitsPer(from, to);
      final why = '${v['qty']} $from -> $to';
      expect(
        per == null ? null : round3((v['qty'] as num) * per),
        v['result'],
        reason: why,
      );
      if (v['result'] != null) {
        expect(
          unitsForFamily(from),
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
      final action = TransferAction.values.byName(v['action'] as String);
      final step = transferStep(v['status'] as String, action);
      final want = v['side'] == null
          ? null
          : (source: v['side'] == 'source', cap: v['cap'] as String);
      expect(step, want, reason: '${v['status']} / ${v['action']}');
    }
  });

  test('a received line', () {
    for (final v in (inv['receives'] as List).cast<Map>()) {
      final out = checkReceiveLine(
        v['qty_sent'] as num,
        v['qty_received'] as num,
        v['note'] as String?,
      );
      final ok = v['ok'] as Map?;
      expect(out, (
        arrival: ok?['arrival'] as String?,
        difference: (ok?['difference'] as num?)?.toDouble(),
        refused: v['refused'] as String?,
      ), reason: '${v['qty_sent']} -> ${v['qty_received']}, note ${v['note']}');
    }
  });

  test('the replenish suggestion (the mock server\'s port)', () {
    for (final v in (inv['replenish'] as List).cast<Map>()) {
      final i = v['input'] as Map, o = v['out'] as Map;
      double d(Object? x) => (x! as num).toDouble();
      final out = replenishSuggest(
        onHand: d(i['on_hand']),
        parMin: d(i['par_min']),
        parMax: (i['par_max'] as num?)?.toDouble(),
        inTransit: d(i['in_transit']),
        openInbound: d(i['open_inbound']),
        warehouseOnHand: d(i['warehouse_on_hand']),
        warehouseDraftedOut: d(i['warehouse_drafted_out']),
      );
      expect(out, (
        need: d(o['need']),
        available: d(o['available']),
        suggested: d(o['suggested']),
      ), reason: '$i');
    }
  });
}
