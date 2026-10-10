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
import 'package:design_system/design_system.dart' show Space;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/report_shared.dart';
import 'ops_analytics.dart';
import 'ops_data.dart';
import 'ops_export.dart';
import 'ops_overview.dart';
import 'ops_tables.dart';

/// The route's page (`DashRoute.builder`).
Widget operationsPageBuilder(BuildContext context, GoRouterState state) =>
    const OperationsReportPage();

/// The web's `prefetchRoute('/reports/operations')`: the default tab is
/// Tables (not prefetched); the Overview's branch sales are warmed when a
/// branch is picked, with no exclusions (the web's key carries none, so a
/// person with excluded items reads again, REP-ALL-029).
void prefetchOperations(DashPrefetcher warm, Scope s) {
  if (s.branchId != null) warm(opsSalesProvider(s.opsSales(null)));
}

/// Intent: warms what [tab]'s view reads when it mounts (its watches).
void opsWarmTab(WidgetRef ref, String tab) {
  final s = ref.read(currentScopeProvider);
  switch (tab) {
    case 'overview':
      final ex = excludeItemsParam(ref.read(excludedItemsProvider(s.orgId)));
      ref.warm(opsSalesProvider(s.opsSales(ex)));
    case 'items':
      ref.warm(opsItemsProvider(s.opsRange));
      ref.warm(opsAddonsProvider(s.opsRange));
    case 'tellers':
      ref.warm(opsTellersProvider(s.opsRange));
    case 'waiters':
      ref.warm(opsWaitersProvider(s.opsRange));
    case 'branches':
      if (s.orgId != null) ref.warm(opsBranchesProvider(s.opsOrgRange));
    default:
      final locale = opsMetricsLocale(ref.read(localeProvider));
      ref.warm(opsTablesProvider(s.opsTables(locale)));
      final branchId = s.branchId;
      if (branchId != null) ref.warm(opsFloorTablesProvider(branchId));
  }
}

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
    final authz = ref.watch(authzProvider);
    final title = t('reports.operations.title');
    if (!authz.ready) {
      // As the shell's gate (divergence SH-10): nothing while the person's
      // rights load, an error with Retry if they could not be read.
      final error = authz.error;
      if (error == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsetsDirectional.all(Space.xl),
        child: DashErrorState(
          title: t('shell.accessLoadError'),
          message: errorMessage(error, t),
          retryLabel: t('common.retry'),
          onRetry: () => ref.read(authzProvider.notifier).refresh(),
        ),
      );
    }
    // REP-OPS-001 / REP-ALL-005.
    if (!authz.can(Cap.ordersRead)) {
      return Restricted(title: title, who: t('reports.noAccess'));
    }
    final body = switch (_tab) {
      'overview' => const OpsOverviewView(),
      'items' => const OpsItemsView(),
      'tellers' => const OpsTellersView(),
      'waiters' => const OpsWaitersView(),
      'branches' => const OpsBranchesView(),
      _ => const OpsTablesView(),
    };
    return DashPageScaffold(
      title: title,
      subtitleWidget: const ReportPeriodSubtitle(),
      actions: [
        if (opsExportTabs.contains(_tab))
          OpsExportButton(key: ValueKey('ops-export-$_tab'), tab: _tab),
      ],
      tabs: DashPageTabs<String>(
        value: _tab,
        onChanged: (v) => setState(() => _tab = v),
        onIntent: (v) => opsWarmTab(ref, v),
        tabs: [
          for (final tab in operationsTabs)
            DashTab(value: tab.id, label: t(tab.labelKey)),
        ],
      ),
      body: KeyedSubtree(key: ValueKey('ops-tab-$_tab'), child: body),
    );
  }
}
