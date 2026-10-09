/// `staff.workShifts` page: the port of the web's
/// `staff/work-shifts-page.tsx` `WorkShiftsPage`; TEAM-SHF rows. No in-page
/// guard (TEAM-ALL-007): the reads 403 into each list's error state.
///
/// The blocks of time people are rostered on, and the standing roster that
/// assigns them. Offers only what the server allows: a branch manager edits
/// their branch's blocks but cannot add or remove blocks, and a
/// business-wide block needs the roster right at every branch.
library;

import 'package:collection/collection.dart';
import 'package:dashboard_api/dashboard_api.dart' show Branch, WorkShift;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/attendance_errors.dart';
import '../shared/refresh_button.dart';
import '../shared/refresh_toast.dart';
import '../shared/staff_query.dart';
import '../shared/team_format.dart';
import '../shared/week.dart';
import 'schedule_grid.dart';
import 'shift_dialog.dart';
import 'shift_form.dart';
import 'shifts_providers.dart';

/// First-strong isolate (the web's `<bdi>`).
String _bdi(String s) => '⁨$s⁩';

class WorkShiftsPage extends ConsumerStatefulWidget {
  const WorkShiftsPage({super.key});

  @override
  ConsumerState<WorkShiftsPage> createState() => _WorkShiftsPageState();
}

class _WorkShiftsPageState extends ConsumerState<WorkShiftsPage> {
  late final AppLifecycleListener _lifecycle;
  DateTime? _loadedAt;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// Refetch on focus (`dawamQuery`): back after the reads went stale (30 s)
  /// asks again; sooner does nothing. Dialogs are never refetched this way.
  void _onResume() {
    final at = _loadedAt;
    if (at == null || !mounted) return;
    final now = ref.read(clockProvider)();
    if (now.difference(at) < kQueryStaleTime) return;
    _loadedAt = now;
    ref
      ..invalidate(staffWorkShiftsProvider)
      ..invalidate(staffActiveEmployeesProvider)
      ..invalidate(shiftsRosterProvider);
  }

  void _open({WorkShift? shift}) {
    final authz = ref.read(authzProvider);
    showShiftDialog(
      context,
      shift: shift,
      branches: ref.read(branchesProvider).value ?? const <Branch>[],
      wholeBusiness: authz.canEverywhere(
        shift != null ? Cap.hrScheduleEdit : Cap.hrScheduleCreate,
      ),
    );
  }

  Future<void> _remove(WorkShift shift) async {
    final t = ref.read(tProvider);
    final ok = await showDashConfirm(
      context,
      title: t('staff.deleteShiftTitle', args: {'name': shift.name}),
      description: t('staff.deleteShiftHint'),
      confirmLabel: t('common.delete'),
      cancelLabel: t('common.cancel'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    final api = ref.read(apiProvider);
    final staff = ref.read(staffRevisionsProvider.notifier);
    final f = ref.read(formatProvider);
    try {
      await api.staff.deleteWorkShift(id: shift.id);
      // The Dawam roster lists the blocks too: all of /staff.
      staff.invalidateStaff();
      if (mounted) DashToast.success(context, t('staff.shiftDeleted'));
    } on Object catch (e) {
      if (mounted) DashToast.error(context, attendanceErrorText(e, t, f));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final authz = ref.watch(authzProvider);
    final canCreate = authz.can(Cap.hrScheduleCreate);
    final canDelete = authz.can(Cap.hrScheduleDelete);
    final canEdit = authz.can(Cap.hrScheduleEdit);
    bool canEditShift(WorkShift s) =>
        canEdit &&
        (s.branchId != null ||
            (authz.canEverywhere(Cap.hrScheduleEdit) &&
                (authz.owner || canCreate)));
    bool canDeleteShift(WorkShift s) =>
        canDelete &&
        (s.branchId != null || authz.canEverywhere(Cap.hrScheduleDelete));

    final q = ref.watch(staffWorkShiftsProvider);
    final employeesQ = ref.watch(staffActiveEmployeesProvider);
    final rosterQ = ref.watch(shiftsRosterProvider);
    final branches = ref.watch(branchesProvider).value ?? const <Branch>[];
    listenStaffRefreshFailure(ref, context, staffWorkShiftsProvider);
    if (q.hasValue) _loadedAt ??= ref.read(clockProvider)();
    ref.listen(staffWorkShiftsProvider, (_, next) {
      if (next.hasValue && !next.isLoading) {
        _loadedAt = ref.read(clockProvider)();
      }
    });

    final shifts = q.value ?? const <WorkShift>[];
    final firstLoad = q.isLoading && !q.hasValue;
    final newButton = DashButton(
      key: const ValueKey('shifts-new'),
      label: t('staff.newShift'),
      icon: 'plus',
      onPressed: _open,
    );

    final Widget list;
    if (firstLoad) {
      list = const DashListCard(
        key: ValueKey('shifts-loading'),
        children: [_SkeletonRow(), _SkeletonRow(), _SkeletonRow()],
      );
    } else if (failedEmpty(q)) {
      list = DashErrorState(
        key: const ValueKey('shifts-error'),
        title: t('staff.shiftsLoadError'),
        retryLabel: t('common.retry'),
        retrying: q.isLoading,
        onRetry: () => ref.invalidate(staffWorkShiftsProvider),
      );
    } else if (shifts.isEmpty) {
      list = DashEmptyState(
        key: const ValueKey('shifts-empty'),
        icon: 'clock',
        title: t('staff.noShifts'),
        description: canCreate
            ? t('staff.noShiftsHintV2')
            : t('staff.noShiftsNoAccess'),
        action: canCreate ? newButton : null,
      );
    } else {
      list = DashListCard(
        key: const ValueKey('shifts-list'),
        children: [
          for (final s in shifts)
            _ShiftRow(
              key: ValueKey('shift-${s.id}'),
              shift: s,
              branchName: s.branchId == null
                  ? t('staff.wholeBusiness')
                  : branches.firstWhereOrNull((b) => b.id == s.branchId)?.name ??
                        '',
              onEdit: canEditShift(s) ? () => _open(shift: s) : null,
              onDelete: canDeleteShift(s) ? () => _remove(s) : null,
            ),
        ],
      );
    }

    return DashPageScaffold(
      title: t('staff.workShifts'),
      subtitle: t('staff.workShiftsSubtitle'),
      actions: [
        DawamRefreshButton(
          key: const ValueKey('shifts-refresh'),
          busy: anyFetching([q, employeesQ, rosterQ]),
        ),
        if (canCreate) newButton,
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.xl,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.md,
            children: [
              DashSectionHeader(
                title: t('staff.shiftsSection'),
                count: firstLoad || failedEmpty(q) ? null : shifts.length,
              ),
              list,
            ],
          ),
          ScheduleGrid(shifts: shifts, shiftsLoading: firstLoad),
        ],
      ),
    );
  }
}

/// One block (TEAM-SHF-006/007): Moon for a night, else Clock; its times,
/// length, next day, grace, overtime, branch, days and own-time days; an
/// over-cap warning and an Inactive pill; Edit and Delete as allowed.
class _ShiftRow extends ConsumerWidget {
  const _ShiftRow({
    required this.shift,
    required this.branchName,
    required this.onEdit,
    required this.onDelete,
    super.key,
  });

