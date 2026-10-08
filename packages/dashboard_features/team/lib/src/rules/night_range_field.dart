/// The web kit's `TimeRangeField` (`components/inputs/time-range-field.tsx`,
/// TEAM-ALL-025), which dashboard_kit does not have yet: a start and an end
/// time with the length always in view. An end at or before the start runs
/// past midnight (a "next day" pill, never an error); equal ends are the one
/// refusal; the classic "9 to 5" slip (an implausibly long overnight that
/// moving the end by twelve hours makes a same-day range) offers a one-tap
/// fix. Used here for the night window (TEAM-RUL-034).
library;

import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import '../shared/team_format.dart';

const int _dayMinutes = 1440;

/// Minutes from [start] to [end] (`spanMinutes`): 0 when they are equal, an
/// end before the start runs to the next day; null when either is unread.
int? spanMinutes(String? start, String? end) {
  final a = DashTime.minutesOf(start);
  final b = DashTime.minutesOf(end);
  if (a == null || b == null) return null;
  if (a == b) return 0;
  return b > a ? b - a : b + _dayMinutes - a;
}

/// Whether [start] → [end] finishes on the next day (`endsNextDay`).
bool endsNextDay(String? start, String? end) {
  final a = DashTime.minutesOf(start);
  final b = DashTime.minutesOf(end);
  return a != null && b != null && b < a;
}

/// "9 to 5" typed as 09:00 → 05:00 is a 20-hour overnight: when an overnight
/// range is longer than 14 h and the end twelve hours later gives a same-day
/// range, that end (`suggestEnd`).
String? suggestEnd(String? start, String? end) {
  final a = DashTime.minutesOf(start);
  final b = DashTime.minutesOf(end);
  if (a == null || b == null || b >= a) return null;
  final span = b + _dayMinutes - a;
  if (span <= 14 * 60) return null;
  final alt = b + 12 * 60;
  return alt < _dayMinutes && alt > a ? DashTime.hhmmOf(alt) : null;
}

/// A start–end pair of wall-clock times.
class NightRangeField extends StatelessWidget {
  const NightRangeField({
    required this.start,
    required this.end,
    required this.onChanged,
    required this.startLabel,
    required this.endLabel,
    required this.groupLabel,
    required this.lang,
    required this.sameTimeText,
    required this.endsNextDayText,
    required this.nextDayShortText,
    required this.longOvernightText,
    required this.didYouMeanText,
    this.enabled = true,
    this.startKey,
    this.endKey,
    super.key,
  });

  /// `HH:MM`, or text the field could not read.
  final String start;
  final String end;
  final void Function(String start, String end) onChanged;
  final String startLabel;
  final String endLabel;

  /// Names the pair for a screen reader (`aria-label`).
  final String groupLabel;
  final String lang;
  final String sameTimeText;
  final String endsNextDayText;
  final String nextDayShortText;

  /// "That's {length}, overnight." for a length.
  final String Function(String length) longOvernightText;

  /// "End at {time} instead" for a time.
  final String Function(String time) didYouMeanText;
  final bool enabled;
  final Key? startKey;
  final Key? endKey;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final f = context.dashFormats;
    final span = spanMinutes(start, end);
    final overnight = endsNextDay(start, end);
    final suggestion = suggestEnd(start, end);
    final same = span == 0;
    final startMin = DashTime.minutesOf(start);

    String? describeEnd(String hhmm) {
      if (startMin == null) return null;
      final s = spanMinutes(start, hhmm);
      if (s == null || s == 0) return null;
      final len = formatSpan(s, lang);
      return endsNextDay(start, hhmm) ? '$len · $nextDayShortText' : len;
    }

    Widget labelled(String label, Widget field) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.xs + DashMetrics.hair,
      children: [
        Text(label, style: DashType.bodyMedium.copyWith(color: c.textPrimary)),
        field,
      ],
    );

    final fields = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      spacing: Space.sm,
      children: [
        Expanded(
          child: labelled(
            startLabel,
            DashTimeField(
              key: startKey,
              value: start,
              onChanged: (v) => onChanged(v, end),
              enabled: enabled,
              invalid: same,
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
              key: endKey,
              value: end,
              onChanged: (v) => onChanged(start, v),
              enabled: enabled,
              invalid: same,
              semanticLabel: endLabel,
              describeOption: describeEnd,
              anchorMinutes: startMin == null ? null : startMin + 8 * 60,
            ),
          ),
        ),
      ],
    );

    Widget? summary;
    if (same) {
      summary = Text(
        sameTimeText,
        style: DashType.small.copyWith(color: c.errorText),
      );
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
          if (overnight)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.sm,
                vertical: DashMetrics.hair,
              ),
              decoration: BoxDecoration(
                color: DashTone.info.wash(c),
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: Space.xs,
                children: [
                  DashIcon(
                    'moon-star',
                    size: IconSize.xs - 2,
                    color: DashTone.info.foreground(c),
                  ),
                  Text(
                    endsNextDayText,
                    style: DashType.smallMedium.copyWith(
                      color: DashTone.info.foreground(c),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    return Semantics(
      container: true,
      label: groupLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.xs + DashMetrics.hair,
        children: [
          fields,
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
          if (suggestion != null && enabled)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.sm + 2,
                vertical: Space.xs + 2,
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
                    longOvernightText(formatSpan(span ?? 0, lang)),
                    style: DashType.small.copyWith(
                      color: DashTone.warning.foreground(c),
                    ),
                  ),
                  DashButton(
                    label: didYouMeanText(f.time(suggestion, h12: true)),
                    variant: DashButtonVariant.outline,
                    size: DashButtonSize.compact,
                    onPressed: () => onChanged(start, suggestion),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
