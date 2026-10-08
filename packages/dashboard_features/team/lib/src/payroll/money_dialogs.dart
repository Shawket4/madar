/// The small money forms Payroll, Approvals and the Team board share
/// (`dawam/money-dialogs.tsx`, TEAM-MNY rows): a bonus or deduction, a
/// salary advance recorded by a manager, an expense advance, correcting a
/// till tag, marking someone paid, rejecting with why, waiving / overriding
/// / un-waiving a rule-made deduction, stopping a monthly line, reopening a
/// month, approving an advance, and the advance-cap note.
///
/// Each is one server call; the server checks limits, the open month and
/// the cap and answers in words, which the toast shows. Every form: a title,
/// a description, its fields, Cancel + Save (destructive where noted,
/// disabled while saving). Save validates; success → the dialog's toast +
/// `invalidateStaff()` + close; failure → the error toast and the dialog
/// stays open. A dialog shows as a centred dialog on a wide screen and full
/// screen on a phone.
///
/// Each `show…` resolves true when it saved.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/staff_query.dart';
import '../shared/team_format.dart';
import 'money_errors.dart';
import 'payroll_data.dart';
import 'payroll_logic.dart';

// ── the frame ───────────────────────────────────────────────────────────

Future<bool> _show(BuildContext context, Widget dialog) async =>
    (await showDashDialog<bool>(context, builder: (_) => dialog)) ?? false;

