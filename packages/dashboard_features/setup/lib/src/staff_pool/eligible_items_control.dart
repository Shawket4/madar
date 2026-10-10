/// Which menu items count as a staff drink
/// (`features/staff-pool/eligible-items-control.tsx`, SET-SPL-010 … 013,
/// 022): a trigger saying how many count (or that the pool is off), a
/// searchable list over the whole org menu, Clear, and a chip per chosen
/// item. The list is a 288 px popover from 760 wide, a picker sheet below.
library;

import 'package:dashboard_api/dashboard_api.dart' show MenuItem;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'staff_pool_data.dart';

/// The popover's width (`w-72`).
const double _popoverWidth = 288;

/// The popover's height cap, so a long menu scrolls inside it.
const double _popoverMaxHeight = 420;

class EligibleItemsControl extends ConsumerStatefulWidget {
  const EligibleItemsControl({
    required this.orgId,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final String? orgId;
  final List<String> value;
  final ValueChanged<List<String>> onChanged;
  final bool enabled;

  @override
  ConsumerState<EligibleItemsControl> createState() =>
      _EligibleItemsControlState();
}

class _EligibleItemsControlState extends ConsumerState<EligibleItemsControl> {
  final _popover = DashPopoverController();

  @override
  void initState() {
    super.initState();
    _popover.addListener(_changed);
  }

  @override
  void dispose() {
    _popover.removeListener(_changed);
    _popover.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  void _toggle(String id) => widget.onChanged(
    widget.value.contains(id)
        ? [
            for (final x in widget.value)
              if (x != id) x,
          ]
        : [...widget.value, id],
  );

  void _warm() {
    final org = widget.orgId;
    if (org != null) ref.warm(staffPoolMenuProvider(org));
  }

  Future<void> _openSheet(Translator t) => showDashPickerSheet<void>(
    context,
    title: t('staffPool.items'),
    fullHeight: true,
    builder: (_) => _PickerBody(
      orgId: widget.orgId,
      value: widget.value,
      onChanged: widget.onChanged,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final lang = ref.watch(localeProvider);
    final org = widget.orgId;
    final ids = widget.value;
    // Loaded to name the chips too: a chip reading a raw id is worse than
    // none. While the list is open, the list itself keeps it.
    final menu = org != null && ids.isNotEmpty
        ? ref.watch(staffPoolMenuProvider(org)).value
        : null;
    final names = {
      for (final m in menu ?? const <MenuItem>[])
        m.id: staffPoolItemName(m, lang),
    };
    final label = ids.isEmpty
        ? t('staffPool.itemsNoneChosen')
        : t('staffPool.itemsChosen', count: ids.length);
    Widget trigger(VoidCallback onTap) => _Trigger(
      key: const ValueKey('spl-items-trigger'),
      label: label,
      semanticLabel: t('staffPool.items'),
      enabled: widget.enabled,
      onTap: onTap,
      onIntent: _warm,
    );
    final phone = DashBreakpoints.isPhone(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.sm,
      children: [
        if (phone)
          trigger(() => _openSheet(t))
        else
          DashPopover(
            controller: _popover,
            width: _popoverWidth,
            maxHeight: _popoverMaxHeight,
            anchor: (context, c) => trigger(c.toggle),
            content: (context, c) => _PickerBody(
              orgId: org,
              value: ids,
              onChanged: widget.onChanged,
            ),
          ),
        if (ids.isNotEmpty)
          Wrap(
            key: const ValueKey('spl-chips'),
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final id in ids)
                _Chip(
                  key: ValueKey('spl-chip-$id'),
                  label: names[id] ?? id,
                  removeLabel: t(
                    'staffPool.itemRemove',
                    args: {'item': names[id] ?? id},
                  ),
                  onRemove: widget.enabled ? () => _toggle(id) : null,
                ),
            ],
          ),
      ],
    );
  }
}

/// The outline trigger (`Button variant="outline" justify-start` with a
/// CupSoda): start-aligned, the count or the pool-off words.
class _Trigger extends StatelessWidget {
  const _Trigger({
    required this.label,
    required this.semanticLabel,
    required this.enabled,
    required this.onTap,
    required this.onIntent,
    super.key,
  });

  final String label;
  final String semanticLabel;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onIntent;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return DashPressable(
      onTap: enabled ? onTap : null,
      onIntent: enabled ? onIntent : null,
      enabled: enabled,
      pressScale: false,
      semanticLabel: '$semanticLabel: $label',
      excludeChildSemantics: true,
      builder: (context, s) => DashFieldShell(
        enabled: enabled,
        focused: s.focused,
        hovered: s.hovered,
        leading: DashIcon('cup-soda', size: IconSize.sm, color: c.textPrimary),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: MadarClippedText(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DashType.bodyMedium.copyWith(color: c.textPrimary),
          ),
        ),
      ),
    );
  }
}

