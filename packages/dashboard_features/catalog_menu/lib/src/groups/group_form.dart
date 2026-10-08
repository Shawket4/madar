/// The group editor's form state and its validation (the web's
/// `makeGroupSchema` in `group-model.ts`, the form values of
/// `group-editor-dialog.tsx` and the per-size grid state of
/// `option-size-grid.tsx`). Pure Dart: the dialog holds one [GroupDraft] and
/// asks [validateGroup] for the messages to show.
///
/// Divergences from the web (logged in
/// `docs/fdash/divergences/catalog_menu-groups.md`):
/// - a field the form hides is not validated (MENU-GRP-049): the "Up to…"
///   count only while "Up to…" shows, ingredient lines only while "Adds
///   ingredients" shows them, the swap fields only for a swap group;
/// - a per-size grid with a cell of 0 shows "Enter an amount above 0" under
///   the grid instead of blocking Save with no message;
/// - every message shows at once (the web's superRefine messages wait for
///   the plain ones).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../shared/grid_model.dart';
import '../shared/label_model.dart';
import '../shared/menu_text.dart';
import 'group_model.dart';

/// One option row as the editor holds it.
class OptionDraft {
  OptionDraft({
    required this.key,
    this.id,
    this.name = '',
    this.nameAr = '',
    this.price = '0',
    this.isActive = true,
    this.isDefault = false,
    this.swapIngredientId = '',
    List<OptionLineDraft>? lines,
    bool? perSize,
  }) : lines = lines ?? [],
       perSize = perSize ?? (lines ?? const []).any(_labelled);

  /// A stable identity for the row's widgets (the web's field-array id).
  final Key key;

  /// The server id; null for a row added in this session.
  final String? id;
  String name;
  String nameAr;

  /// EGP as typed.
  String price;
  bool isActive;
  bool isDefault;

  /// Swap groups: the one ingredient the option pours instead.
  String swapIngredientId;

  /// Adds groups: the lines deducted when chosen (`sizeLabel` null = every
  /// size). The source of truth; the per-size grid writes through it.
  List<OptionLineDraft> lines;

  /// "Different amounts per size" (starts on when any line has a label).
  bool perSize;

  /// The per-size grid once fixed (toggled on or edited); null = derived from
  /// [lines] and the attached items' size labels on every build, so labels
  /// that load later still show as columns (the web's `blocks ?? seed()`).
  List<GridBlock>? blocks;

  static bool _labelled(OptionLineDraft l) => (l.sizeLabel ?? '').isNotEmpty;

  /// The grid's columns: every attached item's size label plus any label
  /// already on a line (a size since renamed).
  static List<String> columnLabels(
    List<String> itemSizeLabels,
    List<OptionLineDraft> lines,
  ) {
    final set = <String>[...itemSizeLabels];
    for (final l in lines) {
      final s = l.sizeLabel;
      if (s != null && s.isNotEmpty && !set.contains(s)) set.add(s);
    }
    return set;
  }

  /// `seed()`: the lines as label columns.
  List<GridBlock> seedBlocks(List<String> itemSizeLabels, String allLabel) =>
      toLabelBlocks(
        [
          for (final l in lines)
            (
              sizeLabel: l.sizeLabel,
              ingredientId: l.ingredientId,
              quantity: l.quantity,
              unit: l.unit,
            ),
        ],
        columnLabels(itemSizeLabels, lines),
        allLabel,
      );

  /// The grid as shown now.
  List<GridBlock> currentBlocks(List<String> itemSizeLabels, String allLabel) =>
      blocks ?? seedBlocks(itemSizeLabels, allLabel);

  /// A grid edit: fixes the grid and writes the cleaned lines back (blank
  /// cells dropped, the All sizes column unlabelled).
  void setBlocks(List<GridBlock> next) {
    blocks = next;
    lines = [
      for (final l in fromLabelBlocks(next))
        OptionLineDraft(
          ingredientId: l.ingredientId,
          quantity: jsNumberText(l.quantity),
          unit: l.unit,
          sizeLabel: l.sizeLabel,
        ),
    ];
  }

  /// The switch: on fixes the grid from the lines (lines with no ingredient
  /// are dropped first, the grid cannot show them); off keeps only the
  /// unlabelled lines.
  void togglePerSize(bool on, List<String> itemSizeLabels, String allLabel) {
    perSize = on;
    if (on) {
      lines = [
        for (final l in lines)
          if (l.ingredientId.isNotEmpty) l,
      ];
      blocks = seedBlocks(itemSizeLabels, allLabel);
    } else {
      blocks = null;
      lines = [
        for (final l in lines)
          if (!_labelled(l)) l,
      ];
    }
  }
}

/// The whole form.
class GroupDraft {
  GroupDraft({
    this.name = '',
    this.nameAr = '',
    this.pick = PickKind.any,
    this.upTo = '1',
    this.effect = GroupEffect.adds,
    this.swapCategoryId = '',
    this.isActive = true,
    List<OptionDraft>? options,
  }) : options = options ?? [];

  String name;
  String nameAr;
  PickKind pick;

  /// The "Up to…" count as typed.
  String upTo;
  GroupEffect effect;
  String swapCategoryId;
  bool isActive;
  List<OptionDraft> options;

  /// The count as a number (`z.coerce.number()`: blank reads 0).
  int get upToCount {
    final n = jsNumber(upTo);
    return n.isFinite ? n.truncate() : 0;
  }

