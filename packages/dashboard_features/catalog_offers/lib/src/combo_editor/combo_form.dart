/// The combo editor's form (the web's `features/combos/form-schema.ts`): what
/// the owner types (EGP text, numbers as text, '' for none), the rules that
/// refuse a Save on the field, and the mappings to and from the wire's
/// `ComboWrite` (piastres, translations, null for none) — plus the tolerant
/// mapping the live price check asks with.
///
/// Margin and saving are not rules here: they are warnings and never block
/// a Save.
library;

import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart'
    show Combo, ComboChoiceWrite, ComboSlotWrite, ComboWrite, SizeSurcharge;
import 'package:flutter/foundation.dart';

import '../shared/offers_format.dart';
import '../shared/sale_window_form.dart';

/// What a choice points at: one item, or every item of a category.
enum ChoiceTarget { item, category }

/// One "other size costs" box: the size and the EGP typed for it.
typedef SizeExtraDraft = ({String label, String surcharge});

/// One choice of a slot. Empty strings mean "none": [includedSizeLabel] ''
/// = the item's cheapest active size; [surcharge] '' = 0.
@immutable
class ChoiceDraft {
  const ChoiceDraft({
    required this.key,
    this.id,
    this.target = ChoiceTarget.item,
    this.menuItemId = '',
    this.categoryId = '',
    this.surcharge = '',
    this.includedSizeLabel = '',
    this.sizeSurcharges = const [],
  });

  /// `emptyChoice()` (an item choice), or a category one.
  factory ChoiceDraft.empty([ChoiceTarget target = ChoiceTarget.item]) =>
      ChoiceDraft(key: newOffersKey('c'), target: target);

  /// A client key for the list (never sent).
  final String key;

  /// The saved choice's id (kept on Save, so the server diffs in place).
  final String? id;
  final ChoiceTarget target;
  final String menuItemId;
  final String categoryId;
  final String surcharge;
  final String includedSizeLabel;
  final List<SizeExtraDraft> sizeSurcharges;

  bool get isItem => target == ChoiceTarget.item;

  /// The item or category it names ('' = not chosen).
  String get targetId => isItem ? menuItemId : categoryId;

  ChoiceDraft copyWith({
    ChoiceTarget? target,
    String? menuItemId,
    String? categoryId,
    String? surcharge,
    String? includedSizeLabel,
    List<SizeExtraDraft>? sizeSurcharges,
  }) => ChoiceDraft(
    key: key,
    id: id,
    target: target ?? this.target,
    menuItemId: menuItemId ?? this.menuItemId,
    categoryId: categoryId ?? this.categoryId,
    surcharge: surcharge ?? this.surcharge,
    includedSizeLabel: includedSizeLabel ?? this.includedSizeLabel,
    sizeSurcharges: sizeSurcharges ?? this.sizeSurcharges,
  );

  /// The extra typed for [label] ('' = the size's usual difference).
  String sizeSurcharge(String label) {
    for (final x in sizeSurcharges) {
      if (x.label == label) return x.surcharge;
    }
    return '';
  }

  /// Types [v] for [label]; a blank box removes the row.
  ChoiceDraft withSizeSurcharge(String label, String v) => copyWith(
    sizeSurcharges: [
      for (final x in sizeSurcharges)
        if (x.label != label) x,
      if (v.trim().isNotEmpty) (label: label, surcharge: v),
    ],
  );

  /// `choiceToWire`: a blank box is no row (the size's usual difference).
  ComboChoiceWrite toWire(int sort) => ComboChoiceWrite(
    id: id,
    menuItemId: isItem ? menuItemId : null,
    categoryId: isItem ? null : categoryId,
    surcharge: _piastres(surcharge) ?? 0,
    includedSizeLabel: _orNull(includedSizeLabel),
    sizeSurcharges: [
      for (final x in sizeSurcharges)
        if (_piastres(x.surcharge) case final p?)
          SizeSurcharge(sizeLabel: x.label, surcharge: p),
    ],
    sort: sort,
    explicitNulls: const {'menu_item_id', 'category_id', 'included_size_label'},
  );

  Map<String, Object?> _values() => {
    'id': id,
    'target': target.name,
    'menu_item_id': menuItemId,
    'category_id': categoryId,
    'surcharge': surcharge,
    'included_size_label': includedSizeLabel,
    'size_surcharges': [
      for (final x in sizeSurcharges) [x.label, x.surcharge],
    ],
  };
}

/// One slot: "pick [min] to [max] of these". [min]/[max] stay text as typed
/// (a blank box counts as 0, as the web's coerced number does).
@immutable
class SlotDraft {
  const SlotDraft({
    required this.key,
    this.id,
    this.name = '',
    this.nameAr = '',
    this.min = '1',
    this.max = '1',
    this.defaultItemId = '',
    this.defaultSizeLabel = '',
    this.choices = const [],
  });

