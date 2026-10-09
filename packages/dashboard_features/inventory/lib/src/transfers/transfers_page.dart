/// Transfers (`/inventory/transfers`, the INV-TRF rows; web
/// `src/features/inventory/transfers-page.tsx`): stock moved between the
/// org's branches, for the scoped branch (or rolled up with All branches),
/// filtered by direction.
///
/// No control is gated by capability (INV-TRF-025): the server refuses.
/// New transfer needs a picked branch and two active branches.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show StockTransfer, UpdateTransferRequest;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/inventory_data.dart';
import '../shared/inventory_export.dart';
import '../shared/inventory_labels.dart';
import 'transfer_dialog.dart';
import 'transfers_data.dart';

/// "Tarek" or "—" for a row without a name.
String _by(StockTransfer tr) =>
    tr.initiatedByName.isEmpty ? '—' : tr.initiatedByName;

class TransfersPage extends ConsumerStatefulWidget {
  const TransfersPage({super.key});

  @override
  ConsumerState<TransfersPage> createState() => _TransfersPageState();
}

class _TransfersPageState extends ConsumerState<TransfersPage> {
  /// The direction filter (null = "All transfers"); per visit, as the web.
  String? _dir;
  bool _exporting = false;

  /// INV-TRF-005: the whole list (same scope and direction), walked, as
  /// `Madar-Transfers-<date>.xlsx`.
  Future<void> _export(TransfersKey key) async {
    final t = ref.read(tProvider);
    final transport = ref.read(transportProvider);
    setState(() => _exporting = true);
    try {
      final rows = await fetchAllTransfers(transport, key);
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

  ExcelConfig _config(Translator t, List<StockTransfer> rows) {
    ExcelColumn<Object?> col(
      String header,
      Object? Function(StockTransfer tr) value,
      ExcelColumnType type,
      double width,
    ) => ExcelColumn<Object?>(
      header: header,
      accessor: (r) => value(r! as StockTransfer),
      type: type,
      width: width,
    );
    const text = ExcelColumnType.text;
    return ExcelConfig(
      filename: 'Madar-Transfers',
      logoUrl: inventoryExportLogo(ref),
      sheets: [
        ExcelSheet<Object?>(
          name: t('inventory.transfers.title'),
          title: t('inventory.transfers.title'),
          rows: rows,
          columns: [
            col(
              t('common.date'),
              (tr) => tr.initiatedAt,
              ExcelColumnType.dateTime,
              20,
            ),
            col(
              t('inventory.transfers.ingredient'),
              (tr) => tr.ingredientName,
              text,
              28,
            ),
            col(
              t('inventory.transfers.quantity'),
              (tr) => tr.quantity,
              ExcelColumnType.number,
              12,
            ),
            col(
              t('inventory.catalog.unit'),
              (tr) => fmtUnit(tr.unit),
              text,
              10,
            ),
            col(
              t('inventory.transfers.from'),
              (tr) => tr.sourceBranchName,
              text,
              22,
            ),
            col(
              t('inventory.transfers.to'),
              (tr) => tr.destinationBranchName,
              text,
              22,
            ),
            col(t('inventory.transfers.by'), _by, text, 18),
            col(t('inventory.transfers.note'), (tr) => tr.note ?? '', text, 30),
          ],
        ),
      ],
    );
  }

  /// INV-TRF-009: confirm, DELETE, invalidate inventory, "Done".
  Future<void> _reverse(StockTransfer tr) async {
    final t = ref.read(tProvider);
    final ok = await showDashConfirm(
      context,
      title: t(
        'inventory.transfers.reverseConfirmTitle',
        args: {'name': tr.ingredientName},
      ),
      description: t('inventory.transfers.reverseConsequence'),
      confirmLabel: t('inventory.transfers.reverseTitle'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    final api = ref.read(apiProvider).inventory;
    // Captured now: the list refreshes even if the page closes mid-call.
    final bus = ref.read(realtimeBusProvider);
    try {
      await api.deleteTransfer(id: tr.id);
    } on Object catch (e) {
      if (mounted) DashToast.error(context, errorMessage(e, t));
      return;
    }
    bus.invalidate(inventoryPathFamilies);
    if (mounted) DashToast.success(context, t('common.done'));
  }

  /// Runs [action] once the menu has closed, so the dialog it opens keeps
  /// the focus.
  void _afterMenu(VoidCallback action) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) action();
      });

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final scope = ref.watch(currentScopeProvider);
    final branchId = scope.branchId;
    final key = scope.transfersKey(_dir);
    final list = ref.watch(transfersProvider(key));
    final rows = list.value ?? const <StockTransfer>[];
    // Read only with an org (INV-ALL-027); inactive ones never count.
    final active = scope.orgId == null
        ? const []
        : ref.watch(activeBranchesProvider) ?? const [];

    return DashPageScaffold(
      title: t('inventory.transfers.title'),
      actions: [
        DashExportButton(
          key: const ValueKey('transfers-export'),
          loading: _exporting,
          enabled: rows.isNotEmpty,
          onExport: () => _export(key),
        ),
        if (branchId != null)
          DashButton(
            key: const ValueKey('transfers-new'),
            label: t('inventory.transfers.create'),
            icon: 'plus-circle',
            // The dialog's read: the picked branch's stock.
            onIntent: () => ref.warm(branchStockProvider(branchId)),
            onPressed: active.length < 2
                ? null
                : () => showTransferDialog(context, sourceId: branchId),
          ),
      ],
      filters: DashSegmentedControl<String?>(
        key: const ValueKey('transfers-direction'),
        value: _dir,
        semanticLabel: t('inventory.transfers.direction'),
        options: [
          for (final d in transferDirections)
            DashOption(value: d, label: t('inventory.transfers.${d ?? 'all'}')),
        ],
        onIntent: (d) => ref.warm(transfersProvider(scope.transfersKey(d))),
        onChanged: (d) => setState(() => _dir = d),
      ),
      body: TransfersTable(
        rows: rows,
        loading: list.awaitingFirst,
        // Kept while Retry runs (no false "No transfers found" in between).
        errorText: list.failedFirst ? errorMessage(list.error, t) : null,
        onRetry: () => ref.invalidate(transfersProvider(key)),
        onEditNote: (tr) => _afterMenu(
          () => showDashDialog<void>(
            context,
            builder: (_) => TransferNoteDialog(transfer: tr, listKey: key),
          ),
        ),
        onReverse: (tr) => _afterMenu(() => _reverse(tr)),
      ),
    );
  }
}

