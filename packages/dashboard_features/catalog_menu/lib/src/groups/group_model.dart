/// The owner-facing model of a choice group and its pure mappings onto the
/// wire fields (the web's `features/menu/groups/group-model.ts`, inventory
/// §8.15): the pick rule, what choosing does, the legacy type a new group is
/// written with, and the recipe replace-set each option writes. Nothing here
/// talks to the API.
library;

import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart' show GroupOut;

import '../shared/menu_text.dart';

// ── Pick rule ⇄ selection_type / min / max / is_required ─────────────────

enum PickKind { exactlyOne, upTo, any }

/// "Exactly 1", "Up to n" or "Any number".
class PickRule {
  const PickRule.exactlyOne() : kind = PickKind.exactlyOne, max = 1;
  const PickRule.upTo(this.max) : kind = PickKind.upTo;
  const PickRule.any() : kind = PickKind.any, max = 0;

  final PickKind kind;

  /// The cap of an `upTo` rule.
  final int max;

  @override
  bool operator ==(Object other) =>
      other is PickRule &&
      other.kind == kind &&
      (kind != PickKind.upTo || other.max == max);

  @override
  int get hashCode => Object.hash(kind, kind == PickKind.upTo ? max : 0);

  @override
  String toString() => kind == PickKind.upTo ? 'upTo($max)' : kind.name;
}

/// The wire fields a pick rule writes.
typedef SelectionFields = ({
  String selectionType,
  int minSelections,
  int? maxSelections,
  bool isRequired,
});

/// `pickRuleToSelection`.
SelectionFields pickRuleToSelection(PickRule rule) => switch (rule.kind) {
  PickKind.exactlyOne => (
    selectionType: 'single',
    minSelections: 1,
    maxSelections: 1,
    isRequired: true,
  ),
  PickKind.upTo => () {
    final max = rule.max < 1 ? 1 : rule.max;
    return (
      selectionType: max == 1 ? 'single' : 'multi',
      minSelections: 0,
      maxSelections: max,
      isRequired: false,
    );
  }(),
  PickKind.any => (
    selectionType: 'multi',
    minSelections: 0,
    maxSelections: null,
    isRequired: false,
  ),
};

/// `selectionToPickRule`: a stored group read back (lossy for shapes the
/// dashboard never writes, e.g. "at least 2 of 5" reads "up to 5").
PickRule selectionToPickRule({
  required String selectionType,
  required int minSelections,
  required int? maxSelections,
  required bool isRequired,
}) {
  if (maxSelections == 1 && (isRequired || minSelections >= 1)) {
    return const PickRule.exactlyOne();
  }
  if (maxSelections == null) {
    return selectionType == 'single'
        ? const PickRule.upTo(1)
        : const PickRule.any();
  }
  return PickRule.upTo(maxSelections);
}

// ── Effect ⇄ legacy_addon_type ───────────────────────────────────────────

enum GroupEffect {
  none,
  adds,
  swaps;

  static GroupEffect? fromWire(String? s) => switch (s) {
    'none' => none,
    'adds' => adds,
    'swaps' => swaps,
    _ => null,
  };
}

enum SwapTarget { milk, beans }

/// The two swap families the resolver understands (`is_swap_family`).
const Map<SwapTarget, String> swapTypes = {
  SwapTarget.milk: 'milk_type',
  SwapTarget.beans: 'coffee_type',
};

/// The ingredient category slug each family swaps on the server.
const Map<SwapTarget, String> swapSlugs = {
  SwapTarget.milk: 'milk',
  SwapTarget.beans: 'coffee_bean',
};

bool isSwapType(String? type) =>
    type != null && swapTypes.values.contains(type);

