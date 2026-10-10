/// The ingredient drawer (INV-ING-033…048, -053, -056; web
/// `item-drawer.tsx`): an ingredient at the picked branch. On hand is the
/// ledger's figure and read-only; the way to correct it is to count it.
/// With All branches it only offers Edit and View recipes.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show
        BranchStockRow,
        CreateStocktakeRequest,
        OrgIngredient,
        SetParRequest,
        StockMovement;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show DashRoutePrefetch;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/inventory_data.dart';
import '../shared/inventory_labels.dart';
import '../shared/inventory_lib.dart';
import '../shared/on_hand.dart';
import 'ingredient_dialog.dart'
    show IngredientNumberField, warmIngredientDialog;
import 'ingredients_data.dart';

/// What the drawer hands back to the page when it closes for a dialog.
enum IngredientDrawerAction { edit, recordWaste }

/// Opens the drawer for [item] at [branchId] (null = All branches).
Future<IngredientDrawerAction?> showIngredientDrawer(
  BuildContext context, {
  required String orgId,
  required String? branchId,
  required OrgIngredient item,
}) => showDashSidePanel<IngredientDrawerAction>(
  context,
  width: IngredientDrawer.width,
  builder: (_) =>
      IngredientDrawer(orgId: orgId, branchId: branchId, item: item),
);

class IngredientDrawer extends ConsumerStatefulWidget {
  const IngredientDrawer({
    required this.orgId,
    required this.branchId,
    required this.item,
    super.key,
  });

  /// `sm:max-w-md`.
  static const double width = Space.xxl * 14;

  final String orgId;
  final String? branchId;
  final OrgIngredient item;

  @override
  ConsumerState<IngredientDrawer> createState() => _IngredientDrawerState();
}

class _IngredientDrawerState extends ConsumerState<IngredientDrawer> {
  String _parMin = '';
  String _parMax = '';

  /// The branch row's levels the fields were last filled from: a fresh row
  /// (the drawer opening, a save coming back) fills them again.
  (double?, double?)? _filledFrom;
  bool _savingPar = false;
  bool _counting = false;

  Future<void> _savePar(String branchId, OrgIngredient item) async {
    final t = ref.read(tProvider);
    final lo = parseNumberInput(_parMin);
    final hi = parseNumberInput(_parMax);
    // Captured now: the lists refresh even if the drawer closes mid-save.
    final bus = ref.read(realtimeBusProvider);
    setState(() => _savingPar = true);
    try {
      await ref
          .read(apiProvider)
          .inventory
          .setParLevels(
            branchId: branchId,
            orgIngredientId: item.id,
            body: SetParRequest(
              parMin: lo,
              parMax: hi,
              explicitNulls: {
                if (lo == null) 'par_min',
                if (hi == null) 'par_max',
              },
            ),
          );
      bus.invalidate(inventoryPathFamilies);
      if (mounted) DashToast.success(context, t('common.savedChanges'));
    } on Object catch (e) {
      if (mounted) DashToast.error(context, errorMessage(e, t));
    } finally {
      if (mounted) setState(() => _savingPar = false);
    }
  }

