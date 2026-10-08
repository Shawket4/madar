import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'controls.dart';
import 'foundation/l10n.dart';
import 'foundation/popover.dart';
import 'foundation/press.dart';
import 'foundation/tokens.dart';

/// One choice in a select, combobox or multi-select.
@immutable
class DashOption<T> {
  const DashOption({
    required this.value,
    required this.label,
    this.hint,
    this.keywords,
    this.icon,
    this.enabled = true,
  });
  final T value;
  final String label;

  /// A quiet word on the end side (a role, a branch).
  final String? hint;

  /// Extra searchable text, not shown ("new york" finds America/New_York).
  final String? keywords;
  final String? icon;
  final bool enabled;

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return '$label ${keywords ?? ''} ${hint ?? ''}'.toLowerCase().contains(q);
  }
}

/// The closed face of a select: the chosen label (or a muted placeholder)
/// and a chevron, in a field frame (the web's `SelectTrigger`).
class DashSelectTrigger extends StatelessWidget {
  const DashSelectTrigger({
    required this.label,
    required this.onTap,
    this.placeholder = false,
    this.invalid = false,
    this.enabled = true,
    this.leadingIcon,
    this.chevron = 'chevron-down',
    this.semanticLabel,
    this.width,
    this.minWidth,
    this.active = false,
    this.expand = true,
    super.key,
  });

  final String label;
  final VoidCallback onTap;

  /// The label is a placeholder (muted).
  final bool placeholder;
  final bool invalid;
  final bool enabled;
  final String? leadingIcon;
  final String chevron;
  final String? semanticLabel;
  final double? width;
  final double? minWidth;

  /// A filter that is set (ink edge).
  final bool active;

  /// Fill the line (a form field); off, it fits its label (a filter).
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return DashPressable(
      onTap: enabled ? onTap : null,
      enabled: enabled,
      pressScale: false,
      semanticLabel: semanticLabel == null ? label : '$semanticLabel: $label',
      excludeChildSemantics: true,
      builder: (context, s) => ConstrainedBox(
        constraints: BoxConstraints(minWidth: minWidth ?? 0),
        child: SizedBox(
          width: width,
          child: DashFieldShell(
            enabled: enabled,
            invalid: invalid,
            focused: s.focused,
            shrinkWrap: !expand && width == null,
            leading: leadingIcon == null
                ? null
                : DashIcon(
                    leadingIcon!,
                    size: IconSize.sm,
                    color: c.textSecondary,
                  ),
            trailing: DashIcon(
              chevron,
              size: IconSize.sm,
              color: c.textSecondary.withValues(alpha: 0.7),
            ),
            child: Builder(
              builder: (context) {
                final text = MadarClippedText(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashType.body.copyWith(
                    color: placeholder ? c.textMuted : c.textPrimary,
                    fontWeight: active ? FontWeight.w500 : null,
                  ),
                );
                return Align(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: !expand && width == null ? 1 : null,
                  child: text,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// A list of options with a check on the chosen one(s), an optional search
/// box above, keyboard ↑/↓/Enter. Shared by the popovers and the phone
/// sheets.
class DashOptionList<T> extends StatefulWidget {
  const DashOptionList({
    required this.options,
    required this.isSelected,
    required this.onPick,
    this.searchable = false,
    this.searchPlaceholder,
    this.emptyText,
    this.multi = false,
    this.shrinkWrap = true,
    super.key,
  });

  final List<DashOption<T>> options;
  final bool Function(T value) isSelected;
  final ValueChanged<T> onPick;
  final bool searchable;
  final String? searchPlaceholder;
  final String? emptyText;

  /// Checkboxes instead of a check mark.
  final bool multi;
  final bool shrinkWrap;

  @override
  State<DashOptionList<T>> createState() => _DashOptionListState<T>();
}

class _DashOptionListState<T> extends State<DashOptionList<T>> {
  String _query = '';
  int _active = -1;

  List<DashOption<T>> get _filtered => [
    for (final o in widget.options)
      if (o.matches(_query)) o,
  ];

  KeyEventResult _key(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final list = _filtered;
    if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => _active = (_active + 1).clamp(0, list.length - 1));
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() => _active = (_active - 1).clamp(0, list.length - 1));
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.enter &&
        _active >= 0 &&
        _active < list.length) {
      widget.onPick(list[_active].value);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final t = context.dashStrings;
    final list = _filtered;
    final items = list.isEmpty
        ? Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Text(
              widget.emptyText ?? t.noResults,
              textAlign: TextAlign.center,
              style: DashType.body.copyWith(color: c.textSecondary),
            ),
          )
        : ListView.builder(
            shrinkWrap: widget.shrinkWrap,
            padding: const EdgeInsets.all(Space.xs),
            itemCount: list.length,
            itemBuilder: (context, i) => _OptionRow<T>(
              option: list[i],
              selected: widget.isSelected(list[i].value),
              active: i == _active,
              multi: widget.multi,
              onTap: () => widget.onPick(list[i].value),
            ),
          );
    return Focus(
      onKeyEvent: _key,
      autofocus: !widget.searchable,
      child: Column(
        mainAxisSize: widget.shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.searchable)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.sm,
                Space.sm,
                Space.sm,
                Space.xs,
              ),
              child: DashTextInput(
                value: _query,
                autofocus: true,
                leadingIcon: 'search',
                placeholder: widget.searchPlaceholder ?? t.searchPlaceholder,
                semanticLabel: widget.searchPlaceholder ?? t.search,
                onChanged: (v) => setState(() {
                  _query = v;
                  _active = v.isEmpty ? -1 : 0;
                }),
                onKeyEvent: _key,
              ),
            ),
          if (widget.shrinkWrap)
            Flexible(child: items)
          else
            Expanded(child: items),
        ],
      ),
    );
  }
}

class _OptionRow<T> extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.selected,
    required this.active,
    required this.multi,
    required this.onTap,
  });

  final DashOption<T> option;
  final bool selected;
  final bool active;
  final bool multi;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return DashPressable(
      onTap: option.enabled ? onTap : null,
      enabled: option.enabled,
      selected: selected,
      checked: multi ? selected : null,
      pressScale: false,
      semanticLabel: option.label,
      excludeChildSemantics: true,
      builder: (context, s) => Container(
        constraints: const BoxConstraints(
          minHeight: DashMetrics.target - Space.xs,
        ),
        padding: const EdgeInsets.symmetric(horizontal: Space.sm),
        decoration: BoxDecoration(
          color: active || s.highlighted || s.focused ? c.hover : null,
          borderRadius: BorderRadius.circular(Radii.xs),
        ),
        child: Row(
          spacing: Space.sm,
          children: [
            if (multi)
              IgnorePointer(
                child: SizedBox(
                  width: DashMetrics.checkbox,
                  height: DashMetrics.checkbox,
                  child: OverflowBox(
                    maxWidth: DashMetrics.target,
                    maxHeight: DashMetrics.target,
                    child: DashCheckbox(
                      value: selected,
                      onChanged: (_) {},
                      semanticLabel: option.label,
                    ),
                  ),
                ),
              )
            else
              SizedBox.square(
                dimension: IconSize.sm,
                child: selected
                    ? DashIcon('check', size: IconSize.sm, color: c.textPrimary)
                    : null,
              ),
            if (option.icon != null)
              DashIcon(option.icon!, size: IconSize.sm, color: c.textSecondary),
            Expanded(
              child: MadarClippedText(
                option.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashType.body.copyWith(
                  color: option.enabled ? c.textPrimary : c.disabledText,
                  fontWeight: selected ? FontWeight.w600 : null,
                ),
              ),
            ),
            if (option.hint != null)
              Text(
                option.hint!,
                style: DashType.small.copyWith(color: c.textSecondary),
              ),
          ],
        ),
      ),
    );
  }
}

