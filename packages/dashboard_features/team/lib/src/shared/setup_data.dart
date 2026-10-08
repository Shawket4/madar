/// The four answers behind the Dawam set-up checklist, as a team PAGE reads
/// them (`dawam/setup.ts` `useSetupData(enabled, onPage = true)`): the
/// Set-up page (TEAM-SET-002) and the rules-first banner (TEAM-ALL-016).
///
/// Unlike the shell's sidebar copy (dashboard_core `setupDataProvider`, which
/// asks only someone holding `hr.rules.edit`), a page asks whenever an
/// organization is in scope; a read this person may not make fails on its
/// own and simply counts as unanswered. No org in scope (a platform admin who
/// has not picked one) asks nothing.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'staff_query.dart';

/// `GET /staff/employees?employment_status=active`.
final setupActiveEmployeesProvider =
    FutureProvider.autoDispose<List<Employee>?>((ref) async {
      watchStaffPath(ref, '/staff/employees');
      if (ref.watch(orgIdProvider) == null) return null;
      return ref.watch(staffActiveEmployeesProvider.future);
    });

/// `GET /staff/work-shifts`.
final setupWorkShiftsProvider = FutureProvider.autoDispose<List<WorkShift>?>((
  ref,
) async {
  watchStaffPath(ref, '/staff/work-shifts');
  if (ref.watch(orgIdProvider) == null) return null;
  return ref.watch(staffWorkShiftsProvider.future);
});

/// `GET /staff/attendance/settings` (the business's rules).
final setupAttendanceSettingsProvider =
    FutureProvider.autoDispose<AttendanceSettings?>((ref) async {
      watchStaffPath(ref, '/staff/attendance/settings');
      if (ref.watch(orgIdProvider) == null) return null;
      return ref.watch(staffAttendanceSettingsProvider.future);
    });

/// The checklist's data, each field null until answered.
class TeamSetupData {
  const TeamSetupData({
    this.branches,
    this.employees,
    this.shifts,
    this.settings,
    this.error,
  });

  final List<Branch>? branches;

  /// The ACTIVE employees.
  final List<Employee>? employees;
  final List<WorkShift>? shifts;
  final AttendanceSettings? settings;

  /// The first read that failed with no data to show.
  final Object? error;

  /// `setupProgress(d)`: each step from real data, never a ticked box
  /// (TEAM-SET-006).
  SetupProgress get progress => setupProgress(
    SetupData(
      branches: branches,
      activeEmployeeStatuses: employees
          ?.map((e) => e.employmentStatus)
          .toList(),
      shiftsActive: shifts?.map((s) => s.isActive).toList(),
      rulesKnown: settings != null,
      rulesSavedAt: settings?.rulesSavedAt,
    ),
  );
}

/// The live checklist data for a team page.
final teamSetupDataProvider = Provider.autoDispose<TeamSetupData>((ref) {
  final reads = <AsyncValue<Object?>>[
    ref.watch(branchesProvider),
    ref.watch(setupActiveEmployeesProvider),
    ref.watch(setupWorkShiftsProvider),
    ref.watch(setupAttendanceSettingsProvider),
  ];
  final failed = reads.where(failedEmpty);
  return TeamSetupData(
    branches: ref.watch(branchesProvider).value,
    employees: ref.watch(setupActiveEmployeesProvider).value,
    shifts: ref.watch(setupWorkShiftsProvider).value,
    settings: ref.watch(setupAttendanceSettingsProvider).value,
    error: failed.isEmpty ? null : failed.first.error,
  );
});

/// Asks again only the checklist reads that failed with nothing to show
/// (TEAM-SET-005 Retry).
void retryTeamSetup(WidgetRef ref) {
  if (failedEmpty(ref.read(branchesProvider))) ref.invalidate(branchesProvider);
  // A failed page read waits on the shared one: that one asks again too.
  if (failedEmpty(ref.read(setupActiveEmployeesProvider))) {
    ref
      ..invalidate(staffActiveEmployeesProvider)
      ..invalidate(setupActiveEmployeesProvider);
  }
  if (failedEmpty(ref.read(setupWorkShiftsProvider))) {
    ref
      ..invalidate(staffWorkShiftsProvider)
      ..invalidate(setupWorkShiftsProvider);
  }
  if (failedEmpty(ref.read(setupAttendanceSettingsProvider))) {
    ref
      ..invalidate(staffAttendanceSettingsProvider)
      ..invalidate(setupAttendanceSettingsProvider);
  }
}
