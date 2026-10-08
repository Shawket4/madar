/// The Receive order dialog (INV-PUR-043…051, -065, -068, -073; web
/// `receive-dialog.tsx`): receive what arrived (the order stays open for
/// the rest) and the order's delivery history; read-only for a received or
/// cancelled order ("View order"). Opened from Purchasing and from Today's
/// "Arriving today" (INV-TOD-018/029). Owned by the purchasing unit; Today
/// calls [showReceiveDialog] and nothing else.
library;

import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart'
    show GoodsReceipt, PurchaseOrderFull, PurchaseOrderLine, ReceiveLineInput, ReceivePurchaseOrderRequest;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/inventory_data.dart';
import '../shared/inventory_lib.dart';
import 'purchasing_data.dart';
import 'purchasing_widgets.dart';

/// Opens the dialog for order [purchaseOrderId]; true once a delivery was
/// recorded (inventory invalidated, toast shown).
Future<bool?> showReceiveDialog(
  BuildContext context, {
  required String purchaseOrderId,
}) => showDashDialog<bool>(
  context,
  width: DashMetrics.dialogWide + Space.xxl * 3,
  builder: (_) => ReceiveDialog(purchaseOrderId: purchaseOrderId),
);

enum _Tab { receive, history }

class ReceiveDialog extends ConsumerStatefulWidget {
  const ReceiveDialog({required this.purchaseOrderId, super.key});

  final String purchaseOrderId;

  @override
  ConsumerState<ReceiveDialog> createState() => _ReceiveDialogState();
}

class _ReceiveDialogState extends ConsumerState<ReceiveDialog> {
  /// What is arriving, per line (text as typed).
  Map<String, String> _receiving = {};

  /// The ACTUAL invoice total (EGP) per line; blank = the ordered total,
  /// pro rata (the server does the same sum).
  Map<String, String> _totals = {};
  _Tab _tab = _Tab.receive;
  bool _busy = false;

  /// The order as last initialised from (React Query's structural sharing:
  /// a refetch with the same answer does not reset what was typed).
  String? _initFrom;

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      purchaseOrderProvider(widget.purchaseOrderId),
      (_, next) {
        final po = next.value;
        if (po == null) return;
        final sig = jsonEncode(po.toJson());
        if (sig == _initFrom) return;
        _initFrom = sig;
        final init = <String, String>{
          for (final l in po.lines)
            l.id: l.quantityOrdered - l.quantityReceived > 0
                ? jsNumberString(l.quantityOrdered - l.quantityReceived)
                : '',
        };
        void apply() {
          _receiving = init;
          _totals = {};
          _tab = _Tab.receive;
        }

        if (mounted && context.mounted) {
          setState(apply);
        } else {
          apply();
        }
      },
      fireImmediately: true,
    );
  }

  bool _pastReceiving(PurchaseOrderFull? po) =>
      po?.status == 'received' || po?.status == 'cancelled';

  List<ReceiveLineInput> _payload(PurchaseOrderFull po) => [
    for (final l in po.lines)
      if (parseInputNumber(_receiving[l.id] ?? '') case final qty
          when qty.isFinite && qty > 0)
        () {
          final raw = (_totals[l.id] ?? '').trim();
          final egp = raw.isEmpty ? double.nan : parseInputNumber(raw);
          final cost = egp.isFinite && egp >= 0 ? egpToPiastres(egp) : null;
          return ReceiveLineInput(
            lineId: l.id,
            quantityReceived: qty,
            lineCost: cost,
            explicitNulls: {if (cost == null) 'line_cost', 'unit_cost'},
          );
        }(),
  ];

  Future<void> _submit(PurchaseOrderFull po) async {
    final lines = _payload(po);
    if (lines.isEmpty) return;
    final t = ref.read(tProvider);
    setState(() => _busy = true);
    try {
      await ref
          .read(apiProvider)
          .purchasing
          .receivePurchaseOrder(
            id: widget.purchaseOrderId,
            body: ReceivePurchaseOrderRequest(lines: lines),
          );
      invalidateInventory(ref);
      if (!mounted) return;
      DashToast.success(context, t('inventory.purchasing.receive'));
      Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      DashToast.error(context, errorMessage(e, t));
    }
  }

  void _openTab(_Tab tab) {
    // The history is asked for every time its tab opens.
    if (tab == _Tab.history && _tab != _Tab.history) {
      ref.invalidate(poReceiptsProvider(widget.purchaseOrderId));
    }
    setState(() => _tab = tab);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final async = ref.watch(purchaseOrderProvider(widget.purchaseOrderId));
    final po = async.value;
    final past = _pastReceiving(po);
    final supplier = po?.supplierName;
    final title =
        '${t('inventory.purchasing.receiveTitle')}'
        '${supplier != null && supplier.isNotEmpty ? ' · $supplier' : ''}';
    final canReceive = po != null && _payload(po).isNotEmpty;

    return DashSurface(
      title: title,
      description: t('inventory.purchasing.partialHint'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.md,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: DashSegmentedControl<_Tab>(
              key: const ValueKey('receive-tabs'),
              options: [
                DashOption(
                  value: _Tab.receive,
                  label: t('inventory.purchasing.receive'),
                ),
                DashOption(
                  value: _Tab.history,
                  label: t('inventory.purchasing.deliveryHistory'),
                ),
              ],
              value: _tab,
              onChanged: _openTab,
            ),
          ),
          if (_tab == _Tab.receive)
            _ReceiveLines(
              async: async,
              receiving: _receiving,
              totals: _totals,
              locked: past,
              onReceiving: (id, v) => setState(() => _receiving[id] = v),
              onTotal: (id, v) => setState(() => _totals[id] = v),
              onRetry: () => ref.invalidate(
                purchaseOrderProvider(widget.purchaseOrderId),
              ),
            )
          else
            _History(purchaseOrderId: widget.purchaseOrderId),
        ],
      ),
      actions: [
        DashButton(
          label: t('common.cancel'),
          variant: DashButtonVariant.outline,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        if (!past)
          DashButton(
            key: const ValueKey('receive-submit'),
            label: t('inventory.purchasing.receive'),
            loading: _busy,
            onPressed: canReceive ? () => _submit(po) : null,
          ),
      ],
    );
  }
}