/// The list (INV-TRF-006/007/010/011/024): Date, Ingredient, Quantity,
/// Direction, By; 10 a page; no search, no row click; ⋯ Edit note /
/// Reverse transfer. Below 760 each row is a card led by the ingredient.
class TransfersTable extends ConsumerWidget {
  const TransfersTable({
    required this.rows,
    required this.loading,
    required this.errorText,
    required this.onRetry,
    required this.onEditNote,
    required this.onReverse,
    super.key,
  });

  final List<StockTransfer> rows;
  final bool loading;
  final String? errorText;
  final VoidCallback onRetry;
  final ValueChanged<StockTransfer> onEditNote;
  final ValueChanged<StockTransfer> onReverse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    Widget one(String s, {TextStyle? style}) => MadarClippedText(
      s,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
    return DashDataTable<StockTransfer>(
      key: const ValueKey('transfers-table'),
      rows: rows,
      rowKey: (tr) => tr.id,
      loading: loading,
      errorMessage: errorText,
      onRetry: onRetry,
      empty: DashEmptyState(
        icon: 'arrow-left-right',
        title: t('inventory.transfers.noTransfers'),
      ),
      columns: [
        DashColumn(
          id: 'initiated_at',
          label: t('common.date'),
          cell: (context, tr) => one(f.fmtDateTime(tr.initiatedAt)),
          numeric: true,
          align: DashAlign.start,
          // "30 Sept, 12:15 PM" uncut, as the web's nowrap cell.
          width: Space.xxl * 6,
        ),
        DashColumn(
          id: 'ingredient_name',
          label: t('inventory.transfers.ingredient'),
          cell: (context, tr) => one(
            tr.ingredientName,
            style: DashType.bodyMedium.copyWith(color: c.textPrimary),
          ),
          phone: DashPhoneRole.title,
          // The web's cells never wrap; a narrow table scrolls instead.
          minWidth: Space.xxl * 6,
        ),
        DashColumn(
          id: 'quantity',
          label: t('inventory.transfers.quantity'),
          cell: (context, tr) => Text(qtyWithUnit(f, tr.quantity, tr.unit)),
          numeric: true,
          width: Space.xxl * 3 + Space.sm,
        ),
        DashColumn(
          id: 'route',
          label: t('inventory.transfers.direction'),
          // Names wrap rather than cut, as the web's flex cell.
          cell: (context, tr) => Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: Space.xs,
            children: [
              Text(tr.sourceBranchName),
              DashIcon(
                DashIcon.arrowForward(context),
                size: IconSize.xs,
                color: c.textMuted,
              ),
              Text(tr.destinationBranchName),
            ],
          ),
          minWidth: Space.xxl * 6,
        ),
        DashColumn(
          id: 'initiated_by_name',
          label: t('inventory.transfers.by'),
          cell: (context, tr) => one(_by(tr)),
          minWidth: Space.xxl * 4 + Space.lg,
        ),
      ],
      rowActions: (context, tr) => DashMenu(
        key: ValueKey('transfer-menu-${tr.id}'),
        items: [
          DashMenuItem(
            label: t('inventory.transfers.editNote'),
            onSelected: () => onEditNote(tr),
          ),
          DashMenuItem(
            label: t('inventory.transfers.reverseTitle'),
            icon: 'rotate-ccw',
            destructive: true,
            onSelected: () => onReverse(tr),
          ),
        ],
        builder: (context, ctl) => DashIconButton(
          icon: 'more-horizontal',
          semanticLabel: t('common.moreActions'),
          onPressed: ctl.toggle,
        ),
      ),
    );
  }
}

