/// The input-kit pieces the shift dialog needs that dashboard_kit does not
/// have yet (kit candidates, TEAM-ALL-025): the web's `TimeRangeField`
/// (`components/inputs/time-range-field.tsx`), `WeekdayPicker`
/// (`components/inputs/weekday-picker.tsx`) and the dialog's collapsible
/// sections (`ui/collapsible`).
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../shared/team_format.dart';
import '../shared/week.dart';
import 'shift_form.dart';

/// A weekday's full name (`weekdayName(dow, lang, "long")`): `Saturday` /
/// `السبت`; [dow] is 0 = Sunday … 6 = Saturday.
String weekdayLong(int dow, String lang) {
  final locale = lang == 'ar' ? 'ar' : 'en_GB';
  // Local symbol data: loads at once, the Future is already complete.
  initializeDateFormatting(locale);
  // 7 January 2024 was a Sunday.
  return DateFormat('EEEE', locale).format(DateTime(2024, 1, 7 + dow));
}

/// Start and end of a shift with its length in view: an end at or before
/// the start runs past midnight ("Ends the next day", never an error), equal
/// ends are the one refusal, and the "9 to 5" slip gets a one-tap fix.
class ShiftTimeRange extends ConsumerWidget {
  const ShiftTimeRange({
    required this.start,
    required this.end,
    required this.onChanged,
    required this.startLabel,
    required this.endLabel,
    this.hideLabels = false,
    this.optional = false,
    this.error,
    super.key,
  });

  /// `HH:MM`, `''`, or text the field could not read.
  final String start;
  final String end;
  final void Function(String start, String end) onChanged;
  final String startLabel;
  final String endLabel;

  /// The row names the pair itself (a weekday): the labels only speak.
  final bool hideLabels;

  /// Both ends may be left empty (an × clears each).
  final bool optional;

  /// The form's message under the range.
  final String? error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final lang = ref.watch(localeProvider);
    final c = context.madarColors;
    final f = context.dashFormats;
    final span = spanMinutes(start, end);
    final same = span == 0;
    final suggestion = suggestEnd(start, end);
    final startMin = DashTime.minutesOf(start);
    final invalid = error != null || same;

    String? describeEnd(String hhmm) {
      if (startMin == null) return null;
      final s = spanMinutes(start, hhmm);
      if (s == null || s == 0) return null;
      final len = formatSpan(s, lang);
      return endsNextDay(start, hhmm)
          ? '$len · ${t('inputs.nextDayShort')}'
          : len;
    }

    Widget labelled(String label, Widget field) => hideLabels
        ? field
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: Space.sm,
            children: [
              Text(
                label,
                style: DashType.bodyMedium.copyWith(color: c.textPrimary),
              ),
              field,
            ],
          );

    Widget? summary;
    if (same) {
      if (error == null) {
        summary = Text(
          t('inputs.sameTime'),
          style: DashType.small.copyWith(color: c.errorText),
        );
      }
    } else if (span != null) {
      summary = Wrap(
        spacing: Space.sm,
        runSpacing: Space.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            formatSpan(span, lang),
            style: DashType.smallMedium.copyWith(color: c.textPrimary),
          ),
          if (endsNextDay(start, end))
            DashStatusPill(
              label: t('inputs.endsNextDay'),
              tone: DashTone.info,
              icon: 'moon-star',
            ),
        ],
      );
    }

    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.xs + DashMetrics.hair,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: Space.sm,
            children: [
              Expanded(
                child: labelled(
                  startLabel,
                  DashTimeField(
                    value: start,
                    onChanged: (v) => onChanged(v, end),
                    clearable: optional,
                    invalid: invalid,
                    semanticLabel: startLabel,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: Space.md),
                child: DashIcon(
                  DashIcon.arrowForward(context),
                  size: IconSize.sm,
                  color: c.textSecondary,
                ),
              ),
              Expanded(
                child: labelled(
                  endLabel,
                  DashTimeField(
                    value: end,
                    onChanged: (v) => onChanged(start, v),
                    clearable: optional,
                    invalid: invalid,
                    semanticLabel: endLabel,
                    describeOption: describeEnd,
                    anchorMinutes: startMin == null ? null : startMin + 8 * 60,
                  ),
                ),
              ),
            ],
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Space.lg + Space.xs),
            child: Semantics(
              liveRegion: true,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: summary ?? const SizedBox.shrink(),
              ),
            ),
          ),
          if (suggestion != null)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.sm + DashMetrics.hair,
                vertical: Space.xs + DashMetrics.hair,
              ),
              decoration: BoxDecoration(
                color: DashTone.warning.wash(c),
                borderRadius: BorderRadius.circular(Radii.xs),
              ),
              child: Wrap(
                spacing: Space.sm,
                runSpacing: Space.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    t(
                      'inputs.longOvernight',
                      args: {'length': formatSpan(span ?? 0, lang)},
                    ),
                    style: DashType.small.copyWith(
                      color: DashTone.warning.foreground(c),
                    ),
                  ),
                  DashButton(
                    label: t(
                      'inputs.didYouMean',
                      args: {'time': f.time(suggestion)},
                    ),
                    variant: DashButtonVariant.outline,
                    size: DashButtonSize.compact,
                    onPressed: () => onChanged(start, suggestion),
                  ),
                ],
              ),
            ),
          if (error != null)
            Semantics(
              liveRegion: true,
              child: Text(
                error!,
                style: DashType.body.copyWith(color: c.errorText),
              ),
            ),
        ],
      ),
    );
  }
}

