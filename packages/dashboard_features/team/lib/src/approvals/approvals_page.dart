/// `dawam.approvals` page: the port of the web's dawam/approvals-page.tsx
/// `ApprovalsPage`; TEAM-APR rows (+ the area-wide TEAM-ALL rows it
/// carries). Everything that waits on a manager or the owner, in one queue:
/// requests and corrections, salary advances, covers, swaps, open-shift
/// claims, overtime, and pay lines over a manager's limit. Each kind shows
/// (and is asked for) only for someone who may decide it; the server checks
/// again. Refused in-page (`TeamPageGate`) for whoever may decide nothing.
library;

import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart'
    show ProviderBase, ProviderListenable;

import '../attendance/attendance_providers.dart';
import '../employees/employees_providers.dart' show employeesListProvider;
import '../payroll/money_dialogs.dart'
    show showRejectDialog, showReviewAdvanceDialog;
import '../shared/page_gate.dart';
import '../shared/refresh_button.dart';
import '../shared/refresh_toast.dart';
import '../shared/staff_query.dart';
import '../shared/team_format.dart';
import 'approvals_data.dart';
import 'approvals_dialogs.dart';
import 'approvals_providers.dart';

/// The lists' rights (TEAM-APR-001): requests any(`hr.leave.edit`,
/// `hr.attendance.edit`), advances `hr.advances.decide`, swaps and open-shift
/// claims `hr.schedule.edit`, covers `hr.shift_cover.confirm`, overtime
/// `hr.overtime.approve`, pay lines over a limit `hr.payroll.run`.
const List<String> approvalsCaps = [
  Cap.hrLeaveEdit,
  Cap.hrAttendanceEdit,
  Cap.hrAdvancesDecide,
  Cap.hrScheduleEdit,
  Cap.hrShiftCoverConfirm,
  Cap.hrOvertimeApprove,
  Cap.hrPayrollRun,
];

/// `listEmployees({})`: the employees linked to the signed-in user, so a
/// manager is never offered their own request (`useOwnEmployeeIds`).
const _everyone = (status: null, departmentId: null);

abstract final class ApprovalsMetrics {
  /// The loading block (`h-48`).
  static const double skeleton = Space.xxl * 6;
}

/// An approval the approver backed out of: nothing sent, nothing to say.
const Object _backedOut = Object();

class ApprovalsPage extends ConsumerWidget {
  const ApprovalsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => TeamPageGate(
    allowed: (a) => a.canAny(approvalsCaps),
    titleKey: 'dawam.approvals',
    whoKey: 'dawam.approvalsNoAccess',
    child: const ApprovalsQueue(),
  );
}

/// One list the page may read: its label, its state, and its read.
class _Section {
  const _Section(this.labelKey, this.value, this.provider);
  final String labelKey;
  final AsyncValue<Object?> value;
  final ProviderBase<Object?> provider;
}

class ApprovalsQueue extends ConsumerStatefulWidget {
  const ApprovalsQueue({super.key});

  @override
  ConsumerState<ApprovalsQueue> createState() => _ApprovalsQueueState();
}

class _ApprovalsQueueState extends ConsumerState<ApprovalsQueue> {
  ApprovalSection _section = ApprovalSection.all;

  /// Rows ticked for a batch approval.
  final Set<String> _selected = {};

  /// Decided here and not yet gone from the refetched lists: never offered
  /// again (a batch sent one twice, 409).
  final Set<String> _gone = {};

  /// The item being decided ('bulk' for a batch): every button waits.
  String? _busy;

  late final AppLifecycleListener _lifecycle;
  DateTime? _loadedAt;
  List<ProviderBase<Object?>> _reads = const [];

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
  /// asks again; sooner does nothing (TEAM-ALL-009).
  void _onResume() {
    final at = _loadedAt;
    if (at == null || !mounted) return;
    final now = ref.read(clockProvider)();
    if (now.difference(at) < kQueryStaleTime) return;
    _loadedAt = now;
    for (final p in _reads) {
      ref.invalidate(p);
    }
  }

  String _err(Object? e) =>
      approvalsErrorText(e, ref.read(tProvider), ref.read(formatProvider));

