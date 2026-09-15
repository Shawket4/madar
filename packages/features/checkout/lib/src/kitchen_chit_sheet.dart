import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/src/receipt_printing.dart';
import 'package:feature_checkout/src/receipt_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// State of the kitchen chit preview — the print-in-flight flag and the
/// sheet's own toast.
@immutable
class ChitPreviewState {
  const ChitPreviewState({this.printing = false, this.toast});

  final bool printing;
  final ToastData? toast;
}

/// The chit preview's state holder — autoDispose, one per presented sheet.
/// [print] goes through [printCartLineChit], the same path as the cart line's
/// tap, then says how it went.
class ChitPreviewNotifier extends Notifier<ChitPreviewState> {
  bool _live = false;
  int _toastSeq = 0;

  @override
  ChitPreviewState build() {
    _live = true;
    ref.onDispose(() => _live = false);
    return const ChitPreviewState();
  }

  void _set(ChitPreviewState s) {
    if (_live) state = s;
  }

  /// Auto-dismiss callback for `ToastHost`.
  void dismissToast(int id) {
    if (state.toast?.id != id) return;
    _set(ChitPreviewState(printing: state.printing));
  }

  /// [tableId] and [lineKey] are only needed to clear that line's kitchen
  /// note once it actually prints — the print itself needs neither.
  Future<void> print(
    CartLineChit chit, {
    String? tableId,
    String? lineKey,
  }) async {
    if (state.printing) return;
    final bridge = ref.read(bridgeProvider);
    _set(ChitPreviewState(printing: true, toast: state.toast));
    final result = await printCartLineChit(
      bridge,
      ref.read(printerServiceProvider),
      chit,
    );
    if (result == PrintState.printed && lineKey != null) {
      await bridge.cartClearLineKitchenNote(tableId: tableId, lineKey: lineKey);
    }
    _toastSeq += 1;
    _set(
      ChitPreviewState(toast: chitPrintToast(bridge, result, id: _toastSeq)),
    );
  }
}

/// One chit preview session per presented sheet.
final NotifierProvider<ChitPreviewNotifier, ChitPreviewState>
chitPreviewProvider = NotifierProvider.autoDispose(ChitPreviewNotifier.new);

/// The toast a chit print answers with — shared by the cart line's tap and
/// the preview sheet, so the two say the same thing.
ToastData chitPrintToast(MadarBridge bridge, PrintState result, {int id = 0}) {
  String tr(String key) => bridge.tr(key: key);
  return switch (result) {
    PrintState.printed => ToastData(
      id: id,
      text: tr('printing.chit_sent'),
      tone: ChipTone.success,
      icon: 'printer',
    ),
    PrintState.noPrinter => ToastData(
      id: id,
      text: tr('printing.no_printer'),
      tone: ChipTone.warning,
      icon: 'printer',
    ),
    PrintState.failed || PrintState.idle || PrintState.printing => ToastData(
      id: id,
      text: tr('printing.failed'),
      tone: ChipTone.danger,
      icon: 'xmark.circle',
    ),
  };
}

/// Preview of one cart line's kitchen chit with Print + Done — the same
/// preview frame as the receipt. Pure-DATA param: the core-built [chit].
/// [tableId] and [lineKey] are only carried through to clear that line's
/// kitchen note once it actually prints from here.
class KitchenChitSheet extends ConsumerWidget {
  const KitchenChitSheet({
    required this.chit,
    this.tableId,
    this.lineKey,
    super.key,
  });

  final CartLineChit chit;
  final String? tableId;
  final String? lineKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    final preview = ref.watch(chitPreviewProvider);
    final notifier = ref.read(chitPreviewProvider.notifier);
    return PrintPreviewFrame(
      title: bridge.tr(key: 'printing.chit_preview'),
      printLabel: bridge.tr(key: 'printing.chit'),
      printing: preview.printing,
      onPrint: () =>
          unawaited(notifier.print(chit, tableId: tableId, lineKey: lineKey)),
      toast: preview.toast,
      onDismissToast: notifier.dismissToast,
      paper: Center(child: KitchenChitPaper(lines: chit.preview)),
    );
  }
}

