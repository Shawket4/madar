/// The Record waste dialog (INV-WST-014…023, INV-WST-031; web
/// `waste-dialog.tsx`), opened from the Waste log, from Today's "Log waste"
/// (INV-TOD-030, no preset) and from the ingredient drawer's "Record waste"
/// (INV-ING-043/046, ingredient preset). Today and Ingredients call
/// [showRecordWasteDialog] and nothing else.
///
/// The picker lists the branch's whole catalog; Record waste is off until an
/// ingredient is picked and 0 < quantity ≤ on hand (the server guards the
/// rest). A recorded waste invalidates inventory, toasts and closes.
library;

import 'package:collection/collection.dart';
import 'package:dashboard_api/dashboard_api.dart' show CreateWasteRequest;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show DashRoutePrefetch;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../purchasing/purchasing_widgets.dart' show PoNumberInput;
import '../shared/inventory_data.dart';
import '../shared/inventory_labels.dart';
import '../shared/inventory_lib.dart';
import '../shared/on_hand.dart';

/// Opens the dialog for [branchId] (with [presetIngredientId] picked); true
/// once the waste was recorded (inventory invalidated, toast shown).
Future<bool?> showRecordWasteDialog(
  BuildContext context, {
  required String branchId,
  String? presetIngredientId,
}) => showDashDialog<bool>(
  context,
  builder: (_) => RecordWasteDialog(
    branchId: branchId,
    presetIngredientId: presetIngredientId,
  ),
);

class RecordWasteDialog extends ConsumerStatefulWidget {
  const RecordWasteDialog({
    required this.branchId,
    this.presetIngredientId,
    super.key,
  });

  final String branchId;
  final String? presetIngredientId;

  @override
  ConsumerState<RecordWasteDialog> createState() => _RecordWasteDialogState();
}

class _RecordWasteDialogState extends ConsumerState<RecordWasteDialog> {
  late String? _ingredientId = widget.presetIngredientId;
  String _qty = '';
  String _reason = 'expired';
  String _note = '';
  bool _busy = false;

