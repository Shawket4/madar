/// The Team board's two dialogs (`dawam/team-page.tsx`): what a manager does
/// with a flag (TEAM-TEM-012…022; nothing is charged automatically) and a
/// punch for someone whose phone died (TEAM-TEM-029/030; a reason is
/// required).
library;

import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../employees/employees_providers.dart';
import '../payroll/money_errors.dart';
import '../shared/attendance_errors.dart';
import '../shared/staff_query.dart';
import '../shared/team_util.dart';
import 'team_board_data.dart';

/// `listEmployees({})`: everyone, to tell the signed-in person's own flags
/// (`useOwnEmployeeIds`).
const EmployeesQuery teamEveryone = (status: null, departmentId: null);

Future<void> showFlagDialog(BuildContext context, AttendanceFlag flag) =>
    showDashDialog<void>(context, builder: (_) => FlagDialog(flag: flag));

Future<void> showPunchDialog(BuildContext context, PresenceRow person) =>
    showDashDialog<void>(context, builder: (_) => PunchDialog(person: person));

/// `JS String(n)` of a pound figure: "48.08", "50", "0".
String _pounds(int piastres) {
  final v = piastres / 100;
  return v == v.truncateToDouble() ? '${v.toInt()}' : '$v';
}

class FlagDialog extends ConsumerStatefulWidget {
  const FlagDialog({required this.flag, super.key});

  final AttendanceFlag flag;

  @override
  ConsumerState<FlagDialog> createState() => _FlagDialogState();
}

class _FlagDialogState extends ConsumerState<FlagDialog> {
  final _form = GlobalKey<FormState>();
  late String _amount = _pounds(widget.flag.suggestedDeductionPiastres);
  String _reason = '';
  bool _busy = false;

  AttendanceFlag get flag => widget.flag;

