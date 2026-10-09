/// Ingredients (`/inventory/ingredients`, legacy `/inventory/items`; the
/// INV-ING rows; web `src/features/inventory/items-page.tsx`): the org's
/// catalog, with the picked branch's book stock beside it.
///
/// No control here is gated by capability (INV-ING-052): New ingredient,
/// Edit, Save par, Count this item and Record waste are offered to whoever
/// reaches the page; a refusal comes back as the server's words in a toast.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show Branch, BranchStockRow, OrgIngredient;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/inventory_data.dart';
import '../shared/inventory_export.dart';
import '../shared/inventory_lib.dart' show jsNumberString;
import '../shared/no_org.dart';
import '../shared/on_hand.dart';
import '../waste/waste_dialog.dart';
import 'ingredient_dialog.dart';
import 'ingredient_drawer.dart';
import 'ingredients_data.dart';

class IngredientsPage extends ConsumerStatefulWidget {
  const IngredientsPage({super.key});

  @override
  ConsumerState<IngredientsPage> createState() => _IngredientsPageState();
}

class _IngredientsPageState extends ConsumerState<IngredientsPage> {
  IngredientFilter _filter = IngredientFilter.all;
  bool _exporting = false;

  List<Branch> _activeBranches() => [
    for (final b in ref.read(branchesProvider).value ?? const <Branch>[])
      if (b.isActive) b,
  ];

  Future<void> _openDialog(String orgId, {OrgIngredient? item}) =>
      showIngredientDialog(
        context,
        orgId: orgId,
        branches: _activeBranches(),
        item: item,
      );

  Future<void> _openDrawer(
    String orgId,
    String? branchId,
    OrgIngredient item,
  ) async {
    final action = await showIngredientDrawer(
      context,
      orgId: orgId,
      branchId: branchId,
      item: item,
    );
    if (!mounted) return;
    switch (action) {
      case IngredientDrawerAction.edit:
        // The drawer's row, fresh: an edit made since it opened shows.
        final fresh =
            ref
                .read(inventoryCatalogProvider(orgId))
                .value
                ?.where((i) => i.id == item.id)
                .firstOrNull ??
            item;
        await _openDialog(orgId, item: fresh);
      case IngredientDrawerAction.recordWaste when branchId != null:
        await showRecordWasteDialog(
          context,
          branchId: branchId,
          presetIngredientId: item.id,
        );
      case _:
        break;
    }
  }

