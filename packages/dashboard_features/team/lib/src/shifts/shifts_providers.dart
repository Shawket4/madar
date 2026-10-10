/// The Work shifts page's reads. The shift list and the active people are
/// dashboard_core's shared reads (`staffWorkShiftsProvider`,
/// `staffActiveEmployeesProvider`, one request each with the set-up check);
/// the standing roster is this unit's.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/staff_query.dart';

/// `GET /staff/schedules` with no employee: the whole org's standing roster
/// in one request (`listAssignments({})`).
final shiftsRosterProvider =
    FutureProvider.autoDispose<List<ScheduleAssignment>>((ref) {
      ref.webCache();
      watchStaffPath(ref, '/staff/schedules');
      return ref.watch(apiProvider).staff.listAssignments();
    });
