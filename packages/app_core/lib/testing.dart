/// Test support: the core's own words, for widget and render tests.
///
/// A test cannot load the Rust library, so a fake bridge answers `tr`. Fakes
/// used to answer from a hand-copied table, and every key the copy lacked
/// rendered as its raw key in the PNGs ("charge.no_methods" where a person
/// would read a sentence) — the pictures were then no evidence of what a
/// teller sees. This reads the real EN and AR tables straight out of
/// `rust-core/crates/madar-core/src/i18n.rs`, so a render test shows the
/// words that ship, and a word changed in the core changes in the picture.
///
/// Not for app code: it reads a source file off disk.
library;

import 'dart:io';

final Map<String, Map<String, String>> _tables = {};

/// The core's table for [lang] (`en` or `ar`), parsed once per test process.
Map<String, String> coreWordTable(String lang) =>
    _tables[lang] ??= _parse(_i18nSource(), lang);

/// `bridge.tr` as the core resolves it: the locale's language, then English,
/// then the key itself.
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
      throw StateError(
        'coreWordTable: rust-core/crates/madar-core/src/i18n.rs not found '
        'above ${Directory.current.path}',
      );
    }
    dir = parent;
  }
}

/// The `"key" => "value"` arms of `fn en` / `fn ar` — including the arms
/// written as a block (`"key" => { "value" }`) when a line runs long.
Map<String, String> _parse(String source, String lang) {
  final start = source.indexOf('fn $lang(key: &str)');
  if (start < 0) throw StateError('coreWordTable: no `fn $lang` in i18n.rs');
  // The table ends where the next top-level item begins.
  final next = source.indexOf('\nfn ', start + 1);
  final tests = source.indexOf('\n#[cfg(test)]', start + 1);
  final ends = [next, tests].where((i) => i > 0);
  final end = ends.isEmpty
      ? source.length
      : ends.reduce((a, b) => a < b ? a : b);
  final body = source.substring(start, end);
  final arm = RegExp(r'"([A-Za-z0-9_.\-]+)"\s*=>\s*\{?\s*"((?:[^"\\]|\\.)*)"');
  return {
    for (final m in arm.allMatches(body))
      m.group(1)!: m
          .group(2)!
          .replaceAll(r'\"', '"')
          .replaceAll(r'\n', '\n')
          .replaceAll(r'\\', r'\'),
  };
}
