import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:feature_checkout/src/checkout_controller.dart';
import 'package:feature_checkout/src/receipt_paper.dart';
import 'package:feature_checkout/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Preview of any order's receipt with Print + Done actions — the sheet form
/// of the natives' ReceiptPreviewScreen (past-order reprint, "view receipt"
/// entry points). Present via `showMadarSheet`; Done / the close affordance
/// pop the sheet.
///
/// Print guards on the device's printer config: with no printer bound it
/// raises a warning toast instead of attempting the send (the natives'
/// printReceiptView), and reports success/failure the same way.
class ReceiptSheet extends StatefulWidget {
  const ReceiptSheet({
    required this.core,
    required this.onStateChanged,
    required this.receipt,
    super.key,
  });

  final MadarCore core;

  /// Screen-contract shell callback (printing moves no app state, so this
  /// is never fired here).
  final void Function() onStateChanged;

  /// The receipt to preview — a fresh checkout's result or a re-rendered
  /// past order (`bridge.orderReceiptView`).
  final ReceiptView receipt;

  @override
  State<ReceiptSheet> createState() => _ReceiptSheetState();
}

class _ReceiptSheetState extends State<ReceiptSheet> {
  MadarBridge get _bridge => widget.core.bridge;

  bool _printing = false;
  String? _orgLogoUrl;
  ToastData? _toast;
  int _toastSeq = 0;

  String _tr(String key) => _bridge.tr(key: key);

  String get _branchName => _bridge.deviceConfig().branchName ?? '';

  String get _currency => _bridge.currentSession()?.currencyCode ?? '';

  @override
  void initState() {
    super.initState();
    unawaited(_loadLogo());
  }

  Future<void> _loadLogo() async {
    try {
      final url = await _bridge.orgLogoUrl();
      if (mounted) setState(() => _orgLogoUrl = url);
    } on MadarError {
      // Best-effort — the paper renders without a brand mark.
    }
  }

  void _showToast(String text, {required ChipTone tone, String? icon}) {
    _toastSeq += 1;
    setState(() {
      _toast = ToastData(id: _toastSeq, text: text, tone: tone, icon: icon);
    });
  }

  /// Render the receipt in the core and stream it to the configured network
  /// printer — toast-driven feedback, no drawer kick (this is a preview /
  /// reprint surface).
  Future<void> _print() async {
    if (_printing) return;
    final config = _bridge.deviceConfig();
    final host = config.printerHost?.trim() ?? '';
    if (host.isEmpty) {
      _showToast(
        _tr('receipt.no_printer'),
        tone: ChipTone.warning,
        icon: 'exclamationmark.triangle',
      );
      return;
    }
    setState(() => _printing = true);
    try {
      final bytes = await _bridge.renderReceipt(
        receipt: widget.receipt,
        storeName: _branchName,
        currency: _currency,
        width: kReceiptChars,
        brand: printerBrandOf(config.printerBrand),
      );
      await _bridge.sendToPrinter(
        host: host,
        port: config.printerPort ?? kJetDirectPort,
        bytes: bytes,
      );
      if (mounted) {
        _showToast(
          _tr('receipt.printed'),
          tone: ChipTone.success,
          icon: 'checkmark.circle',
        );
      }
    } on Exception {
      if (mounted) {
        _showToast(
          _tr('receipt.print_failed'),
          tone: ChipTone.danger,
          icon: 'xmark.circle',
        );
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
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
                      _tr('receipt.title'),
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
                child: Center(
                  child: ReceiptPaper(
                    core: widget.core,
                    receipt: widget.receipt,
                    storeName: _branchName,
                    currency: _currency,
                    orgLogoUrl: _orgLogoUrl,
                  ),
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
                            label: _tr('receipt.print'),
                            icon: 'printer',
                            variant: ActionVariant.outline,
                            loading: _printing,
                            onTap: () => unawaited(_print()),
                          ),
                        ),
                        Expanded(
                          child: ActionButton(
                            label: _tr('order.done'),
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
          _toast,
          onDismiss: (id) {
            if (_toast?.id == id) setState(() => _toast = null);
          },
        ),
      ],
    );
  }
}