/// Days of the week as toggle chips, Saturday first (TEAM-ALL-011), with
/// "Every day" / "Clear" shortcuts. Tab lands on the group once; the arrow
/// keys walk the days in reading order (so they flip in Arabic), Home/End
/// jump to the ends.
class ShiftWeekdayPicker extends ConsumerStatefulWidget {
  const ShiftWeekdayPicker({
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
    this.invalid = false,
    super.key,
  });

  /// Postgres DOW numbers.
  final List<int> value;
  final ValueChanged<List<int>> onChanged;

  /// Names the group (`aria-label`).
  final String semanticLabel;
  final bool invalid;

  @override
  ConsumerState<ShiftWeekdayPicker> createState() =>
      _ShiftWeekdayPickerState();
}

class _ShiftWeekdayPickerState extends ConsumerState<ShiftWeekdayPicker> {
  final List<FocusNode> _nodes = [for (var i = 0; i < 7; i++) FocusNode()];
  int _focus = 0;

  @override
  void dispose() {
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _toggle(int dow) {
    final on = widget.value.contains(dow);
    widget.onChanged(
      on
          ? [
              for (final d in widget.value)
                if (d != dow) d,
            ]
          : ([...widget.value, dow]..sort()),
    );
  }

  KeyEventResult _key(KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final fwd = rtl ? LogicalKeyboardKey.arrowLeft : LogicalKeyboardKey.arrowRight;
    final back = rtl ? LogicalKeyboardKey.arrowRight : LogicalKeyboardKey.arrowLeft;
    final k = e.logicalKey;
    final int next;
    if (k == fwd) {
      next = (_focus + 1) % 7;
    } else if (k == back) {
      next = (_focus + 6) % 7;
    } else if (k == LogicalKeyboardKey.home) {
      next = 0;
    } else if (k == LogicalKeyboardKey.end) {
      next = 6;
    } else {
      return KeyEventResult.ignored;
    }
    setState(() => _focus = next);
    _nodes[next].requestFocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final lang = ref.watch(localeProvider);
    final c = context.madarColors;
    final set = widget.value.toSet();
    for (var i = 0; i < 7; i++) {
      _nodes[i].skipTraversal = i != _focus;
    }
    final chips = Semantics(
      container: true,
      label: widget.semanticLabel,
      explicitChildNodes: true,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (_, e) => _key(e),
        child: Container(
          padding: widget.invalid ? const EdgeInsets.all(DashMetrics.hair) : null,
          decoration: widget.invalid
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.xs),
                  border: Border.all(
                    color: c.errorText.withValues(alpha: 0.3),
                    width: DashMetrics.hair,
                  ),
                )
              : null,
          child: Wrap(
            spacing: Space.xs + DashMetrics.hair,
            runSpacing: Space.xs + DashMetrics.hair,
            children: [
              for (final (i, dow) in weekOrder.indexed)
                _DayChip(
                  label: weekdayName(dow, lang),
                  semanticLabel: weekdayLong(dow, lang),
                  on: set.contains(dow),
                  focusNode: _nodes[i],
                  onFocus: () => _focus = i,
                  onTap: () => _toggle(dow),
                ),
            ],
          ),
        ),
      ),
    );
    Widget shortcut(String label, bool enabled, List<int> days) => DashButton(
      label: label,
      variant: DashButtonVariant.ghost,
      size: DashButtonSize.compact,
      onPressed: enabled ? () => widget.onChanged(days) : null,
    );
    return Wrap(
      spacing: Space.md,
      runSpacing: Space.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        chips,
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: Space.xs,
          children: [
            shortcut(t('inputs.everyDay'), set.length < 7, [...allDays]),
            shortcut(t('inputs.clearDays'), set.isNotEmpty, const []),
          ],
        ),
      ],
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.label,
    required this.semanticLabel,
    required this.on,
    required this.focusNode,
    required this.onFocus,
    required this.onTap,
  });

  final String label;
  final String semanticLabel;
  final bool on;
  final FocusNode focusNode;
  final VoidCallback onFocus;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Focus(
      skipTraversal: true,
      canRequestFocus: false,
      onFocusChange: (f) {
        if (f) onFocus();
      },
      child: DashPressable(
        onTap: onTap,
        focusNode: focusNode,
        checked: on,
        semanticLabel: semanticLabel,
        excludeChildSemantics: true,
        builder: (context, s) => AnimatedContainer(
          duration: DashMotion.of(context, DashMotion.fast),
          height: DashMetrics.target,
          constraints: const BoxConstraints(minWidth: DashMetrics.target),
          padding: const EdgeInsets.symmetric(horizontal: Space.sm + 2),
          foregroundDecoration: dashFocusRing(
            context,
            s,
            BorderRadius.circular(Radii.xs),
          ),
          decoration: BoxDecoration(
            color: on ? c.accent : (s.highlighted ? c.hover : c.card),
            borderRadius: BorderRadius.circular(Radii.xs),
            border: Border.all(color: on ? c.accent : c.input),
          ),
          // `widthFactor`: a centred label, yet the chip only as wide as it
          // (a Container's own alignment would stretch it across the Wrap).
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              style: DashType.bodyMedium.copyWith(
                color: on ? c.textOnAccent : c.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A bordered section that opens and closes (the web's `Collapsible`): a
/// title and a quiet line on the trigger, a chevron that turns.
class ShiftCollapsible extends StatelessWidget {
  const ShiftCollapsible({
    required this.title,
    required this.summary,
    required this.open,
    required this.onToggle,
    required this.child,
    super.key,
  });

  final String title;
  final String summary;
  final bool open;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final radius = BorderRadius.circular(Radii.xs);
    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: c.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashPressable(
            onTap: onToggle,
            expanded: open,
            pressScale: false,
            semanticLabel: '$title. $summary',
            excludeChildSemantics: true,
            builder: (context, s) => Container(
              padding: const EdgeInsets.all(Space.md),
              decoration: BoxDecoration(
                color: s.highlighted ? c.hover.withValues(alpha: 0.5) : null,
                borderRadius: radius,
              ),
              foregroundDecoration: dashFocusRing(context, s, radius),
              child: Row(
                spacing: Space.md,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: DashType.bodyMedium.copyWith(
                            color: c.textPrimary,
                          ),
                        ),
                        Text(
                          summary,
                          style: DashType.small.copyWith(
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: DashMotion.of(context, DashMotion.fast),
                    child: DashIcon(
                      'chevron-down',
                      size: IconSize.sm,
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (open)
            Container(
              padding: const EdgeInsets.all(Space.md),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.hairline)),
              ),
              child: child,
            ),
        ],
      ),
    );
  }
}
