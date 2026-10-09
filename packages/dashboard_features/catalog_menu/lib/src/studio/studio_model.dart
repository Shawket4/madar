/// The Menu Studio's drafts and rules, as pure Dart (the web's
/// `features/menu/studio/util.ts`, the save validation and payloads of
/// `menu-studio-page.tsx`, the grid's cost footer of `recipe-grid.tsx`, the
/// base picker's value and `section-modifiers.tsx`'s allowlist toggle).
///
/// The page owns ONE dirty store: a draft per section plus a pristine
/// signature per section. A section is dirty when its current signature
/// differs from its pristine one; a save step re-baselines only its section.
library;

import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart' show egpToPiastres;

import '../shared/grid_model.dart';
import '../shared/menu_text.dart';

// ── Item details ────────────────────────────────────────────────────────────

/// The item details section's fields (`ItemDraftValues`).
class ItemDraft {
  const ItemDraft({
    this.name = '',
    this.nameAr = '',
    this.description = '',
    this.descriptionAr = '',
    this.categoryId = '',
    this.isActive = true,
  });

  final String name;
  final String nameAr;
  final String description;
  final String descriptionAr;

  /// `''` = no category.
  final String categoryId;
  final bool isActive;

  ItemDraft copyWith({
    String? name,
    String? nameAr,
    String? description,
    String? descriptionAr,
    String? categoryId,
    bool? isActive,
  }) => ItemDraft(
    name: name ?? this.name,
    nameAr: nameAr ?? this.nameAr,
    description: description ?? this.description,
    descriptionAr: descriptionAr ?? this.descriptionAr,
    categoryId: categoryId ?? this.categoryId,
    isActive: isActive ?? this.isActive,
  );

  /// `itemSig`.
  String get sig => jsonEncode([
    name,
    nameAr,
    description,
    descriptionAr,
    categoryId,
    isActive,
  ]);
}

/// `toItemValues`: the Arabic description is always seeded empty (the
/// aggregate does not return it).
ItemDraft toItemDraft(StudioAggregate s) => ItemDraft(
  name: s.name,
  nameAr: arOf(s.nameTranslations),
  description: s.description ?? '',
  categoryId: s.categoryId ?? '',
  isActive: s.isActive,
);

// ── Sizes, prices and recipes ───────────────────────────────────────────────

/// A size's server cost rollup (null piastres = unknown).
typedef ServerCost = ({int? piastres, bool incomplete});

/// One size column: the size row and its inline recipe (`SizeBlockDraft`).
class SizeBlock extends GridBlock {
  const SizeBlock({
    required super.key,
    required super.label,
    required this.price,
    super.id,
    super.baseId,
    super.lines,
    this.seededLabel,
    this.seededPrice,
    this.serverCost,
  });

  /// EGP as typed.
  final String price;

  /// The label and price it was seeded with (null for a new column).
  final String? seededLabel;
  final String? seededPrice;

  /// The server's rollup for a seeded size; null for a new one.
  final ServerCost? serverCost;

  bool get isNew => id == null;

  @override
  SizeBlock withLines(List<GridLine> lines) => copyWith(lines: lines);

  SizeBlock copyWith({
    String? label,
    String? price,
    String? id,
    List<GridLine>? lines,
  }) => SizeBlock(
    key: key,
    id: id ?? this.id,
    label: label ?? this.label,
    price: price ?? this.price,
    baseId: baseId,
    lines: lines ?? this.lines,
    seededLabel: seededLabel,
    seededPrice: seededPrice,
    serverCost: serverCost,
  );
}

int _blockSeq = 0;

/// A client key for a column added in this session (`newBlockKey`).
String newBlockKey() => 'new-${++_blockSeq}';

