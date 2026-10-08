/// `/inventory/purchasing` (INV-PUR-001…027, -058…062, -072; web
/// `src/features/inventory/purchasing-page.tsx`): purchase orders, suppliers
/// and the Reorder suggestions, with the New purchase order, Receive and
/// supplier dialogs.
///
/// No control here is gated by capability (INV-PUR-062): a person missing
/// one sees the read's 403 in that table's error state, or the write's 403
/// in a toast. The tab and the status filter are kept on screen (never in
/// the URL) and across scope changes.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show PurchaseOrder, Supplier;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/inventory_data.dart';
import '../shared/inventory_labels.dart';
import '../shared/no_org.dart';
import 'orders_tab.dart';
import 'purchase_order_dialog.dart';
import 'purchasing_data.dart';
import 'purchasing_widgets.dart';
import 'reorder_tab.dart';
import 'supplier_dialog.dart';
import 'suppliers_tab.dart';

/// The page's tabs.
enum PurchasingView { orders, suppliers, reorder }

class PurchasingPage extends ConsumerStatefulWidget {
  const PurchasingPage({super.key});

  @override
  ConsumerState<PurchasingPage> createState() => _PurchasingPageState();
}

class _PurchasingPageState extends ConsumerState<PurchasingPage> {
  PurchasingView _view = PurchasingView.orders;
  String _status = allPoStatuses;
  bool _exporting = false;

