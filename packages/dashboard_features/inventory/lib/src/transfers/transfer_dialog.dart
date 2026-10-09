/// The transfer dialog (INV-TRF-025…037; web `transfer-dialog.tsx` at
/// af50aa63): one transfer with many lines. Someone at the sending side
/// makes a draft (or sends it now, or, working at both ends, records it
/// arrived); someone at the receiving side makes a request the sender
/// answers. Edit changes a draft's or a request's lines; Accept answers a
/// request. The result (the made, sent or received transfer) is popped.
library;

import 'package:collection/collection.dart';
import 'package:dashboard_api/dashboard_api.dart'
    show
        AcceptTransferRequest,
        BranchStockRow,
        CreateTransferRequest,
        OrgIngredient,
        ReceiveTransferLine,
        ReceiveTransferRequest,
        StockTransfer,
        TransferLineInput,
        UpdateTransferRequest;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../purchasing/purchasing_widgets.dart' show PoNumberInput;
import '../shared/inventory_data.dart';
import '../shared/inventory_labels.dart';
import '../shared/inventory_lib.dart' show jsNumberString;
import 'transfers_data.dart';

/// `create`: a draft or a request. `edit`: a draft's or request's lines.
/// `accept`: answer a request.
enum TransferDialogMode { create, edit, accept }

/// Opens the dialog; the transfer it ended on, or null.
Future<StockTransfer?> showTransferDialog(
  BuildContext context, {
  TransferDialogMode mode = TransferDialogMode.create,
  StockTransfer? transfer,
  String? defaultSourceId,
  String? defaultDestinationId,
  List<TransferLineInput>? prefillLines,
}) => showDashDialog<StockTransfer>(
  context,
  builder: (_) => TransferDialog(
    mode: mode,
    transfer: transfer,
    defaultSourceId: defaultSourceId,
    defaultDestinationId: defaultDestinationId,
    prefillLines: prefillLines,
  ),
);

class TransferDialog extends ConsumerStatefulWidget {
  const TransferDialog({
    this.mode = TransferDialogMode.create,
    this.transfer,
    this.defaultSourceId,
    this.defaultDestinationId,
    this.prefillLines,
    super.key,
  });

  final TransferDialogMode mode;
  final StockTransfer? transfer;
  final String? defaultSourceId;
  final String? defaultDestinationId;
  final List<TransferLineInput>? prefillLines;

  @override
  ConsumerState<TransferDialog> createState() => _TransferDialogState();
}

class _Line {
  _Line(this.key, this.ingredientId, this.qty);

  final int key;
  String? ingredientId;
  String qty;
}

/// A typed quantity > 0 (`isNum`).
bool _isNum(String s) => (dashParseNumber(s) ?? 0) > 0;

class _TransferDialogState extends ConsumerState<TransferDialog> {
  int _keys = 0;
  late String _sourceId;
  late String _destId;
  late bool _asRequest;
  late List<_Line> _lines;
  late String _note;
  bool _receiveNow = false;
  bool _busy = false;

  /// What a multi-call submit already did (made, sent): a retry resumes
  /// from it, so the transfer is never made, or sent, twice (INV-TRF-034).
  StockTransfer? _made;

  TransferDialogMode get _mode => widget.mode;

  @override
  void initState() {
    super.initState();
    final tr = widget.transfer;
    _sourceId = tr?.sourceBranchId ?? widget.defaultSourceId ?? '';
    _destId = tr?.destinationBranchId ?? widget.defaultDestinationId ?? '';
    final mine = {
      for (final b in ref.read(activeBranchesProvider) ?? const []) b.id,
    };
    // Sending from where you work; otherwise you can only ask. Editing a
    // request is still asking: the source's stock isn't yours to read.
    _asRequest = _mode == TransferDialogMode.create
        ? _sourceId.isNotEmpty && !mine.contains(_sourceId)
        : _mode == TransferDialogMode.edit && tr?.status.value == 'requested';
    final from = tr != null
        ? [for (final l in tr.lines) (l.orgIngredientId, l.qtySent)]
        : [
            for (final l in widget.prefillLines ?? const <TransferLineInput>[])
              (l.orgIngredientId, l.quantity),
          ];
    _lines = from.isEmpty
        ? [_Line(++_keys, null, '')]
        : [for (final (id, q) in from) _Line(++_keys, id, jsNumberString(q))];
    _note = tr?.note ?? '';
  }

