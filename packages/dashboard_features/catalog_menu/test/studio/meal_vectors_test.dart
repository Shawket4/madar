// madar-shared's combo_vectors.json (pinned to its tag;
// tool/sync_web_vectors.py) through the studio's mapping to madar-catalog's
// `combo::quote` (run in Rust): every quote part's surcharge comes back from
// [mealQuote], and each case shaped like "Make it a meal" (the item in its
// slot, a default per other slot, no add-ons) is re-asked as a +X: the
// quote's unit total less the item alone.
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_catalog_menu/src/studio/meal_model.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';

typedef J = Map<String, Object?>;

List<J> _list(Object? v) => (v! as List).cast<J>();

/// The vector combo as the API's [Combo]; [slot] patches each slot.
Combo comboOf(J v, [J Function(J slot)? slot]) => Combo.fromJson({
  ...v,
  'available_now': true,
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
  'description_translations': <String, Object?>{},
  'economics': {
    'list_default': 0,
    'list_max': 0,
    'list_min': 0,
    'price': 0,
    'saving_default': 0,
    'warnings': <Object?>[],
  },
  'is_fixed': false,
  'kind': 'combo',
  'name': v['id'],
  'name_translations': <String, Object?>{},
  'windows': <Object?>[],
  'slots': [
    for (final s in _list(v['slots']))
      {
        ...s,
        'name_translations': <String, Object?>{},
        'choices': [
          for (final (i, c) in _list(s['choices']).indexed)
            {...c, 'id': '${s['id']}-$i', 'sort': i},
        ],
        ...?slot?.call(s),
      },
  ],
});

void main() {
  final v = sharedVectors('combo')! as J;
  final items = (v['items']! as Map).cast<String, J>();
  final combos = (v['combos']! as Map).cast<String, J>();
  final cases = _list(v['cases']);
  J itemOf(J pick) => items[pick['item']]!['item']! as J;

  /// What the studio's item list hands the view: active sizes at their
  /// branch-effective price.
  MealItem option(J pick) {
    final it = itemOf(pick);
    return MealItem(
      id: it['id']! as String,
      categoryId: pick['category_id'] as String?,
      sizes: [
        for (final s in _list(it['sizes']))
          if (s['is_active'] == true &&
              (s['branch_price'] ?? s['price']) != null)
            (
              label: s['label']! as String,
              price: (s['branch_price'] ?? s['price'])! as int,
            ),
      ],
    );
  }

  String? sizeOf(J pick) => (pick['selection']! as J)['size_label'] as String?;
  final quotes = [
    for (final c in cases)
      if ((c['expected']! as J)['quote'] != null) c,
  ];
  J quoteOf(J c) => (c['expected']! as J)['quote']! as J;

  test('covers the quote cases', () {
    expect(quotes.length, greaterThanOrEqualTo(15));
  });

  for (final c in quotes) {
    test("${c['name']}: each part's surcharge", () {
      final q = mealQuote(comboOf(combos[c['combo']]!), [
        for (final p in _list(c['picks']))
          (
            slotId: p['slot_id']! as String,
            item: option(p),
            sizeLabel: sizeOf(p),
            quantity: p['quantity']! as int,
          ),
      ])!;
      final got = {
        for (final part in _list(q['parts']))
          part['pick_index']: part['surcharge_unit'],
      };
      for (final part in _list(quoteOf(c)['parts'])) {
        expect(got[part['pick_index']], part['surcharge_unit']);
      }
    });
  }

  // The +X prices one default per slot at its minimum and no add-ons.
  final meals = <(J, J)>[];
  for (final c in quotes) {
    final parts = _list(quoteOf(c)['parts']);
    if (parts.any((p) => p['extras_unit'] != 0)) continue;
    final picks = _list(c['picks']);
    final fits = _list(combos[c['combo']]!['slots']).every((s) {
      final mine = picks.where((p) => p['slot_id'] == s['id']);
      return mine.fold<int>(0, (n, p) => n + (p['quantity']! as int)) ==
              s['min'] &&
          mine.map((p) => p['item']).toSet().length <= 1;
    });
    final own = parts
        .where((p) => p['size_label'] == p['included_size_label'])
        .firstOrNull;
    if (fits && own != null) meals.add((c, own));
  }

  test('re-asks most of them as a +X', () {
    expect(meals.length, greaterThanOrEqualTo(10));
  });

  for (final (c, own) in meals) {
    test('${c['name']}: +X = the quote less the item alone', () {
      final picks = _list(c['picks']);
      final combo = comboOf(combos[c['combo']]!, (s) {
        final p = picks.where((x) => x['slot_id'] == s['id']).firstOrNull;
        return {
          'default_item_id': p == null ? null : itemOf(p)['id'],
          'default_size_label': p == null ? null : sizeOf(p),
        };
      });
      final byId = {for (final p in picks) itemOf(p)['id']: option(p)};
      final pick = picks[own['pick_index']! as int];
      expect(
        mealDelta(
          combo,
          pick['slot_id']! as String,
          option(pick),
          (id) => byId[id],
        ),
        (quoteOf(c)['unit_total']! as int) - (own['unit_price']! as int),
      );
    });
  }

  test('no_priced_size: an item with no priced size has no +X', () {
    final c = cases.firstWhere((x) => x['name'] == 'no_priced_size');
    final pick = _list(c['picks']).first;
    final it = option(pick);
    expect(it.sizes, isEmpty);
    expect(
      mealDelta(
        comboOf(combos[c['combo']]!),
        pick['slot_id']! as String,
        it,
        (_) => it,
      ),
      isNull,
    );
  });

  test('an included size the item no longer sells costs its lowest', () {
    // lunch includes a Regular latte; with Regular off, unit_price(Regular) is
    // the lowest active size, Large 6000: the quote stays 15000, so +9000.
    J pick(String item) => {
      'slot_id': 's-drink',
      'item': item,
      'selection': {'size_label': null},
      'quantity': 1,
    };
    final full = option(pick('latte'));
    final latte = MealItem(
      id: full.id,
      categoryId: full.categoryId,
      sizes: [
        for (final s in full.sizes)
          if (s.label != 'Regular') s,
      ],
    );
    final byId = {
      'latte': latte,
      'burger': option(pick('burger')),
      'fries': option(pick('fries')),
    };
    final combo = comboOf(
      combos['lunch']!,
      (s) => {'default_item_id': _list(s['choices']).first['menu_item_id']},
    );
    expect(mealDelta(combo, 's-drink', latte, (id) => byId[id]), 9000);
  });
}
