/// What is left of the order feature's own kit: the native component metrics
/// its panels measure against. Its button, field and section title are the
/// design system's now — see `design_system/controls.dart` for why one of
/// each, rather than one per feature.
library;

// Native metrics (Components.kt) that fall between the 4-pt
// Space steps — kept verbatim so the Flutter chrome measures identically.

/// Held-order chip height (natives: 46.dp).
const double kHeldChipHeight = 46;

/// Current instant as an RFC3339 UTC timestamp — the live-cart / New chip's
/// sort-key fallback when no recorded start time exists yet.
String nowIso() => DateTime.now().toUtc().toIso8601String();

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
