/// One employee's profile (`staff/employee-dialog.tsx`, TEAM-EMP-016…029):
/// the employee's own name, WhatsApp number, staff-app access and branches,
/// their HR fields, and — for whoever sets pay (`hr.payroll.edit` at every
/// branch) — "paid through Dawam" and the salary with its calculator. A new
/// number, app access off, or any status but active signs their phone out
/// (RO-10), and the dialog says so before saving.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show Branch, Employee, PutEmployeeRequest;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/attendance_errors.dart';
import '../shared/team_format.dart';
import 'employee_fields.dart';
import 'employees_data.dart';
import 'employees_providers.dart';

/// Opens [e]'s profile: a centred dialog, full screen on a phone.
Future<void> showEmployeeDialog(BuildContext context, Employee e) =>
    showDashDialog<void>(
      context,
      width: DashMetrics.dialogWide,
      builder: (_) => EmployeeDialog(employee: e),
    );

/// Signs [e]'s phone out after the destructive confirm (TEAM-EMP-011/029):
/// the phone is refused on its next request. True when it was.
Future<bool> revokeEmployeePhone(
  BuildContext context,
  WidgetRef ref,
  Employee e,
) async {
  final t = ref.read(tProvider);
  final ok = await showDashConfirm(
    context,
    title: t('dawam.revokeTitle', args: {'name': e.name}),
    description: t('dawam.revokeHint'),
    confirmLabel: t('dawam.revokePhoneShort'),
    cancelLabel: t('common.cancel'),
    destructive: true,
  );
  if (!ok || !context.mounted) return false;
  final staff = staffInvalidator(ref);
  final api = ref.read(apiProvider);
  final f = ref.read(formatProvider);
  try {
    await api.staff.revokeDevice(employeeId: e.id);
    staff.invalidateEmployees();
    if (context.mounted) DashToast.success(context, t('dawam.phoneRevoked'));
    return true;
  } on Object catch (err) {
    if (context.mounted) {
      DashToast.error(context, attendanceErrorText(err, t, f));
    }
    return false;
  }
}

class EmployeeDialog extends ConsumerStatefulWidget {
  const EmployeeDialog({required this.employee, super.key});

  final Employee employee;

  @override
  ConsumerState<EmployeeDialog> createState() => _EmployeeDialogState();
}

const String _none = '__none__';

class _EmployeeDialogState extends ConsumerState<EmployeeDialog> {
  Employee get e => widget.employee;

  // The form, reset from the row each time it opens.
  late String _name = e.name;
  late String _phone = e.phone ?? '';
  late bool _appAccess = e.appAccess;
  late List<String> _branchIds = [...e.branchIds];
  late String _departmentId = e.departmentId ?? _none;
  late String _employeeCode = e.employeeCode ?? '';
  late String _jobTitle = e.jobTitle ?? '';
  late String _hireDate = e.hireDate ?? '';
  late String _status =
      const {'active', 'suspended', 'terminated'}.contains(e.employmentStatus)
      ? e.employmentStatus
      : 'active';
  late String _terminationDate = e.terminationDate ?? '';
  late String _salary = e.baseSalaryPiastres == null
      ? ''
      : egpText(e.baseSalaryPiastres!);
  late String _nationalId = e.nationalId ?? '';
  late String _emergencyName = e.emergencyContactName ?? '';
  late String _emergencyPhone = e.emergencyContactPhone ?? '';
  late String _notes = e.notes ?? '';
  late String _gender = e.gender == 'm' || e.gender == 'f' ? e.gender! : _none;
  late String _payMethod = const {'cash', 'bank', 'wallet'}.contains(e.payMethod)
      ? e.payMethod
      : 'cash';
  late String _payAccount = e.payAccount ?? '';
  late bool _onPayroll = e.onPayroll;

  bool _submitted = false;
  bool _busy = false;

