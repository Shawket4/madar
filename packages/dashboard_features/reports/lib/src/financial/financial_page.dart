/// `/reports/financial` Financial (REP-FIN rows): tabs Menu profitability
/// (Ledger, Repricing, Decisions), Revenue, Channel, Valuation, Supplier
/// spend, Material cost trend (`features/reports/financial/financial-reports-page.tsx`).
///
/// Each tab shows only to a holder of its capability; with none the page is
/// Restricted with the reports' words (REP-FIN-001/002). Tabs are page state
/// (REP-ALL-022); the granularity and the inventory scope live here so they
/// survive switching tabs (REP-FIN-005, 054).
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart' show Space;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/report_shared.dart';
import 'fin_data.dart';
import 'fin_export.dart';
import 'fin_inventory.dart';
import 'fin_profitability.dart';
import 'fin_sales.dart';

/// The route's page (`DashRoute.builder`).
Widget financialPageBuilder(BuildContext context, GoRouterState state) =>
    const FinancialReportPage();

/// The web's `prefetchRoute('/reports/financial')`: the default tab's
/// ledger (Snapshot basis) for the scope branch or the sentinel, with an
/// org in scope (REP-ALL-029).
void prefetchFinancial(DashPrefetcher warm, Scope s) {
  if (s.orgId != null) warm(finLedgerProvider(s.finLedger()));
}

/// The tabs, in the web's order, each shown only to a holder of its
/// capability (REP-FIN-001, `fin:39-52`).
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

const Set<String> _inventoryTabs = {
  'valuation',
  'supplierSpend',
  'materialCostTrend',
};

class FinancialReportPage extends ConsumerStatefulWidget {
  const FinancialReportPage({super.key});

  @override
  ConsumerState<FinancialReportPage> createState() =>
      _FinancialReportPageState();
}

class _FinancialReportPageState extends ConsumerState<FinancialReportPage> {
  String _picked = 'profitability';
  String _gran = 'daily';
  late InventoryScope _inv;
  bool _channelExporting = false;
  bool _invExporting = false;

  @override
  void initState() {
    super.initState();
    // Set once on open; it does not follow the scope bar (REP-FIN-005).
    _inv = initialInventoryScope(ref.read(currentScopeProvider));
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final authz = ref.watch(authzProvider);
    final title = t('reports.financial.title');
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
    final visible = [
      for (final tab in financialTabs)
        if (tab.caps.any(authz.can)) tab.id,
    ];
    // REP-FIN-002 / REP-ALL-005.
    if (visible.isEmpty) {
      return Restricted(title: title, who: t('reports.noAccess'));
    }
    final tab = visible.contains(_picked) ? _picked : visible.first;
    final inventory = _inventoryTabs.contains(tab);
    final body = switch (tab) {
      'profitability' => const DashEmbeddedPages(child: FinProfitabilityView()),
      'revenue' => FinRevenueTab(
        gran: _gran,
        onGran: (g) => setState(() => _gran = g),
      ),
      'channel' => const FinChannelTab(),
      'valuation' => FinValuationTab(inv: _inv),
      'supplierSpend' => FinSpendTab(inv: _inv),
      _ => FinTrendTab(inv: _inv),
    };
    return DashPageScaffold(
      title: title,
      subtitleWidget: const ReportPeriodSubtitle(),
      actions: [
        if (tab == 'channel')
          DashExportButton(
            key: const ValueKey('fin-channel-export'),
            loading: _channelExporting,
            onExport: _channelExcel,
            onExportCsv: () => finCsv(
              context,
              ref,
              filename: 'Madar-Analytics-channel',
              sheets: _channelSheets,
            ),
          ),
        if (inventory)
          DashExportButton(
            key: const ValueKey('fin-inventory-export'),
            loading: _invExporting,
            onExport: () => _inventoryExcel(tab),
            onExportCsv: () {
              final sheet = _inventorySheet(tab);
              finCsv(
                context,
                ref,
                filename: 'Madar-${sheet.title}',
                sheets: () async => [sheet],
              );
            },
          ),
      ],
      tabs: DashPageTabs<String>(
        key: const ValueKey('fin-tabs'),
        value: tab,
        onChanged: (v) => setState(() => _picked = v),
        onIntent: _warmTab,
        tabs: [
          for (final def in financialTabs)
            if (visible.contains(def.id))
              DashTab(value: def.id, label: t(def.labelKey)),
        ],
      ),
      filters: inventory
          ? Align(
              alignment: AlignmentDirectional.centerStart,
              child: InventoryScopeToggle(
                key: const ValueKey('fin-inv-scope'),
                value: _inv,
                onChanged: (v) => setState(() => _inv = v),
                onIntent: (v) => finWarmInventory(ref, tab, v),
              ),
            )
          : null,
      body: KeyedSubtree(key: ValueKey('fin-tab-$tab'), child: body),
    );
  }

