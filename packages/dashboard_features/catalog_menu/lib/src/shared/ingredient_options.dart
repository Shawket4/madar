/// The ingredient picker options every recipe editor of the area offers (the
/// web's `use-ingredient-picker.ts` and the recipe builder's own copy): the
/// ACTIVE ingredients, labelled by name, hinted by their unit word, and
/// searchable by their category name too.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';

import 'menu_text.dart';

/// Options for a searchable [DashSelect] of ingredients; [exclude] drops ids
/// already used (the grids' "+ ingredient" offers only new rows).
List<DashOption<String>> ingredientOptions(
  Iterable<OrgIngredient> catalog,
  Translator t, {
  Set<String> exclude = const {},
}) => [
  for (final c in catalog)
    if (c.isActive && !exclude.contains(c.id))
      DashOption<String>(
        value: c.id,
        label: c.name,
        hint: unitWord(t, c.unit),
        keywords: c.categoryName,
      ),
];

/// A positive unit cost (piastres per unit), else null (`costOf`).
double? positiveUnitCost(OrgIngredient? c) {
  final v = c?.costPerUnit;
  return v != null && v > 0 ? v : null;
}