/// `effectToLegacyType`: the legacy type a NEW group is written with. Swaps
/// map to the family; anything else takes a type derived from the name
/// ("Red Bull Type" -> `red_bull_type`), `extra` when that is blank, a swap
/// type or starts with milk/coffee; [taken] (other groups' types) adds `_2`,
/// `_3`…
String effectToLegacyType(
  GroupEffect effect,
  SwapTarget? swapTarget,
  String name, [
  Iterable<String> taken = const [],
]) {
  if (effect == GroupEffect.swaps) {
    return swapTypes[swapTarget ?? SwapTarget.milk]!;
  }
  final slug = name
      .trim()
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  if (slug.isEmpty ||
      isSwapType(slug) ||
      RegExp(r'^(milk|coffee)(_|$)').hasMatch(slug)) {
    return 'extra';
  }
  final used = taken.toSet();
  if (!used.contains(slug)) return slug;
  var n = 2;
  while (used.contains('${slug}_$n')) {
    n++;
  }
  return '${slug}_$n';
}

/// `legacyTypeToEffect`.
({GroupEffect effect, SwapTarget? swapTarget}) legacyTypeToEffect(
  String? type,
  bool anyOptionHasLines,
) {
  if (type == swapTypes[SwapTarget.milk]) {
    return (effect: GroupEffect.swaps, swapTarget: SwapTarget.milk);
  }
  if (type == swapTypes[SwapTarget.beans]) {
    return (effect: GroupEffect.swaps, swapTarget: SwapTarget.beans);
  }
  return (
    effect: anyOptionHasLines ? GroupEffect.adds : GroupEffect.none,
    swapTarget: null,
  );
}

/// `groupEffect`: the explicit column, else inferred from the legacy type.
GroupEffect groupEffect({
  required String? effect,
  required String? legacyAddonType,
  required bool anyOptionHasLines,
}) =>
    GroupEffect.fromWire(effect) ??
    legacyTypeToEffect(legacyAddonType, anyOptionHasLines).effect;

/// `formPickRule`: swap groups always take exactly one.
PickRule formPickRule({
  required PickKind pick,
  required int upTo,
  required GroupEffect effect,
}) => effect == GroupEffect.swaps || pick == PickKind.exactlyOne
    ? const PickRule.exactlyOne()
    : pick == PickKind.upTo
    ? PickRule.upTo(upTo)
    : const PickRule.any();

// ── Option lines ─────────────────────────────────────────────────────────

/// One recipe line as the editor holds it: the quantity as typed, an
/// optional size label (`null` = every size).
class OptionLineDraft {
  const OptionLineDraft({
    required this.ingredientId,
    required this.quantity,
    required this.unit,
    this.sizeLabel,
  });

  final String ingredientId;
  final String quantity;
  final String unit;
  final String? sizeLabel;

  OptionLineDraft copyWith({
    String? ingredientId,
    String? quantity,
    String? unit,
  }) => OptionLineDraft(
    ingredientId: ingredientId ?? this.ingredientId,
    quantity: quantity ?? this.quantity,
    unit: unit ?? this.unit,
    sizeLabel: sizeLabel,
  );

  @override
  bool operator ==(Object other) =>
      other is OptionLineDraft &&
      other.ingredientId == ingredientId &&
      other.quantity == quantity &&
      other.unit == unit &&
      other.sizeLabel == sizeLabel;

  @override
  int get hashCode => Object.hash(ingredientId, quantity, unit, sizeLabel);
}

/// A line of an option's recipe replace-set (`OptionRecipeLineInput`).
typedef OptionWireLine = ({
  String ingredientId,
  double quantity,
  String unit,
  String? sizeLabel,
});

