/// Waste log (`/inventory/waste`, the INV-WST rows; web
/// `src/features/inventory/waste-page.tsx`): the scoped branch's waste log
/// (or the org's, with All branches) beside the period's waste by reason.
///
/// Record waste needs a picked branch and `inventory.waste.record`; nothing
/// else on the page is gated (INV-ALL-006).
library;

import 'package:dashboard_api/dashboard_api.dart' show StockMovement;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/inventory_data.dart';
import '../shared/inventory_export.dart';
import '../shared/inventory_labels.dart';
import '../shared/inventory_lib.dart';
import '../today/today_providers.dart' show todayWasteProvider;
import 'waste_data.dart';
import 'waste_dialog.dart';

/// When a line happened (`occurred_at ?? created_at`).
DateTime _when(StockMovement m) => m.occurredAt ?? m.createdAt;

/// The receive time worth showing (a till that was offline), or null.
String? _late(StockMovement m) => wasteReceivedLate(
  occurredAt: m.occurredAt?.toUtc().toIso8601String(),
  receivedAt: m.receivedAt?.toUtc().toIso8601String(),
  createdAt: m.createdAt.toUtc().toIso8601String(),
);

String _source(StockMovement m) =>
    wasteSource(wasteSource: m.wasteSource, sourceType: m.sourceType);

/// A line wasted as a menu item names it.
bool _fromItem(StockMovement m) =>
    m.wasteSubjectKind == 'menu_item' && (m.wasteSubjectName ?? '').isNotEmpty;

class WastePage extends ConsumerStatefulWidget {
  const WastePage({super.key});

  @override
  ConsumerState<WastePage> createState() => _WastePageState();
}

class _WastePageState extends ConsumerState<WastePage> {
  bool _exporting = false;

