/// Small shared pieces the order feature reuses across its panels — the
/// action button + text field (the natives' MadarButton / MadarTextField),
/// the accent-dot section title, and the RFC3339/category helpers.
library;

// Native metrics (OrderScreen.kt / Components.kt) that fall between the 4-pt
// Space steps — kept verbatim so the Flutter chrome measures identically.

/// Primary action button height (natives: 50.dp).
const double kActionButtonHeight = 50;

/// The item card's width/height ratio (natives: aspectRatio(0.94f)).
const double kMenuCardAspect = 0.94;

/// The wide layout's cart column width (natives: 340.dp).
const double kCartPanelWidth = 340;

/// Held-order chip height (natives: 46.dp).
const double kHeldChipHeight = 46;

/// Category tab strip height (natives: 46.dp).
const double kCategoryTabsHeight = 46;

/// Search field height (natives: 40.dp).
const double kSearchFieldHeight = 40;

/// Small square control (close / recipe / price badge, natives: 32–36.dp).
const double kSquareControl = 36;

/// Pull "HH:MM" out of an RFC3339 timestamp ("2026-07-01T14:32:07Z" → "14:32").
/// Falls back to the raw string if the shape is unexpected.
String formatHHMM(String rfc3339) {
  final index = rfc3339.indexOf('T');
  if (index < 0 || rfc3339.length < index + 6) return rfc3339;
  return rfc3339.substring(index + 1, index + 6);
}

/// Current instant as an RFC3339 UTC timestamp — the live-cart / New chip's
/// sort-key fallback when no recorded start time exists yet.
String nowIso() => DateTime.now().toUtc().toIso8601String();

/// Local wall-clock "HH:MM" — the parked draft's display name on hold.
String nowHHMM() {
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(now.hour)}:${two(now.minute)}';
}

/// Local time as RFC3339 WITH a colon offset, so the core gates bundle
/// windows in the till's timezone (mirrors the natives' nowRfc3339()).
String nowRfc3339Local() {
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final offset = now.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final abs = offset.abs();
  final oh = two(abs.inHours);
  final om = two(abs.inMinutes % 60);
  return '${now.year.toString().padLeft(4, '0')}-${two(now.month)}-'
      '${two(now.day)}T${two(now.hour)}:${two(now.minute)}:${two(now.second)}'
      '$sign$oh:$om';
}

/// Core CatStyleView.icon key → shared icon-catalog name; null for the 'cafe'
/// default (custom category) → the caller shows text only (the monogram
/// carries the identity on the card itself).
String? categoryIconName(String key) => switch (key) {
  'coffee' ||
  'mocha' ||
  'tea' ||
  'bakery' ||
  'lunch' ||
  'icecream' ||
  'drink' ||
  'water' ||
  'ice' ||
  'matcha' => 'cat.$key',
  _ => null,
};

/// Up to two initials from the item name (the natives' monogram rule).
String monogram(String name) {
  final words = name
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList(growable: false);
  if (words.length >= 2) {
    return (words[0].substring(0, 1) + words[1].substring(0, 1)).toUpperCase();
  }
  if (words.isNotEmpty) {
    final w = words[0];
    return w.substring(0, w.length >= 2 ? 2 : 1).toUpperCase();
  }
  return '•';
}
