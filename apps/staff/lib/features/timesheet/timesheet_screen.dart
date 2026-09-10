import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge_staff/rust_bridge_staff.dart';

import '../../app/providers.dart';
import '../../format.dart';
import '../../ui/kit.dart';

/// The employee's own hours, by week or by month.
///
/// The screen's real job is not the total — it is making a WRONG day visible and
/// fixable. A day with a check-in and no check-out reads as red, says what is
/// missing, and offers the one action that fixes it: a correction request, which
/// lands in the manager's approvals queue and, once approved, rewrites the punch
/// and reprices the day.
class TimesheetScreen extends ConsumerStatefulWidget {
  const TimesheetScreen({super.key});

  @override
  ConsumerState<TimesheetScreen> createState() => _TimesheetScreenState();
}

enum _View { week, month }

class _TimesheetScreenState extends ConsumerState<TimesheetScreen> {
  _View _view = _View.week;

  ({String from, String to}) get _range {
    final now = DateTime.now();
    if (_view == _View.week) {
      // Saturday-first, the Egyptian working week.
      final offset = (now.weekday + 1) % 7;
      final start = now.subtract(Duration(days: offset));
      return (
        from: isoDate(start),
        to: isoDate(start.add(const Duration(days: 6))),
      );
    }
    return (
      from: isoDate(DateTime(now.year, now.month)),
      to: isoDate(DateTime(now.year, now.month + 1, 0)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final range = _range;
    final records = ref.watch(attendanceProvider(range));

    return StaffPage(
      title: t('ts.title'),
      onRefresh: () async => ref.invalidate(attendanceProvider(range)),
      children: [
        Segmented<_View>(
          value: _view,
          onChanged: (v) => setState(() => _view = v),
          segments: [
            (value: _View.week, label: t('ts.week')),
            (value: _View.month, label: t('ts.month')),
          ],
        ),
        const SizedBox(height: Space.md),
        records.when(
          loading: () => const SkeletonList(count: 5),
          error: (e, _) => ErrorState(
            message: '$e',
            retryLabel: t('common.retry'),
            onRetry: () => ref.invalidate(attendanceProvider(range)),
          ),
          data: (rows) => _Body(rows: rows, monthly: _view == _View.month),
        ),
      ],
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.rows, required this.monthly});

  final List<AttendanceRecordView> rows;
  final bool monthly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final colors = context.madarColors;

    if (rows.isEmpty) {
      return EmptyState(
        icon: 'clock',
        title: t('attendance.empty'),
        message: t('attendance.emptyHint'),
      );
    }

    final worked = rows.fold<int>(0, (sum, r) => sum + r.workedMinutes);
    final overtime = rows.fold<int>(0, (sum, r) => sum + r.overtimeMinutes);
    final lates = rows.where((r) => r.lateMinutes > 0).length;
    final missing = rows
        .where((r) => r.checkInAt.isNotEmpty && r.checkOutAt.isEmpty)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (missing.isNotEmpty) ...[
          NoticeBanner(
            icon: 'exclamationmark.triangle',
            text: t('ts.missingBanner'),
          ),
          const SizedBox(height: Space.md),
        ],
        if (monthly) ...[
          Row(
            children: [
              Expanded(
                child: StatCard(
                  label: t('ts.days'),
                  value: '${rows.where((r) => r.workedMinutes > 0).length}',
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: StatCard(
                  label: t('ts.hours'),
                  value: formatHm(worked),
                  valueStyle: MadarType.numMd,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Row(
            children: [
              Expanded(
                child: StatCard(
                  label: t('home.overtime'),
                  value: formatHm(overtime, signed: true),
                  valueColor: overtime > 0 ? colors.accent : null,
                  valueStyle: MadarType.numMd,
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: StatCard(
                  label: t('ts.lates'),
                  value: '$lates',
                  valueColor: lates > 0 ? colors.warning : null,
                ),
              ),
            ],
          ),
        ] else
          StaffCard(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.md,
              vertical: Space.sm + 2,
            ),
            child: Row(
              children: [
                Expanded(child: FieldLabel(t('ts.weekTotal'))),
                Num(formatHm(worked), style: MadarType.numMd),
                if (overtime > 0) ...[
                  const SizedBox(width: Space.sm),
                  Num(
                    formatHm(overtime, signed: true),
                    style: MadarType.num,
                    color: colors.accent,
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: Space.md),
        StaffCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++)
                _DayRow(record: rows[i], last: i == rows.length - 1),
            ],
          ),
        ),
        const SizedBox(height: Space.md),
        // The ink footer bar the handoff puts under the week's list.
        StaffCard(
          color: colors.textPrimary,
          padding: const EdgeInsets.symmetric(
            horizontal: Space.lg,
            vertical: Space.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  t('ts.weekTotal'),
                  style: MadarType.labelSm.copyWith(color: colors.bg),
                ),
              ),
              Num(formatHm(worked), style: MadarType.numMd, color: colors.bg),
            ],
          ),
        ),
      ],
    );
  }
}

class _DayRow extends ConsumerWidget {
  const _DayRow({required this.record, required this.last});