  /// "Count this item": join the branch's open count, or start a one-item
  /// count first; then go to Stock counts. A list still loading (or failed)
  /// reads as "no open count" (INV-ING-056).
  Future<void> _count(String branchId, OrgIngredient item) async {
    if (_counting) return;
    _counting = true;
    final t = ref.read(tProvider);
    final router = GoRouter.of(context);
    final bus = ref.read(realtimeBusProvider);
    try {
      final open =
          ref
              .read(stocktakesProvider(branchId))
              .value
              ?.any((s) => isOpenStocktake(s.status)) ??
          false;
      if (!open) {
        await ref
            .read(apiProvider)
            .stocktakes
            .createStocktake(
              branchId: branchId,
              body: CreateStocktakeRequest(
                orgIngredientIds: [item.id],
                explicitNulls: const {'note', 'category_id'},
              ),
            );
        bus.invalidate(inventoryPathFamilies);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      router.go('/inventory/counts');
    } on Object catch (e) {
      if (mounted) DashToast.error(context, errorMessage(e, t));
    } finally {
      _counting = false;
    }
  }

  void _viewRecipes() {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.go('/menu/recipes');
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final branchId = widget.branchId;
    // The catalog row as it is now (an edit lands here), else the one tapped.
    final item =
        ref
            .watch(inventoryCatalogProvider(widget.orgId))
            .value
            ?.where((i) => i.id == widget.item.id)
            .firstOrNull ??
        widget.item;
    BranchStockRow? row;
    if (branchId != null) {
      row = stockByIngredient(
        ref.watch(branchStockProvider(branchId)).value,
      )[item.id];
      ref.watch(stocktakesProvider(branchId));
      final levels = (row?.parMin, row?.parMax);
      if (levels != _filledFrom) {
        _filledFrom = levels;
        _parMin = numberFieldText(row?.parMin);
        _parMax = numberFieldText(row?.parMax);
      }
    }
    final cost = drawerCost(item, row);
    final costLine = StringBuffer()
      ..write(
        cost.branchLabel
            ? t('inventory.catalog.branchCost')
            : t('inventory.catalog.standardCost'),
      )
      ..write(': ')
      ..write(dashFigure(f.fmtMoney(cost.cost)));
    if (item.supplierName != null) costLine.write(' · ${item.supplierName}');

    return DashSurface(
      key: const ValueKey('ingredient-drawer'),
      title: item.name,
      description: costLine.toString(),
      headerTrailing: Padding(
        padding: const EdgeInsets.only(top: Space.sm),
        child: DashBadge(item.categoryName),
      ),
      body: branchId == null
          ? const _PickBranch()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              spacing: Space.lg,
              children: [
                _OnHandBox(
                  item: item,
                  row: row,
                  onCount: () => _count(branchId, item),
                ),
                _ParBox(
                  unit: item.unit,
                  parMin: _parMin,
                  parMax: _parMax,
                  saving: _savingPar,
                  onMin: (v) => setState(() => _parMin = v),
                  onMax: (v) => setState(() => _parMax = v),
                  onSave: () => _savePar(branchId, item),
                ),
                _History(branchId: branchId, ingredientId: item.id),
              ],
            ),
      actions: [
        DashButton(
          key: const ValueKey('ingredient-drawer-edit'),
          label: t('common.edit'),
          icon: 'pencil',
          variant: DashButtonVariant.outline,
          size: DashButtonSize.compact,
          onPressed: () =>
              Navigator.of(context).pop(IngredientDrawerAction.edit),
          onIntent: () => warmIngredientDialog(ref, widget.orgId),
        ),
        if (branchId != null)
          DashButton(
            key: const ValueKey('ingredient-drawer-waste'),
            label: t('inventory.waste.record'),
            icon: 'trash-2',
            variant: DashButtonVariant.outline,
            size: DashButtonSize.compact,
            onPressed: (row?.onHand ?? 0) <= 0
                ? null
                : () => Navigator.of(
                    context,
                  ).pop(IngredientDrawerAction.recordWaste),
          ),
        DashButton(
          key: const ValueKey('ingredient-drawer-recipes'),
          label: t('inventory.viewRecipes'),
          icon: 'chef-hat',
          variant: DashButtonVariant.outline,
          size: DashButtonSize.compact,
          onPressed: _viewRecipes,
          onIntent: () => ref.prefetchRoute('/menu/recipes'),
        ),
      ],
    );
  }
}

/// A bordered box (`rounded-lg border p-3`).
class _Box extends StatelessWidget {
  const _Box({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(Space.md),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(Radii.sm),
      border: Border.all(color: context.madarColors.hairline),
    ),
    child: child,
  );
}

class _PickBranch extends ConsumerWidget {
  const _PickBranch();

  @override
  Widget build(BuildContext context, WidgetRef ref) => _Box(
    key: const ValueKey('ingredient-drawer-pick-branch'),
    child: Text(
      ref.watch(tProvider)('inventory.pickBranch'),
      style: DashType.body.copyWith(color: context.madarColors.textSecondary),
    ),
  );
}

/// The book stock: on hand (below zero tinted, with its pill), when it was
/// last counted, and "Count this item".
class _OnHandBox extends ConsumerWidget {
  const _OnHandBox({
    required this.item,
    required this.row,
    required this.onCount,
  });

  final OrgIngredient item;
  final BranchStockRow? row;
  final VoidCallback onCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final onHand = row?.onHand ?? 0;
    final below = isBelowZero(onHand);
    final counted = row?.lastCountedAt;
    final muted = DashType.small.copyWith(color: c.textSecondary);
    return _Box(
      key: const ValueKey('ingredient-drawer-on-hand'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.xs,
        children: [
          Text(
            t('inventory.catalog.onHand'),
            style: DashType.smallMedium.copyWith(color: c.textSecondary),
          ),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: dashFigure(f.fmtNumber(onHand)),
                  style: MadarType.numLg.copyWith(
                    fontWeight: FontWeight.w600,
                    color: below
                        ? OnHand.negativeColor(context)
                        : c.textPrimary,
                  ),
                ),
                TextSpan(
                  text: ' ${fmtUnit(item.unit)}',
                  style: DashType.body.copyWith(color: c.textSecondary),
                ),
              ],
            ),
          ),
          if (below)
            DashStatusPill(
              label: t('inventory.catalog.belowZero'),
              tone: DashTone.danger,
              small: true,
            ),
          Text(
            counted != null
                ? t(
                    'inventory.catalog.lastCounted',
                    args: {'when': dashFigure(f.fmtDateTime(counted))},
                  )
                : t('inventory.catalog.neverCountedHint'),
            style: muted,
          ),
          const SizedBox(height: Space.sm),
          DashButton(
            key: const ValueKey('ingredient-drawer-count'),
            label: t('inventory.catalog.countThisItem'),
            icon: 'clipboard-list',
            size: DashButtonSize.compact,
            onPressed: onCount,
          ),
        ],
      ),
    );
  }
}