  /// `formPickRule`.
  PickRule get pickRule =>
      formPickRule(pick: pick, upTo: upToCount, effect: effect);

  /// One default per single-choice group: a swap group, "Exactly 1", or
  /// "Up to 1" (MENU-GRP-035).
  bool get singleChoice =>
      effect == GroupEffect.swaps ||
      pick == PickKind.exactlyOne ||
      (pick == PickKind.upTo && upToCount == 1);

  /// An option's Default turned on: in a single-choice group every other
  /// option's Default goes off.
  void setDefault(int index, bool on) {
    options[index].isDefault = on;
    if (!on || !singleChoice) return;
    for (var k = 0; k < options.length; k++) {
      if (k != index) options[k].isDefault = false;
    }
  }
}

/// The editor's messages (the web's `GroupSchemaMessages`, plus the words
/// zod would print for a price that is not a number or is below 0).
class GroupMessages {
  const GroupMessages({
    required this.required,
    required this.maxAtLeastOne,
    required this.swapNeedsIngredient,
    required this.swapNeedsCategory,
    required this.duplicateIngredient,
    required this.qtyPositive,
    required this.priceMin,
    required this.notANumber,
  });

  final String required;
  final String maxAtLeastOne;
  final String swapNeedsIngredient;
  final String swapNeedsCategory;
  final String duplicateIngredient;
  final String qtyPositive;
  final String priceMin;
  final String notANumber;
}

/// The message paths [validateGroup] reports.
abstract final class GroupField {
  static const String name = 'name';
  static const String upTo = 'up_to';
  static const String swapCategory = 'swap_category_id';
  static String optionName(int i) => 'options.$i.name';
  static String optionPrice(int i) => 'options.$i.price';
  static String optionSwap(int i) => 'options.$i.swap_ingredient_id';
  static String lineIngredient(int i, int j) =>
      'options.$i.lines.$j.ingredient_id';
  static String lineQuantity(int i, int j) => 'options.$i.lines.$j.quantity';
  static String optionGrid(int i) => 'options.$i.grid';
}

/// Every message the form shows now; empty = it may be saved.
Map<String, String> validateGroup(GroupDraft d, GroupMessages m) {
  final errors = <String, String>{};
  if (d.name.trim().isEmpty) errors[GroupField.name] = m.required;
  if (d.effect != GroupEffect.swaps &&
      d.pick == PickKind.upTo &&
      d.upToCount < 1) {
    errors[GroupField.upTo] = m.maxAtLeastOne;
  }
  if (d.effect == GroupEffect.swaps && d.swapCategoryId.isEmpty) {
    errors[GroupField.swapCategory] = m.swapNeedsCategory;
  }
  for (final (i, o) in d.options.indexed) {
    if (o.name.trim().isEmpty) errors[GroupField.optionName(i)] = m.required;
    final price = jsNumber(o.price);
    if (price.isNaN) {
      errors[GroupField.optionPrice(i)] = m.notANumber;
    } else if (price < 0) {
      errors[GroupField.optionPrice(i)] = m.priceMin;
    }
    if (d.effect == GroupEffect.swaps && o.swapIngredientId.isEmpty) {
      errors[GroupField.optionSwap(i)] = m.swapNeedsIngredient;
    }
    if (d.effect != GroupEffect.adds) continue;
    if (o.perSize) {
      if (o.lines.any((l) => !(jsNumber(l.quantity) > 0))) {
        errors[GroupField.optionGrid(i)] = m.qtyPositive;
      }
      continue;
    }
    final seen = <String>{};
    for (final (j, l) in o.lines.indexed) {
      if (l.ingredientId.isEmpty) {
        errors[GroupField.lineIngredient(i, j)] = m.required;
      }
      final q = jsNumber(l.quantity);
      if (q.isNaN) {
        errors[GroupField.lineQuantity(i, j)] = m.notANumber;
      } else if (q <= 0) {
        errors[GroupField.lineQuantity(i, j)] = m.qtyPositive;
      }
      final key = lineKey(l.ingredientId, l.sizeLabel);
      if (l.ingredientId.isNotEmpty && seen.contains(key)) {
        errors[GroupField.lineIngredient(i, j)] = m.duplicateIngredient;
      }
      seen.add(key);
    }
  }
  return errors;
}

/// What an option's lines cost when every line's ingredient is costed in the
/// line's own unit (piastres), else null (MENU-GRP-039). [costOf] gives an
/// ingredient's `(costPerUnit, unit)`, or null when it is not in the catalog.
double? optionLinesCost(
  List<OptionLineDraft> lines,
  ({double? costPerUnit, String unit})? Function(String ingredientId) costOf,
) {
  if (lines.isEmpty) return null;
  var sum = 0.0;
  for (final l in lines) {
    final ing = costOf(l.ingredientId);
    final qty = jsNumber(l.quantity);
    if (ing == null ||
        ing.costPerUnit == null ||
        !qty.isFinite ||
        l.unit != ing.unit) {
      return null;
    }
    sum += ing.costPerUnit! * qty;
  }
  return sum;
}

/// A stable text of the lines, for "did this option's set change".
String linesText(List<OptionLineDraft> lines) => jsonEncode([
  for (final l in lines) [l.ingredientId, l.quantity, l.unit, l.sizeLabel],
]);
