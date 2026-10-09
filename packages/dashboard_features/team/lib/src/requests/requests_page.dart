/// `staff.requests` page: the port of the web's staff/requests-inbox.tsx
/// `RequestsInboxPage`; TEAM-REQ rows (+ the area-wide TEAM-ALL rows it
/// carries). One queue for every kind of request: approving here is what
/// stops the penalty engine from charging that day. No in-page guard
/// (TEAM-ALL-007): without `hr.leave.read` the list says its refusal.
library;

import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../approvals/approvals_data.dart';
import '../approvals/approvals_dialogs.dart';
import '../approvals/approvals_providers.dart';
import '../attendance/attendance_providers.dart';
import '../employees/employees_providers.dart';
import '../shared/refresh_button.dart';
import '../shared/refresh_toast.dart';
import '../shared/staff_query.dart';
import '../shared/team_util.dart';
import 'requests_data.dart';
import 'requests_dialogs.dart';
import 'requests_providers.dart';

/// `listEmployees({})`: names and the caller's own records.
const everyone = (status: null, departmentId: null);

/// The status filter's "All" (`ALL`).
const String _all = '__all__';

class RequestsInboxPage extends ConsumerStatefulWidget {
  const RequestsInboxPage({super.key});

  @override
  ConsumerState<RequestsInboxPage> createState() => _RequestsInboxPageState();
}

class _RequestsInboxPageState extends ConsumerState<RequestsInboxPage> {
  String _status = 'pending';
  String? _kind;

  /// The request being decided in one click: its buttons wait (H2-D8).
  String? _busy;

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

  /// Refetch on focus (`dawamQuery`, TEAM-ALL-009): back after the reads
  /// went stale (30 s) asks again; sooner does nothing.
  void _onResume() {
    final at = _loadedAt;
    if (at == null || !mounted) return;
    final now = ref.read(clockProvider)();
    if (now.difference(at) < kQueryStaleTime) return;
    _loadedAt = now;
    ref
      ..invalidate(requestsReadFor(_key(_status, _kind)))
      ..invalidate(employeesListProvider(everyone));
  }

  RequestsQuery _key(String status, String? kind) =>
      (status: status == _all ? null : status, kind: kind);

  void _warmList(String status, String? kind) =>
      ref.warm(requestsReadFor(_key(status, kind)));

