/// What is left of the order feature's own kit: the native component metrics
/// its panels measure against. Its button, field and section title are the
/// design system's now — see `design_system/controls.dart` for why one of
/// each, rather than one per feature.
library;

import 'package:rust_bridge/rust_bridge.dart';

// Native metrics (Components.kt) that fall between the 4-pt
// Space steps — kept verbatim so the Flutter chrome measures identically.

/// Held-order chip height (natives: 46.dp).
const double kHeldChipHeight = 46;

/// Current instant as an RFC3339 UTC timestamp — the live-cart / New chip's
/// sort-key fallback when no recorded start time exists yet.
String nowIso() => DateTime.now().toUtc().toIso8601String();

/// The size an item is sold at when nobody picks one: its first ACTIVE size
/// in the listed order — the same size the server makes a sizeless line's
/// recipe from (`default_recipe_size`). Null for an item with no sizes.
String? baseSizeLabel(MenuItemView item) =>
    (item.sizes.where((s) => s.isActive).firstOrNull ?? item.sizes.firstOrNull)
        ?.label;

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
