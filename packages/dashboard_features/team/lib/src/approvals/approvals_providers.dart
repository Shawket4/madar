/// The Approvals unit's reads, one per list, keyed by exactly the params the
/// request sends (the web's Orval key). The page watches only the lists the
/// person may decide (`enabled: can.…`), so nothing else is asked for.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../payroll/payroll_data.dart' show payrollAdvancesProvider;
import '../requests/requests_providers.dart' show requestsListProvider;
import '../shared/staff_query.dart';

/// `listRequests({status: "pending"})`: the Requests page's read of the
/// same key, one cache for both pages.
final approvalsRequestsProvider = requestsListProvider((
  status: 'pending',
  kind: null,
));

/// `listAdvances({})`: every advance (the page keeps the pending ones); the
/// Payroll page's read of the same address.
final approvalsAdvancesProvider = payrollAdvancesProvider;

/// `listSwaps({status: "pending"})`.
final approvalsSwapsProvider = FutureProvider.autoDispose<List<Swap>>((ref) {
  ref.webCache();
  watchStaffPath(ref, '/staff/swaps');
  return ref.watch(apiProvider).staff.listSwaps(status: 'pending');
});

/// `listOpenShifts({from: today−366, to: today+366})`: a claim can sit on
/// any published week, however far ahead or long undecided.
final approvalsClaimsProvider = FutureProvider.autoDispose
    .family<List<OpenShift>, ({String from, String to})>((ref, k) {
      ref.webCache();
      watchStaffPath(ref, '/staff/open-shifts');
      return ref
          .watch(apiProvider)
          .staff
          .listOpenShifts(from: k.from, to: k.to);
    });

/// `listAttendance({cover_status})` / `({overtime_status})`: every pending
/// cover and overtime, however old (no window).
final approvalsAttendanceProvider = FutureProvider.autoDispose
    .family<List<AttendanceRecord>, ({String? cover, String? overtime})>((
      ref,
      k,
    ) {
      ref.webCache();
      watchStaffPath(ref, '/staff/attendance');
      return ref
          .watch(apiProvider)
          .staff
          .listAttendance(coverStatus: k.cover, overtimeStatus: k.overtime);
    });

const ({String? cover, String? overtime}) pendingCovers = (
  cover: 'pending',
  overtime: null,
);
const ({String? cover, String? overtime}) pendingOvertime = (
  cover: null,
  overtime: 'pending',
);

/// `listAdjustments({status: "pending"})`: pay lines over a manager's limit.
final approvalsPayLinesProvider = FutureProvider.autoDispose<List<Adjustment>>((
  ref,
) {
  ref.webCache();
  watchStaffPath(ref, '/staff/adjustments');
  return ref.watch(apiProvider).staff.listAdjustments(status: 'pending');
});
