/// The provider-agnostic print transport boundary.
///
/// The Rust core produces the COMPLETE ESC/POS buffer — layout, Arabic as a
/// raster image, the cut, the cash-drawer kick — and hands Dart a `Uint8List`.
/// A [PrinterTransport] is a dumb pipe: it opens its link and writes those
/// bytes UNCHANGED. Bluetooth is the transport today; raw-TCP/Wi‑Fi is another;
/// a new one drops in behind this interface without touching the core or any
/// call site.
library;

import 'dart:typed_data';

/// A destination for pre-rendered ESC/POS bytes. Implementations connect on
/// demand and transmit the bytes verbatim — they never generate tickets, text,
/// or images of their own (that would fight the core's output).
// One method by design: this is the transport strategy seam (Bluetooth, TCP,
// and future providers), not a candidate for a top-level function.
// ignore: one_member_abstracts
abstract interface class PrinterTransport {
  /// Transmit a complete ESC/POS buffer, connecting if needed. Throws on any
  /// failure (not connected, out of range, out of paper, write rejected) so the
  /// caller can surface a print failure.
  Future<void> send(Uint8List bytes);
}

/// A paired Bluetooth printer offered in Settings. The underlying plugin's
/// device type never leaks past this package — features see only this.
class BtDevice {
  const BtDevice({required this.name, required this.address});

  /// Human label (falls back to the address when the OS reports no name).
  final String name;

  /// The bonded device's MAC address — the stable id we persist and connect by.
  final String address;
}

/// A print-transport failure, carrying a short human reason for logs/toasts.
class PrinterTransportException implements Exception {
  const PrinterTransportException(this.message);

  final String message;

  @override
  String toString() => 'PrinterTransportException: $message';
}
