/// The Requests inbox's own forms (TEAM-REQ-031, TEAM-REQ-040…048): cancel a
/// request, and file one for someone. Approving with the pay question,
/// rejecting with a reason and the mission's worked-days check are the
/// forms Approvals already has (`approvals_dialogs.dart`), as on the web.
/// Each is one server call; on success it toasts, refreshes everything
/// under `/staff` (even when the dialog is gone by then) and closes; on
/// failure it says the server's words and stays open.
library;

import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../approvals/approvals_data.dart';
import '../approvals/approvals_dialogs.dart' show approvalsErrorText;
import '../employees/employees_providers.dart' show employeesReadFor;
import '../shared/staff_query.dart';
import '../shared/team_format.dart';
import 'requests_data.dart';

abstract final class RequestsMetrics {
  /// The dialogs' width (`sm:max-w-md`).
  static const double dialog = 448;
}

/// `listEmployees({employment_status: "active"})`: who a request is filed for.
const activeEmployees = (status: 'active', departmentId: null);

const int _maxNote = 500;

// ── cancel (requests-inbox.tsx `CancelRequestDialog`) ──────────────────────

/// Cancelling a request: someone else's, or any approved one, needs a reason
/// (AT-7); one's own pending request does not.
Future<void> showCancelRequestDialog(
  BuildContext context,
  StaffRequest request, {
  required bool mine,
}) => showDashDialog<void>(
  context,
  width: RequestsMetrics.dialog,
  builder: (_) => CancelRequestDialog(request: request, mine: mine),
);

class CancelRequestDialog extends ConsumerStatefulWidget {
  const CancelRequestDialog({
    required this.request,
    required this.mine,
    super.key,
  });

  final StaffRequest request;
  final bool mine;

  @override
  ConsumerState<CancelRequestDialog> createState() =>
      _CancelRequestDialogState();
}

class _CancelRequestDialogState extends ConsumerState<CancelRequestDialog> {
  String _note = '';
  bool _submitted = false;
  bool _busy = false;

  String? _problem(Translator t) {
    final n = _note.trim();
    if (n.length > _maxNote) return t('staff.noteTooLong');
    final required = !widget.mine || widget.request.status == 'approved';
    if (required && n.isEmpty) return t('staff.cancelNoteRequired');
    return null;
  }

