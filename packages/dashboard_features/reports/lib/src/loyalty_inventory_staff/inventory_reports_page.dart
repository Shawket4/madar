/// `/reports/inventory` Inventory reports (REP-INV rows): tabs Consumption,
/// Shrinkage, Waste, PO lead time, Low stock
/// (`features/inventory/inventory-reports-page.tsx`, `reports-page.tsx`,
/// `low-stock-tab.tsx`).
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/report_shared.dart';

/// The route's page (`DashRoute.builder`).
Widget inventoryReportsPageBuilder(BuildContext context, GoRouterState state) =>
    const InventoryReportsPage();

/// The tabs (REP-INV-003/004), page state; default Consumption. PO lead time
/// needs `purchasing.orders.read` as well as the page's `inventory.read`.
const List<DashRouteTab> inventoryReportTabs = [
  DashRouteTab(id: 'consumption', labelKey: 'inventory.reports.consumption'),
  DashRouteTab(id: 'shrinkage', labelKey: 'inventory.reports.shrinkage'),
  DashRouteTab(id: 'waste', labelKey: 'inventory.reports.wasteReport'),
  DashRouteTab(
    id: 'poLeadTime',
    labelKey: 'inventory.reports.poLeadTime',
    caps: [Cap.purchasingOrdersRead],
  ),
  DashRouteTab(id: 'lowStock', labelKey: 'reports.operations.tabs.lowStock'),
];

class InventoryReportsPage extends ConsumerWidget {
  const InventoryReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return DashPageScaffold(
      title: t('inventory.reports.title'),
      subtitleWidget: const ReportPeriodSubtitle(),
      body: DashEmptyState(
        icon: 'layers',
        title: t('shell.pendingTitle'),
        description: t('shell.pendingBody'),
      ),
    );
  }
}
