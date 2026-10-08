/// The Reorder tab (INV-PUR-022…027): what the branch should buy, one group
/// per default supplier, each with "Create draft PO". Read only while the
/// tab is open, and only with a branch picked.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show ReorderLine, ReorderSuggestion;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/inventory_labels.dart';
import '../shared/on_hand.dart';
import 'purchase_order_dialog.dart';
import 'purchasing_data.dart';

class ReorderTab extends ConsumerWidget {
  const ReorderTab({required this.branchId, super.key});

  final String branchId;

  List<DashColumn<ReorderLine>> _columns(
    Translator t,
    DashFormat f,
    BuildContext context,
  ) {
    final c = context.madarColors;
    return [
      DashColumn(
        id: 'ingredient_name',
        label: t('inventory.catalog.name'),
        text: (l) => l.ingredientName,
        cell: (context, l) => MadarClippedText(
          l.ingredientName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DashType.bodyMedium.copyWith(color: c.textPrimary),
        ),
        phone: DashPhoneRole.title,
        minWidth: Space.xxl * 5,
      ),
      DashColumn(
        id: 'on_hand',
        label: t('inventory.catalog.onHand'),
        text: (l) => qtyWithUnit(f, l.onHand, l.unit),
        cell: (context, l) => Text(
          dashFigure(qtyWithUnit(f, l.onHand, l.unit)),
          textDirection: TextDirection.ltr,
          style: DashType.mono.copyWith(color: OnHand.negativeColor(context)),
        ),
        numeric: true,
        minWidth: Space.xxl * 4,
      ),
      DashColumn(
        id: 'suggested',
        label: t('inventory.purchasing.suggested'),
        text: (l) => qtyWithUnit(f, l.suggestedQty, l.unit),
        cell: (context, l) => Text(
          dashFigure(qtyWithUnit(f, l.suggestedQty, l.unit)),
          textDirection: TextDirection.ltr,
          style: DashType.monoStrong.copyWith(color: c.textPrimary),
        ),
        numeric: true,
        minWidth: Space.xxl * 4,
      ),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final async = ref.watch(reorderSuggestionsProvider(branchId));
    final columns = _columns(t, f, context);

    if (async.hasError && !async.isLoading) {
      // A section's error: its own title and Retry, no server line.
      return DashErrorState(
        title: t('inventory.purchasing.reorderFailed'),
        onRetry: () => ref.invalidate(reorderSuggestionsProvider(branchId)),
      );
    }
    if (async.firstLoad) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.md,
        children: [
          const Align(
            alignment: AlignmentDirectional.centerStart,
            child: DashSkeleton(width: Space.xxl * 6, height: Space.xxl),
          ),
          DashDataTable<ReorderLine>(
            columns: columns,
            rows: const [],
            rowKey: (l) => l.orgIngredientId,
            loading: true,
            hideViewOptions: true,
          ),
        ],
      );
    }
    final groups = async.value ?? const <ReorderSuggestion>[];
    if (groups.isEmpty) {
      return DashEmptyState(
        icon: 'trending-down',
        title: t('inventory.purchasing.noReorder'),
        description: t('inventory.purchasing.noReorderHint'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.xxl,
      children: [
        for (final (i, g) in groups.indexed)
          Column(
            key: ValueKey('reorder-group-${g.supplierId ?? 'none'}'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: Space.md,
            children: [
              DashSectionHeader(
                title: g.supplierName ?? t('inventory.purchasing.noSupplier'),
                count: g.lines.length,
                trailing: DashButton(
                  key: ValueKey('reorder-create-$i'),
                  label: t('inventory.purchasing.createDraftPo'),
                  icon: 'plus-circle',
                  size: DashButtonSize.compact,
                  onPressed: () => showPurchaseOrderDialog(
                    context,
                    branchId: branchId,
                    prefill: PurchaseOrderPrefill(
                      supplierId: g.supplierId,
                      lines: [
                        for (final l in g.lines)
                          PurchaseOrderPrefillLine(
                            orgIngredientId: l.orgIngredientId,
                            quantity: l.suggestedQty,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              DashDataTable<ReorderLine>(
                columns: columns,
                rows: g.lines,
                rowKey: (l) => l.orgIngredientId,
                pageSize: 50,
                hideViewOptions: true,
              ),
            ],
          ),
      ],
    );
  }
}
