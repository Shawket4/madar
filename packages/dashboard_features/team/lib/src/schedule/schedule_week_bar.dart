/// The schedule's week in one place (`dawam/schedule-week-bar.tsx`,
/// TEAM-SCH-006…010, 073): which week is on screen and how far it is from
/// this one, a way back to today, a jump to any date, and the week's state
/// with the one thing to do next (publish a draft).
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/week.dart';

/// The range's minimum width (`min-w-[10.5rem]`).
const double _rangeWidth = 168;

/// The date jump (`w-44`).
const double _dateWidth = 176;

class ScheduleWeekBar extends ConsumerWidget {
  const ScheduleWeekBar({
    required this.week,
    required this.today,
    required this.onWeek,
    required this.onWeekIntent,
    required this.published,
    required this.canPublish,
    required this.publishing,
    required this.ready,
    required this.changedCount,
    required this.onPublish,
    super.key,
  });

  final String week;
  final String today;
  final ValueChanged<String> onWeek;

  /// About to show [week]: warm its reads.
  final ValueChanged<String> onWeekIntent;
  final bool published;
  final bool canPublish;
  final bool publishing;

  /// The week has loaded: publishing an unloaded week is never offered.
  final bool ready;

  /// Days changed since the week was published.
  final int changedCount;
  final VoidCallback onPublish;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final n = weeksFromNow(week, today);
    final when = switch (n) {
      0 => t('dawamOps.thisWeek'),
      1 => t('dawamOps.nextWeek'),
      -1 => t('dawamOps.lastWeek'),
      > 0 => t('dawamOps.inWeeks', count: n, args: {'count': n}),
      _ => t('dawamOps.weeksAgo', count: -n, args: {'count': -n}),
    };
    final hint = published
        ? changedCount > 0
              ? t(
                  'dawamOps.publishedChanged',
                  count: changedCount,
                  args: {'count': changedCount},
                )
              : t('dawamOps.publishedHint')
        : canPublish
        ? t('dawamOps.draftHint')
        : t('dawamOps.draftHintNoRight');

    // The arrows and the range move as one: a wrapped toolbar never splits
    // them (L-12).
    final arrows = Semantics(
      container: true,
      label: t('dawam.week'),
      child: Row(
        key: const Key('schedule-week-group'),
        mainAxisSize: MainAxisSize.min,
        spacing: Space.xs,
        children: [
          DashIconButton(
            icon: DashIcon.backward(context),
            semanticLabel: t('dawam.prevWeek'),
            variant: DashButtonVariant.outline,
            onIntent: () => onWeekIntent(addDays(week, -7)),
            onPressed: () => onWeek(addDays(week, -7)),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: _rangeWidth),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // `<bdi>`: first-strong, so an Arabic range reads RTL.
                Text(
                  '${f.fmtDate(week)} – ${f.fmtDate(addDays(week, 6))}',
                  maxLines: 1,
                  softWrap: false,
                  style: DashType.bodyStrong.copyWith(color: c.textPrimary),
                ),
                Text(
                  when,
                  style: DashType.small.copyWith(color: c.textSecondary),
                ),
              ],
            ),
          ),
          DashIconButton(
            icon: DashIcon.forward(context),
            semanticLabel: t('dawam.nextWeek'),
            variant: DashButtonVariant.outline,
            onIntent: () => onWeekIntent(addDays(week, 7)),
            onPressed: () => onWeek(addDays(week, 7)),
          ),
        ],
      ),
    );

    final state = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: Space.sm,
      children: [
        if (published)
          DashStatusPill(
            label: t('dawam.isPublished'),
            tone: DashTone.success,
            icon: 'calendar-check',
          )
        else
          DashStatusPill(
            label: t('dawam.draft'),
            tone: DashTone.warning,
            icon: 'calendar-clock',
          ),
        if (!published && canPublish)
          DashButton(
            label: t('dawamOps.publishWeek'),
            icon: 'send',
            size: DashButtonSize.compact,
            loading: publishing,
            onPressed: publishing || !ready ? null : onPublish,
          ),
      ],
    );

    return Semantics(
      container: true,
      label: t('dawam.week'),
      explicitChildNodes: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.md,
        ),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: c.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.md - DashMetrics.hair,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: Space.lg,
              runSpacing: Space.md,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: Space.sm,
                  runSpacing: Space.sm,
                  children: [
                    arrows,
                    if (n != 0)
                      DashButton(
                        label: t('dawamOps.backToThisWeek'),
                        variant: DashButtonVariant.ghost,
                        size: DashButtonSize.compact,
                        onIntent: () => onWeekIntent(weekStartOf(today)),
                        onPressed: () => onWeek(weekStartOf(today)),
                      ),
                    // Any week, however far ahead: one pick, not N clicks.
                    SizedBox(
                      width: _dateWidth,
                      child: DashDateField(
                        key: const Key('schedule-go-to-date'),
                        value: null,
                        placeholder: t('dawamOps.goToDate'),
                        semanticLabel: t('dawamOps.goToDate'),
                        today: DateTime.parse(today),
                        onChanged: (d) => onWeek(weekStartOf(isoDate(d))),
                      ),
                    ),
                  ],
                ),
                state,
              ],
            ),
            Container(
              padding: const EdgeInsets.only(top: Space.md - DashMetrics.hair),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.hairline)),
              ),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  hint,
                  style: DashType.body.copyWith(color: c.textSecondary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A picked calendar day as `yyyy-mm-dd`.
String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