  Future<void> _approve(StaffRequest r) async {
    // Kinds that carry a pay decision get the dialog; the rest are one click.
    if (asksPay.contains(r.kind)) {
      await showApproveWithPayDialog(
        context,
        r,
        source: requestsReadFor(_key(_status, _kind)),
      );
      return;
    }
    if (!await confirmMissionOverPunches(context, ref, r)) return;
    if (!mounted) return;
    if (_busy != null) return;
    setState(() => _busy = r.id);
    final t = ref.read(tProvider);
    final f = ref.read(formatProvider);
    final staff = ref.read(staffRevisionsProvider.notifier);
    try {
      await ref
          .read(apiProvider)
          .staff
          .decideRequest(
            id: r.id,
            body: const RequestDecision(status: 'approved'),
          );
      // The roster's leave, attendance and pay read it too (H2-D9).
      staff.invalidateStaff();
      if (mounted) DashToast.success(context, t('staff.decisionSaved'));
    } on Object catch (e) {
      if (mounted) DashToast.error(context, approvalsErrorText(e, t, f));
      // Decided by someone else first: the list reads again (H2-B2).
      if (isStaleRefusal(e)) staff.invalidateStaff();
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  /// Rejected with an optional reason the requester reads (D8 wording).
  Future<void> _reject(StaffRequest r) {
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider);
    final staff = ref.read(staffRevisionsProvider.notifier);
    return showRejectReasonDialog(
      context,
      title: t(
        'staff.rejectRequestTitle',
        args: {'name': r.employeeName ?? ''},
      ),
      description: t('staff.rejectRequestHint'),
      optional: true,
      onReject: (reason) async {
        try {
          return await api.staff.decideRequest(
            id: r.id,
            body: RequestDecision(
              status: 'rejected',
              note: reason.isEmpty ? null : reason,
              explicitNulls: const {'note'},
            ),
          );
        } on Object catch (e) {
          if (isStaleRefusal(e)) staff.invalidateStaff();
          rethrow;
        }
      },
    );
  }

  /// Pointing at Approve warms what pressing it reads: a mission's worked
  /// days when the server did not name them. The pay dialog reads the
  /// page's own list, already on screen.
  VoidCallback? _approveIntent(StaffRequest r) {
    if (r.kind == 'mission' && r.workedDates == null) {
      return () => ref.warm(attendanceListProvider(missionDaysKey(r)));
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final userId = ref.watch(currentSessionProvider.select((s) => s?.user.id));
    final canFile = ref.watch(
      authzProvider.select((a) => a.can(Cap.hrLeaveCreate)),
    );
    final read = requestsReadFor(_key(_status, _kind));
    final q = ref.watch(read);
    listenStaffRefreshFailure(ref, context, read);
    if (q.hasValue) _loadedAt ??= ref.read(clockProvider)();
    ref.listen(read, (_, next) {
      if (next.hasValue && !next.isLoading) {
        _loadedAt = ref.read(clockProvider)();
      }
    });
    final people = employeesListProvider(everyone);
    final peopleQ = ref.watch(people);
    listenStaffRefreshFailure(ref, context, people);
    final staff = peopleQ.value ?? const <Employee>[];
    final own = {
      for (final e in staff)
        if (userId != null && e.userId == userId) e.id,
    };
    final names = {
      for (final e in staff)
        if (e.userId != null) e.userId!: e.name,
    };

    final Widget body;
    if (q.failedFirst) {
      body = DashErrorState(
        title: t('staff.requestsLoadError'),
        message: approvalsErrorText(q.error, t, ref.watch(formatProvider)),
        retryLabel: t('common.retry'),
        retrying: q.isLoading,
        onRetry: () => ref.invalidate(read),
      );
    } else if (!q.hasValue) {
      body = const RequestsSkeleton();
    } else if (q.value!.isEmpty) {
      body = _status == 'pending' && _kind == null
          ? DashEmptyState(
              icon: 'check',
              title: t('dawamOps.noPendingTitle'),
              description: t('dawamOps.noPendingHint'),
            )
          : DashEmptyState(
              icon: 'calendar-off',
              title: t('staff.noRequestsTitle'),
              description: t('staff.noRequestsHint'),
              action: DashButton(
                label: t('dawamOps.showPending'),
                variant: DashButtonVariant.outline,
                size: DashButtonSize.compact,
                onIntent: () => _warmList('pending', null),
                onPressed: () => setState(() {
                  _status = 'pending';
                  _kind = null;
                }),
              ),
            );
    } else {
      body = DashListCard(
        children: [
          for (final r in q.value!)
            RequestRow(
              request: r,
              mine: isMine(r, own),
              decide: mayDecide(r, own),
              names: names,
              busy: _busy == r.id,
              onApprove: () => _approve(r),
              onApproveIntent: _approveIntent(r),
              onReject: () => _reject(r),
              onCancel: () =>
                  showCancelRequestDialog(context, r, mine: isMine(r, own)),
            ),
        ],
      );
    }

    return DashPageScaffold(
      title: t('staff.requests'),
      subtitle: t('staff.requestsSubtitle'),
      actions: [
        DawamRefreshButton(busy: anyFetching([q, peopleQ])),
        // Filing for someone is hr.leave.create; the server refuses anyone else.
        if (canFile)
          DashButton(
            label: t('staff.newRequest'),
            icon: 'plus',
            onIntent: () => ref.warm(employeesReadFor(activeEmployees)),
            onPressed: () => showNewRequestDialog(context),
          ),
      ],
      filters: Wrap(
        spacing: Space.sm,
        runSpacing: Space.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // The queue first: what waits on a decision is one tap.
          DashSegmentedControl<String>(
            semanticLabel: t('common.status'),
            options: [
              for (final s in const [
                'pending',
                'approved',
                'rejected',
                'cancelled',
              ])
                DashOption(value: s, label: t('staff.req_$s')),
              DashOption(value: _all, label: t('dawam.all')),
            ],
            value: _status,
            onIntent: (s) => _warmList(s, _kind),
            onChanged: (s) => setState(() => _status = s),
          ),
          DashFilterSelect<String>(
            label: t('staff.kind'),
            allLabel: t('staff.allKinds'),
            minWidth: RequestsRowMetrics.kindFilter,
            options: [
              for (final k in requestKinds)
                DashOption(value: k, label: t(requestKindMeta(k).labelKey)),
            ],
            value: _kind,
            onOptionIntent: (k) => _warmList(_status, k),
            onChanged: (k) => setState(() => _kind = k),
          ),
        ],
      ),
      body: body,
    );
  }
}

abstract final class RequestsRowMetrics {
  /// The kind filter (`w-48`).
  static const double kindFilter = 192;

  /// The skeleton's tile (`size-9`).
  static const double tile = Space.xxl + Space.xs;
}

/// Loading: four skeleton rows (TEAM-REQ-004).
class RequestsSkeleton extends StatelessWidget {
  const RequestsSkeleton({super.key});

