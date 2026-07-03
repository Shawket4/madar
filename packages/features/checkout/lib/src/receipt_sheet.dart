import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/src/checkout_provider.dart';
import 'package:feature_checkout/src/receipt_paper.dart';
import 'package:feature_checkout/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// State of the receipt preview sheet — the print-in-flight flag, the
/// core-cached org logo path, and the local toast feedback.
@immutable
class ReceiptPreviewState {
  const ReceiptPreviewState({
    this.printing = false,
    this.orgLogoPath,
    this.toast,
  });

  final bool printing;
  final String? orgLogoPath;
  final ToastData? toast;

  ReceiptPreviewState copyWith({
    bool? printing,
    String? orgLogoPath,
    ToastData? toast,
    bool clearToast = false,
  }) {
    return ReceiptPreviewState(
      printing: printing ?? this.printing,
      orgLogoPath: orgLogoPath ?? this.orgLogoPath,
      toast: clearToast ? null : (toast ?? this.toast),
    );
  }
}

/// The receipt preview's state holder — autoDispose so every presented
/// preview starts fresh. Loads the org logo on build; [print] streams the
/// receipt to the configured printer with toast feedback (no drawer kick —
/// this is a preview / reprint surface, the natives' printReceiptView).
class ReceiptPreviewNotifier extends Notifier<ReceiptPreviewState> {
  bool _live = false;
  int _toastSeq = 0;

  @override
  ReceiptPreviewState build() {
    _live = true;
    ref.onDispose(() => _live = false);
    _loadLogo();
    return const ReceiptPreviewState();
  }

  MadarBridge get _bridge => ref.read(bridgeProvider);

  void _update(ReceiptPreviewState Function(ReceiptPreviewState s) transform) {
    if (_live) state = transform(state);
  }

  void _loadLogo() {
    // Core-cached local file (downloaded during refresh_catalog's image
    // phase) — a cheap sync read; the paper renders without a brand mark
    // until the first successful sync.
    _update((s) => s.copyWith(orgLogoPath: _bridge.orgLogoLocalPath()));
  }

  void _toast(String text, {required ChipTone tone, String? icon}) {
    _toastSeq += 1;
    _update(
      (s) => s.copyWith(
        toast: ToastData(id: _toastSeq, text: text, tone: tone, icon: icon),
      ),
    );
  }

  /// Auto-dismiss callback for `ToastHost`.
  void dismissToast(int id) {
    if (state.toast?.id != id) return;
    _update((s) => s.copyWith(clearToast: true));
  }

  /// Render [receipt] in the core and stream it to the configured network
  /// printer. Guards on the device's printer config: with no printer bound
  /// it raises a warning toast instead of attempting the send.
  Future<void> print(ReceiptView receipt) async {
    if (state.printing) return;
    final bridge = _bridge;
    String tr(String key) => bridge.tr(key: key);
    final config = bridge.deviceConfig();
    final host = config.printerHost?.trim() ?? '';
    if (host.isEmpty) {
      _toast(
        tr('receipt.no_printer'),
        tone: ChipTone.warning,
        icon: 'exclamationmark.triangle',
      );
      return;
    }
    _update((s) => s.copyWith(printing: true));
    try {
      final bytes = await bridge.renderReceipt(
        receipt: receipt,
        storeName: bridge.deviceConfig().branchName ?? '',
        currency: bridge.currentSession()?.currencyCode ?? '',
        width: kReceiptChars,
        brand: printerBrandOf(config.printerBrand),
      );
      await bridge.sendToPrinter(
        host: host,
        port: config.printerPort ?? kJetDirectPort,
        bytes: bytes,
      );
      _toast(
        tr('receipt.printed'),
        tone: ChipTone.success,
        icon: 'checkmark.circle',
      );
    } on Exception {
      _toast(
        tr('receipt.print_failed'),
        tone: ChipTone.danger,
        icon: 'xmark.circle',
      );
    } finally {
      _update((s) => s.copyWith(printing: false));
    }
  }
}

/// One preview session per presented sheet.
final NotifierProvider<ReceiptPreviewNotifier, ReceiptPreviewState>
receiptPreviewProvider = NotifierProvider.autoDispose(
  ReceiptPreviewNotifier.new,
);

/// Preview of any order's receipt with Print + Done actions — the sheet form
/// of the natives' ReceiptPreviewScreen (past-order reprint, "view receipt"
/// entry points). Present via `showMadarSheet`; Done / the close affordance
/// pop the sheet. Pure-DATA param: the [receipt] to preview — a fresh
/// checkout's result or a re-rendered past order
/// (`bridge.orderReceiptView`).
class ReceiptSheet extends ConsumerWidget {
  const ReceiptSheet({
    required this.receipt,
    this.celebrate = false,
    super.key,
  });

  /// The receipt to preview.
  final ReceiptView receipt;

  /// True when the sheet presents a JUST-completed payment (e.g. a delivery
  /// finalize) — plays the one-shot [SettleMark] celebration above the paper
  /// on mount. Leave false for reprints / history previews.
  final bool celebrate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    String tr(String key) => bridge.tr(key: key);
    final preview = ref.watch(receiptPreviewProvider);
    final branchName = bridge.deviceConfig().branchName ?? '';
    final currency = bridge.currentSession()?.currencyCode ?? '';
    return Stack(
      children: [
        Column(
          children: [
            // Sticky header — title + close (natives' preview header).
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: Space.lg,
                vertical: Space.md,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tr('receipt.title'),
                      style: MadarType.h3.copyWith(
                        fontWeight: FontWeight.w900,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  TactileScale(
                    onTap: () => unawaited(Navigator.of(context).maybePop()),
                    child: Container(
                      width: Metrics.closeButton,
                      height: Metrics.closeButton,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colors.surfaceAlt,
                        shape: BoxShape.circle,
                      ),
                      child: MadarIcon(
                        'xmark',
                        tint: colors.textMuted,
                        size: IconSize.sm,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Hairline(),
            // Scrolling paper — centered like the natives' preview.
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsetsDirectional.all(Space.lg),
                child: Column(
                  children: [
                    // One-shot settle celebration — just-paid presentations
                    // only, never reprints (plays once on mount).
                    if (celebrate)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          bottom: Space.lg,
                        ),
                        child: SettleMark(
                          label: tr('receipt.settled'),
                        ),
                      ),
                    Center(
                      child: ReceiptPaper(
                        receipt: receipt,
                        storeName: branchName,
                        currency: currency,
                        orgLogoPath: preview.orgLogoPath,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Pinned actions — Print + Done.
            ColoredBox(
              color: colors.surface,
              child: Column(
                children: [
                  const Hairline(),
                  Padding(
                    padding: const EdgeInsetsDirectional.all(Space.lg),
                    child: Row(
                      spacing: Space.sm,
                      children: [
                        Expanded(
                          child: ActionButton(
                            label: tr('receipt.print'),
                            icon: 'printer',
                            variant: ActionVariant.outline,
                            loading: preview.printing,
                            onTap: () => unawaited(
                              ref
                                  .read(receiptPreviewProvider.notifier)
                                  .print(receipt),
                            ),
                          ),
                        ),
                        Expanded(
                          child: ActionButton(
                            label: tr('order.done'),
                            icon: 'checkmark',
                            onTap: () =>
                                unawaited(Navigator.of(context).maybePop()),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        // Local toast layer — the sheet floats above the screen's host, so
        // print feedback presents inside the sheet itself.
        ToastHost(
          preview.toast,
          onDismiss: ref.read(receiptPreviewProvider.notifier).dismissToast,
        ),
      ],
    );
  }
}
