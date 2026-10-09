/// `staff.employees` page: the port of the web's staff/employees-page.tsx `EmployeesPage`; TEAM-EMP rows (+ the area-wide TEAM-ALL rows). No in-page guard (TEAM-ALL-007): the reads 403 into the list's error state.
///
/// Everyone who works here: someone on the staff app, someone on the
/// records only, or a Madar user who is also an employee. Filters by status
/// and department (local state, not the URL), a client-side search, the
/// profile dialog on a row, phone sign-out and "End employment" row actions,
/// and the Departments, Add employee and Import dialogs.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show Branch, Department, Employee;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/attendance_errors.dart';
import '../shared/refresh_button.dart';
import '../shared/refresh_toast.dart';
import '../shared/staff_query.dart';
import '../shared/team_format.dart' show startEdge;
import '../shared/team_util.dart';
import 'add_employee_dialog.dart';
import 'departments_dialog.dart';
import 'employee_dialog.dart';
import 'employee_fields.dart';
import 'employees_data.dart';
import 'employees_providers.dart';
import 'import_people_dialog.dart';

class EmployeesPage extends ConsumerStatefulWidget {
  const EmployeesPage({super.key});

  @override
  ConsumerState<EmployeesPage> createState() => _EmployeesPageState();
}

class _EmployeesPageState extends ConsumerState<EmployeesPage> {
  String? _status;
  String? _departmentId;
  late final AppLifecycleListener _lifecycle;
  DateTime? _loadedAt;

  EmployeesQuery get _key => (status: _status, departmentId: _departmentId);

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

  /// Refetch on focus (`dawamQuery`): back after the list went stale (30 s)
  /// asks again; sooner does nothing.
  void _onResume() {
    final at = _loadedAt;
    if (at == null || !mounted) return;
    final now = ref.read(clockProvider)();
    if (now.difference(at) < kQueryStaleTime) return;
    _loadedAt = now;
    ref
      ..invalidate(employeesReadFor(_key))
      ..invalidate(staffDepartmentsProvider);
  }

  String _err(Object? e) =>
      attendanceErrorText(e, ref.read(tProvider), ref.read(formatProvider));

