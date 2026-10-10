/// The recipe builder's arithmetic, ported from the web's
/// `features/recipes/recipe-builder.tsx` so it can be checked without a
/// screen: the rows as typed, the seed key that decides when the host's rows
/// replace the draft (MENU-RCP-001), the rows that count (MENU-RCP-014), a
/// size's cost and margin (MENU-RCP-007/008), a line's cost (MENU-RCP-011),
/// scaling from the base size (MENU-RCP-005) and the standalone save's
/// "removed" list.
library;

import 'package:dashboard_api/dashboard_api.dart' show OrgIngredient;
import 'package:flutter/foundation.dart';
import 'package:rust_bridge_dashboard/rules.dart' as rules;

import 'menu_text.dart';

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

/// A line as madar-money costs it: [qty] typed in [unit], as the line
/// stores it (madar-units: through the ingredient's density, grossed up by
/// its yield), at the ingredient's cost. The cost is unknown (null) without
/// an ingredient or a cost, or when [qty] is not a number or does not
/// convert; a cost of 0 is known (free).
rules.CostLine recipeCostLine(OrgIngredient? ing, double qty, String unit) {
  final stored = ing == null || !qty.isFinite
      ? null
      : rules.recipeBaseQty(
          qty: qty,
          unit: unit,
          baseUnit: ing.unit,
          density: ing.densityGPerMl,
          yieldPct: ing.yieldPct,
        );
  return rules.CostLine(
    qty: stored ?? 0,
    costPerUnit: stored == null ? null : ing?.costPerUnit,
  );
}

/// A line's cost in whole piastres (madar-money through the core), or null
/// when it is unknown (shown as "—").
int? recipeLineCost(OrgIngredient? ing, String quantity, String unit) {
  final l = recipeCostLine(ing, jsParseFloat(quantity), unit);
  final cost = l.costPerUnit;
  return cost == null ? null : rules.lineCost(qty: l.qty, costPerUnit: cost);
}

/// madar-money's cost of [lines]: the known ones summed exactly and rounded
/// once, `complete` false when one is unknown. Null when every line is
/// unknown: the server has no figure then either.
rules.RecipeCost? recipeCostOf(List<rules.CostLine> lines) =>
    lines.isNotEmpty && lines.every((l) => l.costPerUnit == null)
    ? null
    : rules.recipeCost(lines: lines);

/// A size's cost ([recipeCostOf]); null with no rows.
rules.RecipeCost? recipeSizeEstimate(
  Iterable<RecipeDraftRow> rows,
  OrgIngredient? Function(String? ingredientId) ingredientOf,
) {
  final lines = [
    for (final r in rows)
      recipeCostLine(
        ingredientOf(r.orgIngredientId),
        jsParseFloat(r.quantity),
        r.ingredientUnit,
      ),
  ];
  return lines.isEmpty ? null : recipeCostOf(lines);
}

/// `(price − cost) / price` over the cost in whole piastres (madar-money);
/// only a complete cost with a price above zero has one.
double? recipeMargin(rules.RecipeCost? estimate, int? price) =>
    estimate == null || !estimate.complete || price == null
    ? null
    : rules.margin(price: price, cost: estimate.piastres);

/// How a margin reads: madar-money's food-cost band (good under 30 % food
/// cost, fair to 40 %, poor above), the food-cost chip's colours.
enum RecipeMarginTone { good, fair, poor }

/// Null without a price above zero.
RecipeMarginTone? recipeMarginTone(int cost, int price) =>
    switch (rules.foodCostBand(cost: cost, price: price)) {
      'good' => RecipeMarginTone.good,
      'fair' => RecipeMarginTone.fair,
      'poor' => RecipeMarginTone.poor,
      _ => null,
    };

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