/// The list: the note, search, "Counts as a staff drink" with a check on
/// each chosen item, and Clear while any is chosen. It keeps its own copy
/// of the choice so the phone sheet (built once) follows each toggle; the
/// popover hands it the new value on every rebuild.
class _PickerBody extends ConsumerStatefulWidget {
  const _PickerBody({
    required this.orgId,
    required this.value,
    required this.onChanged,
  });

  final String? orgId;
  final List<String> value;
  final ValueChanged<List<String>> onChanged;

  @override
  ConsumerState<_PickerBody> createState() => _PickerBodyState();
}

class _PickerBodyState extends ConsumerState<_PickerBody> {
  late List<String> _value = widget.value;

  @override
  void didUpdateWidget(_PickerBody old) {
    super.didUpdateWidget(old);
    _value = widget.value;
  }

  void _set(List<String> next) {
    setState(() => _value = next);
    widget.onChanged(next);
  }

  void _toggle(String id) => _set(
    _value.contains(id)
        ? [
            for (final x in _value)
              if (x != id) x,
          ]
        : [..._value, id],
  );

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final lang = ref.watch(localeProvider);
    final c = context.madarColors;
    final org = widget.orgId;
    final q = org == null ? null : ref.watch(staffPoolMenuProvider(org));
    final heading = t('staffPool.itemsHeading');
    final options = [
      for (final m in q?.value ?? const <MenuItem>[])
        DashOption<String>(
          value: m.id,
          label: staffPoolItemName(m, lang),
          group: heading,
        ),
    ];
    return Column(
      key: const ValueKey('spl-picker'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.md,
            vertical: Space.sm,
          ),
          decoration: BoxDecoration(
            color: c.muted.withValues(alpha: 0.4),
            border: Border(bottom: BorderSide(color: c.border)),
          ),
          child: Text(
            t('staffPool.itemsPickerNote'),
            style: DashType.small.copyWith(color: c.textSecondary),
          ),
        ),
        Flexible(
          child: DashOptionList<String>(
            options: options,
            isSelected: _value.contains,
            onPick: _toggle,
            searchable: true,
            searchPlaceholder: t('common.search'),
            emptyText: q?.awaitingFirst ?? false
                ? t('common.loading')
                : t('common.noResults'),
          ),
        ),
        if (_value.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(Space.xs),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.border)),
            ),
            child: DashButton(
              key: const ValueKey('spl-items-clear'),
              label: t('common.clear'),
              variant: DashButtonVariant.ghost,
              size: DashButtonSize.compact,
              expand: true,
              onPressed: () => _set(const []),
            ),
          ),
      ],
    );
  }
}

/// One chosen item (`Badge variant="outline"`) with its ×.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.removeLabel,
    required this.onRemove,
    super.key,
  });

  final String label;
  final String removeLabel;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      padding: const EdgeInsetsDirectional.only(start: Space.sm),
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(Radii.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: MadarClippedText(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DashType.small.copyWith(
                color: c.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          DashIconButton(
            icon: 'x',
            semanticLabel: removeLabel,
            iconSize: IconSize.xs,
            color: c.textSecondary,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
