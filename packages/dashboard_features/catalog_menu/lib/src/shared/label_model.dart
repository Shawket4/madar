/// Lines keyed by an optional size label (recipe bases, per-size option
/// amounts) to grid columns and back (the web's `recipe/label-model.ts`).
/// Column [allSizes] holds the unlabelled lines ("every size"); every other
/// column is one exact size label and wins over it for that size.
library;

import 'grid_model.dart';
import 'menu_text.dart';

/// The "All sizes" column key.
const String allSizes = '*';

/// One stored line: an optional size label, an ingredient, a quantity, a unit.
typedef LabelledLine = ({
  String? sizeLabel,
  String ingredientId,
  Object quantity,
  String unit,
});

/// A wire line built from the grid (blank cells dropped).
typedef WireLabelledLine = ({
  String? sizeLabel,
  String ingredientId,
  double quantity,
  String unit,
});

/// `labelKey`: `L:<label>`, or [allSizes] for no label.
String labelKey(String? label) =>
    label == null || label.isEmpty ? allSizes : 'L:$label';

/// `toLabelBlocks`: the All sizes column ([allLabel] is its header), then one
/// column per label in first-seen order (lines first, then [extraLabels]).
List<GridBlock> toLabelBlocks(
  List<LabelledLine> lines,
  List<String> extraLabels,
  String allLabel,
) {
  final labels = <String>[];
  void push(String? l) {
    if (l != null && l.isNotEmpty && !labels.contains(l)) labels.add(l);
  }

  for (final l in lines) {
    push(l.sizeLabel);
  }
  extraLabels.forEach(push);
  final keys = [allSizes, for (final l in labels) labelKey(l)];
  final names = [allLabel, ...labels];
  final byKey = {for (final k in keys) k: <GridLine>[]};
  for (final l in lines) {
    final q = l.quantity;
    final n = q is num ? q.toDouble() : jsNumber(q.toString());
    byKey[labelKey(l.sizeLabel)]?.add(
      GridLine(
        ingredientId: l.ingredientId,
        quantity: n.isFinite ? fmtQty(n) : q.toString(),
        unit: l.unit,
      ),
    );
  }
  return [
    for (final (i, k) in keys.indexed)
      GridBlock(key: k, label: names[i], lines: byKey[k]!),
  ];
}

/// `fromLabelBlocks`: grid to flat lines; blank cells dropped, the All sizes
/// column written with no label.
List<WireLabelledLine> fromLabelBlocks(List<GridBlock> blocks) => [
  for (final b in blocks)
    for (final l in b.lines)
      if (l.ingredientId.isNotEmpty &&
          l.quantity.trim().isNotEmpty &&
          jsNumber(l.quantity).isFinite)
        (
          sizeLabel: b.key == allSizes ? null : b.label,
          ingredientId: l.ingredientId,
          quantity: jsNumber(l.quantity),
          unit: l.unit,
        ),
];

/// `removeLabelColumn`: drops a label column (its lines go with it); the All
/// sizes column can never be removed.
List<GridBlock> removeLabelColumn(List<GridBlock> blocks, String key) =>
    key == allSizes
    ? blocks
    : [
        for (final b in blocks)
          if (b.key != key) b,
      ];

/// `addLabelColumn`: a new label column with a blank cell for every row the
/// grid has (a label already there changes nothing).
List<GridBlock> addLabelColumn(List<GridBlock> blocks, String label) {
  if (blocks.any((b) => b.key == labelKey(label))) return blocks;
  final ingredients = <String, String>{};
  for (final b in blocks) {
    for (final l in b.lines) {
      ingredients[l.ingredientId] = l.unit;
    }
  }
  return [
    ...blocks,
    GridBlock(
      key: labelKey(label),
      label: label,
      lines: [
        for (final e in ingredients.entries)
          GridLine(ingredientId: e.key, quantity: '', unit: e.value),
      ],
    ),
  ];
}
