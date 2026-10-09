/// The New transfer dialog (INV-TRF-012…022, -026, -028; web
/// `transfer-dialog.tsx`): move stock from one active branch to another.
///
/// Opens with From = the picked branch and the rest blank. The picker lists
/// only what the source holds (on hand > 0); New transfer stays off until
/// both branches differ, an ingredient is picked and 0 < quantity ≤ on hand.
/// A recorded transfer invalidates inventory, toasts and closes.
library;

import 'package:collection/collection.dart';
import 'package:dashboard_api/dashboard_api.dart'
    show CreateTransferRequest, TransferLineInput;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../purchasing/purchasing_widgets.dart' show PoNumberInput;
import '../shared/inventory_data.dart';
import '../shared/inventory_labels.dart';
import '../shared/inventory_lib.dart';
import '../shared/on_hand.dart';

/// Opens the dialog with [sourceId] as From; true once a transfer was
/// recorded.
Future<bool?> showTransferDialog(
  BuildContext context, {
  required String? sourceId,
}) => showDashDialog<bool>(
  context,
  builder: (_) => TransferDialog(sourceId: sourceId),
);

class TransferDialog extends ConsumerStatefulWidget {
  const TransferDialog({required this.sourceId, super.key});

  final String? sourceId;

  @override
  ConsumerState<TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends ConsumerState<TransferDialog> {
  late String? _sourceId = widget.sourceId;
  String? _destId;
  String? _ingredientId;
  String _qty = '';
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
      await api.createTransfer(
        body: CreateTransferRequest(
          sourceBranchId: _sourceId!,
          destinationBranchId: _destId!,
          lines: [
            TransferLineInput(
              orgIngredientId: _ingredientId!,
              quantity: quantity,
            ),
          ],
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
    DashToast.success(context, t('inventory.transfers.created'));
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final branches = ref.watch(activeBranchesProvider) ?? const [];
    final sourceId = _sourceId;
    // The web's query is off until a source is picked.
    final stock = sourceId == null
        ? null
        : ref.watch(branchStockProvider(sourceId));
    final rows = stock?.value ?? const [];
    final held = [
      for (final s in rows)
        if (s.onHand > 0) s,
    ];
    final selected = rows.firstWhereOrNull(
      (s) => s.orgIngredientId == _ingredientId,
    );
    final sourceBranch = branches.firstWhereOrNull((b) => b.id == sourceId);
    final quantity = dashParseNumber(_qty);
    final sameBranch = sourceId != null && sourceId == _destId;
    final exceeds = exceedsOnHand(quantity, selected?.onHand);
    final valid =
        sourceId != null &&
        _destId != null &&
        !sameBranch &&
        _ingredientId != null &&
        quantity != null &&
        quantity > 0 &&
        !exceeds;
    final failed = stock?.failedFirst ?? false;
    final warn = DashType.small.copyWith(color: OnHand.negativeColor(context));

    List<DashOption<String>> branchOptions() => [
      for (final b in branches) DashOption(value: b.id, label: b.name),
    ];

    return DashSurface(
      title: t('inventory.transfers.createTitle'),
      description: t('inventory.transfers.title'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.md,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: Space.sm,
            children: [
              Expanded(
                child: DashFormField<String?>(
                  label: t('inventory.transfers.source'),
                  builder: (context, _) => DashSelect<String>(
                    key: const ValueKey('transfer-source'),
                    options: branchOptions(),
                    value: sourceId,
                    placeholder: '—',
                    semanticLabel: t('inventory.transfers.source'),
                    // The stock that branch would offer.
                    onOptionIntent: (id) => ref.warm(branchStockProvider(id)),
                    onChanged: (v) => setState(() {
                      _sourceId = v;
                      _ingredientId = null;
                    }),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: Space.md),
                child: DashIcon(
                  DashIcon.arrowForward(context),
                  size: IconSize.sm,
                  color: c.textMuted,
                ),
              ),
              Expanded(
                child: DashSelectField<String>(
                  key: const ValueKey('transfer-destination'),
                  label: t('inventory.transfers.destination'),
                  placeholder: '—',
                  value: _destId,
                  options: branchOptions(),
                  onChanged: (v) => setState(() => _destId = v),
                ),
              ),
            ],
          ),
          if (sameBranch)
            Text(
              t('inventory.transfers.sameBranch'),
              key: const ValueKey('transfer-same-branch'),
              style: warn,
            ),
          if (failed)
            _StockFailed(
              text: errorMessage(stock!.error, t),
              retrying: stock.isLoading,
              onRetry: () => ref.invalidate(branchStockProvider(sourceId!)),
            ),
          DashSelectField<String>(
            key: const ValueKey('transfer-ingredient'),
            label: t('inventory.transfers.ingredient'),
            placeholder: t('inventory.stock.pickIngredient'),
            searchable: true,
            searchPlaceholder: t('common.search'),
            enabled: sourceId != null,
            value: _ingredientId,
            emptyText: stock == null
                ? null
                : stock.awaitingFirst
                ? t('common.loading')
                : held.isEmpty && !failed
                ? t('inventory.transfers.nothingToSend')
                : null,
            description: selected == null || sourceBranch == null
                ? null
                : t(
                    'inventory.transfers.onHandHint',
                    args: {
                      'branch': sourceBranch.name,
                      'qty': f.fmtNumber(selected.onHand),
                      'unit': fmtUnit(selected.unit),
                    },
                  ),
            options: [
              for (final s in held)
                DashOption(
                  value: s.orgIngredientId,
                  label: s.ingredientName,
                  keywords: s.categoryName,
                  hint: qtyWithUnit(f, s.onHand, s.unit),
                ),
            ],
            onChanged: (v) => setState(() => _ingredientId = v),
          ),
          DashFormField<String>(
            label: t('inventory.transfers.quantity'),
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              spacing: Space.xs,
              children: [
                PoNumberInput(
                  key: const ValueKey('transfer-quantity'),
                  value: _qty,
                  semanticLabel: t('inventory.transfers.quantity'),
                  onChanged: (v) => setState(() => _qty = v),
                ),
                if (exceeds)
                  Text(
                    t('inventory.waste.quantityExceeds'),
                    key: const ValueKey('transfer-exceeds'),
                    style: warn,
                  ),
              ],
            ),
          ),
          DashFormField<String>(
            label: t('inventory.transfers.note'),
            optionalText: '(${t('common.optional')})',
            builder: (context, _) => DashTextInput(
              key: const ValueKey('transfer-note'),
              value: _note,
              semanticLabel: t('inventory.transfers.note'),
              minLines: 2,
              maxLines: 4,
              onChanged: (v) => setState(() => _note = v),
            ),
          ),
        ],
      ),
      actions: [
        DashButton(
          key: const ValueKey('transfer-cancel'),
          label: t('common.cancel'),
          variant: DashButtonVariant.outline,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        DashButton(
          key: const ValueKey('transfer-submit'),
          label: t('inventory.transfers.create'),
          loading: _busy,
          onPressed: valid ? () => _submit(quantity) : null,
        ),
      ],
    );
  }
}

/// INV-TRF-028 (divergence): the source's stock could not be read — the
/// server's words and Retry, never "nothing on hand".
class _StockFailed extends ConsumerWidget {
  const _StockFailed({
    required this.text,
    required this.retrying,
    required this.onRetry,
  });

  final String text;
  final bool retrying;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: Space.md,
        vertical: Space.xs,
      ),
      decoration: BoxDecoration(
        color: DashTone.danger.wash(c),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: Space.xs,
        children: [
          Text(text, style: DashType.small.copyWith(color: c.textPrimary)),
          DashButton(
            key: const ValueKey('transfer-stock-retry'),
            label: t('common.retry'),
            variant: DashButtonVariant.link,
            size: DashButtonSize.compact,
            loading: retrying,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}
