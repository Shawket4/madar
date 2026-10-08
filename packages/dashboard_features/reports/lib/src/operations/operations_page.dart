/// `/reports/operations` Operations (REP-OPS rows, plus the area-wide
/// REP-ALL rows): tabs Tables (default), Overview, Items, Tellers, Waiters,
/// Branches (`features/reports/operations/operations-reports-page.tsx`).
///
/// The tabs are page state, not routes (REP-ALL-022): a reload or a deep
/// link opens Tables. The header carries the period and, on the four tabs
/// that put rows in a table, the export (REP-OPS-004). Tables is a whole
/// page nested in this one, its header a sub-heading (REP-ALL-021).
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/report_shared.dart';
import 'ops_analytics.dart';
import 'ops_export.dart';
import 'ops_overview.dart';
import 'ops_support.dart';
import 'ops_tables.dart';

/// The route's page (`DashRoute.builder`).
Widget operationsPageBuilder(BuildContext context, GoRouterState state) =>
    const OperationsReportPage();

/// The tab strip, in the web's order (REP-OPS-003). Tabs are page state,
/// not routes (REP-ALL-022); every tab shows to whoever sees the page.
const List<DashRouteTab> operationsTabs = [
  DashRouteTab(id: 'tables', labelKey: 'reports.operations.tabs.tables'),
  DashRouteTab(id: 'overview', labelKey: 'reports.operations.tabs.overview'),
  DashRouteTab(id: 'items', labelKey: 'reports.operations.tabs.items'),
  DashRouteTab(id: 'tellers', labelKey: 'reports.operations.tabs.tellers'),
  DashRouteTab(id: 'waiters', labelKey: 'reports.operations.tabs.waiters'),
  DashRouteTab(id: 'branches', labelKey: 'reports.operations.tabs.branches'),
];

class OperationsReportPage extends ConsumerStatefulWidget {
  const OperationsReportPage({this.initialTab = 'tables', super.key});

  /// The tab shown first (Tables, as on the web).
  final String initialTab;

  @override
  ConsumerState<OperationsReportPage> createState() =>
      _OperationsReportPageState();
}

class _OperationsReportPageState extends ConsumerState<OperationsReportPage> {
  late String _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    // The page's read cache: each tab's reads stay while the page is open.
    ref.watch(opsCacheProvider);
    final body = switch (_tab) {
      'overview' => const OpsOverviewView(),
      'items' => const OpsItemsView(),
      'tellers' => const OpsTellersView(),
      'waiters' => const OpsWaitersView(),
      'branches' => const OpsBranchesView(),
      _ => const OpsTablesView(),
    };
    return DashPageScaffold(
      title: t('reports.operations.title'),
      subtitleWidget: const ReportPeriodSubtitle(),
      actions: [
        if (opsExportTabs.contains(_tab))
          OpsExportButton(key: ValueKey('ops-export-$_tab'), tab: _tab),
      ],
      tabs: DashPageTabs<String>(
        value: _tab,
        onChanged: (v) => setState(() => _tab = v),
        tabs: [
          for (final tab in operationsTabs)
            DashTab(value: tab.id, label: t(tab.labelKey)),
        ],
      ),
      body: KeyedSubtree(key: ValueKey('ops-tab-$_tab'), child: body),
    );
  }
}
