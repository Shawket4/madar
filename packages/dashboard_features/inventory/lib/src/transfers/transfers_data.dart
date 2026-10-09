/// The Transfers page's reads (`transfers-page.tsx`): the list keyed by the
/// scoped branch (or the all-branches id) and the direction filter, and the
/// export walk of the whole list.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The list's key: the branch it reads and the direction it sends (null =
/// all, the parameter omitted).
typedef TransfersKey = ({String branchId, String? direction});

/// The directions the segmented control offers (null = "All transfers").
const List<String?> transferDirections = [null, 'incoming', 'outgoing'];

extension TransfersKeys on Scope {
  /// INV-TRF-002: the scoped branch, or the all-branches id.
  TransfersKey transfersKey(String? direction) =>
      (branchId: scopeBranchId, direction: direction);
}

/// `GET /inventory/branches/{branch_id}/transfers` (listTransfers): the
/// server's 200 most recent.
final transfersProvider = FutureProvider.autoDispose
    .family<List<StockTransfer>, TransfersKey>((ref, k) {
      ref.webCache();
      ref.watch(
        realtimeEpochProvider('/inventory/branches/${k.branchId}/transfers'),
      );
      return ref
          .watch(apiProvider)
          .inventory
          .listTransfers(branchId: k.branchId, direction: k.direction);
    });

/// INV-TRF-005: the whole list for [k], walked 500 at a time and declared
/// as an export (`X-Madar-Export: 1`), never from the cache.
Future<List<StockTransfer>> fetchAllTransfers(
  ApiTransport transport,
  TransfersKey k,
) {
  final api = DashboardApi(_ExportTransport(transport));
  return fetchAllPages(
    (offset, limit) async => ExportPage(
      await api.inventory.listTransfers(
        branchId: k.branchId,
        direction: k.direction,
        limit: limit,
        offset: offset,
      ),
    ),
  );
}

/// The transport with [exportRequestHeaders] on every request.
class _ExportTransport implements ApiTransport {
  _ExportTransport(this.inner);

  final ApiTransport inner;

  ApiRequest _with(ApiRequest r) => ApiRequest(
    method: r.method,
    path: r.path,
    query: r.query,
    body: r.body,
    files: r.files,
    headers: {...r.headers, ...exportRequestHeaders},
  );

  @override
  Future<ApiResponse> send(ApiRequest request) => inner.send(_with(request));

  @override
  Stream<String> stream(ApiRequest request) => inner.stream(_with(request));
}

/// ponytail: stop-gap so the old one-line transfers unit compiles against the
/// document API (af50aa63: `lines`, `created`); the INV-TRF rebuild removes it.
extension OldTransferView on StockTransfer {
  StockTransferLine? get _first => lines.isEmpty ? null : lines.first;
  String get ingredientName => _first?.ingredientName ?? '';
  double get quantity => _first?.qtySent ?? 0;
  String get unit => _first?.unit ?? '';
  DateTime get initiatedAt => created.at;
  String get initiatedByName => created.byName;
}