  /// The form's problems, by field (the web's zod schema).
  Map<String, String> _problems(Translator t) {
    String atMost(int n) => t('common.atMostChars', args: {'n': n});
    final p = <String, String>{};
    void max(String field, String v, int n) {
      if (v.runes.length > n) p[field] = atMost(n);
    }

    if (_name.trim().isEmpty) {
      p['name'] = t('dawam.nameRequired');
    } else {
      max('name', _name, 120);
    }
    if (_phone.runes.length > phoneRawMax) {
      p['phone'] = atMost(phoneRawMax);
    } else if (_phone.trim().isNotEmpty && !isValidPhone(_phone)) {
      p['phone'] = t('dawam.badPhone');
    } else if (_appAccess && _phone.trim().isEmpty) {
      p['phone'] = t('dawam.phoneForApp');
    }
    if (_branchIds.isEmpty) p['branches'] = t('dawam.pickBranchError');
    max('employeeCode', _employeeCode, 64);
    max('jobTitle', _jobTitle, 120);
    if (_status == 'terminated' && _terminationDate.isEmpty) {
      p['terminationDate'] = t('staff.terminationDateRequired');
    }
    if (_salary.trim().isNotEmpty && readPounds(_salary) == null) {
      p['salary'] = t('dawam.badSalary');
    }
    max('nationalId', _nationalId, 64);
    max('emergencyName', _emergencyName, 120);
    max('emergencyPhone', _emergencyPhone, 40);
    max('notes', _notes, 2000);
    // Only checked where it is shown and sent (never a silent block).
    if (_payMethod != 'cash') max('payAccount', _payAccount, 64);
    return p;
  }