/// `toSizeBlocks`: the active sizes by `sort`; prices as EGP text,
/// quantities as plain numbers (trailing zeros dropped).
List<SizeBlock> toSizeBlocks(StudioAggregate s) {
  final sizes = [
    for (final z in s.sizes)
      if (z.isActive) z,
  ];
  final ordered = sizes.indexed.toList()
    ..sort((a, b) {
      final c = a.$2.sort - b.$2.sort;
      return c != 0 ? c : a.$1 - b.$1;
    });
  return [
    for (final (_, z) in ordered)
      () {
        final price = egpText(z.price);
        return SizeBlock(
          key: z.id,
          id: z.id,
          label: z.label,
          price: price,
          seededLabel: z.label,
          seededPrice: price,
          serverCost: (piastres: z.costPiastres, incomplete: z.costIncomplete),
          baseId: z.baseId,
          lines: [
            for (final r in z.recipe)
              GridLine(
                ingredientId: r.ingredientId,
                quantity: jsNumberText(jsParseFloat(r.quantity)),
                unit: r.unit,
                source: LineSource.fromWire(r.source),
              ),
          ],
        );
      }(),
  ];
}

/// `sizesSig`.
String sizesSig(List<SizeBlock> blocks) =>
    jsonEncode([for (final b in blocks) [b.label, b.price]]);

/// Adds an empty column (`addBlock`): price "0", a blank label and a blank
/// cell for every own row; an item that only had `one_size` gets that label
/// blanked so both must be named.
List<SizeBlock> addSizeBlock(List<SizeBlock> blocks) => [
  for (final b in blocks) b.label == oneSize ? b.copyWith(label: '') : b,
  SizeBlock(
    key: newBlockKey(),
    label: '',
    price: '0',
    lines: [
      for (final r in buildGridRows(blocks))
        if (r.source == LineSource.own)
          GridLine(ingredientId: r.ingredientId, quantity: '', unit: r.unit),
    ],
  ),
];

/// Swaps a column with its neighbour (`moveBlock`); out of range = unchanged.
List<SizeBlock> moveSizeBlock(List<SizeBlock> blocks, String key, int dir) {
  final idx = blocks.indexWhere((b) => b.key == key);
  final to = idx + dir;
  if (idx < 0 || to < 0 || to >= blocks.length) return blocks;
  final next = [...blocks];
  final t = next[idx];
  next[idx] = next[to];
  next[to] = t;
  return next;
}

/// A positive unit cost of an ingredient (`costOf`), else null.
double? unitCostOf(Map<String, OrgIngredient> catalog, String id) {
  final v = catalog[id]?.costPerUnit;
  return v != null && v > 0 ? v : null;
}

/// `estimateFor`: Σ unit cost × quantity over the lines with a quantity;
/// incomplete when a line has no ingredient, no unit cost or a bad quantity.
({double piastres, bool incomplete}) estimateLines(
  Map<String, OrgIngredient> catalog,
  List<GridLine> lines,
) {
  var sum = 0.0;
  var incomplete = false;
  for (final l in lines) {
    if (l.quantity.trim().isEmpty) continue;
    final qty = jsNumber(l.quantity);
    final cost = unitCostOf(catalog, l.ingredientId);
    if (l.ingredientId.isEmpty || cost == null || !qty.isFinite) {
      incomplete = true;
      continue;
    }
    sum += cost * qty;
  }
  return (piastres: sum, incomplete: incomplete);
}

/// What the grid's footer shows for one column.
sealed class ColumnCost {
  const ColumnCost();
}

/// No line at all: "—".
class NoLines extends ColumnCost {
  const NoLines();
}

/// "Cost incomplete".
class CostIncomplete extends ColumnCost {
  const CostIncomplete();
}

/// Money (prefixed "≈ " when [estimated]) and the margin when known.
class CostKnown extends ColumnCost {
  const CostKnown({
    required this.piastres,
    required this.estimated,
    this.margin,
  });

  final double piastres;
  final bool estimated;
  final double? margin;
}

/// The footer's "Cost · margin" of [b]: a browser estimate while the column
/// is new, recipe-dirty or re-priced, else the server's rollup.
ColumnCost columnCost(
  SizeBlock b,
  Map<String, OrgIngredient> catalog, {
  required bool recipeDirty,
}) {
  if (b.lines.isEmpty) return const NoLines();
  final estimated = b.isNew || recipeDirty || b.price != b.seededPrice;
  final bool incomplete;
  final double? cost;
  if (estimated) {
    final est = estimateLines(catalog, b.lines);
    incomplete = est.incomplete;
    cost = est.piastres;
  } else {
    incomplete = b.serverCost?.incomplete ?? false;
    cost = b.serverCost?.piastres?.toDouble();
  }
  if (incomplete || cost == null) return const CostIncomplete();
  final egp = jsNumber(b.price);
  final price = egp.isFinite ? egpToPiastres(egp) : 0;
  return CostKnown(
    piastres: cost,
    estimated: estimated,
    margin: price > 0 ? (price - cost) / price : null,
  );
}