/// A single select (the web's `Select`): a trigger, a list under it on a
/// wide screen, a sheet on a phone. [searchable] makes it the web's
/// `Combobox`.
class DashSelect<T> extends StatefulWidget {
  const DashSelect({
    required this.options,
    required this.value,
    required this.onChanged,
    this.placeholder,
    this.semanticLabel,
    this.searchable = false,
    this.searchPlaceholder,
    this.emptyText,
    this.invalid = false,
    this.enabled = true,
    this.width,
    this.minWidth,
    this.leadingIcon,
    this.sheetTitle,
    this.active = false,
    this.expand = true,
    super.key,
  });

  final List<DashOption<T>> options;
  final T? value;
  final ValueChanged<T> onChanged;

  /// Fill the line (forms) or fit the label (filter rows).
  final bool expand;

  /// Shown when nothing is chosen; defaults to "Select…".
  final String? placeholder;

  /// The accessible name (a filter has no visible label).
  final String? semanticLabel;
  final bool searchable;
  final String? searchPlaceholder;
  final String? emptyText;
  final bool invalid;
  final bool enabled;
  final double? width;
  final double? minWidth;
  final String? leadingIcon;

  /// The phone sheet's title; defaults to [semanticLabel] / [placeholder].
  final String? sheetTitle;

  /// A filter that is narrowing the list.
  final bool active;

  @override
  State<DashSelect<T>> createState() => _DashSelectState<T>();
}

class _DashSelectState<T> extends State<DashSelect<T>> {
  final _popover = DashPopoverController();

  @override
  void dispose() {
    _popover.dispose();
    super.dispose();
  }

  DashOption<T>? get _selected {
    for (final o in widget.options) {
      if (o.value == widget.value) return o;
    }
    return null;
  }

