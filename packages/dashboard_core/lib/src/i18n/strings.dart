/// UI text with i18next's semantics, over the web dashboard's own tables.
///
/// Lookup for `t(key)` in the active language:
///   1. the language's table (the synced web table with every area
///      supplement merged over it);
///   2. English (the web's `fallbackLng`), same merge;
///   3. the call's default (`defaultValue`, or a plural `defaultValues` form);
///   4. the key itself.
/// A key that reaches 3 or 4 is recorded in [MissingKeyLog.missing]; an
/// Arabic lookup that only English answered is recorded in
/// [MissingKeyLog.englishFallbacks]. The test harness fails on both.
///
/// With a `count`, each language is tried as `key_zero` (count 0 only), then
/// `key_<CLDR category>`, then `key`, exactly as i18next's resolver does.
/// `{{name}}` interpolates from `args` (and `{{count}}` from `count`); a
/// variable that was not passed at all is left as written, one passed as null
/// becomes empty — i18next's `skipOnVariables` behaviour.
library;

import 'dart:collection';

import 'package:dashboard_core/src/i18n/plural.dart';

/// Keys that were not translated, collected for the test harness.
class MissingKeyLog {
  /// Keys no table had (the default or the key itself was shown).
  final Set<String> missing = SplayTreeSet<String>();

  /// Keys an Arabic (non-English) lookup only found in English.
  final Set<String> englishFallbacks = SplayTreeSet<String>();

  bool get isEmpty => missing.isEmpty && englishFallbacks.isEmpty;

  void clear() {
    missing.clear();
    englishFallbacks.clear();
  }

  @override
  String toString() =>
      'missing: ${missing.join(', ')}; English in another language: '
      '${englishFallbacks.join(', ')}';
}

/// The loaded string tables for every language.
class Strings {
  /// [tables]: language -> flat key -> text (the synced web tables).
  /// [supplements]: each area's tables, merged over [tables] in order.
  Strings(
    Map<String, Map<String, String>> tables, {
    List<Map<String, Map<String, String>>> supplements = const [],
    this.fallbackLanguage = 'en',
    MissingKeyLog? log,
  }) : log = log ?? MissingKeyLog(),
       _tables = _merge(tables, supplements);

  /// An empty set of tables (every lookup falls to its default or key).
  factory Strings.empty() => Strings(const {});

  final String fallbackLanguage;
  final MissingKeyLog log;
  final Map<String, Map<String, String>> _tables;

  static Map<String, Map<String, String>> _merge(
    Map<String, Map<String, String>> tables,
    List<Map<String, Map<String, String>>> supplements,
  ) {
    final out = <String, Map<String, String>>{
      for (final e in tables.entries) e.key: Map<String, String>.of(e.value),
    };
    for (final s in supplements) {
      for (final e in s.entries) {
        (out[e.key] ??= <String, String>{}).addAll(e.value);
      }
    }
    return out;
  }

  /// The languages that have a table.
  Iterable<String> get languages => _tables.keys;

  /// The merged table of [lang] (read-only view).
  Map<String, String> table(String lang) =>
      UnmodifiableMapView(_tables[_base(lang)] ?? const {});

  /// Whether [key] resolves in [lang] or the fallback without a default.
  bool exists(String lang, String key, {num? count}) =>
      _resolve(lang, key, count) != null;

  /// i18next `t()`: see the library comment for the lookup order.
  String translate(
    String lang,
    String key, {
    Map<String, Object?>? args,
    num? count,
    String? defaultValue,
    Map<String, String>? defaultValues,
  }) {
    final hit = _resolve(lang, key, count);
    String text;
    if (hit != null) {
      text = hit.$1;
      if (hit.$2 != _base(lang) && _base(lang) != fallbackLanguage) {
        log.englishFallbacks.add(key);
      }
    } else {
      log.missing.add(key);
      text = _pluralDefault(lang, count, defaultValue, defaultValues) ?? key;
    }
    return interpolate(text, args: args, count: count);
  }

  /// An array value (`returnObjects`): `key.0`, `key.1`, … in [lang], else
  /// the fallback language. Empty when there is none.
  List<String> list(String lang, String key) {
    for (final code in _codes(lang)) {
      final t = _tables[code];
      if (t == null) continue;
      final out = <String>[];
      for (var i = 0; t.containsKey('$key.$i'); i++) {
        out.add(t['$key.$i']!);
      }
      if (out.isNotEmpty) return out;
    }
    return const [];
  }

  List<String> _codes(String lang) {
    final base = _base(lang);
    return base == fallbackLanguage ? [base] : [base, fallbackLanguage];
  }

  static String _base(String lang) =>
      lang.split(RegExp('[-_]')).first.toLowerCase();

  /// The text and the language that answered, or null.
  (String, String)? _resolve(String lang, String key, num? count) {
    for (final code in _codes(lang)) {
      final t = _tables[code];
      if (t == null) continue;
      // i18next pushes [key, key_<cat>, key_zero] and pops from the end.
      if (count != null) {
        if (count == 0) {
          final zero = t['${key}_zero'];
          if (zero != null) return (zero, code);
        }
        final cat = t['${key}_${pluralCategory(code, count)}'];
        if (cat != null) return (cat, code);
      }
      final plain = t[key];
      if (plain != null) return (plain, code);
    }
    return null;
  }

  String? _pluralDefault(
    String lang,
    num? count,
    String? defaultValue,
    Map<String, String>? defaultValues,
  ) {
    String? pick(String? s) => (s == null || s.isEmpty) ? null : s;
    if (count != null && defaultValues != null) {
      if (count == 0) {
        final zero = pick(defaultValues['zero']);
        if (zero != null) return zero;
      }
      final cat = pick(defaultValues[pluralCategory(lang, count)]);
      if (cat != null) return cat;
    }
    // i18next's `||` chain: the plural forms first, then `defaultValue`.
    return defaultValue;
  }

  static final RegExp _placeholder = RegExp(r'\{\{(-?)\s*([^{}]+?)\s*\}\}');

  /// `{{var}}` / `{{- var}}` interpolation with i18next's rules: a variable
  /// that was not passed stays as written; one passed as null is empty;
  /// numbers print the way JavaScript prints them (`2.0` -> `2`); a dotted
  /// name reads into nested maps; a `, format` suffix is ignored (the web
  /// registers no formatters).
  static String interpolate(
    String text, {
    Map<String, Object?>? args,
    num? count,
  }) {
    if (!text.contains('{{')) return text;
    final data = <String, Object?>{...?args, 'count': ?count};
    return text.replaceAllMapped(_placeholder, (m) {
      final name = m.group(2)!.split(',').first.trim();
      final found = _lookup(data, name);
      if (!found.$1) return m.group(0)!;
      return jsString(found.$2);
    });
  }

  static (bool, Object?) _lookup(Map<String, Object?> data, String name) {
    if (data.containsKey(name)) return (true, data[name]);
    Object? cur = data;
    for (final part in name.split('.')) {
      if (cur is Map && cur.containsKey(part)) {
        cur = cur[part];
      } else {
        return (false, null);
      }
    }
    return (true, cur);
  }

  /// `String(value)` as JavaScript would print it.
  static String jsString(Object? value) {
    if (value == null) return '';
    if (value is double) {
      if (value.isNaN) return 'NaN';
      if (value.isInfinite) return value > 0 ? 'Infinity' : '-Infinity';
      if (value == value.truncateToDouble() && value.abs() < 1e21) {
        return value.toInt().toString();
      }
    }
    return value.toString();
  }
}