/// Reorder levels at this branch, saved on their own.
class _ParBox extends ConsumerWidget {
  const _ParBox({
    required this.unit,
    required this.parMin,
    required this.parMax,
    required this.saving,
    required this.onMin,
    required this.onMax,
    required this.onSave,
  });

  final String unit;
  final String parMin;
  final String parMax;
  final bool saving;
  final ValueChanged<String> onMin;
  final ValueChanged<String> onMax;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    return _Box(
      key: const ValueKey('ingredient-drawer-pars'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.sm,
        children: [
          Text(
            t('inventory.catalog.reorderLevels'),
            style: DashType.bodyMedium.copyWith(color: c.textPrimary),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.sm,
            children: [
              Expanded(
                child: IngredientNumberField(
                  key: const ValueKey('ingredient-drawer-par-min'),
                  label: '${t('inventory.catalog.parMin')} (${fmtUnit(unit)})',
                  value: parMin,
                  onChanged: onMin,
                ),
              ),
              Expanded(
                child: IngredientNumberField(
                  key: const ValueKey('ingredient-drawer-par-max'),
                  label: t('inventory.catalog.parMax'),
                  value: parMax,
                  onChanged: onMax,
                ),
              ),
            ],
          ),
          DashButton(
            key: const ValueKey('ingredient-drawer-par-save'),
            label: t('common.save'),
            variant: DashButtonVariant.outline,
            size: DashButtonSize.compact,
            loading: saving,
            onPressed: onSave,
          ),
        ],
      ),
    );
  }
}

/// The latest 50 movements of the ingredient at the branch.
class _History extends ConsumerWidget {
  const _History({required this.branchId, required this.ingredientId});

  final String branchId;
  final String ingredientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final key = (branchId: branchId, ingredientId: ingredientId);
    final q = ref.watch(ingredientMovementsProvider(key));
    final rows = q.value ?? const <StockMovement>[];
    Widget body;
    if (q.awaitingFirst) {
      body = Column(
        key: const ValueKey('ingredient-history-loading'),
        spacing: Space.md,
        children: [
          for (var i = 0; i < 4; i++)
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: Space.xs + DashMetrics.hair,
                    children: [
                      DashSkeleton(width: Space.xxl * 3.5, height: Space.lg),
                      DashSkeleton(width: Space.xxl * 2.5, height: Space.md),
                    ],
                  ),
                ),
                DashSkeleton(width: Space.xxl * 2, height: Space.lg),
              ],
            ),
        ],
      );
    } else if (q.hasError && !q.retrying) {
      body = DashErrorState(
        key: const ValueKey('ingredient-history-error'),
        framed: false,
        retrying: q.isLoading,
        title: t('inventory.movements.loadFailed'),
        retryLabel: t('common.retry'),
        onRetry: () => ref.invalidate(ingredientMovementsProvider(key)),
      );
    } else if (rows.isEmpty) {
      body = Text(
        t('inventory.movements.noMovements'),
        key: const ValueKey('ingredient-history-empty'),
        style: DashType.body.copyWith(color: c.textSecondary),
      );
    } else {
      body = Column(
        key: const ValueKey('ingredient-history'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++)
            _MovementRow(
              key: ValueKey('movement-${rows[i].id}'),
              m: rows[i],
              last: i == rows.length - 1,
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.sm,
      children: [
        Text(
          t('inventory.stockHistory'),
          style: DashType.bodyMedium.copyWith(color: c.textPrimary),
        ),
        body,
      ],
    );
  }
}

class _MovementRow extends ConsumerWidget {
  const _MovementRow({required this.m, required this.last, super.key});

  final StockMovement m;
  final bool last;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final muted = DashType.small.copyWith(color: c.textSecondary);
    final tone = m.quantity < 0 ? DashTone.danger : DashTone.success;
    return Container(
      padding: const EdgeInsets.only(bottom: Space.sm),
      margin: EdgeInsets.only(bottom: last ? 0 : Space.sm),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: c.hairline)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Space.md,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  movementTypeLabel(t, m.movementType),
                  style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                ),
                Text(dashFigure(f.fmtDateTime(m.createdAt)), style: muted),
                if (m.note != null && m.note!.isNotEmpty)
                  Text(m.note!, style: muted),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                dashFigure(
                  '${f.fmtNumber(m.quantity, const NumberOptions(signDisplay: SignDisplay.exceptZero))} '
                  '${fmtUnit(m.unit)}',
                ),
                key: ValueKey('movement-qty-${m.id}'),
                style: DashType.mono.copyWith(color: tone.foreground(c)),
              ),
              Text(
                dashFigure(f.fmtNumber(m.balanceAfter)),
                style: DashType.mono.copyWith(
                  color: c.textSecondary,
                  fontSize: DashType.small.fontSize,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
