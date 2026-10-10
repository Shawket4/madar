/// The Team board's reads (`dawam/team-page.tsx`), one per endpoint, keyed by
/// exactly the params the request sends (the web's Orval key).
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/staff_query.dart';

/// `teamPresence({branch_id})`: the scope's branch, or none for "All
/// branches" (TEAM-ALL-018). Polled every 60 s by the page (TEAM-TEM-007).
final teamPresenceProvider = FutureProvider.autoDispose
    .family<TeamPresence, String?>((ref, branchId) {
      ref.webCache();
      watchStaffPath(ref, '/staff/team/presence');
      return ref.watch(apiProvider).staff.teamPresence(branchId: branchId);
    });

/// `listAttendanceFlags({branch_id})`: the page keeps the unresolved ones.
final teamFlagsProvider = FutureProvider.autoDispose
    .family<List<AttendanceFlag>, String?>((ref, branchId) {
      ref.webCache();
      watchStaffPath(ref, '/staff/flags');
      return ref
          .watch(apiProvider)
          .staff
          .listAttendanceFlags(branchId: branchId);
    });

/// `listAttendance({from: day, to: day, branch_id})`: today's records, which
/// say whose shift a colleague covers and whether today's month is closed.
typedef TeamTodayKey = ({String day, String? branchId});

final teamTodayRecordsProvider = FutureProvider.autoDispose
    .family<List<AttendanceRecord>, TeamTodayKey>((ref, k) {
      ref.webCache();
      watchStaffPath(ref, '/staff/attendance');
      return ref
          .watch(apiProvider)
          .staff
          .listAttendance(from: k.day, to: k.day, branchId: k.branchId);
    });
