/// The floor page's reads (SELL-FLR-002, -067), each keyed like the web's
/// query (the branch, or the table) and refreshed by the same invalidations:
/// a floor write's `invalidateFloor` (every `/floor…` read), a transfer's
/// `invalidateOccupants` (`/open-tickets`), and the realtime `floor.*`,
/// `table.*`, `transfer.*`, `booking.*`, `ticket.*` events (SELL-ALL-006).
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `GET /floor/sections?branch_id=` (`useListSections`).
final floorSectionsProvider = FutureProvider.autoDispose
    .family<List<FloorSection>, String>((ref, branchId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/floor/sections'));
      return ref
          .watch(apiProvider)
          .reservations
          .listSections(branchId: branchId);
    });

/// `GET /floor/tables?branch_id=` (`useListFloorTables`): every table of the
/// branch, inactive ones included.
final floorTablesProvider = FutureProvider.autoDispose
    .family<List<FloorTable>, String>((ref, branchId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/floor/tables'));
      return ref
          .watch(apiProvider)
          .reservations
          .listFloorTables(branchId: branchId);
    });

/// `GET /floor/transfers?branch_id=` (`useListFloorTransfers`): the waiting
/// requests.
final floorTransfersProvider = FutureProvider.autoDispose
    .family<TransfersSyncResponse, String>((ref, branchId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/floor/transfers'));
      return ref
          .watch(apiProvider)
          .floorTransfers
          .listFloorTransfers(branchId: branchId);
    });

/// `GET /open-tickets?branch_id=` (`useListOpenTickets`): who sits where.
/// Best effort, `retry: false` as on the web: without `tickets.read` the
/// floor still draws, only without names.
final floorOpenTicketsProvider = FutureProvider.autoDispose
    .family<List<OpenTicketView>, String>((ref, branchId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/open-tickets'));
      return ref
          .watch(apiProvider)
          .openTickets
          .listOpenTickets(branchId: branchId);
    }, retry: (_, _) => null);

/// `GET /floor/tables/{id}/history` (`useTableHistory`, no window: the last
/// 30 days).
final floorTableHistoryProvider = FutureProvider.autoDispose
    .family<TableHistory, String>((ref, tableId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/floor/tables/$tableId/history'));
      return ref.watch(apiProvider).floor.tableHistory(id: tableId);
    });

/// React Query's `isLoading`: loading with nothing to show yet.
extension FloorQueryState<T> on AsyncValue<T> {
  bool get firstLoad => isLoading && !hasValue && !hasError;
}
