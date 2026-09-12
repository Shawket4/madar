// The staff app's words live in its own bundled tables, not the core's.
// `Strings.t` falls back en → key, so a key missing from `ar.json` renders
// English to an Arabic reader and a key missing from both renders raw — and
// nothing noticed either until a person did.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, String> _table(String lang) =>
    (json.decode(File('assets/i18n/$lang.json').readAsStringSync())
            as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, '$v'));

/// Values that are not language: placeholder templates, or the OTHER
/// language's own name on the language switch.
const _notLanguage = {'home.shiftWindow', 'requests.windowExcuse'};

void main() {
  final en = _table('en');
  final ar = _table('ar');

  test('en and ar carry the same keys', () {
    expect(ar.keys.toSet().difference(en.keys.toSet()), isEmpty);
    expect(en.keys.toSet().difference(ar.keys.toSet()), isEmpty);
  });

  test('every Arabic value is Arabic', () {
    final arabic = RegExp('[؀-ۿ]');
    final latin = [
      for (final e in ar.entries)
        if (!_notLanguage.contains(e.key) &&
            RegExp('[A-Za-z]').hasMatch(e.value) &&
            !arabic.hasMatch(e.value))
          '${e.key} = ${e.value}',
    ];
    expect(latin, isEmpty);
  });

  test('every key the code asks for exists', () {
    final families = {for (final k in en.keys) k.split('.').first};
    final key = RegExp(r"'([a-z][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)+)'");
    final missing = <String>{};
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final src = f
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      for (final m in key.allMatches(src)) {
        final k = m.group(1)!;
        if (!families.contains(k.split('.').first)) continue;
        if (!en.containsKey(k)) missing.add('$k · ${f.path}');
      }
    }
    expect(missing, isEmpty);
  });
}