/// The base picker's value: none without saved sizes, the one base every
/// saved size shares (or none), else "mixed".
sealed class BaseValue {
  const BaseValue();
}

class BaseNone extends BaseValue {
  const BaseNone();
}

class BaseMixed extends BaseValue {
  const BaseMixed();
}

class BaseOne extends BaseValue {
  const BaseOne(this.id);
  final String id;
}

BaseValue baseValueOf(List<({String id, String? baseId})> sizes) {
  if (sizes.isEmpty) return const BaseNone();
  final ids = {for (final s in sizes) s.baseId};
  if (ids.length > 1) return const BaseMixed();
  final only = ids.single;
  return only == null ? const BaseNone() : BaseOne(only);
}

// ── Modifiers ───────────────────────────────────────────────────────────────

/// One option of an attached group. The recipe and cost come from the
/// aggregate; a group attached in this session has none yet.
class AttachOption {
  const AttachOption({
    required this.id,
    required this.name,
    required this.price,
    this.recipe,
    this.cost,
    this.costIncomplete = false,
  });

  final String id;
  final String name;
  final int price;

  /// (ingredient name, quantity as the server wrote it, unit).
  final List<({String name, String quantity, String unit})>? recipe;
  final int? cost;
  final bool costIncomplete;
}

/// One attached reusable group (`AttachDraft`).
class AttachDraft {
  const AttachDraft({
    required this.groupId,
    required this.name,
    required this.selectionType,
    required this.min,
    required this.isRequired,
    required this.allOptions,
    this.legacyAddonType,
    this.max,
    this.includedOptionIds,
  });

  final String groupId;
  final String name;
  final String? legacyAddonType;
  final String selectionType;
  final int min;

  /// Null = unlimited.
  final int? max;
  final bool isRequired;

  /// Null = every option of the group is offered.
  final List<String>? includedOptionIds;
  final List<AttachOption> allOptions;

  AttachDraft copyWith({
    int? min,
    int? Function()? max,
    bool? isRequired,
    List<String>? Function()? includedOptionIds,
  }) => AttachDraft(
    groupId: groupId,
    name: name,
    legacyAddonType: legacyAddonType,
    selectionType: selectionType,
    min: min ?? this.min,
    max: max == null ? this.max : max(),
    isRequired: isRequired ?? this.isRequired,
    includedOptionIds: includedOptionIds == null
        ? this.includedOptionIds
        : includedOptionIds(),
    allOptions: allOptions,
  );

  bool offers(String optionId) =>
      includedOptionIds == null || includedOptionIds!.contains(optionId);

  /// Toggles one option in or out of the allowlist; back to "all" (null)
  /// when every option is offered again.
  AttachDraft toggle(String optionId) {
    final current =
        includedOptionIds ?? [for (final o in allOptions) o.id];
    final next = current.contains(optionId)
        ? [
            for (final id in current)
              if (id != optionId) id,
          ]
        : [...current, optionId];
    return copyWith(
      includedOptionIds: () => next.length == allOptions.length ? null : next,
    );
  }
}

AttachDraft toAttachDraft(ModifierGroupOut g) {
  final all = [
    for (final o in g.options)
      AttachOption(
        id: o.id,
        name: o.name,
        price: o.price,
        recipe: [
          for (final r in o.recipe)
            (name: r.ingredientName, quantity: r.quantity, unit: r.unit),
        ],
        cost: o.costPiastres,
        costIncomplete: o.costIncomplete,
      ),
  ];
  final included = [
    for (final o in g.options)
      if (o.included) o.id,
  ];
  return AttachDraft(
    groupId: g.groupId,
    name: g.name,
    legacyAddonType: g.legacyAddonType,
    selectionType: g.selectionType,
    min: g.min,
    max: g.max,
    isRequired: g.isRequired,
    includedOptionIds: included.length == all.length ? null : included,
    allOptions: all,
  );
}

