import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Thermal receipt width in characters — the natives' `32u` raster width.
const int kReceiptChars = 32;

/// How long a print may take before it is reported as failed. A printer that
/// accepts the connection and then never answers used to hold "Printing…" on
/// the Done card forever.
const Duration kPrintTimeout = Duration(seconds: 15);

/// Print lifecycle of a receipt — the natives' `PrintState`.
enum PrintState { idle, printing, printed, failed, noPrinter }

/// Device-config brand string (`epson`/`star`) → [PrinterBrand]; anything
/// else falls back to Epson (the natives' default dialect).
PrinterBrand printerBrandOf(String? brand) =>
    brand == 'star' ? PrinterBrand.star : PrinterBrand.epson;

/// Render [receipt] in the core and stream it to the bound printer.
///
/// One function because two things print a receipt — the Charge session the
/// moment the sale lands, and the Done card's Reprint after the session is
/// gone — and they must behave identically: same width, same brand, same
/// "no printer" answer. Returns the resulting state; never throws, because
/// printing never gates money.
///
/// [kickDrawer] pops the till on a cash sale. Only the first print passes
/// it; a reprint must not open the drawer again.
Future<PrintState> printReceiptView(
  MadarBridge bridge,
  PrinterService printer,
  ReceiptView receipt, {
  required bool kickDrawer,
  Duration timeout = kPrintTimeout,
}) async {
  try {
    final tx = printer.activeTransport();
    if (tx == null) return PrintState.noPrinter;
    final config = bridge.deviceConfig();
    final brand = printerBrandOf(config.printerBrand);
    return await () async {
      final bytes = await bridge.renderReceipt(
        receipt: receipt,
        storeName: config.branchName ?? '',
        currency: bridge.currentSession()?.currencyCode ?? '',
        width: kReceiptChars,
        brand: brand,
      );
      await tx.send(bytes);
      if (kickDrawer && receipt.isCash) {
        // Best-effort — a drawer that fails to open must not mark the receipt
        // (already printed) as failed, whatever the transport throws.
        try {
          await tx.send(await bridge.cashDrawerKick(brand: brand));
        } on Object {
          // ignored: the receipt printed; the kick is a bonus.
        }
      }
      return PrintState.printed;
    }().timeout(timeout);
    // Every failure, not only `Exception`s: a platform channel can throw an
    // `Error`, and one that escaped left the card printing forever.
    // ignore: avoid_catches_without_on_clauses
  } catch (_) {
    return PrintState.failed;
  }
}

/// Build ONE cart line's kitchen chit in the core — the chit renderer, the
/// station-then-till routing, the preview lines — at the receipt width and the
/// till printer's brand (a station printer's own brand wins in the core).
Future<CartLineChit> buildCartLineChit(
  MadarBridge bridge, {
  required String? tableId,
  required String lineKey,
  String? tableLabel,
  String? ticketRef,
}) => bridge.cartLineChit(
  tableId: tableId,
  lineKey: lineKey,
  tableLabel: tableLabel,
  ticketRef: ticketRef,
  width: kReceiptChars,
  tillBrand: printerBrandOf(bridge.deviceConfig().printerBrand),
);

/// Send a built [chit] to the printer the core routed it to: its station's
/// LAN printer, or the device's till printer when `target.host` is null.
///
/// The one print path for a cart line's chit — the per-line button's tap and
/// the preview sheet's Print both come through here, with the receipt's
/// timeout and the same "never throws" answer.
Future<PrintState> printCartLineChit(
  MadarBridge bridge,
  PrinterService printer,
  CartLineChit chit, {
  Duration timeout = kPrintTimeout,
}) async {
  try {
    final host = chit.target.host;
    if (host == null) {
      final tx = printer.activeTransport();
      if (tx == null) return PrintState.noPrinter;
      await tx.send(chit.bytes).timeout(timeout);
    } else {
      await bridge
          .sendToPrinter(host: host, port: chit.target.port!, bytes: chit.bytes)
          .timeout(timeout);
    }
    return PrintState.printed;
    // Every failure, as printReceiptView: a platform channel can throw an
    // `Error`, and printing never gates anything.
    // ignore: avoid_catches_without_on_clauses
  } catch (_) {
    return PrintState.failed;
  }
}

/// Build the WHOLE cart's kitchen chit — every line's own chit, one after
/// another, plus the cart-level kitchen note — for the cart-level print
/// button / preview sheet.
Future<CartKitchenChit> buildCartKitchenChit(
  MadarBridge bridge, {
  required String? tableId,
  String? tableLabel,
  String? ticketRef,
}) => bridge.cartKitchenChit(
  tableId: tableId,
  tableLabel: tableLabel,
  ticketRef: ticketRef,
  width: kReceiptChars,
  tillBrand: printerBrandOf(bridge.deviceConfig().printerBrand),
);

/// Print the WHOLE cart's kitchen chit — always to the device's own till
/// printer (a whole-cart copy is a manual/backup pass, not per-station
/// routing). Same timeout and "never throws" contract as [printCartLineChit].
Future<PrintState> printCartKitchenChit(
  PrinterService printer,
  CartKitchenChit chit, {
  Duration timeout = kPrintTimeout,
}) async {
  try {
    final tx = printer.activeTransport();
    if (tx == null) return PrintState.noPrinter;
    await tx.send(chit.bytes).timeout(timeout);
    return PrintState.printed;
    // Every failure, not only `Exception`s: a platform channel can throw an
    // `Error`, and printing must never gate anything by throwing out of here.
    // ignore: avoid_catches_without_on_clauses
  } catch (_) {
    return PrintState.failed;
  }
}