  Future<void> _save(bool canSeeSalary, bool canEditSalary) async {
    final t = ref.read(tProvider);
    setState(() => _submitted = true);
    if (_problems(t).isNotEmpty) return;
    // The server signs the phone in use out when the number changes or app
    // access is turned off: say so before saving, never after.
    final newPhone = _phone.trim().isEmpty ? '' : canonicalPhone(_phone)!;
    final oldPhone = e.phone == null ? '' : canonicalPhone(e.phone);
    final numberChanged = newPhone != oldPhone;
    final accessOff = e.appAccess && !_appAccess;
    final model = e.deviceModel;
    if (model != null && (numberChanged || accessOff)) {
      final ok = await showDashConfirm(
        context,
        title: t('dawam.revokeTitle', args: {'name': e.name}),
        description: numberChanged
            ? t('dawam.signOutOnNewNumber', args: {'model': model})
            : t('dawam.signOutOnAccessOff', args: {'model': model}),
        confirmLabel: t('dawam.saveAndSignOut'),
        cancelLabel: t('common.cancel'),
        destructive: true,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    final staff = staffInvalidator(ref);
    final f = ref.read(formatProvider);
    String? orNull(String v) => v.isEmpty ? null : v;
    final terminated = _status == 'terminated';
    try {
      await ref
          .read(apiProvider)
          .staff
          .putEmployee(
            employeeId: e.id,
            body: PutEmployeeRequest(
              name: _name.trim(),
              // Empty clears it; the server signs the old phone out.
              phone: newPhone,
              appAccess: _appAccess,
              branchIds: _branchIds,
              departmentId: _departmentId == _none ? null : _departmentId,
              employeeCode: orNull(_employeeCode),
              jobTitle: orNull(_jobTitle),
              hireDate: orNull(_hireDate),
              employmentStatus: _status,
              terminationDate: terminated ? _terminationDate : null,
              // Omitted unless the caller sees the salary and typed one, so
              // the server keeps the stored figure.
              baseSalaryPiastres: canSeeSalary && _salary.trim().isNotEmpty
                  ? readPounds(_salary)
                  : null,
              onPayroll: canEditSalary ? _onPayroll : null,
              nationalId: orNull(_nationalId),
              emergencyContactName: orNull(_emergencyName),
              emergencyContactPhone: orNull(_emergencyPhone),
              notes: orNull(_notes),
              gender: _gender == _none ? null : _gender,
              payMethod: _payMethod,
              payAccount: _payMethod == 'cash' ? null : orNull(_payAccount),
              explicitNulls: const {
                'department_id',
                'employee_code',
                'job_title',
                'hire_date',
                'termination_date',
                'national_id',
                'emergency_contact_name',
                'emergency_contact_phone',
                'notes',
                'gender',
                'pay_account',
              },
            ),
          );
      staff.invalidateEmployees();
      if (!mounted) return;
      DashToast.success(context, t('staff.employeeSaved'));
      Navigator.of(context).pop();
    } on Object catch (err) {
      if (!mounted) return;
      DashToast.error(context, attendanceErrorText(err, t, f));
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final authz = ref.watch(authzProvider);
    final canRevoke = authz.can(Cap.hrStaffEdit);
    // Shown and sent only to someone who may set it: the server ignores it
    // from anyone else, and an ignored box is a lie.
    final canEditSalary = authz.canEverywhere(Cap.hrPayrollEdit);
    final salary = salaryStateOf(e);
    final canSeeSalary = canEditSalary && salary != SalaryState.hidden;
    final departments = ref.watch(staffDepartmentsProvider).value ?? const [];
    final branches = ref.watch(branchesProvider).value ?? const <Branch>[];
    final problems = _submitted ? _problems(t) : const <String, String>{};
    final mode = DashSurfaceScope.maybeOf(context) ?? DashSurfaceMode.dialog;
    final model = e.deviceModel;
    final today = dashParseYmd(teamTodayIsoOf(ref));

    DashOption<String> opt(String v, String label) =>
        DashOption(value: v, label: label);
    Widget text(
      String label,
      String value,
      ValueChanged<String> onChanged,
      String field, {
      String? placeholder,
      TextDirection? dir,
      TextInputType? keyboard,
      String? description,
    }) => DashTextField(
      label: label,
      value: value,
      placeholder: placeholder,
      textDirection: dir,
      keyboardType: keyboard,
      description: description,
      errorText: problems[field],
      onChanged: (v) => setState(() => onChanged(v)),
    );
    Widget date(
      String label,
      String value,
      ValueChanged<String> onChanged, [
      String? field,
    ]) => EmployeeDateField(
      label: label,
      value: value,
      today: today,
      errorText: field == null ? null : problems[field],
      onChanged: (v) => setState(() => onChanged(v)),
    );

    // (widget, spans both columns)
    final items = <(Widget, bool)>[
      (text(t('staff.name'), _name, (v) => _name = v, 'name'), false),
      (
        PhoneField(
          label: t('dawam.whatsapp'),
          value: _phone,
          errorText: problems['phone'],
          onChanged: (v) => setState(() => _phone = v),
        ),
        false,
      ),
      (
        DashCheckboxField(
          label: t('dawam.appAccessLabel'),
          description: model != null
              ? t(
                  'dawam.deviceSince',
                  args: {'model': model, 'since': f.fmtDate(e.deviceSince)},
                )
              : t('dawam.noDevice'),
          value: _appAccess,
          onChanged: (v) => setState(() => _appAccess = v),
        ),
        true,
      ),
      (
        BranchChecklist(
          label: t('dawam.branches'),
          branches: branches,
          value: _branchIds,
          errorText: problems['branches'],
          onChanged: (v) => setState(() => _branchIds = v),
        ),
        true,
      ),
      (
        text(
          t('staff.jobTitle'),
          _jobTitle,
          (v) => _jobTitle = v,
          'jobTitle',
          placeholder: t('staff.jobTitlePlaceholder'),
        ),
        false,
      ),
      (
        text(
          t('staff.employeeCode'),
          _employeeCode,
          (v) => _employeeCode = v,
          'employeeCode',
          placeholder: 'EMP-001',
        ),
        false,
      ),
      (
        DashSelectField<String>(
          label: t('staff.department'),
          value: _departmentId,
          options: [
            opt(_none, t('staff.noDepartment')),
            for (final d in departments) opt(d.id, d.name),
          ],
          onChanged: (v) => setState(() => _departmentId = v),
        ),
        false,
      ),
      (date(t('staff.hireDate'), _hireDate, (v) => _hireDate = v), false),
      (
        DashSelectField<String>(
          label: t('staff.employmentStatus'),
          value: _status,
          description: t('staff.suspendedCannotClockIn'),
          options: [
            opt('active', t('staff.statusActive')),
            opt('suspended', t('staff.statusSuspended')),
            opt('terminated', t('staff.statusTerminated')),
          ],
          onChanged: (v) => setState(() => _status = v),
        ),
        false,
      ),
      if (_status == 'terminated')
        (
          date(
            t('staff.terminationDate'),
            _terminationDate,
            (v) => _terminationDate = v,
            'terminationDate',
          ),
          false,
        ),
      if (canEditSalary)
        (
          DashCheckboxField(
            label: t('dawam.onPayroll'),
            description: t('dawam.onPayrollHint'),
            value: _onPayroll,
            onChanged: (v) => setState(() => _onPayroll = v),
          ),
          true,
        ),
      if (canSeeSalary)
        (
          SalaryCalculator(
            label: t('staff.baseSalary'),
            monthly: _salary,
            onMonthly: (v) => setState(() => _salary = v),
            placeholder: salary == SalaryState.notSet
                ? t('dawam.notSet')
                : null,
            hireDate: _hireDate.isEmpty ? null : _hireDate,
            onlyOpenPeriod: true,
            errorText: problems['salary'],
            description: salary == SalaryState.notSet
                ? t('dawam.salaryNotSetHint')
                : null,
          ),
          true,
        ),
      (
        DashSelectField<String>(
          label: t('dawam.gender'),
          value: _gender,
          description: t('dawam.genderSuggestHint'),
          options: [
            opt(_none, t('dawam.notSet')),
            opt('f', t('dawam.gender_f')),
            opt('m', t('dawam.gender_m')),
          ],
          onChanged: (v) => setState(() => _gender = v),
        ),
        false,
      ),
      (
        DashSelectField<String>(
          label: t('dawam.payMethod'),
          value: _payMethod,
          options: [
            opt('cash', t('dawam.pay_cash')),
            opt('bank', t('dawam.pay_bank')),
            opt('wallet', t('dawam.pay_wallet')),
          ],
          onChanged: (v) => setState(() => _payMethod = v),
        ),
        false,
      ),
      if (_payMethod != 'cash')
        (
          text(
            _payMethod == 'bank' ? t('dawam.iban') : t('dawam.walletNumber'),
            _payAccount,
            (v) => _payAccount = v,
            'payAccount',
            dir: TextDirection.ltr,
            description: t('dawam.payAccountHint'),
          ),
          false,
        ),
      (
        text(
          t('staff.nationalId'),
          _nationalId,
          (v) => _nationalId = v,
          'nationalId',
          dir: TextDirection.ltr,
          keyboard: TextInputType.number,
        ),
        false,
      ),
      (
        text(
          t('staff.emergencyName'),
          _emergencyName,
          (v) => _emergencyName = v,
          'emergencyName',
        ),
        false,
      ),
      (
        text(
          t('staff.emergencyPhone'),
          _emergencyPhone,
          (v) => _emergencyPhone = v,
          'emergencyPhone',
          dir: TextDirection.ltr,
          keyboard: TextInputType.phone,
        ),
        false,
      ),
      (text(t('staff.notes'), _notes, (v) => _notes = v, 'notes'), true),
    ];

    final revoke = canRevoke && model != null
        ? DashButton(
            label: t('dawam.revokePhoneShort'),
            variant: DashButtonVariant.outline,
            onPressed: () => revokeEmployeePhone(context, ref, e),
          )
        : null;
    final cancel = DashButton(
      label: t('common.cancel'),
      variant: DashButtonVariant.ghost,
      onPressed: () => Navigator.of(context).maybePop(),
    );
    final save = DashButton(
      label: t('common.save'),
      loading: _busy,
      onPressed: _busy ? null : () => _save(canSeeSalary, canEditSalary),
    );

    return DashSurface(
      title: e.name,
      description: e.userId != null
          ? t('staff.employeeDialogLinked')
          : t('staff.employeeDialogUnlinked'),
      body: _Grid(
        twoColumns: MediaQuery.sizeOf(context).width >= DashBreakpoints.sm,
        items: items,
      ),
      actions: revoke == null || mode == DashSurfaceMode.fullScreen
          ? [?revoke, cancel, save]
          : [
              Row(
                spacing: Space.sm,
                children: [revoke, const Spacer(), cancel, save],
              ),
            ],
    );
  }
}

/// The form's `grid sm:grid-cols-2`: halves fill a row two at a time, a
/// full-width item starts its own row (CSS grid's sparse auto-placement).
class _Grid extends StatelessWidget {
  const _Grid({required this.items, required this.twoColumns});

  final List<(Widget, bool)> items;
  final bool twoColumns;

  @override
  Widget build(BuildContext context) {
    if (!twoColumns) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [for (final i in items) i.$1],
      );
    }
    final rows = <Widget>[];
    Widget? half;
    void flush() {
      if (half == null) return;
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.lg,
          children: [Expanded(child: half!), const Spacer()],
        ),
      );
      half = null;
    }

    for (final (w, full) in items) {
      if (full) {
        flush();
        rows.add(w);
      } else if (half == null) {
        half = w;
      } else {
        rows.add(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.lg,
            children: [Expanded(child: half!), Expanded(child: w)],
          ),
        );
        half = null;
      }
    }
    flush();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: rows,
    );
  }
}