  Future<void> _save() async {
    final t = ref.read(tProvider);
    final f = ref.read(formatProvider);
    setState(() => _submitted = true);
    if (_problem(t) != null || _busy) return;
    setState(() => _busy = true);
    final note = _note.trim();
    final staff = ref.read(staffRevisionsProvider.notifier);
    try {
      await ref
          .read(apiProvider)
          .staff
          .decideRequest(
            id: widget.request.id,
            body: RequestDecision(
              status: 'cancelled',
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
    DashToast.success(context, t('staff.requestCancelled'));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final r = widget.request;
    return DashSurface(
      title: t('staff.cancelRequestTitle'),
      description: '${r.employeeName ?? ''} · ${describeWindow(r, t, f)}',
      body: DashTextField(
        label: t('staff.cancelNote'),
        value: _note,
        errorText: _submitted ? _problem(t) : null,
        onChanged: (v) => setState(() => _note = v),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        DashButton(
          label: t('common.back'),
          variant: DashButtonVariant.ghost,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        DashButton(
          label: t('staff.cancelRequest'),
          variant: DashButtonVariant.destructive,
          loading: _busy,
          onPressed: _busy ? null : _save,
        ),
      ],
    );
  }
}

// ── file one (requests-inbox.tsx `NewRequestDialog`) ───────────────────────

/// File a request on someone's behalf: the phone-call path.
Future<void> showNewRequestDialog(BuildContext context) => showDashDialog<void>(
  context,
  width: RequestsMetrics.dialog,
  builder: (_) => const NewRequestDialog(),
);

class NewRequestDialog extends ConsumerStatefulWidget {
  const NewRequestDialog({super.key});

  @override
  ConsumerState<NewRequestDialog> createState() => _NewRequestDialogState();
}

class _NewRequestDialogState extends ConsumerState<NewRequestDialog> {
  // Opens on today, 12:00–14:00, a late arrival (reset on every open).
  late final NewRequestForm _v = NewRequestForm(onDate: teamTodayIsoOf(ref));
  bool _submitted = false;
  bool _payMissing = false;
  bool _busy = false;

  /// "To" follows "From" until it is set by hand, and never sits before it.
  bool _endByHand = false;

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  bool _needsPay(List<Employee> people) {
    final userId = ref.read(currentSessionProvider)?.user.id;
    if (_v.kind != 'leave' || userId == null) return false;
    final mine = people
        .where((e) => e.id == _v.employeeId)
        .map((e) => e.userId)
        .firstOrNull;
    return mine == userId &&
        ref.read(authzProvider).can(Cap.hrRequestsSelfApprove);
  }

  void _followFrom(String from) {
    if (!_endByHand || _v.endDate.isEmpty || _v.endDate.compareTo(from) < 0) {
      _v.endDate = from;
    }
  }

  Future<void> _save(List<Employee> people) async {
    final t = ref.read(tProvider);
    final f = ref.read(formatProvider);
    setState(() => _submitted = true);
    if (_busy || newRequestProblems(_v, t).isNotEmpty) return;
    if (_needsPay(people) && _v.pay.isEmpty) {
      setState(() => _payMissing = true);
      return;
    }
    setState(() => _busy = true);
    final staff = ref.read(staffRevisionsProvider.notifier);
    final StaffRequest row;
    try {
      row = await ref
          .read(apiProvider)
          .staff
          .createRequestAdmin(body: newRequestBody(_v));
    } on Object catch (e) {
      if (!mounted) return;
      DashToast.error(context, approvalsErrorText(e, t, f));
      setState(() => _busy = false);
      return;
    }
    staff.invalidateStaff();
    if (!mounted) return;
    // The server decides whether it was approved as it was filed (RQ-5).
    DashToast.success(
      context,
      row.status == 'approved'
          ? t('staff.requestFiledApproved')
          : t('staff.requestFiled'),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final people =
        ref.watch(employeesReadFor(activeEmployees)).value ??
        const <Employee>[];
    final errors = _submitted
        ? newRequestProblems(_v, t)
        : const <String, String>{};
    final kind = _v.kind;
    final today = DateTime.parse(teamTodayIsoOf(ref));
    Widget time(
      String label,
      String value,
      String field,
      void Function(String) set,
    ) => DashTimeFormField(
      label: label,
      value: value,
      clearable: true,
      errorText: errors[field],
      onChanged: (x) => setState(() => set(DashTime.toHHMM(x))),
    );
    final cells = <Widget>[
      DashDateFormField(
        label: _v.isSpan ? t('staff.from') : t('staff.date'),
        value: DateTime.parse(_v.onDate),
        today: today,
        onChanged: (d) => setState(() {
          _v.onDate = _iso(d);
          _followFrom(_v.onDate);
        }),
      ),
      if (_v.isSpan)
        DashDateFormField(
          label: t('staff.to'),
          value: DateTime.parse(_v.endDate),
          today: today,
          errorText: errors['end_date'],
          onChanged: (d) => setState(() {
            _endByHand = true;
            _v.endDate = _iso(d);
          }),
        ),
      if (_v.needsFrom)
        time(
          kind == 'early_departure'
              ? t('staff.leavingAt')
              : t('staff.windowFrom'),
          _v.fromTime,
          'from_time',
          (x) => _v.fromTime = x,
        ),
      if (_v.needsTo)
        time(
          kind == 'late_arrival' ? t('staff.arrivingBy') : t('staff.windowTo'),
          _v.toTime,
          'to_time',
          (x) => _v.toTime = x,
        ),
    ];
    return DashSurface(
      title: t('staff.newRequest'),
      description: t('staff.newRequestHint'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          DashSelectField<String>(
            label: t('staff.kind'),
            options: [
              for (final k in fileableKinds)
                DashOption(value: k, label: t(requestKindMeta(k).labelKey)),
            ],
            value: kind,
            onChanged: (k) => setState(() => _v.kind = k),
          ),
          DashSelectField<String>(
            label: t('staff.employee'),
            placeholder: t('staff.pickEmployee'),
            searchable: true,
            options: [
              for (final e in people) DashOption(value: e.id, label: e.name),
            ],
            value: _v.employeeId,
            onChanged: (id) => setState(() => _v.employeeId = id),
          ),
          if (kind == 'leave')
            Container(
              padding: const EdgeInsets.all(Space.md),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.sm),
                border: Border.all(color: c.hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.sm,
                children: [
                  DashSwitchField(
                    label: t('staff.halfDayToggle'),
                    value: _v.halfDay,
                    onChanged: (on) => setState(() => _v.halfDay = on),
                  ),
                  if (_v.halfDay)
                    DashSegmentedControl<String>(
                      semanticLabel: t('staff.halfDayToggle'),
                      options: [
                        DashOption(value: 'first', label: t('staff.firstHalf')),
                        DashOption(
                          value: 'second',
                          label: t('staff.secondHalf'),
                        ),
                      ],
                      value: _v.leaveHalf,
                      onChanged: (h) => setState(() => _v.leaveHalf = h),
                    ),
                  if (_needsPay(people)) ...[
                    Text(
                      t('staff.leavePayQuestion'),
                      style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                    ),
                    DashSegmentedControl<String>(
                      semanticLabel: t('staff.leavePayQuestion'),
                      options: [
                        DashOption(value: 'paid', label: t('staff.paid')),
                        DashOption(value: 'unpaid', label: t('staff.unpaid')),
                      ],
                      value: _v.pay,
                      onChanged: (p) => setState(() {
                        _v.pay = p;
                        _payMissing = false;
                      }),
                    ),
                    if (_payMissing)
                      Text(
                        t('staff.payChoiceNeeded'),
                        style: DashType.small.copyWith(color: c.danger),
                      ),
                  ],
                ],
              ),
            ),
          if (kind == 'mission')
            DashTextField(
              label: t('staff.missionTitleOptional'),
              value: _v.title,
              errorText: errors['title'],
              onChanged: (v) => setState(() => _v.title = v),
            ),
          for (var i = 0; i < cells.length; i += 2)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.md,
              children: [
                Expanded(child: cells[i]),
                Expanded(
                  child: i + 1 < cells.length
                      ? cells[i + 1]
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          if (kind == 'excuse')
            Text(
              t('staff.excuseMidnightHint'),
              style: DashType.small.copyWith(color: c.textSecondary),
            ),
          DashTextField(
            label: t('staff.reason'),
            value: _v.reason,
            errorText: errors['reason'],
            onChanged: (v) => setState(() => _v.reason = v),
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
          label: t('common.save'),
          loading: _busy,
          onPressed: _busy || _v.employeeId == null
              ? null
              : () => _save(people),
        ),
      ],
    );
  }
}
