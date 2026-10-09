/// The transfer drawer (INV-TRF-013…024; web `transfer-drawer.tsx` at
/// af50aa63): one transfer's lines, who did what, and the steps this person
/// may take (the step table, at each side's location), with the receive and
/// the decline / cancel dialogs.
library;

import 'package:collection/collection.dart';
import 'package:dashboard_api/dashboard_api.dart'
    show
        BranchKind,
        CloseTransferRequest,
        ReceiveTransferLine,
        ReceiveTransferRequest,
        StockTransfer,
        TransferStamp;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/inventory_data.dart';
import '../shared/inventory_labels.dart';
import '../shared/inventory_lib.dart' show jsNumberString;
import '../shared/number_input.dart';
import 'transfer_dialog.dart';
import 'transfers_data.dart';
import 'transfers_page.dart' show TransferRoute, transferBranches;

/// Opens the drawer on [transfer]; [listKey] is the list it came from (a
/// newer copy of the transfer there replaces the drawer's).
Future<void> showTransferDrawer(
  BuildContext context, {
  required StockTransfer transfer,
  required TransfersKey listKey,
}) => showDashSidePanel<void>(
  context,
  builder: (_) => TransferDrawer(transfer: transfer, listKey: listKey),
);

/// The drawer's reads, warmed on a row's intent: what each side holds.
void warmDrawer(WidgetRef ref, StockTransfer tr) => ref
  ..warm(authzAtProvider(tr.sourceBranchId))
  ..warm(authzAtProvider(tr.destinationBranchId));

/// The colour of a short (red) or over (amber) figure, pulled toward the
/// text like the web's 50% colour-mix.
Color _diffColor(MadarColors c, double diff) =>
    Color.lerp(diff < 0 ? c.danger : c.warning, c.textPrimary, 0.5)!;

class TransferDrawer extends ConsumerStatefulWidget {
  const TransferDrawer({
    required this.transfer,
    required this.listKey,
    super.key,
  });

  final StockTransfer transfer;
  final TransfersKey listKey;

  @override
  ConsumerState<TransferDrawer> createState() => _TransferDrawerState();
}

class _TransferDrawerState extends ConsumerState<TransferDrawer> {
  /// The transfer shown: the opened row, then each step's answer, then any
  /// newer copy the list brings (INV-TRF-009).
  late StockTransfer _tr = widget.transfer;
  bool _busy = false;

  void _show(StockTransfer? next) {
    if (next != null && mounted) setState(() => _tr = next);
  }