/// A group attached from the org list (`attachGroup`): its own rules, every
/// option offered.
AttachDraft attachFromGroup(GroupOut g) => AttachDraft(
  groupId: g.id,
  name: g.name,
  legacyAddonType: g.legacyAddonType,
  selectionType: g.selectionType,
  min: g.minSelections,
  max: g.maxSelections,
  isRequired: g.isRequired,
  allOptions: [
    for (final o in g.options)
      AttachOption(id: o.id, name: o.name, price: o.price),
  ],
);

/// `toAttachDrafts`: by attachment `sort`.
List<AttachDraft> toAttachDrafts(StudioAggregate s) {
  final ordered = s.modifierGroups.indexed.toList()
    ..sort((a, b) {
      final c = a.$2.sort - b.$2.sort;
      return c != 0 ? c : a.$1 - b.$1;
    });
  return [for (final (_, g) in ordered) toAttachDraft(g)];
}

/// `modifiersSig`.
String modifiersSig(List<AttachDraft> attached) => jsonEncode([
  for (final a in attached)
    [
      a.groupId,
      a.min,
      a.max,
      a.isRequired,
      a.includedOptionIds == null
          ? null
          : ([...a.includedOptionIds!]..sort()),
    ],
]);

// ── Item-only options ───────────────────────────────────────────────────────

/// One item-only option row (`OptionRowDraft`); only the first recipe line
/// is editable.
class OptionRow {
  const OptionRow({
    this.id,
    this.name = '',
    this.price = '0',
    this.isActive = true,
    this.ingredientId = '',
    this.quantity = '',
    this.unit = 'g',
  });

  final String? id;
  final String name;

  /// EGP as typed.
  final String price;
  final bool isActive;

  /// `''` = no deduction.
  final String ingredientId;
  final String quantity;
  final String unit;

  OptionRow copyWith({
    String? name,
    String? price,
    bool? isActive,
    String? ingredientId,
    String? quantity,
    String? unit,
  }) => OptionRow(
    id: id,
    name: name ?? this.name,
    price: price ?? this.price,
    isActive: isActive ?? this.isActive,
    ingredientId: ingredientId ?? this.ingredientId,
    quantity: quantity ?? this.quantity,
    unit: unit ?? this.unit,
  );
}

List<OptionRow> toOptionRows(StudioAggregate s) => [
  for (final o in s.options)
    () {
      final line = o.recipe.firstOrNull;
      return OptionRow(
        id: o.id,
        name: o.name,
        price: egpText(o.price),
        isActive: o.isActive,
        ingredientId: line?.ingredientId ?? '',
        quantity: line == null
            ? ''
            : jsNumberText(jsParseFloat(line.quantity)),
        unit: line?.unit ?? 'g',
      );
    }(),
];

/// `optionsSig`.
String optionsSig(List<OptionRow> rows) => jsonEncode([
  for (final r in rows)
    [r.id, r.name, r.price, r.isActive, r.ingredientId, r.quantity, r.unit],
]);

// ── Steps ───────────────────────────────────────────────────────────────────

/// One step being edited: a library preset (named by the library) or a
/// written one.
class StepDraft {
  const StepDraft({
    required this.kind,
    this.presetSlug,
    this.title = '',
    this.titleAr = '',
    this.note = '',
    this.noteAr = '',
  });

  const StepDraft.custom() : this(kind: 'custom');

  const StepDraft.preset(String slug) : this(kind: 'preset', presetSlug: slug);

  /// `preset` or `custom`.
  final String kind;
  final String? presetSlug;
  final String title;
  final String titleAr;
  final String note;
  final String noteAr;

  bool get isPreset => kind == 'preset';

  StepDraft copyWith({
    String? title,
    String? titleAr,
    String? note,
    String? noteAr,
  }) => StepDraft(
    kind: kind,
    presetSlug: presetSlug,
    title: title ?? this.title,
    titleAr: titleAr ?? this.titleAr,
    note: note ?? this.note,
    noteAr: noteAr ?? this.noteAr,
  );
}

