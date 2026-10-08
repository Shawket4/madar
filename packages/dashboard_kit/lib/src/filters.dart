import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'buttons.dart';
import 'controls.dart';
import 'dates.dart';
import 'foundation/l10n.dart';
import 'foundation/tokens.dart';
import 'select.dart';

/// The filter row under a page header (the web's `below` row): a debounced
/// search box, then the filters (selects, chips, a period), a Clear that
/// shows while anything is narrowing the list, and trailing actions at the
/// end (an export). Wraps on a narrow window; the search takes the full
/// line on a phone.
class DashFilterBar extends StatelessWidget {
  const DashFilterBar({
    this.searchValue,
    this.onSearchChanged,
    this.searchPlaceholder,
    this.searchDebounce = DashSearchInput.listDelay,
    this.filters = const [],
    this.onClear,
    this.trailing = const [],
    super.key,
  });

  /// The query in force (already debounced).
  final String? searchValue;

  /// Called with the trimmed query once typing pauses.
  final ValueChanged<String>? onSearchChanged;
  final String? searchPlaceholder;
  final Duration? searchDebounce;
  final List<Widget> filters;

  /// Clears every filter; the Clear button shows only when this is set.
  final VoidCallback? onClear;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.dashStrings;
    final phone = DashBreakpoints.isPhone(context);
    final search = onSearchChanged == null
        ? null
        : DashSearchInput(
            value: searchValue ?? '',
            onChanged: onSearchChanged!,
            placeholder: searchPlaceholder ?? t.searchPlaceholder,
            debounce: searchDebounce,
            width: phone ? null : DashMetrics.searchWidth,
          );
    final clear = onClear == null
        ? null
        : DashButton(
            label: t.clear,
            icon: 'x',
            variant: DashButtonVariant.ghost,
            size: DashButtonSize.compact,
            onPressed: onClear,
          );
    final row = Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [if (search != null && !phone) search, ...filters, ?clear],
    );
    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.sm,
        children: [
          if (search != null && phone) search,
          if (trailing.isEmpty || phone)
            row
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.sm,
              children: [
                Expanded(child: row),
                Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.sm,
                  children: trailing,
                ),
              ],
            ),
          if (phone && trailing.isNotEmpty)
            Wrap(spacing: Space.sm, runSpacing: Space.sm, children: trailing),
        ],
      ),
    );
  }
}

/// A select in a filter row: its first option is "All …" (null), it inks
/// its edge while it narrows the list.
class DashFilterSelect<T> extends StatelessWidget {
  const DashFilterSelect({
    required this.label,
    required this.allLabel,
    required this.options,
    required this.value,
    required this.onChanged,
    this.searchable = false,
    this.minWidth = 136,
    super.key,
  });

  /// The accessible name ("Status").
  final String label;

  /// The no-filter choice ("All statuses").
  final String allLabel;
  final List<DashOption<T>> options;
  final T? value;
  final ValueChanged<T?> onChanged;
  final bool searchable;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    return DashSelect<_All<T>>(
      semanticLabel: label,
      sheetTitle: label,
      searchable: searchable,
      minWidth: minWidth,
      expand: false,
      active: value != null,
      options: [
        DashOption(value: _All<T>(null), label: allLabel),
        for (final o in options)
          DashOption(
            value: _All<T>(o.value),
            label: o.label,
            hint: o.hint,
            keywords: o.keywords,
            icon: o.icon,
          ),
      ],
      value: _All<T>(value),
      onChanged: (v) => onChanged(v.value),
    );
  }
}

@immutable
class _All<T> {
  const _All(this.value);
  final T? value;

  @override
  bool operator ==(Object other) => other is _All<T> && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// Multi-select chips in a filter row: each choice a pill that toggles.
class DashFilterChips<T> extends StatelessWidget {
  const DashFilterChips({
    required this.options,
    required this.values,
    required this.onChanged,
    this.semanticLabel,
    super.key,
  });

  final List<DashOption<T>> options;
  final Set<T> values;
  final ValueChanged<Set<T>> onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: semanticLabel,
      child: Wrap(
        spacing: Space.xs + DashMetrics.hair,
        runSpacing: 0,
        children: [
          for (final o in options)
            DashChoiceChip(
              label: o.label,
              icon: o.icon,
              selected: values.contains(o.value),
              enabled: o.enabled,
              onTap: () {
                final next = {...values};
                if (!next.remove(o.value)) next.add(o.value);
                onChanged(next);
              },
            ),
        ],
      ),
    );
  }
}

/// A checkbox filter framed like a select ("Today", "Flagged only").
class DashFilterToggle extends StatelessWidget {
  const DashFilterToggle({
    required this.label,
    required this.value,
    required this.onChanged,
    super.key,
  });
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) =>
      DashCheckChip(label: label, value: value, onChanged: onChanged);
}

/// The period filter: [DashDateRangePicker] in a filter row.
typedef DashDateRangeFilter = DashDateRangePicker;
