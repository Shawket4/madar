// Milk is ONE choice. The recipe's default milk is preselected in the group the
// sheet actually renders, it shows as a radio (no stepper), and picking another
// milk replaces it — so the line, the recipe preview and the stock deduction
// all see exactly one milk. Exercised against both the unified (core groups)
// and the legacy (slot / `type:` bucket) catalogs, fresh add and edit.
import 'package:feature_order/src/item_detail_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

const _addons = [
  ItemAddonView(
    addonItemId: 'full',
    name: 'Full fat',
    addonType: 'milk_type',
    chargedPriceMinor: 0,
  ),
  ItemAddonView(
    addonItemId: 'oat',
    name: 'Oat',
    addonType: 'milk_type',
    chargedPriceMinor: 500,
  ),
  ItemAddonView(
    addonItemId: 'shot',
    name: 'Shot',
    addonType: 'extra',
    chargedPriceMinor: 800,
  ),
];

MenuItemView _latte({List<AddonSlotView> slots = const []}) => MenuItemView(
  id: 'latte',
  name: 'Latte',
  basePriceMinor: 4500,
  isActive: true,
  defaultMilkAddonId: 'full',
  allowedAddonIds: const [],
  sizes: const [],
  addonSlots: slots,
  optionalFields: const [],
  recipes: const [],
  recipeSteps: const [],
);

ModifierOptionView _opt(String id) =>
    ModifierOptionView(id: id, name: id, chargedPriceMinor: 0);

/// What an older core / the backfill hands over: milk as multi, no max, and
/// the group not even typed — only its options say it is milk.
final _unifiedGroups = [
  ModifierGroupView(
    groupId: 'g-milk',
    name: 'Milk',
    kind: ModifierGroupKind.addon,
    isRequired: false,
    minSelections: 0,
    options: [_opt('full'), _opt('oat')],
  ),
  ModifierGroupView(
    groupId: 'g-extra',
    name: 'Extras',
    kind: ModifierGroupKind.addon,
    addonType: 'extra',
    isRequired: false,
    minSelections: 0,
    options: [_opt('shot')],
  ),
];

AddonGroup _milkGroup(String id) => AddonGroup(
  id: id,
  title: 'Milk',
  addons: _addons.where((a) => a.addonType == 'milk_type').toList(),
  isMulti: false,
  maxSel: 1,
  isRequired: false,
  minSel: 0,
);

CartLineView _line(List<String> addonIds) => CartLineView(
  key: 'k',
  itemId: 'latte',
  name: 'Latte',
  addons: [
    for (final id in addonIds)
      CartAddonView(addonItemId: id, name: id, qty: 1, priceModifierMinor: 0),
  ],
  optionals: const [],
  unitPriceMinor: 4500,
  qty: 1,
  lineTotalMinor: 4500,
);

List<String> _ids(ItemConfigState s) =>
    s.selectedAddons.map((a) => a.addonItemId).toList();

void main() {
  late ProviderContainer container;
  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  ItemConfigState read(ItemSheetArgs a) =>
      container.read(itemConfigProvider(a));
  ItemConfigNotifier notifier(ItemSheetArgs a) =>
      container.read(itemConfigProvider(a).notifier);

  group('unified catalog', () {
    test('a milk group mis-typed as multi renders single (radio)', () {
      expect(coreGroupIsSingle(_unifiedGroups[0], _addons), isTrue);
      expect(coreGroupIsSingle(_unifiedGroups[1], _addons), isFalse);
    });

    test('fresh add seeds the default in the rendered group; oat replaces', () {
      final args = ItemSheetArgs(
        item: _latte(),
        addons: _addons,
        groups: _unifiedGroups,
      );
      final sub = container.listen(itemConfigProvider(args), (_, _) {});
      expect(read(args).single, {'g-milk': 'full'});
      notifier(args).toggleSingle(_milkGroup('g-milk'), 'oat');
      expect(_ids(read(args)), ['oat']);
      // Tapping the chosen milk again keeps it — a radio, never zero milks.
      notifier(args).toggleSingle(_milkGroup('g-milk'), 'oat');
      expect(_ids(read(args)), ['oat']);
      sub.close();
    });

    test('editing a line rehydrates into the rendered group', () {
      final args = ItemSheetArgs(
        item: _latte(),
        addons: _addons,
        groups: _unifiedGroups,
        editLine: _line(['full', 'shot']),
      );
      final sub = container.listen(itemConfigProvider(args), (_, _) {});
      expect(read(args).single, {'g-milk': 'full'});
      expect(read(args).multi, {
        'g-extra': {'shot': 1},
      });
      notifier(args).toggleSingle(_milkGroup('g-milk'), 'oat');
      expect(_ids(read(args))..sort(), ['oat', 'shot']);
      sub.close();
    });

    test('a pick in "show all" (legacy keys) still replaces the milk', () {
      final args = ItemSheetArgs(
        item: _latte(),
        addons: _addons,
        groups: _unifiedGroups,
      );
      final sub = container.listen(itemConfigProvider(args), (_, _) {});
      notifier(args).toggleSingle(_milkGroup('type:milk_type'), 'oat');
      expect(_ids(read(args)), ['oat']);
      sub.close();
    });
  });

  group('legacy catalog', () {
    const slot = AddonSlotView(
      id: 'slot-milk',
      addonType: 'milk_type',
      isRequired: false,
      minSelections: 0,
    );

    test('unslotted: default seeded in type bucket; oat replaces', () {
      final args = ItemSheetArgs(item: _latte(), addons: _addons);
      final sub = container.listen(itemConfigProvider(args), (_, _) {});
      expect(read(args).single, {'type:milk_type': 'full'});
      notifier(args).toggleSingle(_milkGroup('type:milk_type'), 'oat');
      expect(_ids(read(args)), ['oat']);
      sub.close();
    });

    test('slotted with no max: edit line lands single; oat replaces', () {
      final args = ItemSheetArgs(
        item: _latte(slots: const [slot]),
        addons: _addons,
        editLine: _line(['full']),
      );
      final sub = container.listen(itemConfigProvider(args), (_, _) {});
      expect(read(args).single, {'slot-milk': 'full'});
      expect(read(args).multi, isEmpty);
      notifier(args).toggleSingle(_milkGroup('slot-milk'), 'oat');
      expect(_ids(read(args)), ['oat']);
      sub.close();
    });
  });
}
