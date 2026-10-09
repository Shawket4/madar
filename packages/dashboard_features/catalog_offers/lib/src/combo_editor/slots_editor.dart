/// The combo's slots (the web's `slots-editor.tsx`): each slot is "pick min
/// to max of these", its choices are items or whole categories, and each
/// choice says which size the combo price covers, what it costs extra, and
/// what a bigger size costs. A bigger size left blank costs its usual price
/// difference; the box's placeholder shows that difference.
///
/// Controlled: [SlotsEditor.value] in, [SlotsEditor.onChanged] out, the
/// errors from `validateCombo` passed back in by the page.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/menu_options.dart';
import '../shared/offers_format.dart';
import 'combo_form.dart';
import 'editor_parts.dart';

class SlotsEditor extends ConsumerWidget {
  const SlotsEditor({
    required this.value,
    required this.onChanged,
    required this.menu,
    required this.errors,
    required this.enabled,
    required this.onSubmit,
    super.key,
  });

  final List<SlotDraft> value;
  final ValueChanged<List<SlotDraft>> onChanged;
  final MenuOptions menu;
  final ComboErrors errors;
  final bool enabled;

  /// Enter in a text field saves.
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final itemOptions = [
      for (final it in menu.items)
        DashOption<String>(
          value: it.id,
          label: it.name,
          hint: f.fmtMoney(it.cheapest?.price),
          keywords: menu.categoryName(it.categoryId) ?? '',
        ),
    ];
    final categoryOptions = [
      for (final c in menu.categories)
        DashOption<String>(value: c.id, label: c.name),
    ];

    List<SlotDraft> moved(int from, int to) {
      final list = [...value];
      list.insert(to, list.removeAt(from));
      return list;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.lg,
      children: [
        for (var i = 0; i < value.length; i++)
          _SlotCard(
            key: ValueKey(value[i].key),
            index: i,
            count: value.length,
            slot: value[i],
            errors: errors.slot(i),
            menu: menu,
            itemOptions: itemOptions,
            categoryOptions: categoryOptions,
            enabled: enabled,
            onSubmit: onSubmit,
            onChanged: (s) => onChanged([
              for (var j = 0; j < value.length; j++) j == i ? s : value[j],
            ]),
            onMove: (to) => onChanged(moved(i, to)),
            onRemove: () => onChanged([
              for (var j = 0; j < value.length; j++)
                if (j != i) value[j],
            ]),
          ),
        if (errors.slots != null) ErrorLine(t(errors.slots!)),
        if (enabled)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: DashButton(
              label: t('combos.slots.add'),
              icon: 'plus',
              variant: DashButtonVariant.outline,
              onPressed: () => onChanged([...value, SlotDraft.empty()]),
            ),
          ),
      ],
    );
  }
}

class _SlotCard extends ConsumerWidget {
  const _SlotCard({
    required this.index,
    required this.count,
    required this.slot,
    required this.errors,
    required this.menu,
    required this.itemOptions,
    required this.categoryOptions,
    required this.enabled,
    required this.onSubmit,
    required this.onChanged,
    required this.onMove,
    required this.onRemove,
    super.key,
  });

  final int index;
  final int count;
  final SlotDraft slot;
  final SlotErrors errors;
  final MenuOptions menu;
  final List<DashOption<String>> itemOptions;
  final List<DashOption<String>> categoryOptions;
  final bool enabled;
  final VoidCallback onSubmit;
  final ValueChanged<SlotDraft> onChanged;
  final ValueChanged<int> onMove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final s = slot;
    final e = errors;
    final title = s.name.trim().isNotEmpty
        ? s.name.trim()
        : t('combos.slots.slotN', args: {'n': index + 1});
    final lo = jsNumber(s.min);
    final pick = lo == jsNumber(s.max)
        ? t('combos.slots.pickExactly', count: lo.isFinite ? _whole(lo) : 0)
        // A blank box counts as 0 (the web leaves the figure out).
        : t(
            'combos.slots.pickRange',
            args: {
              'min': s.min.trim().isEmpty ? '0' : s.min,
              'max': s.max.trim().isEmpty ? '0' : s.max,
            },
          );

