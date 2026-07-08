/// The platform Bluetooth-printer backend behind `BluetoothPrinterTransport` and
/// `PrinterService`.
///
/// Two implementations, chosen once per platform:
///   • Android → a native RFCOMM channel (`android/.../BtPrinter.kt`). It connects
///     with the secure → insecure → reflection fallback that cheap portable heads
///     (the P300 class) need — the `print_bluetooth_thermal` plugin opens only a
///     secure socket, which is why printing failed in-app but worked in RawBT —
///     and filters the paired list to printers by Class-of-Device.
///   • Everything else → the `print_bluetooth_thermal` plugin (iOS BLE), with a
///     name-heuristic printer filter since no Class-of-Device is available there.
///
/// Both sit behind one interface so the transport and Settings never branch on
/// platform themselves.
library;

import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:app_core/src/printing/printer_transport.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

/// A paired-printer discovery + SPP connection/write backend.
abstract interface class BtPrinterBackend {
  /// Whether the Bluetooth radio is on.
  Future<bool> isEnabled();

  /// Paired devices already filtered to likely printers.
  Future<List<BtDevice>> listPairedPrinters();

  /// Whether an SPP link is currently open.
  Future<bool> isConnected();

  /// Open an SPP link to [address] (idempotent if already connected to it).
  Future<bool> connect(String address);

  /// Write [bytes], sliced into [chunkSize] pieces [throttleMs] apart so a
  /// small-buffer head can drain a large Arabic raster.
  Future<bool> write(
    Uint8List bytes, {
    required int chunkSize,
    required int throttleMs,
  });

  /// Drop any open link.
  Future<void> disconnect();
}

/// The process-wide backend for this platform.
BtPrinterBackend btPrinterBackend() => _backend;

final BtPrinterBackend _backend =
    Platform.isAndroid ? _AndroidBtBackend() : _PluginBtBackend();

/// Name substrings that mark a paired device as a printer when its Bluetooth
/// Class-of-Device isn't available (the plugin path) — mirrors the native
/// `NAME_HINTS` in `BtPrinter.kt`.
const List<String> _kPrinterNameHints = [
  'print', 'pos', 'receipt', 'thermal', 'xprinter', 'xp-', 'p300', 'p323',
  'rpp', 'mpt', 'mtp', 'ppt', 'spp-r', 'bixolon', 'gprinter', 'goojprt',
  'zjiang', 'sunmi', 'btp', 'znt', 'escpos', 'esc/pos', //
];

bool _nameLooksLikePrinter(String name) {
  final n = name.toLowerCase();
  return _kPrinterNameHints.any(n.contains);
}

/// Native Android RFCOMM bridge — see `android/app/src/main/kotlin/.../BtPrinter.kt`.
class _AndroidBtBackend implements BtPrinterBackend {
  static const MethodChannel _ch = MethodChannel('com.madar.madar/bt_printer');

  @override
  Future<bool> isEnabled() async =>
      await _ch.invokeMethod<bool>('isEnabled') ?? false;

  @override
  Future<List<BtDevice>> listPairedPrinters() async {
    final raw = await _ch.invokeMethod<List<Object?>>('pairedPrinters') ??
        const <Object?>[];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map((m) {
          final address = (m['address'] as String?) ?? '';
          final name = (m['name'] as String?) ?? '';
          return BtDevice(
            name: name.isEmpty ? address : name,
            address: address,
          );
        })
        .where((d) => d.address.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<bool> isConnected() async =>
      await _ch.invokeMethod<bool>('isConnected') ?? false;

  @override
  Future<bool> connect(String address) async =>
      await _ch.invokeMethod<bool>('connect', {'address': address}) ?? false;

  @override
  Future<bool> write(
    Uint8List bytes, {
    required int chunkSize,
    required int throttleMs,
  }) async =>
      await _ch.invokeMethod<bool>('write', {
        'bytes': bytes,
        'chunkSize': chunkSize,
        'throttleMs': throttleMs,
      }) ??
      false;

  @override
  Future<void> disconnect() async => _ch.invokeMethod<void>('disconnect');
}

/// `print_bluetooth_thermal` backend (non-Android — iOS BLE). Only its
/// connection + `writeBytes` are used; the paired list is name-filtered (no
/// Class-of-Device here), falling back to the full list rather than hiding a
/// printer whose name doesn't match a hint.
class _PluginBtBackend implements BtPrinterBackend {
  @override
  Future<bool> isEnabled() => PrintBluetoothThermal.bluetoothEnabled;

  @override
  Future<List<BtDevice>> listPairedPrinters() async {
    final paired = await PrintBluetoothThermal.pairedBluetooths;
    final printers =
        paired.where((d) => _nameLooksLikePrinter(d.name)).toList();
    // Don't hide everything when no name matches — show the full list instead.
    final chosen = printers.isNotEmpty ? printers : paired;
    return chosen
        .map(
          (d) => BtDevice(
            name: d.name.isEmpty ? d.macAdress : d.name,
            address: d.macAdress,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<bool> isConnected() => PrintBluetoothThermal.connectionStatus;

  @override
  Future<bool> connect(String address) =>
      PrintBluetoothThermal.connect(macPrinterAddress: address);

  @override
  Future<bool> write(
    Uint8List bytes, {
    required int chunkSize,
    required int throttleMs,
  }) async {
    for (var offset = 0; offset < bytes.length; offset += chunkSize) {
      final end =
          (offset + chunkSize < bytes.length) ? offset + chunkSize : bytes.length;
      final ok =
          await PrintBluetoothThermal.writeBytes(bytes.sublist(offset, end));
      if (!ok) return false;
      if (throttleMs > 0 && end < bytes.length) {
        await Future<void>.delayed(Duration(milliseconds: throttleMs));
      }
    }
    return true;
  }

  @override
  Future<void> disconnect() async {
    if (await PrintBluetoothThermal.connectionStatus) {
      await PrintBluetoothThermal.disconnect;
    }
  }
}
