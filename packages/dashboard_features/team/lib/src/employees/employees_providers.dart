/// The Employees unit's reads, one per endpoint, keyed by exactly the params
/// the request sends (the web's Orval key), and the invalidations its writes
/// make (`staff/util.ts`).
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/staff_query.dart';

/// `listEmployees(employment_status?, department_id?)`: the page's filters.
typedef EmployeesQuery = ({String? status, String? departmentId});

/// `GET /staff/employees` with the page's filters.
final employeesListProvider = FutureProvider.autoDispose
    .family<List<Employee>, EmployeesQuery>((ref, k) {
      ref.webCache();
      watchStaffPath(ref, '/staff/employees');
      return ref
          .watch(apiProvider)
          .staff
          .listEmployees(
            employmentStatus: k.status,
            departmentId: k.departmentId,
          );
    });

/// The read for [k]: "Active" with no department is the very request the
/// sidebar's set-up check makes (`employment_status=active`), so it shares
/// dashboard_core's read instead of asking twice.
FutureProvider<List<Employee>> employeesReadFor(EmployeesQuery k) =>
    k.status == 'active' && k.departmentId == null
    ? staffActiveEmployeesProvider
    : employeesListProvider(k);

/// `GET /staff/departments`.
final staffDepartmentsProvider = FutureProvider.autoDispose<List<Department>>((
  ref,
) {
  ref.webCache();
  watchStaffPath(ref, '/staff/departments');
  return ref.watch(apiProvider).staff.listDepartments();
});

/// `GET /staff/employees/linkable`: the Madar users who are not employees
/// yet (the Add dialog's "Madar user" kind).
final linkableUsersProvider = FutureProvider.autoDispose<List<LinkableUser>>((
  ref,
) {
  ref.webCache();
  watchStaffPath(ref, '/staff/employees/linkable');
  return ref.watch(apiProvider).staff.linkableUsers();
});

/// The web's invalidation helpers (`invalidateEmployees`, `invalidateStaff`,
/// `invalidateDepartments`). Read it BEFORE a write's `await` and call it
/// after, whatever became of the widget meanwhile: the web's query client
/// refetches even when the dialog closed mid-save.
StaffRevisionsNotifier staffInvalidator(WidgetRef ref) =>
    ref.read(staffRevisionsProvider.notifier);