    // The slot's default can be any item its choices admit, in order.
    final defaults = <ItemOption>[];
    final seen = <String>{};
    for (final ch in s.choices) {
      final list = ch.isItem
          ? [?menu.item(ch.menuItemId)]
          : (ch.categoryId.isEmpty
                ? const <ItemOption>[]
                : menu.itemsOfCategory(ch.categoryId));
      for (final it in list) {
        if (seen.add(it.id)) defaults.add(it);
      }
    }
    final defaultItem = menu.item(s.defaultItemId);

    Widget text({
      required String label,
      required String value,
      required ValueChanged<String> onChanged,
      String? placeholder,
      String? error,
      bool rtl = false,
      bool number = false,
    }) => LabelledField(
      label: label,
      error: error == null ? null : t(error),
      child: DashTextInput(
        value: value,
        onChanged: onChanged,
        placeholder: placeholder,
        semanticLabel: label,
        invalid: error != null,
        enabled: enabled,
        textDirection: rtl
            ? TextDirection.rtl
            : (number ? TextDirection.ltr : null),
        keyboardType: number ? TextInputType.number : null,
        inputFormatters: number ? const [NumberText()] : null,
        mono: number,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => onSubmit(),
      ),
    );

    final name = text(
      label: t('combos.slots.name'),
      value: s.name,
      placeholder: t('combos.slots.namePlaceholder'),
      error: e.name,
      onChanged: (v) => onChanged(s.copyWith(name: v)),
    );
    final nameAr = text(
      label: t('combos.slots.nameAr'),
      value: s.nameAr,
      placeholder: 'مشروب',
      rtl: true,
      onChanged: (v) => onChanged(s.copyWith(nameAr: v)),
    );
    Widget countBox(String label, String value, String? error, bool isMin) =>
        LabelledField(
          label: label,
          child: InvalidOr(
            invalid: error != null,
            child: DashTextInput(
              value: value,
              onChanged: (v) =>
                  onChanged(isMin ? s.copyWith(min: v) : s.copyWith(max: v)),
              semanticLabel: label,
              invalid: error != null,
              enabled: enabled,
              textDirection: TextDirection.ltr,
              keyboardType: TextInputType.number,
              inputFormatters: const [NumberText()],
              mono: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onSubmit(),
            ),
          ),
        );
    final min = countBox(t('combos.slots.min'), s.min, e.min, true);
    final max = countBox(t('combos.slots.max'), s.max, e.max, false);
    final countError = e.min ?? e.max;

    final fields = LayoutBuilder(
      builder: (context, box) => box.maxWidth >= fieldGridWidth
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.md,
              children: [
                Expanded(child: name),
                Expanded(child: nameAr),
                SizedBox(width: _countWidth, child: min),
                SizedBox(width: _countWidth, child: max),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              spacing: Space.md,
              children: [name, nameAr, min, max],
            ),
    );