  // ── the calls ───────────────────────────────────────────────────────────

  StaffApi get _api => ref.read(apiProvider).staff;

  Future<Object?> _approveCall(Pending i) async {
    final s = i.source;
    return switch (i.type) {
      PendingType.request => _api.decideRequest(
        id: (s as StaffRequest).id,
        body: const RequestDecision(status: 'approved'),
      ),
      PendingType.payLine => _api.decideAdjustment(
        kind: (s as Adjustment).kind,
        id: s.id,
        body: const DecidePay(approve: true),
      ),
      PendingType.swap =>
        _api
            .decideSwap(
              id: (s as Swap).id,
              body: const DecideRoster(approve: true),
            )
            .then((_) => null),
      PendingType.claim => _api.decideClaim(
        id: (s as OpenShift).id,
        body: const DecideRoster(approve: true),
      ),
      PendingType.cover => _api.decideCover(
        id: (s as AttendanceRecord).id,
        body: const Decide(approve: true),
      ),
      PendingType.overtime => _api.decideOvertime(
        id: (s as AttendanceRecord).id,
        body: const Decide(approve: true),
      ),
      // Reviewed in its dialog.
      PendingType.advance => throw StateError('an advance is reviewed'),
    };
  }

  Future<Object?> _rejectCall(Pending i, String? reason) async {
    final s = i.source;
    final r = reason?.trim() ?? '';
    return switch (i.type) {
      PendingType.request => _api.decideRequest(
        id: (s as StaffRequest).id,
        body: RequestDecision(
          status: 'rejected',
          note: r.isEmpty ? null : r,
          explicitNulls: const {'note'},
        ),
      ),
      PendingType.advance => _api.reviewAdvance(
        id: (s as SalaryAdvance).id,
        body: ReviewAdvance(approve: false, reason: r),
      ),
      PendingType.payLine => _api.decideAdjustment(
        kind: (s as Adjustment).kind,
        id: s.id,
        body: DecidePay(approve: false, reason: r),
      ),
      PendingType.swap =>
        _api
            .decideSwap(
              id: (s as Swap).id,
              body: const DecideRoster(approve: false),
            )
            .then((_) => null),
      PendingType.claim => _api.decideClaim(
        id: (s as OpenShift).id,
        body: const DecideRoster(approve: false),
      ),
      PendingType.cover => _api.decideCover(
        id: (s as AttendanceRecord).id,
        body: const Decide(approve: false),
      ),
      PendingType.overtime => _api.decideOvertime(
        id: (s as AttendanceRecord).id,
        body: const Decide(approve: false),
      ),
    };
  }

  /// A claim that makes a long day passes a labour limit: said, never
  /// blocked (RU-13, M26).
  void _warn(Object? out, Translator t) {
    if (out is! ClaimDecision) return;
    for (final w in out.warnings) {
      final key = 'dawam.warn_${w.kind}';
      DashToast.warning(
        context,
        t(
          'dawam.limitWarning',
          args: {
            'limit': t.exists(key) ? t(key) : w.kind,
            'minutes': fmtHours(t.lang, w.minutes),
            'cap': fmtHours(t.lang, w.limitMinutes),
          },
        ),
      );
    }
  }