  Future<void> _export(
    List<OrgIngredient> rows,
    Map<String, BranchStockRow> stock, {
    required bool hasBranch,
  }) async {
    final t = ref.read(tProvider);
    String status(OrgIngredient it) => switch (exportStatus(stock[it.id])) {
      StockStatus.neverCounted => t('inventory.stock.neverCounted'),
      StockStatus.low => t('inventory.stock.low'),
      StockStatus.ok => t('inventory.stock.ok'),
    };
    OrgIngredient row(Object? r) => r! as OrgIngredient;
    final config = ExcelConfig(
      filename: 'Madar-Ingredients',
      logoUrl: inventoryExportLogo(ref),
      sheets: [
        ExcelSheet<Object?>(
          name: t('inventory.catalog.title'),
          title: t('inventory.catalog.title'),
          rows: rows,
          columns: [
            ExcelColumn<Object?>(
              header: t('inventory.catalog.name'),
              accessor: (r) => row(r).name,
              type: ExcelColumnType.text,
              width: 28,
            ),
            ExcelColumn<Object?>(
              header: t('inventory.catalog.category'),
              accessor: (r) => row(r).categoryName,
              type: ExcelColumnType.text,
              width: 16,
            ),
            ExcelColumn<Object?>(
              header: t('inventory.catalog.costPerUnit'),
              accessor: (r) => row(r).costPerUnit,
              type: ExcelColumnType.money,
              width: 14,
            ),
            ExcelColumn<Object?>(
              header: t('inventory.catalog.unit'),
              accessor: (r) => fmtUnit(row(r).unit),
              type: ExcelColumnType.text,
              width: 10,
            ),
            ExcelColumn<Object?>(
              header: t('inventory.catalog.supplier'),
              accessor: (r) => row(r).supplierName ?? '—',
              type: ExcelColumnType.text,
              width: 22,
            ),
            if (hasBranch) ...[
              ExcelColumn<Object?>(
                header: t('inventory.catalog.onHand'),
                accessor: (r) => stock[row(r).id]?.onHand,
                type: ExcelColumnType.number,
                width: 12,
              ),
              ExcelColumn<Object?>(
                header: t('inventory.catalog.reorderPoint'),
                accessor: (r) => stock[row(r).id]?.parMin,
                type: ExcelColumnType.number,
                width: 14,
              ),
              ExcelColumn<Object?>(
                header: t('inventory.stock.status'),
                accessor: (r) => status(row(r)),
                type: ExcelColumnType.text,
                width: 14,
              ),
            ],
          ],
        ),
      ],
    );
    setState(() => _exporting = true);
    try {
      await inventoryExportExcel(context, ref, config);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final orgId = ref.watch(orgIdProvider);
    if (orgId == null) {
      return InventoryNoOrgPage(title: t('inventory.catalog.title'));
    }
    final branchId = ref.watch(currentScopeProvider.select((s) => s.branchId));
    final hasBranch = branchId != null;

    final catalog = ref.watch(inventoryCatalogProvider(orgId));
    // The org's branches: the active ones feed the dialog's reorder levels.
    ref.watch(branchesProvider);
    // With a branch only: its stock, and its counts ("Count this item").
    final stock = hasBranch ? ref.watch(branchStockProvider(branchId)) : null;
    if (hasBranch) ref.watch(stocktakesProvider(branchId));
    final byId = stockByIngredient(stock?.value);
    final rows = filterIngredients(
      catalog.value ?? const [],
      byId,
      _filter,
      hasBranch: hasBranch,
    );

    return DashPageScaffold(
      title: t('inventory.catalog.title'),
      subtitle: t('inventory.catalog.subtitle'),
      actions: [
        DashExportButton(
          key: const ValueKey('ingredients-export'),
          loading: _exporting,
          enabled: rows.isNotEmpty,
          onExport: () => _export(rows, byId, hasBranch: hasBranch),
        ),
        DashButton(
          key: const ValueKey('ingredients-new'),
          label: t('inventory.catalog.newItem'),
          icon: 'package-plus',
          onPressed: () => _openDialog(orgId),
        ),
      ],
      filters: hasBranch
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DashSegmentedControl<IngredientFilter>(
                key: const ValueKey('ingredients-filter'),
                value: _filter,
                onChanged: (v) => setState(() => _filter = v),
                options: [
                  DashOption(
                    value: IngredientFilter.all,
                    label: t('common.all'),
                  ),
                  DashOption(
                    value: IngredientFilter.low,
                    label: t('inventory.reports.lowStock'),
                  ),
                  DashOption(
                    value: IngredientFilter.uncounted,
                    label: t('inventory.stock.neverCounted'),
                  ),
                ],
              ),
            )
          : null,
      body: IngredientsTable(
        rows: rows,
        stock: byId,
        hasBranch: hasBranch,
        loading: catalog.firstLoad,
        // Kept while Retry runs, as React Query keeps `error` (no false
        // "No ingredients yet" in between).
        errorText: catalog.errorText(t),
        onRetry: () => ref.invalidate(inventoryCatalogProvider(orgId)),
        onOpen: (it) => _openDrawer(orgId, branchId, it),
      ),
    );
  }
}

/// The catalog table (INV-ING-007…013): Name, Category, Standard cost,
/// Supplier, and with a branch On hand, Reorder point and Status. Below 760
/// each row is a card.
class IngredientsTable extends ConsumerWidget {
  /// A money or quantity column: its figures, never the free space.
  static const double _figureWidth = Space.xxl * 4;