    final choices = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.sm,
      children: [
        Text(
          t('combos.slots.choices'),
          style: DashType.smallMedium.copyWith(color: c.textSecondary),
        ),
        for (var j = 0; j < s.choices.length; j++)
          _ChoiceRow(
            key: ValueKey(s.choices[j].key),
            choice: s.choices[j],
            errors: j < e.choiceErrors.length
                ? e.choiceErrors[j]
                : const ChoiceErrors(),
            menu: menu,
            itemOptions: itemOptions,
            categoryOptions: categoryOptions,
            enabled: enabled,
            onSubmit: onSubmit,
            onChanged: (ch) => onChanged(
              s.copyWith(
                choices: [
                  for (var k = 0; k < s.choices.length; k++)
                    k == j ? ch : s.choices[k],
                ],
              ),
            ),
            onRemove: () => onChanged(
              s.copyWith(
                choices: [
                  for (var k = 0; k < s.choices.length; k++)
                    if (k != j) s.choices[k],
                ],
              ),
            ),
          ),
        if (e.choices != null) ErrorLine(t(e.choices!)),
        if (enabled)
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              DashButton(
                label: t('combos.slots.addItem'),
                icon: 'tag',
                variant: DashButtonVariant.outline,
                size: DashButtonSize.compact,
                onPressed: () => onChanged(
                  s.copyWith(choices: [...s.choices, ChoiceDraft.empty()]),
                ),
              ),
              DashButton(
                label: t('combos.slots.addCategory'),
                icon: 'folder-tree',
                variant: DashButtonVariant.outline,
                size: DashButtonSize.compact,
                onPressed: () => onChanged(
                  s.copyWith(
                    choices: [
                      ...s.choices,
                      ChoiceDraft.empty(ChoiceTarget.category),
                    ],
                  ),
                ),
              ),
            ],
          ),
      ],
    );

    final defaultPick = LabelledField(
      label: t('combos.slots.default'),
      error: e.defaultItem == null ? null : t(e.defaultItem!),
      child: DashSelect<String>(
        options: [
          DashOption(value: '', label: t('combos.slots.defaultFirst')),
          for (final it in defaults) DashOption(value: it.id, label: it.name),
        ],
        value: s.defaultItemId,
        onChanged: (v) =>
            onChanged(s.copyWith(defaultItemId: v, defaultSizeLabel: '')),
        semanticLabel: t('combos.slots.default'),
        invalid: e.defaultItem != null,
        enabled: enabled,
      ),
    );
    final defaultBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.xs + DashMetrics.hair,
      children: [defaultPick, HintLine(t('combos.slots.defaultHint'))],
    );
    final defaultSize = defaultItem != null && defaultItem.sizes.length > 1
        ? LabelledField(
            label: t('combos.slots.defaultSize'),
            child: DashSelect<String>(
              options: [
                DashOption(value: '', label: t('combos.slots.includedSize')),
                for (final z in defaultItem.sizes)
                  DashOption(value: z.label, label: sizeLabelText(t, z.label)),
              ],
              value: s.defaultSizeLabel,
              onChanged: (v) => onChanged(s.copyWith(defaultSizeLabel: v)),
              semanticLabel: t('combos.slots.defaultSize'),
              enabled: enabled,
            ),
          )
        : null;

    final actions = enabled
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DashIconButton(
                icon: 'arrow-up',
                semanticLabel: t('combos.slots.moveUp'),
                onPressed: index == 0 ? null : () => onMove(index - 1),
              ),
              DashIconButton(
                icon: 'arrow-down',
                semanticLabel: t('combos.slots.moveDown'),
                onPressed: index == count - 1 ? null : () => onMove(index + 1),
              ),
              DashIconButton(
                icon: 'trash-2',
                semanticLabel: t('combos.slots.remove'),
                color: c.danger,
                onPressed: onRemove,
              ),
            ],
          )
        : null;

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: title,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(Radii.sheet),
          border: Border.all(color: c.hairline),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: Space.lg,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Space.md,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Semantics(
                          header: true,
                          child: MadarClippedText(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DashType.bodyStrong.copyWith(
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          pick,
                          style: DashType.small.copyWith(
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ?actions,
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                spacing: Space.xs + DashMetrics.hair,
                children: [
                  fields,
                  if (countError != null) ErrorLine(t(countError)),
                  if (lo == 0) HintLine(t('combos.slots.optionalHint')),
                ],
              ),
              choices,
              Divider(height: 1, thickness: 1, color: c.hairline),
              FieldGrid(children: [defaultBlock, ?defaultSize]),
            ],
          ),
        ),
      ),
    );
  }

  /// "At least" / "At most" (`5rem`).
  static const double _countWidth = 80;
}

class _ChoiceRow extends ConsumerWidget {
  const _ChoiceRow({
    required this.choice,
    required this.errors,
    required this.menu,
    required this.itemOptions,
    required this.categoryOptions,
    required this.enabled,
    required this.onSubmit,
    required this.onChanged,
    required this.onRemove,
    super.key,
  });

  final ChoiceDraft choice;
  final ChoiceErrors errors;
  final MenuOptions menu;
  final List<DashOption<String>> itemOptions;
  final List<DashOption<String>> categoryOptions;
  final bool enabled;
  final VoidCallback onSubmit;
  final ValueChanged<ChoiceDraft> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final ch = choice;
    final e = errors;
    final item = ch.isItem ? menu.item(ch.menuItemId) : null;
    final labels = ch.isItem
        ? [for (final z in item?.sizes ?? const <SizeOption>[]) z.label]
        : (ch.categoryId.isEmpty
              ? const <String>[]
              : menu.categorySizeLabels(ch.categoryId));
    final included = ch.includedSizeLabel.isNotEmpty
        ? ch.includedSizeLabel
        : (ch.isItem ? (item?.cheapest?.label ?? '') : '');
    final others = [
      for (final l in labels)
        if (l != included) l,
    ];
    int? priceOf(String label) {
      for (final z in item?.sizes ?? const <SizeOption>[]) {
        if (z.label == label) return z.price;
      }
      return null;
    }

