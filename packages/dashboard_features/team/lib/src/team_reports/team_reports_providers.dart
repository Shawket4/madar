/// The Reports unit's reads, one per endpoint, keyed by exactly the params
/// the request sends (`from`, `to`, `branch_id` = the scope branch,
/// TEAM-ALL-018). The attendance tab shares the Attendance page's
/// `attendanceSummaryProvider` (the web's one `/staff/attendance/summary`
/// key), with no person or status.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../attendance/attendance_providers.dart';
import '../shared/staff_query.dart';

/// Every report's params.
typedef ReportQuery = ({String from, String to, String? branchId});

/// The attendance tab's key on the shared summary read.
AttendanceQuery reportAttendanceKey(ReportQuery k) => (
  from: k.from,
  to: k.to,
  branchId: k.branchId,
  status: null,
  employeeId: null,
);

/// `GET /staff/reports/labour-vs-sales`: per branch and day.
final labourVsSalesProvider = FutureProvider.autoDispose
    .family<List<LabourDay>, ReportQuery>((ref, k) {
      ref.webCache();
      watchStaffPath(ref, '/staff/reports/labour-vs-sales');
      return ref
          .watch(apiProvider)
          .staff
          .labourVsSales(from: k.from, to: k.to, branchId: k.branchId);
    });

/// `GET /staff/reports/payroll-history`: one row per pay period.
final payrollHistoryProvider = FutureProvider.autoDispose
    .family<List<PayrollHistoryRow>, ReportQuery>((ref, k) {
      ref.webCache();
      watchStaffPath(ref, '/staff/reports/payroll-history');
      return ref
          .watch(apiProvider)
          .staff
          .payrollHistory(from: k.from, to: k.to, branchId: k.branchId);
    });

/// `GET /staff/reports/advances`: salary and expense advances given.
final advancesReportProvider = FutureProvider.autoDispose
    .family<AdvancesReport, ReportQuery>((ref, k) {
      ref.webCache();
      watchStaffPath(ref, '/staff/reports/advances');
      return ref
          .watch(apiProvider)
          .staff
          .advances(from: k.from, to: k.to, branchId: k.branchId);
    });