  /// The one-click runner (`run`): one decision at a time; done → it leaves
  /// the queue at once, "Decision saved", `/staff` refreshed; refused → the
  /// server's words, and a stale refusal refreshes the queue.
  Future<void> _run(String key, Future<Object?> Function() fn) async {
    if (_busy != null) return;
    setState(() => _busy = key);
    final t = ref.read(tProvider);
    final f = ref.read(formatProvider);
    final staff = ref.read(staffRevisionsProvider.notifier);
    try {
      final out = await fn();
      if (identical(out, _backedOut)) return;
      if (mounted) setState(() => _gone.add(key));
      staff.invalidateStaff();
      if (!mounted) return;
      DashToast.success(context, t('staff.decisionSaved'));
      _warn(out, t);
    } on Object catch (e) {
      if (mounted) DashToast.error(context, approvalsErrorText(e, t, f));
      // Decided by someone else first: the queue reads again (H2-B2).
      if (isStaleRefusal(e)) staff.invalidateStaff();
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _approve(Pending i) {
    switch (i.approveMode) {
      case ApproveMode.withPay:
        showApproveWithPayDialog(context, i.source as StaffRequest);
      case ApproveMode.review:
        showReviewAdvanceDialog(context, advance: i.source as SalaryAdvance);
      case ApproveMode.mission:
        _run(i.key, () async {
          final r = i.source as StaffRequest;
          if (!await confirmMissionOverPunches(context, ref, r)) {
            return _backedOut;
          }
          return _approveCall(i);
        });
      case ApproveMode.oneClick:
        _run(i.key, () => _approveCall(i));
    }
  }

  /// Money says why it was refused (D8); a request may say why (its note);
  /// the rest confirms.
  Future<void> _reject(Pending i) async {
    final t = ref.read(tProvider);
    final title = t('dawam.rejectTitle', args: {'name': i.who, 'kind': i.kind});
    final requests = i.section == ApprovalSection.requests;
    if (i.reasonRequired || i.reasonOptional) {
      await showRejectDialog(
        context,
        title: title,
        description: requests
            ? t('staff.rejectRequestHint')
            : t('dawam.rejectWhyHint'),
        optional: i.reasonOptional,
        onReject: (reason) => _rejectCall(i, reason),
      );
      return;
    }
    final ok = await showDashConfirm(
      context,
      title: title,
      // A rejected request leaves the day as if nothing was filed; anything
      // else just isn't paid.
      description: requests
          ? t('staff.rejectRequestHint')
          : t('dawam.rejectHint'),
      confirmLabel: t('common.reject'),
      destructive: true,
    );
    if (ok && mounted) await _run(i.key, () => _rejectCall(i, null));
  }

  /// Approve what was ticked, one by one; each failure is said with its
  /// reason and stays in the queue (TEAM-APR-024).
  Future<void> _approvePicked(List<Pending> picked) async {
    if (_busy != null || picked.isEmpty) return;
    final t = ref.read(tProvider);
    final f = ref.read(formatProvider);
    final n = picked.length;
    final ok = await showDashConfirm(
      context,
      title: t('dawamOps.bulkTitle', count: n),
      description:
          '${picked.map((i) => '${i.who} · ${i.kind}').join(t('common.listSeparator'))}. '
          '${t('dawamOps.bulkHint')}',
      confirmLabel: t('dawamOps.approveCount', count: n),
    );
    if (!ok || !mounted) return;
    setState(() => _busy = 'bulk');
    final staff = ref.read(staffRevisionsProvider.notifier);
    var done = 0;
    final failed = <String>[];
    final approved = <String>[];
    for (final i in picked) {
      try {
        final out = await _approveCall(i);
        done++;
        approved.add(i.key);
        if (mounted) _warn(out, t);
      } on Object catch (e) {
        failed.add('${i.who}: ${approvalsErrorText(e, t, f)}');
      }
    }
    staff.invalidateStaff();
    if (!mounted) return;
    setState(() {
      _busy = null;
      _selected.clear();
      _gone.addAll(approved);
    });
    if (done > 0) {
      DashToast.success(context, t('dawamOps.bulkDone', count: done));
    }
    if (failed.isNotEmpty) {
      final head = t(
        'dawamOps.bulkFailed',
        args: {'first': failed.first},
        count: failed.length,
      );
      if (failed.length > 1) {
        DashToast.show(
          context,
          head,
          kind: DashToastKind.error,
          description: failed.skip(1).join('\n'),
          duration: const Duration(seconds: 10),
        );
      } else {
        DashToast.error(context, head);
      }
    }
  }

  // ── build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final authz = ref.watch(authzProvider);
    final can = (
      requests: authz.canAny(const [Cap.hrLeaveEdit, Cap.hrAttendanceEdit]),
      advances: authz.can(Cap.hrAdvancesDecide),
      roster: authz.can(Cap.hrScheduleEdit),
      covers: authz.can(Cap.hrShiftCoverConfirm),
      overtime: authz.can(Cap.hrOvertimeApprove),
      payLines: authz.can(Cap.hrPayrollRun),
    );
    // The owner (payroll run everywhere) may pass the advance cap (D7).
    final mayPassCap = authz.canEverywhere(Cap.hrPayrollRun);
    final userId = ref.watch(currentSessionProvider.select((s) => s?.user.id));
    final claimsKey = (
      from: teamTodayIsoOf(ref, -366),
      to: teamTodayIsoOf(ref, 366),
    );

    // Only the lists this person may decide are asked for.
    final sections = <String, _Section>{};
    final reads = <ProviderBase<Object?>>[];
    AsyncValue<T>? read<T>(
      bool on,
      String? labelKey,
      ProviderListenable<AsyncValue<T>> p,
    ) {
      if (!on) return null;
      final v = ref.watch(p);
      listenStaffRefreshFailure(ref, context, p);
      final provider = p as ProviderBase<Object?>;
      reads.add(provider);
      if (labelKey != null) {
        sections[labelKey] = _Section(labelKey, v, provider);
      }
      return v;
    }

    final requestsQ = read(
      can.requests,
      'staff.requests',
      approvalsRequestsProvider,
    );
    // A manager's own requests are decided above them (RQ-5).
    final employeesQ = read(
      can.requests && userId != null,
      null,
      employeesListProvider(_everyone),
    );
    final advancesQ = read(
      can.advances,
      'dawam.salaryAdvances',
      approvalsAdvancesProvider,
    );
    final swapsQ = read(can.roster, 'dawam.swap', approvalsSwapsProvider);
    final claimsQ = read(
      can.roster,
      'dawam.openShiftClaim',
      approvalsClaimsProvider(claimsKey),
    );
    final coversQ = read(
      can.covers,
      'dawam.cover',
      approvalsAttendanceProvider(pendingCovers),
    );
    final overtimeQ = read(
      can.overtime,
      'dawam.overtime',
      approvalsAttendanceProvider(pendingOvertime),
    );
    final payLinesQ = read(
      can.payLines,
      'dawam.payLines',
      approvalsPayLinesProvider,
    );
    _reads = reads;
    final all = [for (final s in sections.values) s.value];
    if (all.any((v) => v.hasValue)) _loadedAt ??= ref.read(clockProvider)();

    final own = {
      for (final e in employeesQ?.value ?? const <Employee>[])
        if (userId != null && e.userId == userId) e.id,
    };
    final items = buildPending(
      t: t,
      f: f,
      mayPassCap: mayPassCap,
      own: own,
      requests: requestsQ?.value,
      advances: advancesQ?.value,
      payLines: payLinesQ?.value,
      swaps: swapsQ?.value,
      claims: claimsQ?.value,
      covers: coversQ?.value,
      overtime: overtimeQ?.value,
    );
    final live = [
      for (final i in items)
        if (!_gone.contains(i.key)) i,
    ];
    final shown = inSection(live, _section);
    final batchable = [
      for (final i in shown)
        if (i.batchable) i,
    ];
    final picked = [
      for (final i in batchable)
        if (_selected.contains(i.key)) i,
    ];
    final loading = all.any((v) => v.awaitingFirst);
    final failed = [
      for (final s in sections.values)
        if (s.value.failedFirst) s,
    ];

    String label(ApprovalSection s, String key) =>
        '${t(key)} (${inSection(live, s).length})';

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        // One list failing doesn't hide the others (DSH-1).
        for (final s in failed)
          DashErrorState(
            title: t(
              'dawam.sectionLoadError',
              args: {'section': t(s.labelKey)},
            ),
            message: _err(s.value.error),
            retryLabel: t('common.retry'),
            retrying: s.value.isLoading,
            onRetry: () => ref.invalidate(s.provider),
          ),
        if (loading)
          const DashSkeleton(
            height: ApprovalsMetrics.skeleton,
            radius: Radii.card,
          )
        else if (shown.isEmpty)
          DashEmptyState(
            icon: 'inbox',
            title: t('dawam.nothingWaiting'),
            description: t('dawam.nothingWaitingHint'),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.sm,
            children: [
              if (batchable.length > 1)
                _BatchBar(
                  count: batchable.length,
                  picked: picked.length,
                  busy: _busy,
                  onAll: (on) => setState(() {
                    _selected.clear();
                    if (on) _selected.addAll(batchable.map((i) => i.key));
                  }),
                  onApprove: () => _approvePicked(picked),
                ),
              DashListCard(
                children: [
                  for (final i in shown)
                    PendingRow(
                      key: ValueKey(i.key),
                      item: i,
                      batchMode: batchable.length > 1,
                      selected: _selected.contains(i.key),
                      busy: _busy != null,
                      onSelect: i.batchable
                          ? (on) => setState(
                              () => on
                                  ? _selected.add(i.key)
                                  : _selected.remove(i.key),
                            )
                          : null,
                      onApprove: () => _approve(i),
                      onApproveIntent: _missionIntent(i),
                      onReject: () => _reject(i),
                    ),
                ],
              ),
            ],
          ),
      ],
    );

