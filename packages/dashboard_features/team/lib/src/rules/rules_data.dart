/// The Rules page's reads (`staff/attendance-rules-page.tsx`).
///
/// - `GET /staff/attendance/settings/branches` (`listBranchRules`): the
///   person's branches and which rules each sets itself.
/// - `GET /staff/attendance/settings[?branch_id]` (`getAttendanceSettings`):
///   the business's rules (dashboard_core's `staffAttendanceSettingsProvider`,
///   one request shared with the set-up checklist and the rules banner), or a
///   branch's effective ones with `overridden`.
///
/// All are keyed by their endpoint path, so a save's `invalidateAttendance`
/// (every `/staff/attendance…` read) and the Refresh button reach them.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/staff_query.dart';

/// `GET /staff/attendance/settings/branches`.
final rulesBranchesProvider = FutureProvider.autoDispose<List<BranchRules>>((
  ref,
) {
  ref.webCache();
  watchStaffPath(ref, '/staff/attendance/settings/branches');
  return ref.watch(apiProvider).staff.listBranchRules();
});

/// `GET /staff/attendance/settings?branch_id=…`: one branch's effective rules.
final rulesBranchSettingsProvider = FutureProvider.autoDispose
    .family<AttendanceSettings, String>((ref, branchId) {
      ref.webCache();
      watchStaffPath(ref, '/staff/attendance/settings');
      return ref
          .watch(apiProvider)
          .staff
          .getAttendanceSettings(branchId: branchId);
    });

/// The settings read for a scope: null is the business.
FutureProvider<AttendanceSettings> rulesSettingsFor(String? branchId) =>
    branchId == null
    ? staffAttendanceSettingsProvider
    : rulesBranchSettingsProvider(branchId);
