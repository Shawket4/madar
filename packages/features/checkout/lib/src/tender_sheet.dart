import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/src/checkout_drawer.dart';
import 'package:feature_checkout/src/checkout_provider.dart';
import 'package:feature_checkout/src/receipt_paper.dart';
import 'package:feature_checkout/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
/// Owns its [checkoutProvider] session (autoDispose — starts the cart
/// session on mount, resets on dismiss):
///
/// ```dart
/// final receipt = await showMadarSheet<ReceiptView>(
///   context,
///   size: SheetSize.large,
///   builder: (_) => const TenderSheet(),
/// );
/// ```
class TenderSheet extends ConsumerStatefulWidget {
  const TenderSheet({super.key});

  @override
  ConsumerState<TenderSheet> createState() => _TenderSheetState();
}

class _TenderSheetState extends ConsumerState<TenderSheet> {
  @override
  void initState() {
    super.initState();
    // Kicks the fresh autoDispose session; the first state write lands
    // after the loads (post-frame), so this is build-safe.
    unawaited(ref.read(checkoutProvider.notifier).startCart());
  }

  @override
  Widget build(BuildContext context) {
    final bridge = ref.watch(bridgeProvider);
    final receipt = ref.watch(checkoutProvider.select((s) => s.receipt));
    if (receipt != null) {
      return _ReceiptConfirmation(
        receipt: receipt,
        onDone: () => unawaited(Navigator.of(context).maybePop(receipt)),
      );
    }
    // No `placing` override — the drawer watches the session's own
    // isPlacingOrder.
    return CheckoutDrawer(
      title: bridge.tr(key: 'order.tender'),
      terminalLabel: bridge.tr(key: 'order.place_order'),
      terminalIcon: 'checkmark',
      showDiscountPicker: true,
      showCustomerFields: true,
      onClose: () => unawaited(Navigator.of(context).maybePop()),
      onTerminal: (result) =>
          unawaited(ref.read(checkoutProvider.notifier).placeOrder(result)),
    );
  }
}

/// The post-checkout confirmation: fixed status header · scrolling receipt ·
/// pinned footer — so the print controls + New Order stay reachable however
/// long the receipt is. Mirrors the natives' ReceiptConfirmation.
class _ReceiptConfirmation extends ConsumerWidget {
  const _ReceiptConfirmation({
    required this.receipt,
    required this.onDone,
  });

  final ReceiptView receipt;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    String tr(String key) => bridge.tr(key: key);
    final printState = ref.watch(
      checkoutProvider.select((s) => s.printState),
    );
    final branchName = ref.watch(
      checkoutProvider.select((s) => s.branchName),
    );
    final currency = ref.watch(checkoutProvider.select((s) => s.currency));
    final orgLogoUrl = ref.watch(
      checkoutProvider.select((s) => s.orgLogoUrl),
    );
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
                tr('order.order_placed'),
                style: MadarType.h2.copyWith(
                  fontSize: _placedTitleSize,
                  fontWeight: FontWeight.w900,
                  color: colors.textPrimary,
                ),
              ),
              StatusChip(
                label: tr(queued ? 'order.queued_hint' : 'order.sent_hint'),
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
                receipt: receipt,
                storeName: branchName,
                currency: currency,
                orgLogoUrl: orgLogoUrl,
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
                    switch (printState) {
                      PrintState.printed => Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: StatusChip(
                          label: tr('receipt.printed'),
                          tone: ChipTone.success,
                          icon: 'checkmark.circle',
                        ),
                      ),
                      PrintState.noPrinter => Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: StatusChip(
                          label: tr('receipt.no_printer'),
                          tone: ChipTone.warning,
                          icon: 'exclamationmark.triangle',
                        ),
                      ),
                      PrintState.failed => Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: StatusChip(
                          label: tr('receipt.print_failed'),
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
                            label: tr('receipt.reprint'),
                            icon: 'printer',
                            variant: ActionVariant.outline,
                            loading: printState == PrintState.printing,
                            onTap: () => unawaited(
                              ref
                                  .read(checkoutProvider.notifier)
                                  .printReceipt(kickDrawer: false),
                            ),
                          ),
                        ),
                        Expanded(
                          child: ActionButton(
                            label: tr('order.new_order'),
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