/// The shared save flow of every money form (`FormDialog`).
mixin _MoneyForm<W extends ConsumerStatefulWidget> on ConsumerState<W> {
  final formKey = GlobalKey<FormState>();
  bool busy = false;

  ReasonFor? get reasonFor => null;
  bool get monthForm => false;

  Translator get t => ref.read(tProvider);

  /// Validates, sends, then toasts and closes; a refusal toasts its words
  /// and keeps the form open.
  Future<void> submit(Future<void> Function() send) async {
    if (busy) return;
    if (!(formKey.currentState?.validate() ?? false)) return;
    setState(() => busy = true);
    try {
      await send();
      ref.read(staffRevisionsProvider.notifier).invalidateStaff();
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (mounted) {
        DashToast.error(
          context,
          dawamErrorMessage(
            e,
            t,
            ref.read(formatProvider),
            reasonFor: reasonFor,
            monthForm: monthForm,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// The dialog itself.
  Widget frame({
    required String title,
    String? description,
    required List<Widget> fields,
    required VoidCallback onSave,
    String? saveLabel,
    bool destructive = false,
  }) {
    final tr = ref.watch(tProvider);
    return DashSurface(
      title: title,
      description: description,
      body: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: Space.md,
          children: fields,
        ),
      ),
      actions: [
        DashButton(
          label: tr('common.cancel'),
          variant: DashButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        DashButton(
          label: saveLabel ?? tr('common.save'),
          variant: destructive
              ? DashButtonVariant.destructive
              : DashButtonVariant.primary,
          onPressed: busy ? null : onSave,
        ),
      ],
    );
  }
}

/// The employee picker (`PersonField`): ACTIVE employees, read while the
/// dialog is open; [notSelf] leaves out the signed-in person (a pay line is
/// never for yourself, AD-4).
class MoneyPersonField extends ConsumerWidget {
  const MoneyPersonField({
    required this.value,
    required this.onChanged,
    this.notSelf = false,
    this.validator,
    super.key,
  });

  final String? value;
  final ValueChanged<String> onChanged;
  final bool notSelf;

  /// Defaults to "Pick an employee" when empty.
  final DashValidator<String?>? validator;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final me = ref.watch(currentSessionProvider.select((s) => s?.user.id));
    final people = ref.watch(payrollPeopleProvider).value ?? const [];
    return DashSelectField<String>(
      label: t('staff.employee'),
      placeholder: t('staff.pickEmployee'),
      value: value,
      onChanged: onChanged,
      options: [
        for (final e in people)
          if (!notSelf || me == null || e.userId != me)
            DashOption(value: e.id, label: e.name),
      ],
      validator:
          validator ??
          (v) => v == null || v.isEmpty ? t('staff.pickEmployee') : null,
    );
  }
}

/// A one-line text field with the kit's frame.
Widget _text({
  required String label,
  required String value,
  required ValueChanged<String> onChanged,
  String? description,
  DashValidator<String>? validator,
  int maxLength = 500,
}) => DashTextField(
  label: label,
  value: value,
  onChanged: onChanged,
  description: description,
  validator: validator,
  maxLength: maxLength,
);

/// A month picker (`<input type="month">`): ‹ October 2026 › on the field's
/// frame, the value `YYYY-MM`.
class MoneyMonthField extends ConsumerWidget {
  const MoneyMonthField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.description,
    this.validator,
    super.key,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final String? description;
  final DashValidator<String>? validator;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.madarColors;
    final strings = context.dashStrings;
    final valid = RegExp(r'^\d{4}-\d{2}$').hasMatch(value);
    final shown = valid
        ? context.dashFormats.monthYear(
            DateTime(
              int.parse(value.substring(0, 4)),
              int.parse(value.substring(5, 7)),
            ),
          )
        : '';
    return DashFormField<String>(
      label: label,
      description: description,
      validator: validator,
      value: value,
      builder: (context, invalid) => DashFieldShell(
        invalid: invalid,
        padding: EdgeInsets.zero,
        leading: DashIconButton(
          icon: DashIcon.backward(context),
          semanticLabel: strings.previous,
          onPressed: valid ? () => onChanged(addMonths(value, -1)) : null,
        ),
        trailing: DashIconButton(
          icon: DashIcon.forward(context),
          semanticLabel: strings.next,
          onPressed: valid ? () => onChanged(addMonths(value, 1)) : null,
        ),
        child: Semantics(
          label: label,
          value: shown,
          child: Text(
            shown,
            textAlign: TextAlign.center,
            style: DashType.bodyMedium.copyWith(color: c.textPrimary),
          ),
        ),
      ),
    );
  }
}

// ── bonus or deduction (TEAM-MNY-001, -010 … -017) ──────────────────────

/// "Add a bonus or deduction": [employeeId] fixes the person (the payslip
/// sheet); [bonus] picks the starting kind.
Future<bool> showAdjustmentDialog(
  BuildContext context, {
  String? employeeId,
  bool bonus = true,
}) => _show(context, AdjustmentDialog(employeeId: employeeId, bonus: bonus));

class AdjustmentDialog extends ConsumerStatefulWidget {
  const AdjustmentDialog({this.employeeId, this.bonus = true, super.key});

  final String? employeeId;
  final bool bonus;

  @override
  ConsumerState<AdjustmentDialog> createState() => _AdjustmentDialogState();
}

class _AdjustmentDialogState extends ConsumerState<AdjustmentDialog>
    with _MoneyForm {
  late String? _employee = widget.employeeId;
  late String _kind = widget.bonus ? 'bonus' : 'deduction';
  String _by = 'amount';

  /// Pounds, or a percent.
  double? _amount;
  String _reason = '';
  bool _recurring = false;
  String? _month;

  @override
  ReasonFor? get reasonFor => ReasonFor.payLine;

  @override
  bool get monthForm => true;

  /// The first open month, from the payroll run when this person may read
  /// it; the form follows it until the month is touched.
  String _openMonth() {
    final canRead = ref.watch(payrollCanReadProvider);
    final period = canRead
        ? ref.watch(payrollCurrentProvider).value?.period
        : null;
    return firstOpenMonth(period, teamTodayIsoOf(ref));
  }

  bool get _percent => _kind == 'bonus' && _by == 'percent';

  Future<void> _save() => submit(() async {
    final month = _month ?? _openMonth();
    final line = await ref
        .read(apiProvider)
        .staff
        .createAdjustment(
          body: NewAdjustment(
            employeeId: _employee!,
            kind: _kind,
            reason: _reason.trim(),
            recurring: _recurring,
            amountPiastres: _percent ? null : egpToPiastres(_amount!),
            percentOfBase: _percent ? _amount : null,
            effectiveDate: monthToDate(month),
            explicitNulls: {_percent ? 'amount_piastres' : 'percent_of_base'},
          ),
        );
    if (!mounted) return;
    if (line.status == 'pending') {
      DashToast.info(context, t('dawam.payLinePending'));
    } else {
      DashToast.success(context, t('dawam.payLineAdded'));
    }
  });

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final month = _month ?? _openMonth();
    final percent = _percent;
    return frame(
      title: t('dawam.addPayLine'),
      description: t('dawam.addPayLineHint'),
      onSave: _save,
      fields: [
        if (widget.employeeId == null)
          MoneyPersonField(
            value: _employee,
            notSelf: true,
            onChanged: (v) => setState(() => _employee = v),
          ),
        DashSegmentedControl<String>(
          semanticLabel: t('dawam.addPayLine'),
          value: _kind,
          onChanged: (v) => setState(() => _kind = v),
          options: [
            DashOption(value: 'bonus', label: t('dawam.bonus')),
            DashOption(value: 'deduction', label: t('dawam.deduction')),
          ],
        ),
        if (_kind == 'bonus')
          DashSegmentedControl<String>(
            value: _by,
            onChanged: (v) => setState(() => _by = v),
            options: [
              DashOption(value: 'amount', label: t('dawam.byAmount')),
              DashOption(value: 'percent', label: t('dawam.byPercent')),
            ],
          ),
        if (percent)
          DashNumberField(
            key: const ValueKey('adj-percent'),
            label: t('dawam.percent'),
            value: _amount,
            step: 0.5,
            stepper: true,
            allowEmpty: true,
            onChanged: (v) => setState(() => _amount = v),
            validator: (v) => v == null || v.isNaN || v <= 0 || v > 100
                ? t('dawam.amountRequired')
                : null,
          )
        else
          DashMoneyField(
            key: const ValueKey('adj-amount'),
            label: t('dawam.amountEgp'),
            value: _amount == null ? null : egpToPiastres(_amount!),
            allowEmpty: true,
            onChanged: (p) => setState(() => _amount = p == null ? null : p / 100),
            validator: (p) =>
                p == null || p <= 0 ? t('dawam.amountRequired') : null,
          ),
        _text(
          label: t('staff.reason'),
          value: _reason,
          onChanged: (v) => setState(() => _reason = v),
          description: t('dawam.reasonShown'),
          validator: (v) =>
              v.trim().isEmpty ? t('dawam.reasonRequired') : null,
        ),
        MoneyMonthField(
          label: _recurring
              ? t('dawam.recurringFrom')
              : t('dawam.effectiveMonth'),
          value: month,
          description: t('dawam.monthHint'),
          onChanged: (v) => setState(() => _month = v),
          validator: (v) => RegExp(r'^\d{4}-\d{2}$').hasMatch(v)
              ? null
              : t('dawam.monthRequired'),
        ),
        DashCard(
          padding: const EdgeInsets.all(Space.md),
          child: DashSwitchField(
            label: t('dawam.everyMonth'),
            description: t('dawam.everyMonthHint'),
            value: _recurring,
            onChanged: (v) => setState(() => _recurring = v),
          ),
        ),
      ],
    );
  }
}

// ── salary advance (TEAM-MNY-020) ───────────────────────────────────────

/// "Record a salary advance": recorded and approved in one call.
Future<bool> showRecordAdvanceDialog(BuildContext context) =>
    _show(context, const RecordAdvanceDialog());

class RecordAdvanceDialog extends ConsumerStatefulWidget {
  const RecordAdvanceDialog({super.key});

  @override
  ConsumerState<RecordAdvanceDialog> createState() =>
      _RecordAdvanceDialogState();
}

String? _installmentsProblem(Translator t, double? v) =>
    v == null || v.isNaN || v != v.roundToDouble() || v < 1 || v > 24
    ? t('dawam.installmentsHint')
    : null;

class _RecordAdvanceDialogState extends ConsumerState<RecordAdvanceDialog>
    with _MoneyForm {
  String? _employee;
  int? _amount;
  double? _installments = 1;
  String _reason = '';

  Future<void> _save() => submit(() async {
    await ref
        .read(apiProvider)
        .staff
        .recordAdvance(
          body: RecordAdvance(
            employeeId: _employee!,
            amountPiastres: _amount!,
            installments: _installments!.round(),
            reason: _reason.trim().isEmpty ? null : _reason.trim(),
            explicitNulls: {if (_reason.trim().isEmpty) 'reason'},
          ),
        );
    if (mounted) DashToast.success(context, t('dawam.advanceRecorded'));
  });

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    return frame(
      title: t('dawam.recordAdvance'),
      description: t('dawam.recordAdvanceHint'),
      onSave: _save,
      fields: [
        MoneyPersonField(
          value: _employee,
          onChanged: (v) => setState(() => _employee = v),
        ),
        DashMoneyField(
          label: t('dawam.amountEgp'),
          value: _amount,
          allowEmpty: true,
          onChanged: (p) => setState(() => _amount = p),
          validator: (p) =>
              p == null || p <= 0 ? t('dawam.amountRequired') : null,
        ),
        DashNumberField(
          label: t('dawam.installments'),
          description: t('dawam.installmentsHint'),
          value: _installments,
          stepper: true,
          allowEmpty: true,
          onChanged: (v) => setState(() => _installments = v),
          validator: (v) => _installmentsProblem(t, v),
        ),
        _text(
          label: t('dawam.whatFor'),
          value: _reason,
          onChanged: (v) => setState(() => _reason = v),
        ),
      ],
    );
  }
}

