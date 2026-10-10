/// Financial's inventory-backed tabs (`features/inventory/reports-page.tsx`
/// `ValuationTab`, `SupplierSpendTab`, `MaterialCostTrendTab`,
/// REP-FIN-005, 066…070): read for the branch or the whole org per the
/// page's toggle; "This branch" with All branches selected asks nothing and
/// shows the empty words (no "pick a branch" message here).
library;

import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/report_shared.dart';
import 'fin_data.dart';

/// The valuation read for [inv] (null when it cannot run).
AsyncValue<InventoryValuationReport>? finValuationOf(
  WidgetRef ref,
  Scope scope,
  InventoryScope inv,
) {
  if (inv == InventoryScope.branch) {
    final id = scope.branchId;
    return id == null ? null : ref.watch(finBranchValuationProvider(id));
  }
  final org = scope.orgId;
  return org == null ? null : ref.watch(finOrgValuationProvider(org));
}

/// The spend read for [inv] (null when it cannot run).
AsyncValue<List<SupplierSpendRow>>? finSpendOf(
  WidgetRef ref,
  Scope scope,
  InventoryScope inv,
) {
  final id = inv == InventoryScope.branch ? scope.branchId : scope.orgId;
  if (id == null) return null;
  final k = (id: id, from: scope.from, to: scope.to);
  return ref.watch(
    inv == InventoryScope.branch
        ? finBranchSpendProvider(k)
        : finOrgSpendProvider(k),
  );
}

/// The trend read for [inv] (null when it cannot run).
AsyncValue<List<MaterialCostTrendRow>>? finTrendOf(
  WidgetRef ref,
  Scope scope,
  InventoryScope inv,
) {
  final id = inv == InventoryScope.branch ? scope.branchId : scope.orgId;
  if (id == null) return null;
  final k = (id: id, from: scope.from, to: scope.to);
  return ref.watch(
    inv == InventoryScope.branch
        ? finBranchTrendProvider(k)
        : finOrgTrendProvider(k),
  );
}

/// Intent: warms what [tab] reads for [inv] (as the `fin*Of` reads above).
void finWarmInventory(WidgetRef ref, String tab, InventoryScope inv) {
  final s = ref.read(currentScopeProvider);
  final branch = inv == InventoryScope.branch;
  final id = branch ? s.branchId : s.orgId;
  final org = s.orgId;
  if (tab == 'valuation' && org != null) ref.warm(finCatalogProvider(org));
  if (id == null) return;
  final k = (id: id, from: s.from, to: s.to);
  switch (tab) {
    case 'valuation':
      ref.warm(
        branch ? finBranchValuationProvider(id) : finOrgValuationProvider(id),
      );
    case 'supplierSpend':
      ref.warm(branch ? finBranchSpendProvider(k) : finOrgSpendProvider(k));
    default:
      ref.warm(branch ? finBranchTrendProvider(k) : finOrgTrendProvider(k));
  }
}

/// REP-FIN-066/067 stock value now, and by catalog category.
class FinValuationTab extends ConsumerWidget {
  const FinValuationTab({required this.inv, super.key});

