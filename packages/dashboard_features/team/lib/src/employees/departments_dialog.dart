/// The Departments dialog (`staff/employees-page.tsx` `DepartmentsDialog`,
/// TEAM-EMP-060…063): the list for everyone; adding and deleting are
/// business-wide acts (the right at every branch), so a branch manager only
/// reads it.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show Department, UpsertDepartmentRequest;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/attendance_errors.dart';
import 'employee_fields.dart';
import 'employees_providers.dart';

Future<void> showDepartmentsDialog(BuildContext context) =>
    showDashDialog<void>(context, builder: (_) => const DepartmentsDialog());

class DepartmentsDialog extends ConsumerStatefulWidget {
  const DepartmentsDialog({super.key});

  @override
  ConsumerState<DepartmentsDialog> createState() => _DepartmentsDialogState();
}

class _DepartmentsDialogState extends ConsumerState<DepartmentsDialog> {
  String _name = '';
  bool _busy = false;

  String _err(Object e) =>
      attendanceErrorText(e, ref.read(tProvider), ref.read(formatProvider));

  Future<void> _add() async {
    final name = _name.trim();
    if (name.isEmpty || _busy) return;
    setState(() => _busy = true);
    final staff = staffInvalidator(ref);
    try {
      await ref
          .read(apiProvider)
          .staff
          .createDepartment(body: UpsertDepartmentRequest(name: name));
      staff.invalidateDepartments();
      if (!mounted) return;
      setState(() => _name = '');
    } on Object catch (e) {
      if (mounted) DashToast.error(context, _err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(Department d) async {
    final t = ref.read(tProvider);
    final ok = await showDashConfirm(
      context,
      title: t('staff.deleteDepartmentTitle', args: {'name': d.name}),
      description: t('staff.deleteDepartmentHint'),
      confirmLabel: t('common.delete'),
      cancelLabel: t('common.cancel'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    final staff = staffInvalidator(ref);
    try {
      await ref.read(apiProvider).staff.deleteDepartment(id: d.id);
      staff.invalidateDepartments();
    } on Object catch (e) {
      // Still has staff: the server says how many, shown as it is.
      if (mounted) DashToast.error(context, _err(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final authz = ref.watch(authzProvider);
    final canAdd = authz.canEverywhere(Cap.hrStaffCreate);
    final canDelete = authz.canEverywhere(Cap.hrStaffDelete);
    final read = ref.watch(staffDepartmentsProvider);
    final departments = read.value;
    final empty = _name.trim().isEmpty;
    return DashSurface(
      title: t('staff.departments'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          if (canAdd)
            Row(
              spacing: Space.sm,
              children: [
                Expanded(
                  child: DashTextInput(
                    value: _name,
                    placeholder: t('staff.newDepartment'),
                    semanticLabel: t('staff.newDepartment'),
                    onChanged: (v) => setState(() => _name = v),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                DashIconButton(
                  icon: 'plus',
                  semanticLabel: t('staff.addDepartment'),
                  variant: DashButtonVariant.primary,
                  onPressed: _busy || empty ? null : _add,
                ),
              ],
            ),
          if (departments == null && read.hasError)
            DashErrorState(
              framed: false,
              message: _err(read.error!),
              retrying: read.isLoading,
              onRetry: () => ref.invalidate(staffDepartmentsProvider),
            )
          else if (departments == null)
            for (var i = 0; i < 3; i++)
              const DashSkeleton(height: Space.xxl * 2, radius: Radii.card)
          else if (departments.isEmpty)
            Text(
              t('staff.noDepartments'),
              style: DashType.body.copyWith(color: c.textSecondary),
            )
          else
            for (final d in departments)
              DashCard(
                key: ValueKey('department-${d.id}'),
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.lg,
                  vertical: Space.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      spacing: Space.sm,
                      children: [
                        Expanded(
                          child: Text(
                            d.name,
                            style: DashType.bodyMedium.copyWith(
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                        DashBadge(
                          t(
                            'staff.employeeCount',
                            args: {'count': d.employeeCount},
                          ),
                        ),
                        if (canDelete)
                          EmployeeRowAction(
                            icon: 'trash-2',
                            label: t('common.delete'),
                            destructive: true,
                            onPressed: () => _remove(d),
                          ),
                      ],
                    ),
                    if (d.managerName != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Space.xs),
                        child: Text(
                          t('staff.managedBy', args: {'name': d.managerName}),
                          style: DashType.small.copyWith(
                            color: c.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
        ],
      ),
      actions: [
        DashButton(
          label: t('common.close'),
          variant: DashButtonVariant.ghost,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }
}
