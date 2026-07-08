/// Raw-TCP (JetDirect / port 9100) transport — the network printer path,
/// unchanged from before Bluetooth existed. It delegates straight to the
/// core's proven `sendToPrinter`, so a fixed WiFi/LAN station keeps working
/// exactly as it did.
library;

import 'dart:typed_data';

import 'package:app_core/src/printing/printer_transport.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Sends the core's bytes over raw TCP via `MadarBridge.sendToPrinter` (the
/// same 3× connect-retry the app has always used for network printers).
class TcpPrinterTransport implements PrinterTransport {
  const TcpPrinterTransport(
    this._bridge, {
    required this.host,
    required this.port,
  });

  final MadarBridge _bridge;
  final String host;
  final int port;

  @override
  Future<void> send(Uint8List bytes) async {
    try {
      await _bridge.sendToPrinter(host: host, port: port, bytes: bytes);
    } on Exception catch (e) {
      throw PrinterTransportException('TCP send to $host:$port failed: $e');
    }
  }
}
