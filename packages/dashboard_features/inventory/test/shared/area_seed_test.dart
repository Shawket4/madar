// The area seed tells one story: each stocked pair's ledger ends at its
// on-hand, balances never dip below zero except where designed, counts and
// reports agree with the stock; and every declared i18n supplement exists.
import 'dart:convert';
import 'dart:io';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_inventory/dashboard_inventory.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:dashboard_inventory/src/mock/inventory_views.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final db = MockDb.seeded();
  InventorySeed.loadInto(db);

  test('loading twice adds nothing', () {
    final n = db[InvTables.movements].length;
    InventorySeed.loadInto(db);
    expect(db[InvTables.movements].length, n);
  });

  test('every stocked pair\'s ledger ends at its on-hand', () {
    for (final bs in db[InvTables.branchStock].rows) {
      final moves = db[InvTables.movements].where(
        (m) =>
            m['branch_id'] == bs['branch_id'] &&
            m['org_ingredient_id'] == bs['org_ingredient_id'],
      );
      expect(moves, isNotEmpty, reason: '${bs['id']} has no movements');
      final last = moves.last;
      expect(last['balance_after'], bs['on_hand'], reason: '${last['id']}');
      expect(bs['last_movement_at'], last['created_at']);
    }
  });

  test('balances below zero only where designed (Zamalek Oat Milk)', () {
    final below = db[InvTables.movements].where(
      (m) => (m['balance_after']! as num) < 0,
    );
    expect(
      below.map((m) => '${m['branch_name']} ${m['ingredient_name']}').toSet(),
      {'Zamalek Oat Milk'},
    );
  });

  test('Heliopolis has not started inventory', () {
    final rows = InvViews.branchStock(db, SeedIds.heliopolis);
    expect(rows, isNotEmpty);
    expect(rows.every((r) => r['has_activity'] == false), isTrue);
    expect(InvViews.stocktakes(db, [SeedIds.heliopolis]), isEmpty);
  });

  test('low stock: 5 at Zamalek (2 critical), 9 across the org', () {
    final z = InvViews.lowStock(db, [SeedIds.zamalek]);
    expect(z, hasLength(5));
    expect(z.where((r) => (r['on_hand']! as num) <= 0), hasLength(2));
    expect(InvViews.lowStock(db, SeedIds.sabahBranches), hasLength(9));
  });

  test('three deliveries due by the end of today across the org', () {
    final due =
        InvViews.purchaseOrders(
          db,
          where: (po) => true,
          expectedBefore: DateTime.parse('2026-10-08T20:59:59.999Z'),
        ).where(
          (po) =>
              po['status'] == 'ordered' || po['status'] == 'partially_received',
        );
    expect(due, hasLength(3));
  });

  test('four waste lines at Zamalek this morning', () {
    final today = InvViews.waste(db, [SeedIds.zamalek]).where(
      (m) => DateTime.parse(
        m['created_at']! as String,
      ).isAfter(DateTime.parse('2026-10-07T21:00:00Z')),
    );
    expect(today, hasLength(4));
  });

  test('the open count at New Cairo: 9 counted, figures from the ledger', () {
    final open = InvViews.stocktakes(db, [SeedIds.newCairo]).first;
    expect(open['status'], 'in_progress');
    expect(open['counted_items'], 9);
    final items = InvViews.stocktakeItems(db, open['id']! as String);
    expect(items.where((i) => i['is_new'] == true), hasLength(1));
    final stock = {
      for (final r in InvViews.branchStock(db, SeedIds.newCairo))
        r['org_ingredient_id']: r['on_hand'],
    };
    for (final i in items) {
      if (i['is_new'] == true) continue;
      expect(i['book_qty'], stock[i['org_ingredient_id']]);
    }
  });

  test('finalized count rows over the threshold carry a reason', () {
    for (final st in db[InvTables.stocktakes].where(
      (s) => s['status'] == 'finalized',
    )) {
      for (final i in InvViews.stocktakeItems(db, st['id']! as String)) {
        final book = (i['book_qty']! as num).toDouble();
        final counted = (i['counted_qty'] as num?)?.toDouble();
        if (counted == null) continue;
        final flagged = book.abs() < 1e-9
            ? counted.abs() > 1e-9
            : (counted - book).abs() / book.abs() * 100 >=
                  invVarianceThresholdPct;
        if (flagged) {
          expect(
            i['variance_reason'],
            isNotNull,
            reason: '${st['id']} ${i['ingredient_name']}',
          );
        }
      }
    }
  });

  test('valuation: every stocked ingredient priced but Dried Hibiscus', () {
    final v = InvViews.valuation(db, SeedIds.sabahBranches);
    expect(v['unknown_cost_count'], 1);
    expect(v['total_value'], greaterThan(0));
  });

  test('every declared i18n supplement exists, en and ar keys match', () {
    final files = <String, Map<String, Object?>>{};
    for (final key in inventoryArea.i18nSupplements) {
      final name = key.split('/').last;
      final f = File('assets/i18n/$name');
      expect(f.existsSync(), isTrue, reason: name);
      files[name] = jsonDecode(f.readAsStringSync()) as Map<String, Object?>;
    }
    for (final name in files.keys.where((n) => n.endsWith('en.json'))) {
      final ar = name.replaceFirst(RegExp(r'en\.json$'), 'ar.json');
      expect(files[ar]?.keys.toSet(), files[name]!.keys.toSet(), reason: name);
    }
  });
}
