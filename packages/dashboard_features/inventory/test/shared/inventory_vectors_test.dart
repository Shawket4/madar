// madar-shared's unit_vectors.json and inventory_vectors.json (the web's pinned
// copies, synced by tool/sync_web_vectors.py) against the rules the dashboard
// calls: madar-units and madar-inventory themselves, through the core's
// bridge (the host library flutter_test_config.dart loads).
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
}
