/// The archive confirmation (web `ArchiveIngredientDialog`): what still
/// uses the ingredient and the stock it holds, read from `GET …/usage`.
/// Archiving changes neither: those recipes keep deducting it and the stock
/// stays until it is counted or wasted down. Archive sends `confirm: true`.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show
        ArchiveIngredientRequest,
        IngredientUsage,
        IngredientUsageRef,
        OrgIngredient;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/archive.dart';
import '../shared/inventory_data.dart';

/// `GET /inventory/orgs/{org_id}/catalog/{id}/usage` (getCatalogItemUsage),
/// read fresh each time the dialog opens (the web's `staleTime: 0`).
final ingredientUsageProvider = FutureProvider.autoDispose
    .family<IngredientUsage, ({String orgId, String id})>((ref, k) {
      ref.watch(
        realtimeEpochProvider('/inventory/orgs/${k.orgId}/catalog/${k.id}'),
      );
      return ref
          .watch(apiProvider)
          .inventory
          .getCatalogItemUsage(orgId: k.orgId, id: k.id);
    });

/// The order the groups show in (the server's `ord`).
const List<String> archiveUsageKinds = [
  'recipe',
  'modifier_option',
  'swap',
  'recipe_base',
  'packaging_rule',
  'purchase_order',
  'stocktake',
  'transfer',
];

/// A usage kind's group label (`inventory.archive.kind.*`).
String archiveKindLabel(Translator t, String kind) => switch (kind) {
  'recipe' => t('inventory.archive.kind.recipe'),
  'modifier_option' => t('inventory.archive.kind.modifierOption'),
  'swap' => t('inventory.archive.kind.swap'),
  'recipe_base' => t('inventory.archive.kind.recipeBase'),
  'packaging_rule' => t('inventory.archive.kind.packagingRule'),
  'purchase_order' => t('inventory.archive.kind.purchaseOrder'),
  'stocktake' => t('inventory.archive.kind.stocktake'),
  'transfer' => t('inventory.archive.kind.transfer'),
  _ => kind,
};

/// [usages] grouped by kind, in [archiveUsageKinds] order (an unknown kind
/// last).
List<(String, List<IngredientUsageRef>)> groupUsages(
  List<IngredientUsageRef> usages,
) {
  final by = <String, List<IngredientUsageRef>>{};
  for (final u in usages) {
    (by[u.kind] ??= []).add(u);
  }
  int rank(String k) {
    final i = archiveUsageKinds.indexOf(k);
    return i < 0 ? archiveUsageKinds.length : i;
  }

  final kinds = by.keys.toList()..sort((a, b) => rank(a) - rank(b));
  return [for (final k in kinds) (k, by[k]!)];
}

/// Opens the confirmation for [item]; true once it is archived.
Future<bool> showArchiveIngredientDialog(
  BuildContext context, {
  required String orgId,
  required OrgIngredient item,
}) async =>
    await showDashDialog<bool>(
      context,
      builder: (_) => ArchiveIngredientDialog(orgId: orgId, item: item),
    ) ??
    false;

class ArchiveIngredientDialog extends ConsumerStatefulWidget {
  const ArchiveIngredientDialog({
    required this.orgId,
    required this.item,
    super.key,
  });

  final String orgId;
  final OrgIngredient item;

  @override
  ConsumerState<ArchiveIngredientDialog> createState() =>
      _ArchiveIngredientDialogState();
}