  @override
  Widget build(BuildContext context) => DashListCard(
    children: [
      for (var i = 0; i < 4; i++)
        Container(
          constraints: const BoxConstraints(minHeight: DashMetrics.listRow),
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: Space.lg,
            vertical: Space.sm + DashMetrics.hair,
          ),
          child: Row(
            spacing: Space.md,
            children: [
              const DashSkeleton(
                width: RequestsRowMetrics.tile,
                height: RequestsRowMetrics.tile,
                radius: Radii.sm,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Space.xs + DashMetrics.hair,
                  children: const [
                    FractionallySizedBox(
                      widthFactor: 1 / 3,
                      child: DashSkeleton(height: Space.md + DashMetrics.hair),
                    ),
                    FractionallySizedBox(
                      widthFactor: 1 / 2,
                      child: DashSkeleton(height: Space.md),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

/// One request (the web's `ListRow`): kind glyph; name, kind and badges;
/// the window, title, reason, who decided or cancelled; what approving
/// means; then the status and the actions (under the words on a phone).
class RequestRow extends ConsumerWidget {
  const RequestRow({
    required this.request,
    required this.mine,
    required this.decide,
    required this.names,
    required this.busy,
    required this.onApprove,
    required this.onReject,
    required this.onCancel,
    this.onApproveIntent,
    super.key,
  });

  final StaffRequest request;

  /// The caller's own (`isMine`).
  final bool mine;

  /// The caller may approve or reject it (`mayDecide`).
  final bool decide;

  /// Employees' names by their account (who cancelled).
  final Map<String, String> names;

  /// A one-click decision on it is running: its buttons wait.
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback? onApproveIntent;
  final VoidCallback onReject;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final width = MediaQuery.sizeOf(context).width;
    final phone = DashBreakpoints.isPhoneWidth(width);
    final r = request;
    final closed = r.monthClosed == true;
    // An approved correction already rewrote the punch (the server refuses
    // to cancel it), and approved time in a closed month can't be cancelled.
    final live =
        r.status == 'pending' ||
        (r.status == 'approved' && r.kind != 'correction' && !closed);
    final badges = [
      if (r.isPaid == false) t('staff.unpaidBadge'),
      if (r.kind == 'leave' && r.isHalfDay)
        switch (r.leaveHalf) {
          'second' => t('staff.halfSecond'),
          'first' => t('staff.halfFirst'),
          _ => t('staff.halfDayUnsaid'),
        },
      if (mine) t('staff.yourRequest'),
      if (r.toOwner == true) t('staff.toOwner'),
      if (closed && r.status == 'pending') t('staff.monthClosedRejectOnly'),
    ];
    final meta = joinSaid([
      describeWindow(r, t, f),
      // A mission's title says what it is (M43).
      isolate(r.title),
      isolate(r.reason),
      if (r.decidedByName != null && r.status != 'pending')
        t('staff.decidedBy', args: {'name': isolate(r.decidedByName)}),
      isolate(r.decisionNote),
      cancelWords(r, names, t),
    ], ' · ');
    final statusKey = 'staff.req_${r.status}';
    final actions = Wrap(
      spacing: Space.xs,
      runSpacing: Space.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        DashStatusPill(
          label: t.exists(statusKey) ? t(statusKey) : r.status,
          tone: requestStatusTone[r.status] ?? DashTone.neutral,
        ),
        if (decide && !closed)
          DashButton(
            label: t('common.approve'),
            icon: 'check',
            variant: DashButtonVariant.outline,
            size: DashButtonSize.compact,
            onIntent: onApproveIntent,
            onPressed: busy ? null : onApprove,
          ),
        if (decide)
          DashIconButton(
            icon: 'x',
            semanticLabel: t('common.reject'),
            color: c.danger,
            onPressed: busy ? null : onReject,
          ),
        if (live)
          DashIconButton(
            icon: 'ban',
            semanticLabel: t('staff.cancelRequest'),
            onPressed: onCancel,
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
              r.employeeName ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DashType.bodyStrong.copyWith(color: c.textPrimary),
            ),
            DashBadge(t(requestKindMeta(r.kind).labelKey)),
            for (final b in badges)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.sm,
                  vertical: DashMetrics.hair,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.pill),
                  border: Border.all(color: c.hairline),
                ),
                child: Text(
                  b,
                  style: DashType.smallMedium.copyWith(color: c.textPrimary),
                ),
              ),
          ],
        ),
        if (meta.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: DashMetrics.hair),
            // Who decided and who cancelled must stay readable on a phone.
            child: Text(
              meta,
              style: DashType.meta.copyWith(color: c.textSecondary),
            ),
          ),
        if (decide && !closed)
          Padding(
            padding: const EdgeInsets.only(top: DashMetrics.hair),
            child: Text(
              approveMeans(r, t, f),
              style: DashType.small.copyWith(
                color: c.textPrimary.withValues(alpha: 0.8),
              ),
            ),
          ),
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
    final glyph = Container(
      width: RequestsRowMetrics.tile,
      height: RequestsRowMetrics.tile,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: DashIcon(
        requestKindMeta(r.kind).icon,
        size: IconSize.sm,
        color: c.textSecondary,
      ),
    );
    return Container(
      constraints: const BoxConstraints(minHeight: DashMetrics.listRow),
      padding: EdgeInsetsDirectional.symmetric(
        horizontal: width >= DashBreakpoints.sm ? Space.card : Space.lg,
        vertical: Space.sm + DashMetrics.hair,
      ),
      child: Row(
        crossAxisAlignment: phone
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        spacing: Space.md,
        children: [
          glyph,
          Expanded(child: text),
          if (!phone) actions,
        ],
      ),
    );
  }
}
