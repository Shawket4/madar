/// The app's doors to the outside: a web address opened in the browser (the
/// legal documents), and the banner logo an Excel export carries.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [uri] in the platform's browser.
Future<void> openExternal(Uri uri) async {
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Madar's lockup, the banner logo of an export with no org logo (the web
/// rasterizes `/madar.svg`).
const String madarLogoAsset =
    'packages/design_system/assets/brand/lockup_latin.png';

/// The banner logo for a workbook: the org's logo when it has one and it
/// downloads in time, else Madar's.
Future<Uint8List?> exportLogo(String? logoUrl) async {
  final url = logoUrl?.trim();
  if (url != null && url.isNotEmpty) {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      try {
        final req = await client.getUrl(Uri.parse(url));
        final res = await req.close().timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          final b = BytesBuilder(copy: false);
          await res.forEach(b.add).timeout(const Duration(seconds: 8));
          return b.takeBytes();
        }
      } finally {
        client.close(force: true);
      }
    } on Object {
      // Falls through to Madar's mark.
    }
  }
  try {
    final data = await rootBundle.load(madarLogoAsset);
    return data.buffer.asUint8List();
  } on Object {
    return null;
  }
}