  /// A step: run it, invalidate inventory, toast, show its answer; a
  /// failure toasts and (when stale) refreshes inventory too (INV-TRF-024).
  Future<void> _act(Future<StockTransfer> Function() step, String done) async {
    final t = ref.read(tProvider);
    // Captured now: inventory refreshes even if the drawer closes mid-call.
    final bus = ref.read(realtimeBusProvider);
    setState(() => _busy = true);
    try {
      final next = await step();
      bus.invalidate(inventoryPathFamilies);
      if (!mounted) return;
      DashToast.success(context, done);
      _show(next);
    } on Object catch (e) {
      if (isStaleTransferRefusal(e)) bus.invalidate(inventoryPathFamilies);
      if (mounted) DashToast.error(context, errorMessage(e, t));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// INV-TRF-019: confirm, then dispatch.
  Future<void> _dispatch(StockTransfer tr) async {
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider).inventory;
    final ok = await showDashConfirm(
      context,
      title: t(
        'inventory.transfers.dispatchConfirm',
        args: {'ref': tr.reference},
      ),
      description: t(
        'inventory.transfers.dispatchConsequence',
        args: {'from': tr.sourceBranchName},
      ),
      confirmLabel: t('inventory.transfers.sendNow'),
    );
    if (!ok || !mounted) return;
    await _act(
      () => api.dispatchTransfer(id: tr.id),
      t('inventory.transfers.dispatchedToast'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    ref.listen(transfersProvider(widget.listKey), (_, next) {
      if (next.isLoading) return;
      _show(next.value?.firstWhereOrNull((x) => x.id == _tr.id));
    });
    final tr = _tr;
    final status = tr.status.value;
    final atSource =
        ref.watch(authzAtProvider(tr.sourceBranchId)).value ?? Authz.none;
    final atDest =
        ref.watch(authzAtProvider(tr.destinationBranchId)).value ?? Authz.none;
    final mine = {for (final b in transferBranches(ref)) b.id};
    final actions = transferActions(
      tr,
      mine,
      (cap, at) => (at == tr.sourceBranchId ? atSource : atDest).can(cap),
    );
    final received = status == 'received';
    final value = received ? transitValue(tr) : 0.0;
    final busy = _busy;
    final muted = DashType.small.copyWith(color: c.textMuted);

    DashButton step(
      String key,
      String label,
      String icon,
      VoidCallback onPressed, {
      DashButtonVariant variant = DashButtonVariant.primary,
      bool loading = false,
      VoidCallback? onIntent,
    }) => DashButton(
      key: ValueKey('transfer-step-$key'),
      label: label,
      icon: icon,
      variant: variant,
      loading: loading,
      onPressed: busy ? null : onPressed,
      onIntent: onIntent,
    );

    Widget stamp(String key, String label, TransferStamp? s) => s == null
        ? const SizedBox.shrink()
        : Row(
            key: ValueKey('transfer-stamp-$key'),
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.md,
            children: [
              Text(label, style: DashType.body.copyWith(color: c.textMuted)),
              Expanded(
                child: Text(
                  // Isolated: a Latin name never pulls the Arabic date
                  // into its run.
                  '\u2068${s.byName}\u2069 · ${f.fmtDateTime(s.at)}',
                  textAlign: TextAlign.end,
                  style: DashType.body.copyWith(color: c.textPrimary),
                ),
              ),
            ],
          );

    return DashSurface(
      key: const ValueKey('transfer-drawer'),
      title: tr.reference,
      headerTrailing: Padding(
        padding: const EdgeInsets.only(top: Space.sm),
        child: DashStatusPill(
          label: transferStatusLabel(t, status),
          tone: transferTone(status),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.lg,
        children: [
          TransferRoute(
            key: const ValueKey('transfer-drawer-route'),
            source: tr.sourceBranchName,
            destination: tr.destinationBranchName,
            sourceWarehouse: tr.sourceKind == BranchKind.warehouse,
            destinationWarehouse: tr.destinationKind == BranchKind.warehouse,
            style: DashType.body.copyWith(color: c.textMuted),
          ),
          _Lines(tr: tr),
          if (received && value.abs() > 0.5)
            Container(
              key: const ValueKey('transfer-transit-value'),
              padding: const EdgeInsets.all(Space.md),
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Text(
                value < 0
                    ? t(
                        'inventory.transfers.transitLoss',
                        args: {'value': f.fmtMoney(-value)},
                      )
                    : t(
                        'inventory.transfers.transitGain',
                        args: {'value': f.fmtMoney(value)},
                      ),
                style: DashType.body.copyWith(color: c.textPrimary),
              ),
            ),
          if (tr.note case final note? when note.isNotEmpty)
            Column(
              key: const ValueKey('transfer-note'),
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.xs,
              children: [
                Text(
                  t('inventory.transfers.note'),
                  style: muted.copyWith(fontWeight: FontWeight.w500),
                ),
                Text(note, style: DashType.body.copyWith(color: c.textPrimary)),
              ],
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.xs,
            children: [
              if (tr.requested != null)
                stamp(
                  'requested',
                  t('inventory.transfers.requestedBy'),
                  tr.requested,
                )
              else
                stamp(
                  'created',
                  t('inventory.transfers.createdBy'),
                  tr.created,
                ),
              stamp(
                'sent',
                t('inventory.transfers.dispatchedBy'),
                tr.dispatched,
              ),
              stamp(
                'received',
                t('inventory.transfers.receivedBy'),
                tr.received,
              ),
              stamp(
                'cancelled',
                t('inventory.transfers.cancelledBy'),
                tr.cancelled,
              ),
            ],
          ),
        ],
      ),
      actions: [
        if (actions.contains(TransferAction.cancel))
          step(
            'cancel',
            status == 'requested'
                ? t('inventory.transfers.withdraw')
                : t('inventory.transfers.cancel'),
            'ban',
            () async => _show(await showCloseTransferDialog(context, tr)),
            variant: DashButtonVariant.ghost,
          ),
        if (actions.contains(TransferAction.decline))
          step(
            'decline',
            t('inventory.transfers.decline'),
            'x',
            () async => _show(
              await showCloseTransferDialog(context, tr, decline: true),
            ),
            variant: DashButtonVariant.outline,
          ),
        if (actions.contains(TransferAction.edit))
          step(
            'edit',
            t('common.edit'),
            'pencil',
            () async => _show(
              await showTransferDialog(
                context,
                mode: TransferDialogMode.edit,
                transfer: tr,
              ),
            ),
            variant: DashButtonVariant.outline,
            // Editing a request lists the catalogue; a send, the source's
            // stock.
            onIntent: () {
              if (status != 'requested') {
                ref.warm(branchStockProvider(tr.sourceBranchId));
              } else if (ref.read(orgIdProvider) case final orgId?) {
                ref.warm(inventoryCatalogProvider(orgId));
              }
            },
          ),
        if (actions.contains(TransferAction.accept))
          step(
            'accept',
            t('inventory.transfers.accept'),
            'check',
            () async => _show(
              await showTransferDialog(
                context,
                mode: TransferDialogMode.accept,
                transfer: tr,
              ),
            ),
            onIntent: () => ref.warm(branchStockProvider(tr.sourceBranchId)),
          ),
        if (actions.contains(TransferAction.dispatch))
          DashButton(
            key: const ValueKey('transfer-step-dispatch'),
            label: t('inventory.transfers.sendNow'),
            icon: 'send',
            loading: busy,
            onPressed: () => _dispatch(tr),
          ),
        if (actions.contains(TransferAction.receive))
          step(
            'receive',
            t('inventory.transfers.receive'),
            'package-check',
            () async => _show(await showReceiveTransferDialog(context, tr)),
          ),
      ],
    );
  }
}

/// The lines table (INV-TRF-014): Ingredient (+ the line's note), Asked or
/// Sent, and once received what arrived with the difference.
class _Lines extends ConsumerWidget {
  const _Lines({required this.tr});

  final StockTransfer tr;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final received = tr.status.value == 'received';
    final head = DashType.small.copyWith(
      color: c.textMuted,
      fontWeight: FontWeight.w500,
    );
    final body = DashType.body.copyWith(color: c.textPrimary);
    const qtyWidth = Space.xxl * 3;
    Widget num(String s, {TextStyle? style}) => SizedBox(
      width: qtyWidth,
      child: Text(
        s,
        textAlign: TextAlign.end,
        style: (style ?? body).copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
    final border = BorderSide(color: c.border);
    return Column(
      key: const ValueKey('transfer-lines'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: Space.sm),
          decoration: BoxDecoration(border: Border(bottom: border)),
          child: Row(
            spacing: Space.sm,
            children: [
              Expanded(
                child: Text(t('inventory.transfers.ingredient'), style: head),
              ),
              num(
                tr.status.value == 'requested'
                    ? t('inventory.transfers.asked')
                    : t('inventory.transfers.sent'),
                style: head,
              ),
              if (received) num(t('inventory.transfers.received'), style: head),
            ],
          ),
        ),
        for (final (i, l) in tr.lines.indexed)
          Container(
            key: ValueKey('transfer-line-${l.id}'),
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            decoration: BoxDecoration(
              border: i == tr.lines.length - 1 ? null : Border(bottom: border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.sm,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.ingredientName,
                        style: body.copyWith(fontWeight: FontWeight.w500),
                      ),
                      if (l.note case final note? when note.isNotEmpty)
                        Text(
                          note,
                          style: DashType.small.copyWith(color: c.textMuted),
                        ),
                    ],
                  ),
                ),
                num(qtyWithUnit(f, l.qtySent, l.unit)),
                if (received)
                  SizedBox(
                    width: qtyWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          qtyWithUnit(f, l.qtyReceived ?? 0, l.unit),
                          textAlign: TextAlign.end,
                          style: body,
                        ),
                        if (l.qtyReceived case final got?
                            when (got - l.qtySent).abs() > 1e-9)
                          Text(
                            '${got - l.qtySent > 0 ? '+' : ''}'
                            '${f.fmtNumber(got - l.qtySent)}',
                            key: ValueKey('transfer-line-diff-${l.id}'),
                            style: DashType.small.copyWith(
                              color: _diffColor(c, got - l.qtySent),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

// ── Receive ─────────────────────────────────────────────────────────────

/// Opens the receive dialog; the received transfer, or null.
Future<StockTransfer?> showReceiveTransferDialog(
  BuildContext context,
  StockTransfer tr,
) => showDashDialog<StockTransfer>(
  context,
  builder: (_) => ReceiveTransferDialog(transfer: tr),
);

/// What arrived, line by line, prefilled with what was sent (INV-TRF-021/022).
class ReceiveTransferDialog extends ConsumerStatefulWidget {
  const ReceiveTransferDialog({required this.transfer, super.key});

  final StockTransfer transfer;

  @override
  ConsumerState<ReceiveTransferDialog> createState() =>
      _ReceiveTransferDialogState();
}

class _ReceiveTransferDialogState extends ConsumerState<ReceiveTransferDialog> {
  late final Map<String, String> _qty = {
    for (final l in widget.transfer.lines) l.id: jsNumberString(l.qtySent),
  };
  final Map<String, String> _notes = {};
  bool _busy = false;

  Future<void> _submit(List<ReceiveTransferLine> lines) async {
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider).inventory;
    final bus = ref.read(realtimeBusProvider);
    setState(() => _busy = true);
    try {
      final next = await api.receiveTransfer(
        id: widget.transfer.id,
        body: ReceiveTransferRequest(lines: lines),
      );
      bus.invalidate(inventoryPathFamilies);
      if (!mounted) return;
      DashToast.success(context, t('inventory.transfers.receivedToast'));
      Navigator.of(context).pop(next);
    } on Object catch (e) {
      if (isStaleTransferRefusal(e)) bus.invalidate(inventoryPathFamilies);
      if (!mounted) return;
      setState(() => _busy = false);
      DashToast.error(context, errorMessage(e, t));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final tr = widget.transfer;
    final rows = [
      for (final l in tr.lines)
        () {
          final got = double.tryParse((_qty[l.id] ?? '').trim());
          // The server's rule (`check_receive_line`), in thousandths.
          final check = got == null || !got.isFinite
              ? null
              : checkReceiveLine(l.qtySent, got, _notes[l.id]);
          final ok = check != null && check.refused != 'negative';
          final needsNote = ok && check.refused == 'over_needs_note';
          final over = needsNote || check?.arrival == 'over';
          final short = check?.arrival == 'short';
          return (
            l: l,
            got: got,
            ok: ok,
            over: over,
            short: short,
            needsNote: needsNote,
          );
        }(),
    ];
    final valid = rows.every((r) => r.ok && !r.needsNote);
    final shortColor = _diffColor(c, -1);
    return DashSurface(
      key: const ValueKey('transfer-receive'),
      title: t('inventory.transfers.receiveTitle', args: {'ref': tr.reference}),
      description: t('inventory.transfers.receiveHint'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.md,
        children: [
          for (final r in rows)
            Container(
              key: ValueKey('receive-line-${r.l.id}'),
              padding: const EdgeInsets.all(Space.md),
              decoration: BoxDecoration(
                border: Border.all(color: c.border),
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.sm,
                children: [
                  Row(
                    spacing: Space.md,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MadarClippedText(
                              r.l.ingredientName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DashType.bodyMedium.copyWith(
                                color: c.textPrimary,
                              ),
                            ),
                            Text(
                              t(
                                'inventory.transfers.sentQty',
                                args: {
                                  'qty': qtyWithUnit(f, r.l.qtySent, r.l.unit),
                                },
                              ),
                              style: DashType.small.copyWith(
                                color: c.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: Space.xxl * 3 + Space.lg,
                        child: PoNumberInput(
                          key: ValueKey('receive-qty-${r.l.id}'),
                          value: _qty[r.l.id] ?? '',
                          semanticLabel: t('inventory.transfers.received'),
                          onChanged: (v) => setState(() => _qty[r.l.id] = v),
                        ),
                      ),
                    ],
                  ),
                  if (r.short)
                    Text(
                      t(
                        'inventory.transfers.shortBy',
                        args: {'qty': f.fmtNumber(r.l.qtySent - r.got!)},
                      ),
                      key: ValueKey('receive-short-${r.l.id}'),
                      style: DashType.small.copyWith(color: shortColor),
                    ),
                  if (r.over || r.short)
                    DashTextInput(
                      key: ValueKey('receive-note-${r.l.id}'),
                      value: _notes[r.l.id] ?? '',
                      placeholder: r.over
                          ? t('inventory.transfers.overNote')
                          : t('inventory.transfers.shortNote'),
                      semanticLabel: r.over
                          ? t('inventory.transfers.overNote')
                          : t('inventory.transfers.shortNote'),
                      invalid: r.needsNote,
                      onChanged: (v) => setState(() => _notes[r.l.id] = v),
                    ),
                ],
              ),
            ),
        ],
      ),
      actions: [
        DashButton(
          key: const ValueKey('receive-cancel'),
          label: t('common.cancel'),
          variant: DashButtonVariant.outline,
          onPressed: () => Navigator.of(context).pop(),
        ),
        DashButton(
          key: const ValueKey('receive-submit'),
          label: t('inventory.transfers.receive'),
          loading: _busy,
          onPressed: !valid
              ? null
              : () => _submit([
                  for (final r in rows)
                    ReceiveTransferLine(
                      lineId: r.l.id,
                      qtyReceived: r.got!,
                      note: (_notes[r.l.id] ?? '').trim().isEmpty
                          ? null
                          : _notes[r.l.id]!.trim(),
                      explicitNulls: (_notes[r.l.id] ?? '').trim().isEmpty
                          ? const {'note'}
                          : const {},
                    ),
                ]),
        ),
      ],
    );
  }
}

// ── Decline / cancel / withdraw ─────────────────────────────────────────

/// Opens the decline (reason required) or cancel/withdraw (reason
/// optional) dialog; the closed transfer, or null.
Future<StockTransfer?> showCloseTransferDialog(
  BuildContext context,
  StockTransfer tr, {
  bool decline = false,
}) => showDashDialog<StockTransfer>(
  context,
  builder: (_) => CloseTransferDialog(transfer: tr, decline: decline),
);

/// INV-TRF-023: a reason, then decline or cancel.
class CloseTransferDialog extends ConsumerStatefulWidget {
  const CloseTransferDialog({
    required this.transfer,
    required this.decline,
    super.key,
  });

  final StockTransfer transfer;
  final bool decline;

  @override
  ConsumerState<CloseTransferDialog> createState() =>
      _CloseTransferDialogState();
}

class _CloseTransferDialogState extends ConsumerState<CloseTransferDialog> {
  String _note = '';
  bool _busy = false;

  Future<void> _submit() async {
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider).inventory;
    final bus = ref.read(realtimeBusProvider);
    final note = _note.trim();
    final body = CloseTransferRequest(
      note: note.isEmpty ? null : note,
      explicitNulls: note.isEmpty ? const {'note'} : const {},
    );
    final id = widget.transfer.id;
    setState(() => _busy = true);
    try {
      final next = widget.decline
          ? await api.declineTransfer(id: id, body: body)
          : await api.cancelStockTransfer(id: id, body: body);
      bus.invalidate(inventoryPathFamilies);
      if (!mounted) return;
      DashToast.success(
        context,
        widget.decline
            ? t('inventory.transfers.declinedToast')
            : t('inventory.transfers.cancelledToast'),
      );
      Navigator.of(context).pop(next);
    } on Object catch (e) {
      if (isStaleTransferRefusal(e)) bus.invalidate(inventoryPathFamilies);
      if (!mounted) return;
      setState(() => _busy = false);
      DashToast.error(context, errorMessage(e, t));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final tr = widget.transfer;
    final decline = widget.decline;
    return DashSurface(
      key: const ValueKey('transfer-close'),
      title: decline
          ? t('inventory.transfers.declineTitle', args: {'ref': tr.reference})
          : t('inventory.transfers.cancelTitle', args: {'ref': tr.reference}),
      description: decline
          ? t(
              'inventory.transfers.declineHint',
              args: {'to': tr.destinationBranchName},
            )
          : tr.status.value == 'dispatched'
          ? t(
              'inventory.transfers.cancelInTransitHint',
              args: {'from': tr.sourceBranchName},
            )
          : t('inventory.transfers.cancelHint'),
      body: DashFormField<String>(
        label: t('inventory.transfers.reason'),
        optionalText: decline ? null : '(${t('common.optional')})',
        builder: (context, _) => DashTextInput(
          key: const ValueKey('transfer-close-reason'),
          value: _note,
          semanticLabel: t('inventory.transfers.reason'),
          minLines: 2,
          maxLines: 4,
          onChanged: (v) => setState(() => _note = v),
        ),
      ),
      actions: [
        DashButton(
          key: const ValueKey('transfer-close-back'),
          label: t('common.back'),
          variant: DashButtonVariant.outline,
          onPressed: () => Navigator.of(context).pop(),
        ),
        DashButton(
          key: const ValueKey('transfer-close-submit'),
          label: decline
              ? t('inventory.transfers.decline')
              : t('inventory.transfers.cancel'),
          variant: DashButtonVariant.destructive,
          loading: _busy,
          onPressed: decline && _note.trim().isEmpty ? null : _submit,
        ),
      ],
    );
  }
}