    final basePrice = priceOf(included);
    // Pressing the segment already chosen still clears the choice (the
    // web's control always reports a change).
    final segments = DashSegmentedControl<ChoiceTarget>(
      options: [
        DashOption(value: ChoiceTarget.item, label: t('combos.choice.item')),
        DashOption(
          value: ChoiceTarget.category,
          label: t('combos.choice.category'),
        ),
      ],
      value: ch.target,
      enabled: enabled,
      onChanged: (v) => onChanged(
        ChoiceDraft(key: ch.key, id: ch.id, target: v, surcharge: ch.surcharge),
      ),
    );

    final picker = ch.isItem
        ? DashSelect<String>(
            options: itemOptions,
            value: ch.menuItemId.isEmpty ? null : ch.menuItemId,
            onChanged: (v) => onChanged(
              ch.copyWith(
                menuItemId: v,
                includedSizeLabel: '',
                sizeSurcharges: const [],
              ),
            ),
            placeholder: t('combos.choice.pickItem'),
            semanticLabel: t('combos.choice.pickItem'),
            searchable: true,
            searchPlaceholder: t('common.search'),
            emptyText: t('common.noResults'),
            invalid: e.target != null,
            enabled: enabled,
          )
        : DashSelect<String>(
            options: categoryOptions,
            value: ch.categoryId.isEmpty ? null : ch.categoryId,
            onChanged: (v) => onChanged(
              ch.copyWith(
                categoryId: v,
                includedSizeLabel: '',
                sizeSurcharges: const [],
              ),
            ),
            placeholder: t('combos.choice.pickCategory'),
            semanticLabel: t('combos.choice.pickCategory'),
            invalid: e.target != null,
            enabled: enabled,
          );

