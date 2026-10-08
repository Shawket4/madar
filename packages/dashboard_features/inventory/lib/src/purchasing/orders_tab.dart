/// The Purchase orders tab (INV-PUR-008…016, -058, -060, -061): the scoped
/// branch's orders (every branch's with All branches, then with a Branch
/// column), the status filter, and per row Place order / Receive / ⋯ (View
/// order, Cancel order). A row opens the receive dialog.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show PurchaseOrder;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/inventory_data.dart';
import '../shared/inventory_labels.dart';
import '../shared/inventory_lib.dart';
import 'purchasing_data.dart';
import 'purchasing_widgets.dart';
import 'receive_dialog.dart';

/// The status filter's "every status" value.
const String allPoStatuses = 'all';

class PurchaseOrdersTab extends ConsumerStatefulWidget {
  const PurchaseOrdersTab({
    required this.ordersKey,
    required this.allBranches,
    required this.status,
    required this.onStatus,
    super.key,
  });

  final PurchaseOrdersKey ordersKey;
  final bool allBranches;

  /// [allPoStatuses] or one of [poStatuses].
  final String status;
  final ValueChanged<String> onStatus;

  @override
  ConsumerState<PurchaseOrdersTab> createState() => _PurchaseOrdersTabState();
}

class _PurchaseOrdersTabState extends ConsumerState<PurchaseOrdersTab> {
  /// The order whose Place order is in flight.
  String? _submitting;

  Future<void> _place(PurchaseOrder po) async {
    final t = ref.read(tProvider);
    setState(() => _submitting = po.id);
    try {
      await ref.read(apiProvider).purchasing.submitPurchaseOrder(id: po.id);
      invalidateInventory(ref);
      if (mounted) {
        DashToast.success(context, t('inventory.purchasing.orderPlaced'));
      }
    } on Object catch (e) {
      if (mounted) DashToast.error(context, errorMessage(e, t));
    } finally {
      if (mounted) setState(() => _submitting = null);
    }
  }

