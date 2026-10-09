/// Adding one person (`dawam/add-employees.tsx` `AddEmployeeDialog`,
/// TEAM-EMP-030…040). Three kinds: `app` signs in to the staff app with a
/// WhatsApp code, `manual` is on the records only, `linked` makes an existing
/// Madar user an employee. Creating an employee never creates a POS user.
/// Salary is asked only of someone who may set it (`hr.payroll.edit` at
/// every branch). Opened from the Employees header and empty state, Set-up
/// step 2, the Team header and (with [userId]) the Users page.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show Branch, CreateEmployeeRequest, LinkableUser;
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

/// Opens "Add employee" (or "Make employee" for the Madar user [userId]).
Future<void> showAddEmployeeDialog(BuildContext context, {String? userId}) =>
    showDashDialog<void>(
      context,
      builder: (_) => AddEmployeeDialog(userId: userId),
    );

class AddEmployeeDialog extends ConsumerStatefulWidget {
  const AddEmployeeDialog({this.userId, super.key});

  /// Preset: make this Madar user an employee (from the Users page).
  final String? userId;

  @override
  ConsumerState<AddEmployeeDialog> createState() => _AddEmployeeDialogState();
}

class _AddEmployeeDialogState extends ConsumerState<AddEmployeeDialog> {
  late String _kind = widget.userId != null ? 'linked' : 'app';
  late String _userId = widget.userId ?? '';
  String _name = '';
  String _phone = '';
  bool _appAccess = false;
  List<String> _branchIds = const [];
  String _jobTitle = '';
  String _hireDate = '';
  String _salary = '';
  String _gender = '';

  /// Fields whose problems show (validated on change, `mode: "onChange"`).
  final Set<String> _shown = {};
  bool _submitting = false;

  bool get _needsPhone => _kind == 'app' || (_kind == 'linked' && _appAccess);

  Map<String, String> _problems(Translator t) {
    String atMost(int n) => t('common.atMostChars', args: {'n': n});
    final p = <String, String>{};
    if (_kind == 'linked' && _userId.isEmpty) {
      p['user'] = t('dawam.pickUserError');
    }
    if (_kind != 'linked' && _name.trim().isEmpty) {
      p['name'] = t('dawam.nameRequired');
    } else if (_name.runes.length > 120) {
      p['name'] = atMost(120);
    }
    if (_phone.runes.length > phoneRawMax) {
      p['phone'] = atMost(phoneRawMax);
    } else if (_phone.trim().isNotEmpty && !isValidPhone(_phone)) {
      p['phone'] = t('dawam.importBadPhone', args: {'value': _phone});
    } else if (_needsPhone && _phone.trim().isEmpty) {
      p['phone'] = t('dawam.phoneForApp');
    }
    if (_branchIds.isEmpty) p['branches'] = t('dawam.pickBranchError');
    if (_jobTitle.runes.length > 120) p['jobTitle'] = atMost(120);
    if (_salary.trim().isNotEmpty && readPounds(_salary) == null) {
      p['salary'] = t('dawam.badSalary');
    }
    return p;
  }

  /// What the disabled Add button is waiting for, in the form's own words.
  List<String> _missing(Translator t) => [
    if (_kind == 'linked' && _userId.isEmpty) t('dawam.needPerson'),
    if (_kind != 'linked' && _name.trim().isEmpty) t('dawam.needName'),
    if (_needsPhone && _phone.trim().isEmpty) t('dawam.needPhone'),
    if (_phone.trim().isNotEmpty && !isValidPhone(_phone))
      t('dawam.needGoodPhone'),
    if (_branchIds.isEmpty) t('dawam.needBranch'),
  ];

  void _edit(String field, VoidCallback change) => setState(() {
    change();
    _shown.add(field);
  });