/// Edit note (INV-TRF-008/027): the row's note as the draft (re-taken from a
/// background refresh until the person types); Save sends it trimmed (blank
/// → null), invalidates inventory, toasts and closes.
class TransferNoteDialog extends ConsumerStatefulWidget {
  const TransferNoteDialog({
    required this.transfer,
    required this.listKey,
    super.key,
  });

  final StockTransfer transfer;

  /// The list the row came from.
  final TransfersKey listKey;

  @override
  ConsumerState<TransferNoteDialog> createState() => _TransferNoteDialogState();
}

class _TransferNoteDialogState extends ConsumerState<TransferNoteDialog> {
  late String _draft = widget.transfer.note ?? '';
  bool _edited = false;
  bool _busy = false;

  Future<void> _save() async {
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider).inventory;
    final bus = ref.read(realtimeBusProvider);
    final note = _draft.trim();
    setState(() => _busy = true);
    try {
      await api.updateTransfer(
        id: widget.transfer.id,
        body: UpdateTransferRequest(
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
    DashToast.success(context, t('common.savedChanges'));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    ref.listen(transfersProvider(widget.listKey), (_, next) {
      final id = widget.transfer.id;
      final row = next.value?.where((r) => r.id == id).firstOrNull;
      if (!_edited && row != null) setState(() => _draft = row.note ?? '');
    });
    return DashSurface(
      title: t('inventory.transfers.editNote'),
      body: DashFormField<String>(
        label: t('inventory.transfers.note'),
        builder: (context, _) => DashTextInput(
          key: const ValueKey('transfer-note-draft'),
          value: _draft,
          semanticLabel: t('inventory.transfers.note'),
          minLines: 3,
          maxLines: 6,
          onChanged: (v) => setState(() {
            _draft = v;
            _edited = true;
          }),
        ),
      ),
      actions: [
        DashButton(
          key: const ValueKey('transfer-note-cancel'),
          label: t('common.cancel'),
          variant: DashButtonVariant.outline,
          onPressed: () => Navigator.of(context).pop(),
        ),
        DashButton(
          key: const ValueKey('transfer-note-save'),
          label: t('common.save'),
          loading: _busy,
          onPressed: _save,
        ),
      ],
    );
  }
}
