/// Which items a deal counts (the web's `features/deals/pool-editor.tsx`):
/// items or whole categories, each optionally at one size ("Any size" by
/// default). Controlled, so the pool and the reward list share it.
///
/// Looser than a combo choice, as on the web: the same item may be listed
/// twice, a switched-off item has no badge and is offered in the picker, an
/// item that is gone just reads "Choose an item" (its id is sent back as it
/// was), and pressing the segment already chosen still clears the entry.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/menu_options.dart';
import '../shared/offers_format.dart';
import 'deal_form.dart';

class PoolEditor extends ConsumerWidget {
  const PoolEditor({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.menu,
    this.errors = const [],
    this.enabled = true,
    super.key,
  });

  /// The list's name ("Items that count", "Reward items"): its accessible
  /// name.
  final String label;
  final List<PoolEntryDraft> value;
  final ValueChanged<List<PoolEntryDraft>> onChanged;
  final MenuOptions menu;

  /// One per entry (an i18n key, or null).
  final List<String?> errors;

  /// False = read-only: every control disabled, no remove, no add.
  final bool enabled;

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

    void patch(int i, PoolEntryDraft next) => onChanged([
      for (var j = 0; j < value.length; j++) j == i ? next : value[j],
    ]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.sm,
      children: [
        Semantics(
          container: true,
          explicitChildNodes: true,
          label: label,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: Space.sm,
            children: [
              for (var i = 0; i < value.length; i++)
                _PoolEntryRow(
                  key: ValueKey(value[i].key),
                  entry: value[i],
                  error: i < errors.length ? errors[i] : null,
                  menu: menu,
                  itemOptions: itemOptions,
                  categoryOptions: categoryOptions,
                  enabled: enabled,
                  t: t,
                  onChanged: (e) => patch(i, e),
                  onRemove: () => onChanged([
                    for (var j = 0; j < value.length; j++)
                      if (j != i) value[j],
                  ]),
                ),
            ],
          ),
        ),
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
                onPressed: () => onChanged([...value, PoolEntryDraft.empty()]),
              ),
              DashButton(
                label: t('combos.slots.addCategory'),
                icon: 'folder-tree',
                variant: DashButtonVariant.outline,
                size: DashButtonSize.compact,
                onPressed: () => onChanged([
                  ...value,
                  PoolEntryDraft.empty(PoolTarget.category),
                ]),
              ),
            ],
          ),
      ],
    );
  }
}

class _PoolEntryRow extends StatelessWidget {
  const _PoolEntryRow({
    required this.entry,
    required this.error,
    required this.menu,
    required this.itemOptions,
    required this.categoryOptions,
    required this.enabled,
    required this.t,
    required this.onChanged,
    required this.onRemove,
    super.key,
  });

  final PoolEntryDraft entry;
  final String? error;
  final MenuOptions menu;
  final List<DashOption<String>> itemOptions;
  final List<DashOption<String>> categoryOptions;
  final bool enabled;
  final Translator t;
  final ValueChanged<PoolEntryDraft> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final e = entry;
    final sizes = e.target == PoolTarget.item
        ? [for (final s in menu.item(e.menuItemId)?.sizes ?? const []) s.label]
        : (e.categoryId.isNotEmpty
              ? menu.categorySizeLabels(e.categoryId)
              : const <String>[]);

    final segments = DashSegmentedControl<PoolTarget>(
      options: [
        DashOption(value: PoolTarget.item, label: t('combos.choice.item')),
        DashOption(
          value: PoolTarget.category,
          label: t('combos.choice.category'),
        ),
      ],
      value: e.target,
      enabled: enabled,
      // Always a change, even on the chosen segment (the web's control).
      onChanged: (v) => onChanged(
        e.copyWith(target: v, menuItemId: '', categoryId: '', sizeLabel: ''),
      ),
    );

    final picker = e.target == PoolTarget.item
        ? DashSelect<String>(
            options: itemOptions,
            value: e.menuItemId.isEmpty ? null : e.menuItemId,
            onChanged: (v) =>
                onChanged(e.copyWith(menuItemId: v, sizeLabel: '')),
            placeholder: t('combos.choice.pickItem'),
            semanticLabel: t('combos.choice.pickItem'),
            searchable: true,
            searchPlaceholder: t('common.search'),
            emptyText: t('common.noResults'),
            invalid: error != null,
            enabled: enabled,
          )
        : DashSelect<String>(
            options: categoryOptions,
            value: e.categoryId.isEmpty ? null : e.categoryId,
            onChanged: (v) =>
                onChanged(e.copyWith(categoryId: v, sizeLabel: '')),
            placeholder: t('combos.choice.pickCategory'),
            semanticLabel: t('combos.choice.pickCategory'),
            invalid: error != null,
            enabled: enabled,
          );

    final size = sizes.length > 1
        ? SizedBox(
            width: _sizeWidth,
            child: DashSelect<String>(
              options: [
                DashOption(value: '', label: t('deals.pool.anySize')),
                for (final s in sizes)
                  DashOption(value: s, label: sizeLabelText(t, s)),
              ],
              value: e.sizeLabel,
              onChanged: (v) => onChanged(e.copyWith(sizeLabel: v)),
              semanticLabel: t('deals.pool.size'),
              enabled: enabled,
            ),
          )
        : null;

    final remove = enabled
        ? DashIconButton(
            icon: 'trash-2',
            semanticLabel: t('deals.pool.remove'),
            color: c.danger,
            onPressed: onRemove,
          )
        : null;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: c.hairline),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.all(Space.sm + DashMetrics.hair),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: Space.xs,
          children: [
            LayoutBuilder(
              builder: (context, box) => box.maxWidth >= _rowWidth
                  ? Row(
                      spacing: Space.sm,
                      children: [
                        segments,
                        Expanded(child: picker),
                        ?size,
                        ?remove,
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      spacing: Space.sm,
                      children: [
                        Row(children: [segments, const Spacer(), ?remove]),
                        picker,
                        ?size,
                      ],
                    ),
            ),
            if (error != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  t(error!),
                  style: DashType.small.copyWith(color: c.errorText),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The size select's width (`w-36`).
  static const double _sizeWidth = 144;

  /// Narrower than this the entry stacks (the web's row wraps).
  static const double _rowWidth = 520;
}