  /// INV-WST-004: the whole log, walked, as `Madar-Waste-<date>.xlsx`.
  Future<void> _export(String branchId) async {
    final t = ref.read(tProvider);
    final transport = ref.read(transportProvider);
    setState(() => _exporting = true);
    try {
      final rows = await fetchWholeWasteLog(transport, branchId);
      if (!mounted) return;
      await inventoryExportExcel(context, ref, _config(t, rows));
    } on ExportTooLargeError catch (e) {
      if (mounted) DashToast.error(context, e.message(t));
    } on Object catch (e) {
      if (mounted) DashToast.error(context, errorMessage(e, t));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  ExcelConfig _config(Translator t, List<StockMovement> rows) {
    StockMovement m(Object? r) => r! as StockMovement;
    ExcelColumn<Object?> col(
      String header,
      Object? Function(StockMovement m) value,
      ExcelColumnType type,
      double width,
    ) => ExcelColumn<Object?>(
      header: header,
      accessor: (r) => value(m(r)),
      type: type,
      width: width,
    );
    return ExcelConfig(
      filename: 'Madar-Waste',
      logoUrl: inventoryExportLogo(ref),
      sheets: [
        ExcelSheet<Object?>(
          name: t('inventory.waste.title'),
          title: t('inventory.waste.title'),
          rows: rows,
          columns: [
            col(t('common.date'), _when, ExcelColumnType.dateTime, 20),
            col(
              t('inventory.waste.receivedColumn'),
              _late,
              ExcelColumnType.dateTime,
              20,
            ),
            col(
              t('inventory.waste.ingredient'),
              (m) => m.ingredientName,
              ExcelColumnType.text,
              28,
            ),
            col(
              t('inventory.waste.quantity'),
              (m) => m.quantity.abs(),
              ExcelColumnType.number,
              14,
            ),
            col(
              t('inventory.catalog.unit'),
              (m) => fmtUnit(m.unit),
              ExcelColumnType.text,
              10,
            ),
            col(
              t('inventory.waste.reason'),
              (m) => m.reason == null ? '—' : wasteReasonLabel(t, m.reason!),
              ExcelColumnType.text,
              18,
            ),
            col(
              t('inventory.waste.by'),
              (m) => m.createdByName ?? '—',
              ExcelColumnType.text,
              18,
            ),
            col(
              t('inventory.waste.approvedByColumn'),
              (m) => m.approvedByName ?? '',
              ExcelColumnType.text,
              18,
            ),
            col(
              t('inventory.waste.item'),
              (m) => m.wasteSubjectKind == 'menu_item'
                  ? m.wasteSubjectName ?? ''
                  : '',
              ExcelColumnType.text,
              22,
            ),
            col(
              t('inventory.waste.source'),
              (m) => wasteSourceLabel(t, _source(m)),
              ExcelColumnType.text,
              14,
            ),
            col(
              t('inventory.waste.deviceColumn'),
              (m) => m.deviceName ?? '',
              ExcelColumnType.text,
              12,
            ),
            col(
              t('inventory.waste.orderColumn'),
              (m) => m.orderDisplayNumber ?? '',
              ExcelColumnType.text,
              12,
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final scope = ref.watch(currentScopeProvider);
    final branchId = scope.branchId;
    final canRecord = ref.watch(
      authzProvider.select((a) => a.can(Cap.inventoryWasteRecord)),
    );
    final logKey = scope.scopeBranchId;
    final log = ref.watch(todayWasteProvider(logKey));
    final rows = log.value ?? const <StockMovement>[];
    final wide = MediaQuery.sizeOf(context).width >= DashBreakpoints.lg;

    final table = WasteTable(
      rows: rows,
      allBranches: scope.isAllBranches,
      loading: log.awaitingFirst,
      // Kept while Retry runs (no false "No waste recorded" in between).
      errorText: log.failedFirst ? errorMessage(log.error, t) : null,
      onRetry: () => ref.invalidate(todayWasteProvider(logKey)),
    );
    final reasons = WasteByReason(range: scope.wasteRange);

    return DashPageScaffold(
      title: t('inventory.waste.title'),
      actions: [
        DashExportButton(
          key: const ValueKey('waste-export'),
          loading: _exporting,
          enabled: rows.isNotEmpty,
          onExport: () => _export(logKey),
        ),
        if (branchId != null && canRecord)
          DashButton(
            key: const ValueKey('waste-record'),
            label: t('inventory.waste.record'),
            icon: 'trash-2',
            // The dialog's read: the branch's stock.
            onIntent: () => ref.warm(branchStockProvider(branchId)),
            onPressed: () => showRecordWasteDialog(context, branchId: branchId),
          ),
      ],
      body: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.xl,
              children: [
                Expanded(flex: 2, child: table),
                Expanded(child: reasons),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.xl,
              children: [table, reasons],
            ),
    );
  }
}

/// The log (INV-WST-005…013): Date, Branch (All branches only), Ingredient,
/// Quantity, Reason, By, Source; 10 a page, searched over the raw values.
/// Below 760 each row is a card led by the ingredient.
class WasteTable extends ConsumerWidget {
  const WasteTable({
    required this.rows,
    required this.allBranches,
    required this.loading,
    required this.errorText,
    required this.onRetry,
    super.key,
  });

  final List<StockMovement> rows;
  final bool allBranches;
  final bool loading;
  final String? errorText;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final muted = DashType.small.copyWith(color: c.textMuted);
    Widget lines(String main, List<String> under, {TextStyle? style}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: DashMetrics.hair,
      children: [
        // The web's cells never wrap (`whitespace-nowrap`): one line each.
        MadarClippedText(
          main,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
        for (final u in under)
          MadarClippedText(
            u,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: muted,
          ),
      ],
    );
    return DashDataTable<StockMovement>(
      key: const ValueKey('waste-table'),
      rows: rows,
      rowKey: (m) => m.id,
      loading: loading,
      errorMessage: errorText,
      onRetry: onRetry,
      searchPlaceholder: t('common.search'),
      empty: DashEmptyState(
        icon: 'trash-2',
        title: t('inventory.waste.noWaste'),
      ),
      columns: [
        DashColumn(
          id: 'occurred_at',
          label: t('common.date'),
          text: (m) => _when(m).toUtc().toIso8601String(),
          cell: (context, m) {
            final late = _late(m);
            return lines(f.fmtDateTime(_when(m)), [
              if (late != null)
                t(
                  'inventory.waste.received',
                  args: {'when': f.fmtDateTime(late)},
                ),
            ]);
          },
          numeric: true,
          align: DashAlign.start,
          // "Received 07 Oct, 10:05 AM" uncut.
          width: Space.xxl * 6 + Space.lg,
        ),
        if (allBranches)
          DashColumn(
            id: 'branch_name',
            label: t('inventory.waste.branch'),
            text: (m) => m.branchName ?? '',
            cell: (context, m) => lines(m.branchName ?? '—', const []),
            minWidth: Space.xxl * 3 + Space.lg,
          ),
        DashColumn(
          id: 'ingredient_name',
          label: t('inventory.waste.ingredient'),
          text: (m) => m.ingredientName,
          cell: (context, m) => lines(m.ingredientName, [
            if (_fromItem(m))
              t(
                'inventory.waste.fromItem',
                args: {
                  'item': m.wasteSizeLabel == null
                      ? m.wasteSubjectName
                      : '${m.wasteSubjectName} (${m.wasteSizeLabel})',
                  'qty': f.fmtNumber(m.wasteQuantity ?? 0),
                },
              ),
          ], style: DashType.bodyMedium.copyWith(color: c.textPrimary)),
          phone: DashPhoneRole.title,
          // "From Latte (Medium) × 2" uncut.
          minWidth: Space.xxl * 6,
        ),
        DashColumn(
          id: 'quantity',
          label: t('inventory.waste.quantity'),
          // Searched by its raw (signed) figure, as the web's accessor.
          text: (m) => jsNumberString(m.quantity),
          cell: (context, m) => Text(
            qtyWithUnit(f, m.quantity.abs(), m.unit),
            maxLines: 1,
            softWrap: false,
          ),
          numeric: true,
          width: Space.xxl * 3 + Space.sm,
        ),
        DashColumn(
          id: 'reason',
          label: t('inventory.waste.reason'),
          text: (m) => m.reason ?? '',
          cell: (context, m) => lines(
            m.reason == null ? '—' : wasteReasonLabel(t, m.reason!),
            const [],
          ),
          // "Overproduction", "Refunded sale" uncut, as the web's nowrap cells.
          minWidth: Space.xxl * 4,
        ),
        DashColumn(
          id: 'created_by_name',
          label: t('inventory.waste.by'),
          text: (m) => m.createdByName ?? '',
          cell: (context, m) => lines(m.createdByName ?? '—', [
            if (m.approvedByName != null)
              t('inventory.waste.approvedBy', args: {'name': m.approvedByName}),
          ]),
          // "Approved by {name}" uncut.
          minWidth: Space.xxl * 6,
        ),
        DashColumn(
          id: 'source',
          label: t('inventory.waste.source'),
          searchable: false,
          cell: (context, m) {
            final source = _source(m);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: DashMetrics.hair,
              children: [
                SourceBadge(
                  wasteSourceLabel(t, source),
                  filled: source == 'pos',
                ),
                if (m.deviceName != null)
                  MadarClippedText(
                    t('inventory.waste.device', args: {'name': m.deviceName}),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: muted,
                  ),
                if (source == 'refund' && m.orderDisplayNumber != null)
                  MadarClippedText(
                    t(
                      'inventory.waste.refundOf',
                      args: {'number': m.orderDisplayNumber},
                    ),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: muted,
                  ),
              ],
            );
          },
          // The widest badge ("Voided order", "لوحة التحكم") on one line.
          minWidth: Space.xxl * 4,
        ),
      ],
    );
  }
}

/// The web's `Badge`: `secondary` (filled) for a till's waste, `outline`
/// for the others.
class SourceBadge extends StatelessWidget {
  const SourceBadge(this.label, {required this.filled, super.key});

  final String label;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm,
        vertical: DashMetrics.hair,
      ),
      decoration: BoxDecoration(
        color: filled ? DashTone.neutral.wash(c) : null,
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: filled ? Colors.transparent : c.hairline),
      ),
      // The web's cells never wrap (`whitespace-nowrap`).
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        style: DashType.smallMedium.copyWith(color: c.textPrimary),
      ),
    );
  }
}

/// "By reason" (INV-WST-024…028): the period's waste value per reason and
/// the total, with its own loading, error and empty states.
class WasteByReason extends ConsumerWidget {
  const WasteByReason({required this.range, super.key});