  List<TransferLineInput> _payload() => [
    for (final l in _lines)
      if (l.ingredientId != null)
        TransferLineInput(
          orgIngredientId: l.ingredientId!,
          quantity: dashParseNumber(l.qty)!,
        ),
  ];

  void _remember(StockTransfer tr) {
    _made = tr;
    if (mounted) setState(() {});
  }

  /// INV-TRF-033/034: up to three calls (make or save, send, receive).
  Future<void> _run({required bool send, required bool quick}) async {
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider).inventory;
    // Captured now: inventory refreshes even if the dialog closes mid-save.
    final bus = ref.read(realtimeBusProvider);
    final note = _note.trim();
    final noteNull = note.isEmpty ? const {'note'} : const <String>{};
    final lines = _payload();
    setState(() => _busy = true);
    var tr = _made;
    try {
      if (tr == null) {
        final base = widget.transfer;
        if (_mode == TransferDialogMode.edit && base != null) {
          tr = await api.updateTransfer(
            id: base.id,
            body: UpdateTransferRequest(
              lines: lines,
              note: note.isEmpty ? null : note,
              explicitNulls: noteNull,
            ),
          );
        } else if (_mode == TransferDialogMode.accept && base != null) {
          tr = await api.acceptTransfer(
            id: base.id,
            body: AcceptTransferRequest(lines: lines),
          );
        } else {
          tr = await api.createTransfer(
            body: CreateTransferRequest(
              sourceBranchId: _sourceId,
              destinationBranchId: _destId,
              request: _asRequest,
              lines: lines,
              note: note.isEmpty ? null : note,
              explicitNulls: noteNull,
            ),
          );
        }
      } else if (tr.status.value == 'draft') {
        // The lines may have changed since (lowered to what's on hand).
        tr = await api.updateTransfer(
          id: tr.id,
          body: UpdateTransferRequest(
            lines: lines,
            note: note.isEmpty ? null : note,
            explicitNulls: noteNull,
          ),
        );
      }
      _remember(tr);
      if (send) {
        if (tr.status.value == 'draft') {
          tr = await api.dispatchTransfer(id: tr.id);
          _remember(tr);
        }
        // Working at both ends: record the arrival too.
        if (quick && tr.status.value == 'dispatched') {
          tr = await api.receiveTransfer(
            id: tr.id,
            body: ReceiveTransferRequest(
              lines: [
                for (final l in tr.lines)
                  ReceiveTransferLine(lineId: l.id, qtyReceived: l.qtySent),
              ],
            ),
          );
          _remember(tr);
        }
      }
      bus.invalidate(inventoryPathFamilies);
      if (!mounted) return;
      DashToast.success(context, switch (tr.status.value) {
        'requested' => t('inventory.transfers.requestedToast'),
        'received' => t('inventory.transfers.receivedToast'),
        'dispatched' => t('inventory.transfers.dispatchedToast'),
        _ => t('inventory.transfers.savedDraft'),
      });
      Navigator.of(context).pop(tr);
    } on Object catch (e) {
      // Part of it went through, or the transfer moved on: say so.
      if (tr != null || isStaleTransferRefusal(e)) {
        bus.invalidate(inventoryPathFamilies);
      }
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
    final orgId = ref.watch(orgIdProvider);
    final branches = ref.watch(activeBranchesProvider) ?? const [];
    final mine = {for (final b in branches) b.id};
    final src = _sourceId, dst = _destId, asRequest = _asRequest;
    final locations = orgId == null
        ? null
        : ref.watch(transferLocationsProvider(orgId)).value;
    final stock = src.isNotEmpty && !asRequest
        ? ref.watch(branchStockProvider(src))
        : null;
    final catalog = asRequest && orgId != null
        ? ref.watch(inventoryCatalogProvider(orgId)).value
        : null;
    final atSource = src.isEmpty ? null : ref.watch(authzAtProvider(src));
    final atDest = dst.isEmpty ? null : ref.watch(authzAtProvider(dst));
    Authz held(AsyncValue<Authz>? a) => a?.value ?? Authz.none;

    final stockById = {
      for (final s in stock?.value ?? const <BranchStockRow>[])
        s.orgIngredientId: s,
    };
    final unitById = {
      for (final i in catalog ?? const <OrgIngredient>[]) i.id: i.unit,
    };
    final options = <DashOption<String>>[
      ...asRequest
          ? [
              for (final i in catalog ?? const <OrgIngredient>[])
                DashOption(
                  value: i.id,
                  label: i.name,
                  keywords: i.categoryName,
                  hint: fmtUnit(i.unit),
                ),
            ]
          : [
              for (final s in stock?.value ?? const <BranchStockRow>[])
                if (s.onHand > 0 ||
                    _lines.any((l) => l.ingredientId == s.orgIngredientId))
                  DashOption(
                    value: s.orgIngredientId,
                    label: s.ingredientName,
                    keywords: s.categoryName,
                    hint: qtyWithUnit(f, s.onHand, s.unit),
                  ),
            ],
    ];

    final same = src.isNotEmpty && src == dst;
    const create = Cap.inventoryTransfersCreate;
    final canSend = mine.contains(src) && held(atSource).can(create);
    final canAsk = mine.contains(dst) && held(atDest).can(create);
    // Recording the arrival is the destination's receive (.edit there).
    final quickReceive =
        canSend &&
        mine.contains(dst) &&
        held(atDest).can(Cap.inventoryTransfersEdit);
    final picked = [
      for (final l in _lines)
        if (l.ingredientId != null) l,
    ];
    final dupes =
        picked.map((l) => l.ingredientId).toSet().length != picked.length;
    final isNew = _mode == TransferDialogMode.create;
    final valid =
        src.isNotEmpty &&
        dst.isNotEmpty &&
        !same &&
        picked.isNotEmpty &&
        picked.every((l) => _isNum(l.qty)) &&
        !dupes &&
        (!isNew || (asRequest ? canAsk : canSend));
    BranchStockRow? stockOf(_Line l) =>
        !asRequest && l.ingredientId != null ? stockById[l.ingredientId] : null;
    bool over(_Line l) {
      final s = stockOf(l);
      return s != null &&
          _isNum(l.qty) &&
          milli(dashParseNumber(l.qty)!) > milli(s.onHand);
    }

    // The server refuses to send more than is on hand: don't offer it.
    final short = _lines.any(over);
    final quick = _receiveNow && quickReceive;

    final title = switch (_mode) {
      TransferDialogMode.edit => t('inventory.transfers.editTitle'),
      TransferDialogMode.accept => t('inventory.transfers.acceptTitle'),
      _ =>
        asRequest
            ? t('inventory.transfers.requestTitle')
            : t('inventory.transfers.createTitle'),
    };
    // Your own side is where you work; the other side, any location (both,
    // once fixed).
    final all = locations != null
        ? [for (final l in locations) (id: l.id, name: l.name)]
        : [for (final b in branches) (id: b.id, name: b.name)];
    final own = [for (final b in branches) (id: b.id, name: b.name)];
    final fixed = !isNew || _made != null;
    final sourceList = fixed || asRequest ? all : own;
    final destList = fixed || !asRequest ? all : own;
    final sourceName = all.firstWhereOrNull((b) => b.id == src)?.name;
    final warn = DashType.small.copyWith(
      color: Color.lerp(c.danger, c.textPrimary, 0.5),
    );
    final muted = DashType.small.copyWith(color: c.textMuted);
    final sideReady = asRequest
        ? atDest?.hasValue ?? false
        : atSource?.hasValue ?? false;

    Widget select(
      String key,
      String label,
      String value,
      List<({String id, String name})> list,
      ValueChanged<String> onChanged,
    ) => DashFormField<String>(
      label: label,
      builder: (context, _) => DashSelect<String>(
        key: ValueKey(key),
        options: [for (final b in list) DashOption(value: b.id, label: b.name)],
        value: value.isEmpty ? null : value,
        placeholder: '—',
        semanticLabel: label,
        enabled: !fixed,
        // The reads that side would bring: its stock, what you hold there.
        onOptionIntent: (id) {
          ref.warm(authzAtProvider(id));
          if (key == 'transfer-source' && !asRequest) {
            ref.warm(branchStockProvider(id));
          }
        },
        onChanged: (v) => setState(() => onChanged(v)),
      ),
    );

    return DashSurface(
      key: const ValueKey('transfer-dialog'),
      title: title,
      description: _mode == TransferDialogMode.accept
          ? t('inventory.transfers.acceptHint')
          : asRequest
          ? t('inventory.transfers.requestHint')
          : t('inventory.transfers.sendHint'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.md,
        children: [
          if (isNew)
            DashSegmentedControl<bool>(
              key: const ValueKey('transfer-mode'),
              value: asRequest,
              enabled: _made == null,
              expand: true,
              options: [
                DashOption(
                  value: false,
                  label: t('inventory.transfers.modeSend'),
                ),
                DashOption(
                  value: true,
                  label: t('inventory.transfers.modeRequest'),
                ),
              ],
              // Asking reads the catalogue; sending reads the new source's
              // stock (the ends swap).
              onIntent: (v) {
                if (v) {
                  if (orgId != null) ref.warm(inventoryCatalogProvider(orgId));
                } else if (dst.isNotEmpty) {
                  ref.warm(branchStockProvider(dst));
                }
              },
              onChanged: (v) => setState(() {
                _asRequest = v;
                // Your side swaps ends: sending to X becomes asking X.
                _sourceId = dst;
                _destId = src;
              }),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: Space.sm,
            children: [
              Expanded(
                child: select(
                  'transfer-source',
                  t('inventory.transfers.from'),
                  src,
                  sourceList,
                  (v) => _sourceId = v,
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
                child: select(
                  'transfer-destination',
                  t('inventory.transfers.to'),
                  dst,
                  destList,
                  (v) => _destId = v,
                ),
              ),
            ],
          ),
          if (same)
            Text(
              t('inventory.transfers.sameBranch'),
              key: const ValueKey('transfer-same-branch'),
              style: warn,
            ),
          if (isNew &&
              src.isNotEmpty &&
              dst.isNotEmpty &&
              !same &&
              sideReady &&
              !(asRequest ? canAsk : canSend))
            Text(
              asRequest
                  ? t('inventory.transfers.notAtDestination')
                  : t('inventory.transfers.notAtSource'),
              key: const ValueKey('transfer-side-check'),
              style: muted,
            ),
          if (stock != null && stock.failedFirst)
            _StockFailed(
              text: errorMessage(stock.error, t),
              retrying: stock.isLoading,
              onRetry: () => ref.invalidate(branchStockProvider(src)),
            ),
          DashFormField<String>(
            label: t('inventory.transfers.items'),
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              spacing: Space.sm,
              children: [
                for (final (i, l) in _lines.indexed)
                  _LineRow(
                    key: ValueKey('transfer-line-${l.key}'),
                    index: i,
                    line: l,
                    options: options,
                    enabled: src.isNotEmpty,
                    emptyText: stock == null
                        ? null
                        : stock.awaitingFirst
                        ? t('common.loading')
                        : options.isEmpty && !stock.failedFirst
                        ? t('inventory.transfers.nothingToSend')
                        : null,
                    hint: stockOf(l) == null || sourceName == null
                        ? null
                        : t(
                            'inventory.transfers.onHandHint',
                            args: {
                              'branch': sourceName,
                              'qty': f.fmtNumber(stockOf(l)!.onHand),
                              'unit': fmtUnit(stockOf(l)!.unit),
                            },
                          ),
                    over: over(l),
                    unit:
                        stockOf(l)?.unit ??
                        (l.ingredientId == null
                            ? null
                            : unitById[l.ingredientId]),
                    canRemove: _lines.length > 1,
                    onPick: (id) => setState(() => l.ingredientId = id),
                    onQty: (v) => setState(() => l.qty = v),
                    onRemove: () => setState(() => _lines.remove(l)),
                  ),
                if (dupes)
                  Text(
                    t('inventory.transfers.duplicateItem'),
                    key: const ValueKey('transfer-duplicate'),
                    style: warn,
                  ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: DashButton(
                    key: const ValueKey('transfer-add-line'),
                    label: t('inventory.transfers.addItem'),
                    icon: 'plus',
                    variant: DashButtonVariant.outline,
                    size: DashButtonSize.compact,
                    onPressed: src.isEmpty
                        ? null
                        : () => setState(
                            () => _lines.add(_Line(++_keys, null, '')),
                          ),
                  ),
                ),
              ],
            ),
          ),
          if (_mode != TransferDialogMode.accept)
            DashFormField<String>(
              label: t('inventory.transfers.note'),
              optionalText: '(${t('common.optional')})',
              builder: (context, _) => DashTextInput(
                key: const ValueKey('transfer-note-input'),
                value: _note,
                semanticLabel: t('inventory.transfers.note'),
                minLines: 2,
                maxLines: 4,
                onChanged: (v) => setState(() => _note = v),
              ),
            ),
          if (!asRequest && _mode != TransferDialogMode.edit && quickReceive)
            Container(
              key: const ValueKey('transfer-receive-now'),
              padding: const EdgeInsets.all(Space.md),
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: DashCheckboxField(
                value: _receiveNow,
                label: t('inventory.transfers.receiveNow'),
                description: t('inventory.transfers.receiveNowHint'),
                onChanged: (v) => setState(() => _receiveNow = v),
              ),
            ),
        ],
      ),
      actions: [
        DashButton(
          key: const ValueKey('transfer-cancel'),
          label: t('common.cancel'),
          variant: DashButtonVariant.outline,
          onPressed: () => Navigator.of(context).pop(),
        ),
        if (asRequest || _mode == TransferDialogMode.edit)
          DashButton(
            key: const ValueKey('transfer-save'),
            label: asRequest && isNew
                ? t('inventory.transfers.sendRequest')
                : t('common.save'),
            loading: _busy,
            onPressed: valid ? () => _run(send: false, quick: false) : null,
          )
        else ...[
          DashButton(
            key: const ValueKey('transfer-save-draft'),
            label: t('inventory.transfers.saveDraft'),
            variant: DashButtonVariant.outline,
            loading: _busy,
            onPressed: valid ? () => _run(send: false, quick: false) : null,
          ),
          DashButton(
            key: const ValueKey('transfer-send'),
            label: quick
                ? t('inventory.transfers.sendAndReceive')
                : t('inventory.transfers.sendNow'),
            loading: _busy,
            onPressed: valid && !short
                ? () => _run(send: true, quick: quick)
                : null,
          ),
        ],
      ],
    );
  }
}

