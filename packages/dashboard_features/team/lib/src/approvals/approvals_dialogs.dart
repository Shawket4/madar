/// The forms an Approvals decision may open (TEAM-APR-012…017, TEAM-MNY-033,
/// TEAM-MNY-039, TEAM-REQ-020…024): approve with the pay question, review an
/// advance, reject with a reason, and the mission's worked-days check.
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

/// Lets a number field still in focus settle its value (it does on blur, as
/// the web's does when Save is clicked).
Future<void> _settleFields() async {
  FocusManager.instance.primaryFocus?.unfocus();
  await Future<void>.microtask(() {});
}

// ── reject with a reason (money-dialogs.tsx `RejectDialog`) ─────────────────

/// Reject [onReject] with a reason: REQUIRED for money (D8), optional for a
/// request (sent as its note). TEAM-MNY-033.
Future<void> showRejectReasonDialog(
  BuildContext context, {
  required String title,
  required String description,
  required bool optional,
  required Future<Object?> Function(String reason) onReject,
}) => showDashDialog<void>(
  context,
  builder: (_) => RejectReasonDialog(
    title: title,
    description: description,
    optional: optional,
    onReject: onReject,
  ),
);

class RejectReasonDialog extends ConsumerStatefulWidget {
  const RejectReasonDialog({
    required this.title,
    required this.description,
    required this.optional,
    required this.onReject,
    super.key,
  });

  final String title;
  final String description;
  final bool optional;
  final Future<Object?> Function(String reason) onReject;

  @override
  ConsumerState<RejectReasonDialog> createState() => _RejectReasonDialogState();
}

class _RejectReasonDialogState extends ConsumerState<RejectReasonDialog> {
  String _reason = '';
  bool _submitted = false;
  bool _busy = false;

  String? _problem(Translator t) {
    final r = _reason.trim();
    if (!widget.optional && r.isEmpty) return t('dawam.reasonRequired');
    // The web's required reason over 500 says zod's English: its note words.
    if (r.length > _maxNote) return t('staff.noteTooLong');
    return null;
  }

  Future<void> _save() async {
    final t = ref.read(tProvider);
    final f = ref.read(formatProvider);
    setState(() => _submitted = true);
    if (_problem(t) != null) return;
    setState(() => _busy = true);
    final staff = ref.read(staffRevisionsProvider.notifier);
    try {
      await widget.onReject(_reason.trim());
    } on Object catch (e) {
      if (!mounted) return;
      DashToast.error(context, approvalsErrorText(e, t, f, decline: true));
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
    return DashSurface(
      title: widget.title,
      description: widget.description,
      body: DashTextField(
        label: widget.optional
            ? t('dawamOps.reasonOptional')
            : t('staff.reason'),
        description: t('dawamOps.reasonSeen'),
        value: _reason,
        errorText: _submitted ? _problem(t) : null,
        onChanged: (v) => setState(() => _reason = v),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        DashButton(
          label: t('common.cancel'),
          variant: DashButtonVariant.ghost,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        DashButton(
          label: t('common.reject'),
          variant: DashButtonVariant.destructive,
          loading: _busy,
          onPressed: _busy ? null : _save,
        ),
      ],
    );
  }
}

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

// ── review an advance (money-dialogs.tsx `ReviewAdvanceDialog`) ────────────

/// Decide a salary advance someone asked for, optionally changing it
/// (TEAM-MNY-039).
Future<void> showReviewAdvanceDialog(
  BuildContext context,
  SalaryAdvance advance,
) => showDashDialog<void>(
  context,
  builder: (_) => ReviewAdvanceDialog(advance: advance),
);

class ReviewAdvanceDialog extends ConsumerStatefulWidget {
  const ReviewAdvanceDialog({required this.advance, super.key});

  final SalaryAdvance advance;

  @override
  ConsumerState<ReviewAdvanceDialog> createState() =>
      _ReviewAdvanceDialogState();
}

class _ReviewAdvanceDialogState extends ConsumerState<ReviewAdvanceDialog> {
  int? _amount;
  double? _installments;
  String _note = '';
  bool _edited = false;
  bool _submitted = false;
  bool _busy = false;

  Map<String, String> _problems(Translator t) {
    final n = _installments;
    return {
      if (_amount == null || _amount! <= 0) 'amount': t('dawam.amountRequired'),
      // The web's minimum says zod's English: the field's own range words.
      if (n == null || !n.isFinite || n != n.roundToDouble() || n < 1 || n > 24)
        'installments': t('dawam.installmentsHint'),
      if (_note.length > _maxNote) 'note': t('staff.noteTooLong'),
    };
  }

  void _edit(VoidCallback change) => setState(() {
    change();
    _edited = true;
  });

  Future<void> _save(SalaryAdvance a) async {
    await _settleFields();
    if (!mounted) return;
    final t = ref.read(tProvider);
    final f = ref.read(formatProvider);
    setState(() => _submitted = true);
    if (_problems(t).isNotEmpty) return;
    setState(() => _busy = true);
    final staff = ref.read(staffRevisionsProvider.notifier);
    final amount = _amount!;
    final note = _note.trim();
    try {
      await ref
          .read(apiProvider)
          .staff
          .reviewAdvance(
            id: a.id,
            body: ReviewAdvance(
              approve: true,
              // Sent exactly as approved: an untouched amount keeps its
              // piastres (null).
              amountPiastres: amount == a.amountPiastres ? null : amount,
              installments: _installments!.round(),
              note: note.isEmpty ? null : note,
              explicitNulls: const {'amount_piastres', 'note'},
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
    var a = widget.advance;
    for (final x in ref.watch(approvalsAdvancesProvider).value ?? const []) {
      if (x.id == a.id) a = x;
    }
    // Seeded from the latest copy until the approver edits.
    if (!_edited) {
      _amount = a.amountPiastres;
      _installments = a.installments.toDouble();
    }
    final problems = _submitted ? _problems(t) : const <String, String>{};
    return DashSurface(
      title: t('dawam.reviewAdvance', args: {'name': a.employeeName ?? ''}),
      description: t('dawam.reviewAdvanceHint'),
      // Focusing a field starts an edit: a refresh never wipes a number
      // typed but not settled yet (fields settle on blur).
      body: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (focused) => _edited = _edited || focused,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.md,
          children: [
            DashMoneyField(
              label: t('dawam.amountEgp'),
              value: _amount,
              allowEmpty: true,
              errorText: problems['amount'],
              onChanged: (v) => _edit(() => _amount = v),
            ),
            DashNumberField(
              label: t('dawam.installments'),
              value: _installments,
              stepper: true,
              allowEmpty: true,
              errorText: problems['installments'],
              onChanged: (v) => _edit(() => _installments = v),
            ),
            DashTextField(
              label: t('staff.note'),
              value: _note,
              errorText: problems['note'],
              onChanged: (v) => _edit(() => _note = v),
            ),
          ],
        ),
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
          onPressed: _busy ? null : () => _save(a),
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