  Future<void> _save(bool canSetSalary) async {
    final t = ref.read(tProvider);
    if (_problems(t).isNotEmpty) return;
    final phone = _phone.trim().isEmpty ? null : canonicalPhone(_phone);
    final appAccess = _needsPhone;
    setState(() => _submitting = true);
    final staff = staffInvalidator(ref);
    final f = ref.read(formatProvider);
    try {
      await ref
          .read(apiProvider)
          .staff
          .createEmployee(
            body: CreateEmployeeRequest(
              userId: _kind == 'linked' ? _userId : null,
              name: _kind == 'linked' ? null : _name.trim(),
              phone: phone,
              appAccess: appAccess,
              branchIds: _branchIds,
              jobTitle: _jobTitle.trim().isEmpty ? null : _jobTitle.trim(),
              hireDate: _hireDate.isEmpty ? null : _hireDate,
              gender: _gender.isEmpty ? null : _gender,
              baseSalaryPiastres: canSetSalary && _salary.trim().isNotEmpty
                  ? readPounds(_salary)
                  : null,
              explicitNulls: const {'phone', 'job_title', 'hire_date', 'gender'},
            ),
          );
      staff.invalidateStaff();
      if (!mounted) return;
      DashToast.success(
        context,
        appAccess ? t('dawam.employeeAdded') : t('dawam.employeeAddedNoApp'),
      );
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (!mounted) return;
      DashToast.error(context, attendanceErrorText(e, t, f));
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final canSetSalary = ref.watch(
      authzProvider.select((a) => a.canEverywhere(Cap.hrPayrollEdit)),
    );
    final branches = ref.watch(branchesProvider).value ?? const <Branch>[];
    final linkableRead = ref.watch(linkableUsersProvider);
    final linkable = linkableRead.value ?? const <LinkableUser>[];
    final preset = widget.userId != null;

    // One branch: nothing to choose.
    if (branches.length == 1 && _branchIds.isEmpty) {
      _branchIds = [branches.first.id];
      _shown.add('branches');
    }

    final all = _problems(t);
    final problems = {
      for (final e in all.entries)
        if (_shown.contains(e.key)) e.key: e.value,
    };
    final missing = _missing(t);
    final valid = all.isEmpty;
    final kindHint = switch (_kind) {
      'manual' => t('dawam.kindHint_manual'),
      'linked' => t('dawam.kindHint_linked'),
      _ => t('dawam.kindHint_app'),
    };
    final twoColumns = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm;
    final jobTitle = DashTextField(
      label: t('dawam.jobTitle'),
      value: _jobTitle,
      errorText: problems['jobTitle'],
      onChanged: (v) => _edit('jobTitle', () => _jobTitle = v),
    );
    final hire = EmployeeDateField(
      label: t('staff.hireDate'),
      value: _hireDate,
      today: dashParseYmd(teamTodayIsoOf(ref)),
      onChanged: (v) => _edit('hireDate', () => _hireDate = v),
    );

    return DashSurface(
      title: preset ? t('dawam.makeEmployee') : t('dawam.addEmployee'),
      description: kindHint,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          if (!preset)
            DashFormField<String>(
              label: t('dawam.employeeKind'),
              builder: (context, _) => Align(
                alignment: AlignmentDirectional.centerStart,
                child: DashSegmentedControl<String>(
                  semanticLabel: t('dawam.employeeKind'),
                  value: _kind,
                  options: [
                    DashOption(value: 'app', label: t('dawam.kind_app')),
                    DashOption(value: 'manual', label: t('dawam.kind_manual')),
                    DashOption(value: 'linked', label: t('dawam.kind_linked')),
                  ],
                  onChanged: (k) => setState(() => _kind = k),
                ),
              ),
            ),
          if (_kind == 'linked')
            DashSelectField<String>(
              label: t('dawam.madarUser'),
              placeholder: t('dawam.pickUser'),
              value: _userId.isEmpty ? null : _userId,
              enabled: !preset,
              // Said only of a real answer, never while it loads.
              description: linkableRead.hasError && !linkableRead.hasValue
                  ? attendanceErrorText(
                      linkableRead.error,
                      t,
                      ref.read(formatProvider),
                    )
                  : !preset && linkableRead.hasValue && linkable.isEmpty
                  ? t('dawam.noLinkable')
                  : null,
              errorText: problems['user'],
              options: [
                for (final u in linkable)
                  DashOption(
                    value: u.userId,
                    label:
                        '${u.name} · ${t.exists('roles.${u.role}') ? t('roles.${u.role}') : u.role}',
                  ),
              ],
              onChanged: (id) => _edit('user', () {
                _userId = id;
                // A linked person's number defaults to their account's.
                final u = linkable.where((l) => l.userId == id).firstOrNull;
                if (u?.phone != null && _phone.isEmpty) _phone = u!.phone!;
              }),
            )
          else
            DashTextField(
              label: t('staff.name'),
              value: _name,
              errorText: problems['name'],
              onChanged: (v) => _edit('name', () => _name = v),
            ),
          PhoneField(
            label: t('dawam.whatsapp'),
            value: _phone,
            errorText: problems['phone'],
            description: _kind == 'manual' ? t('dawam.phoneOptional') : null,
            onChanged: (v) => _edit('phone', () => _phone = v),
          ),
          if (_kind == 'linked')
            DashCheckboxField(
              label: t('dawam.appAccessLabel'),
              value: _appAccess,
              onChanged: (v) => _edit('appAccess', () => _appAccess = v),
            ),
          BranchChecklist(
            label: t('dawam.branches'),
            branches: branches,
            value: _branchIds,
            errorText: problems['branches'],
            onChanged: (v) => _edit('branches', () => _branchIds = v),
          ),
          if (twoColumns)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.md,
              children: [
                Expanded(child: jobTitle),
                Expanded(child: hire),
              ],
            )
          else ...[
            jobTitle,
            hire,
          ],
          if (canSetSalary)
            SalaryCalculator(
              label: t('dawam.salaryEgp'),
              monthly: _salary,
              onMonthly: (v) => _edit('salary', () => _salary = v),
              hireDate: _hireDate.isNotEmpty ? _hireDate : teamTodayIsoOf(ref),
              errorText: problems['salary'],
              description: _salary.trim().isEmpty
                  ? t('dawam.salaryEmptyHint')
                  : null,
            )
          else
            Container(
              padding: const EdgeInsets.all(Space.md),
              decoration: BoxDecoration(
                color: c.muted,
                borderRadius: BorderRadius.circular(Radii.card),
              ),
              child: Text(
                t('dawam.salaryNoAccessHint'),
                style: DashType.body.copyWith(color: c.textSecondary),
              ),
            ),
          DashSelectField<String>(
            label: t('dawam.gender'),
            placeholder: t('dawam.notSet'),
            value: _gender.isEmpty ? null : _gender,
            options: [
              DashOption(value: 'm', label: t('dawam.gender_m')),
              DashOption(value: 'f', label: t('dawam.gender_f')),
            ],
            onChanged: (v) => _edit('gender', () => _gender = v),
          ),
          if (missing.isNotEmpty && !_submitting)
            Semantics(
              liveRegion: true,
              child: Text(
                t(
                  'dawam.addNeeds',
                  args: {'what': missing.join(t('common.listSeparator'))},
                ),
                style: DashType.small.copyWith(color: c.textSecondary),
              ),
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
          label: preset ? t('dawam.makeEmployee') : t('dawam.addEmployee'),
          loading: _submitting,
          onPressed: _submitting || !valid ? null : () => _save(canSetSalary),
        ),
      ],
    );
  }
}