    final pickerBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.xs,
      children: [
        InvalidOr(invalid: e.target != null, child: picker),
        if (e.target != null) ErrorLine(t(e.target!)),
        if (!ch.isItem && ch.categoryId.isNotEmpty)
          HintLine(
            t(
              'combos.choice.categoryCount',
              count: menu.itemsOfCategory(ch.categoryId).length,
            ),
          ),
        if (item != null && !item.isActive)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: DashBadge(t('common.inactive')),
          ),
      ],
    );

    final extra = SizedBox(
      width: _extraWidth,
      child: LabelledField(
        label: t('combos.choice.surcharge'),
        small: true,
        child: InvalidOr(
          invalid: e.surcharge != null,
          child: DashTextInput(
            value: ch.surcharge,
            onChanged: (v) => onChanged(ch.copyWith(surcharge: v)),
            placeholder: '0',
            semanticLabel: t('combos.choice.surcharge'),
            invalid: e.surcharge != null,
            enabled: enabled,
            textDirection: TextDirection.ltr,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            mono: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSubmit(),
          ),
        ),
      ),
    );

    final remove = enabled
        ? DashIconButton(
            icon: 'trash-2',
            semanticLabel: t('combos.choice.remove'),
            color: c.danger,
            onPressed: onRemove,
          )
        : null;

    final head = LayoutBuilder(
      builder: (context, box) => box.maxWidth >= _rowWidth
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.sm,
              children: [
                segments,
                Expanded(child: pickerBlock),
                extra,
                if (remove != null)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(top: Space.lg),
                    child: remove,
                  ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              spacing: Space.sm,
              children: [
                Row(children: [segments, const Spacer(), ?remove]),
                pickerBlock,
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: extra,
                ),
              ],
            ),
    );

    Widget? sizes;
    if (labels.length > 1) {
      final includedSelect = LabelledField(
        label: t('combos.choice.includedSize'),
        small: true,
        child: DashSelect<String>(
          options: [
            DashOption(value: '', label: t('combos.choice.cheapest')),
            for (final l in labels)
              DashOption(value: l, label: sizeLabelText(t, l)),
          ],
          value: ch.includedSizeLabel,
          onChanged: (v) => onChanged(
            ch.copyWith(
              includedSizeLabel: v,
              sizeSurcharges: [
                for (final x in ch.sizeSurcharges)
                  if (x.label != v) x,
              ],
            ),
          ),
          semanticLabel: t('combos.choice.includedSize'),
          enabled: enabled,
        ),
      );
      final otherBoxes = others.isEmpty
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              spacing: Space.xs,
              children: [
                Text(
                  t('combos.choice.otherSizes'),
                  style: DashType.smallMedium.copyWith(color: c.textPrimary),
                ),
                Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.sm,
                  children: [
                    for (final label in others)
                      _SizeExtraBox(
                        label: sizeLabelText(t, label),
                        value: ch.sizeSurcharge(label),
                        placeholder: () {
                          final size = priceOf(label);
                          if (basePrice == null || size == null) {
                            return t('combos.choice.difference');
                          }
                          final diff = size - basePrice;
                          return t(
                            'combos.choice.differenceAmount',
                            args: {
                              'amount': f.fmtMoney(
                                diff < 0 ? 0 : diff,
                                currency: false,
                              ),
                            },
                          );
                        }(),
                        invalid:
                            e.badSizes.contains(label) ||
                            !_finiteOrBlank(ch.sizeSurcharge(label)),
                        enabled: enabled,
                        onSubmit: onSubmit,
                        onChanged: (v) =>
                            onChanged(ch.withSizeSurcharge(label, v)),
                      ),
                  ],
                ),
                HintLine(t('combos.choice.blankMeansDifference')),
              ],
            );
      sizes = LayoutBuilder(
        builder: (context, box) => box.maxWidth >= _rowWidth
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Space.md,
                children: [
                  SizedBox(width: _includedWidth, child: includedSelect),
                  if (otherBoxes != null) Expanded(child: otherBoxes),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                spacing: Space.md,
                children: [includedSelect, ?otherBoxes],
              ),
      );
    }

    // A saved item that is no longer on the menu gets an amber frame.
    final gone = ch.isItem && ch.menuItemId.isNotEmpty && item == null;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(
          color: gone ? DashTone.warning.foreground(c) : c.hairline,
        ),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.all(Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: Space.md,
          children: [
            head,
            if (e.surcharge != null) ErrorLine(t(e.surcharge!)),
            ?sizes,
          ],
        ),
      ),
    );
  }

  /// The extra charge box (`w-28`).
  static const double _extraWidth = 112;

  /// "Size the price covers" (`12rem`).
  static const double _includedWidth = 192;

  /// Narrower than this the row stacks (the web's row wraps).
  static const double _rowWidth = 520;
}

/// Junk in a size box is marked at once, before any Save.
bool _finiteOrBlank(String text) {
  final p = moneyIn(text);
  return p == null || p.isFinite;
}

/// One "other size" box: the size's name, then its EGP (no words under it
/// when refused: only the invalid mark).
class _SizeExtraBox extends ConsumerWidget {
  const _SizeExtraBox({
    required this.label,
    required this.value,
    required this.placeholder,
    required this.invalid,
    required this.enabled,
    required this.onSubmit,
    required this.onChanged,
  });

  final String label;
  final String value;
  final String placeholder;
  final bool invalid;
  final bool enabled;
  final VoidCallback onSubmit;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: Space.xs + DashMetrics.hair,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: Space.xxl + Space.lg),
          child: Text(
            label,
            style: DashType.small.copyWith(color: c.textSecondary),
          ),
        ),
        SizedBox(
          width: _ChoiceRow._extraWidth,
          child: InvalidOr(
            invalid: invalid,
            child: DashTextInput(
              value: value,
              onChanged: onChanged,
              placeholder: placeholder,
              semanticLabel: t(
                'combos.choice.sizeExtra',
                args: {'size': label},
              ),
              invalid: invalid,
              enabled: enabled,
              textDirection: TextDirection.ltr,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              mono: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onSubmit(),
            ),
          ),
        ),
      ],
    );
  }
}

/// A whole double as an int, so `{{count}}` reads "2", not "2.0".
num _whole(double n) => n == n.truncateToDouble() ? n.toInt() : n;