  /// An employee with history is never deleted (AT-6): ending one marks them
  /// terminated, signs their phone out and keeps every record.
  Future<void> _end(Employee e) async {
    final t = ref.read(tProvider);
    final ok = await showDashConfirm(
      context,
      title: t('staff.endEmploymentTitle', args: {'name': e.name}),
      description: t('staff.endEmploymentHint'),
      confirmLabel: t('staff.endEmployment'),
      cancelLabel: t('common.cancel'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    final staff = staffInvalidator(ref);
    try {
      await ref.read(apiProvider).staff.deleteEmployee(employeeId: e.id);
      staff.invalidateEmployees();
      if (mounted) DashToast.success(context, t('staff.employmentEnded'));
    } on Object catch (err) {
      if (mounted) DashToast.error(context, _err(err));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final authz = ref.watch(authzProvider);
    final canCreate = authz.can(Cap.hrStaffCreate);
    final canEdit = authz.can(Cap.hrStaffEdit);
    final canDelete = authz.can(Cap.hrStaffDelete);
    // The salary calculator (Add, the profile) reads the rules.
    final canSetPay = authz.canEverywhere(Cap.hrPayrollEdit);
    final read = employeesReadFor(_key);
    final q = ref.watch(read);
    final departments = ref.watch(staffDepartmentsProvider);
    final branches = ref.watch(branchesProvider).value ?? const <Branch>[];
    listenStaffRefreshFailure(ref, context, read);
    listenStaffRefreshFailure(ref, context, staffDepartmentsProvider);
    ref.listen(read, (_, next) {
      if (next.hasValue && !next.isLoading) {
        _loadedAt = ref.read(clockProvider)();
      }
    });
    if (q.hasValue) _loadedAt ??= ref.read(clockProvider)();

    final employees = q.value ?? const <Employee>[];
    // Redaction is per caller: a salary on any row, or the right to set pay
    // (the owner sees it even while nobody has a salary yet).
    final showSalary =
        employees.any((e) => e.baseSalaryPiastres != null) || canSetPay;
    final addButton = DashButton(
      label: t('dawam.addEmployee'),
      icon: 'plus',
      onIntent: () {
        ref.warm(linkableUsersProvider);
        if (canSetPay) ref.warm(staffAttendanceSettingsProvider);
      },
      onPressed: () => showAddEmployeeDialog(context),
    );

    return DashPageScaffold(
      title: t('staff.employees'),
      subtitle: t('staff.employeesSubtitle2'),
      actions: [
        DawamRefreshButton(busy: anyFetching([q, departments])),
        DashButton(
          label: t('staff.departments'),
          icon: 'users',
          variant: DashButtonVariant.outline,
          onIntent: () => ref.warm(staffDepartmentsProvider),
          onPressed: () => showDepartmentsDialog(context),
        ),
        if (canCreate) ...[
          DashButton(
            label: t('dawam.importTitle'),
            icon: 'file-spreadsheet',
            variant: DashButtonVariant.outline,
            onPressed: () => showImportPeopleDialog(context),
          ),
          addButton,
        ],
      ],
      filters: DashFilterBar(
        filters: [
          DashFilterSelect<String>(
            label: t('staff.employmentStatus'),
            allLabel: t('staff.allStatuses'),
            value: _status,
            options: [
              DashOption(value: 'active', label: t('staff.statusActive')),
              DashOption(value: 'suspended', label: t('staff.statusSuspended')),
              DashOption(
                value: 'terminated',
                label: t('staff.statusTerminated'),
              ),
            ],
            onOptionIntent: (v) => ref.warm(
              employeesReadFor((status: v, departmentId: _departmentId)),
            ),
            onChanged: (v) => setState(() => _status = v),
          ),
          DashFilterSelect<String>(
            label: t('staff.department'),
            allLabel: t('staff.allDepartments'),
            value: _departmentId,
            options: [
              for (final d in departments.value ?? const <Department>[])
                DashOption(value: d.id, label: d.name),
            ],
            onOptionIntent: (v) =>
                ref.warm(employeesReadFor((status: _status, departmentId: v))),
            onChanged: (v) => setState(() => _departmentId = v),
          ),
        ],
      ),
      body: DashDataTable<Employee>(
        columns: _columns(context, branches, showSalary),
        rows: employees,
        rowKey: (e) => e.id,
        loading: q.awaitingFirst,
        // A failed refresh replaces the rows (the web's table takes the raw
        // query error, TEAM-ALL-010); the stale-data toast says it too.
        // An attempt Riverpod will retry is still loading.
        errorMessage: q.hasError && !q.retrying ? _err(q.error) : null,
        onRetry: () => ref.invalidate(read),
        retrying: q.isLoading,
        onRowIntent: (_) {
          if (canSetPay) ref.warm(staffAttendanceSettingsProvider);
        },
        onRowTap: (e) => showEmployeeDialog(context, e, live: read),
        searchPlaceholder: t('staff.searchEmployees'),
        rowActionsWidth: 2 * DashMetrics.target,
        rowActions: canEdit || canDelete
            ? (context, e) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (canEdit && e.deviceModel != null)
                    EmployeeRowAction(
                      icon: 'smartphone',
                      label: t('dawam.revokePhoneShort'),
                      onPressed: () => revokeEmployeePhone(context, ref, e),
                    ),
                  if (canDelete && e.employmentStatus != 'terminated')
                    EmployeeRowAction(
                      icon: 'user-x',
                      label: t('staff.endEmployment'),
                      destructive: true,
                      onPressed: () => _end(e),
                    ),
                ],
              )
            : null,
        empty: DashEmptyState(
          icon: 'user-round',
          title: t('staff.noEmployees'),
          description: t('staff.noEmployeesHint2'),
          action: canCreate ? addButton : null,
        ),
      ),
    );
  }

  List<DashColumn<Employee>> _columns(
    BuildContext context,
    List<Branch> branches,
    bool showSalary,
  ) {
    final t = ref.read(tProvider);
    final f = ref.read(formatProvider);
    final c = context.madarColors;
    final branchName = {for (final b in branches) b.id: b.name};
    final muted = DashType.small.copyWith(color: c.textSecondary);
    String dash(String? s) => s == null || s.isEmpty ? '—' : s;
    Widget two(String top, String below, {TextStyle? topStyle}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Free text reads in its own direction (`dir="auto"`).
        MadarClippedText(
          top,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: topStyle,
          textDirection: dashTextDirectionOf(top),
          textAlign: startEdge(context),
        ),
        MadarClippedText(
          below,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: muted,
          textDirection: dashTextDirectionOf(below),
          textAlign: startEdge(context),
        ),
      ],
    );

    // `text` is what the web's search reads (the accessor value: the kind,
    // role and status KEYS, the raw number); `cell` is what shows.
    return [
      DashColumn(
        id: 'name',
        label: t('staff.name'),
        phone: DashPhoneRole.title,
        flex: 2,
        minWidth: 150,
        text: (e) => e.name,
        cell: (context, e) => two(
          e.name,
          e.jobTitle ?? t('staff.noJobTitle'),
          topStyle: DashType.bodyMedium.copyWith(color: c.textPrimary),
        ),
      ),
      DashColumn(
        id: 'kind',
        label: t('staff.kind'),
        minWidth: 112,
        text: (e) => e.kind,
        // One line: a long kind shrinks rather than wraps the badge.
        cell: (context, e) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: DashBadge(
            t.exists('staff.kind_${e.kind}')
                ? t('staff.kind_${e.kind}')
                : e.kind,
          ),
        ),
      ),
      DashColumn(
        id: 'branches',
        label: t('dawam.branches'),
        minWidth: 112,
        searchable: false,
        text: (e) => dash(
          e.branchIds
              .map((id) => branchName[id])
              .nonNulls
              .join(t('common.listSeparator')),
        ),
      ),
      DashColumn(
        id: 'phone',
        label: t('dawam.whatsapp'),
        numeric: true,
        align: DashAlign.start,
        minWidth: 156,
        text: (e) => e.phone ?? '',
        cell: (context, e) => e.phone == null
            ? const Text('—')
            : MadarClippedText(
                phoneCell(e.phone!),
                textDirection: TextDirection.ltr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
      ),
      DashColumn(
        id: 'app_access',
        label: t('staff.appAccess'),
        minWidth: 96,
        searchable: false,
        text: (e) =>
            e.appAccess ? t('staff.appAccessYes') : t('staff.appAccessNo'),
      ),
      DashColumn(
        id: 'role',
        label: t('staff.madarRole'),
        minWidth: 136,
        text: (e) => e.role ?? '',
        cell: (context, e) => MadarClippedText(
          e.role == null
              ? '—'
              : t.exists('roles.${e.role}')
              ? t('roles.${e.role}')
              : e.role!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      DashColumn(
        id: 'device',
        label: t('staff.device'),
        minWidth: 168,
        searchable: false,
        cell: (context, e) => e.deviceModel == null
            ? const Text('—')
            : two(
                e.deviceModel!,
                t(
                  'staff.deviceSince',
                  args: {'date': f.fmtDate(e.deviceSince)},
                ),
              ),
      ),
      DashColumn(
        id: 'department',
        label: t('staff.department'),
        minWidth: 136,
        text: (e) => e.departmentName ?? '',
        cell: (context, e) => MadarClippedText(
          dash(e.departmentName),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textDirection: dashTextDirectionOf(dash(e.departmentName)),
          textAlign: startEdge(context),
        ),
      ),
      DashColumn(
        id: 'status',
        label: t('staff.employmentStatus'),
        minWidth: 112,
        text: (e) => e.employmentStatus,
        cell: (context, e) => DashStatusPill(
          tone: employmentStatusTone[e.employmentStatus] ?? DashTone.neutral,
          label: t.exists('staff.status_${e.employmentStatus}')
              ? t('staff.status_${e.employmentStatus}')
              : e.employmentStatus,
        ),
      ),
      if (showSalary)
        DashColumn(
          id: 'salary',
          label: t('staff.baseSalary'),
          numeric: true,
          minWidth: 196,
          searchable: false,
          cell: (context, e) => switch (salaryStateOf(e)) {
            // Nobody set one: payroll won't approve until it is.
            SalaryState.notSet => Tooltip(
              message: t('dawam.salaryNotSetHint'),
              child: DashStatusPill(
                tone: DashTone.warning,
                icon: 'circle-alert',
                small: true,
                label: t('dawam.notSet'),
              ),
            ),
            SalaryState.hidden => const Text('—'),
            SalaryState.set => MadarClippedText(
              f.fmtMoney(e.baseSalaryPiastres),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          },
        ),
    ];
  }
}