  /// `emptySlot()`: at least 1, at most 1, one empty item choice.
  factory SlotDraft.empty() =>
      SlotDraft(key: newOffersKey('s'), choices: [ChoiceDraft.empty()]);

  final String key;
  final String? id;
  final String name;
  final String nameAr;
  final String min;
  final String max;
  final String defaultItemId;
  final String defaultSizeLabel;
  final List<ChoiceDraft> choices;

  SlotDraft copyWith({
    String? name,
    String? nameAr,
    String? min,
    String? max,
    String? defaultItemId,
    String? defaultSizeLabel,
    List<ChoiceDraft>? choices,
  }) => SlotDraft(
    key: key,
    id: id,
    name: name ?? this.name,
    nameAr: nameAr ?? this.nameAr,
    min: min ?? this.min,
    max: max ?? this.max,
    defaultItemId: defaultItemId ?? this.defaultItemId,
    defaultSizeLabel: defaultSizeLabel ?? this.defaultSizeLabel,
    choices: choices ?? this.choices,
  );

  /// `slotToWire`.
  ComboSlotWrite toWire(int sort, {String? name, List<ChoiceDraft>? only}) {
    final list = only ?? choices;
    return ComboSlotWrite(
      id: id,
      name: (name ?? this.name).trim(),
      nameTranslations: _trOf(nameAr),
      sort: sort,
      min: jsNumber(min).toInt(),
      max: jsNumber(max).toInt(),
      defaultItemId: _orNull(defaultItemId),
      defaultSizeLabel: defaultItemId.isEmpty
          ? null
          : _orNull(defaultSizeLabel),
      choices: [for (final (i, c) in list.indexed) c.toWire(i)],
      explicitNulls: const {'default_item_id', 'default_size_label'},
    );
  }

  Map<String, Object?> _values() => {
    'id': id,
    'name': name,
    'name_ar': nameAr,
    'min': min,
    'max': max,
    'default_item_id': defaultItemId,
    'default_size_label': defaultSizeLabel,
    'choices': [for (final c in choices) c._values()],
  };
}

/// Everything the editor edits.
@immutable
class ComboDraft {
  const ComboDraft({
    this.name = '',
    this.nameAr = '',
    this.description = '',
    this.descriptionAr = '',
    this.categoryId = '',
    this.isActive = true,
    this.price = '',
    this.slots = const [],
    this.windows = const [],
  });

  /// `EMPTY_COMBO`: blank name and price, on, one slot, no windows.
  factory ComboDraft.empty() => ComboDraft(slots: [SlotDraft.empty()]);

  /// `fromWire`: slots and choices by their `sort`, ids kept, a 0 surcharge
  /// left blank.
  factory ComboDraft.fromWire(Combo c) {
    final slots = [...c.slots]..sort((a, b) => a.sort.compareTo(b.sort));
    return ComboDraft(
      name: c.name,
      nameAr: arabicOf(c.nameTranslations) ?? '',
      description: c.description ?? '',
      descriptionAr: arabicOf(c.descriptionTranslations) ?? '',
      categoryId: c.categoryId ?? '',
      isActive: c.isActive,
      price: moneyOut(c.price),
      slots: [
        for (final s in slots)
          SlotDraft(
            key: s.id,
            id: s.id,
            name: s.name,
            nameAr: arabicOf(s.nameTranslations) ?? '',
            min: '${s.min}',
            max: '${s.max}',
            defaultItemId: s.defaultItemId ?? '',
            defaultSizeLabel: s.defaultSizeLabel ?? '',
            choices: [
              for (final ch in [
                ...s.choices,
              ]..sort((a, b) => a.sort.compareTo(b.sort)))
                ChoiceDraft(
                  key: ch.id,
                  id: ch.id,
                  target: (ch.categoryId ?? '').isNotEmpty
                      ? ChoiceTarget.category
                      : ChoiceTarget.item,
                  menuItemId: ch.menuItemId ?? '',
                  categoryId: ch.categoryId ?? '',
                  surcharge: ch.surcharge == 0 ? '' : moneyOut(ch.surcharge),
                  includedSizeLabel: ch.includedSizeLabel ?? '',
                  sizeSurcharges: [
                    for (final x in ch.sizeSurcharges)
                      (label: x.sizeLabel, surcharge: moneyOut(x.surcharge)),
                  ],
                ),
            ],
          ),
      ],
      windows: [for (final w in c.windows) WindowDraft.fromWire(w)],
    );
  }

  final String name;
  final String nameAr;
  final String description;
  final String descriptionAr;
  final String categoryId;
  final bool isActive;

