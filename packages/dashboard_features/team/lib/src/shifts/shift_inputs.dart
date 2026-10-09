/// The input-kit pieces the shift dialog needs that dashboard_kit does not
/// have yet (kit candidates, TEAM-ALL-025): the web's `WeekdayPicker`
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