    return DashPageScaffold(
      title: t('dawam.approvals'),
      subtitle: t('dawam.approvalsSubtitle'),
      // The own-employees read spins it too (the web's `useIsFetching`).
      actions: [
        DawamRefreshButton(busy: anyFetching([...all, ?employeesQ])),
      ],
      filters: Align(
        alignment: AlignmentDirectional.centerStart,
        child: DashSegmentedControl<ApprovalSection>(
          value: _section,
          onChanged: (s) => setState(() => _section = s),
          options: [
            DashOption(
              value: ApprovalSection.all,
              label: label(ApprovalSection.all, 'dawam.all'),
            ),
            DashOption(
              value: ApprovalSection.requests,
              label: label(ApprovalSection.requests, 'staff.requests'),
            ),
            DashOption(
              value: ApprovalSection.money,
              label: label(ApprovalSection.money, 'dawam.money'),
            ),
            DashOption(
              value: ApprovalSection.shifts,
              label: label(ApprovalSection.shifts, 'dawam.shifts'),
            ),
          ],
        ),
      ),
      body: body,
    );
  }

  /// A mission the server sent no worked days for reads them on Approve:
  /// pointing at Approve warms that read.
  VoidCallback? _missionIntent(Pending i) {
    final s = i.source;
    if (i.approveMode != ApproveMode.mission ||
        s is! StaffRequest ||
        s.workedDates != null) {
      return null;
    }
    return () => ref.warm(attendanceListProvider(missionDaysKey(s)));
  }
}