  final InventoryScope inv;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final scope = ref.watch(currentScopeProvider);
    final q = finValuationOf(ref, scope, inv);
    final org = scope.orgId;
    final catalog = org == null ? null : ref.watch(finCatalogProvider(org));
    if (q != null && q.failed) {
      return DashErrorState(
        title: t('inventory.reports.valuationFailed'),
        retrying: q.isLoading,
        retryLabel: t('common.retry'),
        onRetry: () => inv == InventoryScope.branch
            ? ref.invalidate(finBranchValuationProvider(scope.branchId!))
            : ref.invalidate(finOrgValuationProvider(org!)),
      );
    }
    final data = q?.value;
    final loading = q?.awaitingFirst ?? false;
    final unknown = data?.unknownCostCount ?? 0;
    final rows = finByCategory(
      data,
      catalog?.value,
      t('inventory.catalog.uncategorized'),
    );
    final max = rows.fold<int>(0, (m, r) => r.$2 > m ? r.$2 : m);
    final wide = MediaQuery.sizeOf(context).width >= DashBreakpoints.lg;
    final Widget list;
    if (loading || (catalog?.awaitingFirst ?? false)) {
      list = DashCard(
        key: const ValueKey('fin-by-category-loading'),
        child: Column(
          spacing: Space.lg,
          children: [
            for (var i = 0; i < 4; i++)
              const Column(
                spacing: Space.sm,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      DashSkeleton(width: 112),
                      DashSkeleton(width: 80),
                    ],
                  ),
                  DashSkeleton(height: Space.sm),
                ],
              ),
          ],
        ),
      );
    } else if (rows.isEmpty) {
      list = DashEmptyState(title: t('inventory.reports.noValuation'));
    } else {
      list = DashCard(
        key: const ValueKey('fin-by-category'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.lg,
          children: [
            for (final (cat, value) in rows)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.xs + DashMetrics.hair,
                children: [
                  Row(
                    spacing: Space.lg,
                    children: [
                      Expanded(
                        child: Text(
                          cat,
                          style: DashType.bodyMedium.copyWith(
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        dashFigure(f.fmtMoney(value)),
                        style: DashType.mono.copyWith(color: c.textPrimary),
                      ),
                    ],
                  ),
                  DashProgressBar(
                    value: value.toDouble(),
                    max: max.toDouble(),
                    semanticLabel: cat,
                  ),
                ],
              ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.xl,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: wide ? 672 : double.infinity),
            child: DashLedgerStrip(
              items: [
                DashLedgerItem(
                  key: 'value',
                  label: t('inventory.reports.totalValue'),
                  value: data?.totalValue ?? 0,
                  format: DashStatFormat.money,
                  icon: 'wallet',
                  loading: loading,
                ),
                DashLedgerItem(
                  key: 'unknown',
                  label: t('inventory.reports.unknownCostLabel'),
                  value: unknown,
                  format: DashStatFormat.number,
                  icon: 'circle-help',
                  tone: unknown > 0 ? DashTone.warning : DashTone.neutral,
                  loading: loading,
                ),
              ],
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.md,
          children: [
            DashSectionHeader(title: t('inventory.reports.byCategory')),
            list,
          ],
        ),
      ],
    );
  }
}

/// REP-FIN-068 spend per supplier.
class FinSpendTab extends ConsumerWidget {
  const FinSpendTab({required this.inv, super.key});

  final InventoryScope inv;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final scope = ref.watch(currentScopeProvider);
    final q = finSpendOf(ref, scope, inv);
    return InventoryReportTable(
      key: const ValueKey('fin-spend'),
      emptyTitle: t('inventory.reports.noDataPeriod'),
      loading: q?.awaitingFirst ?? false,
      retrying: q?.isLoading ?? false,
      error: q != null && q.failed ? q.error : null,
      onRetry: () => _retry(ref, scope, inv, spend: true),
      head: [
        ReportHead(t('inventory.reports.supplier')),
        ReportHead(t('inventory.reports.orders'), numeric: true),
        ReportHead(t('inventory.reports.totalSpend'), numeric: true),
      ],
      rows: [
        for (final (i, r) in (q?.value ?? const <SupplierSpendRow>[]).indexed)
          ReportRow(
            key: r.supplierId ?? '${r.supplierName}-$i',
            cells: [
              r.supplierName,
              f.fmtNumber(r.orders),
              f.fmtMoney(r.totalSpend),
            ],
          ),
      ],
    );
  }
}

