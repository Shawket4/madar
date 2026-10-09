// The Orders unit's pure rules against hand-computed answers (the web's
// `reward-lines.test.ts`, `staff-drink-lines.test.ts`, `order-lines.ts`,
// `discount-attribution.ts`, `export/build-filename.ts`, `columns.test.ts`).
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_sell/src/orders/export_data.dart';
import 'package:dashboard_sell/src/orders/order_lines.dart';
import 'package:flutter_test/flutter_test.dart';

OrderItemFull _line(
  String id, {
  int qty = 1,
  int unit = 11500,
  int? total,
  String? kind,
  String? combo,
  int? staffComp,
  int? rewardCovered,
  bool? isReward,
  List<OrderItemAddon> addons = const [],
  List<OrderItemOptional> optionals = const [],
  int? lineCost,
  bool costMissing = false,
}) => OrderItemFull(
  id: id,
  orderId: 'o',
  itemName: id,
  nameTranslations: const {'ar': 'اسم'},
  quantity: qty,
  unitPrice: unit,
  lineTotal: total ?? unit * qty,
  lineKind: kind,
  comboLineId: combo,
  staffCompMinor: staffComp,
  rewardCovered: rewardCovered,
  isReward: isReward,
  costMissing: costMissing,
  lineCost: lineCost,
  deductionsSnapshot: const <Object?>[],
  addons: addons,
  optionals: optionals,
);

OrderItemAddon _addon(int total, {int? comp}) => OrderItemAddon(
  id: 'a$total',
  orderItemId: 'x',
  addonItemId: 'ai',
  addonName: 'Oat milk',
  nameTranslations: const {},
  quantity: 1,
  unitPrice: total,
  lineTotal: total,
  staffCompMinor: comp,
);

