/// The QR page's reads (`features/qr/*`): one code per kind and render
/// options, the branch's tables, and one code per table.
///
/// The web calls these imperatively (no React Query); here they are cached
/// reads keyed by exactly the request's params, so a Generate button can be
/// warmed on intent and a press answers from that warm read. The press then
/// drops it (the server redraws the card from the current brand each time),
/// and nothing is retried: the next press asks again, as on the web.
library;

import 'package:dashboard_api/dashboard_api.dart' show BranchTable, QrResponse;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The five single codes the page makes (the web's `QrKind` list, in order).
enum QrKind {
  orgOrder(org: true),
  orgBooking(org: true),
  branchOrder(org: false),
  branchBooking(org: false),
  branchOrderInMall(org: false);

  const QrKind({required this.org});

  /// Made for the whole organization (needs "All branches"); else for the
  /// header's branch.
  final bool org;
}

/// The in-mall card's three fields (`place_name`, `floor`, `unit_number`).
typedef QrPlace = ({String placeName, String floor, String unitNumber});

/// One single code's request: the kind, the org or branch id, the render
/// options (`card`, `dpi`) and, for the in-mall kind, the place.
typedef QrKey = ({QrKind kind, String id, bool card, int dpi, QrPlace? place});

/// `GET /orgs/{id}/qr`, `/orgs/{id}/booking-qr`, `/branches/{id}/qr`
/// (with the place for the in-mall kind) or `/branches/{id}/booking-qr`.
final qrCodeProvider = FutureProvider.autoDispose.family<QrResponse, QrKey>((
  ref,
  k,
) {
  ref.webCache();
  final qr = ref.watch(apiProvider).qr;
  return switch (k.kind) {
    QrKind.orgOrder => qr.orgQr(id: k.id, card: k.card, dpi: k.dpi),
    QrKind.orgBooking => qr.orgBookingQr(id: k.id, card: k.card, dpi: k.dpi),
    QrKind.branchOrder => qr.branchQr(id: k.id, card: k.card, dpi: k.dpi),
    QrKind.branchBooking => qr.branchBookingQr(
      id: k.id,
      card: k.card,
      dpi: k.dpi,
    ),
    QrKind.branchOrderInMall => qr.branchQr(
      id: k.id,
      card: k.card,
      dpi: k.dpi,
      placeName: k.place!.placeName,
      floor: k.place!.floor,
      unitNumber: k.place!.unitNumber,
    ),
  };
}, retry: (_, _) => null);

/// `GET /branches/{id}/tables` (`useListTables`, enabled with a branch).
final qrTablesProvider = FutureProvider.autoDispose
    .family<List<BranchTable>, String>((ref, branchId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/branches/$branchId/tables'));
      return ref.watch(apiProvider).qr.listTables(id: branchId);
    });

/// One table's code: `GET /branches/{id}/tables/{tid}/qr?caption=<label>`.
typedef QrTableKey = ({String branchId, String tableId, String caption});

final qrTableCodeProvider = FutureProvider.autoDispose
    .family<QrResponse, QrTableKey>((ref, k) {
      ref.webCache();
      return ref
          .watch(apiProvider)
          .qr
          .tableQr(id: k.branchId, tid: k.tableId, caption: k.caption);
    }, retry: (_, _) => null);

/// The table codes for [rows] at [branchId], one request at a time (the
/// web's sequential loop: a shared short-link provider rate-limits a burst).
/// A failure drops its read from the cache and is rethrown.
Future<List<(BranchTable, QrResponse)>> readTableCodes(
  ProviderContainer container,
  String branchId,
  List<BranchTable> rows,
) async {
  final out = <(BranchTable, QrResponse)>[];
  for (final row in rows) {
    final read = qrTableCodeProvider((
      branchId: branchId,
      tableId: row.id,
      caption: row.label,
    ));
    try {
      out.add((row, await container.read(read.future)));
    } on Object {
      container.invalidate(read);
      rethrow;
    }
  }
  return out;
}