void _retry(
  WidgetRef ref,
  Scope scope,
  InventoryScope inv, {
  required bool spend,
}) {
  final branch = inv == InventoryScope.branch;
  final id = branch ? scope.branchId : scope.orgId;
  if (id == null) return;
  final k = (id: id, from: scope.from, to: scope.to);
  if (spend) {
    ref.invalidate(branch ? finBranchSpendProvider(k) : finOrgSpendProvider(k));
  } else {
    ref.invalidate(branch ? finBranchTrendProvider(k) : finOrgTrendProvider(k));
  }
}

/// REP-FIN-069 three straight price rises from the current supplier.
class FinTrendTab extends ConsumerWidget {
  const FinTrendTab({required this.inv, super.key});

  final InventoryScope inv;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final scope = ref.watch(currentScopeProvider);
    final q = finTrendOf(ref, scope, inv);
    final none = Text(
      '—',
      style: DashType.body.copyWith(color: c.textSecondary),
    );
    return DashDataTable<MaterialCostTrendRow>(
      key: const ValueKey('fin-trend'),
      rows: q?.value ?? const [],
      rowKey: (r) => r.orgIngredientId,
      loading: q?.awaitingFirst ?? false,
      retrying: q?.isLoading ?? false,
      errorMessage: q != null && q.failed ? errorMessage(q.error, t) : null,
      onRetry: () => _retry(ref, scope, inv, spend: false),
      pageSize: 25,
      hideViewOptions: true,
      empty: DashEmptyState(
        icon: 'trending-up',
        title: t('inventory.reports.noDataPeriod'),
        description: t('inventory.reports.noCostTrend'),
      ),
      columns: [
        DashColumn(
          id: 'ingredient',
          label: t('inventory.reports.ingredient'),
          phone: DashPhoneRole.title,
          flex: 2,
          minWidth: 160,
          text: (r) => r.ingredientName,
          cell: (context, r) => Text(
            r.ingredientName,
            style: DashType.bodyMedium.copyWith(color: c.textPrimary),
          ),
        ),
        DashColumn(
          id: 'supplier',
          label: t('inventory.reports.supplier'),
          flex: 2,
          minWidth: 140,
          text: (r) => r.currentSupplierName,
        ),
        DashColumn(
          id: 'cost',
          label: t('inventory.reports.currentCost'),
          numeric: true,
          flex: 2,
          minWidth: 140,
          text: (r) => f.fmtMoney(r.currentCost),
        ),
        DashColumn(
          id: 'streak',
          label: t('inventory.reports.priceStreak'),
          numeric: true,
          flex: 2,
          minWidth: 210,
          text: (r) => _streak(t, f, r),
          cell: (context, r) => Align(
            alignment: AlignmentDirectional.centerEnd,
            child: DashStatusPill(
              label: _streak(t, f, r),
              small: true,
              wrap: true,
              tone: DashTone.danger,
              icon: 'trending-up',
            ),
          ),
        ),
        DashColumn(
          id: 'suggestion',
          label: t('inventory.reports.suggestion'),
          flex: 3,
          minWidth: 280,
          text: (r) => r.cheaperSupplierName == null ? '—' : _switch(t, f, r),
          cell: (context, r) => r.cheaperSupplierName == null
              ? none
              : Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: DashStatusPill(
                    label: _switch(t, f, r),
                    small: true,
                    wrap: true,
                    tone: DashTone.neutral,
                    icon: Directionality.of(context) == TextDirection.rtl
                        ? 'arrow-left'
                        : 'arrow-right',
                  ),
                ),
        ),
      ],
    );
  }
}

String _streak(Translator t, DashFormat f, MaterialCostTrendRow r) => t(
  'inventory.reports.streakBadge',
  args: {
    'pct': f.fmtNumber(
      r.pctIncrease,
      const NumberOptions(maximumFractionDigits: 1),
    ),
    'count': r.streakLength,
  },
);

String _switch(Translator t, DashFormat f, MaterialCostTrendRow r) => t(
  'inventory.reports.switchTo',
  args: {
    'supplier': r.cheaperSupplierName,
    'cost': f.fmtMoney(r.cheaperCost ?? 0),
  },
);
