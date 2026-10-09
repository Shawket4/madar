/// The forms an Approvals decision may open (TEAM-APR-012…017,
/// TEAM-REQ-020…024): approve with the pay question and the mission's
/// worked-days check. Reviewing an advance and rejecting with a reason are
/// payroll's shared money forms (`money_dialogs.dart`, as the web's
/// `money-dialogs.tsx`, TEAM-MNY-033 / TEAM-MNY-039).
/// Each is one server call; on success it says "Decision saved", refreshes
/// everything under `/staff` (even when the dialog is gone by then) and
/// closes; on failure it says the server's words and stays open.
library;

import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../attendance/attendance_providers.dart';
import '../requests/requests_dialogs.dart' show RequestsMetrics;
import '../shared/attendance_errors.dart';
import '../shared/staff_query.dart';
import 'approvals_data.dart';
import 'approvals_providers.dart';

/// What a person reads for a decision refused (`getErrorMessage(e, opts)`):
/// the shared wording, plus the variants a decision meets — a missing
/// reason worded for a rejection (`reasonFor: "decline"`), an advance over
/// the cap for someone who may not see the salary, and the status variants.
String approvalsErrorText(
  Object? error,
  Translator t,
  DashFormat f, {
  bool decline = false,
}) {
  if (error is ApiException) {
    final code = error.code;
    final d = error.details;
    final vars = d is Map && d['vars'] is Map
        ? (d['vars']! as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final status = vars['status'];
    final key = switch (code) {
      'REASON_REQUIRED' when decline => 'REASON_REQUIRED_decline',
      'ADVANCE_OVER_CAP'
          when vars['more_egp'] == null && vars['over_cap'] == true =>
        'ADVANCE_OVER_CAP_owner',
      'CANCEL_REASON_REQUIRED' when status == 'approved' =>
        'CANCEL_REASON_REQUIRED_approved',
      'OPEN_SHIFT_CLOSED' when status == 'filled' || status == 'cancelled' =>
        'OPEN_SHIFT_CLOSED_$status',
      _ => null,
    };
    if (key != null && t.exists('errors.codes.$key')) {
      return t('errors.codes.$key');
    }
  }
  return attendanceErrorText(error, t, f);
}

/// The longest note or reason the forms take (`max(500)`).
const int _maxNote = 500;

// ── approve with pay (requests-inbox.tsx `ApproveWithPayDialog`) ───────────

/// Approving leave, a permission or an early departure asks paid or not
/// (TEAM-REQ-020…023). [source] is the list the request came from (its
/// fresher copy re-seeds the switch); Approvals' pending read by default.
Future<void> showApproveWithPayDialog(
  BuildContext context,
  StaffRequest request, {
  FutureProvider<List<StaffRequest>>? source,
}) => showDashDialog<void>(
  context,
  width: RequestsMetrics.dialog,
  builder: (_) => ApproveWithPayDialog(request: request, source: source),
);

class ApproveWithPayDialog extends ConsumerStatefulWidget {
  const ApproveWithPayDialog({required this.request, this.source, super.key});

  final StaffRequest request;
  final FutureProvider<List<StaffRequest>>? source;

  @override
  ConsumerState<ApproveWithPayDialog> createState() =>
      _ApproveWithPayDialogState();
}

class _ApproveWithPayDialogState extends ConsumerState<ApproveWithPayDialog> {
  bool? _paid;
  bool _touched = false;
  String _note = '';
  bool _submitted = false;
  bool _busy = false;

  String? _noteProblem(Translator t) =>
      _note.length > _maxNote ? t('staff.noteTooLong') : null;

  Future<void> _approve(StaffRequest r) async {
    final t = ref.read(tProvider);
    final f = ref.read(formatProvider);
    setState(() => _submitted = true);
    if (_noteProblem(t) != null) return;
    setState(() => _busy = true);
    // Leave always says (the server requires it); a window kind the approver
    // didn't touch says nothing, so the rule applies.
    final sendPaid = r.kind == 'leave' || _touched;
    final note = _note.trim();
    final staff = ref.read(staffRevisionsProvider.notifier);
    try {
      await ref
          .read(apiProvider)
          .staff
          .decideRequest(
            id: r.id,
            body: RequestDecision(
              status: 'approved',
              isPaid: sendPaid ? (_paid ?? r.paidDefault ?? true) : null,
              note: note.isEmpty ? null : note,
              explicitNulls: const {'note'},
            ),
          );
    } on Object catch (e) {
      if (!mounted) return;
      DashToast.error(context, approvalsErrorText(e, t, f));
      setState(() => _busy = false);
      return;
    }
    staff.invalidateStaff();
    if (!mounted) return;
    DashToast.success(context, t('staff.decisionSaved'));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    // The latest copy of the request: a refresh re-seeds the switch until
    // the approver touches it.
    var r = widget.request;
    final source = widget.source ?? approvalsRequestsProvider;
    for (final x in ref.watch(source).value ?? const []) {
      if (x.id == r.id) r = x;
    }
    final leave = r.kind == 'leave';
    final paid = _touched ? _paid! : (r.paidDefault ?? true);
    final worked = r.workedDates ?? const <String>[];
    final sep = t('common.listSeparator');
    return DashSurface(
      title: t('staff.approveRequest'),
      description: '${r.employeeName} · ${describeWindow(r, t, f)}',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          Container(
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.sm),
              border: Border.all(color: c.hairline),
            ),
            child: Row(
              spacing: Space.md,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: DashMetrics.hair,
                    children: [
                      Text(
                        leave ? t('staff.paidLeaveSwitch') : t('staff.paidTime'),
                        style: DashType.bodyMedium.copyWith(
                          color: c.textPrimary,
                        ),
                      ),
                      Text(
                        leave ? t('staff.paidLeaveHint') : t('staff.paidTimeHint'),
                        style: DashType.small.copyWith(color: c.textSecondary),
                      ),
                      // Leave over a worked day turns it into leave (M16).
                      if (leave && worked.isNotEmpty)
                        Text(
                          t(
                            'staff.leaveOverPunches',
                            args: {
                              'name': r.employeeName,
                              'dates': worked.map(f.fmtDate).join(sep),
                            },
                          ),
                          style: DashType.smallMedium.copyWith(
                            color: DashTone.warning.foreground(c),
                          ),
                        ),
                      if (!leave && r.paidDefault != null)
                        Text(
                          r.paidDefault!
                              ? t('staff.ruleSaysPaid')
                              : t('staff.ruleSaysUnpaid'),
                          style: DashType.small.copyWith(
                            color: c.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                DashSwitch(
                  value: paid,
                  semanticLabel: leave
                      ? t('staff.paidLeaveSwitch')
                      : t('staff.paidTime'),
                  onChanged: (v) => setState(() {
                    _paid = v;
                    _touched = true;
                  }),
                ),
              ],
            ),
          ),
          DashTextField(
            label: t('staff.note'),
            value: _note,
            errorText: _submitted ? _noteProblem(t) : null,
            onChanged: (v) => setState(() => _note = v),
          ),
        ],
      ),
      actions: [
        DashButton(
          label: t('common.cancel'),
          variant: DashButtonVariant.ghost,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        DashButton(
          label: t('common.approve'),
          loading: _busy,
          onPressed: _busy ? null : () => _approve(r),
        ),
      ],
    );
  }
}

