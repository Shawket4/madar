/// `/staff/team`: the port of the web's `dawam/team-page.tsx` `TeamPage`
/// (TEAM-TEM rows). Who is in, late, absent or on leave right now at my
/// branches, the flags the location pings raised with what a manager can do
/// about each, and punching for someone whose phone died. Where `/` sends a
/// Dawam-only org.
library;

import 'dart:async';

import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../employees/add_employee_dialog.dart';
import '../employees/employees_providers.dart';
import '../employees/import_people_dialog.dart';
import '../payroll/money_dialogs.dart';
import '../payroll/payroll_data.dart';
import '../shared/attendance_errors.dart';
import '../shared/page_gate.dart';
import '../shared/refresh_button.dart';
import '../shared/refresh_toast.dart';
import '../shared/rules_banner.dart';
import '../shared/setup_data.dart';
import '../shared/staff_query.dart';
import '../shared/team_format.dart';
import '../shared/team_util.dart';
import 'team_board_data.dart';
import 'team_board_dialogs.dart';
import 'team_board_providers.dart';

abstract final class TeamBoardMetrics {
  /// The flags' loading block (`h-24`).
  static const double flagsSkeleton = Space.xxl * 3;

  /// The team's loading block (`h-48`).
  static const double teamSkeleton = Space.xxl * 6;

  /// How often the presence is asked again while the page is open.
  static const Duration poll = Duration(seconds: 60);
}

class TeamBoardPage extends ConsumerWidget {
  const TeamBoardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => TeamPageGate(
    allowed: (a) => a.can(Cap.hrAttendanceRead),
    titleKey: 'dawam.team',
    whoKey: 'dawam.teamNoAccess',
    child: const TeamBoard(),
  );
}

class TeamBoard extends ConsumerStatefulWidget {
  const TeamBoard({super.key});

  @override
  ConsumerState<TeamBoard> createState() => _TeamBoardState();
}

