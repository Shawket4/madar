/// CLDR cardinal plural rules, as i18next asks `Intl.PluralRules` for them.
library;

/// The plural categories i18next knows, in its suffix order.
const List<String> pluralCategories = [
  'zero',
  'one',
  'two',
  'few',
  'many',
  'other',
];

/// The CLDR cardinal category of [count] in [lang] (`en`, `ar`, or a tag such
/// as `ar-EG`). Arabic uses all six; English `one`/`other`; any other
/// language falls back to i18next's dummy rule (`1` -> `one`, else `other`).
///
/// Like JavaScript, an integral double (`2.0`) counts as the integer it is.
String pluralCategory(String lang, num count) {
  final n = count.abs();
  final integral = n.isFinite && n == n.truncateToDouble();
  final base = lang.split(RegExp('[-_]')).first.toLowerCase();
  switch (base) {
    case 'ar':
      if (!integral) return 'other';
      final i = n.toInt();
      if (i == 0) return 'zero';
      if (i == 1) return 'one';
      if (i == 2) return 'two';
      final mod = i % 100;
      if (mod >= 3 && mod <= 10) return 'few';
      if (mod >= 11 && mod <= 99) return 'many';
      return 'other';
    case 'en':
      // `one`: i = 1 and v = 0 (no visible fraction).
      return integral && n == 1 ? 'one' : 'other';
    default:
      return count == 1 ? 'one' : 'other';
  }
}
