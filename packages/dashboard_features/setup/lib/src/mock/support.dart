/// What the setup area's mock handlers share: registering a route only when
/// no other area answers it, seeding a table only when no other area has,
/// and the QR answers (`QrResponse`) the QR, Links page and Loyalty units
/// all hand out — with a real, scannable code image that follows the render
/// query ([mockQrFor]): the branded card, the receipt code, or the unbranded
/// code with or without the shop's logo in the middle.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:pdf/widgets.dart'
    show Barcode, BarcodeBar, BarcodeQRCorrectionLevel;

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

/// What a code's image looks like (the server's three renders).
enum MockQrLook {
  /// The branded A6 card: a frame, the code with Madar's mark (or the
  /// shop's logo) in the middle, the purpose line and "Powered by" under it.
  card,

  /// The small plain receipt code: nothing in the middle.
  receipt,

  /// The unbranded code: the square QR and nothing else.
  plain,
}

/// A `QrResponse` as the backend answers it: [kind] (`org_order`,
/// `branch_booking`, `org_loyalty`, …), the page it lands on, a short link
/// whose code is stable for [key], and the code itself as a PNG data URL in
/// [look] (with the shop's logo in the middle when [logo]).
QrResponse mockQrResponse({
  required String kind,
  required String longUrl,
  required String key,
  MockQrLook look = MockQrLook.receipt,
  bool logo = false,
  bool? centreLogo,
}) {
  final code = mockShortCode(key);
  final shortUrl = '$mockShortLinkBase/$code';
  return QrResponse(
    kind: kind,
    longUrl: longUrl,
    shortUrl: shortUrl,
    shortCode: code,
    qrDataUrl: qrPngDataUrl(shortUrl, look: look, logo: logo),
    centreLogo: centreLogo,
  );
}

/// The answer to [req]'s render query (`QrRenderQuery`), as the server draws
/// it: `unbranded=true` the plain code (the shop's logo in the middle when
/// `centre_logo` is not false AND [orgId]'s shop has a printable logo on a
/// paid plan; `centre_logo` in the answer says which); else `card=false` the
/// receipt code, else the branded card.
QrResponse mockQrFor(
  MockRequest req,
  MockDb db, {
  required String? orgId,
  required String kind,
  required String longUrl,
  required String key,
}) {
  if (req.q('unbranded') == 'true') {
    final wanted = req.q('centre_logo') != 'false';
    final logo = wanted && mockHasPrintableLogo(db, orgId);
    return mockQrResponse(
      kind: kind,
      longUrl: longUrl,
      key: key,
      look: MockQrLook.plain,
      logo: logo,
      centreLogo: logo,
    );
  }
  if (req.q('card') == 'false') {
    return mockQrResponse(
      kind: kind,
      longUrl: longUrl,
      key: key,
      centreLogo: false,
    );
  }
  return mockQrResponse(
    kind: kind,
    longUrl: longUrl,
    key: key,
    look: MockQrLook.card,
    logo: mockHasPrintableLogo(db, orgId),
    centreLogo: true,
  );
}

