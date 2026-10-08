/// What the setup area's mock handlers share: registering a route only when
/// no other area answers it, seeding a table only when no other area has,
/// and the QR answers (`QrResponse`) the QR, Links page and Loyalty units
/// all hand out — with a real, scannable code image.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:pdf/widgets.dart' show Barcode, BarcodeBar;

/// Registers [handler] for `method template` unless another area already
/// answers it. In the app every area shares one server and one database: a
/// route another area owns (catalog_offers' `GET /discounts`, sell's
/// `GET /branches/{id}/tables`, admin's `GET /devices`) keeps that area's
/// handler; in this package's own tests ours answers.
void onIfAbsent(
  MockServer server,
  String method,
  String template,
  MockHandler handler,
) {
  if (server.handles(method, template)) return;
  server.on(method, template, handler);
}

/// Fills [table] from [rows] (on first read) unless the table already
/// exists — another area may have seeded the same rows first, and two areas
/// must never disagree about one record.
void seedTableIfAbsent(
  MockDb db,
  String table,
  Iterable<MockRow> Function() rows,
) {
  if (db.hasTable(table)) return;
  db.lazyTable(table, rows);
}

/// Where the mock's short links live (the backend's Shlink domain).
const String mockShortLinkBase = 'https://s.madar-pos.cloud';

/// A `QrResponse` as the backend answers it: [kind] (`org_order`,
/// `branch_booking`, `org_loyalty`, …), the page it lands on, a short link
/// whose code is stable for [key], and the code itself as a PNG data URL.
QrResponse mockQrResponse({
  required String kind,
  required String longUrl,
  required String key,
}) {
  final code = mockShortCode(key);
  final shortUrl = '$mockShortLinkBase/$code';
  return QrResponse(
    kind: kind,
    longUrl: longUrl,
    shortUrl: shortUrl,
    shortCode: code,
    qrDataUrl: qrPngDataUrl(shortUrl),
  );
}

/// A stable six-character short code for [key] (Shlink's alphabet: no
/// look-alike characters).
String mockShortCode(String key) {
  const alphabet = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final id = mockUuid('short-code:$key').replaceAll('-', '');
  final out = StringBuffer();
  for (var i = 0; i < 6; i++) {
    final n = int.parse(id.substring(i * 4, i * 4 + 4), radix: 16);
    out.write(alphabet[n % alphabet.length]);
  }
  return out.toString();
}

/// [data] as a scannable QR code: a 1-bit PNG with a four-module quiet zone,
/// eight pixels a module, as a `data:image/png;base64,…` URL.
String qrPngDataUrl(String data) =>
    'data:image/png;base64,${base64.encode(qrPng(data))}';

/// [data] as a scannable QR code PNG (see [qrPngDataUrl]).
Uint8List qrPng(String data, {int scale = 8, int quiet = 4}) {
  final bars = Barcode.qrCode()
      .make(data, width: 1, height: 1)
      .whereType<BarcodeBar>()
      .toList();
  final n = (1 / bars.first.height).round();
  final dark = List.generate(n, (_) => List.filled(n, false));
  for (final b in bars) {
    if (!b.black) continue;
    final row = (b.top * n).round();
    final from = (b.left * n).round();
    final to = ((b.left + b.width) * n).round();
    for (var x = from; x < to && x < n; x++) {
      dark[row][x] = true;
    }
  }
  final side = (n + quiet * 2) * scale;
  final rowBytes = (side + 7) >> 3;
  final raw = BytesBuilder();
  for (var y = 0; y < side; y++) {
    raw.addByte(0); // filter: none
    final line = Uint8List(rowBytes)..fillRange(0, rowBytes, 0xFF);
    final my = y ~/ scale - quiet;
    for (var x = 0; x < side; x++) {
      final mx = x ~/ scale - quiet;
      if (my >= 0 && my < n && mx >= 0 && mx < n && dark[my][mx]) {
        line[x >> 3] &= ~(0x80 >> (x & 7));
      }
    }
    raw.add(line);
  }
  final ihdr = ByteData(13)
    ..setUint32(0, side)
    ..setUint32(4, side)
    ..setUint8(8, 1) // bit depth
    ..setUint8(9, 0) // greyscale
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);
  final out = BytesBuilder()
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    ..add(_chunk('IHDR', ihdr.buffer.asUint8List()))
    ..add(_chunk('IDAT', _zlibStored(raw.takeBytes())))
    ..add(_chunk('IEND', const []));
  return out.takeBytes();
}

List<int> _chunk(String type, List<int> data) {
  final typeBytes = ascii.encode(type);
  final len = ByteData(4)..setUint32(0, data.length);
  final crc = ByteData(4)..setUint32(0, _crc32([...typeBytes, ...data]));
  return [
    ...len.buffer.asUint8List(),
    ...typeBytes,
    ...data,
    ...crc.buffer.asUint8List(),
  ];
}

/// A zlib stream of stored (uncompressed) deflate blocks: no codec needed.
List<int> _zlibStored(Uint8List data) {
  final out = BytesBuilder()..add(const [0x78, 0x01]);
  var at = 0;
  do {
    final len = (data.length - at).clamp(0, 0xFFFF);
    final last = at + len >= data.length;
    out
      ..addByte(last ? 1 : 0)
      ..add([len & 0xFF, len >> 8, ~len & 0xFF, (~len >> 8) & 0xFF])
      ..add(Uint8List.sublistView(data, at, at + len));
    at += len;
  } while (at < data.length);
  var a = 1;
  var b = 0;
  for (final byte in data) {
    a = (a + byte) % 65521;
    b = (b + a) % 65521;
  }
  final adler = ByteData(4)..setUint32(0, (b << 16) | a);
  out.add(adler.buffer.asUint8List());
  return out.takeBytes();
}

final List<int> _crcTable = List.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >>> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
