/// The standing roster as a grid (`staff/schedule-grid.tsx` `ScheduleGrid`,
/// TEAM-SHF-025…033): everyone down the side, the week across the top,
/// Saturday first. Each cell is the shift that will actually be scheduled
/// that day: the weekday's own row if there is one, else the every-day row;
/// the difference is shown, because clearing a cell that only inherits does
/// nothing and the grid has to say so.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show Employee, ScheduleAssignment, WorkShift, CreateAssignmentRequest;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/attendance_errors.dart';
import '../shared/refresh_toast.dart';
import '../shared/staff_query.dart';
import '../shared/week.dart';
import 'shifts_providers.dart';

/// One person's standing roster: the every-day row and one per weekday.
typedef RosterRow = ({
  ScheduleAssignment? everyDay,
  List<ScheduleAssignment?> byWeekday,
});

/// `employee_id` → their rows, the newest `effective_from` winning: the
/// list arrives newest first, so the FIRST row seen for a slot is the one in
/// force and later ones are superseded history.
Map<String, RosterRow> rosterOf(Iterable<ScheduleAssignment> rows) {
  final every = <String, ScheduleAssignment>{};
  final days = <String, List<ScheduleAssignment?>>{};
  for (final a in rows) {
    final week = days.putIfAbsent(a.employeeId, () => List.filled(7, null));
    final d = a.dayOfWeek;
    if (d == null) {
      every.putIfAbsent(a.employeeId, () => a);
    } else if (d >= 0 && d <= 6) {
      week[d] ??= a;
    }
  }
  return {
    for (final e in days.entries)
      e.key: (everyDay: every[e.key], byWeekday: e.value),
  };
}

/// The blocks a weekday cell offers (only those that run that day) or, for
/// the every-day cell ([weekday] null), all of [shifts].
List<WorkShift> offeredOn(List<WorkShift> shifts, int? weekday) =>
    weekday == null
    ? shifts
    : [
        for (final s in shifts)
          if (s.validDays.contains(weekday)) s,
      ];

/// "HH:MM–HH:MM": that day's own times, else the block's.
String timesOn(WorkShift s, int? weekday) {
  final own = weekday == null
      ? null
      : s.dayTimes?.where((d) => d.dayOfWeek == weekday).firstOrNull;
  String cut(String v) => v.length >= 5 ? v.substring(0, 5) : v;
  return '${cut(own?.startTime ?? s.startTime)}–${cut(own?.endTime ?? s.endTime)}';
}

/// The grid's own fixed sizes (the web's `min-w-[46rem]`, `max-w-[12rem]`).
abstract final class RosterMetrics {
  static const double tableMin = 736;
  static const double nameMax = 192;
  static const double namePhone = 136;
  static const double row = DashMetrics.target;
  static const double cell = Space.xxl;
}

class ScheduleGrid extends ConsumerStatefulWidget {
  const ScheduleGrid({required this.shifts, required this.shiftsLoading, super.key});

  /// The page's shift list (every block, active or not).
  final List<WorkShift> shifts;

  /// The list's first load is still on its way: the grid waits for it
  /// rather than saying there is nothing to assign.
  final bool shiftsLoading;

  @override
  ConsumerState<ScheduleGrid> createState() => _ScheduleGridState();
}

class _ScheduleGridState extends ConsumerState<ScheduleGrid> {
  String? _busyCell;