/// State of the whole-cart kitchen chit preview — mirrors [ChitPreviewState].
@immutable
class CartChitPreviewState {
  const CartChitPreviewState({this.printing = false, this.toast});

  final bool printing;
  final ToastData? toast;
}

/// The whole-cart chit preview's state holder. [print] goes through
/// [printCartKitchenChit] and, on success, clears the cart-level note and
/// every printed line's own note — exactly what the cart-level tap does.
class CartChitPreviewNotifier extends Notifier<CartChitPreviewState> {
  bool _live = false;
  int _toastSeq = 0;

  @override
  CartChitPreviewState build() {
    _live = true;
    ref.onDispose(() => _live = false);
    return const CartChitPreviewState();
  }

  void _set(CartChitPreviewState s) {
    if (_live) state = s;
  }

  void dismissToast(int id) {
    if (state.toast?.id != id) return;
    _set(CartChitPreviewState(printing: state.printing));
  }

  Future<void> print(CartKitchenChit chit, {String? tableId}) async {
    if (state.printing) return;
    final bridge = ref.read(bridgeProvider);
    _set(CartChitPreviewState(printing: true, toast: state.toast));
    final result = await printCartKitchenChit(
      ref.read(printerServiceProvider),
      chit,
    );
    // "The cart-level note and the printed rows' notes" — every row in THIS
    // chit was every row in the cart at build time, so clearing the
    // cart-level note plus every current line's note is exactly that.
    if (result == PrintState.printed) {
      await bridge.cartClearAllKitchenNotes(tableId: tableId);
    }
    _toastSeq += 1;
    _set(
      CartChitPreviewState(
        toast: chitPrintToast(bridge, result, id: _toastSeq),
      ),
    );
  }
}

/// One whole-cart chit preview session per presented sheet.
final NotifierProvider<CartChitPreviewNotifier, CartChitPreviewState>
cartChitPreviewProvider = NotifierProvider.autoDispose(
  CartChitPreviewNotifier.new,
);

/// Preview of the WHOLE cart's kitchen chit with Print + Done. Pure-DATA
/// params: the core-built [chit] and the [tableId] it was built for (only to
/// clear notes on print).
class CartKitchenChitSheet extends ConsumerWidget {
  const CartKitchenChitSheet({required this.chit, this.tableId, super.key});

  final CartKitchenChit chit;
  final String? tableId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    final preview = ref.watch(cartChitPreviewProvider);
    final notifier = ref.read(cartChitPreviewProvider.notifier);
    return PrintPreviewFrame(
      title: bridge.tr(key: 'printing.cart_chit_preview'),
      printLabel: bridge.tr(key: 'printing.cart_chit'),
      printing: preview.printing,
      onPrint: () => unawaited(notifier.print(chit, tableId: tableId)),
      toast: preview.toast,
      onDismissToast: notifier.dismissToast,
      paper: Center(child: KitchenChitPaper(lines: chit.preview)),
    );
  }
}

/// Paper metrics — the receipt paper's card.
const double _paperMaxWidth = 360;
const double _paperRadius = 10;
const double _paperPad = 18;

/// The chit on white paper: the core's lines, as they print.
class KitchenChitPaper extends StatelessWidget {
  const KitchenChitPaper({required this.lines, super.key});

  final List<ChitLineView> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: _paperMaxWidth),
      padding: const EdgeInsetsDirectional.all(_paperPad),
      decoration: BoxDecoration(
        color: Paper.paper,
        borderRadius: BorderRadius.circular(_paperRadius),
        border: Border.all(color: Paper.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.xs,
        children: [
          for (final l in lines)
            Text(
              l.text,
              textAlign: l.centered ? TextAlign.center : TextAlign.start,
              maxLines: 1,
              overflow: TextOverflow.clip,
              softWrap: false,
              style: (l.large ? MadarType.h3 : MadarType.bodySm).copyWith(
                color: Paper.ink,
                fontWeight: l.bold ? FontWeight.w800 : FontWeight.w400,
              ),
            ),
        ],
      ),
    );
  }
}