/// The Receive tab: one row per order line (cards on a phone).
class _ReceiveLines extends ConsumerWidget {
  const _ReceiveLines({
    required this.async,
    required this.receiving,
    required this.totals,
    required this.locked,
    required this.onReceiving,
    required this.onTotal,
    required this.onRetry,
  });

  final AsyncValue<PurchaseOrderFull> async;
  final Map<String, String> receiving;
  final Map<String, String> totals;
  final bool locked;
  final void Function(String lineId, String v) onReceiving;
  final void Function(String lineId, String v) onTotal;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final phone = DashBreakpoints.isPhone(context);
    final po = async.value;

    if (po == null && async.hasError && !async.isLoading) {
      return DashErrorState(
        message: errorMessage(async.error, t),
        onRetry: onRetry,
      );
    }

    /// What the order says [l] costs for what is arriving: its total, pro
    /// rata; null until a positive quantity is typed.
    String expected(PurchaseOrderLine l) {
      final arriving = parseInputNumber(receiving[l.id] ?? '');
      if (!arriving.isFinite || arriving <= 0 || l.quantityOrdered <= 0) {
        return '—';
      }
      final p = jsRound(l.lineCost * arriving / l.quantityOrdered);
      return piastresToEgpFixed(p);
    }

    Widget figure(String text) => Text(
      dashFigure(text),
      textDirection: TextDirection.ltr,
      style: DashType.mono.copyWith(color: c.textPrimary),
    );

    bool off(PurchaseOrderLine l) =>
        l.quantityOrdered - l.quantityReceived <= 0 || locked;

    Widget qtyInput(PurchaseOrderLine l) => PoNumberInput(
      key: ValueKey('receive-qty-${l.id}'),
      value: receiving[l.id] ?? '',
      onChanged: (v) => onReceiving(l.id, v),
      semanticLabel:
          '${t('inventory.purchasing.receiving')} · ${l.ingredientName}',
      enabled: !off(l),
    );

    Widget totalInput(PurchaseOrderLine l) => PoNumberInput(
      key: ValueKey('receive-total-${l.id}'),
      value: totals[l.id] ?? '',
      onChanged: (v) => onTotal(l.id, v),
      placeholder: expected(l),
      semanticLabel:
          '${t('inventory.purchasing.invoiceTotal')} · ${l.ingredientName}',
      enabled: !off(l),
    );

