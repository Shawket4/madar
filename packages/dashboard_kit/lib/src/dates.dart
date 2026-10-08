import 'dart:math' as math;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'buttons.dart';
import 'foundation/l10n.dart';
import 'foundation/popover.dart';
import 'foundation/press.dart';
import 'foundation/tokens.dart';
import 'select.dart';

/// A calendar day with no time: midnight, local.
DateTime dashDay(DateTime d) => DateTime(d.year, d.month, d.day);

/// `YYYY-MM-DD` for the API.
String dashYmd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// `YYYY-MM-DD` → a day, or null.
DateTime? dashParseYmd(String? s) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s ?? '');
  if (m == null) return null;
  return DateTime(
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
  );
}

/// Columns before the 1st of a month in a week that starts on Saturday.
int dashDaysIntoWeek(DateTime firstOfMonth) =>
    (firstOfMonth.weekday - DateTime.saturday) % 7;

/// One month of days on the app's calendar: Saturday first, today ringed,
/// the chosen day (or the ends of a range) inked, the days between washed.
class DashCalendar extends StatelessWidget {
  const DashCalendar({
    required this.month,
    required this.today,
    required this.onPick,
    this.selected,
    this.rangeFrom,
    this.rangeTo,
    this.onHover,
    this.disableFuture = false,
    this.disablePast = false,
    super.key,
  });

  /// Any day in the month shown.
  final DateTime month;
  final DateTime today;
  final ValueChanged<DateTime> onPick;
  final DateTime? selected;
  final DateTime? rangeFrom;