class _ArchiveIngredientDialogState
    extends ConsumerState<ArchiveIngredientDialog> {
  bool _busy = false;

  ({String orgId, String id}) get _key =>
      (orgId: widget.orgId, id: widget.item.id);

  Future<void> _archive() async {
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider);
    final bus = ref.read(realtimeBusProvider);
    setState(() => _busy = true);
    try {
      await api.inventory.archiveCatalogItem(
        orgId: widget.orgId,
        id: widget.item.id,
        body: const ArchiveIngredientRequest(confirm: true),
      );
    } on Object catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        DashToast.error(context, errorMessage(e, t));
      }
      return;
    }
    bus.invalidate(inventoryPathFamilies);
    if (!mounted) return;
    Navigator.of(context).pop(true);
    DashToast.success(
      context,
      t('inventory.archive.archived', args: {'name': widget.item.name}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final usage = ref.watch(ingredientUsageProvider(_key));
    final data = usage.value;
    final Widget body;
    if (usage.awaitingFirst) {
      body = const Column(
        key: ValueKey('archive-usage-loading'),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.sm,
        children: [
          DashSkeleton(width: Space.xxl * 8, height: Space.lg),
          DashSkeleton(width: Space.xxl * 6, height: Space.lg),
        ],
      );
    } else if (usage.hasError && !usage.retrying) {
      body = DashErrorState(
        key: const ValueKey('archive-usage-error'),
        framed: false,
        retrying: usage.isLoading,
        message: errorMessage(usage.error, t),
        retryLabel: t('common.retry'),
        onRetry: () => ref.invalidate(ingredientUsageProvider(_key)),
      );
    } else if (data != null) {
      body = _UsageBody(usage: data, unit: widget.item.unit);
    } else {
      body = const SizedBox.shrink();
    }
    return DashSurface(
      key: const ValueKey('archive-ingredient-dialog'),
      title: t('inventory.archive.title', args: {'name': widget.item.name}),
      description: t('inventory.archive.consequence'),
      body: body,
      actions: [
        DashButton(
          label: t('common.cancel'),
          variant: DashButtonVariant.outline,
          onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
        ),
        DashButton(
          key: const ValueKey('archive-confirm'),
          label: t('inventory.archive.action'),
          icon: archiveGlyph,
          loading: _busy,
          onPressed: data == null ? null : _archive,
        ),
      ],
    );
  }
}

class _UsageBody extends ConsumerWidget {
  const _UsageBody({required this.usage, required this.unit});

  final IngredientUsage usage;
  final String unit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final heading = DashType.bodyMedium.copyWith(color: c.textPrimary);
    final muted = DashType.body.copyWith(color: c.textSecondary);
    final groups = groupUsages(usage.usages);
    final stock = usage.stock;
    if (groups.isEmpty && stock.isEmpty) {
      return Text(
        t('inventory.archive.unused'),
        key: const ValueKey('archive-unused'),
        style: muted,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.lg,
      children: [
        if (groups.isNotEmpty)
          Column(
            key: const ValueKey('archive-usages'),
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            spacing: Space.sm,
            children: [
              Text(t('inventory.archive.stillUsed'), style: heading),
              Text(t('inventory.archive.keepsDeducting'), style: muted),
              for (final (kind, rows) in groups)
                Column(
                  key: ValueKey('archive-kind-$kind'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  spacing: Space.xs,
                  children: [
                    Text(
                      '${archiveKindLabel(t, kind)} · '
                      '${dashFigure(f.fmtNumber(rows.length))}',
                      style: DashType.smallMedium.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                    for (final u in rows)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: Space.md,
                        ),
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '• ${u.name}',
                                style: DashType.body.copyWith(
                                  color: c.textPrimary,
                                ),
                              ),
                              if (u.detail != null && u.detail!.isNotEmpty)
                                TextSpan(text: ' · ${u.detail}', style: muted),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        if (stock.isNotEmpty)
          Column(
            key: const ValueKey('archive-stock'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: Space.xs,
            children: [
              Text(t('inventory.archive.onHand'), style: heading),
              for (final s in stock)
                Row(
                  spacing: Space.md,
                  children: [
                    Expanded(
                      child: Text(
                        s.branchName,
                        style: DashType.body.copyWith(color: c.textPrimary),
                      ),
                    ),
                    Text(
                      dashFigure(
                        '${f.fmtNumber(s.onHand)} '
                        '${fmtUnit(unit.isEmpty ? usage.unit : unit)}',
                      ),
                      style: DashType.mono.copyWith(color: c.textPrimary),
                    ),
                  ],
                ),
              const SizedBox(height: Space.xs),
              Text(t('inventory.archive.stockStays'), style: muted),
            ],
          ),
      ],
    );
  }
}
