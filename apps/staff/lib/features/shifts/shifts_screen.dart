import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge_staff/rust_bridge_staff.dart';

import '../../app/providers.dart';
import '../../format.dart';
import '../../ui/kit.dart';

/// When the employee is expected at work, a week at a time.
///
/// Answers exactly one question — "am I on tomorrow, and from when?" — so it
/// pages by week rather than showing a month grid nobody can read on a phone.
class ShiftsScreen extends ConsumerStatefulWidget {
  const ShiftsScreen({super.key});

  @override
  ConsumerState<ShiftsScreen> createState() => _ShiftsScreenState();
}

class _ShiftsScreenState extends ConsumerState<ShiftsScreen> {
  /// 0 = the current week, +1 = next, −1 = last.
  int _weekOffset = 0;

  DateTime get _weekStart {
    final now = DateTime.now();
    // Saturday-first.
    final offset = (now.weekday + 1) % 7;
    return DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: offset - _weekOffset * 7));
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final colors = context.madarColors;
    final start = _weekStart;
    final range = (
      from: isoDate(start),
      to: isoDate(start.add(const Duration(days: 6))),
    );
    final days = ref.watch(scheduleProvider(range));
    final today = isoDate(DateTime.now());

    return StaffPage(
      title: t('shifts.title'),
      onRefresh: () async => ref.invalidate(scheduleProvider(range)),
      children: [
        MadarCard(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.sm + 2,
            vertical: Space.sm,
          ),
          radius: Radii.sm + 2,
          child: Row(
            children: [
              _PagerButton(
                icon: 'chevron.backward',
                onTap: () => setState(() => _weekOffset--),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    formatRange(range.from, range.to),
                    style: MadarType.body.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              _PagerButton(
                icon: 'chevron.forward',
                onTap: () => setState(() => _weekOffset++),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.md),
        days.when(
          loading: () => const SkeletonList(count: 5),
          error: (e, _) => ErrorState(
            message: '$e',
            retryLabel: t('common.retry'),
            onRetry: () => ref.invalidate(scheduleProvider(range)),
          ),
          data: (rows) => _Week(days: rows, today: today),
        ),
      ],
    );
  }
}

class _PagerButton extends StatelessWidget {
  const _PagerButton({required this.icon, required this.onTap});

  final String icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return TactileScale(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(Radii.xs + 2),
        ),
        alignment: Alignment.center,
        child: MadarIcon(icon, tint: colors.textSecondary),
      ),
    );
  }
}

class _Week extends ConsumerWidget {
  const _Week({required this.days, required this.today});

  final List<ScheduledDayView> days;
  final String today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);

    final working = days.where((d) => d.shifts.isNotEmpty).toList();
    final minutes = working.fold<int>(0, (sum, d) {
      final s = DateTime.tryParse(d.shifts.first.scheduledStartAt);
      final e = DateTime.tryParse(d.shifts.first.scheduledEndAt);
      return sum + (s != null && e != null ? e.difference(s).inMinutes : 0);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: Space.sm),
          child: FieldLabel(
            t('shifts.count', {
              'count': '${working.length}',
              'hours': formatHm(minutes),
            }),
          ),
        ),
        for (final day in days)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: _DayCard(day: day, isToday: day.date == today),
          ),
      ],
    );
  }
}

class _DayCard extends ConsumerWidget {
  const _DayCard({required this.day, required this.isToday});

  final ScheduledDayView day;
  final bool isToday;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final colors = context.madarColors;
    final rest = day.shifts.isEmpty;
    final shift = rest ? null : day.shifts.first;

    return MadarCard(
      padding: const EdgeInsets.all(Space.sm + 2),
      child: Row(
        children: [
          // Date tile.
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: isToday ? colors.accent : colors.surfaceAlt,
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  formatWeekdayShort(day.date),
                  style: MadarType.labelSm.copyWith(
                    color: isToday ? colors.textOnAccent : colors.textMuted,
                  ),
                ),
                Num(
                  dayOfMonth(day.date),
                  style: MadarType.num.copyWith(fontWeight: FontWeight.w700),
                  color: isToday ? colors.textOnAccent : colors.textPrimary,
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: rest
                ? Text(
                    t('shifts.weeklyOff'),
                    style: MadarType.body.copyWith(color: colors.textMuted),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Num(
                        '${formatClock(shift!.scheduledStartAt)}–'
                        '${formatClock(shift.scheduledEndAt)}',
                        style: MadarType.num.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (day.branchName.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            MadarIcon(
                              'mappin.and.ellipse',
                              tint: colors.textMuted,
                              size: IconSize.xs,
                            ),
                            const SizedBox(width: Space.xs),
                            Text(
                              day.branchName,
                              style: MadarType.labelSm.copyWith(
                                color: colors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
          ),
          if (isToday)
            StatusChip(label: t('shifts.today'), tone: ChipTone.accent)
          else if (!rest)
            StatusChip(label: shift!.name),
        ],
      ),
    );
  }
}
