// The i18n build gate (AT-13) for the staff app: every word on screen comes
// from the core's table (madar-core `i18n.rs`) in English AND Arabic.
//
// `tr` falls back to the raw key, so a key missing from the table would ship
// as `staff.something` on a sheet no screenshot test opens. This test reads
// the Dart sources instead of rendering them, so it covers every sheet and
// form, not only each tab's first screen:
//   1. every key literal the staff tree names exists in EN and AR;
//   2. every key family built at run time (`staff.day_$n`) exists;
//   3. no user-visible string bypasses the table (allow-list below).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:staff_core/testing.dart';

/// The staff app's Dart: the shell, the spine and every Dawam feature.
List<File> _sources() {
  final roots = [
    Directory('lib'),
    Directory('../../packages/staff_core/lib'),
    ...Directory('../../packages/features')
        .listSync()
        .whereType<Directory>()
        .where((d) => d.uri.pathSegments.any((s) => s.startsWith('dawam_')))
        .map((d) => Directory('${d.path}/lib')),
  ];
  return [
    for (final r in roots)
      if (r.existsSync())
        ...r
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .where((f) => !f.path.contains('/generated/')),
  ];
}

String _rel(File f) {
  final p = f.path.replaceAll('\\', '/');
  return p.startsWith('../../') ? p.substring(6) : 'apps/staff/$p';
}

/// A string literal that is exactly a table key.
final _keyLiteral = RegExp(
  r'''['"]((?:staff|settings|common)\.[a-z0-9_]+)['"]''',
);

/// A key built at run time: the literal part before the first `$`.
final _keyFamily = RegExp(r'''['"]((?:staff|settings|common)\.[a-z0-9_]+)\$''');

/// Where a user-visible string is passed: `Text('…')` and the kit's named
/// text parameters.
final _visible = RegExp(
  r'''(?:\bText\(\s*|\b(?:title|subtitle|label|hint|hintText|labelText|helperText|message|tooltip|semanticLabel|semanticsLabel|ok|retryLabel|text|body|placeholder|emptyText|actionLabel)\s*:\s*)(?:const\s+)?'((?:[^'\\\n]|\\.)*)'|(?:\bText\(\s*|\b(?:title|subtitle|label|hint|hintText|labelText|helperText|message|tooltip|semanticLabel|semanticsLabel|ok|retryLabel|text|body|placeholder|emptyText|actionLabel)\s*:\s*)(?:const\s+)?"((?:[^"\\\n]|\\.)*)"''',
);

/// Words a person reads, once interpolations are removed.
final _letters = RegExp(r'[A-Za-z؀-ۿ]{2,}');

/// Deliberate exceptions, each with its reason. `file` is relative to the
/// repo root; `text` is the literal as written.
const _allowed = <(String, String), String>{
  // The boot-failure screen: the core (and so its table) may not be up.
  ('apps/staff/lib/main.dart', 'Retry · أعد المحاولة'):
      'shown when the core failed to start',
  // The phone field's shape, not words.
  ('packages/features/dawam_auth/lib/src/sign_in_screen.dart', '01X XXXX XXXX'):
      'a digit mask',
  // A file format and a language's own name, the same in both languages.
  ('packages/features/dawam_pay/lib/src/slip_view.dart', r'PDF · $l'):
      'PDF + the language name in that language',
};

void main() {
  final en = coreWordTable('en');
  final ar = coreWordTable('ar');
  final files = _sources();

  test('the gate reads the staff tree', () {
    expect(files.length, greaterThan(20));
    expect(en.length, greaterThan(1000));
  });

  test('every key the staff app names is in English and Arabic', () {
    final missing = <String>[];
    for (final f in files) {
      final src = f.readAsStringSync();
      for (final m in _keyLiteral.allMatches(src)) {
        final key = m.group(1)!;
        // A prefix the code matches keys against (`staff.n_`), not a key.
        if (key.endsWith('_')) continue;
        if (!en.containsKey(key)) missing.add('${_rel(f)}: $key (en)');
        if (!ar.containsKey(key)) missing.add('${_rel(f)}: $key (ar)');
      }
    }
    expect(missing, isEmpty, reason: 'add these to i18n.rs, EN and AR');
  });

  test('every key family built at run time exists', () {
    final missing = <String>[];
    for (final f in files) {
      for (final m in _keyFamily.allMatches(f.readAsStringSync())) {
        final prefix = m.group(1)!;
        if (!en.keys.any((k) => k.startsWith(prefix)) ||
            !ar.keys.any((k) => k.startsWith(prefix))) {
          missing.add('${_rel(f)}: $prefix…');
        }
      }
    }
    expect(missing, isEmpty);
    // The two families every date is written with.
    for (var d = 1; d <= 7; d++) {
      expect(en['staff.day_$d'], isNotNull);
      expect(ar['staff.day_$d'], isNotNull);
    }
    for (var m = 1; m <= 12; m++) {
      expect(en['staff.month_$m'], isNotNull);
      expect(ar['staff.month_$m'], isNotNull);
    }
  });

  test('every placeholder a key carries is the same in EN and AR', () {
    final ph = RegExp(r'\{([a-z0-9_]+)\}');
    final bad = <String>[];
    for (final k in en.keys.where((k) => k.startsWith('staff.'))) {
      final a = ar[k];
      if (a == null) continue;
      final e1 = ph.allMatches(en[k]!).map((m) => m.group(1)).toSet();
      final a1 = ph.allMatches(a).map((m) => m.group(1)).toSet();
      if (e1.length != a1.length || !e1.containsAll(a1)) bad.add(k);
    }
    expect(bad, isEmpty);
  });

  test('no user-visible string bypasses the table', () {
    final found = <String>[];
    final used = <(String, String)>{};
    for (final f in files) {
      final rel = _rel(f);
      for (final m in _visible.allMatches(f.readAsStringSync())) {
        final text = m.group(1) ?? m.group(2)!;
        final bare = text
            .replaceAll(RegExp(r'\$\{[^}]*\}'), '')
            // an interpolation cut short by a quote nested inside it
            .replaceAll(RegExp(r'\$\{.*$'), '')
            .replaceAll(RegExp(r'\$[A-Za-z_][A-Za-z0-9_.]*'), '');
        if (!_letters.hasMatch(bare)) continue;
        if (_keyLiteral.hasMatch("'$text'")) continue;
        if (_allowed.containsKey((rel, text))) {
          used.add((rel, text));
          continue;
        }
        found.add('$rel: "$text"');
      }
    }
    expect(found, isEmpty, reason: 'use tr() with a key in i18n.rs');
    expect(
      _allowed.keys.toSet().difference(used),
      isEmpty,
      reason: 'an allow-list entry no longer matches: drop it',
    );
  });

  test('the gate catches what it is for', () {
    // A self-check on the patterns, so a regex slip can't make it pass.
    expect(_keyLiteral.hasMatch("tr('staff.clock_in')"), isTrue);
    expect(_keyFamily.hasMatch(r"tr('staff.day_$w')"), isTrue);
    expect(_visible.hasMatch("Text('Clock in')"), isTrue);
    expect(_visible.hasMatch("label: 'Send'"), isTrue);
    expect(_visible.hasMatch('title: "تم"'), isTrue);
    expect(_letters.hasMatch(r' · '), isFalse);
  });
}
