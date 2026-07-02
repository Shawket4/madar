import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:feature_checkout/src/checkout_controller.dart';
import 'package:feature_checkout/src/checkout_drawer.dart';
import 'package:feature_checkout/src/receipt_paper.dart';
import 'package:feature_checkout/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:rust_bridge/rust_bridge.dart';

// Native metrics (TenderScreen.kt ReceiptConfirmation) kept verbatim.

/// Status glyph atop the confirmation (natives: 44.dp).
const double _statusIconSize = 44;

/// "Order placed" headline size (natives: 22.sp Black).
const double _placedTitleSize = 22;

/// Tender — THE checkout drawer, presented via
/// `showMadarSheet(size: SheetSize.large)`. Pick a payment method, take cash
/// (with live change), tip, discount, and place the order through the core
/// (online or queued offline). On success the same sheet flips to a receipt
/// confirmation; dismissing the confirmation returns the [ReceiptView] as
/// the sheet result. Port of the natives' TenderOverlay / TenderForm.
///
/// ```dart
/// final receipt = await showMadarSheet<ReceiptView>(
///   context,
///   size: SheetSize.large,
///   builder: (_) => TenderSheet(core: core, onStateChanged: onStateChanged),
/// );
/// ```
class TenderSheet extends StatefulWidget {
  const TenderSheet({
    required this.core,
    required this.onStateChanged,
    super.key,
  });

  final MadarCore core;

  /// Fired after a successful checkout (the cart empties and the shift
  /// stats/history move).
  final void Function() onStateChanged;

  @override
  State<TenderSheet> createState() => _TenderSheetState();
}

class _TenderSheetState extends State<TenderSheet> {
  late final CheckoutController _model;

  @override
  void initState() {
    super.initState();
    _model = CheckoutController(
      core: widget.core,
      onStateChanged: widget.onStateChanged,
    );
    unawaited(_model.init());
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _model,
      builder: (context, _) {
        final receipt = _model.receipt;
        if (receipt != null) {
          return _ReceiptConfirmation(
            model: _model,
            receipt: receipt,
            onDone: () => unawaited(Navigator.of(context).maybePop(receipt)),
          );
        }
        final totals = _model.cartTotals;
        return CheckoutDrawer(
          controller: _model,
          summary: CheckoutSummary(
            subtotalMinor: totals.subtotalMinor,
            discountMinor: totals.discountMinor,
            taxMinor: totals.taxMinor,
            totalMinor: totals.totalMinor,
          ),
          title: _model.tr('order.tender'),
          terminalLabel: _model.tr('order.place_order'),
          terminalIcon: 'checkmark',
          placing: _model.isPlacingOrder,
          showDiscountPicker: true,
          showCustomerFields: true,
          onClose: () => unawaited(Navigator.of(context).maybePop()),
          onTerminal: (result) => unawaited(_model.placeOrder(result)),
        );
      },
    );
  }
}

/// The post-checkout confirmation: fixed status header · scrolling receipt ·
/// pinned footer — so the print controls + New Order stay reachable however
/// long the receipt is. Mirrors the natives' ReceiptConfirmation.
class _ReceiptConfirmation extends StatelessWidget {
  const _ReceiptConfirmation({
    required this.model,
    required this.receipt,
    required this.onDone,
  });

  final CheckoutController model;
  final ReceiptView receipt;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final queued = receipt.queuedOffline;
    return Column(
      children: [
        // ── Fixed status header ──
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: Space.xl,
            vertical: Space.lg,
          ),
          child: Column(
            spacing: Space.sm,
            children: [
              MadarIcon(
                queued ? 'clock' : 'checkmark.circle',
                tint: queued ? colors.warning : colors.success,
                size: _statusIconSize,
              ),
              Text(
                model.tr('order.order_placed'),
                style: MadarType.h2.copyWith(
                  fontSize: _placedTitleSize,
                  fontWeight: FontWeight.w900,
                  color: colors.textPrimary,
                ),
              ),
              StatusChip(
                label: model.tr(
                  queued ? 'order.queued_hint' : 'order.sent_hint',
                ),
                tone: queued ? ChipTone.warning : ChipTone.success,
                icon: queued ? 'clock' : 'checkmark.circle',
              ),
            ],
          ),
        ),
        // ── Scrolling receipt (only the paper scrolls) ──
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: Space.xl,
            ),
            child: Center(
              child: ReceiptPaper(
                core: model.core,
                receipt: receipt,
                storeName: model.branchName,
                currency: model.currency,
                orgLogoUrl: model.orgLogoUrl,
              ),
            ),
          ),
        ),
        // ── Pinned footer (surface + top hairline): print status + actions ──
        ColoredBox(
          color: colors.surface,
          child: Column(
            children: [
              const Hairline(),
              Padding(
                padding: const EdgeInsetsDirectional.all(Space.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: Space.sm,
                  children: [
                    switch (model.printState) {
                      PrintState.printed => Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: StatusChip(
                          label: model.tr('receipt.printed'),
                          tone: ChipTone.success,
                          icon: 'checkmark.circle',
                        ),
                      ),
                      PrintState.noPrinter => Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: StatusChip(
                          label: model.tr('receipt.no_printer'),
                          tone: ChipTone.warning,
                          icon: 'exclamationmark.triangle',
                        ),
                      ),
                      PrintState.failed => Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: StatusChip(
                          label: model.tr('receipt.print_failed'),
                          tone: ChipTone.danger,
                          icon: 'exclamationmark.triangle',
                        ),
                      ),
                      PrintState.idle ||
                      PrintState.printing => const SizedBox.shrink(),
                    },
                    Row(
                      spacing: Space.sm,
                      children: [
                        Expanded(
                          child: ActionButton(
                            label: model.tr('receipt.reprint'),
                            icon: 'printer',
                            variant: ActionVariant.outline,
                            loading: model.printState == PrintState.printing,
                            onTap: () => unawaited(
                              model.printReceipt(kickDrawer: false),
                            ),
                          ),
                        ),
                        Expanded(
                          child: ActionButton(
                            label: model.tr('order.new_order'),
                            icon: 'plus',
                            onTap: onDone,
                          ),
                        ),
                      ],
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
