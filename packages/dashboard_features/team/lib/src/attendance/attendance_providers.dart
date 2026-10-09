/// The Attendance unit's reads, one per endpoint, keyed by exactly the
/// params the request sends (the web's Orval key), and the export's re-read.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/staff_query.dart';

/// `listAttendance` / `attendanceSummary` params: the page's window and
/// filters (`branch_id` = the scope branch, TEAM-ALL-018), or the Add
/// dialog's look-ahead (`from`/`to` only).
typedef AttendanceQuery = ({
  String from,
  String to,
  String? branchId,
  String? status,
  String? employeeId,
});

/// A window with no filters (the Add dialog's look-ahead).
AttendanceQuery attendanceWindow(String from, String to) =>
    (from: from, to: to, branchId: null, status: null, employeeId: null);

/// `GET /staff/attendance`: one unpaged answer for the window.
final attendanceListProvider = FutureProvider.autoDispose
    .family<List<AttendanceRecord>, AttendanceQuery>((ref, k) {
      ref.webCache();
      watchStaffPath(ref, '/staff/attendance');
      return ref
          .watch(apiProvider)
          .staff
          .listAttendance(
            from: k.from,
            to: k.to,
            branchId: k.branchId,
            status: k.status,
            employeeId: k.employeeId,
          );
    });

/// `GET /staff/attendance/summary`: per-employee totals, with the page's
/// params (the server ignores `status`; the web sends it all the same).
final attendanceSummaryProvider = FutureProvider.autoDispose
    .family<List<AttendanceSummary>, AttendanceQuery>((ref, k) {
      ref.webCache();
      watchStaffPath(ref, '/staff/attendance/summary');
      return ref
          .watch(apiProvider)
          .staff
          .attendanceSummary(
            from: k.from,
            to: k.to,
            branchId: k.branchId,
            status: k.status,
            employeeId: k.employeeId,
          );
    });

/// The page's query again, declared as an export (`X-Madar-Export: 1`,
/// `EXPORT_REQUEST`), never from the cache.
Future<List<AttendanceRecord>> exportAttendance(
  ApiTransport transport,
  AttendanceQuery k,
) => DashboardApi(_HeaderTransport(transport, exportRequestHeaders)).staff
    .listAttendance(
      from: k.from,
      to: k.to,
      branchId: k.branchId,
      status: k.status,
      employeeId: k.employeeId,
    );

class _HeaderTransport implements ApiTransport {
  _HeaderTransport(this.inner, this.headers);

  final ApiTransport inner;
  final Map<String, String> headers;

  ApiRequest _with(ApiRequest r) => ApiRequest(
    method: r.method,
    path: r.path,
    query: r.query,
    body: r.body,
    files: r.files,
    headers: {...r.headers, ...headers},
  );

  @override
  Future<ApiResponse> send(ApiRequest request) => inner.send(_with(request));

  @override
  Stream<String> stream(ApiRequest request) => inner.stream(_with(request));
}