  Future<void> _send(String action, [int? amountPiastres]) async {
    if (_busy) return;
    setState(() => _busy = true);
    final t = ref.read(tProvider);
    final f = ref.read(formatProvider);
    final authz = ref.read(authzProvider);
    // Captured first: the web refetches even when the dialog is gone.
    final revisions = ref.read(staffRevisionsProvider.notifier);
    final reason = _reason.trim();
    try {
      final handled = await ref
          .read(apiProvider)
          .staff
          .resolveFlag(
            id: flag.id,
            body: ResolveFlag(
              action: action,
              amountPiastres: amountPiastres,
              // A deduction is a pay line the employee reads: it carries why.
              reason: action == 'deduct' && reason.isNotEmpty ? reason : null,
              explicitNulls: const {'amount_piastres', 'reason'},
            ),
          );
      revisions.invalidateStaff();
      final waits = deductionWaits(
        handled: handled,
        action: action,
        amountPiastres: amountPiastres,
        holdsRight: authz.can(Cap.hrDeductionsCreate),
        limit: authz.limitsOf(Cap.hrDeductionsCreate)?.maxAmount,
      );
      if (!mounted) return;
      if (waits) {
        DashToast.info(context, t('dawam.payLinePending'));
      } else {
        DashToast.success(context, t('dawam.flagHandled'));
      }
      Navigator.of(context).pop();
    } on Object catch (e) {
      // Handled by someone else first: the board reads again.
      final stale = isStaleRefusal(e);
      if (stale) revisions.invalidateStaff();
      if (!mounted) return;
      DashToast.error(context, attendanceErrorText(e, t, f));
      if (stale) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _deduct() {
    if (!(_form.currentState?.validate() ?? false)) return;
    _send('deduct', readPounds(_amount));
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final authz = ref.watch(authzProvider);
    final canDeduct =
        authz.can(Cap.hrDeductionsCreate) ||
        authz.canAsk(Cap.hrDeductionsCreate);
    final canConfirmCover = authz.can(Cap.hrShiftCoverConfirm);
    final canRevoke = authz.can(Cap.hrStaffEdit);
    // Nobody decides their own flag (server 403 OWN_DECISION).
    final userId = ref.watch(currentSessionProvider.select((s) => s?.user.id));
    final people = userId == null
        ? const <Employee>[]
        : ref.watch(employeesListProvider(teamEveryone)).value ??
              const <Employee>[];
    final mine = people.any(
      (e) => e.id == flag.employeeId && e.userId == userId,
    );
    final kind = flag.kind;
    final cover = kind == 'cover';
    final note = DashType.small.copyWith(color: c.textSecondary);

    final body = <Widget>[
      if (mine)
        Text(
          t('dawam.ownFlag'),
          style: DashType.body.copyWith(color: c.textSecondary),
        ),
      if (!mine && kind == 'left_mid_shift') ...[
        Row(
          spacing: Space.sm,
          children: [
            Expanded(
              child: DashButton(
                label: t('dawam.excusePaid'),
                variant: DashButtonVariant.outline,
                expand: true,
                onPressed: _busy ? null : () => _send('excuse_paid'),
              ),
            ),
            Expanded(
              child: canDeduct
                  ? DashButton(
                      label: t('dawam.excuseUnpaid'),
                      variant: DashButtonVariant.outline,
                      expand: true,
                      onPressed: _busy ? null : () => _send('excuse_unpaid'),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
        if (canDeduct)
          Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.md,
              children: [
                DashTextField(
                  label: t('dawam.deductAmount'),
                  value: _amount,
                  onChanged: (v) => setState(() => _amount = v),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  description: t(
                    'dawam.suggested',
                    args: {
                      'amount': f.fmtMoney(flag.suggestedDeductionPiastres),
                    },
                  ),
                  validator: (v) =>
                      readPounds(v) == null ? t('dawam.badAmount') : null,
                ),
                DashTextField(
                  label: t('dawam.deductReason'),
                  value: _reason,
                  onChanged: (v) => setState(() => _reason = v),
                ),
                DashButton(
                  label: t('dawam.deduct'),
                  variant: DashButtonVariant.destructive,
                  expand: true,
                  onPressed: _busy ? null : _deduct,
                ),
              ],
            ),
          )
        else
          Text(t('dawam.deductNeedsRight'), style: note),
      ],
      if (!mine && cover && !canConfirmCover)
        Text(t('dawam.coverNeedsRight'), style: note),
    ];
    final actions = mine
        ? const <Widget>[]
        : [
            if (kind == 'new_phone' && canRevoke)
              DashButton(
                label: t('dawam.revokePhone'),
                variant: DashButtonVariant.destructive,
                onPressed: _busy ? null : () => _send('revoke'),
              ),
            // A cover flag is confirmed or rejected, nothing else.
            if (cover && canConfirmCover) ...[
              DashButton(
                label: t('dawam.rejectCover'),
                variant: DashButtonVariant.outline,
                onPressed: _busy ? null : () => _send('reject'),
              ),
              DashButton(
                label: t('dawam.confirmCover'),
                onPressed: _busy ? null : () => _send('confirm'),
              ),
            ],
            if (!cover)
              DashButton(
                label: t('dawam.ignore'),
                variant: DashButtonVariant.ghost,
                onPressed: _busy ? null : () => _send('ignore'),
              ),
          ];
    return DashSurface(
      title: '${flag.employeeName} · ${t(flagMeta(kind).key)}',
      description: t(flagHintKey(kind), args: {'m': flag.minutesAway}),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.md,
        children: body,
      ),
      actions: actions,
    );
  }
}

class PunchDialog extends ConsumerStatefulWidget {
  const PunchDialog({required this.person, super.key});

  final PresenceRow person;

  @override
  ConsumerState<PunchDialog> createState() => _PunchDialogState();
}

class _PunchDialogState extends ConsumerState<PunchDialog> {
  final _form = GlobalKey<FormState>();
  String _reason = '';
  bool _busy = false;

  Future<void> _save() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    final t = ref.read(tProvider);
    final f = ref.read(formatProvider);
    final revisions = ref.read(staffRevisionsProvider.notifier);
    final out = punchesOut(widget.person);
    try {
      await ref
          .read(apiProvider)
          .staff
          .punchFor(
            body: PunchFor(
              employeeId: widget.person.employeeId,
              reason: _reason.trim(),
            ),
          );
      revisions.invalidateStaff();
      if (!mounted) return;
      DashToast.success(
        context,
        out ? t('dawam.punchedOut') : t('dawam.punchedIn'),
      );
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) {
        DashToast.error(
          context,
          dawamErrorMessage(e, t, f, reasonFor: ReasonFor.punchFor),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final p = widget.person;
    final out = punchesOut(p);
    final empty = _reason.trim().isEmpty;
    final chips = [
      t('dawam.reasonPhoneDied'),
      t('dawam.reasonNoSignal'),
      t('dawam.reasonForgotPhone'),
    ];
    return DashSurface(
      title: out
          ? t('dawam.punchOutFor', args: {'name': p.employeeName})
          : t('dawam.punchInFor', args: {'name': p.employeeName}),
      description: t('dawam.punchHint'),
      body: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: Space.sm,
          children: [
            DashTextField(
              label: t('staff.reason'),
              placeholder: t('dawam.punchReasonPlaceholder'),
              value: _reason,
              autofocus: true,
              onChanged: (v) => setState(() => _reason = v),
              onSubmitted: (_) => _save(),
              description: empty ? t('dawam.punchReasonNeeded') : null,
              validator: (v) =>
                  v.trim().isEmpty ? t('staff.reasonRequired') : null,
            ),
            Wrap(
              spacing: Space.xs + DashMetrics.hair,
              runSpacing: Space.xs + DashMetrics.hair,
              children: [
                for (final r in chips)
                  DashButton(
                    label: r,
                    size: DashButtonSize.compact,
                    variant: DashButtonVariant.outline,
                    onPressed: () => setState(() => _reason = r),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        DashButton(
          label: t('common.cancel'),
          variant: DashButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        DashButton(
          label: out ? t('dawam.punchOut') : t('dawam.punchIn'),
          loading: _busy,
          onPressed: _busy || empty ? null : _save,
        ),
      ],
    );
  }
}
