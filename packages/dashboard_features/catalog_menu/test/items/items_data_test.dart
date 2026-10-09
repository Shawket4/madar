// The items page's browser-side rules (items_data.dart) as plain functions.
import 'package:dashboard_api/dashboard_api.dart'
    show AddonItem, Category, GroupOut;
import 'package:dashboard_catalog_menu/src/items/items_data.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _t0 = DateTime.utc(2026, 1, 1);

Category _cat(String id, String name) => Category(
  id: id,
  orgId: 'org',
  name: name,
  nameTranslations: const {},
  displayOrder: 0,
  isActive: true,
  createdAt: _t0,
  updatedAt: _t0,
);

AddonItem _addon(String id, String name, String type) => AddonItem(
  id: id,
  orgId: 'org',
  name: name,
  nameTranslations: const {},
  addonType: type,
  defaultPrice: 0,
  isActive: true,
  createdAt: _t0,
  updatedAt: _t0,
);

GroupOut _group(String id, String name, String? legacy) => GroupOut.fromJson({
  'id': id,
  'org_id': 'org',
  'name': name,
  'name_translations': const <String, Object?>{},
  'selection_type': 'multi',
  'min_selections': 0,
  'is_required': false,
  'is_active': true,
  'sort': 0,
  'effect': 'adds',
  'legacy_addon_type': legacy,
  'options': const <Object?>[],
});

void main() {
  test('normalizeSearch: case, Latin accents, Arabic tashkeel, trim', () {
    expect(normalizeSearch('  Caffè LATTE '), 'caffe latte');
    expect(normalizeSearch('Frappé'), 'frappe');
    expect(normalizeSearch('قَهْوَة'), 'قهوة');
  });

  test('searchRows folds both sides; blank keeps all', () {
    final rows = ['Caffè Latte', 'Cortado'];
    expect(searchRows(rows, 'CAFFE', (r) => r), ['Caffè Latte']);
    expect(searchRows(rows, 'caffè', (r) => r), ['Caffè Latte']);
    expect(searchRows(rows, '  ', (r) => r), rows);
  });

  test('formatRate: fraction to percent, four places at most', () {
    expect(formatRate(0.14), '14%');
    expect(formatRate(0.125), '12.5%');
    expect(formatRate(0.123456), '12.3456%');
  });

  test('hasRecipeParam', () {
    expect(hasRecipeParam(RecipeFilter.all), isNull);
    expect(hasRecipeParam(RecipeFilter.missing), isFalse);
    expect(hasRecipeParam(RecipeFilter.has), isTrue);
  });

  test(
    'pasteRowError: name, then price, then category (English, any case)',
    () {
      final cats = [_cat('hot', 'Hot Coffee')];
      expect(
        pasteRowError({'name': ' ', 'base_price': 'x'}, cats),
        'menu.grid.nameRequired',
      );
      expect(
        pasteRowError({'name': 'A', 'base_price': 'x'}, cats),
        'menu.grid.priceInvalid',
      );
      expect(
        pasteRowError({'name': 'A', 'base_price': '-1'}, cats),
        'menu.grid.priceInvalid',
      );
      expect(
        pasteRowError({
          'name': 'A',
          'base_price': '45 EGP',
          'category': 'x',
        }, cats),
        'menu.grid.categoryUnknown',
      );
      expect(
        pasteRowError({
          'name': 'A',
          'base_price': '45 EGP',
          'category': ' hot coffee ',
        }, cats),
        isNull,
      );
      expect(pasteCategoryId({'category': 'HOT COFFEE'}, cats), 'hot');
      expect(pastePricePiastres({'base_price': '12.345'}), 1235);
      expect(pastePricePiastres({'base_price': '45 EGP'}), 4500);
    },
  );

  test('runBulk: four at a time, a failure never stops the rest', () async {
    var inFlight = 0, most = 0;
    final r = await runBulk<int>([1, 2, 3, 4, 5, 6], (n) async {
      inFlight++;
      most = most < inFlight ? inFlight : most;
      await Future<void>.delayed(const Duration(milliseconds: 1));
      inFlight--;
      if (n.isEven) throw StateError('no');
    });
    expect(most, 4);
    expect(r.ok.toSet(), {1, 3, 5});
    expect(r.failed.toSet(), {2, 4, 6});
  });

  test('selectionKey ignores order', () {
    expect(selectionKey(['b', 'a']), selectionKey(['a', 'b']));
    expect(selectionKey(<String>[]), '');
  });

  test('addonAttachments: by type → group (legacy type, else name), '
      'first-seen order; unknown types dropped', () {
    final addons = [
      _addon('oat', 'Oat', 'milk_type'),
      _addon('shot', 'Shot', 'extra'),
      _addon('soy', 'Soy', 'milk_type'),
      _addon('x', 'X', 'nowhere'),
    ];
    final groups = [
      _group('g-milk', 'Milk', 'milk_type'),
      _group('g-extra', 'extra', null),
    ];
    final out = addonAttachments(['shot', 'oat', 'soy', 'x'], addons, groups);
    expect(
      [for (final g in out) g.toJson()],
      [
        {
          'group_id': 'g-extra',
          'sort': 0,
          'included_option_ids': ['shot'],
        },
        {
          'group_id': 'g-milk',
          'sort': 1,
          'included_option_ids': ['oat', 'soy'],
        },
      ],
    );
  });

  test('addonPickerGroups: name filter, by type in first-seen order', () {
    final addons = [
      _addon('oat', 'Oat milk', 'milk_type'),
      _addon('shot', 'Extra shot', 'extra'),
      _addon('soy', 'Soy milk', 'milk_type'),
    ];
    final g = addonPickerGroups(addons, 'MILK');
    expect(g.map((e) => e.$1), ['milk_type']);
    expect(g.single.$2.map((a) => a.id), ['oat', 'soy']);
    expect(addonPickerGroups(addons, '').map((e) => e.$1), [
      'milk_type',
      'extra',
    ]);
  });

  test('egpTextToPiastres', () {
    expect(egpTextToPiastres('12.5'), 1250);
    expect(egpTextToPiastres(''), isNull);
    expect(egpTextToPiastres('0'), 0);
  });
}
