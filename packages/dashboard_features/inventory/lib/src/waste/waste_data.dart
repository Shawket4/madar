/// The Waste log's reads and what the web computes in the browser
/// (`waste-page.tsx`): the by-reason report keyed by the scope's period,
/// the by-reason sums, and the export walk of the whole log.
///
/// The log is a "Load more" window from the newest ([wasteLogProvider]);
/// Today's waste section keeps its own read (`todayWasteProvider`).
library;

import 'package:collection/collection.dart';
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The log's key: the branch (or the all-branches sentinel) and how far
/// "Load more" went (`limit`, always sent from offset 0).
typedef WasteLogKey = ({String branchId, int limit});

/// The waste log is a "Load more" window from the newest: the endpoint
/// answers 200 rows when no limit is sent and caps `limit` at 1000, so a
/// plain read silently stopped at the latest 200 entries.
const int wasteWindow = 100;
const int wasteWindowMax = 1000;

/// `GET /inventory/branches/{branch_id}/waste?limit=&offset=0` (listWaste).
final wasteLogProvider = FutureProvider.autoDispose
    .family<List<StockMovement>, WasteLogKey>((ref, k) {
      ref.webCache();
      ref.watch(
        realtimeEpochProvider('/inventory/branches/${k.branchId}/waste'),
      );
      return ref
          .watch(apiProvider)
          .inventory
          .listWaste(branchId: k.branchId, limit: k.limit, offset: 0);
    });

/// The report's key: the branch (or the all-branches sentinel) and the
/// period it sends.
typedef WasteRange = ({String id, String from, String to});

extension WasteKeys on Scope {
  /// INV-WST-002: the scoped branch (or all branches) over the PERIOD.
  WasteRange get wasteRange => (id: scopeBranchId, from: from, to: to);
}

/// `GET /reports/branches/{branch_id}/waste-report` (branchWasteReport).
final wasteReportProvider = FutureProvider.autoDispose
    .family<List<WasteReportRow>, WasteRange>((ref, k) {
      ref.webCache();
      ref.watch(
        realtimeEpochProvider('/reports/branches/${k.id}/waste-report'),
      );
      return ref
          .watch(apiProvider)
          .reports
          .branchWasteReport(
            branchId: k.id,
            from: DateTime.parse(k.from),
            to: DateTime.parse(k.to),
          );
    });

/// One reason's line: the summed value, and whether any line had a cost.
typedef ReasonTotal = ({String reason, int value, bool hasValue});

/// INV-WST-025: report rows summed per reason, largest value first (ties
/// keep the server's order, as the web's stable sort).
List<ReasonTotal> wasteByReason(List<WasteReportRow> rows) {
  final sums = <String, (int, bool)>{};
  for (final r in rows) {
    final (v, has) = sums[r.reason] ?? (0, false);
    sums[r.reason] = r.wasteValue == null
        ? (v, has)
        : (v + r.wasteValue!, true);
  }
  final out = [
    for (final e in sums.entries)
      (reason: e.key, value: e.value.$1, hasValue: e.value.$2),
  ];
  mergeSort(out, compare: (a, b) => b.value.compareTo(a.value));
  return out;
}

/// "Total this period": Σ every row's value (an unknown one counts 0).
int wasteTotal(List<WasteReportRow> rows) =>
    rows.fold(0, (s, r) => s + (r.wasteValue ?? 0));

/// INV-WST-004: the whole log for [branchId], walked 500 at a time and
/// declared as an export (`X-Madar-Export: 1`), never from the cache.
Future<List<StockMovement>> fetchWholeWasteLog(
  ApiTransport transport,
  String branchId,
) {
  final api = apiWithHeaders(transport, exportRequestHeaders);
  return fetchAllPages(
    (offset, limit) async => ExportPage(
      await api.inventory.listWaste(
        branchId: branchId,
        limit: limit,
        offset: offset,
      ),
    ),
  );
}