// ── expense advance (TEAM-MNY-030) ──────────────────────────────────────

/// "Log an expense advance": a log only, never deducted.
Future<bool> showExpenseAdvanceDialog(BuildContext context) =>
    _show(context, const ExpenseAdvanceDialog());

class ExpenseAdvanceDialog extends ConsumerStatefulWidget {
  const ExpenseAdvanceDialog({super.key});

  @override
  ConsumerState<ExpenseAdvanceDialog> createState() =>
      _ExpenseAdvanceDialogState();
}

class _ExpenseAdvanceDialogState extends ConsumerState<ExpenseAdvanceDialog>
    with _MoneyForm {
  String? _employee;
  int? _amount;
  String _purpose = '';
  String _via = 'safe';
  late String? _givenOn = teamTodayIsoOf(ref);
  String? _branch;

  Future<void> _save() => submit(() async {
    await ref
        .read(apiProvider)
        .staff
        .logExpenseAdvance(
          body: NewExpenseAdvance(
            employeeId: _employee!,
            amountPiastres: _amount!,
            purpose: _purpose.trim(),
            via: _via,
            givenOn: _givenOn,
            branchId: _branch,
          ),
        );
    if (mounted) DashToast.success(context, t('dawam.expenseLogged'));
  });

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final branches = ref.watch(branchesProvider).value ?? const <Branch>[];
    final today = dashParseYmd(teamTodayIsoOf(ref));
    return frame(
      title: t('dawam.logExpense'),
      description: t('dawam.logExpenseHint'),
      onSave: _save,
      fields: [
        MoneyPersonField(
          value: _employee,
          onChanged: (v) => setState(() => _employee = v),
        ),
        DashMoneyField(
          label: t('dawam.amountEgp'),
          value: _amount,
          allowEmpty: true,
          onChanged: (p) => setState(() => _amount = p),
          validator: (p) =>
              p == null || p <= 0 ? t('dawam.amountRequired') : null,
        ),
        _text(
          label: t('dawam.purpose'),
          value: _purpose,
          onChanged: (v) => setState(() => _purpose = v),
          validator: (v) =>
              v.trim().isEmpty ? t('dawam.purposeRequired') : null,
        ),
        DashDateFormField(
          label: t('dawam.givenOn'),
          value: dashParseYmd(_givenOn),
          today: today,
          onChanged: (d) => setState(() => _givenOn = dashYmd(d)),
          validator: (d) => d == null ? t('dawam.dateRequired') : null,
        ),
        DashSelectField<String>(
          label: t('dawam.givenAt'),
          placeholder: t('dawam.pickBranch'),
          value: _branch,
          onChanged: (v) => setState(() => _branch = v),
          options: [
            for (final b in branches) DashOption(value: b.id, label: b.name),
          ],
          validator: (v) =>
              v == null || v.isEmpty ? t('dawam.pickBranch') : null,
        ),
        DashSegmentedControl<String>(
          value: _via,
          onChanged: (v) => setState(() => _via = v),
          options: [
            DashOption(value: 'safe', label: t('dawam.viaSafe')),
            DashOption(value: 'bank', label: t('dawam.viaBank')),
          ],
        ),
      ],
    );
  }
}