  Future<void> _export({
    required PurchasingView view,
    required List<PurchaseOrder> orders,
    required List<Supplier> suppliers,
  }) async {
    final t = ref.read(tProvider);
    final logo = purchasingExportLogo(ref);
    // Both lists are whole (unpaged), and the orders already carry the
    // status filter: what the tab shows is what the file holds. The Reorder
    // tab exports the suppliers, as the web does.
    final ExcelConfig config;
    if (view == PurchasingView.orders) {
      config = ExcelConfig(
        filename: 'Madar-PurchaseOrders',
        logoUrl: logo,
        sheets: [
          ExcelSheet<Object?>(
            name: t('inventory.purchasing.orders'),
            title: t('inventory.purchasing.orders'),
            rows: orders,
            columns: [
              ExcelColumn<Object?>(
                header: t('inventory.purchasing.reference'),
                accessor: (r) {
                  final po = r! as PurchaseOrder;
                  return poReference(id: po.id, reference: po.reference);
                },
                type: ExcelColumnType.text,
                width: 20,
              ),
              ExcelColumn<Object?>(
                header: t('inventory.purchasing.supplier'),
                accessor: (r) => (r! as PurchaseOrder).supplierName ?? '—',
                type: ExcelColumnType.text,
                width: 22,
              ),
              ExcelColumn<Object?>(
                header: t('inventory.purchasing.status'),
                accessor: (r) => poStatusLabel(t, (r! as PurchaseOrder).status),
                type: ExcelColumnType.text,
                width: 16,
              ),
              ExcelColumn<Object?>(
                header: t('inventory.purchasing.expectedAt'),
                accessor: (r) {
                  final at = (r! as PurchaseOrder).expectedAt;
                  return at == null ? '' : isoString(at);
                },
                type: ExcelColumnType.date,
                width: 16,
              ),
              ExcelColumn<Object?>(
                header: t('inventory.purchasing.createdAt'),
                accessor: (r) => isoString((r! as PurchaseOrder).createdAt),
                type: ExcelColumnType.date,
                width: 16,
              ),
            ],
          ),
        ],
      );
    } else {
      config = ExcelConfig(
        filename: 'Madar-Suppliers',
        logoUrl: logo,
        sheets: [
          ExcelSheet<Object?>(
            name: t('inventory.purchasing.suppliers'),
            title: t('inventory.purchasing.suppliers'),
            rows: suppliers,
            columns: [
              ExcelColumn<Object?>(
                header: t('inventory.purchasing.supplier'),
                accessor: (r) => (r! as Supplier).name,
                type: ExcelColumnType.text,
                width: 26,
              ),
              ExcelColumn<Object?>(
                header: t('inventory.purchasing.contactName'),
                accessor: (r) => (r! as Supplier).contactName ?? '—',
                type: ExcelColumnType.text,
                width: 22,
              ),
              ExcelColumn<Object?>(
                header: t('inventory.purchasing.email'),
                accessor: (r) => (r! as Supplier).email ?? '—',
                type: ExcelColumnType.text,
                width: 26,
              ),
              ExcelColumn<Object?>(
                header: t('inventory.purchasing.phone'),
                accessor: (r) => (r! as Supplier).phone ?? '—',
                type: ExcelColumnType.text,
                width: 18,
              ),
              ExcelColumn<Object?>(
                header: t('common.status'),
                accessor: (r) => (r! as Supplier).isActive
                    ? t('common.active')
                    : t('common.inactive'),
                type: ExcelColumnType.text,
                width: 12,
              ),
            ],
          ),
        ],
      );
    }
    setState(() => _exporting = true);
    try {
      await purchasingExportExcel(context, ref, config);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final orgId = ref.watch(orgIdProvider);
    if (orgId == null) {
      return InventoryNoOrgPage(title: t('inventory.purchasing.title'));
    }
    final branchId = ref.watch(currentScopeProvider.select((s) => s.branchId));
    final allBranches = branchId == null;
    final scopeBranchId = branchId ?? allBranchesId;

    final suppliers = ref.watch(inventorySuppliersProvider(orgId));
    // The PO dialog's ingredient picker reads the same cache.
    ref.watch(inventoryCatalogProvider(orgId));
    final ordersKey = (
      branchId: scopeBranchId,
      status: _status == allPoStatuses ? null : _status,
    );
    final orders = ref.watch(purchaseOrdersProvider(ordersKey));

    // Reorder is per branch: with All branches its tab is off and the page
    // shows the orders instead (the web would show a false "No items to
    // reorder"; see the divergence log). The choice is kept, so picking a
    // branch again returns to it.
    final view = _view == PurchasingView.reorder && allBranches
        ? PurchasingView.orders
        : _view;

    final exportable = view == PurchasingView.orders
        ? orders.value ?? const <PurchaseOrder>[]
        : suppliers.value ?? const <Supplier>[];

    return DashPageScaffold(
      title: t('inventory.purchasing.title'),
      actions: [
        DashExportButton(
          key: const ValueKey('purchasing-export'),
          loading: _exporting,
          enabled: exportable.isNotEmpty,
          onExport: () => _export(
            view: view,
            orders: orders.value ?? const [],
            suppliers: suppliers.value ?? const [],
          ),
        ),
        if (view == PurchasingView.orders)
          DashButton(
            key: const ValueKey('purchasing-new-order'),
            label: t('inventory.purchasing.newOrder'),
            icon: 'plus-circle',
            onPressed: branchId == null
                ? null
                : () => showPurchaseOrderDialog(context, branchId: branchId),
          )
        else if (view == PurchasingView.suppliers)
          DashButton(
            key: const ValueKey('purchasing-new-supplier'),
            label: t('inventory.purchasing.newSupplier'),
            icon: 'plus-circle',
            onPressed: () => showSupplierDialog(context, orgId: orgId),
          ),
      ],
      tabs: PurchasingTabStrip<PurchasingView>(
        key: const ValueKey('purchasing-tabs'),
        tabs: [
          PurchasingTab(
            value: PurchasingView.orders,
            label: t('inventory.purchasing.orders'),
            icon: 'truck',
          ),
          PurchasingTab(
            value: PurchasingView.suppliers,
            label: t('inventory.purchasing.suppliers'),
            icon: 'users',
          ),
          PurchasingTab(
            value: PurchasingView.reorder,
            label: t('inventory.purchasing.reorder'),
            icon: 'trending-down',
            enabled: !allBranches,
          ),
        ],
        value: view,
        onChanged: (v) => setState(() => _view = v),
      ),
      body: switch (view) {
        PurchasingView.orders => PurchaseOrdersTab(
          ordersKey: ordersKey,
          allBranches: allBranches,
          status: _status,
          onStatus: (s) => setState(() => _status = s),
        ),
        PurchasingView.suppliers => SuppliersTab(orgId: orgId),
        PurchasingView.reorder => ReorderTab(branchId: branchId!),
      },
    );
  }
}