// ── the mission's worked days (requests-inbox.tsx) ──────────────────────────

/// `listAttendance({from, to, employee_id})`: the days a mission covers, the
/// read made before approving one the server sent no `worked_dates` for.
AttendanceQuery missionDaysKey(StaffRequest r) => (
  from: r.onDate,
  to: r.endDate ?? r.onDate,
  branchId: null,
  status: null,
  employeeId: r.employeeId,
);

/// A mission approved over days already worked turns them into mission
/// days; the approver is told first (`confirmMissionOverPunches`). False
/// means they backed out. If the days can't be read, it goes ahead.
Future<bool> confirmMissionOverPunches(
  BuildContext context,
  WidgetRef ref,
  StaffRequest r,
) async {
  if (r.kind != 'mission') return true;
  var worked = r.workedDates;
  if (worked == null) {
    try {
      final days = await ref.read(
        attendanceListProvider(missionDaysKey(r)).future,
      );
      worked = [
        for (final a in days)
          if (a.checkInAt != null) a.businessDate,
      ];
    } on Object {
      return true;
    }
  }
  if (!context.mounted) return false;
  if (worked.isEmpty) return true;
  final t = ref.read(tProvider);
  final f = ref.read(formatProvider);
  final dates = worked.map(f.fmtDate).join(t('common.listSeparator'));
  return showDashConfirm(
    context,
    title: t('staff.missionOverPunchesTitle', args: {'name': r.employeeName}),
    description:
        '${t('staff.workedOn', args: {'dates': dates})} '
        '${t('staff.missionOverPunchesHint')}',
    confirmLabel: t('common.approve'),
  );
}
