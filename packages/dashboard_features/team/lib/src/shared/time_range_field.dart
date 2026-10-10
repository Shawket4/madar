/// The web kit's `TimeRangeField` (`components/inputs/time-range-field.tsx`,
/// TEAM-ALL-025), which dashboard_kit does not have yet (kit candidate), and
/// the clock arithmetic behind it (`inputs/time.ts`): a start and an end
/// time with the length always in view. An end at or before the start runs
/// past midnight (a "next day" pill, never an error); equal ends are the one
/// refusal; the classic "9 to 5" slip (an implausibly long overnight that
/// moving the end by twelve hours makes a same-day range) offers a one-tap
/// fix. One copy for a work shift's times (TEAM-SHF), a rota day's times
/// (TEAM-SCH) and the rules' night window (TEAM-RUL-034).
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'team_format.dart';

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
  if (b + _dayMinutes - a <= 14 * 60) return null;
  final alt = b + 12 * 60;
  return alt < _dayMinutes && alt > a ? DashTime.hhmmOf(alt) : null;
}

/// A start–end pair of wall-clock times.
class TeamTimeRangeField extends ConsumerWidget {
  const TeamTimeRangeField({
    required this.start,
    required this.end,
    required this.onChanged,
    required this.startLabel,
    required this.endLabel,
    this.groupLabel,
    this.enabled = true,
    this.optional = false,
    this.hideLabels = false,
    this.error,
    this.startKey,
    this.endKey,
    super.key,
  });

  /// `HH:MM`, `''`, or text the field could not read.
  final String start;
  final String end;
  final void Function(String start, String end) onChanged;
  final String startLabel;
  final String endLabel;

  /// Names the pair for a screen reader (`aria-label`).
  final String? groupLabel;
  final bool enabled;

  /// Both ends may be left empty (an × clears each).
  final bool optional;

  /// The row names the pair itself (a weekday): the labels only speak.
  final bool hideLabels;

  /// The form's message under the range.
  final String? error;
  final Key? startKey;
  final Key? endKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final lang = t.lang;
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

    String spoken(String label) =>
        hideLabels && groupLabel != null ? '$groupLabel: $label' : label;

    Widget labelled(String label, Widget field) => hideLabels
        ? field
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: Space.xs + DashMetrics.hair,
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
      final info = DashTone.info.foreground(c);
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
                  DashIcon('moon-star', size: IconSize.xs - 2, color: info),
                  Text(
                    t('inputs.endsNextDay'),
                    style: DashType.smallMedium.copyWith(color: info),
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
          Row(
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
                    clearable: optional,
                    invalid: invalid,
                    semanticLabel: spoken(startLabel),
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
                    clearable: optional,
                    invalid: invalid,
                    semanticLabel: spoken(endLabel),
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
          if (suggestion != null && enabled)
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
