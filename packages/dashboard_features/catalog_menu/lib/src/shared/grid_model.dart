/// The pure model behind every ingredients-by-size grid of the area (the web's
/// `features/menu/recipe/grid-model.ts`): the studio recipe grid (rows =
/// ingredients, columns = sizes) and the label grids of recipe bases,
/// packaging rules and per-size option amounts.
///
/// Only `own` lines are editable and written; lines the server expanded from a
/// recipe base, a packaging rule or a linked item are shown read-only and
/// never sent. Every edit returns new lists.
library;

import 'dart:convert';

import 'menu_text.dart';

/// Where a stored size recipe line came from. Legacy rows (`null`) are own.
enum LineSource {
  own,
  base,
  rule,
  linked;

  /// `normalizeSource`: anything but `base`/`rule`/`linked` is own.
  static LineSource fromWire(String? s) => switch (s) {
    'base' => LineSource.base,
    'rule' => LineSource.rule,
    'linked' => LineSource.linked,
    _ => LineSource.own,
  };

  /// Pivot order: own and linked first, then base, then rule.
  int get order => switch (this) {
    LineSource.own || LineSource.linked => 0,
    LineSource.base => 1,
    LineSource.rule => 2,
  };
}

/// One line of one column: an ingredient, the quantity as typed, its unit.
class GridLine {
  const GridLine({
    required this.ingredientId,
    required this.quantity,
    required this.unit,
    this.source = LineSource.own,
  });

  final String ingredientId;

  /// The quantity as typed (may be blank).
  final String quantity;
  final String unit;
  final LineSource source;

  bool get isOwn => source == LineSource.own;

  GridLine withQuantity(String q) => GridLine(
    ingredientId: ingredientId,
    quantity: q,
    unit: unit,
    source: source,
  );

  @override
  bool operator ==(Object other) =>
      other is GridLine &&
      other.ingredientId == ingredientId &&
      other.quantity == quantity &&
      other.unit == unit &&
      other.source == source;

  @override
  int get hashCode => Object.hash(ingredientId, quantity, unit, source);

  @override
  String toString() =>
      'GridLine($ingredientId, "$quantity" $unit, ${source.name})';
}

/// One column: a size (studio) or a size label (label grids).
class GridBlock {
  const GridBlock({
    required this.key,
    required this.label,
    this.lines = const [],
    this.id,
    this.baseId,
  });

  /// Stable column key (a size id, `new-1`, `*`, `L:<label>`).
  final String key;

  /// The saved size's id, when it has one.
  final String? id;
  final String label;
  final String? baseId;
  final List<GridLine> lines;

  /// This column with other lines. A subclass carrying more draft fields
  /// (price, …) overrides this to keep them.
  GridBlock withLines(List<GridLine> lines) =>
      GridBlock(key: key, id: id, label: label, baseId: baseId, lines: lines);
}

/// A line that would be written: own, with an ingredient and a finite
/// quantity.
typedef OwnLine = ({String ingredientId, double quantity, String unit});

/// `ownPayload`: the own lines with an ingredient and a finite quantity.
List<OwnLine> ownPayload(List<GridLine> lines) => [
  for (final l in lines)
    if (l.isOwn &&
        l.ingredientId.isNotEmpty &&
        l.quantity.trim().isNotEmpty &&
        jsNumber(l.quantity).isFinite)
      (
        ingredientId: l.ingredientId,
        quantity: jsNumber(l.quantity),
        unit: l.unit,
      ),
];

/// `ownRecipeSig`: the dirty signature of one size's recipe (only what a save
/// would send).
String ownRecipeSig(List<GridLine> lines) => jsonEncode([
  for (final l in ownPayload(lines))
    [l.ingredientId, _jsonNumber(l.quantity), l.unit],
]);

Object _jsonNumber(double v) => v == v.truncateToDouble() ? v.toInt() : v;

/// `changedSizeKeys`: keys of columns whose own recipe differs from
/// [pristine] (a column with no pristine entry counts as changed).
Set<String> changedSizeKeys(
  List<GridBlock> blocks,
  Map<String, String> pristine,
) => {
  for (final b in blocks)
    if (pristine[b.key] == null || ownRecipeSig(b.lines) != pristine[b.key])
      b.key,
};

/// One grid row: an ingredient from one source across the columns.
class GridRow {
  GridRow({
    required this.key,
    required this.ingredientId,
    required this.source,
    required this.unit,
  });

  /// `own:<ingredient>`, `base:<ingredient>`, …
  final String key;
  final String ingredientId;
  final LineSource source;
  final String unit;

  /// Quantity per column key; absent = no line in that column.
  final Map<String, String> cells = {};

  /// Column keys that carry this row (the first names the base, for tags).
  final List<String> blockKeys = [];
}