/// `optionRecipeLines`: what an option writes per effect — a swap pours one
/// line of 1 in the ingredient's unit, adds writes its typed lines, nothing
/// writes none.
List<OptionWireLine> optionRecipeLines(
  GroupEffect effect, {
  required String swapIngredientId,
  required List<OptionLineDraft> lines,
  required String? Function(String ingredientId) unitOf,
}) {
  switch (effect) {
    case GroupEffect.swaps:
      return swapIngredientId.isEmpty
          ? const []
          : [
              (
                ingredientId: swapIngredientId,
                quantity: 1,
                unit: unitOf(swapIngredientId) ?? 'pcs',
                sizeLabel: null,
              ),
            ];
    case GroupEffect.adds:
      return [
        for (final l in lines)
          if (l.ingredientId.isNotEmpty)
            (
              ingredientId: l.ingredientId,
              quantity: jsNumber(l.quantity),
              unit: l.unit,
              sizeLabel: (l.sizeLabel ?? '').isEmpty ? null : l.sizeLabel,
            ),
      ];
    case GroupEffect.none:
      return const [];
  }
}

/// `recipeSig`: compares two replace-sets.
String recipeSig(List<OptionWireLine> lines) => jsonEncode([
  for (final l in lines)
    [l.ingredientId, _num(l.quantity), l.unit, l.sizeLabel],
]);

Object _num(double q) =>
    q.isFinite && q == q.truncateToDouble() ? q.toInt() : (q.isNaN ? 'NaN' : q);

/// The key of the duplicate check: (ingredient, size label or "every size").
String lineKey(String ingredientId, String? sizeLabel) =>
    jsonEncode([ingredientId, (sizeLabel ?? '').isEmpty ? null : sizeLabel]);

// ── The list (groups-page.tsx) ───────────────────────────────────────────

/// The shared groups the page lists: the item-private "Options" sets (no
/// legacy type) are edited in each item's editor; by `sort`, then name.
List<GroupOut> sharedGroups(Iterable<GroupOut> all) =>
    [
      for (final g in all)
        if (g.legacyAddonType != null) g,
    ]..sort((a, b) {
      final c = a.sort - b.sort;
      return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

/// A row's pick-rule badge: (key, count for "up to").
(String, int?) pickBadge(GroupOut g) {
  final rule = selectionToPickRule(
    selectionType: g.selectionType,
    minSelections: g.minSelections,
    maxSelections: g.maxSelections,
    isRequired: g.isRequired,
  );
  return switch (rule.kind) {
    PickKind.exactlyOne => ('menu.groups.pick.exactlyOneShort', null),
    PickKind.upTo => ('menu.groups.pick.upToShort', rule.max),
    PickKind.any => ('menu.groups.pick.anyShort', null),
  };
}

/// Whether a row's effect badge is the filled one (it swaps).
bool groupSwaps(GroupOut g) =>
    g.effect == 'swaps' || isSwapType(g.legacyAddonType);

/// A row's effect badge key.
String effectBadgeKey(GroupOut g) {
  if (groupSwaps(g)) {
    if (g.swapCategorySlug == swapSlugs[SwapTarget.beans] ||
        g.legacyAddonType == swapTypes[SwapTarget.beans]) {
      return 'menu.groups.effect.swapsBeans';
    }
    final slug = g.swapCategorySlug;
    return slug != null && slug.isNotEmpty && slug != swapSlugs[SwapTarget.milk]
        ? 'menu.groups.effect.swapsOther'
        : 'menu.groups.effect.swapsMilk';
  }
  return switch (g.effect) {
    'adds' => 'menu.groups.effect.adds',
    'none' => 'menu.groups.effect.none',
    _ => 'menu.groups.effect.addsOrNothing',
  };
}

/// The name to show in [lang]: the Arabic one in Arabic when it is not
/// blank, else [name] (`getTranslatedName` would put an empty `ar` into a
/// sentence: "حذف ؟").
String shownName(String name, Object? translations, String lang) {
  final ar = arOf(translations).trim();
  return lang.startsWith('ar') && ar.isNotEmpty ? ar : name;
}

/// `arrayMove`.
List<T> arrayMove<T>(List<T> list, int from, int to) {
  final next = [...list];
  next.insert(to, next.removeAt(from));
  return next;
}
