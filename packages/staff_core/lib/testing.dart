/// Test support: the core's own words for widget and render tests, read
/// straight out of `rust-core/crates/madar-core/src/i18n.rs`, so a render
/// shows the words that ship.
///
/// The staff app's copy of `app_core`'s `coreWord`. It is kept here rather
/// than taken from app_core because app_core brings the POS `rust_bridge`
/// plugin, and Flutter links a dev dependency's plugins into debug builds:
/// its FRB symbols then shadow the staff bridge's and the core refuses to
/// start ("content hash … different from Rust side").
///
/// Not for app code: it reads a source file off disk.
library;

import 'dart:io';

final Map<String, Map<String, String>> _tables = {};

/// The core's table for [lang] (`en` or `ar`), parsed once per process.
Map<String, String> coreWordTable(String lang) =>
    _tables[lang] ??= _parse(_i18nSource(), lang);

/// `bridge.tr` as the core resolves it: the language, then English, then
/// the key itself.
String coreWord(String key, {bool arabic = false}) {
  if (arabic) {
    final ar = coreWordTable('ar')[key];
    if (ar != null) return ar;
  }
  return coreWordTable('en')[key] ?? key;
}

String _i18nSource() {
  var dir = Directory.current.absolute;
  while (true) {
    final file = File('${dir.path}/rust-core/crates/madar-core/src/i18n.rs');
    if (file.existsSync()) return file.readAsStringSync();
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('coreWordTable: i18n.rs not found above ${dir.path}');
    }
    dir = parent;
  }
}

Map<String, String> _parse(String source, String lang) {
  final start = source.indexOf('fn $lang(key: &str)');
  if (start < 0) throw StateError('coreWordTable: no `fn $lang` in i18n.rs');
  final ends = [
    source.indexOf('\nfn ', start + 1),
    source.indexOf('\n#[cfg(test)]', start + 1),
  ].where((i) => i > 0);
  final end = ends.isEmpty
      ? source.length
      : ends.reduce((a, b) => a < b ? a : b);
  final arm = RegExp(r'"([A-Za-z0-9_.\-]+)"\s*=>\s*\{?\s*"((?:[^"\\]|\\.)*)"');
  return {
    for (final m in arm.allMatches(source.substring(start, end)))
      m.group(1)!: m
          .group(2)!
          .replaceAll(r'\"', '"')
          .replaceAll(r'\n', '\n')
          .replaceAll(r'\\', r'\'),
  };
}
