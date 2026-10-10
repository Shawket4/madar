/// The Orders page's reads, one provider per endpoint, keyed by exactly the
/// params its request sends (the web's React Query key), and the excluded
/// items kept per org on this device.
///
/// Every read calls `ref.webCache()` first and watches the realtime epoch of
/// its own path: the void invalidates `/orders` and `/orders/<id>`, a
/// `till.*` event refetches the delivery block (`/reports`), a `delivery.*`
/// event an open sheet's delivery progress (SELL-ORD-086).
library;

import 'package:dashboard_api/dashboard_api.dart'
    show
        Branch,
        CustomerDetail,
        DeliveryOrder,
        DeliverySalesReport,
        MenuItem,
        OrderFull,
        OrgIngredient,
        PaginatedOrders;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

/// Rows per page (`pageSize` on the web, `ORDERS_PER_PAGE` in its prefetch).
const int ordersPerPage = 20;

/// The list's key: the scope, the filters and the page (1-based).
typedef OrdersKey = ({
  String? branchId,
  String? from,
  String? to,
  String? status,
  String? payment,
  String? teller,
  String? waiter,
  String? type,
  String? channel,
  String? exclude,
  String? till,
  int page,
});

/// A report read's key: the branch (or the all-branches sentinel) and the
/// period.
typedef OrdersRange = ({String id, String from, String to});

extension OrdersKeys on Scope {
  /// The list's first page with no filter: what the page asks on mount and
  /// what the sidebar warms (the web's `prefetchRoute('/orders')`, which
  /// leaves out the excluded items and the till).
  OrdersKey get ordersFirstPage => (
    branchId: branchId,
    from: from,
    to: to,
    status: null,
    payment: null,
    teller: null,
    waiter: null,
    type: null,
    channel: null,
    exclude: null,
    till: null,
    page: 1,
  );

  /// The delivery block's key: the branch or the all-branches sentinel.
  OrdersRange get deliveryRange => (id: scopeBranchId, from: from, to: to);

  /// The web asks nothing while neither a branch nor an org is in scope.
  bool get ordersEnabled => branchId != null || orgId != null;
}

DateTime? _instant(String? iso) => iso == null ? null : DateTime.parse(iso);

/// SELL-ORD-002 `GET /orders`.
final ordersListProvider = FutureProvider.autoDispose
    .family<PaginatedOrders, OrdersKey>((ref, k) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/orders'));
      return ref
          .watch(apiProvider)
          .orders
          .listOrders(
            branchId: k.branchId,
            from: _instant(k.from),
            to: _instant(k.to),
            status: k.status,
            paymentMethod: k.payment,
            tellerName: k.teller,
            waiterName: k.waiter,
            orderType: k.type,
            channel: k.channel,
            excludeItems: k.exclude,
            tillId: k.till,
            page: k.page,
            perPage: ordersPerPage,
          );
    });

/// SELL-ORD-016 `GET /reports/branches/{id}/delivery-sales`.
final ordersDeliveryProvider = FutureProvider.autoDispose
    .family<DeliverySalesReport, OrdersRange>((ref, k) {
      ref.webCache();
      ref.watch(
        realtimeEpochProvider('/reports/branches/${k.id}/delivery-sales'),
      );
      return ref
          .watch(apiProvider)
          .reports
          .branchDeliverySales(
            branchId: k.id,
            from: DateTime.parse(k.from),
            to: DateTime.parse(k.to),
          );
    });

/// SELL-ORD-035 `GET /orders/{order_id}`.
final orderDetailProvider = FutureProvider.autoDispose
    .family<OrderFull, String>((ref, id) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/orders/$id'));
      return ref.watch(apiProvider).orders.getOrder(orderId: id);
    });

/// SELL-ORD-045 `GET /delivery-orders/{id}`: the delivery's steps.
final orderDeliveryProvider = FutureProvider.autoDispose
    .family<DeliveryOrder, String>((ref, id) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/delivery-orders/$id'));
      return ref.watch(apiProvider).delivery.getDeliveryOrder(id: id);
    });

/// SELL-ORD-044 `GET /customers/{id}`: who a one-time delivery belongs to
/// (asked once: no retry).
final orderOwnerProvider = FutureProvider.autoDispose
    .family<CustomerDetail, String>((ref, id) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/customers/$id'));
      return ref.watch(apiProvider).customers.getCustomer(id: id);
    }, retry: (_, _) => null);

/// SELL-ORD-056 `GET /inventory/orgs/{org_id}/catalog`: prices the
/// ingredient deductions a snapshot left unpriced.
final orderCatalogProvider = FutureProvider.autoDispose
    .family<List<OrgIngredient>, String>((ref, orgId) {
      // `order-detail-sheet.tsx:77`: `staleTime: 5 * 60_000`.
      ref.webCache(staleTime: const Duration(minutes: 5));
      ref.watch(realtimeEpochProvider('/inventory/orgs/$orgId/catalog'));
      return ref.watch(apiProvider).inventory.listCatalog(orgId: orgId);
    });

/// SELL-ORD-014 `GET /menu-items?org_id=`: read once the exclude list opens.
final ordersMenuItemsProvider = FutureProvider.autoDispose
    .family<List<MenuItem>, String>((ref, orgId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/menu-items'));
      return ref.watch(apiProvider).menu.listMenuItems(orgId: orgId);
    });

/// SELL-ORD-074 `GET /branches/{id}`: the export's branch name.
final ordersExportBranchProvider = FutureProvider.autoDispose
    .family<Branch, String>((ref, id) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/branches/$id'));
      return ref.watch(apiProvider).branches.getBranch(id: id);
    });

// ── helpers ───────────────────────────────────────────────────────────────

/// Watches [provider] only when [enabled] (a web query's `enabled: false`
/// asks nothing and is not loading).
AsyncValue<T?> watchIfOrders<T>(
  WidgetRef ref,
  bool enabled,
  ProviderListenable<AsyncValue<T>> Function() provider,
) => enabled ? ref.watch(provider()) : const AsyncData(null);
