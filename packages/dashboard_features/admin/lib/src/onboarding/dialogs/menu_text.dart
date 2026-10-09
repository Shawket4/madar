/// Small text and number rules the menu pages share, ported from the web:
/// `features/menu/util.ts` (`ONE_SIZE`, `arOf`), `lib/translation.ts`
/// (`getTranslatedName`), the add-on type humaniser of the item dialog and the
/// studio modifiers, the unit words (`units.*`) and the quantity rules of the
/// recipe grids (`grid-model.ts`).
library;

import 'package:dashboard_core/dashboard_core.dart';

/// The label of the single size that carries a simple item's price (the web's
/// `ONE_SIZE`). An item with exactly this one size reads as "one price": the
/// label is never shown to anyone.
const String oneSize = 'one_size';

/// The ingredient units the recipe editors offer, in the web's order.
const List<String> ingredientUnits = ['g', 'kg', 'ml', 'l', 'pcs'];

/// `arOf`: the Arabic text of a `*_translations` object, else `''`.
String arOf(Object? translations) {
  if (translations is Map) {
    final v = translations['ar'];
    if (v is String) return v;
  }
  return '';
}

/// `getTranslatedName`: the Arabic name when the UI is Arabic and the
/// translations carry an Arabic string, else [name] (the web returns the
/// Arabic value as soon as it is a string).
String translatedName(String name, Object? translations, String lang) {
  if (lang.startsWith('ar') && translations is Map) {
    final v = translations['ar'];
    if (v is String) return v;
  }
  return name;
}

/// The add-on type as words: a trailing `_type` dropped, `_` to spaces, each
/// word capitalised (`milk_type` -> `Milk`, `extra_shot` -> `Extra Shot`).
String humanizeAddonType(String type) {
  final base = type.endsWith('_type')
      ? type.substring(0, type.length - '_type'.length)
      : type;
  return base
      .replaceAll('_', ' ')
      .replaceAllMapped(RegExp(r'\b\w'), (m) => m[0]!.toUpperCase());
}

/// The unit word (`t('units.<unit>', unit)`): g / kg / ml / L / pcs, and
/// جم / كجم / مل / لتر / قطعة in Arabic.
String unitWord(Translator t, String unit) =>
    t('units.$unit', defaultValue: unit);

/// A size's column or pill label: the `one_size` sentinel reads [oneSizeText]
/// (the caller's word: "One size" in the recipe builder, "Price" in the grid).
String sizeLabelText(String label, String oneSizeText) =>
    label == oneSize ? oneSizeText : label;

/// Keeps what a quantity or price cell accepts while typing: digits and dots,
/// a comma read as a dot (the web's `cleanQty`, then one decimal point kept).
String cleanDecimal(String v) {
  final s = v.replaceAll(',', '.').replaceAll(RegExp(r'[^\d.]'), '');
  final dot = s.indexOf('.');
  if (dot == -1) return s;
  return s.substring(0, dot + 1) + s.substring(dot + 1).replaceAll('.', '');
}

/// JavaScript's `Number(text)`: blank -> 0, surrounding spaces ignored,
/// anything else that is not a number -> NaN.
double jsNumber(String text) {
  final s = text.trim();
  if (s.isEmpty) return 0;
  return double.tryParse(s) ?? double.nan;
}

/// JavaScript's `parseFloat(text)`: the longest leading number ("45 EGP" ->
/// 45), else NaN.
double jsParseFloat(String text) {
  final m = RegExp(
    r'^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?',
  ).firstMatch(text.trimLeft());
  if (m == null) return double.nan;
  return double.parse(m[0]!);
}

/// JavaScript's `Math.round` (halves round up, towards +infinity).
int jsRound(num v) => (v + 0.5).floor();

/// JavaScript's `String(n)` for the numbers these editors produce: integral
/// values without a fraction (`180`, not `180.0`).
String jsNumberText(num n) {
  if (n is int) return n.toString();
  if (n.isFinite && n == n.truncateToDouble() && n.abs() < 1e21) {
    return n.toInt().toString();
  }
  return n.toString();
}

/// `fmtQty`: rounded to the 3 decimals the quantity inputs accept.
String fmtQty(num q) => jsNumberText(jsRound(q * 1000) / 1000);

/// A price typed in pounds as the editors show it: an integer, or up to two
/// decimals with trailing zeros trimmed (`45`, `12.5`). Used for placeholders
/// and seeded price boxes (`piastres / 100`).
String egpText(num piastres) => jsNumberText(piastres / 100);