  const IngredientsTable({
    required this.rows,
    required this.stock,
    required this.hasBranch,
    required this.loading,
    required this.errorText,
    required this.onRetry,
    required this.onOpen,
    super.key,
  });

  final List<OrgIngredient> rows;
  final Map<String, BranchStockRow> stock;
  final bool hasBranch;
  final bool loading;
  final String? errorText;
  final VoidCallback onRetry;
  final ValueChanged<OrgIngredient> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    Widget dash() => Text('—', style: DashType.body.copyWith(color: c.textMuted));
    return DashDataTable<OrgIngredient>(
      key: const ValueKey('ingredients-table'),
      rows: rows,
      rowKey: (it) => it.id,
      loading: loading,
      errorMessage: errorText,
      onRetry: onRetry,
      onRowTap: onOpen,
      searchPlaceholder: t('inventory.catalog.search'),
      empty: DashEmptyState(icon: 'boxes', title: t('inventory.catalog.noItems')),
      columns: [
        DashColumn(
          id: 'name',
          label: t('inventory.catalog.name'),
          text: (it) => it.name,
          cell: (context, it) => MadarClippedText(
            it.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DashType.bodyMedium.copyWith(color: c.textPrimary),
          ),
          phone: DashPhoneRole.title,
          minWidth: Space.xxl * 5,
        ),
        DashColumn(
          id: 'category_name',
          label: t('inventory.catalog.category'),
          text: (it) => it.categoryName,
          cell: (context, it) => Align(
            alignment: AlignmentDirectional.centerStart,
            child: DashBadge(it.categoryName),
          ),
          minWidth: Space.xxl * 5,
        ),
        DashColumn(
          id: 'cost_per_unit',
          label: t('inventory.catalog.standardCost'),
          // Searched by its raw figure, as the web's accessor (INV-ALL-021).
          text: (it) => it.costPerUnit == null
              ? ''
              : jsNumberString(it.costPerUnit!),
          cell: (context, it) => Text(dashFigure(f.fmtMoney(it.costPerUnit))),
          numeric: true,
          width: _figureWidth,
        ),
        DashColumn(
          id: 'supplier_name',
          label: t('inventory.catalog.supplier'),
          text: (it) => it.supplierName ?? '',
          cell: (context, it) => it.supplierName == null
              ? dash()
              : MadarClippedText(
                  it.supplierName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          minWidth: Space.xxl * 5,
        ),
        if (hasBranch) ...[
          DashColumn(
            id: 'on_hand',
            label: t('inventory.catalog.onHand'),
            searchable: false,
            cell: (context, it) {
              final s = stock[it.id];
              return s == null
                  ? dash()
                  : OnHand(qty: s.onHand, unit: s.unit, style: DashType.mono);
            },
            numeric: true,
            width: _figureWidth + Space.lg,
          ),
          DashColumn(
            id: 'par',
            label: t('inventory.catalog.reorderPoint'),
            searchable: false,
            cell: (context, it) {
              final s = stock[it.id];
              if (s?.parMin == null) return dash();
              return Text(
                ltr('${f.fmtNumber(s!.parMin)} ${fmtUnit(s.unit)}'),
              );
            },
            numeric: true,
            width: _figureWidth + Space.lg,
          ),
          DashColumn(
            id: 'status',
            label: t('inventory.stock.status'),
            searchable: false,
            cell: (context, it) => switch (stockStatus(stock[it.id])) {
              null => const SizedBox.shrink(),
              StockStatus.neverCounted => DashStatusPill(
                label: t('inventory.stock.neverCounted'),
                icon: 'circle-dashed',
              ),
              StockStatus.low => DashStatusPill(
                label: t('inventory.stock.low'),
                tone: DashTone.warning,
              ),
              StockStatus.ok => DashStatusPill(
                label: t('inventory.stock.ok'),
                tone: DashTone.success,
              ),
            },
            // "Never counted" with its glyph fits on one line.
            width: Space.xxl * 5 + Space.md,
          ),
        ],
      ],
    );
  }
}