    if (phone) {
      if (po == null) {
        return Column(
          spacing: Space.sm,
          children: [
            for (var i = 0; i < 2; i++)
              const DashSkeleton(height: Space.xxl * 4, radius: Radii.card),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.sm,
        children: [
          for (final l in po.lines)
            DashCard(
              key: ValueKey('receive-line-${l.id}'),
              padding: const EdgeInsets.all(Space.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.sm,
                children: [
                  Text(
                    l.ingredientName,
                    style: DashType.bodyStrong.copyWith(color: c.textPrimary),
                  ),
                  LabelValueGrid(
                    entries: [
                      (
                        t('inventory.purchasing.qtyOrdered'),
                        figure('${f.fmtNumber(l.quantityOrdered)} ${l.purchaseUnit}'),
                      ),
                      (
                        t('inventory.purchasing.alreadyReceived'),
                        figure(f.fmtNumber(l.quantityReceived)),
                      ),
                      (
                        t('inventory.purchasing.remaining'),
                        figure(
                          f.fmtNumber(l.quantityOrdered - l.quantityReceived),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: Space.sm,
                    children: [
                      Expanded(
                        child: _Labelled(
                          t('inventory.purchasing.receiving'),
                          qtyInput(l),
                        ),
                      ),
                      Expanded(
                        child: _Labelled(
                          t('inventory.purchasing.invoiceTotal'),
                          totalInput(l),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      );
    }

    // Wide: the web's table.
    const inputQty = Space.xxl * 3;
    const inputTotal = Space.xxl * 3 + Space.lg;
    final head = DashType.tableHeader.copyWith(color: c.textSecondary);
    Widget cell(Widget child, {double? width, bool end = true}) {
      final aligned = Align(
        alignment: end
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        child: child,
      );
      return width == null
          ? Expanded(child: aligned)
          : SizedBox(width: width, child: aligned);
    }

    Widget headCell(String label, {double? width, bool end = true}) => cell(
      MadarClippedText(
        label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: head,
      ),
      width: width,
      end: end,
    );

    const fig = Space.xxl * 2 + Space.lg;
    final rows = <Widget>[
      Container(
        height: DashMetrics.tableHeader,
        padding: const EdgeInsets.symmetric(horizontal: Space.md),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.hairline)),
        ),
        child: Row(
          spacing: Space.md,
          children: [
            headCell(t('inventory.catalog.name'), end: false),
            headCell(t('inventory.purchasing.qtyOrdered'), width: fig),
            headCell(t('inventory.purchasing.alreadyReceived'), width: fig),
            headCell(t('inventory.purchasing.remaining'), width: fig),
            headCell(t('inventory.purchasing.receiving'), width: inputQty),
            headCell(t('inventory.purchasing.invoiceTotal'), width: inputTotal),
          ],
        ),
      ),
      if (po == null)
        for (var i = 0; i < 2; i++)
          Container(
            height: DashMetrics.tableRow,
            padding: const EdgeInsets.symmetric(horizontal: Space.md),
            alignment: Alignment.center,
            child: const DashSkeleton(),
          )
      else
        for (var i = 0; i < po.lines.length; i++)
          Container(
            key: ValueKey('receive-line-${po.lines[i].id}'),
            constraints: const BoxConstraints(minHeight: DashMetrics.tableRow),
            padding: const EdgeInsets.symmetric(horizontal: Space.md),
            decoration: BoxDecoration(
              border: i == po.lines.length - 1
                  ? null
                  : Border(bottom: BorderSide(color: c.hairline)),
            ),
            child: Row(
              spacing: Space.md,
              children: [
                cell(
                  MadarClippedText(
                    po.lines[i].ingredientName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                  ),
                  end: false,
                ),
                cell(
                  figure(
                    '${f.fmtNumber(po.lines[i].quantityOrdered)} ${po.lines[i].purchaseUnit}',
                  ),
                  width: fig,
                ),
                cell(figure(f.fmtNumber(po.lines[i].quantityReceived)), width: fig),
                cell(
                  figure(
                    f.fmtNumber(
                      po.lines[i].quantityOrdered -
                          po.lines[i].quantityReceived,
                    ),
                  ),
                  width: fig,
                ),
                SizedBox(width: inputQty, child: qtyInput(po.lines[i])),
                SizedBox(width: inputTotal, child: totalInput(po.lines[i])),
              ],
            ),
          ),
    ];
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: c.hairline),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const min = 560.0;
          final table = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: rows,
          );
          if (constraints.maxWidth >= min) return table;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: min, child: table),
          );
        },
      ),
    );
  }
}

class _Labelled extends StatelessWidget {
  const _Labelled(this.label, this.child);

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.xs,
      children: [
        MadarClippedText(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DashType.smallMedium.copyWith(color: c.textPrimary),
        ),
        child,
      ],
    );
  }
}