  final WasteRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final q = ref.watch(wasteReportProvider(range));
    final Widget body;
    if (q.failedFirst) {
      body = DashErrorState(
        title: t('inventory.waste.reportFailed'),
        retrying: q.isLoading,
        onRetry: () => ref.invalidate(wasteReportProvider(range)),
      );
    } else if (q.awaitingFirst) {
      body = DashCard(
        key: const ValueKey('waste-reasons-loading'),
        padding: const EdgeInsets.all(Space.card),
        child: Column(
          spacing: Space.md,
          children: [
            for (var i = 0; i < 4; i++)
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  DashSkeleton(width: Space.xxl * 3 + Space.lg),
                  DashSkeleton(width: Space.xxl * 2),
                ],
              ),
          ],
        ),
      );
    } else {
      final rows = q.value ?? const [];
      final reasons = wasteByReason(rows);
      body = reasons.isEmpty
          ? DashEmptyState(title: t('inventory.waste.noReasonData'))
          : DashCard(
              key: const ValueKey('waste-reasons'),
              padding: const EdgeInsets.symmetric(
                horizontal: Space.card,
                vertical: Space.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final r in reasons)
                    DashSummaryLine(
                      label: wasteReasonLabel(t, r.reason),
                      value: r.hasValue ? f.fmtMoney(r.value) : '—',
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Space.sm),
                    child: Divider(height: 1, thickness: 1, color: c.hairline),
                  ),
                  DashSummaryLine(
                    emphasis: true,
                    label: t('inventory.waste.totalPeriod'),
                    value: f.fmtMoney(wasteTotal(rows)),
                  ),
                ],
              ),
            );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.md,
      children: [
        DashSectionHeader(title: t('inventory.waste.byReason')),
        body,
      ],
    );
  }
}
