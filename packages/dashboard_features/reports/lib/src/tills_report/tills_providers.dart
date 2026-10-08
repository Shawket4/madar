/// The one read behind all three tabs (REP-TIL-002, -005):
/// `GET /reports/branches/{scopeBranchId}/tills?from&to` (`branchTillSessions`),
/// keyed like the web's React Query key (the path and its params), so a
/// branch or period change asks again.
///
/// A realtime `till.*` (or `resync`) invalidates every `/reports…` key, so the
/// read watches its own path's epoch and refetches (REP-ALL-009).
library;

import 'package:dashboard_api/dashboard_api.dart' show TillSessionRow;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The read's key: the scope's branch (or the all-branches sentinel) and the
/// day-bounded instants.
typedef TillSessionsKey = ({String branchId, String from, String to});

/// The key for [scope].
TillSessionsKey tillSessionsKey(Scope scope) =>
    (branchId: scope.scopeBranchId, from: scope.from, to: scope.to);

/// The path the read invalidates under.
String tillSessionsPath(String branchId) => '/reports/branches/$branchId/tills';

final tillSessionsProvider = FutureProvider.autoDispose
    .family<List<TillSessionRow>, TillSessionsKey>((ref, k) {
      ref.watch(realtimeEpochProvider(tillSessionsPath(k.branchId)));
      return ref
          .watch(apiProvider)
          .reports
          .branchTillSessions(
            branchId: k.branchId,
            from: DateTime.parse(k.from),
            to: DateTime.parse(k.to),
          );
    });
