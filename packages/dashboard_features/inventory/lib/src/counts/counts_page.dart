/// Stock counts (`/inventory/counts`; the INV-CNT rows; web
/// `src/features/inventory/counts-page.tsx`): the front door of inventory. A
/// branch is counted from the org catalog alone; the first finalized count
/// is what brings its numbers to life.
///
/// No control here is gated by capability (INV-CNT-059): Start, the editor's
/// autosave, Cancel and Finalize are offered to whoever reaches the page and
/// a refusal comes back as the server's words in a toast. Counts has no
/// no-organization guard (INV-ALL-027).
library;

import 'package:dashboard_api/dashboard_api.dart' show Stocktake;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show publicBrandProvider;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/inventory_data.dart';
import '../shared/inventory_export.dart';
import '../shared/inventory_labels.dart';
import '../shared/inventory_lib.dart';
import 'count_editor.dart';
import 'counts_data.dart';
import 'start_count_dialog.dart';
import 'variance_report_dialog.dart';

class CountsPage extends ConsumerStatefulWidget {
  const CountsPage({super.key});

  @override
  ConsumerState<CountsPage> createState() => _CountsPageState();
}

class _CountsPageState extends ConsumerState<CountsPage> {
  bool _exporting = false;

  /// The scope dialog, reset every time it opens (INV-CNT-061).
  Future<void> _start(String branchId) => showDashDialog<void>(
    context,
    builder: (_) =>
        StartCountDialog(branchId: branchId, orgId: ref.read(orgIdProvider)),
  );

  /// The start dialog's reads (its category and ingredient pickers).
  void _warmStart() {
    final orgId = ref.read(orgIdProvider);
    if (orgId == null) return;
    ref.warm(ingredientCategoriesProvider(orgId));
    ref.warm(inventoryCatalogProvider(orgId));
  }

  Future<void> _report(String id) => showVarianceReport(context, id);

  Future<void> _export(List<Stocktake> rows) async {
    final t = ref.read(tProvider);
    Stocktake row(Object? r) => r! as Stocktake;
    final config = ExcelConfig(
      filename: 'Madar-Stocktakes',
      logoUrl: exportLogoUrl(ref.read(publicBrandProvider).value),
      sheets: [
        ExcelSheet<Object?>(
          name: t('inventory.stocktakes.title'),
          title: t('inventory.stocktakes.title'),
          rows: rows,
          columns: [
            ExcelColumn<Object?>(
              header: t('inventory.stocktakes.started'),
              accessor: (r) => row(r).startedAt,
              type: ExcelColumnType.dateTime,
              width: 20,
            ),
            ExcelColumn<Object?>(
              header: t('inventory.transfers.by'),
              accessor: (r) => row(r).startedByName ?? '—',
              type: ExcelColumnType.text,
              width: 20,
            ),
            ExcelColumn<Object?>(
              header: t('inventory.stocktakes.scope'),
              accessor: (r) => stocktakeScopeLabel(t, row(r)),
              type: ExcelColumnType.text,
              width: 16,
            ),
            ExcelColumn<Object?>(
              header: t('inventory.stocktakes.status'),
              accessor: (r) => stocktakeStatusLabel(t, row(r).status),
              type: ExcelColumnType.text,
              width: 14,
            ),
            ExcelColumn<Object?>(
              header: t('inventory.stocktakes.finalized'),
              accessor: (r) => row(r).finalizedAt,
              type: ExcelColumnType.dateTime,
              width: 20,
            ),
            ExcelColumn<Object?>(
              header: t('inventory.transfers.note'),
              accessor: (r) => row(r).note ?? '',
              type: ExcelColumnType.text,
              width: 30,
            ),
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
    final c = context.madarColors;
    final scope = ref.watch(currentScopeProvider);
    final branchId = scope.branchId;
    final listKey = scope.scopeBranchId;
    final q = ref.watch(stocktakesProvider(listKey));
    final open = openStocktake(q.value);
    final history = closedStocktakes(q.value);
    final firstRun =
        branchId != null &&
        open == null &&
        !q.awaitingFirst &&
        needsFirstCount(q.value?.map((s) => s.status));

    return DashPageScaffold(
      title: t('inventory.stocktakes.title'),
      subtitle: t('inventory.stocktakes.subtitle'),
      actions: [
        DashExportButton(
          key: const ValueKey('counts-export'),
          loading: _exporting,
          enabled: history.isNotEmpty,
          onExport: () => _export(history),
        ),
        if (branchId != null && open == null)
          DashButton(
            key: const ValueKey('counts-start'),
            label: t('inventory.stocktakes.start'),
            icon: 'plus-circle',
            onPressed: () => _start(branchId),
            onIntent: _warmStart,
          ),
      ],
      filters: branchId == null
          ? Text(
              t('inventory.stocktakes.pickBranchToCount'),
              style: DashType.body.copyWith(color: c.textSecondary),
            )
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.xl,
        children: [
          if (firstRun)
            _FirstRunCard(
              onStart: () => _start(branchId),
              onIntent: _warmStart,
            ),
          if (branchId != null && open != null)
            CountEditor(
              key: ValueKey('count-editor-${open.id}'),
              stocktakeId: open.id,
              onFinalized: (id) {
                if (mounted) _report(id);
              },
            ),
          CountsHistoryTable(
            rows: branchId != null ? history : (q.value ?? const []),
            allBranches: branchId == null,
            loading: q.awaitingFirst,
            // Kept while Retry runs, as React Query keeps `error` (no false
            // "No counts yet" in between); never during automatic retries.
            errorText: q.errorText(t),
            onRetry: () => ref.invalidate(stocktakesProvider(listKey)),
            retrying: q.isLoading,
            onReport: _report,
          ),
        ],
      ),
    );
  }
}

/// "This branch has never been counted" (INV-CNT-006).
class _FirstRunCard extends ConsumerWidget {
  const _FirstRunCard({required this.onStart, required this.onIntent});

  final VoidCallback onStart;
  final VoidCallback onIntent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.xs,
      children: [
        Text(
          t('inventory.stocktakes.firstRunTitle'),
          style: DashType.bodyStrong.copyWith(color: c.textPrimary),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: DashMetrics.proseWide),
          child: Text(
            t('inventory.stocktakes.firstRunHint'),
            style: DashType.body.copyWith(color: c.textSecondary),
          ),
        ),
      ],
    );
    final button = DashButton(
      key: const ValueKey('counts-first-run'),
      label: t('inventory.stocktakes.startFirst'),
      icon: 'clipboard-list',
      onPressed: onStart,
      onIntent: onIntent,
    );
    return DashCard(
      key: const ValueKey('counts-first-run-card'),
      child: LayoutBuilder(
        builder: (context, box) => box.maxWidth >= DashBreakpoints.sm
            ? Row(
                spacing: Space.md,
                children: [
                  Expanded(child: words),
                  button,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Space.md,
                children: [words, button],
              ),
      ),
    );
  }
}

/// The counts history (INV-CNT-008…017, -058): Started, Branch (All
/// branches), Scope, By, Status, Finalized; "View report" on finalized
/// rows. Below 760 each row is a card.
class CountsHistoryTable extends ConsumerWidget {
  const CountsHistoryTable({
    required this.rows,
    required this.allBranches,
    required this.loading,
    required this.errorText,
    required this.onRetry,
    this.retrying = false,
    required this.onReport,
    super.key,
  });