  /// Intent: warms what opening [tab] reads, with the page's state.
  void _warmTab(String tab) {
    final s = ref.read(currentScopeProvider);
    switch (tab) {
      case 'profitability':
        if (s.orgId != null) ref.warm(finLedgerProvider(s.finLedger()));
      case 'revenue':
        finWarmRevenue(ref, _gran);
      case 'channel':
        ref.warm(finChannelsProvider(s.finSales));
      default:
        finWarmInventory(ref, tab, _inv);
    }
  }

  Future<List<ExcelSheet<Object?>>> _channelSheets() => finChannelSheets(
    ref.read(exportApiProvider),
    ref.read(tProvider),
    ref.read(currentScopeProvider).finSales,
  );

  Future<void> _channelExcel() async {
    final t = ref.read(tProvider);
    final preset = ref.read(currentScopeProvider).preset;
    setState(() => _channelExporting = true);
    await finExcel(
      context,
      ref,
      filename: 'Madar-Analytics-channel',
      meta: t(preset.labelKey, defaultValue: preset.fallback),
      sheets: _channelSheets,
    );
    if (mounted) setState(() => _channelExporting = false);
  }

  /// REP-FIN-070 the sheet from what the tab has loaded.
  ExcelSheet<Object?> _inventorySheet(String tab) {
    final t = ref.read(tProvider);
    final scope = ref.read(currentScopeProvider);
    final branch = _inv == InventoryScope.branch;
    final id = branch ? scope.branchId : scope.orgId;
    final k = id == null ? null : (id: id, from: scope.from, to: scope.to);
    switch (tab) {
      case 'valuation':
        final org = scope.orgId;
        final valuation = id == null
            ? null
            : ref
                  .read(
                    branch
                        ? finBranchValuationProvider(id)
                        : finOrgValuationProvider(id),
                  )
                  .value;
        final catalog = org == null
            ? null
            : ref.read(finCatalogProvider(org)).value;
        return finInventorySheet(
          t,
          tab: tab,
          branch: branch,
          byCategory: finByCategory(
            valuation,
            catalog,
            t('inventory.catalog.uncategorized'),
          ),
        );
      case 'supplierSpend':
        return finInventorySheet(
          t,
          tab: tab,
          branch: branch,
          spend: k == null
              ? const []
              : ref
                        .read(
                          branch
                              ? finBranchSpendProvider(k)
                              : finOrgSpendProvider(k),
                        )
                        .value ??
                    const [],
        );
      default:
        return finInventorySheet(
          t,
          tab: tab,
          branch: branch,
          trend: k == null
              ? const []
              : ref
                        .read(
                          branch
                              ? finBranchTrendProvider(k)
                              : finOrgTrendProvider(k),
                        )
                        .value ??
                    const [],
        );
    }
  }

  Future<void> _inventoryExcel(String tab) async {
    final sheet = _inventorySheet(tab);
    setState(() => _invExporting = true);
    await finExcel(
      context,
      ref,
      filename: 'Madar-${sheet.title}',
      sheets: () async => [sheet],
    );
    if (mounted) setState(() => _invExporting = false);
  }
}