/// The Delivery history tab: one card per receipt, newest first.
class _History extends ConsumerWidget {
  const _History({required this.purchaseOrderId});

  final String purchaseOrderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final phone = DashBreakpoints.isPhone(context);
    final async = ref.watch(poReceiptsProvider(purchaseOrderId));
    if (async.firstLoad) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          for (var i = 0; i < 2; i++)
            Container(
              padding: const EdgeInsets.all(Space.md),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.sm),
                border: Border.all(color: c.hairline),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.sm,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      DashSkeleton(width: Space.xxl * 4 + Space.lg),
                      DashSkeleton(width: Space.xxl * 2 + Space.lg),
                    ],
                  ),
                  DashSkeleton(),
                  FractionallySizedBox(
                    widthFactor: 0.8,
                    alignment: AlignmentDirectional.centerStart,
                    child: DashSkeleton(),
                  ),
                ],
              ),
            ),
        ],
      );
    }
    final failed = async.errorText(t);
    if (failed != null) {
      return DashErrorState(
        message: failed,
        onRetry: () => ref.invalidate(poReceiptsProvider(purchaseOrderId)),
      );
    }
    final receipts = async.value ?? const <GoodsReceipt>[];
    if (receipts.isEmpty) {
      return DashEmptyState(title: t('inventory.purchasing.noDeliveries'));
    }
    final mono = DashType.mono.copyWith(color: c.textPrimary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        for (final r in receipts)
          Container(
            key: ValueKey('receipt-${r.id}'),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(Radii.sm),
              border: Border.all(color: c.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.md,
                    vertical: Space.sm,
                  ),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: c.hairline)),
                  ),
                  child: Row(
                    spacing: Space.sm,
                    children: [
                      Text(
                        f.fmtDateTime(r.receivedAt.toIso8601String()),
                        style: DashType.bodyMedium.copyWith(
                          color: c.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (r.isReturn)
                        DashStatusPill(
                          label: t('inventory.purchasing.return'),
                          tone: DashTone.danger,
                          small: true,
                        ),
                      const Spacer(),
                      Flexible(
                        child: MadarClippedText(
                          r.receivedByName ?? r.receivedBy,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DashType.body.copyWith(
                            color: c.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                for (var i = 0; i < r.lines.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.md,
                      vertical: Space.sm,
                    ),
                    decoration: BoxDecoration(
                      border: i == r.lines.length - 1
                          ? null
                          : Border(bottom: BorderSide(color: c.hairline)),
                    ),
                    child: _ReceiptLine(
                      phone: phone,
                      name: r.lines[i].ingredientName,
                      qty: f.fmtNumber(
                        r.lines[i].quantity,
                        const NumberOptions(
                          signDisplay: SignDisplay.exceptZero,
                        ),
                      ),
                      cost: r.lines[i].lineCost != null
                          ? f.fmtMoney(r.lines[i].lineCost)
                          : '—',
                      unitCost: r.lines[i].unitCostExact != null
                          ? formatUnitCost(f, r.lines[i].unitCostExact!)
                          : '—',
                      mono: mono,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ReceiptLine extends StatelessWidget {
  const _ReceiptLine({
    required this.phone,
    required this.name,
    required this.qty,
    required this.cost,
    required this.unitCost,
    required this.mono,
  });

  final bool phone;
  final String name;
  final String qty;
  final String cost;
  final String unitCost;
  final TextStyle mono;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    Widget fig(String s, {bool muted = false}) => Text(
      dashFigure(s),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      softWrap: false,
      style: muted ? mono.copyWith(color: c.textSecondary) : mono,
    );
    final nameText = MadarClippedText(
      name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: DashType.body.copyWith(color: c.textPrimary),
    );
    final figures = [fig(qty), fig(cost), fig(unitCost, muted: true)];
    if (phone) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.xs,
        children: [
          nameText,
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: figures,
          ),
        ],
      );
    }
    return Row(
      spacing: Space.lg,
      children: [
        Expanded(child: nameText),
        for (final w in figures)
          SizedBox(
            width: Space.xxl * 3 + Space.lg,
            child: Align(alignment: AlignmentDirectional.centerEnd, child: w),
          ),
      ],
    );
  }
}
