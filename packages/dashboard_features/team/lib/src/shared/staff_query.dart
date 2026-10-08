/// The web's Dawam data plumbing, ported once for every team page.
///
/// - **Invalidation by endpoint path** (`staff/util.ts:12-34`, TEAM-ALL-026).
///   Orval keys every read by its endpoint path; the web invalidates by a
///   plain string prefix of it. Here every team read provider calls
///   [watchStaffPath] with its path first thing, and a mutation calls one of
///   [StaffRevisionsNotifier]'s helpers: every read whose path starts with
///   that prefix rebuilds (a mounted read at once, the rest when next shown)
///   and keeps its last data on screen while it does.
///
///   ```dart
///   final employeesProvider = FutureProvider.autoDispose((ref) {
///     ref.webCache();
///     watchStaffPath(ref, '/staff/employees');
///     return ref.watch(apiProvider).staff.listEmployees();
///   });
///   // after a write:
///   ref.read(staffRevisionsProvider.notifier).invalidateEmployees();
///   ```
///
/// - **The Refresh button's refetch** (`dawam/live.ts` `keyUnder`,
///   TEAM-ALL-008) matches on a path-SEGMENT boundary: `/staff-pool` is not
///   `/staff`. The invalidation helpers are plain prefixes and DO reach
///   `/staff-pool…` reads, exactly as the web's do.
/// - [failedEmpty]: a read that failed with nothing to show (TEAM-ALL-010).
///
/// Reads outside the team area (the core's `branchesProvider`, another
/// area's staff-drinks reads) do not watch these revisions: a page that shows
/// them invalidates them itself (Set-up's Refresh also covers `/branches`).
library;

import 'package:dashboard_core/dashboard_core.dart' show realtimeBusProvider;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The key prefix of every Dawam endpoint (`DAWAM_KEY_PREFIX`).
const String dawamKeyPrefix = '/staff';

/// Whether [path] sits under one of [prefixes] on a path-segment boundary
/// (`keyUnder`): `/staff/employees` is under `/staff`, `/staff-pool` is not.
bool keyUnder(String path, Iterable<String> prefixes) =>
    prefixes.any((p) => path == p || path.startsWith('$p/'));

/// How often each prefix was invalidated, by kind of match.
@immutable
class StaffRevisions {
  const StaffRevisions({this.plain = const {}, this.segment = const {}});

  /// Plain string-prefix invalidations (`invalidatePrefix`).
  final Map<String, int> plain;

  /// Segment-bounded refetches (the Refresh button).
  final Map<String, int> segment;

  /// The revision of a read at [path]: it changes exactly when a prefix the
  /// path falls under is bumped.
  int revisionOf(String path) {
    var n = 0;
    plain.forEach((p, v) {
      if (path.startsWith(p)) n += v;
    });
    segment.forEach((p, v) {
      if (keyUnder(path, [p])) n += v;
    });
    return n;
  }
}

/// The web's invalidation helpers and the Refresh button's refetch.
class StaffRevisionsNotifier extends Notifier<StaffRevisions> {
  @override
  StaffRevisions build() => const StaffRevisions();

  void _bump(String prefix, {required bool segment}) {
    final s = state;
    final map = Map<String, int>.of(segment ? s.segment : s.plain);
    map[prefix] = (map[prefix] ?? 0) + 1;
    state = segment
        ? StaffRevisions(plain: s.plain, segment: map)
        : StaffRevisions(plain: map, segment: s.segment);
    // The Dawam reads dashboard_core shares (the set-up check's) listen on
    // the bus, by plain prefix.
    ref.read(realtimeBusProvider).invalidate([prefix]);
  }

  /// Every read whose path starts with [prefix] (`invalidatePrefix`).
  void invalidatePrefix(String prefix) => _bump(prefix, segment: false);

  /// Everything under the staff module (`invalidateStaff`), `/staff-pool…`
  /// included: a write that crosses sub-trees.
  void invalidateStaff() => invalidatePrefix('/staff');

  void invalidateEmployees() => invalidatePrefix('/staff/employees');
  void invalidateDepartments() => invalidatePrefix('/staff/departments');
  void invalidateWorkShifts() => invalidatePrefix('/staff/work-shifts');
  void invalidateSchedules() => invalidatePrefix('/staff/schedules');

  /// `/staff/attendance…`, which also covers `/staff/attendance/settings`,
  /// `/settings/branches` and `/summary`.
  void invalidateAttendance() => invalidatePrefix('/staff/attendance');
  void invalidateLeave() => invalidatePrefix('/staff/leave');

  /// Requests live under `/staff/requests`, leave balances under
  /// `/staff/leave`: a decision that spends leave touches both.
  void invalidateRequests() {
    invalidatePrefix('/staff/requests');
    invalidatePrefix('/staff/leave');
  }

  void invalidatePayroll() => invalidatePrefix('/staff/payroll');

  /// The Refresh button: fetch again what the page shows under [prefixes]
  /// (segment-bounded, so `/staff-pool` is left alone).
  void refetch([List<String> prefixes = const [dawamKeyPrefix]]) {
    for (final p in prefixes) {
      _bump(p, segment: true);
    }
  }
}

final staffRevisionsProvider =
    NotifierProvider<StaffRevisionsNotifier, StaffRevisions>(
      StaffRevisionsNotifier.new,
    );

/// Call first thing in a team read provider, with the endpoint's path (the
/// web's query key): the provider then rebuilds whenever that path is
/// invalidated or refetched.
int watchStaffPath(Ref ref, String path) =>
    ref.watch(staffRevisionsProvider.select((r) => r.revisionOf(path)));

/// A read that failed with nothing to show: the page's error state. A
/// refresh that fails while the last data is on screen keeps that data
/// (and toasts, see `refresh_toast.dart`).
bool failedEmpty(AsyncValue<Object?> v) => v.hasError && !v.hasValue;

/// Whether any of [reads] is fetching (first load or a refresh): the Refresh
/// button spins.
bool anyFetching(Iterable<AsyncValue<Object?>> reads) =>
    reads.any((v) => v.isLoading);