// ── correct a till tag (TEAM-MNY-031) ───────────────────────────────────

/// "Correct {{name}}'s till tag": clear it, or move it to the person who
/// really took the cash, with why.
Future<bool> showCorrectExpenseTagDialog(
  BuildContext context, {
  required ExpenseAdvance expense,
}) => _show(context, CorrectExpenseTagDialog(expense: expense));

class CorrectExpenseTagDialog extends ConsumerStatefulWidget {
  const CorrectExpenseTagDialog({required this.expense, super.key});

  final ExpenseAdvance expense;

  @override
  ConsumerState<CorrectExpenseTagDialog> createState() =>
      _CorrectExpenseTagDialogState();
}

class _CorrectExpenseTagDialogState
    extends ConsumerState<CorrectExpenseTagDialog>
    with _MoneyForm {
  String _action = 'reassign';
  String? _employee;
  String _reason = '';

  @override
  ReasonFor? get reasonFor => ReasonFor.correctAdvance;

  Future<void> _save() => submit(() async {
    final api = ref.read(apiProvider).staff;
    final x = widget.expense;
    if (_action == 'clear') {
      await api.clearExpenseAdvance(id: x.id, reason: _reason.trim());
      if (mounted) DashToast.success(context, t('dawam.tagCleared'));
    } else {
      await api.reassignExpenseAdvance(
        id: x.id,
        body: ReassignExpenseAdvance(
          employeeId: _employee!,
          reason: _reason.trim(),
        ),
      );
      if (mounted) DashToast.success(context, t('dawam.tagReassigned'));
    }
  });

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    return frame(
      title: t(
        'dawam.correctTagTitle',
        args: {'name': widget.expense.employeeName},
      ),
      description: t('dawam.correctTagHint'),
      onSave: _save,
      fields: [
        DashSegmentedControl<String>(
          value: _action,
          onChanged: (v) => setState(() => _action = v),
          options: [
            DashOption(value: 'reassign', label: t('dawam.reassignTag')),
            DashOption(value: 'clear', label: t('dawam.clearTag')),
          ],
        ),
        if (_action == 'reassign')
          MoneyPersonField(
            value: _employee,
            onChanged: (v) => setState(() => _employee = v),
            validator: (v) =>
                v == null || v.isEmpty || v == widget.expense.employeeId
                ? t('dawam.pickSomeoneElse')
                : null,
          ),
        _text(
          label: t('staff.reason'),
          value: _reason,
          onChanged: (v) => setState(() => _reason = v),
          validator: (v) =>
              v.trim().isEmpty ? t('dawam.reasonRequired') : null,
        ),
      ],
    );
  }
}