/// `buildGridRows`: one row per (source, ingredient), own/linked first, then
/// base, then rule; insertion order within each.
List<GridRow> buildGridRows(List<GridBlock> blocks) {
  final rows = <String, GridRow>{};
  for (final b in blocks) {
    for (final l in b.lines) {
      if (l.ingredientId.isEmpty) continue;
      final key = '${l.source.name}:${l.ingredientId}';
      final row = rows.putIfAbsent(
        key,
        () => GridRow(
          key: key,
          ingredientId: l.ingredientId,
          source: l.source,
          unit: l.unit,
        ),
      );
      row.cells[b.key] = l.quantity;
      row.blockKeys.add(b.key);
    }
  }
  final indexed = rows.values.indexed.toList()
    ..sort((a, b) {
      final c = a.$2.source.order - b.$2.source.order;
      return c != 0 ? c : a.$1 - b.$1;
    });
  return [for (final e in indexed) e.$2];
}

List<B> _mapBlock<B extends GridBlock>(
  List<B> blocks,
  String key,
  GridBlock Function(B b) fn,
) => [for (final b in blocks) b.key == key ? fn(b) as B : b];

/// `setCell`: sets (or adds) the own quantity of [ingredientId] in one column.
List<B> setCell<B extends GridBlock>(
  List<B> blocks,
  String blockKey,
  String ingredientId,
  String quantity,
  String unit,
) => _mapBlock(blocks, blockKey, (b) {
  final idx = b.lines.indexWhere(
    (l) => l.isOwn && l.ingredientId == ingredientId,
  );
  if (idx == -1) {
    return b.withLines([
      ...b.lines,
      GridLine(ingredientId: ingredientId, quantity: quantity, unit: unit),
    ]);
  }
  return b.withLines([
    for (final (i, l) in b.lines.indexed)
      i == idx ? l.withQuantity(quantity) : l,
  ]);
});

/// `addRow`: an own row with an empty cell in every column lacking it.
List<B> addRow<B extends GridBlock>(
  List<B> blocks,
  String ingredientId,
  String unit,
) => [
  for (final b in blocks)
    b.lines.any((l) => l.isOwn && l.ingredientId == ingredientId)
        ? b
        : b.withLines([
                ...b.lines,
                GridLine(ingredientId: ingredientId, quantity: '', unit: unit),
              ])
              as B,
];

/// `removeRow`: drops the own lines of [ingredientId] from every column.
List<B> removeRow<B extends GridBlock>(List<B> blocks, String ingredientId) => [
  for (final b in blocks)
    b.withLines([
          for (final l in b.lines)
            if (!(l.isOwn && l.ingredientId == ingredientId)) l,
        ])
        as B,
];

/// `scaleQty`: blanks stay blank, numbers are multiplied and rounded to 3
/// decimals, anything else is kept as typed.
String scaleQty(String quantity, double factor) {
  if (quantity.trim().isEmpty) return quantity;
  final n = jsNumber(quantity);
  return n.isFinite ? fmtQty(n * factor) : quantity;
}

/// `copyColumn`: replaces the own lines of [toKey] with those of [fromKey]
/// (optionally scaled); the target's base/rule/linked lines stay.
List<B> copyColumn<B extends GridBlock>(
  List<B> blocks,
  String fromKey,
  String toKey, [
  double factor = 1,
]) {
  final from = blocks.where((b) => b.key == fromKey).firstOrNull;
  if (from == null || fromKey == toKey) {
    return factor == 1 ? blocks : scaleColumn(blocks, toKey, factor);
  }
  final copied = [
    for (final l in from.lines)
      if (l.isOwn)
        GridLine(
          ingredientId: l.ingredientId,
          quantity: scaleQty(l.quantity, factor),
          unit: l.unit,
        ),
  ];
  return _mapBlock(
    blocks,
    toKey,
    (b) => b.withLines([...copied, ...b.lines.where((l) => !l.isOwn)]),
  );
}

/// `scaleColumn`: multiplies every own quantity of one column by [factor].
List<B> scaleColumn<B extends GridBlock>(
  List<B> blocks,
  String key,
  double factor,
) => _mapBlock(
  blocks,
  key,
  (b) => b.withLines([
    for (final l in b.lines)
      l.isOwn ? l.withQuantity(scaleQty(l.quantity, factor)) : l,
  ]),
);

/// Ingredient category slugs whose line a choice group can swap.
const Set<String> swappableSlugs = {'milk', 'coffee_bean'};

/// A group attached to the item, for the "swappable" badge.
typedef SwapGroupInfo = ({String name, List<String> ingredientIds});

/// `swapGroupFor`: the first attached group offering an option whose
/// ingredient is in the row's (swappable) category, by name.
String? swapGroupFor(
  String? categorySlug,
  List<SwapGroupInfo> groups,
  String? Function(String ingredientId) slugOf,
) {
  if (categorySlug == null || !swappableSlugs.contains(categorySlug)) {
    return null;
  }
  for (final g in groups) {
    if (g.ingredientIds.any((id) => slugOf(id) == categorySlug)) return g.name;
  }
  return null;
}