/// One line: the ingredient picker (with the source's on-hand under it),
/// the quantity box and Remove.
class _LineRow extends ConsumerWidget {
  const _LineRow({
    required this.index,
    required this.line,
    required this.options,
    required this.enabled,
    required this.emptyText,
    required this.hint,
    required this.over,
    required this.unit,
    required this.canRemove,
    required this.onPick,
    required this.onQty,
    required this.onRemove,
    super.key,
  });

  final int index;
  final _Line line;
  final List<DashOption<String>> options;
  final bool enabled;
  final String? emptyText;
  final String? hint;
  final bool over;
  final String? unit;
  final bool canRemove;
  final ValueChanged<String> onPick;
  final ValueChanged<String> onQty;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.sm,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.xs,
            children: [
              DashSelect<String>(
                key: ValueKey('transfer-ingredient-$index'),
                options: options,
                value: line.ingredientId,
                placeholder: t('inventory.stock.pickIngredient'),
                semanticLabel: t('inventory.stock.pickIngredient'),
                searchable: true,
                searchPlaceholder: t('common.search'),
                emptyText: emptyText,
                enabled: enabled,
                onChanged: onPick,
              ),
              if (hint != null)
                Text(
                  hint!,
                  key: ValueKey('transfer-on-hand-$index'),
                  style: DashType.small.copyWith(
                    color: over
                        ? Color.lerp(c.danger, c.textPrimary, 0.5)
                        : c.textMuted,
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          width: Space.xxl * 3 + Space.lg,
          child: PoNumberInput(
            key: ValueKey('transfer-qty-$index'),
            value: line.qty,
            placeholder: unit != null
                ? fmtUnit(unit)
                : t('inventory.transfers.quantity'),
            semanticLabel: t('inventory.transfers.quantity'),
            onChanged: onQty,
          ),
        ),
        DashIconButton(
          key: ValueKey('transfer-remove-$index'),
          icon: 'x',
          semanticLabel: t('common.remove'),
          onPressed: canRemove ? onRemove : null,
        ),
      ],
    );
  }
}

/// (divergence) The source's stock could not be read: the server's words
/// and Retry, never "nothing on hand".
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
