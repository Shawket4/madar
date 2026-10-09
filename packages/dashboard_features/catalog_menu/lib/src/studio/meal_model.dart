/// "Make it a meal" (the web's `features/combos/meal.ts` and the item list of
/// `use-menu-options.ts`): which slots of a combo take this item, and the
/// "+X" the till shows.
library;

import 'package:dashboard_api/dashboard_api.dart';

import '../shared/menu_text.dart';

/// A sellable item with its active sizes, cheapest first (a single-price
/// item has one `one_size` row).
class MealItem {
  const MealItem({required this.id, required this.categoryId, this.sizes = const []});

  final String id;
  final String? categoryId;
  final List<({String label, int price})> sizes;

  int? priceOf(String? label) {
    for (final s in sizes) {
      if (s.label == label) return s.price;
    }
    return null;
  }
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
          final rows = (m.allSizes?.isNotEmpty ?? false) ? m.allSizes! : m.sizes;
          final sizes = [
            for (final s in rows)
              if (s.isActive) (label: s.label, price: s.priceOverride),
          ]..sort((a, b) => a.price.compareTo(b.price));
          return sizes.isEmpty
              ? [(label: oneSize, price: m.basePrice)]
              : sizes;
        }(),
      ),
};

/// The choice in [slot] that admits the item: its own item choice first,
/// else its category's.
ComboChoice? choiceFor(ComboSlot slot, String itemId, String? categoryId) {
  for (final c in slot.choices) {
    if (c.menuItemId == itemId) return c;
  }
  if (categoryId == null) return null;
  for (final c in slot.choices) {
    if (c.categoryId != null && c.categoryId == categoryId) return c;
  }
  return null;
}

List<ComboSlot> slotsAdmitting(
  Combo combo,
  String itemId,
  String? categoryId,
) => [
  for (final s in combo.slots)
    if (choiceFor(s, itemId, categoryId) != null) s,
];

String? _includedLabel(ComboChoice c, MealItem? it) =>
    c.includedSizeLabel ?? it?.sizes.firstOrNull?.label;

/// What one pick of [it] through [c] at [sizeLabel] adds on top of the combo
/// price.
int _pickExtra(ComboChoice c, MealItem? it, String? sizeLabel) {
  final inc = _includedLabel(c, it);
  var sizeExtra = 0;
  if (sizeLabel != null && inc != null && sizeLabel != inc) {
    final owner = c.sizeSurcharges
        .where((x) => x.sizeLabel == sizeLabel)
        .firstOrNull;
    if (owner != null) {
      sizeExtra = owner.surcharge;
    } else {
      final chosen = it?.priceOf(sizeLabel);
      final base = it?.priceOf(inc);
      sizeExtra = chosen != null && base != null && chosen > base
          ? chosen - base
          : 0;
    }
  }
  return c.surcharge + sizeExtra;
}

/// A slot's default pick's extra: its default item (or first item choice).
int _defaultExtra(ComboSlot slot, MealItem? Function(String id) lookup) {
  final id =
      slot.defaultItemId ??
      slot.choices.where((c) => c.menuItemId != null).firstOrNull?.menuItemId;
  final it = id == null ? null : lookup(id);
  final c = it != null
      ? choiceFor(slot, it.id, it.categoryId)
      : slot.choices.firstOrNull;
  return c == null ? 0 : _pickExtra(c, it, slot.defaultSizeLabel);
}

/// The "+X": the combo with this item in [slotId] and the defaults
/// elsewhere, minus the item alone at the size the combo includes. Null
/// when the slot does not admit the item or a price is unknown.
int? mealDelta(
  Combo combo,
  String slotId,
  MealItem item,
  MealItem? Function(String id) lookup,
) {
  final slot = combo.slots.where((s) => s.id == slotId).firstOrNull;
  final own = slot == null ? null : choiceFor(slot, item.id, item.categoryId);
  if (slot == null || own == null) return null;
  final alone = item.priceOf(_includedLabel(own, item));
  if (alone == null) return null;
  var total = combo.price + _pickExtra(own, item, null);
  for (final s in combo.slots) {
    final picks = s.id == slotId ? (s.min - 1 < 0 ? 0 : s.min - 1) : s.min;
    if (picks > 0) total += picks * _defaultExtra(s, lookup);
  }
  return total - alone;
}
