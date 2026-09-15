import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/src/receipt_paper.dart';
import 'package:feature_checkout/src/receipt_printing.dart';
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
    // Seed the logo IN the initial state — writing `state` during build()
    // throws (it briefly rendered the reprint sheet blank), and the local
    // path is a cheap sync read anyway.
    return ReceiptPreviewState(
      orgLogoPath: ref.read(bridgeProvider).orgLogoLocalPath(),
    );
  }

  MadarBridge get _bridge => ref.read(bridgeProvider);

  void _update(ReceiptPreviewState Function(ReceiptPreviewState s) transform) {
    if (_live) state = transform(state);
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

  /// Print [receipt] through the one shared print path ([printReceiptView]:
  /// same width, brand, timeout and failure handling as the Charge's
  /// auto-print), then say how it went. No drawer kick — this is a preview /
  /// reprint surface.
  Future<void> print(ReceiptView receipt) async {
    if (state.printing) return;
    final bridge = _bridge;
    String tr(String key) => bridge.tr(key: key);
    _update((s) => s.copyWith(printing: true));
    final result = await printReceiptView(
      bridge,
      ref.read(printerServiceProvider),
      receipt,
      kickDrawer: false,
    );
    switch (result) {
      case PrintState.noPrinter:
        _toast(
          tr('receipt.no_printer'),
          tone: ChipTone.warning,
          icon: 'exclamationmark.triangle',
        );
      case PrintState.printed:
        _toast(
          tr('receipt.printed'),
          tone: ChipTone.success,
          icon: 'checkmark.circle',
        );
      case PrintState.failed || PrintState.idle || PrintState.printing:
        _toast(
          tr('receipt.print_failed'),
          tone: ChipTone.danger,
          icon: 'xmark.circle',
        );
    }
    _update((s) => s.copyWith(printing: false));
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
    final bridge = ref.bridge;
    String tr(String key) => bridge.tr(key: key);
    final preview = ref.watch(receiptPreviewProvider);
    final branchName = bridge.deviceConfig().branchName ?? '';
    final currency = bridge.currentSession()?.currencyCode ?? '';
    return PrintPreviewFrame(
      title: tr('receipt.title'),
      printLabel: tr('receipt.print'),
      printing: preview.printing,
      onPrint: () =>
          unawaited(ref.read(receiptPreviewProvider.notifier).print(receipt)),
      toast: preview.toast,
      onDismissToast: ref.read(receiptPreviewProvider.notifier).dismissToast,
      paper: Column(
        children: [
          // One-shot settle celebration — just-paid presentations
          // only, never reprints (plays once on mount).
          if (celebrate)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: Space.lg),
              child: SettleMark(label: tr('receipt.settled')),
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
    );
  }
}

/// The print preview sheet's frame — sticky title + close, the scrolling
/// paper, pinned Print + Done, and a local toast layer. Shared by every
/// print preview (a receipt, a kitchen chit) so they cannot drift apart.
class PrintPreviewFrame extends ConsumerWidget {
  const PrintPreviewFrame({
    required this.title,
    required this.printLabel,
    required this.printing,
    required this.onPrint,
    required this.paper,
    required this.toast,
    required this.onDismissToast,
    super.key,
  });

  final String title;
  final String printLabel;
  final bool printing;
  final VoidCallback onPrint;
  final Widget paper;
  final ToastData? toast;
  final ValueChanged<int> onDismissToast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    String tr(String key) => ref.bridge.tr(key: key);
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
                      title,
                      style: MadarType.h3.copyWith(
                        fontWeight: FontWeight.w900,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  TactileScale(
                    onTap: () => Navigator.of(context).maybePop(),
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
            const MadarHairline(),
            // Scrolling paper — centered like the natives' preview.
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsetsDirectional.all(Space.lg),
                child: paper,
              ),
            ),
            // Pinned actions — Print + Done.
            ColoredBox(
              color: colors.surface,
              child: Column(
                children: [
                  const MadarHairline(),
                  Padding(
                    padding: const EdgeInsetsDirectional.all(Space.lg),
                    child: Row(
                      spacing: Space.sm,
                      children: [
                        Expanded(
                          child: MadarButton(
                            label: printLabel,
                            icon: 'printer',
                            variant: MadarButtonVariant.outline,
                            loading: printing,
                            onTap: onPrint,
                          ),
                        ),
                        Expanded(
                          child: MadarButton(
                            label: tr('order.done'),
                            icon: 'checkmark',
                            onTap: () => Navigator.of(context).maybePop(),
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
        ToastHost(toast, onDismiss: onDismissToast),
      ],
    );
  }
}
