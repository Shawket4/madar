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
    this.group,
  });
  final T value;
  final String label;

  /// A heading shown above the first option of a run of options with this
  /// group (the web's `SelectGroup` + `SelectLabel`); null = no heading.
  final String? group;

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
    this.onIntent,
    this.placeholder = false,
    this.invalid = false,
    this.warning = false,
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

  /// About to be pressed ([DashIntent]): warm the read the press leads to.
  final VoidCallback? onIntent;

  /// The label is a placeholder (muted).
  final bool placeholder;
  final bool invalid;

  /// A soft warning edge and a warning-tinted glyph (a past date).
  final bool warning;
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
      onIntent: onIntent,
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
            warning: warning,
            focused: s.focused,
            shrinkWrap: !expand && width == null,
            leading: leadingIcon == null
                ? null
                : DashIcon(
                    leadingIcon!,
                    size: IconSize.sm,
                    color: warning
                        ? DashTone.warning.foreground(c)
                        : c.textSecondary,
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
    this.onIntent,
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

  /// An option is about to be picked ([DashIntent]): warm the read it
  /// leads to (the list under that filter).
  final ValueChanged<T>? onIntent;
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

  /// A plain list is short and capped (256): every row is built, so a
  /// keyboard pick or a test can scroll to any of them. A searchable one may
  /// be long: lazy.
  Widget _rows(
    BuildContext context,
    List<DashOption<T>> list,
    IndexedWidgetBuilder row,
  ) => widget.searchable
      ? ListView.builder(
          shrinkWrap: widget.shrinkWrap,
          padding: const EdgeInsets.all(Space.xs),
          itemCount: list.length,
          itemBuilder: row,
        )
      : SingleChildScrollView(
          padding: const EdgeInsets.all(Space.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (var i = 0; i < list.length; i++) row(context, i)],
          ),
        );

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
        : _rows(context, list, (context, i) {
            final group = list[i].group;
            final row = _OptionRow<T>(
              option: list[i],
              selected: widget.isSelected(list[i].value),
              active: i == _active,
              multi: widget.multi,
              onTap: () => widget.onPick(list[i].value),
              onIntent: widget.onIntent == null
                  ? null
                  : () => widget.onIntent!(list[i].value),
            );
            if (group == null || (i > 0 && list[i - 1].group == group)) {
              return row;
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    Space.sm,
                    Space.sm,
                    Space.sm,
                    Space.xs,
                  ),
                  child: Semantics(
                    header: true,
                    child: Text(
                      group,
                      style: DashType.small.copyWith(
                        color: c.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                row,
              ],
            );
          });
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
    this.onIntent,
  });

  final DashOption<T> option;
  final bool selected;
  final bool active;
  final bool multi;
  final VoidCallback onTap;
  final VoidCallback? onIntent;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    // The arrow keys' row stays in the capped list's view, as Radix scrolls
    // its highlighted item into view.
    if (active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        for (final p in const [
          ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        ]) {
          Scrollable.ensureVisible(context, alignmentPolicy: p);
        }
      });
    }
    return DashPressable(
      onTap: option.enabled ? onTap : null,
      onIntent: onIntent,
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

/// A single select (the web's `Select`): a trigger and a list under it, on
/// a phone too, as the web shows it there. [searchable] makes it the web's
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
    this.active = false,
    this.expand = true,
    this.onOptionIntent,
    super.key,
  });

  final List<DashOption<T>> options;
  final T? value;
  final ValueChanged<T> onChanged;

  /// An option is about to be picked ([DashIntent]): warm the read the
  /// change makes (the list under that filter, same other filters).
  final ValueChanged<T>? onOptionIntent;

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

  @override
  Widget build(BuildContext context) {
    final t = context.dashStrings;
    final sel = _selected;
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
    return DashPopover(
      controller: _popover,
      matchAnchorWidth: true,
      width: widget.searchable
          ? DashMetrics.popover
          : DashMetrics.menu - Space.xxl,
      // A plain list takes the room the window has and scrolls past it (the
      // web's Select: max-h of the available height); a searchable one is
      // cmdk's 300 px list under its search box.
      maxHeight: widget.searchable ? 360 : double.infinity,
      anchor: (context, c) => trigger(c.toggle),
      content: (context, c) => DashOptionList<T>(
        options: widget.options,
        isSelected: (v) => v == widget.value,
        searchable: widget.searchable,
        searchPlaceholder: widget.searchPlaceholder,
        emptyText: widget.emptyText,
        onIntent: widget.onOptionIntent,
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
    return DashPopover(
      matchAnchorWidth: true,
      anchor: (context, c) => trigger(c.toggle),
      content: (context, c) =>
          StatefulBuilder(builder: (context, inner) => _list(inner)),
    );
  }
}