// ── mark paid (TEAM-MNY-032) ────────────────────────────────────────────

/// Who is being marked paid.
class MarkPaidPerson {
  const MarkPaidPerson({
    required this.employeeId,
    required this.name,
    this.payMethod,
    this.net,
  });

  final String employeeId;
  final String name;
  final String? payMethod;
  final int? net;
}

/// "Mark {{name}} paid"; [first] when nobody is paid by hand yet (this
/// payment ends reopening).
Future<bool> showMarkPaidDialog(
  BuildContext context, {
  required String periodId,
  required MarkPaidPerson person,
  bool first = false,
}) => _show(
  context,
  MarkPaidDialog(periodId: periodId, person: person, first: first),
);

class MarkPaidDialog extends ConsumerStatefulWidget {
  const MarkPaidDialog({
    required this.periodId,
    required this.person,
    this.first = false,
    super.key,
  });

  final String periodId;
  final MarkPaidPerson person;
  final bool first;

  @override
  ConsumerState<MarkPaidDialog> createState() => _MarkPaidDialogState();
}

class _MarkPaidDialogState extends ConsumerState<MarkPaidDialog>
    with _MoneyForm {
  late String _method = payMethods.contains(widget.person.payMethod)
      ? widget.person.payMethod!
      : 'cash';

  Future<void> _save() => submit(() async {
    await ref
        .read(apiProvider)
        .staff
        .markPaid(
          id: widget.periodId,
          employeeId: widget.person.employeeId,
          body: MarkPaid(method: _method),
        );
    if (mounted) DashToast.success(context, t('dawam.markedPaid'));
  });

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final p = widget.person;
    final description = [
      if (p.net != null)
        t(
          'dawamOps.markPaidAmount',
          args: {'amount': f.fmtMoney(p.net), 'name': p.name},
        ),
      widget.first ? t('dawamOps.markPaidFirst') : t('dawam.markPaidHint'),
    ].join(' ');
    return frame(
      title: t('dawam.markPaidTitle', args: {'name': p.name}),
      description: description,
      saveLabel: t('dawam.markPaid'),
      onSave: _save,
      fields: [
        DashSegmentedControl<String>(
          value: _method,
          onChanged: (v) => setState(() => _method = v),
          options: [
            for (final m in payMethods)
              DashOption(value: m, label: t('dawam.pay_$m')),
          ],
        ),
      ],
    );
  }
}

