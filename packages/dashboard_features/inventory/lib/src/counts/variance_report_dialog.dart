/// The variance report (INV-CNT-049…054, -066; web
/// `variance-report-dialog.tsx`): a finalized count's differences against
/// BOOK stock at finalize, so the columns add up (Counted − Book =
/// Difference). Read-only; read only while open.
library;

import 'package:dashboard_api/dashboard_api.dart' show VarianceRow;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/inventory_labels.dart';
import 'count_table.dart';
import 'counts_data.dart';

/// `sm:max-w-4xl`.
const double varianceReportWidth = Space.xxl * 28;

/// Opens the report of count [id] (full screen on a phone).
Future<void> showVarianceReport(BuildContext context, String id) =>
    showDashDialog<void>(
      context,
      width: varianceReportWidth,
      builder: (_) => VarianceReportDialog(stocktakeId: id),
    );

class VarianceReportDialog extends ConsumerWidget {
  const VarianceReportDialog({required this.stocktakeId, super.key});

  final String stocktakeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final q = ref.watch(varianceReportProvider(stocktakeId));
    final data = q.hasError ? null : q.value;
    final net = data?.netVarianceValue ?? 0;

    final Widget body;
    if (q.hasError) {
      body = DashErrorState(
        title: t('inventory.stocktakes.reportFailed'),
        retryLabel: t('common.retry'),
        retrying: q.isLoading,
        onRetry: () => ref.invalidate(varianceReportProvider(stocktakeId)),
      );
    } else if (data == null) {
      body = Column(
        key: const ValueKey('variance-loading'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.sm,
        children: [
          for (var i = 0; i < 5; i++)
            const DashSkeleton(height: Space.xxl + Space.xs),
        ],
      );
    } else {
      body = _VarianceTable(rows: data.rows);
    }

    return DashSurface(
      key: const ValueKey('variance-report'),
      title: t('inventory.stocktakes.varianceReport'),
      description: data == null
          ? null
          : t(
              'inventory.stocktakes.unknownCost',
              args: {'count': data.unknownCostCount},
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          if (!q.hasError)
            DashLedgerStrip(
              key: const ValueKey('variance-kpis'),
              items: [
                DashLedgerItem(
                  key: 'shrink',
                  label: t('inventory.stocktakes.shrinkage'),
                  value: data?.totalShrinkageValue ?? 0,
                  format: DashStatFormat.money,
                  icon: 'arrow-down-circle',
                  tone: DashTone.danger,
                  loading: data == null,
                ),
                DashLedgerItem(
                  key: 'over',
                  label: t('inventory.stocktakes.overage'),
                  value: data?.totalOverageValue ?? 0,
                  format: DashStatFormat.money,
                  icon: 'arrow-up-circle',
                  tone: DashTone.success,
                  loading: data == null,
                ),
                DashLedgerItem(
                  key: 'net',
                  label: t('inventory.stocktakes.net'),
                  value: net,
                  format: DashStatFormat.money,
                  icon: 'scale',
                  tone: net < 0 ? DashTone.danger : DashTone.success,
                  loading: data == null,
                ),
              ],
            ),
          body,
        ],
      ),
    );
  }
}

/// Ingredient / Book stock / Counted / Difference / Value / Reason; no rows
/// is the header alone (INV-CNT-066).
class _VarianceTable extends ConsumerWidget {
  const _VarianceTable({required this.rows});

  final List<VarianceRow> rows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    return CountTable(
      key: const ValueKey('variance-table'),
      columns: [
        CountColumn(t('inventory.stocktakes.ingredient')),
        CountColumn(
          t('inventory.stocktakes.bookStock'),
          width: CountWidths.reportBook,
          end: true,
        ),
        CountColumn(
          t('inventory.stocktakes.counted'),
          width: CountWidths.reportFigure,
          end: true,
        ),
        CountColumn(
          t('inventory.stocktakes.difference'),
          width: CountWidths.reportFigure,
          end: true,
        ),
        CountColumn(
          t('inventory.stocktakes.value'),
          width: CountWidths.figure,
          end: true,
        ),
        CountColumn(
          t('inventory.stocktakes.reason'),
          width: CountWidths.reportReason,
        ),
      ],
      rows: [
        for (final r in rows)
          CountTableRow(
            key: ValueKey('variance-row-${r.orgIngredientId}'),
            cells: [
              CountNameCell(
                name: r.ingredientName,
                category: r.categoryName,
                pills: [
                  if (r.isFlagged)
                    DashStatusPill(
                      label: t('inventory.flagged'),
                      tone: DashTone.warning,
                      small: true,
                    ),
                ],
              ),
              CountBookCell(
                book: r.bookQty,
                opening: r.openingQty,
                unit: r.unit,
              ),
              CountFigure(
                r.countedQty == null ? '—' : f.fmtNumber(r.countedQty),
              ),
              CountFigure(
                r.variance == null
                    ? '—'
                    : f.fmtNumber(
                        r.variance,
                        const NumberOptions(
                          signDisplay: SignDisplay.exceptZero,
                        ),
                      ),
                color: countDifferenceColor(c, r.variance),
              ),
              CountFigure(f.fmtMoney(r.varianceValue)),
              MadarClippedText(
                r.varianceReason == null
                    ? '—'
                    : varianceReasonLabel(t, r.varianceReason!),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashType.body.copyWith(color: c.textPrimary),
              ),
            ],
          ),
      ],
    );
  }
}