class _TeamBoardState extends ConsumerState<TeamBoard> {
  late final AppLifecycleListener _lifecycle;
  late final Timer _poll;
  DateTime? _loadedAt;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    _poll = Timer.periodic(TeamBoardMetrics.poll, (_) => _onPoll());
  }

  @override
  void dispose() {
    _poll.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  String? get _branch => ref.read(currentScopeProvider).branchId;

  bool get _canRead => ref.read(authzProvider).can(Cap.hrAttendanceRead);

  /// The 60 s poll (`refetchInterval`), never while the app is hidden.
  void _onPoll() {
    final life = WidgetsBinding.instance.lifecycleState;
    if (!mounted || !_canRead) return;
    if (life != null && life != AppLifecycleState.resumed) return;
    ref.invalidate(teamPresenceProvider(_branch));
  }

  /// Refetch on focus (`dawamQuery`): back after the reads went stale (30 s)
  /// asks the presence, the flags and the banner's checklist again.
  void _onResume() {
    final at = _loadedAt;
    if (at == null || !mounted || !_canRead) return;
    final now = ref.read(clockProvider)();
    if (now.difference(at) < kQueryStaleTime) return;
    _loadedAt = now;
    ref
      ..invalidate(teamPresenceProvider(_branch))
      ..invalidate(teamFlagsProvider(_branch))
      ..invalidate(staffActiveEmployeesProvider)
      ..invalidate(staffWorkShiftsProvider)
      ..invalidate(staffAttendanceSettingsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final authz = ref.watch(authzProvider);
    final branch = ref.watch(currentScopeProvider.select((s) => s.branchId));
    final canRead = authz.can(Cap.hrAttendanceRead);
    final canPunch = authz.can(Cap.hrAttendancePunchOthers);
    final canResolve = authz.can(Cap.hrAttendanceEdit);
    final canCreate = authz.can(Cap.hrStaffCreate);
    // Money a branch manager handles from here, without the Payroll page.
    final canPayLine = authz.canAny(const [
      Cap.hrAdjustmentsCreate,
      Cap.hrDeductionsCreate,
    ]);
    final canExpense = authz.can(Cap.hrExpenseAdvancesLog);

    // Until the person's rights are known nothing is asked (`enabled`).
    final presenceQ = canRead
        ? ref.watch(teamPresenceProvider(branch))
        : const AsyncLoading<TeamPresence>();
    final flagsQ = canRead
        ? ref.watch(teamFlagsProvider(branch))
        : const AsyncLoading<List<AttendanceFlag>>();
    if (canRead) {
      listenStaffRefreshFailure(ref, context, teamPresenceProvider(branch));
      listenStaffRefreshFailure(ref, context, teamFlagsProvider(branch));
    }
    if (presenceQ.hasValue || flagsQ.hasValue) {
      _loadedAt ??= ref.read(clockProvider)();
    }
    final p = presenceQ.value;
    final today = p?.businessDate;
    // Today's records say whose shift a colleague is covering.
    final todayQ = canPunch && today != null
        ? ref.watch(teamTodayRecordsProvider((day: today, branchId: branch)))
        : null;
    final todayRecords = todayQ?.value ?? const <AttendanceRecord>[];
    // Today is in an approved or paid month: no punch is offered.
    final monthClosed = todayRecords.any((r) => r.monthClosed ?? false);
    final flags = [
      for (final f in flagsQ.value ?? const <AttendanceFlag>[])
        if (f.resolution == null) f,
    ];

    final actions = <Widget>[
      // The banner's checklist is under `/staff` too: it spins the button.
      DawamRefreshButton(
        busy: anyFetching([
          presenceQ,
          flagsQ,
          ?todayQ,
          ref.watch(setupActiveEmployeesProvider),
          ref.watch(setupWorkShiftsProvider),
          ref.watch(setupAttendanceSettingsProvider),
        ]),
      ),
      if (canPayLine)
        DashButton(
          label: t('dawam.addPayLineHere'),
          icon: 'receipt-text',
          variant: DashButtonVariant.outline,
          onIntent: () => ref
            ..warm(payrollCurrentProvider)
            ..warm(setupActiveEmployeesProvider),
          onPressed: () => showAdjustmentDialog(context),
        ),
      if (canExpense)
        DashButton(
          label: t('dawam.logExpense'),
          icon: 'wallet',
          variant: DashButtonVariant.outline,
          onIntent: () => ref.warm(setupActiveEmployeesProvider),
          onPressed: () => showExpenseAdvanceDialog(context),
        ),
      if (canCreate)
        DashButton(
          label: t('dawam.importTitle'),
          icon: 'file-spreadsheet',
          variant: DashButtonVariant.outline,
          onPressed: () => showImportPeopleDialog(context),
        ),
      if (canCreate)
        DashButton(
          label: t('dawam.addEmployee'),
          icon: 'user-round-plus',
          onIntent: () => ref.warm(linkableUsersProvider),
          onPressed: () => showAddEmployeeDialog(context),
        ),
    ];
    return DashPageScaffold(
      title: t('dawam.team'),
      subtitle: t('dawam.teamSubtitle'),
      actions: actions,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          const RulesFirstBanner(),
          _StatCards(
            presence: presenceQ,
            flags: flagsQ,
            openFlags: flags.length,
          ),
          _Section(
            title: t('dawam.flags'),
            children: [
              _FlagsList(
                read: flagsQ,
                flags: flags,
                canResolve: canResolve,
                onRetry: () => ref.invalidate(teamFlagsProvider(branch)),
              ),
            ],
          ),
          _Section(
            title: today == null
                ? t('dawam.rightNow')
                : '${t('dawam.rightNow')} · ${ltr(today)}',
            children: [
              if (canPunch && monthClosed)
                Text(
                  t('dawam.todayMonthClosed'),
                  style: DashType.body.copyWith(
                    color: context.madarColors.textSecondary,
                  ),
                ),
              _PresenceList(
                read: presenceQ,
                today: today,
                todayRecords: todayRecords,
                canPunch: canPunch && !monthClosed,
                onRetry: () => ref.invalidate(teamPresenceProvider(branch)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A titled section (`<h2 class="text-sm font-semibold text-muted-…">`).
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: Space.md,
    children: [
      Semantics(
        header: true,
        child: Text(
          title,
          style: DashType.bodyStrong.copyWith(
            color: context.madarColors.textSecondary,
          ),
        ),
      ),
      ...children,
    ],
  );
}

/// TEAM-TEM-008: In / Late / Absent / Open flags, 2×2 on a phone and 4 in a
/// row from `lg`. A failed load has no counts: a dash, never a reassuring 0.
class _StatCards extends ConsumerWidget {
  const _StatCards({
    required this.presence,
    required this.flags,
    required this.openFlags,
  });

  final AsyncValue<TeamPresence> presence;
  final AsyncValue<List<AttendanceFlag>> flags;
  final int openFlags;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final p = presence.value;
    final cols = MediaQuery.sizeOf(context).width >= DashBreakpoints.lg ? 4 : 2;
    final noFlags = flags.failedFirst;
    final cards = [
      (
        t('dawam.stateIn'),
        p?.present,
        'users-round',
        DashTone.success,
        presence,
      ),
      (t('dawam.stateLate'), p?.late_, 'clock-3', DashTone.warning, presence),
      (
        t('dawam.stateAbsent'),
        p?.absent,
        'circle-alert',
        DashTone.danger,
        presence,
      ),
      (
        t('dawam.openFlags'),
        noFlags ? null : openFlags,
        'shield-alert',
        DashTone.neutral,
        flags,
      ),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final w = (box.maxWidth - Space.md * (cols - 1)) / cols;
        return Wrap(
          spacing: Space.md,
          runSpacing: Space.md,
          children: [
            for (final (label, n, icon, tone, read) in cards)
              SizedBox(
                width: w,
                child: DashStatCard(
                  label: label,
                  icon: icon,
                  tone: tone,
                  format: DashStatFormat.number,
                  loading: read.awaitingFirst,
                  value: n,
                  valueText: n == null ? '—' : null,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// TEAM-TEM-009…011: the open flags, each a row a manager opens to act on.
class _FlagsList extends ConsumerWidget {
  const _FlagsList({
    required this.read,
    required this.flags,
    required this.canResolve,
    required this.onRetry,
  });

  final AsyncValue<List<AttendanceFlag>> read;
  final List<AttendanceFlag> flags;
  final bool canResolve;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    if (read.failedFirst) {
      return DashErrorState(
        title: t('dawam.flagsLoadError'),
        message: attendanceErrorText(read.error, t, f),
        retryLabel: t('common.retry'),
        retrying: read.isLoading,
        onRetry: onRetry,
      );
    }
    if (read.awaitingFirst || !read.hasValue) {
      return const DashSkeleton(
        height: TeamBoardMetrics.flagsSkeleton,
        radius: Radii.card,
      );
    }
    if (flags.isEmpty) {
      return DashEmptyState(
        icon: 'shield-alert',
        title: t('dawam.noFlags'),
        description: t('dawam.noFlagsHint'),
      );
    }
    final hasUser = ref.watch(
      currentSessionProvider.select((s) => s?.user.id != null),
    );
    return DashListCard(
      children: [
        for (final flag in flags)
          DashListRow(
            key: ValueKey(flag.id),
            icon: flagMeta(flag.kind).icon,
            variant: DashListRowVariant.nav,
            title: '${flag.employeeName} · ${t(flagMeta(flag.kind).key)}',
            meta: [
              f.fmtDateTime(flag.detectedAt),
              if (flag.minutesAway != 0)
                t('dawam.minutesAway', args: {'m': flag.minutesAway}),
            ].join(' · '),
            onTap: canResolve ? () => showFlagDialog(context, flag) : null,
            // The dialog reads everyone to tell the person's own flags.
            onIntent: canResolve && hasUser
                ? () => ref.warm(employeesListProvider(teamEveryone))
                : null,
          ),
      ],
    );
  }
}

/// TEAM-TEM-023…028: today's people, with a punch for whoever needs one.
class _PresenceList extends ConsumerWidget {
  const _PresenceList({
    required this.read,
    required this.today,
    required this.todayRecords,
    required this.canPunch,
    required this.onRetry,
  });

  final AsyncValue<TeamPresence> read;
  final String? today;
  final List<AttendanceRecord> todayRecords;

  /// The right to punch, and today in an open month.
  final bool canPunch;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    if (read.failedFirst) {
      return DashErrorState(
        title: t('dawam.teamLoadError'),
        message: attendanceErrorText(read.error, t, f),
        retryLabel: t('common.retry'),
        retrying: read.isLoading,
        onRetry: onRetry,
      );
    }
    final rows = read.value?.rows;
    if (read.awaitingFirst || rows == null) {
      return const DashSkeleton(
        height: TeamBoardMetrics.teamSkeleton,
        radius: Radii.card,
      );
    }
    if (!anyoneRostered(rows)) {
      return DashEmptyState(
        icon: 'users-round',
        title: t('dawam.nobodyRostered'),
        description: t('dawam.nobodyRosteredHint'),
      );
    }
    final now = ref.watch(clockProvider)();
    final c = context.madarColors;
    return DashListCard(
      children: [
        for (final r in rows)
          Builder(
            key: ValueKey(r.employeeId),
            builder: (context) {
              final out = punchesOut(r);
              final coverer = !out && today != null
                  ? coveredBy(todayRecords, r.employeeId, today!)
                  : null;
              final trailing = Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: Space.sm,
                runSpacing: Space.xs,
                children: [
                  DashStatusPill(
                    label: t.exists('dawam.state_${r.state}')
                        ? t('dawam.state_${r.state}')
                        : r.state,
                    tone: presenceTone[r.state] ?? DashTone.neutral,
                  ),
                  if (coverer != null)
                    Text(
                      t('dawam.coveredBy', args: {'name': coverer}),
                      style: DashType.small.copyWith(color: c.textSecondary),
                    ),
                  if (canPunch && punchOffered(r, now))
                    DashButton(
                      label: out ? t('dawam.punchOut') : t('dawam.punchIn'),
                      icon: 'log-in',
                      size: DashButtonSize.compact,
                      variant: DashButtonVariant.outline,
                      tooltip: coverer == null
                          ? null
                          : t('dawam.punchCoveredWhy', args: {'name': coverer}),
                      onPressed: coverer != null
                          ? null
                          : () => showPunchDialog(context, r),
                    ),
                ],
              );
              return DashListRow(
                title: r.employeeName,
                meta: [
                  ?r.branchName,
                  if (r.checkInAt != null)
                    t('dawam.inAt', args: {'time': f.fmtTime(r.checkInAt)}),
                  if (r.lateMinutes > 0)
                    t(
                      'dawam.lateBy',
                      args: {'m': fmtMinutes(f, r.lateMinutes)},
                    ),
                ].join(' · '),
                // The pill and the punch wrap under each other on a narrow
                // row instead of squeezing the name out.
                trailing: Flexible(
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: trailing,
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
