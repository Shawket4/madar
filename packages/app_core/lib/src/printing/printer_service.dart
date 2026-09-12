/// Resolves the device's active printer transport from the core config and
/// owns the Bluetooth housekeeping (runtime permission, paired-device listing,
/// disconnect). Rendering stays in the core (`renderReceipt` / `cashDrawerKick`);
/// this only decides WHERE the finished bytes go — so adding a transport never
/// reaches into a call site.
library;

import 'dart:io' show Platform;
import 'dart:typed_data' show Uint8List;

import 'package:app_core/src/printing/bluetooth_printer_transport.dart';
import 'package:app_core/src/printing/bt_backend.dart';
import 'package:app_core/src/printing/printer_transport.dart';
import 'package:app_core/src/printing/tcp_printer_transport.dart';
import 'package:app_core/src/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Default JetDirect (raw-TCP) printer port — the network printer fallback.
const int _kJetDirectPort = 9100;

/// Terminal outcome of one print attempt — shared so a one-tap print site
/// (no dedicated screen/notifier of its own, e.g. a list row's single-tap
/// print) reports "sent / no printer / failed" exactly like the feature
/// screens that already carry this three-way state under their own name
/// (`PrintState` in checkout, `ShiftPrintState` in shift).
enum PrintOutcome {
  /// The transport accepted the bytes.
  printed,

  /// No printer is bound in the device config — not a failure, an
  /// unconfigured device.
  noPrinter,

  /// A printer is bound but the transport rejected the write (off, out of
  /// range, out of paper).
  failed,
}

/// The device's printer transport resolver + Bluetooth housekeeping.
class PrinterService {
  PrinterService(this._bridge);

  final MadarBridge _bridge;

  /// The transport the device is configured to print through, or `null` when
  /// nothing is bound (→ the existing "no printer" UX). Reads the LIVE config
  /// each call, so a Settings change takes effect on the next print.
  PrinterTransport? activeTransport() {
    final config = _bridge.deviceConfig();
    final bluetooth = (config.printerTransport ?? 'lan') == 'bluetooth';
    if (bluetooth) {
      final address = config.printerBtAddress?.trim() ?? '';
      if (address.isEmpty) return null;
      return BluetoothPrinterTransport(address: address);
    }
    final host = config.printerHost?.trim() ?? '';
    if (host.isEmpty) return null;
    return TcpPrinterTransport(
      _bridge,
      host: host,
      port: config.printerPort ?? _kJetDirectPort,
    );
  }

  /// List the OS's paired (bonded) Bluetooth printers for the Settings picker,
  /// already filtered to actual printers (by Class-of-Device on Android, by name
  /// elsewhere). Requests runtime BLUETOOTH_CONNECT first (Android 12+); returns
  /// empty when permission is denied or Bluetooth is off.
  Future<List<BtDevice>> listPairedDevices() async {
    if (!await ensureBluetoothPermission()) return const [];
    final backend = btPrinterBackend();
    if (!await backend.isEnabled()) return const [];
    return await backend.listPairedPrinters();
  }

  /// Whether an SPP link is currently open (the Settings status row).
  Future<bool> bluetoothConnected() => btPrinterBackend().isConnected();

  /// Drop any open Bluetooth link — call when the selected device changes so
  /// the next print reconnects to the new one (the backend's connection is
  /// process-global).
  Future<void> disconnectBluetooth() async {
    final backend = btPrinterBackend();
    if (await backend.isConnected()) await backend.disconnect();
  }

  /// Request runtime Bluetooth permission (Android 12+ BLUETOOTH_CONNECT).
  /// Older Androids grant it at install time; non-Android platforms manage it
  /// through their own manifests/plists, so this resolves true there.
  Future<bool> ensureBluetoothPermission() async {
    if (!Platform.isAndroid) return true;
    final status = await Permission.bluetoothConnect.request();
    return status.isGranted;
  }

  /// Stream already-rendered bytes to the active transport, mapping "no
  /// transport bound" / "write rejected" onto [PrintOutcome] — the one-tap
  /// print sites that have no screen of their own to hold a richer state
  /// machine (a list row's single-tap print, converted from a tap-to-preview
  /// affordance so the SAME tap that used to open a preview now prints
  /// directly).
  Future<PrintOutcome> printBytes(Uint8List bytes) async {
    final tx = activeTransport();
    if (tx == null) return PrintOutcome.noPrinter;
    try {
      await tx.send(bytes);
      return PrintOutcome.printed;
    } on PrinterTransportException {
      return PrintOutcome.failed;
    }
  }
}

/// The device's printer transport resolver — every print path reads this.
final printerServiceProvider = Provider<PrinterService>(
  (ref) => PrinterService(ref.watch(bridgeProvider)),
);