  /// The range's end (or the hovered day while picking it).
  final DateTime? rangeTo;
  final ValueChanged<DateTime?>? onHover;
  final bool disableFuture;
  final bool disablePast;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final f = context.dashFormats;
    final first = DateTime(month.year, month.month);
    final days = DateTime(month.year, month.month + 1, 0).day;
    final lead = dashDaysIntoWeek(first);
    final cells = <DateTime?>[
      for (var i = 0; i < lead; i++) null,
      for (var d = 1; d <= days; d++) DateTime(month.year, month.month, d),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    final t0 = dashDay(today);
    final lo = rangeFrom != null && rangeTo != null
        ? (rangeFrom!.isBefore(rangeTo!) ? rangeFrom : rangeTo)
        : null;
    final hi = rangeFrom != null && rangeTo != null
        ? (rangeFrom!.isBefore(rangeTo!) ? rangeTo : rangeFrom)
        : null;
    final names = f.weekdaysShort();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            for (final n in names)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.xs),
                  child: Text(
                    n,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: DashType.smallStrong.copyWith(
                      color: c.textSecondary,
                    ),
                  ),
                ),
              ),
          ],
        ),
        for (var r = 0; r < cells.length ~/ 7; r++)
          Row(
            children: [
              for (var i = r * 7; i < r * 7 + 7; i++)
                Expanded(
                  child: cells[i] == null
                      ? const SizedBox(height: DashMetrics.target - Space.xs)
                      : _DayCell(
                          day: cells[i]!,
                          today: cells[i] == t0,
                          disabled:
                              (disableFuture && cells[i]!.isAfter(t0)) ||
                              (disablePast && cells[i]!.isBefore(t0)),
                          selected:
                              cells[i] == selected ||
                              (rangeFrom != null && cells[i] == rangeFrom) ||
                              (rangeTo != null &&
                                  rangeFrom != null &&
                                  cells[i] == rangeTo),
                          inRange:
                              lo != null &&
                              cells[i]!.isAfter(lo) &&
                              cells[i]!.isBefore(hi!),
                          rangeStart: lo != null && lo != hi && cells[i] == lo,
                          rangeEnd: hi != null && lo != hi && cells[i] == hi,
                          onPick: onPick,
                          onHover: onHover,
                        ),
                ),
            ],
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.today,
    required this.disabled,
    required this.selected,
    required this.inRange,
    required this.rangeStart,
    required this.rangeEnd,
    required this.onPick,
    required this.onHover,
  });

  final DateTime day;
  final bool today;
  final bool disabled;
  final bool selected;
  final bool inRange;
  final bool rangeStart;
  final bool rangeEnd;
  final ValueChanged<DateTime> onPick;
  final ValueChanged<DateTime?>? onHover;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final f = context.dashFormats;
    final wash = c.accent.withValues(alpha: 0.1);
    const disc = DashMetrics.target - Space.md;
    return MouseRegion(
      onEnter: disabled || onHover == null ? null : (_) => onHover!(day),
      onExit: onHover == null ? null : (_) => onHover!(null),
      child: Container(
        height: DashMetrics.target - Space.xs,
        decoration: BoxDecoration(
          color: inRange || rangeStart || rangeEnd ? wash : null,
          borderRadius: BorderRadiusDirectional.horizontal(
            start: rangeStart ? const Radius.circular(Radii.pill) : Radius.zero,
            end: rangeEnd ? const Radius.circular(Radii.pill) : Radius.zero,
          ),
        ),
        alignment: Alignment.center,
        child: DashPressable(
          onTap: disabled ? null : () => onPick(day),
          enabled: !disabled,
          selected: selected,
          pressScale: false,
          semanticLabel: f.date(day),
          excludeChildSemantics: true,
          builder: (context, s) => Container(
            width: disc,
            height: disc,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected
                  ? c.accent
                  : s.hovered && !disabled
                  ? c.muted
                  : null,
              border: today && !selected ? Border.all(color: c.accent) : null,
            ),
            child: Text(
              '${day.day}',
              style: DashType.smallMedium.copyWith(
                color: disabled
                    ? c.textMuted.withValues(alpha: 0.4)
                    : selected
                    ? c.textOnAccent
                    : c.textPrimary,
                fontWeight: selected ? FontWeight.w600 : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The month bar over a calendar: previous · "October 2026" · next.
class DashMonthBar extends StatelessWidget {
  const DashMonthBar({required this.month, required this.onChanged, super.key});
  final DateTime month;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final t = context.dashStrings;
    return Row(
      children: [
        DashIconButton(
          icon: DashIcon.backward(context),
          semanticLabel: t.previous,
          onPressed: () => onChanged(DateTime(month.year, month.month - 1)),
        ),
        Expanded(
          child: Text(
            context.dashFormats.monthYear(month),
            textAlign: TextAlign.center,
            style: DashType.bodyStrong.copyWith(color: c.textPrimary),
          ),
        ),
        DashIconButton(
          icon: DashIcon.forward(context),
          semanticLabel: t.next,
          onPressed: () => onChanged(DateTime(month.year, month.month + 1)),
        ),
      ],
    );
  }
}

/// A single day (the web's `DatePicker` / `DateField`): a trigger with a
/// calendar glyph, a month calendar in a popover (a sheet on a phone),
/// Today in the footer. [warnPast] allows a past day but says so.
class DashDateField extends StatefulWidget {
  const DashDateField({
    required this.value,
    required this.onChanged,
    this.placeholder,
    this.semanticLabel,
    this.today,
    this.disableFuture = false,
    this.disablePast = false,
    this.warnPast = false,
    this.warningText,
    this.invalid = false,
    this.enabled = true,
    super.key,
  });

  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final String? placeholder;
  final String? semanticLabel;

  /// The business's today (its timezone); defaults to the device's.
  final DateTime? today;
  final bool disableFuture;
  final bool disablePast;
  final bool warnPast;
  final String? warningText;
  final bool invalid;
  final bool enabled;

  @override
  State<DashDateField> createState() => _DashDateFieldState();
}

class _DashDateFieldState extends State<DashDateField> {
  late DateTime _month = widget.value ?? widget.today ?? DateTime.now();

  DateTime get _today => dashDay(widget.today ?? DateTime.now());

  Widget _panel(BuildContext context, void Function(DateTime) apply) {
    final c = context.madarColors;
    final t = context.dashStrings;
    return StatefulBuilder(
      builder: (context, inner) => Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DashMonthBar(
              month: _month,
              onChanged: (m) => inner(() => _month = m),
            ),
            const SizedBox(height: Space.sm),
            DashCalendar(
              month: _month,
              today: _today,
              selected: widget.value == null ? null : dashDay(widget.value!),
              disableFuture: widget.disableFuture,
              disablePast: widget.disablePast,
              onPick: apply,
            ),
            const SizedBox(height: Space.md),
            Container(
              padding: const EdgeInsets.only(top: Space.sm),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.hairline)),
              ),
              child: Row(
                children: [
                  DashButton(
                    label: t.today,
                    variant: DashButtonVariant.ghost,
                    size: DashButtonSize.compact,
                    onPressed: () => apply(_today),
                  ),
                  const Spacer(),
                  Text(
                    widget.value == null
                        ? t.clickDay
                        : context.dashFormats.date(widget.value),
                    style: DashType.smallMedium.copyWith(
                      color: widget.value == null
                          ? c.textSecondary
                          : c.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final t = context.dashStrings;
    final pastSelected =
        widget.warnPast &&
        widget.value != null &&
        dashDay(widget.value!).isBefore(_today);
    final label = widget.value == null
        ? (widget.placeholder ?? t.pickDate)
        : context.dashFormats.date(widget.value);
    Widget trigger(VoidCallback onTap) => DashSelectTrigger(
      label: label,
      placeholder: widget.value == null,
      leadingIcon: 'calendar',
      chevron: 'chevron-down',
      invalid: widget.invalid,
      enabled: widget.enabled,
      semanticLabel: widget.semanticLabel,
      onTap: () {
        _month = widget.value ?? _today;
        onTap();
      },
    );
    final phone = DashBreakpoints.isPhone(context);
    final field = phone
        ? trigger(
            () => showDashPickerSheet<void>(
              context,
              title: widget.semanticLabel ?? t.pickDate,
              builder: (sheet) => _panel(sheet, (d) {
                Navigator.of(sheet).pop();
                widget.onChanged(d);
              }),
            ),
          )
        : DashPopover(
            width: DashMetrics.popover + Space.xxl,
            maxHeight: 440,
            anchor: (context, ctl) => trigger(ctl.toggle),
            content: (context, ctl) => _panel(context, (d) {
              ctl.close();
              widget.onChanged(d);
            }),
          );
    if (!pastSelected) return field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.xs,
      children: [
        field,
        Row(
          spacing: Space.xs,
          children: [
            DashIcon(
              'alert-triangle',
              size: IconSize.xs - DashMetrics.hair,
              color: DashTone.warning.foreground(c),
            ),
            Flexible(
              child: Text(
                widget.warningText ?? t.pastWarning,
                style: DashType.small.copyWith(
                  color: DashTone.warning.foreground(c),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A named period choice for [DashDateRangePicker].
@immutable
class DashPeriodPreset {
  const DashPeriodPreset({required this.value, required this.label});
  final String value;
  final String label;
}

/// The period picker (the web's `DateRangePicker`): preset pills on top, a
/// From/To summary, a range calendar (tap a start, tap an end, hover to
/// preview, the future refused) and Apply. [preset] is `custom` when a hand
/// range is in force.
class DashDateRangePicker extends StatefulWidget {
  const DashDateRangePicker({
    required this.preset,
    required this.presets,
    required this.onSelectPreset,
    required this.onApplyCustom,
    this.from,
    this.to,
    this.today,
    this.align = DashPopoverAlign.end,
    super.key,
  });

  final String preset;
  final List<DashPeriodPreset> presets;
  final DateTime? from;
  final DateTime? to;
  final ValueChanged<String> onSelectPreset;

  /// The hand-picked days (inclusive).
  final void Function(DateTime from, DateTime to) onApplyCustom;
  final DateTime? today;
  final DashPopoverAlign align;

  @override
  State<DashDateRangePicker> createState() => _DashDateRangePickerState();
}

class _DashDateRangePickerState extends State<DashDateRangePicker> {
  DateTime? _from;
  DateTime? _to;
  DateTime? _hover;
  late DateTime _month;

  DateTime get _today => dashDay(widget.today ?? DateTime.now());

  void _seed() {
    _from = widget.from == null ? null : dashDay(widget.from!);
    _to = widget.to == null ? null : dashDay(widget.to!);
    _hover = null;
    _month = _from ?? _today;
  }

  void _pick(DateTime d) {
    if (_from == null || _to != null) {
      _from = d;
      _to = null;
    } else if (!d.isBefore(_from!)) {
      _to = d;
    } else {
      _to = _from;
      _from = d;
    }
  }

  String _label(BuildContext context) {
    final t = context.dashStrings;
    final f = context.dashFormats;
    if (widget.preset != 'custom') {
      for (final p in widget.presets) {
        if (p.value == widget.preset) return p.label;
      }
      return t.custom;
    }
    if (widget.from != null && widget.to != null) {
      return '${f.date(widget.from)} → ${f.date(widget.to)}';
    }
    return t.custom;
  }

  Widget _panel(BuildContext context, VoidCallback close) {
    final c = context.madarColors;
    final t = context.dashStrings;
    final f = context.dashFormats;
    return StatefulBuilder(
      builder: (context, inner) {
        final shownTo = _to ?? _hover;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(Space.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: Space.xs + DashMetrics.hair,
                runSpacing: Space.xs + DashMetrics.hair,
                children: [
                  for (final p in widget.presets)
                    DashButton(
                      label: p.label,
                      size: DashButtonSize.compact,
                      variant: widget.preset == p.value
                          ? DashButtonVariant.primary
                          : DashButtonVariant.outline,
                      onPressed: () {
                        close();
                        widget.onSelectPreset(p.value);
                      },
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.md),
                child: Divider(height: 1, thickness: 1, color: c.hairline),
              ),
              Container(
                padding: const EdgeInsets.all(Space.sm + DashMetrics.hair),
                decoration: BoxDecoration(
                  color: c.muted,
                  borderRadius: BorderRadius.circular(Radii.control),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _End(
                        label: t.from,
                        value: _from == null ? '—' : f.date(_from),
                      ),
                    ),
                    Container(width: 1, height: Space.xl, color: c.input),
                    Expanded(
                      child: _End(
                        label: t.to,
                        value: shownTo == null ? '—' : f.date(shownTo),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Space.md),
              DashMonthBar(
                month: _month,
                onChanged: (m) => inner(() => _month = m),
              ),
              const SizedBox(height: Space.sm),
              DashCalendar(
                month: _month,
                today: _today,
                disableFuture: true,
                rangeFrom: _from,
                rangeTo: shownTo,
                onHover: (d) => inner(() => _hover = d),
                onPick: (d) => inner(() => _pick(d)),
              ),
              const SizedBox(height: Space.md),
              Container(
                padding: const EdgeInsets.only(top: Space.sm),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: c.hairline)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _from == null
                            ? t.clickStart
                            : _to == null
                            ? t.clickEnd
                            : t.rangeSelected,
                        style: DashType.small.copyWith(color: c.textSecondary),
                      ),
                    ),
                    DashButton(
                      label: t.apply,
                      size: DashButtonSize.compact,
                      onPressed: _from == null
                          ? null
                          : () {
                              close();
                              widget.onApplyCustom(_from!, _to ?? _from!);
                            },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.dashStrings;
    Widget trigger(VoidCallback onTap) => DashButton(
      label: _label(context),
      icon: 'calendar',
      variant: DashButtonVariant.outline,
      onPressed: () {
        _seed();
        onTap();
      },
    );
    if (DashBreakpoints.isPhone(context)) {
      return trigger(
        () => showDashPickerSheet<void>(
          context,
          title: t.custom,
          builder: (sheet) => _panel(sheet, () => Navigator.of(sheet).pop()),
        ),
      );
    }
    return DashPopover(
      width: DashMetrics.popover + Space.xxl,
      maxHeight: 640,
      align: widget.align,
      anchor: (context, ctl) => trigger(ctl.toggle),
      content: (context, ctl) => _panel(context, ctl.close),
    );
  }
}

class _End extends StatelessWidget {
  const _End({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: DashType.small.copyWith(color: c.textSecondary)),
        const SizedBox(height: DashMetrics.hair),
        Text(value, style: DashType.smallStrong.copyWith(color: c.textPrimary)),
      ],
    );
  }
}

/// A quick range for [DashDateRangeField].
enum DashQuickRange {
  thisPeriod,
  lastPeriod,
  thisMonth,
  lastMonth,
  thisWeek,
  lastWeek,
}

/// The days a quick range covers (the web's `quickRange`): a pay period
/// starts on [periodStartDay] (1–28); weeks start on Saturday.
({DateTime from, DateTime to}) dashQuickRange(
  DashQuickRange kind, {
  required DateTime today,
  int periodStartDay = 1,
}) {
  final y = today.year;
  final m = today.month;
  switch (kind) {
    case DashQuickRange.thisMonth:
      return (from: DateTime(y, m), to: DateTime(y, m + 1, 0));
    case DashQuickRange.lastMonth:
      return (from: DateTime(y, m - 1), to: DateTime(y, m, 0));
    case DashQuickRange.thisWeek:
    case DashQuickRange.lastWeek:
      final start = dashDay(
        today,
      ).subtract(Duration(days: (today.weekday - DateTime.saturday) % 7));
      final off = kind == DashQuickRange.thisWeek ? 0 : -7;
      final s = DateTime(start.year, start.month, start.day + off);
      return (from: s, to: DateTime(s.year, s.month, s.day + 6));
    case DashQuickRange.thisPeriod:
    case DashQuickRange.lastPeriod:
      final start = math.min(28, math.max(1, periodStartDay));
      var sm = today.day >= start ? m : m - 1;
      if (kind == DashQuickRange.lastPeriod) sm -= 1;
      return (from: DateTime(y, sm, start), to: DateTime(y, sm + 1, start - 1));
  }
}

/// From–to days with one-tap ranges (the web's `DateRangeField`, for
/// forms): an end before the start is said out loud.
class DashDateRangeField extends StatelessWidget {
  const DashDateRangeField({
    required this.from,
    required this.to,
    required this.onChanged,
    this.quick = const [
      DashQuickRange.thisPeriod,
      DashQuickRange.lastPeriod,
      DashQuickRange.thisMonth,
      DashQuickRange.lastMonth,
    ],
    this.periodStartDay = 1,
    this.today,
    this.disableFuture = false,
    this.enabled = true,
    this.errorText,
    this.fromLabel,
    this.toLabel,
    super.key,
  });

  final DateTime? from;
  final DateTime? to;
  final void Function(DateTime? from, DateTime? to) onChanged;
  final List<DashQuickRange> quick;
  final int periodStartDay;
  final DateTime? today;
  final bool disableFuture;
  final bool enabled;
  final String? errorText;
  final String? fromLabel;
  final String? toLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final t = context.dashStrings;
    final now = dashDay(today ?? DateTime.now());
    final backwards = from != null && to != null && to!.isBefore(from!);
    final names = {
      DashQuickRange.thisPeriod: t.thisPeriod,
      DashQuickRange.lastPeriod: t.lastPeriod,
      DashQuickRange.thisMonth: t.thisMonth,
      DashQuickRange.lastMonth: t.lastMonth,
      DashQuickRange.thisWeek: t.thisWeek,
      DashQuickRange.lastWeek: t.lastWeek,
    };
    Widget end(String label, DateTime? v, void Function(DateTime) set) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          spacing: Space.xs + DashMetrics.hair,
          children: [
            Text(
              label,
              style: DashType.bodyMedium.copyWith(color: c.textPrimary),
            ),
            DashDateField(
              value: v,
              today: now,
              semanticLabel: label,
              disableFuture: disableFuture,
              enabled: enabled,
              invalid: backwards || errorText != null,
              onChanged: set,
            ),
          ],
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.sm,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          spacing: Space.sm,
          children: [
            Expanded(
              child: end(
                fromLabel ?? t.rangeFrom,
                from,
                (d) => onChanged(d, to),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(
                bottom: Space.md + DashMetrics.hair,
              ),
              child: DashIcon(
                DashIcon.arrowForward(context),
                size: IconSize.sm,
                color: c.textSecondary,
              ),
            ),
            Expanded(
              child: end(toLabel ?? t.rangeTo, to, (d) => onChanged(from, d)),
            ),
          ],
        ),
        if (quick.isNotEmpty)
          Semantics(
            label: t.quickRanges,
            container: true,
            child: Wrap(
              spacing: Space.xs,
              runSpacing: Space.xs,
              children: [
                for (final k in quick)
                  Builder(
                    builder: (context) {
                      final r = dashQuickRange(
                        k,
                        today: now,
                        periodStartDay: periodStartDay,
                      );
                      final on = from == r.from && to == r.to;
                      return DashChoiceChip(
                        label: names[k]!,
                        selected: on,
                        enabled: enabled,
                        onTap: () => onChanged(r.from, r.to),
                      );
                    },
                  ),
              ],
            ),
          ),
        if (backwards || errorText != null)
          Semantics(
            liveRegion: true,
            child: Text(
              backwards ? t.endsBeforeStart : errorText!,
              style: DashType.small.copyWith(color: c.errorText),
            ),
          ),
      ],
    );
  }
}

/// A small pill that is on or off (a preset, a quick range, a filter chip).
class DashChoiceChip extends StatelessWidget {
  const DashChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
    this.icon,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;
  final String? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return DashPressable(
      onTap: enabled ? onTap : null,
      enabled: enabled,
      selected: selected,
      checked: selected,
      semanticLabel: label,
      excludeChildSemantics: true,
      builder: (context, s) => SizedBox(
        height: DashMetrics.target,
        child: Center(
          widthFactor: 1,
          child: Opacity(
            opacity: enabled ? 1 : 0.5,
            child: Container(
              height: Space.xxl,
              padding: const EdgeInsets.symmetric(
                horizontal: Space.md - DashMetrics.hair,
              ),
              foregroundDecoration: dashFocusRing(
                context,
                s,
                BorderRadius.circular(Radii.pill),
              ),
              decoration: BoxDecoration(
                color: selected
                    ? c.accent.withValues(alpha: 0.08)
                    : s.hovered
                    ? c.hover
                    : c.card,
                borderRadius: BorderRadius.circular(Radii.pill),
                border: Border.all(color: selected ? c.accent : c.hairline),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: Space.xs,
                children: [
                  if (selected)
                    DashIcon(
                      'check',
                      size: IconSize.xs - DashMetrics.hair,
                      color: c.textPrimary,
                    ),
                  if (icon != null)
                    DashIcon(icon!, size: IconSize.xs, color: c.textSecondary),
                  Text(
                    label,
                    style: (selected ? DashType.smallMedium : DashType.small)
                        .copyWith(
                          color: selected ? c.textPrimary : c.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