  /// Assign or clear one slot. A slot holds one shift, so replacing drops the
  /// existing row first; otherwise both would resolve and the person would
  /// be scheduled twice that day.
  Future<void> _setCell(
    String employeeId,
    int? dayOfWeek,
    ScheduleAssignment? existing,
    String? shiftId,
  ) async {
    final t = ref.read(tProvider);
    final f = ref.read(formatProvider);
    final api = ref.read(apiProvider);
    final staff = ref.read(staffRevisionsProvider.notifier);
    setState(() => _busyCell = '$employeeId:${dayOfWeek ?? 'all'}');
    try {
      if (existing != null) await api.staff.deleteAssignment(id: existing.id);
      if (shiftId != null) {
        await api.staff.createAssignment(
          body: CreateAssignmentRequest(
            employeeId: employeeId,
            workShiftId: shiftId,
            dayOfWeek: dayOfWeek,
            explicitNulls: const {'day_of_week'},
          ),
        );
      }
    } on Object catch (e) {
      if (mounted) DashToast.error(context, attendanceErrorText(e, t, f));
    } finally {
      // Read again whatever happened: a replace whose new shift is refused
      // has already dropped the old row on the server. The Dawam roster
      // shows the pattern too, so all of /staff.
      staff.invalidateStaff();
      if (mounted) setState(() => _busyCell = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final employeesQ = ref.watch(staffActiveEmployeesProvider);
    final rosterQ = ref.watch(shiftsRosterProvider);
    listenStaffRefreshFailure(ref, context, staffActiveEmployeesProvider);
    listenStaffRefreshFailure(ref, context, shiftsRosterProvider);
    final Widget content;
    if (employeesQ.awaitingFirst ||
        rosterQ.awaitingFirst ||
        widget.shiftsLoading) {
      content = Padding(
        key: const ValueKey('roster-loading'),
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          spacing: Space.sm,
          children: [
            for (var i = 0; i < 4; i++)
              const DashSkeleton(height: Space.xxl + Space.xs),
          ],
        ),
      );
    } else if (employeesQ.failedFirst || rosterQ.failedFirst) {
      content = DashErrorState(
        key: const ValueKey('roster-error'),
        framed: false,
        title: t('staff.rosterLoadError'),
        retryLabel: t('common.retry'),
        // Both reads, as the web's Retry does.
        onRetry: () => ref
          ..invalidate(staffActiveEmployeesProvider)
          ..invalidate(shiftsRosterProvider),
      );
    } else {
      final employees = employeesQ.value ?? const <Employee>[];
      final active = [
        for (final s in widget.shifts)
          if (s.isActive) s,
      ];
      if (employees.isEmpty || active.isEmpty) {
        content = Padding(
          padding: const EdgeInsets.all(Space.card),
          child: Text(
            employees.isEmpty
                ? t('staff.noEmployeesYet')
                : t('staff.noShiftsToRoster'),
            style: DashType.body.copyWith(color: c.textSecondary),
          ),
        );
      } else {
        content = _table(
          context,
          t,
          employees,
          active,
          rosterOf(rosterQ.value ?? const []),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        DashSectionHeader(
          title: t('staff.roster'),
          description: t('staff.gridHint'),
        ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(Radii.card),
            border: Border.all(color: c.hairline),
          ),
          child: content,
        ),
      ],
    );
  }

  Widget _table(
    BuildContext context,
    Translator t,
    List<Employee> employees,
    List<WorkShift> active,
    Map<String, RosterRow> roster,
  ) {
    final c = context.madarColors;
    final head = DashType.tableHeader.copyWith(color: c.textSecondary);
    final line = BorderSide(color: c.hairline);
    return LayoutBuilder(
      builder: (context, box) {
        final nameW = DashBreakpoints.isPhone(context)
            ? RosterMetrics.namePhone
            : RosterMetrics.nameMax;
        final cellsW = (box.maxWidth - nameW).clamp(
          RosterMetrics.tableMin - nameW,
          double.infinity,
        );
        final cellW = cellsW / 8;

        Widget headCell(Widget child) => Container(
          width: cellW,
          height: DashMetrics.tableHeader,
          alignment: Alignment.center,
          decoration: BoxDecoration(border: Border(bottom: line)),
          child: child,
        );

        final names = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: DashMetrics.tableHeader,
              alignment: AlignmentDirectional.centerStart,
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: Space.lg,
              ),
              decoration: BoxDecoration(border: Border(bottom: line)),
              child: Text(t('staff.employee'), style: head),
            ),
            for (final (i, e) in employees.indexed)
              Container(
                height: RosterMetrics.row,
                alignment: AlignmentDirectional.centerStart,
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: Space.lg,
                ),
                decoration: BoxDecoration(
                  border: i == 0 ? null : Border(top: line),
                ),
                child: MadarClippedText(
                  e.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                ),
              ),
          ],
        );

        final cells = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                headCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: Space.xs,
                    children: [
                      DashIcon('sun', size: IconSize.xs, color: c.textSecondary),
                      Flexible(
                        child: MadarClippedText(
                          t('staff.everyDay'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: head,
                        ),
                      ),
                    ],
                  ),
                ),
                for (final d in weekOrder)
                  headCell(Text(t(weekdayKeys[d]), style: head)),
              ],
            ),
            for (final (i, e) in employees.indexed)
              _row(i, e, active, roster[e.id], cellW, line),
          ],
        );

        return Row(
          key: const ValueKey('roster-table'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: nameW, child: names),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(width: cellsW, child: cells),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _row(
    int i,
    Employee e,
    List<WorkShift> active,
    RosterRow? entry,
    double cellW,
    BorderSide line,
  ) {
    // A block belongs to its branch: offer this person only their own
    // branches' blocks and the business-wide ones.
    final theirs = [
      for (final s in active)
        if (s.branchId == null || e.branchIds.contains(s.branchId)) s,
    ];
    Widget cell(int? weekday) {
      final own = weekday == null ? entry?.everyDay : entry?.byWeekday[weekday];
      return Container(
        width: cellW,
        height: RosterMetrics.row,
        padding: const EdgeInsets.symmetric(horizontal: Space.xs),
        decoration: BoxDecoration(border: i == 0 ? null : Border(top: line)),
        alignment: Alignment.center,
        child: RosterCell(
          key: ValueKey('roster-${e.id}-${weekday ?? 'all'}'),
          weekday: weekday,
          assignment: own,
          inherited: weekday == null ? null : entry?.everyDay,
          shifts: offeredOn(theirs, weekday),
          busy: _busyCell == '${e.id}:${weekday ?? 'all'}',
          onPick: (shiftId) => _setCell(e.id, weekday, own, shiftId),
        ),
      );
    }

    return Row(
      children: [
        cell(null),
        for (final d in weekOrder) cell(d),
      ],
    );
  }
}

