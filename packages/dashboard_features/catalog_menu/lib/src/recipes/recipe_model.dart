/// The recipe builder's arithmetic, ported from the web's
/// `features/recipes/recipe-builder.tsx` so it can be checked without a
/// screen: the rows as typed, the seed key that decides when the host's rows
/// replace the draft (MENU-RCP-001), the rows that count (MENU-RCP-014), a
/// size's cost and margin (MENU-RCP-007/008), a line's cost (MENU-RCP-011),
/// scaling from the base size (MENU-RCP-005) and the standalone save's
/// "removed" list.
library;

import 'package:flutter/foundation.dart';

import '../shared/menu_text.dart';

/// One row as edited (the web's `BuilderRow`): the quantity is the text in
/// the box. [id] only keeps a row's widgets attached to it; it is not part
/// of the row's content.
@immutable
class RecipeDraftRow {
  const RecipeDraftRow({
    required this.id,
    required this.sizeLabel,
    required this.ingredientName,
    required this.ingredientUnit,
    required this.quantity,
    this.orgIngredientId,
  });

  final int id;
  final String sizeLabel;
  final String? orgIngredientId;
  final String ingredientName;
  final String ingredientUnit;
  final String quantity;

  RecipeDraftRow copyWith({
    int? id,
    String? sizeLabel,
    String? Function()? orgIngredientId,
    String? ingredientName,
    String? ingredientUnit,
    String? quantity,
  }) => RecipeDraftRow(
    id: id ?? this.id,
    sizeLabel: sizeLabel ?? this.sizeLabel,
    orgIngredientId: orgIngredientId != null
        ? orgIngredientId()
        : this.orgIngredientId,
    ingredientName: ingredientName ?? this.ingredientName,
    ingredientUnit: ingredientUnit ?? this.ingredientUnit,
    quantity: quantity ?? this.quantity,
  );

  /// The same content (size, ingredient, name, unit, quantity text).
  bool sameContent(RecipeDraftRow o) =>
      sizeLabel == o.sizeLabel &&
      orgIngredientId == o.orgIngredientId &&
      ingredientName == o.ingredientName &&
      ingredientUnit == o.ingredientUnit &&
      quantity == o.quantity;
}

/// The web's `isDirty`: the rows differ from the baseline (order counts).
bool recipeRowsDiffer(List<RecipeDraftRow> a, List<RecipeDraftRow> b) {
  if (a.length != b.length) return true;
  for (var i = 0; i < a.length; i++) {
    if (!a[i].sameContent(b[i])) return true;
  }
  return false;
}

/// The web's `initialKey`: every initial row as `size::name=quantity`,
/// sorted and joined. The draft is re-seeded only when this changes, so a
/// host that rebuilds with equal rows keeps the person's edits.
String recipeSeedKey(
  Iterable<({String sizeLabel, String ingredientName, double quantityUsed})>
  rows,
) {
  final parts = [
    for (final r in rows)
      '${r.sizeLabel}::${r.ingredientName}=${jsNumberText(r.quantityUsed)}',
  ]..sort();
  return parts.join('|');
}

/// A row that counts (`cleanRows`): a name and a finite quantity above zero.
typedef RecipeCleanLine = ({
  String sizeLabel,
  String? orgIngredientId,
  String ingredientName,
  String ingredientUnit,
  double quantityUsed,
});

/// The rows that count, in order; the rest are dropped silently
/// (MENU-RCP-014).
List<RecipeCleanLine> cleanRecipeRows(Iterable<RecipeDraftRow> rows) => [
  for (final r in rows)
    if (r.ingredientName.isNotEmpty &&
        jsParseFloat(r.quantity).isFinite &&
        jsParseFloat(r.quantity) > 0)
      (
        sizeLabel: r.sizeLabel,
        orgIngredientId: r.orgIngredientId,
        ingredientName: r.ingredientName,
        ingredientUnit: r.ingredientUnit,
        quantityUsed: jsParseFloat(r.quantity),
      ),
];

/// The standalone save's `removed`: initial rows whose `size::name` is no
/// longer among the rows that count.
List<({String sizeLabel, String ingredientName})> removedRecipeRows(
  Iterable<({String sizeLabel, String ingredientName})> initial,
  Iterable<RecipeCleanLine> cleaned,
) {
  final kept = {for (final c in cleaned) '${c.sizeLabel}::${c.ingredientName}'};
  return [
    for (final r in initial)
      if (!kept.contains('${r.sizeLabel}::${r.ingredientName}'))
        (sizeLabel: r.sizeLabel, ingredientName: r.ingredientName),
  ];
}

/// A line's cost in piastres (unit cost × quantity), or null when the unit
/// cost is unknown or the quantity is not a number (shown as "—").
double? recipeLineCost(double? unitCost, String quantity) {
  final q = jsParseFloat(quantity);
  if (unitCost == null || !q.isFinite) return null;
  return unitCost * q;
}

/// A size's estimate (`Σ unit cost × quantity`): null with no rows, or as
/// soon as one row lacks a positive unit cost or a numeric quantity.
double? recipeSizeEstimate(
  Iterable<RecipeDraftRow> rows,
  double? Function(String? ingredientId) unitCostOf,
) {
  double? estimate;
  var any = false;
  for (final r in rows) {
    any = true;
    final cost = recipeLineCost(unitCostOf(r.orgIngredientId), r.quantity);
    if (cost == null) return null;
    estimate = (estimate ?? 0) + cost;
  }
  return any ? estimate ?? 0 : null;
}

/// `(price − cost) / price`, shown only when the cost is known and the price
/// is above zero.
double? recipeMargin(double? estimate, int? price) {
  if (estimate == null || price == null || price <= 0) return null;
  return (price - estimate) / price;
}

/// How a margin reads: green from 60 %, plain from 30 %, amber below.
enum RecipeMarginTone { good, fair, low }

RecipeMarginTone recipeMarginTone(double margin) => margin >= 0.6
    ? RecipeMarginTone.good
    : margin >= 0.3
    ? RecipeMarginTone.fair
    : RecipeMarginTone.low;

/// "Apply scaling": every non-base size whose factor is a number above zero
/// gets the base size's rows with each quantity × factor, rounded to 3
/// decimals (a blank quantity stays blank); an untouched factor box counts
/// as × 1. A size whose box was cleared (or holds 0) keeps its rows as they
/// are (the web drops them; see the divergences file). [nextId] numbers the
/// new rows.
List<RecipeDraftRow> scaleRecipeRows(
  List<RecipeDraftRow> rows,
  List<String> sizes,
  Map<String, String> factors,
  int Function() nextId,
) {
  if (sizes.length < 2) return rows;
  final base = sizes.first;
  final baseRows = [
    for (final r in rows)
      if (r.sizeLabel == base) r,
  ];
  final scaled = <String, double>{};
  for (final size in sizes.skip(1)) {
    final f = jsParseFloat(factors[size] ?? '1');
    if (f.isFinite && f > 0) scaled[size] = f;
  }
  return [
    for (final r in rows)
      if (!scaled.containsKey(r.sizeLabel)) r,
    for (final MapEntry(key: size, value: f) in scaled.entries)
      for (final r in baseRows)
        r.copyWith(
          id: nextId(),
          sizeLabel: size,
          quantity: jsParseFloat(r.quantity).isFinite
              ? fmtQty(jsParseFloat(r.quantity) * f)
              : '',
        ),
  ];
}
