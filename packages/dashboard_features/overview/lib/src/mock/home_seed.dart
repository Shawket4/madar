/// The overview area's own seed data, on top of the shared seed's ids: what
/// each menu item costs to make (the recipe snapshot the margin watch reads)
/// and which items have no recipe yet. Everything else the home shows comes
/// from the shared seed's orders, tills and branches.
///
/// Sabah Coffee's onboarding records 85 % recipe coverage: 34 of its 40
/// items carry a recipe cost, the six below do not.
library;

import 'package:dashboard_api/mock.dart';

/// Items with no recipe yet (cost unknown → "Recipe incomplete").
const Set<String> homeItemsWithoutRecipe = {
  'v60',
  'turkish',
  'hibiscus',
  'green_tea',
  'lemon_tart',
  'turkey_croissant',
};

/// Ingredient cost as a share of the menu price, by category: coffee is
/// cheap to pour, food carries its ingredients.
const Map<String, double> _categoryCostRatio = {
  'hot': 0.24,
  'iced': 0.27,
  'tea': 0.22,
  'juice': 0.36,
  'bakery': 0.34,
  'dessert': 0.33,
  'breakfast': 0.38,
};

/// The items whose recipe costs run over the category's usual share
/// (pistachio paste, avocados, a skillet of eggs): the margin watch's
/// "Needs attention" list.
const Map<String, double> _itemCostRatio = {
  'pistachio_latte': 0.47,
  'avocado': 0.58,
  'shakshuka': 0.52,
  'almond_croissant': 0.44,
};

final Map<String, SeedItem> _itemsById = {
  for (final m in seedMenu) MockSeed.menuItemId(m.key): m,
};

final Map<String, String> _categoryIds = {
  for (final c in seedCategories) MockSeed.categoryId(c.key): c.key,
};

/// The size label a line carries for [m]'s size [label] (`one_size` for a
/// single-size item, as the ledger keys it).
String _skuLabel(SeedItem m, String label) =>
    m.sizes.length > 1 ? label : 'one_size';

/// Every (item, size) on the menu: the ledger's catalog rows.
Set<(String, String)> homeCatalogSkus() => _catalog;

final Set<(String, String)> _catalog = {
  for (final m in seedMenu)
    for (final (label, _) in m.sizes)
      (MockSeed.menuItemId(m.key), _skuLabel(m, label)),
};

/// The recipe cost of one [itemId] in size [sizeLabel], in piastres; null
/// when the item has no recipe (or is not one of the seed's).
int? homeUnitCost(String itemId, String sizeLabel) {
  final m = _itemsById[itemId];
  if (m == null || homeItemsWithoutRecipe.contains(m.key)) return null;
  final ratio = _itemCostRatio[m.key] ?? _categoryCostRatio[m.category] ?? 0.3;
  for (final (label, egp) in m.sizes) {
    if (_skuLabel(m, label) == sizeLabel) return (egp * 100 * ratio).round();
  }
  return null;
}

/// The seed category id of [itemId].
String? homeCategoryOf(String itemId) {
  final m = _itemsById[itemId];
  return m == null ? null : MockSeed.categoryId(m.category);
}

/// A category's English name ('' when unknown).
String? homeCategoryName(String categoryId) {
  final key = _categoryIds[categoryId];
  if (key == null) return null;
  return seedCategories.firstWhere((c) => c.key == key).name;
}

/// A category's names by language.
Map<String, Object?> homeCategoryNames(String categoryId) {
  final key = _categoryIds[categoryId];
  if (key == null) return const {};
  final c = seedCategories.firstWhere((c) => c.key == key);
  return MockSeed.tr(c.name, c.ar);
}

/// An item's English name.
String homeItemName(String itemId) => _itemsById[itemId]?.name ?? '';

/// An item's names by language.
Map<String, Object?> homeItemNames(String itemId) {
  final m = _itemsById[itemId];
  return m == null ? const {} : MockSeed.tr(m.name, m.ar);
}

/// How many active menu items have a recipe (the onboarding `recipes` step).
int homeItemsWithRecipes() =>
    seedMenu.where((m) => !homeItemsWithoutRecipe.contains(m.key)).length;
