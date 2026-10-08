/// Purchasing's own reads (INV-PUR-003, -022, -043, -048) as providers keyed
/// like the web's React Query keys, and the helpers the page and its dialogs
/// share: the order reference, a load state, the web's number parsing and
/// the export with its toasts.
///
/// The shared reads (suppliers, catalog) live in `shared/inventory_data.dart`
/// so Today, Ingredients and these dialogs read one cache.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show GoodsReceipt, PurchaseOrder, PurchaseOrderFull, ReorderSuggestion;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show publicBrandProvider;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
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

/// An order's name in a table, a title or a sheet: its reference, else `#`
/// and the first 8 characters of its id.
String poReference({required String id, String? reference}) =>
    (reference != null && reference.isNotEmpty)
    ? reference
    : '#${id.length > 8 ? id.substring(0, 8) : id}';

/// A read as a record table or a section shows it: the web's `isLoading`
/// is a FIRST load only (a refetch keeps the rows), and an error wins over
/// rows (React Query keeps `error` beside stale `data`).
extension PurchasingAsyncX<T> on AsyncValue<T> {
  /// Loading with nothing to show yet.
  bool get firstLoad => isLoading && !hasValue && !hasError;

  /// The words for a failed read, or null.
  String? errorText(Translator t) =>
      hasError && !isLoading ? errorMessage(error, t) : null;
}

/// `parseFloat` of an `<input type="number">`'s text: blank or unreadable
/// is NaN; Arabic digits and the Arabic decimal sign are read too.
double parseInputNumber(String raw) => dashParseNumber(raw) ?? double.nan;

/// `String(n)` in JavaScript: a whole number without `.0`.
String jsNumberString(num n) {
  final d = n.toDouble();
  if (d.isFinite && d == d.truncateToDouble() && d.abs() < 1e21) {
    return d.toInt().toString();
  }
  return d.toString();
}

/// `piastres / 100` at exactly two decimals (`toFixed(2)`), for an input.
String piastresToEgpFixed(num piastres) => (piastres / 100).toStringAsFixed(2);

/// The logo a generated spreadsheet wears (`useExportLogo`): the shop's own
/// on the branding tier, else null (Madar's).
String? purchasingExportLogo(WidgetRef ref) {
  final brand = ref.read(publicBrandProvider).value;
  final logo = brand?.logoUrl?.trim();
  if (brand == null || !brand.customBranding) return null;
  return logo == null || logo.isEmpty ? null : logo;
}

/// `exportToExcel(config)` with the web's toasts (INV-ALL-013): nothing →
/// "Nothing to export"; else "Gathering data…" that turns into "Exported N
/// rows" or "Export failed".
Future<void> purchasingExportExcel(
  BuildContext context,
  WidgetRef ref,
  ExcelConfig config,
) async {
  final t = ref.read(tProvider);
  if (config.sheets.every((s) => s.rows.isEmpty)) {
    DashToast.error(context, const ExportNothing().message(t));
    return;
  }
  final toast = DashToast.loading(context, t('excel.generating'));
  final outcome = await ref.read(exporterProvider).exportToExcel(config);
  toast.update(
    outcome is ExportDone ? DashToastKind.success : DashToastKind.error,
    outcome.message(t),
  );
}
