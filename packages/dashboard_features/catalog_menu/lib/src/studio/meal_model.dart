/// "Make it a meal" (the web's `features/combos/meal.ts` and the item list of
/// `use-menu-options.ts`): which slots of a combo take this item, and the
/// "+X" the till shows, quoted by madar-catalog's `combo::quote`.
library;

import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart';
import 'package:rust_bridge_dashboard/rules.dart' as rules;

import '../shared/menu_text.dart';

/// A sellable item with its active sizes (a single-price item has one
/// `one_size` row).
class MealItem {
  const MealItem({
    required this.id,
    required this.categoryId,
    this.sizes = const [],
  });

  final String id;
  final String? categoryId;
  final List<({String label, int price})> sizes;

  /// madar-catalog's `CatalogView` of the item: its sizes, no add-ons.
  Map<String, Object?> get view => {
    'item': {
      'id': id,
      'sizes': [
        for (final s in sizes)
          {'label': s.label, 'price': s.price, 'is_active': true},
      ],
    },
  };
}

/// The org's sellable items (`useMenuOptions().items`): never a combo nor a
/// deleted item.
Map<String, MealItem> mealItemsOf(List<MenuItemFull> full) => {
  for (final m in full)
    if (m.kind != 'combo' && m.deletedAt == null)
      m.id: MealItem(
        id: m.id,
        categoryId: m.categoryId,
        sizes: () {
          final rows = (m.allSizes?.isNotEmpty ?? false)
              ? m.allSizes!
              : m.sizes;
          final sizes = [
            for (final s in rows)
              if (s.isActive) (label: s.label, price: s.priceOverride),
          ];
          return sizes.isEmpty ? [(label: oneSize, price: m.basePrice)] : sizes;
        }(),
      ),
};

/// [combo] in madar-catalog's `ComboView` shape. The windows are not a
/// quote's business, nor in its shape.
String _comboJson(Combo combo) =>
    jsonEncode({...combo.toJson(), 'windows': const <Object?>[]});

/// The slots of [combo] that take the item: madar-catalog's
/// `combo::choice_for` through the core (its own item choice, else a
/// category choice for its category).
List<ComboSlot> slotsAdmitting(Combo combo, String itemId, String? categoryId) {
  final ids = rules
      .comboSlotsFor(
        comboJson: _comboJson(combo),
        menuItemId: itemId,
        categoryId: categoryId,
      )
      .toSet();
  return [
    for (final s in combo.slots)
      if (ids.contains(s.id)) s,
  ];
}

/// One pick for [mealQuote]: [item] in [slotId] at [sizeLabel] (null: the
/// size the combo includes), [quantity] per combo.
typedef MealPick = ({
  String slotId,
  MealItem item,
  String? sizeLabel,
  int quantity,
});

/// madar-catalog's `combo::quote` of one [combo] of [picks], no add-ons;
/// null when it refuses them.
Map<String, Object?>? mealQuote(Combo combo, List<MealPick> picks) {
  final answer = rules.comboQuote(
    comboJson: _comboJson(combo),
    picksJson: jsonEncode([
      for (final p in picks)
        {
          'slot_id': p.slotId,
          'view': p.item.view,
          'category_id': p.item.categoryId,
          'selection': {'size_label': p.sizeLabel},
          'quantity': p.quantity,
        },
    ]),
    n: 1,
  );
  return (jsonDecode(answer) as Map<String, Object?>)['Ok']
      as Map<String, Object?>?;
}

/// The "+X": the combo with this item in [slotId] and each slot's default
/// (its default item, else its first item choice) at its minimum elsewhere,
/// less the item alone at the size the combo includes. Null when the quote
/// refuses it (the slot does not admit the item, a default is not a
/// sellable item, no priced size).
int? mealDelta(
  Combo combo,
  String slotId,
  MealItem item,
  MealItem? Function(String id) lookup,
) {
  final picks = <MealPick>[
    (slotId: slotId, item: item, sizeLabel: null, quantity: 1),
  ];
  for (final s in combo.slots) {
    final n = s.id == slotId ? s.min - 1 : s.min;
    if (n < 1) continue;
    final id =
        s.defaultItemId ??
        s.choices.where((c) => c.menuItemId != null).firstOrNull?.menuItemId;
    final it = id == null ? null : lookup(id);
    if (it == null) return null;
    picks.add((
      slotId: s.id,
      item: it,
      sizeLabel: s.defaultSizeLabel,
      quantity: n,
    ));
  }
  final q = mealQuote(combo, picks);
  if (q == null) return null;
  final own = (q['parts']! as List).cast<Map<String, Object?>>().firstWhere(
    (p) => p['pick_index'] == 0,
  );
  return (q['unit_total']! as int) - (own['unit_price']! as int);
}
