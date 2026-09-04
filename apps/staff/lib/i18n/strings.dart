import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Static UI strings, loaded from bundled JSON at boot. The staff app owns its
/// own chrome copy; the core still localizes dynamic / domain content, and the
/// BACKEND owns anything it decides (a geofence refusal names the real distance,
/// so it is shown verbatim rather than re-worded here). Lookups fall back
/// en → key so a missing key is never fatal.
class Strings {
  const Strings(this._en, this._ar);

  final Map<String, String> _en;
  final Map<String, String> _ar;

  String t(String locale, String key) {
    final table = locale == 'ar' ? _ar : _en;
    return table[key] ?? _en[key] ?? key;
  }

  static Future<Strings> load() async {
    Future<Map<String, String>> read(String lang) async {
      final raw = await rootBundle.loadString('assets/i18n/$lang.json');
      final decoded = json.decode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, '$v'));
    }

    return Strings(await read('en'), await read('ar'));
  }
}