/// The batch bar (TEAM-APR-023): tick all that need no extra answer, then
/// approve them together.
class _BatchBar extends ConsumerWidget {
  const _BatchBar({
    required this.count,
    required this.picked,
    required this.busy,
    required this.onAll,
    required this.onApprove,
  });

  final int count;
  final int picked;
  final String? busy;
  final ValueChanged<bool> onAll;
  final VoidCallback onApprove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final wide = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm;
    final value = picked == count ? true : (picked > 0 ? null : false);
    final words = t('dawamOps.selectAll', count: count);
    return Container(
      padding: EdgeInsetsDirectional.symmetric(
        horizontal: wide ? Space.card : Space.lg,
        vertical: Space.xs,
      ),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: c.hairline),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: Space.sm,
        runSpacing: Space.xs,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DashCheckbox(
                value: value,
                semanticLabel: words,
                onChanged: (on) => onAll(on),
              ),
              Flexible(
                child: GestureDetector(
                  onTap: () => onAll(value != true),
                  child: ExcludeSemantics(
                    child: Text(
                      words,
                      style: DashType.body.copyWith(color: c.textPrimary),
                    ),
                  ),
                ),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: Space.sm,
            children: [
              if (picked == 0)
                Flexible(
                  child: Text(
                    t('dawamOps.pickToBatch'),
                    style: DashType.small.copyWith(color: c.textSecondary),
                  ),
                ),
              DashButton(
                label: picked == 0
                    ? t('dawamOps.approveSelected')
                    : t('dawamOps.approveCount', count: picked),
                icon: 'check',
                size: DashButtonSize.compact,
                loading: busy == 'bulk',
                onPressed: picked == 0 || busy != null ? null : onApprove,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One waiting item (TEAM-APR-007): kind glyph; who, the kind and its
/// markers; what it is and what approving does; Approve and Reject.
class PendingRow extends ConsumerWidget {
  const PendingRow({
    required this.item,
    required this.batchMode,
    required this.selected,
    required this.busy,
    required this.onApprove,
    required this.onReject,
    this.onSelect,
    this.onApproveIntent,
    super.key,
  });

  final Pending item;

  /// The batch bar shows: every row keeps a checkbox column.
  final bool batchMode;
  final bool selected;

  /// A decision is running: every button waits.
  final bool busy;
  final ValueChanged<bool>? onSelect;
  final VoidCallback onApprove;
  final VoidCallback? onApproveIntent;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= DashBreakpoints.sm;
    final phone = DashBreakpoints.isPhoneWidth(width);
    final i = item;
    final tile = Container(
      width: Space.xxl + Space.xs,
      height: Space.xxl + Space.xs,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: DashIcon(i.icon, size: IconSize.sm, color: c.textSecondary),
    );
    final lead = batchMode
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onSelect != null)
                DashCheckbox(
                  value: selected,
                  semanticLabel: t(
                    'dawamOps.selectItem',
                    args: {'name': i.who, 'kind': i.kind},
                  ),
                  onChanged: (on) => onSelect!(on),
                )
              else
                const SizedBox(width: DashMetrics.target),
              tile,
            ],
          )
        : tile;
    final reject = t('common.reject');
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: Space.xs,
      children: [
        if (!i.rejectOnly)
          DashButton(
            label: t('common.approve'),
            icon: 'check',
            variant: DashButtonVariant.outline,
            size: DashButtonSize.compact,
            onPressed: busy ? null : onApprove,
            onIntent: onApproveIntent,
          ),
        if (wide)
          DashButton(
            label: reject,
            icon: 'x',
            variant: DashButtonVariant.ghost,
            size: DashButtonSize.compact,
            onPressed: busy ? null : onReject,
          )
        else
          DashIconButton(
            icon: 'x',
            semanticLabel: reject,
            onPressed: busy ? null : onReject,
          ),
      ],
    );
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            MadarClippedText(
              i.who,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DashType.bodyStrong.copyWith(color: c.textPrimary),
            ),
            DashBadge(i.kind),
            for (final b in i.badges) _badge(context, b),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: DashMetrics.hair),
          child: Text(
            i.detail,
            style: DashType.meta.copyWith(color: c.textSecondary),
          ),
        ),
        if (i.effect != null && i.effect!.isNotEmpty && !i.rejectOnly)
          Padding(
            padding: const EdgeInsets.only(top: DashMetrics.hair),
            child: Text(
              i.effect!,
              style: DashType.small.copyWith(
                color: c.textPrimary.withValues(alpha: 0.8),
              ),
            ),
          ),
        // A phone keeps the words full width; the buttons go under them.
        if (phone)
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: actions,
            ),
          ),
      ],
    );
    return Container(
      constraints: const BoxConstraints(minHeight: DashMetrics.listRow),
      padding: EdgeInsetsDirectional.symmetric(
        horizontal: wide ? Space.card : Space.lg,
        vertical: Space.sm + DashMetrics.hair,
      ),
      child: Row(
        crossAxisAlignment: phone
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        spacing: Space.md,
        children: [
          lead,
          Expanded(child: text),
          if (!phone) actions,
        ],
      ),
    );
  }

  Widget _badge(BuildContext context, PendingBadge b) {
    final c = context.madarColors;
    return switch (b) {
      OutlineBadge() => DashBadge(b.text, outline: true),
      PillBadge(:final tone) => DashStatusPill(
        label: b.text,
        tone: tone,
        small: true,
      ),
      NoteBadge(:final fullLine) => SizedBox(
        width: fullLine ? double.infinity : null,
        child: Text(
          b.text,
          style: DashType.small.copyWith(color: c.textSecondary),
        ),
      ),
    };
  }
}
