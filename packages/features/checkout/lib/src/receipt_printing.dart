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
