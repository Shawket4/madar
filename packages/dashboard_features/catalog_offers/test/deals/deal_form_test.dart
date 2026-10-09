// The deal form's pure rules (the web's `features/deals/form-schema.ts` and
// its `form-schema.test.ts`): the field checks, the wire body both ways, the
// branch calls a Save sends, and the list's order.
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_catalog_offers/src/deals/deal_form.dart';
import 'package:dashboard_catalog_offers/src/deals/deals_data.dart';
import 'package:flutter_test/flutter_test.dart';

PoolEntryDraft _bites() =>
    PoolEntryDraft.empty(PoolTarget.category).copyWith(categoryId: 'bites');

DealDraft _valid() => DealDraft.empty().copyWith(
  name: 'Any 2 bites for 90',
  price: '90',
  pool: [_bites()],
);

DealRule _rule({
  String kind = 'buy_get',
  int? price,
  int? maxPerOrder,
  List<DealPoolEntry> reward = const [],
  List<DealBranchOverride> overrides = const [],
  int sort = 0,
  String name = 'Deal',
}) => DealRule.fromJson({
  'id': 'd-$name',
  'name': name,
  'name_translations': {'ar': 'عرض'},
  'kind': kind,
  'qty': 2,
  'price': price,
  'get_qty': kind == 'buy_get' ? 1 : null,
  'get_percent': kind == 'buy_get' ? 50 : null,
  'max_per_order': maxPerOrder,
  'is_active': true,
  'sort': sort,
  'pool': [
    {'menu_item_id': 'coffee', 'category_id': null, 'size_label': 'Large'},
  ],
  'reward_pool': [for (final e in reward) e.toJson()],
  'windows': <Object?>[],
  'branch_overrides': [for (final o in overrides) o.toJson()],
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
});