  /// EGP as typed.
  final String price;
  final List<SlotDraft> slots;
  final List<WindowDraft> windows;

  ComboDraft copyWith({
    String? name,
    String? nameAr,
    String? description,
    String? descriptionAr,
    String? categoryId,
    bool? isActive,
    String? price,
    List<SlotDraft>? slots,
    List<WindowDraft>? windows,
  }) => ComboDraft(
    name: name ?? this.name,
    nameAr: nameAr ?? this.nameAr,
    description: description ?? this.description,
    descriptionAr: descriptionAr ?? this.descriptionAr,
    categoryId: categoryId ?? this.categoryId,
    isActive: isActive ?? this.isActive,
    price: price ?? this.price,
    slots: slots ?? this.slots,
    windows: windows ?? this.windows,
  );

  /// `toWire`: the body Save sends. Call only on a form that passed
  /// [validateCombo].
  ComboWrite toWire() => ComboWrite(
    name: name.trim(),
    nameTranslations: _trOf(nameAr),
    categoryId: _orNull(categoryId),
    description: _orNull(description),
    descriptionTranslations: _trOf(descriptionAr),
    isActive: isActive,
    price: _piastres(price) ?? 0,
    windows: [for (final w in windows) w.toWire()],
    slots: [for (final (i, s) in slots.indexed) s.toWire(i)],
    explicitNulls: const {'category_id', 'description'},
  );

  /// `toEconomicsBody`, tolerant of a half-typed form: choices with nothing
  /// chosen are dropped, so is a slot with no choice left or a broken
  /// count; null until there is a price and one slot left. The JSON map the
  /// price check asks with (before its `branch_id`).
  Map<String, Object?>? economicsBody() {
    final p = moneyIn(price);
    if (p == null || !p.isFinite || p < 0) return null;
    final out = <ComboSlotWrite>[];
    for (final (i, s) in slots.indexed) {
      final chosen = [
        for (final c in s.choices)
          if (c.targetId.isNotEmpty) c,
      ];
      final lo = jsNumber(s.min);
      final hi = jsNumber(s.max);
      if (chosen.isEmpty ||
          !_isInteger(lo) ||
          !_isInteger(hi) ||
          hi < 1 ||
          lo > hi) {
        continue;
      }
      out.add(s.toWire(i, name: s.name.isEmpty ? '—' : s.name, only: chosen));
    }
    if (out.isEmpty) return null;
    final trimmed = name.trim();
    return {
      'name': trimmed.isEmpty ? '—' : trimmed,
      'name_translations': const <String, Object?>{},
      'category_id': _orNull(categoryId),
      'description': null,
      'is_active': isActive,
      'price': p.toInt(),
      'windows': const <Object?>[],
      'slots': [for (final s in out) s.toJson()],
    };
  }

  /// Every value, for "unsaved changes" (client keys left out).
  String fingerprint() => jsonEncode({
    'name': name,
    'name_ar': nameAr,
    'description': description,
    'description_ar': descriptionAr,
    'category_id': categoryId,
    'is_active': isActive,
    'price': price,
    'slots': [for (final s in slots) s._values()],
    'windows': [
      for (final w in windows)
        [w.branchId, w.weekdays, w.startsAt, w.endsAt, w.validFrom, w.validTo],
    ],
  });
}

/// `isFixedShape` on the form: every slot picks exactly its one item choice.
bool isFixedDraft(List<SlotDraft> slots) =>
    slots.isNotEmpty &&
    slots.every(
      (s) =>
          jsNumber(s.min) == jsNumber(s.max) &&
          s.choices.length == 1 &&
          s.choices.single.isItem &&
          s.choices.single.menuItemId.isNotEmpty,
    );

// ── Rules (`comboSchema`) ───────────────────────────────────────────────

/// The i18n keys of the combo rules (`E`).
abstract final class ComboErrorKeys {
  static const String required = 'combos.errors.required';
  static const String money = 'combos.errors.money';
  static const String slotsRequired = 'combos.errors.slotsRequired';
  static const String minOverMax = 'combos.errors.minOverMax';
  static const String maxZero = 'combos.errors.maxZero';
  static const String pickRange = 'combos.errors.pickRange';
  static const String noChoices = 'combos.errors.noChoices';
  static const String choiceTarget = 'combos.errors.choiceTarget';
  static const String choiceDuplicate = 'combos.errors.choiceDuplicate';
  static const String defaultNotChoice = 'combos.errors.defaultNotChoice';
}

/// A choice's refusals.
@immutable
class ChoiceErrors {
  const ChoiceErrors({this.target, this.surcharge, this.badSizes = const {}});

  /// "Choose an item or a category." / "This choice is already in the slot."
  final String? target;
  final String? surcharge;

