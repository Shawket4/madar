/// The Schedule unit's reads, one per endpoint, keyed by exactly the params
/// the request sends (the web's Orval key). Every one is under `/staff`, so
/// the page's writes (`invalidateStaff`) and its Refresh button reach them.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/staff_query.dart';

/// `roster(branch_id, from, to)`: the viewed week, or today → today + 45
/// (the holidays still to decide).
typedef RosterKey = ({String branchId, String from, String to});

/// `suggestions(branch_id, week_start)`.
typedef SuggestionsKey = ({String branchId, String weekStart});

/// `GET /staff/roster`.
final scheduleRosterProvider = FutureProvider.autoDispose
    .family<RosterView, RosterKey>((ref, k) {
      ref.webCache();
      watchStaffPath(ref, '/staff/roster');
      return ref
          .watch(apiProvider)
          .staff
          .roster(branchId: k.branchId, from: k.from, to: k.to);
    });

/// `GET /staff/roster/suggestions` (with `hr.schedule.edit` only).
final scheduleSuggestionsProvider = FutureProvider.autoDispose
    .family<List<Suggestion>, SuggestionsKey>((ref, k) {
      ref.webCache();
      watchStaffPath(ref, '/staff/roster/suggestions');
      return ref
          .watch(apiProvider)
          .staff
          .suggestions(branchId: k.branchId, weekStart: k.weekStart);
    });

/// `GET /staff/roster/coverage` (the coverage card, an editor: no focus
/// refetch).
final scheduleCoverageProvider = FutureProvider.autoDispose
    .family<CoverageView, String>((ref, branchId) {
      ref.webCache();
      watchStaffPath(ref, '/staff/roster/coverage');
      return ref.watch(apiProvider).staff.getCoverage(branchId: branchId);
    });

/// `GET /staff/employees/{id}/preferences/log`.
final schedulePreferenceLogProvider = FutureProvider.autoDispose
    .family<List<PreferenceChange>, String>((ref, employeeId) {
      ref.webCache();
      watchStaffPath(ref, '/staff/employees/$employeeId/preferences/log');
      return ref.watch(apiProvider).staff.preferenceLog(id: employeeId);
    });

/// `GET /staff/roster/fairness?month=YYYY-MM-01`.
final scheduleFairnessProvider = FutureProvider.autoDispose
    .family<FairnessView, String>((ref, month) {
      ref.webCache();
      watchStaffPath(ref, '/staff/roster/fairness');
      return ref.watch(apiProvider).staff.fairness(month: month);
    });

/// `GET /staff/roster/fairness/audits`.
final scheduleFairnessAuditsProvider =
    FutureProvider.autoDispose<List<FairnessAudit>>((ref) {
      ref.webCache();
      watchStaffPath(ref, '/staff/roster/fairness/audits');
      return ref.watch(apiProvider).staff.fairnessAudits();
    });