void main() {
  group('OFFR-DEA-029/030/038 validateDeal', () {
    test('a valid N for a price passes', () {
      expect(validateDeal(_valid()).isEmpty, isTrue);
    });

    test('N for a price: 2..20 whole, a price of 0 or more', () {
      for (final q in ['1', '21', '2.5', '', 'x']) {
        expect(
          validateDeal(_valid().copyWith(qty: q)).qty,
          'deals.errors.qtyN',
        );
      }
      expect(validateDeal(_valid().copyWith(qty: ' 20 ')).qty, isNull);
      for (final p in ['', '-1', 'abc']) {
        expect(
          validateDeal(_valid().copyWith(price: p)).price,
          'deals.errors.price',
          reason: p,
        );
      }
      expect(validateDeal(_valid().copyWith(price: '0')).price, isNull);
    });

    test('buy X get Y: 1..20, 1..20 and 1..100 percent', () {
      final bg = _valid().copyWith(kind: DealKind.buyGet);
      expect(validateDeal(bg).isEmpty, isTrue);
      expect(validateDeal(bg.copyWith(qty: '0')).qty, 'deals.errors.qtyBuy');
      expect(
        validateDeal(bg.copyWith(getQty: '21')).getQty,
        'deals.errors.getQty',
      );
      expect(
        validateDeal(bg.copyWith(getPercent: '150')).getPercent,
        'deals.errors.percent',
      );
      expect(validateDeal(bg.copyWith(getPercent: '0')).getPercent, isNotNull);
      expect(validateDeal(bg.copyWith(getPercent: '100')).getPercent, isNull);
      // The price is not checked for buy X get Y.
      expect(validateDeal(bg.copyWith(price: '')).price, isNull);
    });

    test('the cap: blank or a whole number of 1 or more', () {
      expect(
        validateDeal(_valid().copyWith(maxPerOrder: '  ')).maxPerOrder,
        isNull,
      );
      expect(
        validateDeal(_valid().copyWith(maxPerOrder: '1')).maxPerOrder,
        isNull,
      );
      for (final m in ['0', '-2', '1.5']) {
        expect(
          validateDeal(_valid().copyWith(maxPerOrder: m)).maxPerOrder,
          'deals.errors.maxPerOrder',
        );
      }
    });

    test('OFFR-DEA-032/035/037 the lists: not empty, every entry chosen; '
        'the reward list only for buy X get Y with the switch on', () {
      expect(
        validateDeal(_valid().copyWith(pool: [])).pool,
        'deals.errors.poolEmpty',
      );
      final e = validateDeal(
        _valid().copyWith(pool: [_bites(), PoolEntryDraft.empty()]),
      );
      expect(e.poolEntries, [null, 'deals.errors.poolTarget']);
      // A leftover reward list on N for a price is not checked.
      expect(
        validateDeal(_valid().copyWith(useRewardPool: true)).rewardPool,
        isNull,
      );
      final bg = _valid().copyWith(kind: DealKind.buyGet, useRewardPool: true);
      expect(validateDeal(bg).rewardPool, 'deals.errors.rewardEmpty');
      expect(
        validateDeal(
          bg.copyWith(rewardPool: [PoolEntryDraft.empty()]),
        ).rewardEntries,
        ['deals.errors.poolTarget'],
      );
    });

    test('OFFR-DEA-026 a blank name is required', () {
      expect(
        validateDeal(_valid().copyWith(name: '  ')).name,
        'deals.errors.required',
      );
    });
  });

  group('OFFR-DEA-044 toWire', () {
    test('N for a price in piastres, no get, no reward list', () {
      final body = _valid()
          .copyWith(
            nameAr: '  ',
            kind: DealKind.nForPrice,
            useRewardPool: true,
            rewardPool: [_bites()],
            price: '12.5',
          )
          .toWire(sort: 7)
          .toJson();
      expect(body, {
        'name': 'Any 2 bites for 90',
        'name_translations': <String, Object?>{},
        'kind': 'n_for_price',
        'qty': 2,
        'price': 1250,
        'get_qty': null,
        'get_percent': null,
        'max_per_order': null,
        'sort': 7,
        'is_active': true,
        'pool': [
          {'menu_item_id': null, 'category_id': 'bites', 'size_label': null},
        ],
        'reward_pool': <Object?>[],
        'windows': <Object?>[],
      });
    });

    test('buy X get Y: no price, its numbers, its own reward list', () {
      final body = _valid()
          .copyWith(
            kind: DealKind.buyGet,
            getQty: '1',
            getPercent: '50',
            maxPerOrder: '3',
            useRewardPool: true,
            rewardPool: [
              PoolEntryDraft.empty().copyWith(
                menuItemId: 'cookie',
                sizeLabel: 'Big',
              ),
            ],
          )
          .toWire(sort: 0)
          .toJson();
      expect(body['price'], isNull);
      expect(body['get_qty'], 1);
      expect(body['get_percent'], 50);
      expect(body['max_per_order'], 3);
      expect(body['reward_pool'], [
        {'menu_item_id': 'cookie', 'category_id': null, 'size_label': 'Big'},
      ]);
    });
  });

  group('OFFR-DEA-025 fromWire', () {
    test('a buy-get rule with a reward list and overrides', () {
      final d = DealDraft.fromWire(
        _rule(
          maxPerOrder: 0,
          reward: const [DealPoolEntry(menuItemId: 'cookie')],
          overrides: const [
            DealBranchOverride(branchId: 'b-1', isActive: true),
            DealBranchOverride(branchId: 'b-2', isActive: false),
          ],
        ),
      );
      expect(d.kind, DealKind.buyGet);
      expect(d.nameAr, 'عرض');
      expect(d.price, '');
      expect(d.getPercent, '50');
      expect(d.maxPerOrder, '', reason: '0 reads as no limit');
      expect(d.useRewardPool, isTrue);
      expect(d.pool.single.target, PoolTarget.item);
      expect(d.pool.single.sizeLabel, 'Large');
      expect(d.branches, {'b-1': BranchState.on, 'b-2': BranchState.off});
    });

    test('an N-for-price rule shows its price; get 1 and percent 100 by '
        'default', () {
      final d = DealDraft.fromWire(_rule(kind: 'n_for_price', price: 9050));
      expect(d.price, '90.5');
      expect(d.getQty, '1');
      expect(d.getPercent, '100');
      expect(d.useRewardPool, isFalse);
    });
  });

  test('OFFR-DEA-045 branchChanges: PUTs for on/off, then DELETEs for '
      'back to follow; unchanged sends nothing', () {
    final calls = branchChanges(
      {'b-1': BranchState.on, 'b-2': BranchState.off},
      {
        'b-1': BranchState.inherit,
        'b-2': BranchState.off,
        'b-3': BranchState.on,
        'b-4': BranchState.inherit,
      },
    );
    expect(calls, [
      (branchId: 'b-3', isActive: true),
      (branchId: 'b-1', isActive: null),
    ]);
    expect(branchChanges({'b-1': BranchState.on}, {'b-1': BranchState.off}), [
      (branchId: 'b-1', isActive: false),
    ]);
  });

  test('OFFR-DEA-006 sortedDeals: by sort, then name A→Z', () {
    final rows = sortedDeals([
      _rule(sort: 1, name: 'b'),
      _rule(sort: 0, name: 'Zed'),
      _rule(sort: 1, name: 'A'),
      _rule(sort: 0, name: 'alpha'),
    ]);
    expect([for (final r in rows) r.name], ['alpha', 'Zed', 'A', 'b']);
    // `localeCompare` folds the alef forms: آيس sorts after اسبريسو.
    final ar = sortedDeals([_rule(name: 'آيس لاتيه'), _rule(name: 'اسبريسو')]);
    expect([for (final r in ar) r.name], ['اسبريسو', 'آيس لاتيه']);
  });

  test('wholeNumber reads a whole number the web\'s way', () {
    expect(wholeNumber(' 3 '), 3);
    expect(wholeNumber('3.0'), 3);
    expect(wholeNumber('3.5'), isNull);
    expect(wholeNumber(''), isNull);
    expect(wholeNumber('1e1'), 10);
  });
}