/// `toStepDrafts`: a written step whose Arabic name equals its English one
/// seeds the Arabic box empty (saving must not invent an Arabic name).
List<StepDraft> toStepDrafts(StudioAggregate s) => [
  for (final st in s.recipeSteps)
    st.kind == 'preset'
        ? StepDraft(
            kind: 'preset',
            presetSlug: st.presetSlug,
            note: st.note ?? '',
            noteAr: st.noteAr ?? '',
          )
        : StepDraft(
            kind: 'custom',
            title: st.name,
            titleAr: st.nameAr == st.name ? '' : st.nameAr,
            note: st.note ?? '',
            noteAr: st.noteAr ?? '',
          ),
];

/// `stepsSig`.
String stepsSig(List<StepDraft> steps) => jsonEncode([
  for (final s in steps)
    [
      s.kind,
      s.presetSlug,
      s.title.trim(),
      s.titleAr.trim(),
      s.note.trim(),
      s.noteAr.trim(),
    ],
]);

/// Moves the step at [from] to [to] (out of range = unchanged).
List<StepDraft> moveStep(List<StepDraft> steps, int from, int to) {
  if (to < 0 || to >= steps.length) return steps;
  final next = [...steps];
  final row = next.removeAt(from);
  next.insert(to, row);
  return next;
}

// ── Pristine signatures ─────────────────────────────────────────────────────

class Pristine {
  const Pristine({
    this.item = '',
    this.sizes = '',
    this.recipes = const {},
    this.modifiers = '',
    this.options = '',
    this.steps = '',
  });

  final String item;
  final String sizes;

  /// Per column key; a missing key is a new column.
  final Map<String, String> recipes;
  final String modifiers;
  final String options;
  final String steps;

  Pristine copyWith({
    String? item,
    String? sizes,
    Map<String, String>? recipes,
    String? modifiers,
    String? options,
    String? steps,
  }) => Pristine(
    item: item ?? this.item,
    sizes: sizes ?? this.sizes,
    recipes: recipes ?? this.recipes,
    modifiers: modifiers ?? this.modifiers,
    options: options ?? this.options,
    steps: steps ?? this.steps,
  );
}

// ── Save: validation and payloads ───────────────────────────────────────────

/// The first rule a save breaks, as its i18n key and arguments.
typedef StudioProblem = ({String key, Map<String, Object?> args});

/// JavaScript's `Number.isFinite(parseFloat(x)) && x >= 0`.
bool _validPrice(String text) {
  final p = jsParseFloat(text);
  return p.isFinite && p >= 0;
}

/// The save's validation (the first failure is toasted; nothing is written).
StudioProblem? validateStudio({
  required ItemDraft item,
  required List<SizeBlock> blocks,
  required List<StepDraft> steps,
  required List<OptionRow> rows,
}) {
  if (item.name.trim().isEmpty) {
    return (key: 'menu.studio.validate.nameRequired', args: const {});
  }
  final seen = <String>{};
  for (final b in blocks) {
    final label = b.label.trim();
    if (label.isEmpty) {
      return (key: 'menu.studio.validate.sizeLabel', args: const {});
    }
    if (!seen.add(label)) {
      return (key: 'menu.studio.validate.sizeLabelDup', args: {'label': label});
    }
    if (!_validPrice(b.price)) {
      return (key: 'menu.studio.validate.priceFor', args: {'name': label});
    }
  }
  for (final s in steps) {
    if (!s.isPreset && s.title.trim().isEmpty && s.titleAr.trim().isEmpty) {
      return (key: 'menu.studio.validate.stepName', args: const {});
    }
  }
  for (final r in rows) {
    if (r.name.trim().isEmpty) {
      return (key: 'menu.studio.validate.optionName', args: const {});
    }
    if (!_validPrice(r.price)) {
      return (
        key: 'menu.studio.validate.priceFor',
        args: {'name': r.name.trim()},
      );
    }
  }
  return null;
}

/// Step 1: the item's fields (`image_url: null` when the image was removed).
UpdateMenuItemRequest itemPayload(ItemDraft v, {required bool imageRemoved}) =>
    UpdateMenuItemRequest(
      name: v.name,
      nameTranslations: v.nameAr.isEmpty ? {} : {'ar': v.nameAr},
      description: v.description.isEmpty ? null : v.description,
      descriptionTranslations: v.descriptionAr.isEmpty
          ? {}
          : {'ar': v.descriptionAr},
      categoryId: v.categoryId.isEmpty ? null : v.categoryId,
      isActive: v.isActive,
      explicitNulls: {
        if (v.description.isEmpty) 'description',
        if (v.categoryId.isEmpty) 'category_id',
        if (imageRemoved) 'image_url',
      },
    );

