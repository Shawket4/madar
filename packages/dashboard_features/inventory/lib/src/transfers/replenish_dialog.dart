/// The replenish dialog (INV-TRF-038…040; web `replenish-dialog.tsx` at
/// af50aa63): what a selling branch is low on, and what this warehouse can
/// send it (the backend's `madar_inventory::replenish` rule). The ticked
/// lines go to the transfer dialog as a draft.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show Branch, ReplenishmentRow, TransferLineInput;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/inventory_data.dart' show branchStockProvider;
import '../shared/inventory_labels.dart';
import '../shared/inventory_lib.dart' show jsNumberString;
import '../shared/number_input.dart';
import 'transfers_data.dart';

/// The branch picked and the lines to send it.
typedef ReplenishPick = ({String dest, List<TransferLineInput> lines});

Future<ReplenishPick?> showReplenishDialog(
  BuildContext context, {
  required Branch warehouse,
  required List<({String id, String name})> branches,
}) => showDashDialog<ReplenishPick>(
  context,
  width: DashMetrics.dialog * 4 / 3,
  builder: (_) => ReplenishDialog(warehouse: warehouse, branches: branches),
);

class ReplenishDialog extends ConsumerStatefulWidget {
  const ReplenishDialog({
    required this.warehouse,
    required this.branches,
    super.key,
  });

  final Branch warehouse;

  /// The selling branches this warehouse can fill.
  final List<({String id, String name})> branches;

  @override
  ConsumerState<ReplenishDialog> createState() => _ReplenishDialogState();
}

class _ReplenishDialogState extends ConsumerState<ReplenishDialog> {
  late String? _branchId = widget.branches.length == 1
      ? widget.branches.single.id
      : null;
  Map<String, String> _qty = {};
  Map<String, bool> _on = {};
  String? _seededFor;
  List<ReplenishmentRow>? _seededRows;
  bool _edited = false;

  ReplenishKey _key(String branchId) =>
      (warehouseId: widget.warehouse.id, branchId: branchId);

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final branchId = _branchId;
    final q = branchId == null
        ? null
        : ref.watch(replenishmentProvider(_key(branchId)));
    final rows = q?.value;
    // Seeded per branch picked, and again from a newer answer until the
    // first edit: after it, a background refetch keeps the edits.
    if (rows != null &&
        (_seededFor != branchId ||
            (!_edited && !identical(rows, _seededRows)))) {
      if (_seededFor != branchId) _edited = false;
      _seededFor = branchId;
      _seededRows = rows;
      _qty = {
        for (final r in rows)
          r.orgIngredientId: r.suggested > 0 ? jsNumberString(r.suggested) : '',
      };
      _on = {for (final r in rows) r.orgIngredientId: r.suggested > 0};
    }
    final picked = [
      for (final r in rows ?? const <ReplenishmentRow>[])
        if ((_on[r.orgIngredientId] ?? false) &&
            (dashParseNumber(_qty[r.orgIngredientId] ?? '') ?? 0) > 0)
          TransferLineInput(
            orgIngredientId: r.orgIngredientId,
            quantity: dashParseNumber(_qty[r.orgIngredientId]!)!,
          ),
    ];

    final Widget state;
    if (q == null) {
      state = const SizedBox.shrink();
    } else if (q.awaitingFirst) {
      state = Column(
        key: const ValueKey('replenish-loading'),
        spacing: Space.sm,
        children: [
          for (var i = 0; i < 3; i++)
            const DashSkeleton(height: Space.xxl + Space.sm),
        ],
      );
    } else if (q.failedFirst) {
      state = DashErrorState(
        key: const ValueKey('replenish-error'),
        message: errorMessage(q.error, t),
        retrying: q.isLoading,
        onRetry: () => ref.invalidate(replenishmentProvider(_key(branchId!))),
      );
    } else if (rows!.isEmpty) {
      state = DashEmptyState(
        key: const ValueKey('replenish-empty'),
        icon: 'package',
        title: t('inventory.transfers.nothingLow'),
        description: t('inventory.transfers.nothingLowHint'),
      );
    } else {
      state = _Table(
        rows: rows,
        qty: _qty,
        on: _on,
        onTick: (id, v) => setState(() {
          _edited = true;
          _on[id] = v;
        }),
        onQty: (id, v) => setState(() {
          _edited = true;
          _qty[id] = v;
        }),
      );
    }