// ── the reason forms (TEAM-MNY-033 … -037) ──────────────────────────────

/// A one-field reason form shared by reject, waive, un-waive, stop and
/// reopen (`ReasonDialog`).
class ReasonDialog extends ConsumerStatefulWidget {
  const ReasonDialog({
    required this.title,
    required this.description,
    required this.saveLabel,
    required this.onSave,
    required this.done,
    this.destructive = false,
    this.reasonFor,
    this.optional = false,
    this.hint,
    this.child,
    super.key,
  });

  final String title;
  final String description;
  final String saveLabel;
  final Future<Object?> Function(String reason) onSave;

  /// The success toast.
  final String done;
  final bool destructive;
  final ReasonFor? reasonFor;

  /// The reason may be left empty (a request's rejection note).
  final bool optional;

  /// Under the reason: who reads it.
  final String? hint;

  /// What the decision does, above the reason.
  final Widget? child;

  @override
  ConsumerState<ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends ConsumerState<ReasonDialog> with _MoneyForm {
  String _reason = '';

  @override
  ReasonFor? get reasonFor => widget.reasonFor;

  Future<void> _save() => submit(() async {
    await widget.onSave(_reason.trim());
    if (mounted) DashToast.success(context, widget.done);
  });

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    return frame(
      title: widget.title,
      description: widget.description,
      saveLabel: widget.saveLabel,
      destructive: widget.destructive,
      onSave: _save,
      fields: [
        ?widget.child,
        DashTextField(
          label: widget.optional
              ? t('dawamOps.reasonOptional')
              : t('staff.reason'),
          value: _reason,
          description: widget.hint,
          onChanged: (v) => setState(() => _reason = v),
          maxLength: widget.optional ? null : 500,
          validator: (v) => widget.optional
              ? (v.trim().length > 500 ? t('staff.noteTooLong') : null)
              : (v.trim().isEmpty ? t('dawam.reasonRequired') : null),
        ),
      ],
    );
  }
}

/// Reject an advance, a pay line or a request, with why (`RejectDialog`):
/// required unless [optional] (a request's note); destructive "Reject";
/// toast "Decision saved".
Future<bool> showRejectDialog(
  BuildContext context, {
  required String title,
  required String description,
  required Future<Object?> Function(String reason) onReject,
  bool optional = false,
  Widget? child,
}) {
  final t = ProviderScope.containerOf(context).read(tProvider);
  return _show(
    context,
    ReasonDialog(
      title: title,
      description: description,
      saveLabel: t('common.reject'),
      destructive: true,
      onSave: onReject,
      reasonFor: ReasonFor.decline,
      optional: optional,
      hint: t('dawamOps.reasonSeen'),
      done: t('staff.decisionSaved'),
      child: child,
    ),
  );
}

/// Waive a rule-made deduction (`WaiveDialog`).
Future<bool> showWaiveDialog(
  BuildContext context, {
  required String deductionId,
  required String label,
}) {
  final c = ProviderScope.containerOf(context);
  final t = c.read(tProvider);
  return _show(
    context,
    ReasonDialog(
      title: t('dawam.waiveTitle', args: {'line': label}),
      description: t('dawam.waiveHint'),
      saveLabel: t('dawam.waive'),
      onSave: (reason) => c
          .read(apiProvider)
          .staff
          .waiveDeduction(
            id: deductionId,
            body: WaiveDeductionRequest(reason: reason),
          ),
      done: t('dawam.waived'),
    ),
  );
}