void main() {
  test('SELL-ORD-047 translatedName: Arabic when there is one', () {
    expect(translatedName('Latte', const {'ar': 'لاتيه'}, 'ar'), 'لاتيه');
    expect(translatedName('Latte', const {'ar': 'لاتيه'}, 'en'), 'Latte');
    expect(translatedName('Latte', const {}, 'ar'), 'Latte');
  });

  test('SELL-ORD-018 refs: order_ref, else #display, else #number', () {
    expect(orderDisplayRef(orderRef: 'HL-1', displayNumber: 'T1-4', orderNumber: 4), 'HL-1');
    expect(orderDisplayRef(orderRef: null, displayNumber: 'T1-4', orderNumber: 4), '#T1-4');
    expect(orderDisplayRef(orderRef: null, displayNumber: null, orderNumber: 4), '#4');
    expect(orderPlainRef(orderRef: null, orderNumber: 4), '#4');
  });

  test('SELL-ORD-055 staff drink: normal = charged + comp; charged counts '
      'add-ons and optionals × qty', () {
    final it = _line(
      'l',
      qty: 2,
      total: 0,
      staffComp: 26000,
      addons: [_addon(5000)],
      optionals: [
        OrderItemOptional(
          id: 'o1',
          orderItemId: 'l',
          fieldName: 'Extra hot',
          nameTranslations: const {},
          price: 500,
        ),
      ],
    );
    final s = staffDrinkLine(it)!;
    expect(s.charged, 0 + 5000 + 500 * 2);
    expect(s.comp, 26000);
    expect(s.normal, 6000 + 26000);
    expect(staffDrinkLine(_line('paid')), isNull);
    expect(addonNormalTotal(_addon(0, comp: 3000)), 3000);
    expect(orderStaffComp([it, _line('p', staffComp: -5)]), 26000);
  });

  test('SELL-ORD-046 combos: parts under their header, its total; an orphan '
      'part stays a plain line', () {
    final rows = orderRows([
      _line('h', kind: 'combo', total: 0),
      _line('p1', kind: 'combo_part', combo: 'h', total: 11000, addons: [_addon(2500)]),
      _line('plain'),
      _line('p2', kind: 'combo_part', combo: 'h', total: 9000),
      _line('orphan', kind: 'combo_part', combo: 'gone', total: 4000),
    ]);
    expect(rows.map((r) => r.line.id), ['h', 'p1', 'p2', 'plain', 'orphan']);
    expect((rows.first as ComboRow).total, 11000 + 2500 + 9000);
    expect((rows[1] as LineRow).part, isTrue);
    expect((rows.last as LineRow).part, isFalse);
  });

  test('SELL-ORD-047/058 rewards: covered or flagged, the total covered', () {
    final r = orderRewards(
      OrderFull.fromJson({
        ..._order(),
        'loyalty_customer_id': 'c1',
        'loyalty_member_name': 'Nada',
        'items': [
          _line('a', rewardCovered: 11500, total: 0).toJson(),
          _line('b', isReward: true, rewardCovered: -3).toJson(),
          _line('c').toJson(),
        ],
      }),
    );
    expect(r.lines.keys, ['a', 'b']);
    expect(r.totalCovered, 11500);
    expect(r.memberName, 'Nada');
  });

  test('SELL-ORD-058 discount attribution', () {
    expect(bpsLabel(1250), '12.5%');
    expect(bpsLabel(1000), '10%');
    expect(bpsLabel(1234), '12.34%');
    expect(bpsLabel(null), isNull);
  });

  test('SELL-ORD-059 COGS: known lines, a missing one makes it a bound', () {
    final o = OrderFull.fromJson({
      ..._order(total: 30000),
      'items': [
        _line('a', lineCost: 7000).toJson(),
        _line('b', costMissing: true).toJson(),
      ],
    });
    final c = orderCogs(o);
    expect(c.known, 7000);
    expect(c.anyMissing, isTrue);
    expect(c.profit, 23000);
    expect(c.profitShare, closeTo(23000 / 30000, 1e-9));
  });

  test('SELL-ORD-075 the default file name', () {
    expect(
      exportFilename(
        presetId: 'accountant_daily',
        branchSlug: branchSlug('New Cairo'),
        from: '2026-10-07T21:00:00.000Z',
        to: '2026-10-08T21:00:00.000Z',
        now: DateTime.utc(2026, 10, 8, 7),
      ),
      'accountant-daily-new-cairo-2026-10-07_to_2026-10-08',
    );
    expect(branchSlug(''), 'branch');
    expect(
      exportFilename(
        presetId: 'custom',
        branchSlug: 'branch',
        from: null,
        to: null,
        now: DateTime.utc(2026, 10, 8, 7),
      ),
      'custom-branch-2026-10-08',
    );
  });

  test('SELL-ORD-072 the presets and what they force', () {
    expect(exportPresets.map((p) => p.id), [
      'accountant_daily',
      'talabat_reconcile',
      'till_handoff',
      'ingredient_consumption',
      'custom',
    ]);
    const f = OrdersExportFilters(branchId: 'b', status: 'voided', payment: 'card');
    expect(f.merged(exportPresets[0]).status, 'completed');
    expect(f.merged(exportPresets[1]).payment, 'talabat_online,talabat_cash');
    expect(f.merged(exportPresets[2]).status, 'voided');
    expect(exportPresets[3].grains, [ExportGrain.deduction]);
  });
}

Map<String, Object?> _order({int total = 0}) => {
  'id': 'o',
  'branch_id': 'b',
  'till_id': 't',
  'shift_id': 't',
  'teller_id': 'u',
  'teller_name': 'Ali Hassan',
  'order_number': 1,
  'order_type': 'dine_in',
  'payment_method': 'cash',
  'payment_legs': const <Object?>[],
  'status': 'completed',
  'subtotal': total,
  'discount_amount': 0,
  'discount_value': 0,
  'tax_amount': 0,
  'delivery_fee': 0,
  'total_amount': total,
  'created_at': '2026-10-08T07:00:00.000Z',
};