/// The shop has a logo the server can print in a code: a logo on file and
/// a plan with `branding` (not Free).
bool mockHasPrintableLogo(MockDb db, String? orgId) {
  if (orgId == null) return false;
  final org = db['orgs'].find(orgId);
  if (org == null) return false;
  final logo = (org['logo_url'] as String?)?.trim() ?? '';
  return logo.isNotEmpty && org['plan'] != 'free';
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

/// [data] as a scannable QR code in [look]: a 1-bit PNG with a four-module
/// quiet zone, eight pixels a module, as a `data:image/png;base64,…` URL.
String qrPngDataUrl(
  String data, {
  MockQrLook look = MockQrLook.receipt,
  bool logo = false,
}) =>
    'data:image/png;base64,${base64.encode(qrPng(data, look: look, logo: logo))}';

/// [data] as a scannable QR code PNG (see [qrPngDataUrl]).
Uint8List qrPng(
  String data, {
  int scale = 8,
  int quiet = 4,
  MockQrLook look = MockQrLook.receipt,
  bool logo = false,
}) {
  // Something in the middle covers modules: the highest error correction
  // then; a bare code keeps the lowest (bigger modules), as the server does.
  final centre = look == MockQrLook.card || logo;
  final level = centre
      ? BarcodeQRCorrectionLevel.high
      : BarcodeQRCorrectionLevel.low;
  final bars = Barcode.qrCode(
    errorCorrectLevel: level,
  ).make(data, width: 1, height: 1).whereType<BarcodeBar>().toList();
  final n = (1 / bars.first.height).round();
  final side = (n + quiet * 2) * scale;
  final card = look == MockQrLook.card;
  // The card is A6 (105 x 148): the code at the top, its words under it.
  final width = side;
  final height = card ? (side * 148 / 105).round() : side;
  final img = _Raster(width, height);
  for (final b in bars) {
    if (!b.black) continue;
    final row = (b.top * n).round();
    final from = (b.left * n).round();
    final to = ((b.left + b.width) * n).round();
    img.fill(
      (quiet + from) * scale,
      (quiet + row) * scale,
      (to - from) * scale,
      scale,
    );
  }
  if (centre) {
    // A white plaque over the middle fifth, with the mark on it: the shop's
    // logo a round dot, Madar's mark a square ring.
    final plaque = ((n * 0.22).round() | 1) * scale;
    final at = (side - plaque) ~/ 2;
    img.fill(at, at, plaque, plaque, dark: false);
    final inset = scale;
    if (logo) {
      img.disc(side / 2, side / 2, plaque / 2 - inset);
    } else {
      img
        ..fill(at + inset, at + inset, plaque - 2 * inset, plaque - 2 * inset)
        ..fill(
          at + 2 * inset,
          at + 2 * inset,
          plaque - 4 * inset,
          plaque - 4 * inset,
          dark: false,
        );
    }
  }
  if (card) {
    // The frame, the purpose line, the caption and "Powered by".
    final t = scale ~/ 2;
    img
      ..fill(0, 0, width, t)
      ..fill(0, height - t, width, t)
      ..fill(0, 0, t, height)
      ..fill(width - t, 0, t, height);
    final words = side + scale;
    img
      ..fill(width * 2 ~/ 10, words, width * 6 ~/ 10, scale * 2)
      ..fill(width * 3 ~/ 10, words + scale * 4, width * 4 ~/ 10, scale)
      ..fill(width * 4 ~/ 10, height - scale * 4, width * 2 ~/ 10, scale);
  }
  return img.png();
}

/// A 1-bit image, white until drawn on.
class _Raster {
  _Raster(this.width, this.height)
    : _dark = List.generate(height, (_) => List.filled(width, false));

  final int width;
  final int height;
  final List<List<bool>> _dark;

  void fill(int x, int y, int w, int h, {bool dark = true}) {
    for (var yy = y.clamp(0, height); yy < (y + h).clamp(0, height); yy++) {
      for (var xx = x.clamp(0, width); xx < (x + w).clamp(0, width); xx++) {
        _dark[yy][xx] = dark;
      }
    }
  }

  void disc(double cx, double cy, double r) {
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final dx = x + 0.5 - cx;
        final dy = y + 0.5 - cy;
        if (dx * dx + dy * dy <= r * r) _dark[y][x] = true;
      }
    }
  }

  Uint8List png() {
    final rowBytes = (width + 7) >> 3;
    final raw = BytesBuilder();
    for (var y = 0; y < height; y++) {
      raw.addByte(0); // filter: none
      final line = Uint8List(rowBytes)..fillRange(0, rowBytes, 0xFF);
      for (var x = 0; x < width; x++) {
        if (_dark[y][x]) line[x >> 3] &= ~(0x80 >> (x & 7));
      }
      raw.add(line);
    }
    final ihdr = ByteData(13)
      ..setUint32(0, width)
      ..setUint32(4, height)
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