/// Undo a waiver (`UnwaiveDialog`).
Future<bool> showUnwaiveDialog(
  BuildContext context, {
  required String deductionId,
  required String label,
}) {
  final c = ProviderScope.containerOf(context);
  final t = c.read(tProvider);
  return _show(
    context,
    ReasonDialog(
      title: t('dawam.unwaiveTitle', args: {'line': label}),
      description: t('dawam.unwaiveHint'),
      saveLabel: t('dawam.unwaive'),
      onSave: (reason) => c
          .read(apiProvider)
          .staff
          .unwaiveDeduction(
            id: deductionId,
            body: WaiveDeductionRequest(reason: reason),
          ),
      done: t('dawam.unwaived'),
    ),
  );
}

/// Stop a monthly line from next month (`StopDialog`).
Future<bool> showStopDialog(
  BuildContext context, {
  required String kind,
  required String id,
  required String line,
}) {
  final c = ProviderScope.containerOf(context);
  final t = c.read(tProvider);
  return _show(
    context,
    ReasonDialog(
      title: t('dawam.stopTitle', args: {'line': line}),
      description: t('dawam.stopHint'),
      saveLabel: t('dawam.stop'),
      destructive: true,
      reasonFor: ReasonFor.stopLine,
      onSave: (reason) => c
          .read(apiProvider)
          .staff
          .stopAdjustment(
            kind: kind,
            id: id,
            body: StopAdjustment(reason: reason),
          ),
      done: t('dawam.stoppedToast'),
    ),
  );
}

/// Reopen an approved month (`ReopenDialog`).
Future<bool> showReopenDialog(
  BuildContext context, {
  required String periodId,
}) {
  final c = ProviderScope.containerOf(context);
  final t = c.read(tProvider);
  return _show(
    context,
    ReasonDialog(
      title: t('dawam.reopenTitle'),
      description: '${t('dawam.reopenHint')} ${t('dawam.reopenReason')}',
      saveLabel: t('dawam.reopen'),
      destructive: true,
      onSave: (reason) => c
          .read(apiProvider)
          .staff
          .setPeriodStatus(
            id: periodId,
            body: PeriodStatusRequest(status: 'draft', reason: reason),
          ),
      done: t('dawam.reopened'),
    ),
  );
}

// ── override (TEAM-MNY-038) ─────────────────────────────────────────────

/// Override a rule-made deduction's amount; [current] is its piastres.
Future<bool> showOverrideDialog(
  BuildContext context, {
  required String deductionId,
  required String label,
  required int current,
}) => _show(
  context,
  OverrideDialog(deductionId: deductionId, label: label, current: current),
);

class OverrideDialog extends ConsumerStatefulWidget {
  const OverrideDialog({
    required this.deductionId,
    required this.label,
    required this.current,
    super.key,
  });

  final String deductionId;
  final String label;
  final int current;

  @override
  ConsumerState<OverrideDialog> createState() => _OverrideDialogState();
}

class _OverrideDialogState extends ConsumerState<OverrideDialog>
    with _MoneyForm {
  late int? _amount = widget.current;
  String _reason = '';

  Future<void> _save() => submit(() async {
    await ref
        .read(apiProvider)
        .staff
        .overrideDeduction(
          id: widget.deductionId,
          body: OverrideDeductionRequest(
            amountPiastres: _amount!,
            reason: _reason.trim(),
          ),
        );
    if (mounted) DashToast.success(context, t('dawam.overridden'));
  });

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    return frame(
      title: t('dawam.overrideTitle', args: {'line': widget.label}),
      description: t('dawam.overrideHint'),
      saveLabel: t('dawam.override'),
      onSave: _save,
      fields: [
        DashMoneyField(
          label: t('dawam.newAmount'),
          value: _amount,
          allowEmpty: true,
          onChanged: (p) => setState(() => _amount = p),
          validator: (p) =>
              p == null || p < 0 ? t('dawam.amountRequired') : null,
        ),
        _text(
          label: t('staff.reason'),
          value: _reason,
          onChanged: (v) => setState(() => _reason = v),
          validator: (v) =>
              v.trim().isEmpty ? t('dawam.reasonRequired') : null,
        ),
      ],
    );
  }
}

