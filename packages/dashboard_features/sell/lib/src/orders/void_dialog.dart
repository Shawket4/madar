/// The void dialog (the web's `features/orders/void-order-dialog.tsx`,
/// SELL-ORD-063 … SELL-ORD-069, SELL-ORD-088).
library;

import 'package:dashboard_api/dashboard_api.dart' show VoidOrderRequest;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/invalidate.dart';

const List<String> voidReasons = [
  'customer_request',
  'wrong_order',
  'quality_issue',
  'other',
];

/// What the dialog holds between openings, as the web's component state
/// does (SELL-ORD-088): Cancel keeps the reason and the note, even for
/// another order; only a void that went through resets them; the restore
/// switch always keeps its last value.
class VoidDraft {
  String reason = 'customer_request';
  String note = '';
  bool restore = true;
}

/// Opens the dialog for the order [orderId] (shown as [ref]).
Future<void> showVoidDialog(
  BuildContext context, {
  required String orderId,
  required String ref,
  required VoidDraft draft,
}) => showDashDialog<void>(
  context,
  builder: (_) =>
      VoidOrderDialog(orderId: orderId, orderRef: ref, draft: draft),
);

class VoidOrderDialog extends ConsumerStatefulWidget {
  const VoidOrderDialog({
    required this.orderId,
    required this.orderRef,
    required this.draft,
    super.key,
  });

  final String orderId;

  /// `order_ref`, else `#order_number`.
  final String orderRef;
  final VoidDraft draft;

  @override
  ConsumerState<VoidOrderDialog> createState() => _VoidOrderDialogState();
}

class _VoidOrderDialogState extends ConsumerState<VoidOrderDialog> {
  bool _busy = false;

  VoidDraft get d => widget.draft;

  bool get _noteMissing => d.reason == 'other' && d.note.trim().isEmpty;

  Future<void> _submit() async {
    if (_noteMissing || _busy) return;
    final t = ref.read(tProvider);
    // Captured first: the refresh happens even if the dialog closed meanwhile.
    final bus = ref.read(realtimeBusProvider);
    setState(() => _busy = true);
    try {
      final note = d.note.trim();
      await ref
          .read(apiProvider)
          .orders
          .voidOrder(
            orderId: widget.orderId,
            body: VoidOrderRequest(
              reason: d.reason,
              note: note.isEmpty ? null : note,
              restoreInventory: d.restore,
            ),
          );
      // `["/orders"]` and `["/orders/<id>"]`, nothing else.
      bus.invalidate(SellInvalidate.orderVoided(widget.orderId));
      d
        ..reason = 'customer_request'
        ..note = '';
      if (!mounted) return;
      DashToast.success(context, t('orders.voided'));
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (!mounted) return;
      DashToast.error(context, errorMessage(e, t));
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    return DashSurface(
      title: '${t('orders.voidTitle')} ${widget.orderRef}',
      description: t('orders.voidDesc'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          DashSelectField<String>(
            key: const ValueKey('void-reason'),
            label: t('orders.voidReason'),
            value: d.reason,
            options: [
              for (final r in voidReasons)
                DashOption(value: r, label: t('orders.voidReasons.$r')),
            ],
            onChanged: (v) => setState(() => d.reason = v),
          ),
          DashFormField<String>(
            key: const ValueKey('void-note'),
            label: t('orders.voidNote'),
            requiredMark: d.reason == 'other',
            errorText: _noteMissing ? t('orders.voidNoteRequired') : null,
            value: d.note,
            builder: (context, invalid) => DashTextInput(
              value: d.note,
              placeholder: t('orders.voidNotePh'),
              semanticLabel: t('orders.voidNote'),
              invalid: invalid,
              minLines: 3,
              maxLines: 3,
              onChanged: (v) => setState(() => d.note = v),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: Space.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.control),
              border: Border.all(color: c.hairline),
            ),
            child: DashSwitchField(
              key: const ValueKey('void-restore'),
              label: t('orders.restoreInventory'),
              value: d.restore,
              onChanged: (v) => setState(() => d.restore = v),
            ),
          ),
        ],
      ),
      actions: [
        DashButton(
          label: t('common.cancel'),
          variant: DashButtonVariant.outline,
          onPressed: () => Navigator.of(context).pop(),
        ),
        DashButton(
          key: const ValueKey('void-submit'),
          label: t('orders.void'),
          variant: DashButtonVariant.destructive,
          loading: _busy,
          onPressed: _noteMissing ? null : _submit,
        ),
      ],
    );
  }
}
