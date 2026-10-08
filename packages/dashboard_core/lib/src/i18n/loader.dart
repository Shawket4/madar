/// Loading the string tables from assets.
library;

import 'dart:convert';

import 'package:dashboard_core/src/i18n/strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The languages the dashboard ships (`SUPPORTED_LANGUAGES`).
const List<String> supportedLanguages = ['en', 'ar'];

/// The synced web tables, as an app or another package's tests see them.
String coreStringsAsset(String lang) =>
    'packages/dashboard_core/assets/i18n/$lang.json';

/// Flattens i18next JSON (nested objects, arrays, null leaves) into dotted
/// keys, the same way `tool/sync_dashboard_i18n.py` does.
Map<String, String> flattenStrings(Object? json) {
  final out = <String, String>{};
  void walk(Object? node, String prefix) {
    if (node is Map) {
      for (final e in node.entries) {
        walk(e.value, '$prefix${e.key}.');
      }
    } else if (node is List) {
      for (var i = 0; i < node.length; i++) {
        walk(node[i], '$prefix$i.');
      }
    } else if (node != null) {
      out[prefix.substring(0, prefix.length - 1)] = Strings.jsString(node);
    }
  }

  walk(json, '');
  return out;
}

/// Parses one table's JSON text (flat or nested).
Map<String, String> parseStringTable(String jsonText) =>
    flattenStrings(json.decode(jsonText));

/// The language an asset key is for: `.../i18n/ar.json` -> `ar`.
String languageOfAsset(String assetKey) {
  final file = assetKey.split('/').last;
  return file.endsWith('.json') ? file.substring(0, file.length - 5) : file;
}

/// Loads the synced web tables plus every area supplement.
///
/// [supplementAssets] are asset keys such as
/// `packages/dashboard_sell/assets/i18n/en.json` (each `DashArea` declares
/// its own); the file name is the language. A declared asset that is missing
/// is reported in [warnings] and skipped, so one unfinished area does not
/// take every page's text down with it.
Future<Strings> loadStrings({
  AssetBundle? bundle,
  List<String> supplementAssets = const [],
  MissingKeyLog? log,
  List<String>? warnings,
}) async {
  final b = bundle ?? rootBundle;
  final tables = <String, Map<String, String>>{};
  for (final lang in supportedLanguages) {
    tables[lang] = parseStringTable(await _loadCore(b, lang));
  }
  final supplements = <Map<String, Map<String, String>>>[];
  for (final key in supplementAssets) {
    try {
      final text = await b.loadString(key, cache: false);
      supplements.add({languageOfAsset(key): parseStringTable(text)});
    } on Object catch (e) {
      final msg = 'i18n supplement $key could not be loaded: $e';
      warnings?.add(msg);
      debugPrint(msg);
    }
  }
  return Strings(tables, supplements: supplements, log: log);
}

Future<String> _loadCore(AssetBundle b, String lang) async {
  try {
    return await b.loadString(coreStringsAsset(lang), cache: false);
  } on Object {
    // Inside dashboard_core's own tests the package's assets are unprefixed.
    return b.loadString('assets/i18n/$lang.json', cache: false);
  }
}