  final List<Stocktake> rows;
  final bool allBranches;
  final bool loading;
  final String? errorText;
  final VoidCallback onRetry;
  final bool retrying;
  final ValueChanged<String> onReport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    return DashDataTable<Stocktake>(
      key: const ValueKey('counts-table'),
      rows: rows,
      rowKey: (s) => s.id,
      loading: loading,
      errorMessage: errorText,
      onRetry: onRetry,
      retrying: retrying,
      // Only a finalized count opens; the others are still focusable.
      onRowTap: (s) {
        if (s.status == 'finalized') onReport(s.id);
      },
      onRowIntent: (s) {
        if (s.status == 'finalized') ref.warm(varianceReportProvider(s.id));
      },
      rowActionsWidth: Space.xxl * 4,
      rowActions: (context, s) => s.status == 'finalized'
          ? DashButton(
              key: ValueKey('counts-report-${s.id}'),
              label: t('inventory.stocktakes.viewReport'),
              variant: DashButtonVariant.outline,
              size: DashButtonSize.compact,
              onPressed: () => onReport(s.id),
              onIntent: () => ref.warm(varianceReportProvider(s.id)),
            )
          : const SizedBox.shrink(),
      empty: DashEmptyState(
        icon: 'clipboard-list',
        title: t('inventory.stocktakes.noStocktakes'),
        description: t('inventory.stocktakes.startHint'),
      ),
      columns: [
        DashColumn(
          id: 'started_at',
          label: t('inventory.stocktakes.started'),
          text: (s) => f.fmtDateTime(s.startedAt),
          phone: DashPhoneRole.title,
          minWidth: Space.xxl * 5,
        ),
        if (allBranches)
          DashColumn(
            id: 'branch_name',
            label: t('tills.branch'),
            text: (s) => s.branchName ?? '—',
            minWidth: Space.xxl * 4,
          ),
        DashColumn(
          id: 'scope',
          label: t('inventory.stocktakes.scope'),
          cell: (context, s) => MadarClippedText.rich(
            TextSpan(
              children: [
                TextSpan(text: stocktakeScopeLabel(t, s)),
                if (s.totalItems != null)
                  TextSpan(
                    text: ' · ${ltr('${s.countedItems ?? 0}/${s.totalItems}')}',
                    style: TextStyle(
                      color: c.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DashType.body.copyWith(color: c.textPrimary),
          ),
          minWidth: Space.xxl * 6,
          flex: 2,
        ),
        DashColumn(
          id: 'started_by_name',
          label: t('inventory.transfers.by'),
          cell: (context, s) => MadarClippedText(
            s.startedByName ?? '—',
            textDirection: dashTextDirectionOf(s.startedByName ?? ''),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          minWidth: Space.xxl * 4,
        ),
        DashColumn(
          id: 'status',
          label: t('inventory.stocktakes.status'),
          cell: (context, s) => Align(
            alignment: AlignmentDirectional.centerStart,
            child: DashStatusPill(
              label: stocktakeStatusLabel(t, s.status),
              tone: stocktakeStatusTone(s.status),
            ),
          ),
          width: Space.xxl * 4 + Space.lg,
        ),
        DashColumn(
          id: 'finalized_at',
          label: t('inventory.stocktakes.finalized'),
          text: (s) => f.fmtDateTime(s.finalizedAt),
          minWidth: Space.xxl * 5,
        ),
      ],
    );
  }
}
