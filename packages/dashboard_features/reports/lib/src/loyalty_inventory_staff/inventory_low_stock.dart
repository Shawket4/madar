/// Inventory reports › Low stock (REP-INV-015…018, `low-stock-tab.tsx`,
/// `on-hand.tsx`): a read-only list of what sits at or under its reorder
/// point, for the branch picked in the scope bar or the whole org, with its
/// own export. Reordering is the Inventory page's job.
library;

import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show publicBrandProvider;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/report_shared.dart' show ReportAsync;
import 'lis_providers.dart';
import 'lis_support.dart';

/// `isBelowZero`: a finite figure under zero.
bool isBelowZero(num? onHand) =>
    onHand != null && onHand.isFinite && onHand < 0;

class InventoryLowStockTab extends ConsumerStatefulWidget {
  const InventoryLowStockTab({super.key});

  @override
  ConsumerState<InventoryLowStockTab> createState() =>
      _InventoryLowStockTabState();
}

class _InventoryLowStockTabState extends ConsumerState<InventoryLowStockTab> {
  bool _exporting = false;

  ExcelConfig _config(List<LowStockRow> rows, bool allBranches) {
    final t = ref.read(tProvider);
    final title = t('reports.operations.tabs.lowStock');
    ExcelColumn<LowStockRow> col(
      String header,
      Object? Function(LowStockRow r) get,
      ExcelColumnType type,
      double width,
    ) => ExcelColumn(header: header, accessor: get, type: type, width: width);
    const text = ExcelColumnType.text, number = ExcelColumnType.number;
    return ExcelConfig(
      filename: 'Madar-$title',
      logoUrl: exportLogoUrl(ref.read(publicBrandProvider).value),
      sheets: [
        ExcelSheet<LowStockRow>(
          name: title,
          title: title,
          rows: rows,
          columns: [
            col(t('inventory.catalog.name'), (r) => r.ingredientName, text, 26),
            if (allBranches)
              col(
                t('inventory.reports.branchName'),
                (r) => r.branchName,
                text,
                20,
              ),
            col(t('inventory.today.onHand'), (r) => r.onHand, number, 14),
            col(t('inventory.today.reorderPoint'), (r) => r.parMin, number, 16),
            col(
              t('inventory.today.suggested'),
              (r) => r.suggestedQty,
              number,
              14,
            ),
            col(t('inventory.catalog.unit'), (r) => fmtUnit(r.unit), text, 10),
            col(
              t('inventory.catalog.supplier'),
              (r) => r.supplierName ?? '',
              text,
              20,
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final scope = ref.watch(currentScopeProvider);
    final k = scope.lowStockKey;
    final AsyncValue<List<LowStockRow>?> q = k == null
        ? const AsyncData(null)
        : ref.watch(invLowStockProvider(k));
    final rows = q.value ?? const <LowStockRow>[];
    final all = scope.isAllBranches;
    return DashDataTable<LowStockRow>(
      rowKey: (r) => '${r.branchId}-${r.orgIngredientId}',
      rows: rows,
      loading: q.awaitingFirst,
      retrying: q.isLoading,
      errorMessage: q.failed ? errorMessage(q.error, t) : null,
      onRetry: k == null ? null : () => ref.invalidate(invLowStockProvider(k)),
      pageSize: 50,
      toolbar: DashExportButton(
        key: const ValueKey('low-stock-export'),
        compact: true,
        loading: _exporting,
        enabled: rows.isNotEmpty,
        onExport: () async {
          final config = _config(rows, all);
          setState(() => _exporting = true);
          try {
            await lisExportExcel(context, ref, config);
          } finally {
            if (mounted) setState(() => _exporting = false);
          }
        },
        onExportCsv: () => lisExportCsv(context, ref, _config(rows, all)),
      ),
      empty: DashEmptyState(title: t('inventory.today.noLowStock')),
      columns: [
        DashColumn<LowStockRow>(
          id: 'name',
          label: t('inventory.catalog.name'),
          phone: DashPhoneRole.title,
          minWidth: 200,
          flex: 2,
          text: (r) => r.ingredientName,
          cell: (context, r) => Wrap(
            spacing: Space.sm,
            runSpacing: Space.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                r.ingredientName,
                style: DashType.bodyMedium.copyWith(color: c.textPrimary),
              ),
              r.onHand <= 0
                  ? DashStatusPill(
                      label: t('inventory.today.statusCritical'),
                      tone: DashTone.danger,
                      small: true,
                    )
                  : DashStatusPill(
                      label: t('inventory.today.statusLow'),
                      tone: DashTone.warning,
                      small: true,
                    ),
            ],
          ),
        ),
        if (all)
          DashColumn<LowStockRow>(
            id: 'branch',
            label: t('inventory.reports.branchName'),
            text: (r) => r.branchName,
          ),
        DashColumn<LowStockRow>(
          id: 'onHand',
          label: t('inventory.today.onHand'),
          numeric: true,
          minWidth: 150,
          text: (r) => invQty(f, r.onHand, r.unit),
          cell: (context, r) => OnHandFigure(qty: r.onHand, unit: r.unit),
        ),
        DashColumn<LowStockRow>(
          id: 'par',
          label: t('inventory.today.reorderPoint'),
          numeric: true,
          text: (r) => invQty(f, r.parMin, r.unit),
        ),
        DashColumn<LowStockRow>(
          id: 'suggested',
          label: t('inventory.today.suggested'),
          numeric: true,
          text: (r) => invQty(f, r.suggestedQty, r.unit),
        ),
        DashColumn<LowStockRow>(
          id: 'supplier',
          label: t('inventory.catalog.supplier'),
          text: (r) => r.supplierName ?? '—',
          cell: (context, r) => Text(
            r.supplierName ?? '—',
            style: DashType.body.copyWith(
              color: r.supplierName == null ? c.textSecondary : c.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

/// `OnHand`: the figure and its unit; below zero it is tinted and carries
/// a "Below zero" pill (never hidden or clamped).
class OnHandFigure extends ConsumerWidget {
  const OnHandFigure({required this.qty, this.unit, super.key});

  final double qty;
  final String? unit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final below = isBelowZero(qty);
    final figure = Text(
      dashFigure(invQty(f, qty, unit)),
      style: below
          ? DashType.monoStrong.copyWith(
              fontSize: DashType.mono.fontSize,
              color: DashTone.danger.foreground(c),
            )
          : DashType.mono.copyWith(color: c.textPrimary),
    );
    if (!below) return figure;
    return Wrap(
      spacing: Space.xs + DashMetrics.hair,
      runSpacing: Space.xs,
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        figure,
        DashStatusPill(
          label: t('inventory.catalog.belowZero'),
          tone: DashTone.danger,
          small: true,
        ),
      ],
    );
  }
}