  /// The size labels whose extra is not an amount of 0 or more (marked
  /// invalid, no words).
  final Set<String> badSizes;

  bool get isEmpty => target == null && surcharge == null && badSizes.isEmpty;
}

/// A slot's refusals.
@immutable
class SlotErrors {
  const SlotErrors({
    this.name,
    this.min,
    this.max,
    this.choices,
    this.defaultItem,
    this.choiceErrors = const [],
  });

  final String? name;
  final String? min;
  final String? max;

  /// The list's own error ("Add at least one choice to this slot.").
  final String? choices;
  final String? defaultItem;

  /// One per choice.
  final List<ChoiceErrors> choiceErrors;

  bool get isEmpty =>
      name == null &&
      min == null &&
      max == null &&
      choices == null &&
      defaultItem == null &&
      choiceErrors.every((c) => c.isEmpty);
}

/// The form's refusals, as i18n keys, by the field they show under.
@immutable
class ComboErrors {
  const ComboErrors({
    this.name,
    this.price,
    this.slots,
    this.slotErrors = const [],
    this.windows = const [],
  });

  final String? name;
  final String? price;

  /// "Add at least one slot."
  final String? slots;
  final List<SlotErrors> slotErrors;
  final List<WindowErrors?> windows;

  bool get isEmpty =>
      name == null &&
      price == null &&
      slots == null &&
      slotErrors.every((s) => s.isEmpty) &&
      windows.every((w) => w == null || w.isEmpty);

  SlotErrors slot(int i) =>
      i < slotErrors.length ? slotErrors[i] : const SlotErrors();
}

/// The web's `comboSchema` with its refinements.
ComboErrors validateCombo(ComboDraft v) {
  final price = moneyIn(v.price);
  return ComboErrors(
    name: v.name.trim().isEmpty ? ComboErrorKeys.required : null,
    price: price == null || !price.isFinite || price < 0
        ? ComboErrorKeys.money
        : null,
    slots: v.slots.isEmpty ? ComboErrorKeys.slotsRequired : null,
    slotErrors: [for (final s in v.slots) _validateSlot(s)],
    windows: [
      for (final w in v.windows)
        switch (validateWindow(w)) {
          final e when e.isEmpty => null,
          final e => e,
        },
    ],
  );
}

SlotErrors _validateSlot(SlotDraft s) {
  final lo = jsNumber(s.min);
  final hi = jsNumber(s.max);
  bool inRange(double n) => _isInteger(n) && n >= 0 && n <= 10;
  // The field's own rule first, then the pair's (as the web lists them).
  var min = inRange(lo) ? null : ComboErrorKeys.pickRange;
  var max = inRange(hi) ? null : ComboErrorKeys.pickRange;
  if (hi == 0) {
    max ??= ComboErrorKeys.maxZero;
  } else if (lo > hi) {
    min ??= ComboErrorKeys.minOverMax;
  }

  final seen = <String>{};
  final choiceErrors = [
    for (final c in s.choices)
      ChoiceErrors(
        target: c.targetId.isEmpty
            ? ComboErrorKeys.choiceTarget
            : (seen.add('${c.target.name}:${c.targetId}')
                  ? null
                  : ComboErrorKeys.choiceDuplicate),
        surcharge: moneyOk(c.surcharge) ? null : ComboErrorKeys.money,
        badSizes: {
          for (final x in c.sizeSurcharges)
            if (!moneyOk(x.surcharge)) x.label,
        },
      ),
  ];

  // A category choice admits items the form cannot list; the server checks
  // those.
  String? defaultItem;
  if (s.defaultItemId.isNotEmpty) {
    final itemChoice = s.choices.any(
      (c) => c.isItem && c.menuItemId == s.defaultItemId,
    );
    final anyCategory = s.choices.any(
      (c) => !c.isItem && c.categoryId.isNotEmpty,
    );
    if (!itemChoice && !anyCategory) {
      defaultItem = ComboErrorKeys.defaultNotChoice;
    }
  }

  return SlotErrors(
    name: s.name.trim().isEmpty ? ComboErrorKeys.required : null,
    min: min,
    max: max,
    choices: s.choices.isEmpty ? ComboErrorKeys.noChoices : null,
    defaultItem: defaultItem,
    choiceErrors: choiceErrors,
  );
}

bool _isInteger(double n) => n.isFinite && n == n.truncateToDouble();

/// Piastres for a typed amount: blank or junk → null.
int? _piastres(String text) {
  final p = moneyIn(text);
  return p == null || !p.isFinite ? null : p.toInt();
}

Map<String, Object?> _trOf(String ar) =>
    ar.trim().isEmpty ? const {} : {'ar': ar.trim()};

String? _orNull(String s) => s.trim().isEmpty ? null : s.trim();