  final AttendanceRecordView record;
  final bool last;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final colors = context.madarColors;
    final missingPunch =
        record.checkInAt.isNotEmpty && record.checkOutAt.isEmpty;
    final off = record.status == 'absent' && record.checkInAt.isEmpty;

    return Container(
      decoration: BoxDecoration(
        color: missingPunch
            ? colors.dangerBg
            : off
            ? colors.surfaceAlt
            : null,
        border: last
            ? null
            : Border(bottom: BorderSide(color: colors.borderLight)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm + 1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 74,
                child: Text(
                  formatWeekday(record.businessDate),
                  style: MadarType.bodySm.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: record.checkInAt.isEmpty
                      ? Text(
                          t('ts.off'),
                          style: MadarType.labelSm.copyWith(
                            color: colors.textMuted,
                          ),
                        )
                      : Num(
                          '${formatClock(record.checkInAt)}–'
                          '${record.checkOutAt.isEmpty ? "—" : formatClock(record.checkOutAt)}',
                        ),
                ),
              ),
              SizedBox(
                width: 52,
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Num(
                    record.workedMinutes == 0
                        ? '—'
                        : formatHm(record.workedMinutes),
                    style: MadarType.num.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
          if (record.lateMinutes > 0 ||
              record.overtimeMinutes > 0 ||
              missingPunch) ...[
            const SizedBox(height: Space.xs + 2),
            Wrap(
              spacing: Space.xs + 2,
              runSpacing: Space.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (record.lateMinutes > 0)
                  StatusChip(
                    label: t('ts.lateBy', {'minutes': '${record.lateMinutes}'}),
                    tone: ChipTone.warning,
                  ),
                if (record.overtimeMinutes > 0)
                  StatusChip(
                    label: t('ts.otBy', {
                      'duration': formatHm(
                        record.overtimeMinutes,
                        signed: true,
                      ),
                    }),
                    tone: ChipTone.accent,
                  ),
                if (missingPunch) ...[
                  StatusChip(
                    label: t('ts.missingPunch'),
                    tone: ChipTone.danger,
                  ),
                  _FixButton(record: record),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// "Request a fix" → a `correction` request carrying the time the employee says
/// they actually left. Becomes a pending chip once filed.
class _FixButton extends ConsumerWidget {
  const _FixButton({required this.record});

  final AttendanceRecordView record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final colors = context.madarColors;

    // A correction already filed for this record shows its status instead of
    // the button, so nobody files twice and wonders which one counts.
    final filed = ref
        .watch(requestsProvider)
        .maybeWhen(
          data: (rows) => rows
              .where(
                (r) =>
                    r.kind == 'correction' &&
                    r.onDate == record.businessDate &&
                    (r.status == 'pending' || r.status == 'approved'),
              )
              .firstOrNull,
          orElse: () => null,
        );
    if (filed != null) {
      return StatusChip(
        label: filed.status == 'pending'
            ? t('ts.fixPending')
            : t('req.approved'),
        tone: filed.status == 'pending' ? ChipTone.warning : ChipTone.success,
      );
    }

    return TactileScale(
      onTap: () => _openSheet(context, ref),
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: Space.md),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(Radii.pill),
          border: Border.all(color: colors.border),
        ),
        alignment: Alignment.center,
        child: Text(
          t('ts.requestFix'),
          style: MadarType.labelSm.copyWith(color: colors.textPrimary),
        ),
      ),
    );
  }

  Future<void> _openSheet(BuildContext context, WidgetRef ref) async {
    final t = ref.read(tProvider);
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 17, minute: 0),
      helpText: t('ts.fixTitle'),
    );
    if (picked == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final core = ref.read(coreProvider);
    try {
      await core.bridge.staffCreateRequest(
        kind: 'correction',
        onDate: record.businessDate,
        toTime:
            '${picked.hour.toString().padLeft(2, '0')}:'
            '${picked.minute.toString().padLeft(2, '0')}',
        isHalfDay: false,
        attendanceRecordId: record.id,
        reason: t('ts.missingPunch'),
      );
      ref.invalidate(requestsProvider);
      messenger.showSnackBar(SnackBar(content: Text(t('ts.fixSent'))));
    } on MadarError catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(core.bridge.humanMessage(e))),
      );
    }
  }
}
