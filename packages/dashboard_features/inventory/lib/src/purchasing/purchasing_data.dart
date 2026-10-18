/// Purchasing's own reads (INV-PUR-003, -022, -043, -048) as providers keyed
/// like the web's React Query keys, and the helpers the page and its dialogs
/// share: the order reference and the web's number parsing. The load state,
/// `jsNumberString` and the export live in `shared/`.
///
/// The shared reads (suppliers, catalog) live in `shared/inventory_data.dart`
/// so Today, Ingredients and these dialogs read one cache.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show
        GoodsReceipt,
        LastPrice,
        PurchaseOrder,
        PurchaseOrderFull,
        ReorderSuggestion;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart' show dashParseNumber;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `listPurchaseOrders(scopeBranchId, {status})`: a branch, or the
/// all-branches sentinel; [status] null = every status.
typedef PurchaseOrdersKey = ({String branchId, String? status});

/// `GET /purchasing/branches/{branch_id}/orders?status=` (newest first).
final purchaseOrdersProvider = FutureProvider.autoDispose
    .family<List<PurchaseOrder>, PurchaseOrdersKey>((ref, k) {
      ref.webCache();
      ref.watch(
        realtimeEpochProvider('/purchasing/branches/${k.branchId}/orders'),
      );
      return ref
          .watch(apiProvider)
          .purchasing
          .listPurchaseOrders(branchId: k.branchId, status: k.status);
    });

/// `GET /purchasing/branches/{branch_id}/reorder-suggestions`: one group
/// per default supplier, in the server's order.
final reorderSuggestionsProvider = FutureProvider.autoDispose
    .family<List<ReorderSuggestion>, String>((ref, branchId) {
      ref.webCache();
      ref.watch(
        realtimeEpochProvider(
          '/purchasing/branches/$branchId/reorder-suggestions',
        ),
      );
      return ref
          .watch(apiProvider)
          .purchasing
          .reorderSuggestions(branchId: branchId);
    });

/// `GET /purchasing/orders/{id}`: the order and its lines (the receive
/// dialog, while it is open).
final purchaseOrderProvider = FutureProvider.autoDispose
    .family<PurchaseOrderFull, String>((ref, id) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/purchasing/orders/$id'));
      return ref.watch(apiProvider).purchasing.getPurchaseOrder(id: id);
    });

/// `GET /purchasing/orders/{id}/receipts`: the order's deliveries, newest
/// first. The dialog refreshes it every time its history tab opens.
final poReceiptsProvider = FutureProvider.autoDispose
    .family<List<GoodsReceipt>, String>((ref, id) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/purchasing/orders/$id/receipts'));
      return ref.watch(apiProvider).purchasing.listPoReceipts(id: id);
    });

/// `listPurchaseLastPrices(orgId, {supplier_id})`: [supplierId] null = no
/// supplier chosen (any supplier's last price).
typedef LastPricesKey = ({String orgId, String? supplierId});

/// `GET /purchasing/orgs/{org_id}/last-prices?supplier_id=`: the last price
/// paid per ingredient (the supplier's, else any supplier's), the New
/// purchase order dialog's default for a line.
final lastPricesProvider = FutureProvider.autoDispose
    .family<List<LastPrice>, LastPricesKey>((ref, k) {
      ref.webCache();
      ref.watch(
        realtimeEpochProvider('/purchasing/orgs/${k.orgId}/last-prices'),
      );
      return ref
          .watch(apiProvider)
          .purchasing
          .listPurchaseLastPrices(orgId: k.orgId, supplierId: k.supplierId);
    });

/// An order's name in a table, a title or a sheet: its reference, else `#`
/// and the first 8 characters of its id.
String poReference({required String id, String? reference}) =>
    (reference != null && reference.isNotEmpty)
    ? reference
    : '#${id.length > 8 ? id.substring(0, 8) : id}';

/// `parseFloat` of an `<input type="number">`'s text: blank or unreadable
/// is NaN; Arabic digits and the Arabic decimal sign are read too.
double parseInputNumber(String raw) => dashParseNumber(raw) ?? double.nan;

/// `piastres / 100` at exactly two decimals (`toFixed(2)`), for an input.
String piastresToEgpFixed(num piastres) => (piastres / 100).toStringAsFixed(2);