/// One cell: the effective shift's name (its own row filled, an inherited
/// one dashed, none faint and dashed) or "Rest", opening the "Assign shift"
/// menu.
class RosterCell extends ConsumerWidget {
  const RosterCell({
    required this.weekday,
    required this.assignment,
    required this.inherited,
    required this.shifts,
    required this.busy,
    required this.onPick,
    super.key,
  });

  final int? weekday;
  final ScheduleAssignment? assignment;

  /// The every-day row this cell falls back to when it has none of its own.
  final ScheduleAssignment? inherited;

  /// What the menu offers (already filtered to this day).
  final List<WorkShift> shifts;
  final bool busy;

  /// A block's id, or null for a rest day.
  final ValueChanged<String?> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final effective = assignment ?? inherited;
    final label = effective?.workShiftName ?? t('staff.restDay');
    final radius = BorderRadius.circular(Radii.xs - 2);
    return DashPopover(
      width: DashMetrics.menu,
      align: DashPopoverAlign.start,
      anchor: (context, ctl) => DashPressable(
        onTap: busy ? null : ctl.toggle,
        enabled: !busy,
        pressScale: false,
        semanticLabel: label,
        excludeChildSemantics: true,
        builder: (context, s) {
          final own = assignment != null;
          final fg = own
              ? c.textPrimary
              : effective != null
              ? c.textSecondary
              : c.textSecondary.withValues(alpha: 0.6);
          final box = Container(
            height: RosterMetrics.cell,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: Space.sm),
            decoration: BoxDecoration(
              color: s.highlighted
                  ? c.hover
                  : own
                  ? c.muted
                  : null,
              borderRadius: radius,
            ),
            foregroundDecoration: dashFocusRing(context, s, radius),
            child: busy
                ? const SizedBox.square(
                    dimension: IconSize.xs,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : MadarClippedText(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DashType.small.copyWith(
                      color: fg,
                      fontWeight: own ? FontWeight.w500 : null,
                    ),
                  ),
          );
          return SizedBox(
            height: RosterMetrics.row,
            child: Center(
              child: own
                  ? box
                  : CustomPaint(
                      foregroundPainter: _DashedBorder(
                        color: effective != null
                            ? c.input
                            : c.input.withValues(alpha: 0.6),
                        radius: Radii.xs - 2,
                      ),
                      child: box,
                    ),
            ),
          );
        },
      ),
      content: (context, ctl) => _AssignMenu(
        weekday: weekday,
        shifts: shifts,
        canClear: assignment != null,
        onPick: (id) {
          ctl.close();
          onPick(id);
        },
      ),
    );
  }
}

class _AssignMenu extends ConsumerWidget {
  const _AssignMenu({
    required this.weekday,
    required this.shifts,
    required this.canClear,
    required this.onPick,
  });

  final int? weekday;
  final List<WorkShift> shifts;
  final bool canClear;
  final ValueChanged<String?> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    Widget item(
      String label, {
      String? times,
      required VoidCallback? onTap,
      Key? key,
    }) => DashPressable(
      key: key,
      onTap: onTap,
      enabled: onTap != null,
      pressScale: false,
      semanticLabel: times == null ? label : '$label $times',
      excludeChildSemantics: true,
      builder: (context, s) => Container(
        constraints: const BoxConstraints(
          minHeight: DashMetrics.target - Space.xs,
        ),
        padding: const EdgeInsets.symmetric(horizontal: Space.sm),
        decoration: BoxDecoration(
          color: s.highlighted || s.focused ? c.hover : null,
          borderRadius: BorderRadius.circular(Radii.xs),
        ),
        child: Row(
          spacing: Space.md,
          children: [
            Expanded(
              child: MadarClippedText(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashType.body.copyWith(
                  color: onTap == null ? c.disabledText : c.textPrimary,
                ),
              ),
            ),
            if (times != null)
              Text(
                times,
                textDirection: TextDirection.ltr,
                style: DashType.mono.copyWith(
                  fontSize: DashType.small.fontSize,
                  color: c.textSecondary,
                ),
              ),
          ],
        ),
      ),
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Space.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.sm,
              vertical: Space.xs + 2,
            ),
            child: Text(
              t('staff.assignShift'),
              style: DashType.bodyMedium.copyWith(color: c.textPrimary),
            ),
          ),
          for (final s in shifts)
            item(
              s.name,
              key: ValueKey('assign-${s.id}'),
              times: timesOn(s, weekday),
              onTap: () => onPick(s.id),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.xs),
            child: Divider(height: 1, thickness: 1, color: c.hairline),
          ),
          // Clearing a cell that only inherits would silently do nothing.
          item(
            t('staff.clearCell'),
            key: const ValueKey('assign-rest'),
            onTap: canClear ? () => onPick(null) : null,
          ),
        ],
      ),
    );
  }
}

/// A dashed rounded outline (the web's `border-dashed`).
class _DashedBorder extends CustomPainter {
  const _DashedBorder({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ).deflate(0.5),
      );
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 6) {
        canvas.drawPath(m.extractPath(d, d + 3), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) =>
      old.color != color || old.radius != radius;
}