  Future<void> _openSheet(BuildContext context) async {
    final t = context.dashStrings;
    final picked = await showDashPickerSheet<DashOption<T>>(
      context,
      title:
          widget.sheetTitle ??
          widget.semanticLabel ??
          widget.placeholder ??
          t.select,
      fullHeight: widget.searchable,
      builder: (sheet) => DashOptionList<T>(
        options: widget.options,
        isSelected: (v) => v == widget.value,
        searchable: widget.searchable,
        searchPlaceholder: widget.searchPlaceholder,
        emptyText: widget.emptyText,
        shrinkWrap: !widget.searchable,
        onPick: (v) => Navigator.of(
          sheet,
        ).pop(widget.options.firstWhere((o) => o.value == v)),
      ),
    );
    if (picked != null && picked.value != widget.value) {
      widget.onChanged(picked.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.dashStrings;
    final sel = _selected;
    final phone = DashBreakpoints.isPhone(context);
    Widget trigger(VoidCallback onTap) => DashSelectTrigger(
      label: sel?.label ?? widget.placeholder ?? t.select,
      placeholder: sel == null,
      onTap: onTap,
      invalid: widget.invalid,
      enabled: widget.enabled,
      width: widget.width,
      minWidth: widget.minWidth,
      leadingIcon: widget.leadingIcon,
      semanticLabel: widget.semanticLabel,
      active: widget.active,
      expand: widget.expand,
      chevron: widget.searchable ? 'chevrons-up-down' : 'chevron-down',
    );
    if (phone) return trigger(() => _openSheet(context));
    return DashPopover(
      controller: _popover,
      matchAnchorWidth: true,
      width: widget.searchable
          ? DashMetrics.popover
          : DashMetrics.menu - Space.xxl,
      anchor: (context, c) => trigger(c.toggle),
      content: (context, c) => DashOptionList<T>(
        options: widget.options,
        isSelected: (v) => v == widget.value,
        searchable: widget.searchable,
        searchPlaceholder: widget.searchPlaceholder,
        emptyText: widget.emptyText,
        onPick: (v) {
          c.close();
          if (v != widget.value) widget.onChanged(v);
        },
      ),
    );
  }
}

/// Pick several (the web's checkbox lists and chip filters): the trigger
/// reads the chosen labels joined (or "N selected"), the list has checkboxes
/// and a search box when [searchable].
class DashMultiSelect<T> extends StatefulWidget {
  const DashMultiSelect({
    required this.options,
    required this.values,
    required this.onChanged,
    this.placeholder,
    this.semanticLabel,
    this.searchable = true,
    this.searchPlaceholder,
    this.invalid = false,
    this.enabled = true,
    this.width,
    this.minWidth,
    this.expand = true,
    super.key,
  });

  final List<DashOption<T>> options;

  /// Fill the line (forms) or fit the label (filter rows).
  final bool expand;
  final Set<T> values;
  final ValueChanged<Set<T>> onChanged;
  final String? placeholder;
  final String? semanticLabel;
  final bool searchable;
  final String? searchPlaceholder;
  final bool invalid;
  final bool enabled;
  final double? width;
  final double? minWidth;

  @override
  State<DashMultiSelect<T>> createState() => _DashMultiSelectState<T>();
}

class _DashMultiSelectState<T> extends State<DashMultiSelect<T>> {
  late Set<T> _working = {...widget.values};

  @override
  void didUpdateWidget(DashMultiSelect<T> old) {
    super.didUpdateWidget(old);
    _working = {...widget.values};
  }

  void _toggle(T v, StateSetter? inner) {
    final next = {..._working};
    if (!next.remove(v)) next.add(v);
    _working = next;
    inner?.call(() {});
    setState(() {});
    widget.onChanged(next);
  }

  String _summary(BuildContext context) {
    final t = context.dashStrings;
    final chosen = [
      for (final o in widget.options)
        if (widget.values.contains(o.value)) o.label,
    ];
    if (chosen.isEmpty) return widget.placeholder ?? t.select;
    if (chosen.length <= 2) return chosen.join(t.listSeparator);
    return t.selectedCount(chosen.length);
  }

  Widget _list(StateSetter? inner) => DashOptionList<T>(
    options: widget.options,
    multi: true,
    isSelected: _working.contains,
    searchable: widget.searchable,
    searchPlaceholder: widget.searchPlaceholder,
    onPick: (v) => _toggle(v, inner),
  );

  @override
  Widget build(BuildContext context) {
    final phone = DashBreakpoints.isPhone(context);
    final t = context.dashStrings;
    Widget trigger(VoidCallback onTap) => DashSelectTrigger(
      label: _summary(context),
      placeholder: widget.values.isEmpty,
      active: widget.values.isNotEmpty,
      onTap: onTap,
      invalid: widget.invalid,
      enabled: widget.enabled,
      width: widget.width,
      minWidth: widget.minWidth,
      semanticLabel: widget.semanticLabel,
      chevron: 'chevrons-up-down',
      expand: widget.expand,
    );
    if (phone) {
      return trigger(
        () => showDashPickerSheet<void>(
          context,
          title: widget.semanticLabel ?? widget.placeholder ?? t.select,
          fullHeight: widget.searchable,
          builder: (sheet) =>
              StatefulBuilder(builder: (context, inner) => _list(inner)),
        ),
      );
    }
    return DashPopover(
      matchAnchorWidth: true,
      anchor: (context, c) => trigger(c.toggle),
      content: (context, c) =>
          StatefulBuilder(builder: (context, inner) => _list(inner)),
    );
  }
}
