/// The Bundles report's reads (REP-BUN-004, REP-BUN-013), keyed by their
/// params as the web's React Query keys are (`getBundlesReportQueryKey`,
/// `getComboMixQueryKey`). A `till.*` event (prefix `/reports`) and a
/// `resync` refetch them (REP-ALL-009).
library;

import 'package:dashboard_api/dashboard_api.dart' show BundlesReport, ComboMix;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `{from, to, branch_id?, kind}`: the period as branch-local dates.
typedef BundlesQuery = ({
  String from,
  String to,
  String? branchId,
  String kind,
});

/// `{comboId, from, to, branch_id?}`.
typedef ComboMixQuery = ({
  String comboId,
  String from,
  String to,
  String? branchId,
});

/// `GET /reports/bundles` (bundlesReport).
final bundlesReportProvider = FutureProvider.autoDispose
    .family<BundlesReport, BundlesQuery>((ref, q) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/reports/bundles'));
      return ref
          .watch(apiProvider)
          .reports
          .bundlesReport(
            from: q.from,
            to: q.to,
            branchId: q.branchId,
            kind: q.kind,
          );
    });

/// `GET /reports/bundles/combos/{id}/mix` (comboMix).
final comboMixProvider = FutureProvider.autoDispose
    .family<ComboMix, ComboMixQuery>((ref, q) {
      ref.webCache();
      ref.watch(
        realtimeEpochProvider('/reports/bundles/combos/${q.comboId}/mix'),
      );
      return ref
          .watch(apiProvider)
          .reports
          .comboMix(
            id: q.comboId,
            from: q.from,
            to: q.to,
            branchId: q.branchId,
          );
    });