/// Step 2: the size set, in column order.
PutSizesRequest sizesPayload(List<SizeBlock> blocks) => PutSizesRequest(
  sizes: [
    for (final (i, b) in blocks.indexed)
      SizeInput(
        label: b.label.trim(),
        price: egpToPiastres(jsParseFloat(b.price)),
        sort: i,
        isActive: true,
      ),
  ],
);

/// Step 3: one size's own lines.
PutRecipeRequest recipePayload(List<GridLine> lines) => PutRecipeRequest(
  lines: [
    for (final l in ownPayload(lines))
      RecipeLineInput(
        ingredientId: l.ingredientId,
        quantity: l.quantity,
        unit: l.unit,
      ),
  ],
);

String? _trimmedOrNull(String s) {
  final t = s.trim();
  return t.isEmpty ? null : t;
}

/// Step 4: the steps; a preset sends only its slug and notes.
PutRecipeStepsRequest stepsPayload(List<StepDraft> steps) =>
    PutRecipeStepsRequest(
      steps: [
        for (final s in steps)
          s.isPreset
              ? RecipeStepInput(
                  kind: 'preset',
                  presetSlug: s.presetSlug,
                  note: _trimmedOrNull(s.note),
                  noteAr: _trimmedOrNull(s.noteAr),
                  explicitNulls: const {'preset_slug', 'note', 'note_ar'},
                )
              : RecipeStepInput(
                  kind: 'custom',
                  title: _trimmedOrNull(s.title),
                  titleAr: _trimmedOrNull(s.titleAr),
                  note: _trimmedOrNull(s.note),
                  noteAr: _trimmedOrNull(s.noteAr),
                  explicitNulls: const {'title', 'title_ar', 'note', 'note_ar'},
                ),
      ],
    );

/// Step 5: the attachment set in order (`[]` detaches every group).
PutModifierGroupsRequest modifiersPayload(List<AttachDraft> attached) =>
    PutModifierGroupsRequest(
      groups: [
        for (final (i, a) in attached.indexed)
          GroupAttachInput(
            groupId: a.groupId,
            sort: i,
            minOverride: a.min,
            maxOverride: a.max,
            isRequiredOverride: a.isRequired,
            includedOptionIds: a.includedOptionIds,
            explicitNulls: const {'max_override', 'included_option_ids'},
          ),
      ],
    );

/// Step 6: the item-only options. With an ingredient and a numeric quantity
/// the deduction is sent; with no ingredient an empty recipe clears it (the
/// web sends `null`, which the server reads as "keep the old lines", so a
/// cleared deduction came back: see the divergence log); an ingredient with
/// no usable quantity sends `null` (leave the lines as they are), as the web.
PutItemOptionsRequest optionsPayload(List<OptionRow> rows) =>
    PutItemOptionsRequest(
      options: [
        for (final r in rows)
          () {
            final qty = jsParseFloat(r.quantity);
            final List<OptionRecipeLineInput>? recipe;
            if (r.ingredientId.isEmpty) {
              recipe = const [];
            } else if (qty.isFinite) {
              recipe = [
                OptionRecipeLineInput(
                  ingredientId: r.ingredientId,
                  quantity: qty,
                  unit: r.unit,
                ),
              ];
            } else {
              recipe = null;
            }
            return ItemOptionInput(
              id: r.id,
              name: r.name.trim(),
              price: egpToPiastres(jsParseFloat(r.price)),
              isActive: r.isActive,
              recipe: recipe,
              explicitNulls: const {'recipe'},
            );
          }(),
      ],
    );

/// `?tab=` deep links → the section to scroll to; anything else stays at
/// the top (the pricing link is availability's home now).
const Map<String, String> tabToSection = {
  'basics': 'item',
  'sizes': 'sizes',
  'recipe': 'sizes',
  'steps': 'steps',
  'modifiers': 'modifiers',
  'options': 'options',
};
