/// `/reports/financial` Financial (REP-FIN rows): tabs Menu profitability
/// (Ledger, Repricing, Decisions), Revenue, Channel, Valuation, Supplier
/// spend, Material cost trend (`features/reports/financial/financial-reports-page.tsx`).
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/report_shared.dart';

/// The route's page (`DashRoute.builder`).
Widget financialPageBuilder(BuildContext context, GoRouterState state) =>
    const FinancialReportPage();

/// The tabs, in the web's order, each shown only to a holder of its
/// capability (REP-FIN-001, `fin:39-52`). The page is Restricted when none
/// is visible (REP-FIN-002).
const List<DashRouteTab> financialTabs = [
  DashRouteTab(
    id: 'profitability',
    labelKey: 'reports.financial.tabs.profitability',
    caps: [Cap.ordersRead],
  ),
  DashRouteTab(
    id: 'revenue',
    labelKey: 'reports.financial.tabs.revenue',
    caps: [Cap.ordersRead],
  ),
  DashRouteTab(
    id: 'channel',
    labelKey: 'reports.financial.tabs.channel',
    caps: [Cap.ordersRead],
  ),
  DashRouteTab(
    id: 'valuation',
    labelKey: 'reports.financial.tabs.valuation',
    caps: [Cap.inventoryRead],
  ),
  DashRouteTab(
    id: 'supplierSpend',
    labelKey: 'reports.financial.tabs.supplierSpend',
    caps: [Cap.purchasingOrdersRead],
  ),
  DashRouteTab(
    id: 'materialCostTrend',
    labelKey: 'reports.financial.tabs.materialCostTrend',
    caps: [Cap.purchasingOrdersRead],
  ),
];

class FinancialReportPage extends ConsumerWidget {
  const FinancialReportPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return DashPageScaffold(
      title: t('reports.financial.title'),
      subtitleWidget: const ReportPeriodSubtitle(),
      body: DashEmptyState(
        icon: 'layers',
        title: t('shell.pendingTitle'),
        description: t('shell.pendingBody'),
      ),
    );
  }
}