  final WorkShift shift;
  final String branchName;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final lang = ref.watch(localeProvider);
    final c = context.madarColors;
    final s = shift;
    final span = spanMinutes(s.startTime, s.endTime);
    final ownTimes = s.dayTimes?.length ?? 0;
    final meta = [
      '${_bdi('${f.fmtWireTime(s.startTime)} – ${f.fmtWireTime(s.endTime)}')}'
          '${span == null || span == 0 ? '' : ' (${formatSpan(span, lang)})'}',
      if (s.crossesMidnight || endsNextDay(s.startTime, s.endTime))
        t('inputs.endsNextDay'),
      t('staff.graceBadge', args: {'n': s.graceMinutes}),
      t('staff.otBadge', args: {'n': jsFigure(s.overtimeMultiplier)}),
      branchName,
      summarizeDays(
        s.validDays,
        lang,
        t('staff.everyDay'),
        t('inputs.noDays'),
      ),
      if (ownTimes > 0) t('staff.ownTimesOn', args: {'n': ownTimes}),
    ].join(' · ');
    return DashListRow(
      title: s.name,
      icon: s.crossesMidnight ? 'moon' : 'clock',
      meta: meta,
      enabled: s.isActive,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: Space.xs,
        children: [
          if (s.overPresenceCap ?? false)
            DashStatusPill(
              label: t('staff.overCapShort'),
              tone: DashTone.warning,
              icon: 'triangle-alert',
            ),
          if (!s.isActive) DashStatusPill(label: t('staff.inactive')),
          if (onEdit != null)
            DashIconButton(
              key: ValueKey('shift-edit-${s.id}'),
              icon: 'pencil',
              semanticLabel: t('common.edit'),
              onPressed: onEdit,
            ),
          if (onDelete != null)
            DashIconButton(
              key: ValueKey('shift-delete-${s.id}'),
              icon: 'trash-2',
              semanticLabel: t('staff.deleteShift'),
              color: c.danger,
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}

/// A loading row: a glyph tile and two lines.
class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: DashMetrics.listRow),
    padding: const EdgeInsets.symmetric(
      horizontal: Space.card,
      vertical: Space.sm + DashMetrics.hair,
    ),
    child: Row(
      spacing: Space.md,
      children: [
        const DashSkeleton(
          width: Space.xxl + Space.xs,
          height: Space.xxl + Space.xs,
          radius: Radii.sm,
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.xs + DashMetrics.hair,
              children: [
                DashSkeleton(width: box.maxWidth / 4, height: Space.md + 2),
                DashSkeleton(width: box.maxWidth / 3, height: Space.md),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
