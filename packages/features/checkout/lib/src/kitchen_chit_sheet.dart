import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/src/receipt_printing.dart';
import 'package:feature_checkout/src/receipt_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// State of the kitchen chit preview — the print-in-flight flag. How the
/// print went is said through the app's one toast ([sayChitPrint]), so it is
/// seen even when the sheet has closed by the time the printer answers.
@immutable
class ChitPreviewState {
  const ChitPreviewState({this.printing = false});

  final bool printing;
}

/// The chit preview's state holder — autoDispose, one per presented sheet.
/// [print] goes through [printCartLineChit], the same path as the cart line's
/// tap, then says how it went.
class ChitPreviewNotifier extends Notifier<ChitPreviewState> {
  bool _live = false;

  @override
  ChitPreviewState build() {
    _live = true;
    ref.onDispose(() => _live = false);
    return const ChitPreviewState();
  }

  void _set(ChitPreviewState s) {
    if (_live) state = s;
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
    final toasts = ref.read(appToastProvider.notifier);
    _set(const ChitPreviewState(printing: true));
    final result = await printCartLineChit(
      bridge,
      ref.read(printerServiceProvider),
      chit,
    );
    if (result == PrintState.printed && lineKey != null) {
      await bridge.cartClearLineKitchenNote(tableId: tableId, lineKey: lineKey);
    }
    _set(const ChitPreviewState());
    sayChitPrint(toasts, bridge, result);
  }
}

/// One chit preview session per presented sheet.
final NotifierProvider<ChitPreviewNotifier, ChitPreviewState>
chitPreviewProvider = NotifierProvider.autoDispose(ChitPreviewNotifier.new);

/// Say how a chit print went, through the app's one toast — shared by the
/// cart line's tap, the cart's chit and the preview sheets, so they all say
/// the same thing.
void sayChitPrint(
  AppToastNotifier toasts,
  MadarBridge bridge,
  PrintState result,
) {
  String tr(String key) => bridge.tr(key: key);
  switch (result) {
    case PrintState.printed:
      toasts.show(
        tr('printing.chit_sent'),
        tone: ChipTone.success,
        icon: 'printer',
      );
    case PrintState.noPrinter:
      toasts.show(
        tr('printing.no_printer'),
        tone: ChipTone.warning,
        icon: 'printer',
      );
    case PrintState.failed || PrintState.idle || PrintState.printing:
      toasts.show(
        tr('printing.failed'),
        tone: ChipTone.danger,
        icon: 'xmark.circle',
      );
  }
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
      paper: Center(child: KitchenChitPaper(lines: chit.preview)),
    );
  }
}

/// State of the whole-cart kitchen chit preview — mirrors [ChitPreviewState].
@immutable
class CartChitPreviewState {
  const CartChitPreviewState({this.printing = false});

  final bool printing;
}

/// The whole-cart chit preview's state holder. [print] goes through
/// [printCartKitchenChit] and, on success, clears the cart-level note and
/// every printed line's own note — exactly what the cart-level tap does.
class CartChitPreviewNotifier extends Notifier<CartChitPreviewState> {
  bool _live = false;

  @override
  CartChitPreviewState build() {
    _live = true;
    ref.onDispose(() => _live = false);
    return const CartChitPreviewState();
  }

  void _set(CartChitPreviewState s) {
    if (_live) state = s;
  }

  Future<void> print(CartKitchenChit chit, {String? tableId}) async {
    if (state.printing) return;
    final bridge = ref.read(bridgeProvider);
    final toasts = ref.read(appToastProvider.notifier);
    _set(const CartChitPreviewState(printing: true));
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
    _set(const CartChitPreviewState());
    sayChitPrint(toasts, bridge, result);
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
