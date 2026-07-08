/// Bluetooth Classic (SPP) transport for a paired thermal printer.
///
/// Delegates to the platform [BtPrinterBackend] (native RFCOMM on Android, the
/// `print_bluetooth_thermal` plugin elsewhere): connect to the bonded device by
/// MAC, then write the core's ESC/POS bytes RAW. No ticket / text / image helpers
/// are involved — the bytes go out unchanged. The backend's connection is
/// process-global, so a fresh instance reuses an already-open link.
library;

import 'dart:typed_data';

import 'package:app_core/src/printing/bt_backend.dart';
import 'package:app_core/src/printing/printer_transport.dart';

/// Bytes per write. RFCOMM's `write()` blocks under the printer's credit-based
/// flow control, so a mid-size chunk streams continuously and the head keeps
/// feeding at its native speed. A tiny chunk + a per-chunk sleep instead makes
/// the motor start/stop, feeding in slow spurts — the "super slow feed".
const int kDefaultBtChunkSize = 4096;

/// Pause between chunks (ms); 0 = none. Flow control is already handled twice —
/// the raster ships in ≤128-row `GS v 0` bands (printer-level pacing) and the
/// RFCOMM socket blocks when the head's buffer is full — so an artificial
/// throttle only slows the feed. Raise this ONLY if a specific head proves to
/// drop data without it.
const int kDefaultBtThrottleMs = 0;

/// Connects to [address] and streams bytes in throttled chunks.
class BluetoothPrinterTransport implements PrinterTransport {
  BluetoothPrinterTransport({
    required this.address,
    this.chunkSize = kDefaultBtChunkSize,
    this.throttleMs = kDefaultBtThrottleMs,
  });

  /// The paired printer's MAC address (the bonded Android device).
  final String address;

  /// Bytes per write; large rasters are split so the printer buffer drains.
  final int chunkSize;

  /// Pause between chunks in milliseconds — configurable throttle for long
  /// tickets / images.
  final int throttleMs;

  @override
  Future<void> send(Uint8List bytes) async {
    final backend = btPrinterBackend();
    await _ensureConnected(backend);
    // The backend slices + throttles the write for a small-buffer portable head.
    final ok = await backend.write(
      bytes,
      chunkSize: chunkSize,
      throttleMs: throttleMs,
    );
    if (!ok) {
      throw const PrinterTransportException(
        'Bluetooth write rejected — printer off, out of range, or out of paper.',
      );
    }
  }

  /// Open the SPP link if it isn't already. Reuses the backend's global
  /// connection when present (Settings disconnects it on a device change so we
  /// never write to the wrong printer).
  Future<void> _ensureConnected(BtPrinterBackend backend) async {
    if (await backend.isConnected()) return;
    if (!await backend.connect(address)) {
      throw const PrinterTransportException(
        'Could not connect to the Bluetooth printer. Is it powered on and in range?',
      );
    }
  }
}
