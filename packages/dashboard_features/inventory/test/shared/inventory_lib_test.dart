// The web's `src/features/inventory/lib.test.ts` vectors, against the port.
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_inventory/src/shared/inventory_lib.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isVarianceFlagged', () {
    test('flags a difference at or above the tolerance of book stock', () {
      expect(isVarianceFlagged(100, 90, 10), isTrue);
      expect(isVarianceFlagged(100, 91, 10), isFalse);
      expect(isVarianceFlagged(100, 110, 10), isTrue);
    });

    test('flags stock from zero, never an uncounted row', () {
      expect(isVarianceFlagged(0, 3, 10), isTrue);
      expect(isVarianceFlagged(0, 0, 10), isFalse);
      expect(isVarianceFlagged(100, null, 10), isFalse);
    });
  });

  group('buildCountPayload', () {
    test('sends only counted rows, with their reason when picked', () {
      final payload = buildCountPayload(
        ['a', 'b', 'c'],
        {'a': '12', 'b': '', 'c': 'abc'},
        {'a': 'miscount'},
      );
      expect(payload.map((p) => p.toJson()).toList(), [
        {
          'counted_qty': 12.0,
          'org_ingredient_id': 'a',
          'variance_reason': 'miscount',
        },
      ]);
    });

    test('treats a blank reason as none (sent as null)', () {
      final p = buildCountPayload(['a'], {'a': '0'}, {'a': ''}).single;
      expect(p.varianceReason, isNull);
      expect(p.toJson().containsKey('variance_reason'), isTrue);
      expect(parseCount(' '), isNull);
      expect(parseCount('12abc'), 12);
    });
  });

  test('missingReasons names flagged rows without a reason', () {
    const items = <CountRowRef>[
      (orgIngredientId: 'milk', name: 'Milk', bookQty: 100),
      (orgIngredientId: 'new', name: 'New item', bookQty: 0),
    ];
    expect(missingReasons(items, {'milk': '50', 'new': '0'}, {}, 10), ['Milk']);
    expect(missingReasons(items, {'milk': '95', 'new': '4'}, {}, 10), [
      'New item',
    ]);
    expect(
      missingReasons(
        items,
        {'milk': '50', 'new': '4'},
        {'milk': 'theft', 'new': 'miscount'},
        10,
      ),
      isEmpty,
    );
  });

  group('first run and counts due', () {
    test('no finalized count means a first count is needed', () {
      expect(needsFirstCount(<String>[]), isTrue);
      expect(needsFirstCount(['in_progress']), isTrue);
      expect(needsFirstCount(['finalized', 'cancelled']), isFalse);
      expect(needsFirstCount(null), isFalse);
    });

    test('never-counted and stale rows are due', () {
      final now = DateTime.parse('2026-09-05T12:00:00Z');
      expect(
        countsDue([null, '2026-09-01T00:00:00Z', '2026-08-01T00:00:00Z'], now),
        2,
      );
    });
  });

  group('waste', () {
    test('source: the server\'s, else the older backend fallback', () {
      expect(wasteSource(wasteSource: 'pos'), 'pos');
      expect(wasteSource(sourceType: 'order'), 'order');
      expect(wasteSource(sourceType: 'waste'), 'dashboard');
      expect(wasteSource(wasteSource: 'refund'), 'refund');
      expect(wasteSource(sourceType: 'refund'), 'refund');
    });

    test('dated by when it happened on the device', () {
      expect(
        wasteWhen(
          occurredAt: '2026-09-17T08:00:00Z',
          createdAt: '2026-09-17T10:00:00Z',
        ),
        '2026-09-17T08:00:00Z',
      );
      expect(
        wasteWhen(createdAt: '2026-09-17T10:00:00Z'),
        '2026-09-17T10:00:00Z',
      );
    });

    test('receive time only past five minutes', () {
      const occurred = '2026-09-17T08:00:00Z';
      expect(
        wasteReceivedLate(
          occurredAt: occurred,
          receivedAt: '2026-09-17T08:04:59Z',
          createdAt: 'x',
        ),
        isNull,
      );
      expect(
        wasteReceivedLate(
          occurredAt: occurred,
          receivedAt: '2026-09-17T08:05:01Z',
          createdAt: 'x',
        ),
        '2026-09-17T08:05:01Z',
      );
      expect(
        wasteReceivedLate(
          occurredAt: occurred,
          createdAt: '2026-09-17T11:00:00Z',
        ),
        '2026-09-17T11:00:00Z',
      );
      expect(wasteReceivedLate(createdAt: '2026-09-17T11:00:00Z'), isNull);
    });
  });

  test('below zero marks only a negative figure', () {
    expect(isBelowZero(-0.5), isTrue);
    expect(isBelowZero(0), isFalse);
    expect(isBelowZero(3), isFalse);
    expect(isBelowZero(null), isFalse);
  });

  group('purchase line costs', () {
    test('unit cost from the invoice total, unrounded', () {
      expect(unitCostFromTotal(54816, 12000), closeTo(4.568, 1e-9));
      expect(unitCostFromTotal(54816, 0), isNull);
      expect(unitCostFromTotal(-1, 10), isNull);
      expect(unitCostFromTotal(double.nan, 10), isNull);
    });

    test('a unit cost shows all six decimals', () {
      const f = DashFormat();
      expect(formatUnitCost(f, 54816 / 12000), '0.045680');
      expect(formatUnitCost(f, 60000 / 12000), '0.050000');
      expect(formatUnitCost(f, 10000 / 3), '33.333333');
    });

    test('purchase unit to stock units within a measure', () {
      expect(stockUnitsPer('kg', 'g'), 1000);
      expect(stockUnitsPer('g', 'g'), 1);
      expect(stockUnitsPer('l', 'ml'), 1000);
      expect(stockUnitsPer('case', 'pcs'), 1);
      expect(stockUnitsPer('kg', 'ml'), 1);
    });

    test('line estimate from the catalog cost per stock unit', () {
      expect(estimateLineTotal(4.568, 12000, 'g', 'g'), 54816);
      expect(estimateLineTotal(4.568, 12, 'kg', 'g'), 54816);
      expect(estimateLineTotal(null, 12, 'kg', 'g'), isNull);
      expect(estimateLineTotal(4.568, 0, 'g', 'g'), isNull);
    });
  });

  test('measure families', () {
    expect(unitsForFamily('kg'), ['g', 'kg']);
    expect(unitsForFamily('ml'), ['ml', 'l']);
    expect(unitsForFamily('pcs'), ['pcs']);
  });
}