// ── approve an advance (TEAM-MNY-039) ───────────────────────────────────

/// "Approve {{name}}'s advance", changing the amount or installments when
/// needed.
Future<bool> showReviewAdvanceDialog(
  BuildContext context, {
  required SalaryAdvance advance,
}) => _show(context, ReviewAdvanceDialog(advance: advance));

class ReviewAdvanceDialog extends ConsumerStatefulWidget {
  const ReviewAdvanceDialog({required this.advance, super.key});

  final SalaryAdvance advance;

  @override
  ConsumerState<ReviewAdvanceDialog> createState() =>
      _ReviewAdvanceDialogState();
}

class _ReviewAdvanceDialogState extends ConsumerState<ReviewAdvanceDialog>
    with _MoneyForm {
  late int? _amount = widget.advance.amountPiastres;
  late double? _installments = widget.advance.installments.toDouble();
  String _note = '';

  Future<void> _save() => submit(() async {
    final a = widget.advance;
    // Sent as approved: only what changed differs from the request.
    final amount = _amount!;
    final changed = amount != a.amountPiastres;
    await ref
        .read(apiProvider)
        .staff
        .reviewAdvance(
          id: a.id,
          body: ReviewAdvance(
            approve: true,
            amountPiastres: changed ? amount : null,
            installments: _installments!.round(),
            note: _note.trim().isEmpty ? null : _note.trim(),
            explicitNulls: {
              if (!changed) 'amount_piastres',
              if (_note.trim().isEmpty) 'note',
            },
          ),
        );
    if (mounted) DashToast.success(context, t('staff.decisionSaved'));
  });

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    return frame(
      title: t(
        'dawam.reviewAdvance',
        args: {'name': widget.advance.employeeName ?? ''},
      ),
      description: t('dawam.reviewAdvanceHint'),
      saveLabel: t('common.approve'),
      onSave: _save,
      fields: [
        DashMoneyField(
          label: t('dawam.amountEgp'),
          value: _amount,
          allowEmpty: true,
          onChanged: (p) => setState(() => _amount = p),
          validator: (p) =>
              p == null || p <= 0 ? t('dawam.amountRequired') : null,
        ),
        DashNumberField(
          label: t('dawam.installments'),
          value: _installments,
          stepper: true,
          allowEmpty: true,
          onChanged: (v) => setState(() => _installments = v),
          validator: (v) => _installmentsProblem(t, v),
        ),
        _text(
          label: t('staff.note'),
          value: _note,
          onChanged: (v) => setState(() => _note = v),
        ),
      ],
    );
  }
}

// ── the cap note (TEAM-MNY-040) ─────────────────────────────────────────

/// "Within cap" / "Over cap" (or "only the owner can approve" for someone
/// who may not pass it), with the figures only when the server sends the
/// cap; nothing when it is unknown.
class AdvanceCapNote extends ConsumerWidget {
  const AdvanceCapNote({
    required this.advance,
    required this.mayPassCap,
    super.key,
  });

  final SalaryAdvance advance;

  /// The owner (`canEverywhere(hr.payroll.run)`).
  final bool mayPassCap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final v = capView(advance);
    final within = v.within;
    if (within == null) return const SizedBox.shrink();
    return Wrap(
      spacing: Space.xs,
      runSpacing: Space.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        DashStatusPill(
          tone: within ? DashTone.success : DashTone.warning,
          label: within
              ? t('dawam.withinCap')
              : mayPassCap
              ? t('dawam.overCap')
              : t('dawam.overCapOwner'),
        ),
        if (v.cap != null)
          Text(
            t(
              'dawam.capFigures',
              args: {'owed': f.fmtMoney(v.owed), 'cap': f.fmtMoney(v.cap)},
            ),
            style: DashType.small.copyWith(color: c.textSecondary),
          ),
      ],
    );
  }
}