  Future<void> _submit(double quantity) async {
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider).inventory;
    // Captured now: inventory refreshes even if the dialog closes mid-save.
    final bus = ref.read(realtimeBusProvider);
    final note = _note.trim();
    setState(() => _busy = true);
    try {
      await api.createWaste(
        branchId: widget.branchId,
        body: CreateWasteRequest(
          orgIngredientId: _ingredientId!,
          quantity: quantity,
          reason: _reason,
          note: note.isEmpty ? null : note,
          explicitNulls: note.isEmpty ? const {'note'} : const {},
        ),
      );
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      DashToast.error(context, errorMessage(e, t));
      return;
    }
    bus.invalidate(inventoryPathFamilies);
    if (!mounted) return;
    DashToast.success(context, t('inventory.waste.recorded'));
    Navigator.of(context).pop(true);
  }

  /// "Count it first" (INV-WST-015): Stock counts, the scope kept.
  void _countFirst() {
    final router = GoRouter.of(context);
    Navigator.of(context).pop(false);
    router.go('/inventory/counts');
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final stock = ref.watch(branchStockProvider(widget.branchId));
    final rows = stock.value ?? const [];
    final selected = rows.firstWhereOrNull(
      (s) => s.orgIngredientId == _ingredientId,
    );
    final quantity = dashParseNumber(_qty);
    final exceeds = exceedsOnHand(quantity, selected?.onHand);
    final valid =
        _ingredientId != null &&
        quantity != null &&
        quantity > 0 &&
        !exceeds;
    final failed = stock.failedFirst;
    final nothingCounted =
        !failed && !stock.awaitingFirst && rows.every((s) => !s.hasActivity);

    Widget callout(DashTone tone, String text, Widget action) => Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: Space.md,
        vertical: Space.xs,
      ),
      decoration: BoxDecoration(
        color: tone.wash(c),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: Space.xs,
        children: [
          Text(text, style: DashType.small.copyWith(color: c.textPrimary)),
          action,
        ],
      ),
    );

    return DashSurface(
      title: t('inventory.waste.recordTitle'),
      description: t('inventory.waste.title'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.md,
        children: [
          if (failed)
            callout(
              DashTone.danger,
              errorMessage(stock.error, t),
              DashButton(
                key: const ValueKey('waste-stock-retry'),
                label: t('common.retry'),
                variant: DashButtonVariant.link,
                size: DashButtonSize.compact,
                loading: stock.isLoading,
                onPressed: () =>
                    ref.invalidate(branchStockProvider(widget.branchId)),
              ),
            )
          else if (nothingCounted)
            callout(
              DashTone.info,
              t('inventory.waste.countFirstHint'),
              DashButton(
                key: const ValueKey('waste-count-first'),
                label: t('inventory.waste.countFirstLink'),
                variant: DashButtonVariant.link,
                size: DashButtonSize.compact,
                onIntent: () => ref.prefetchRoute('/inventory/counts'),
                onPressed: _countFirst,
              ),
            ),
          DashSelectField<String>(
            key: const ValueKey('waste-ingredient'),
            label: t('inventory.waste.ingredient'),
            placeholder: t('inventory.stock.pickIngredient'),
            searchable: true,
            searchPlaceholder: t('common.search'),
            value: _ingredientId,
            description: selected == null
                ? null
                : t(
                    'inventory.waste.onHandHint',
                    args: {
                      'qty': f.fmtNumber(selected.onHand),
                      'unit': fmtUnit(selected.unit),
                    },
                  ),
            options: [
              for (final s in rows)
                DashOption(
                  value: s.orgIngredientId,
                  label: s.ingredientName,
                  keywords: s.categoryName,
                  hint: s.onHand > 0
                      ? qtyWithUnit(f, s.onHand, s.unit)
                      : s.onHand < 0
                      ? t(
                          'inventory.catalog.belowZeroHint',
                          args: {'qty': qtyWithUnit(f, s.onHand, s.unit)},
                        )
                      : t('inventory.waste.nothingOnHand'),
                ),
            ],
            onChanged: (v) => setState(() => _ingredientId = v),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.md,
            children: [
              Expanded(
                child: DashFormField<String>(
                  label: t('inventory.waste.quantity'),
                  builder: (context, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    spacing: Space.xs,
                    children: [
                      PoNumberInput(
                        key: const ValueKey('waste-quantity'),
                        value: _qty,
                        semanticLabel: t('inventory.waste.quantity'),
                        onChanged: (v) => setState(() => _qty = v),
                      ),
                      if (exceeds)
                        Text(
                          t('inventory.waste.quantityExceeds'),
                          key: const ValueKey('waste-exceeds'),
                          style: DashType.small.copyWith(
                            color: OnHand.negativeColor(context),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: DashSelectField<String>(
                  key: const ValueKey('waste-reason'),
                  label: t('inventory.waste.reason'),
                  value: _reason,
                  options: [
                    for (final r in wasteReasons)
                      DashOption(value: r, label: wasteReasonLabel(t, r)),
                  ],
                  onChanged: (v) => setState(() => _reason = v),
                ),
              ),
            ],
          ),
          DashFormField<String>(
            label: t('inventory.waste.note'),
            optionalText: '(${t('common.optional')})',
            builder: (context, _) => DashTextInput(
              key: const ValueKey('waste-note'),
              value: _note,
              semanticLabel: t('inventory.waste.note'),
              minLines: 2,
              maxLines: 4,
              onChanged: (v) => setState(() => _note = v),
            ),
          ),
        ],
      ),
      actions: [
        DashButton(
          key: const ValueKey('waste-cancel'),
          label: t('common.cancel'),
          variant: DashButtonVariant.outline,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        DashButton(
          key: const ValueKey('waste-submit'),
          label: t('inventory.waste.record'),
          loading: _busy,
          onPressed: valid ? () => _submit(quantity) : null,
        ),
      ],
    );
  }
}