    return DashSurface(
      key: const ValueKey('replenish-dialog'),
      title: t('inventory.transfers.replenishTitle'),
      description: t(
        'inventory.transfers.replenishHint',
        args: {'warehouse': widget.warehouse.name},
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.md,
        children: [
          DashFormField<String>(
            label: t('inventory.transfers.to'),
            builder: (context, _) => DashSelect<String>(
              key: const ValueKey('replenish-branch'),
              options: [
                for (final b in widget.branches)
                  DashOption(value: b.id, label: b.name),
              ],
              value: branchId,
              placeholder: t('inventory.transfers.pickBranch'),
              semanticLabel: t('inventory.transfers.to'),
              onOptionIntent: (id) => ref.warm(replenishmentProvider(_key(id))),
              onChanged: (v) => setState(() => _branchId = v),
            ),
          ),
          state,
        ],
      ),
      actions: [
        DashButton(
          key: const ValueKey('replenish-cancel'),
          label: t('common.cancel'),
          variant: DashButtonVariant.outline,
          onPressed: () => Navigator.of(context).pop(),
        ),
        DashButton(
          key: const ValueKey('replenish-review'),
          label: t('inventory.transfers.reviewTransfer', count: picked.length),
          // The transfer dialog's reads: the warehouse's stock, what you
          // hold at the branch.
          onIntent: picked.isEmpty
              ? null
              : () => ref
                  ..warm(branchStockProvider(widget.warehouse.id))
                  ..warm(authzAtProvider(branchId!)),
          onPressed: picked.isEmpty
              ? null
              : () =>
                    Navigator.of(context).pop((dest: branchId!, lines: picked)),
        ),
      ],
    );
  }
}

/// The rows (INV-TRF-039): tick, Ingredient + level, At branch, Coming, Can
/// send, Send. Narrower than the columns need, it scrolls sideways.
class _Table extends ConsumerWidget {
  const _Table({
    required this.rows,
    required this.qty,
    required this.on,
    required this.onTick,
    required this.onQty,
  });

  final List<ReplenishmentRow> rows;
  final Map<String, String> qty;
  final Map<String, bool> on;
  final void Function(String id, bool v) onTick;
  final void Function(String id, String v) onQty;

  static const double _num = Space.xxl * 2 + Space.lg;
  static const double _min = Space.xxl * 15;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final head = DashType.small.copyWith(
      color: c.textMuted,
      fontWeight: FontWeight.w500,
    );
    final body = DashType.body.copyWith(
      color: c.textPrimary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final border = BorderSide(color: c.border);
    Widget cell(String s, {TextStyle? style, double width = _num}) => SizedBox(
      width: width,
      child: Text(s, textAlign: TextAlign.end, style: style ?? body),
    );

    Widget table(double width) => SizedBox(
      width: width,
      child: Column(
        key: const ValueKey('replenish-table'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            decoration: BoxDecoration(border: Border(bottom: border)),
            child: Row(
              spacing: Space.sm,
              children: [
                const SizedBox(width: DashMetrics.target),
                Expanded(
                  child: Text(t('inventory.transfers.ingredient'), style: head),
                ),
                cell(t('inventory.transfers.branchOnHand'), style: head),
                cell(t('inventory.transfers.coming'), style: head),
                cell(t('inventory.transfers.inWarehouse'), style: head),
                cell(
                  t('inventory.transfers.send'),
                  style: head,
                  width: _num + Space.lg,
                ),
              ],
            ),
          ),
          for (final (i, r) in rows.indexed)
            Container(
              key: ValueKey('replenish-row-${r.orgIngredientId}'),
              padding: const EdgeInsets.symmetric(vertical: Space.xs),
              decoration: BoxDecoration(
                border: i == rows.length - 1 ? null : Border(bottom: border),
              ),
              child: Row(
                spacing: Space.sm,
                children: [
                  DashCheckbox(
                    key: ValueKey('replenish-tick-${r.orgIngredientId}'),
                    value: on[r.orgIngredientId] ?? false,
                    semanticLabel: r.ingredientName,
                    onChanged: (v) => onTick(r.orgIngredientId, v),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.ingredientName,
                          style: body.copyWith(fontWeight: FontWeight.w500),
                        ),
                        Text(
                          t(
                            'inventory.transfers.parRange',
                            args: {
                              'min': f.fmtNumber(r.parMin),
                              'max': f.fmtNumber(r.parMax ?? r.parMin),
                            },
                          ),
                          style: DashType.small.copyWith(color: c.textMuted),
                        ),
                      ],
                    ),
                  ),
                  cell(qtyWithUnit(f, r.onHand, r.unit)),
                  cell(
                    f.fmtNumber(r.inTransit + r.openInbound),
                    style: body.copyWith(color: c.textMuted),
                  ),
                  cell(f.fmtNumber(r.available)),
                  SizedBox(
                    width: _num + Space.lg,
                    child: PoNumberInput(
                      key: ValueKey('replenish-qty-${r.orgIngredientId}'),
                      value: qty[r.orgIngredientId] ?? '',
                      semanticLabel: t('inventory.transfers.send'),
                      onChanged: (v) => onQty(r.orgIngredientId, v),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, box) => box.maxWidth >= _min
          ? table(box.maxWidth)
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: table(_min),
            ),
    );
  }
}