  Future<void> _cancel(PurchaseOrder po) async {
    final t = ref.read(tProvider);
    final ok = await showDashConfirm(
      context,
      title: t(
        'inventory.purchasing.cancelTitle',
        args: {'ref': poReference(id: po.id, reference: po.reference)},
      ),
      description: t('inventory.purchasing.cancelConsequence'),
      confirmLabel: t('inventory.purchasing.cancel'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(apiProvider).purchasing.cancelPurchaseOrder(id: po.id);
      invalidateInventory(ref);
      if (mounted) DashToast.success(context, t('common.done'));
    } on Object catch (e) {
      if (mounted) DashToast.error(context, errorMessage(e, t));
    }
  }

  void _open(PurchaseOrder po) =>
      showReceiveDialog(context, purchaseOrderId: po.id);

  /// Place order on a draft; Receive on a draft or ordered order, Receive
  /// remaining on a partly received one.
  List<Widget> _buttons(Translator t, PurchaseOrder po) => [
    if (po.status == 'draft')
      DashButton(
        key: ValueKey('po-place-${po.id}'),
        label: t('inventory.purchasing.placeOrder'),
        icon: 'send-horizonal',
        variant: DashButtonVariant.outline,
        size: DashButtonSize.compact,
        loading: _submitting == po.id,
        onPressed: () => _place(po),
      ),
    if (po.status == 'draft' ||
        po.status == 'ordered' ||
        po.status == 'partially_received')
      DashButton(
        key: ValueKey('po-receive-${po.id}'),
        label: po.status == 'partially_received'
            ? t('inventory.purchasing.receiveRemaining')
            : t('inventory.purchasing.receive'),
        icon: 'package-check',
        variant: DashButtonVariant.outline,
        size: DashButtonSize.compact,
        onPressed: () => _open(po),
      ),
  ];

  Widget _menu(Translator t, PurchaseOrder po) => DashMenu(
    key: ValueKey('po-menu-${po.id}'),
    items: [
      DashMenuItem(
        label: t('inventory.purchasing.viewOrder'),
        onSelected: () => _open(po),
      ),
      // A partly received order cannot be cancelled (the server refuses):
      // the goods have to be reversed first.
      if (po.status == 'draft' || po.status == 'ordered')
        DashMenuItem(
          label: t('inventory.purchasing.cancel'),
          icon: 'x-circle',
          destructive: true,
          onSelected: () => _cancel(po),
        ),
    ],
    builder: (context, c) => DashIconButton(
      icon: 'more-horizontal',
      semanticLabel: t('common.moreActions'),
      onPressed: c.toggle,
    ),
  );

  /// The widest row's actions: its buttons' labels measured, plus the ⋯.
  double _actionsWidth(BuildContext context, Translator t, List<PurchaseOrder> rows) {
    final style = DashType.meta.copyWith(fontWeight: FontWeight.w500);
    final scaler = MediaQuery.textScalerOf(context);
    final dir = Directionality.of(context);
    double button(String label) {
      final p = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: dir,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final w = p.width;
      p.dispose();
      return Space.md * 2 + IconSize.sm + Space.sm + w + Space.xs;
    }

    var widest = 0.0;
    for (final po in rows) {
      var w = 0.0;
      if (po.status == 'draft') {
        w += button(t('inventory.purchasing.placeOrder')) + Space.xs;
        w += button(t('inventory.purchasing.receive')) + Space.xs;
      } else if (po.status == 'ordered') {
        w += button(t('inventory.purchasing.receive')) + Space.xs;
      } else if (po.status == 'partially_received') {
        w += button(t('inventory.purchasing.receiveRemaining')) + Space.xs;
      }
      if (w > widest) widest = w;
    }
    return widest + DashMetrics.target + Space.lg;
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final async = ref.watch(purchaseOrdersProvider(widget.ordersKey));
    final rows = async.value ?? const <PurchaseOrder>[];
    final all = widget.allBranches;

    Widget muted(String s) => Text(s, style: DashType.body.copyWith(color: c.textMuted));

    Widget refText(PurchaseOrder po, {TextStyle? style}) => MadarClippedText(
      poReference(id: po.id, reference: po.reference),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textDirection: TextDirection.ltr,
      style: style ?? DashType.bodyMedium.copyWith(color: c.textPrimary),
    );

    Widget pill(PurchaseOrder po) => DashStatusPill(
      label: poStatusLabel(t, po.status),
      tone: poStatusTone(po.status),
    );

    final columns = <DashColumn<PurchaseOrder>>[
      DashColumn(
        id: 'reference',
        label: t('inventory.purchasing.reference'),
        text: (po) => poReference(id: po.id, reference: po.reference),
        cell: (context, po) => refText(po),
        phone: DashPhoneRole.title,
        minWidth: Space.xxl * 3,
        searchable: false,
      ),
      if (all)
        DashColumn(
          id: 'branch_name',
          label: t('inventory.purchasing.branch'),
          text: (po) => po.branchName ?? '—',
          minWidth: Space.xxl * 3,
          searchable: false,
        ),
      DashColumn(
        id: 'supplier_name',
        label: t('inventory.purchasing.supplier'),
        text: (po) => po.supplierName ?? '',
        cell: (context, po) => po.supplierName == null
            ? muted('—')
            : MadarClippedText(
                po.supplierName!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
        minWidth: Space.xxl * 4,
        searchable: false,
      ),
      DashColumn(
        id: 'status',
        label: t('inventory.purchasing.status'),
        text: (po) => poStatusLabel(t, po.status),
        cell: (context, po) => pill(po),
        minWidth: Space.xxl * 4 + Space.lg,
        searchable: false,
      ),
      DashColumn(
        id: 'expected_at',
        label: t('inventory.purchasing.expectedAt'),
        text: (po) => f.fmtDate(po.expectedAt),
        numeric: true,
        minWidth: Space.xxl * 3 + Space.sm,
        searchable: false,
      ),
      DashColumn(
        id: 'created_at',
        label: t('inventory.purchasing.createdAt'),
        text: (po) => f.fmtDate(po.createdAt),
        numeric: true,
        minWidth: Space.xxl * 3 + Space.sm,
        searchable: false,
      ),
    ];

    return DashDataTable<PurchaseOrder>(
      key: const ValueKey('po-table'),
      columns: columns,
      rows: rows,
      rowKey: (po) => po.id,
      loading: async.firstLoad,
      errorMessage: async.errorText(t),
      onRetry: () => ref.invalidate(purchaseOrdersProvider(widget.ordersKey)),
      empty: DashEmptyState(
        icon: 'truck',
        title: t('inventory.purchasing.noOrders'),
      ),
      onRowTap: _open,
      rowSemanticLabel: (po) => poReference(id: po.id, reference: po.reference),
      rowActions: (context, po) => Row(
        mainAxisSize: MainAxisSize.min,
        spacing: Space.xs,
        children: [..._buttons(t, po), _menu(t, po)],
      ),
      rowActionsWidth: _actionsWidth(context, t, rows),
      toolbar: DashSelect<String>(
        key: const ValueKey('po-status-filter'),
        options: [
          DashOption(
            value: allPoStatuses,
            label: t('inventory.purchasing.allStatuses'),
          ),
          for (final s in poStatuses)
            DashOption(value: s, label: poStatusLabel(t, s)),
        ],
        value: widget.status,
        onChanged: widget.onStatus,
        semanticLabel: t('inventory.purchasing.status'),
        expand: false,
        width: Space.xxl * 5 + Space.lg,
      ),
      rowCardBuilder: (context, po) {
        final buttons = _buttons(t, po);
        return DashCard(
          key: ValueKey('po-card-${po.id}'),
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: Space.sm,
            children: [
              Row(
                spacing: Space.sm,
                children: [
                  Expanded(
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: refText(
                        po,
                        style: DashType.sectionTitle.copyWith(
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  _menu(t, po),
                ],
              ),
              LabelValueGrid(
                entries: [
                  if (all)
                    (t('inventory.purchasing.branch'), Text(po.branchName ?? '—')),
                  (
                    t('inventory.purchasing.supplier'),
                    po.supplierName == null ? muted('—') : Text(po.supplierName!),
                  ),
                  (
                    t('inventory.purchasing.status'),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: pill(po),
                    ),
                  ),
                  (
                    t('inventory.purchasing.expectedAt'),
                    Text(
                      dashFigure(f.fmtDate(po.expectedAt)),
                      style: DashType.mono.copyWith(color: c.textPrimary),
                    ),
                  ),
                  (
                    t('inventory.purchasing.createdAt'),
                    Text(
                      dashFigure(f.fmtDate(po.createdAt)),
                      style: DashType.mono.copyWith(color: c.textPrimary),
                    ),
                  ),
                ],
              ),
              if (buttons.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: Space.xs),
                  child: Wrap(
                    spacing: Space.sm,
                    runSpacing: Space.sm,
                    children: buttons,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
