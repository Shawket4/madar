/// The Waste log's reads and what the web computes in the browser
/// (`waste-page.tsx`): the by-reason report keyed by the scope's period,
/// the by-reason sums, and the export walk of the whole log.
///
/// The log itself is the read Today also shows (`todayWasteProvider` in
/// `shared/inventory_data.dart`, the same `/inventory/branches/{id}/waste`
/// key), so the two pages share a cache.
library;

import 'package:collection/collection.dart';
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  final api = DashboardApi(_HeaderTransport(transport, exportRequestHeaders));
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

/// The generated client with extra headers on every request.
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
