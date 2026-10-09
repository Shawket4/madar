/// What the items page computes in the browser, as pure functions: the
/// search fold (`lib/normalize.ts`), the tax-rate words (`formatRate`), the
/// paste rows' validation and payload, the add-on selection → group
/// attachments of the item dialog, and the bulk runner (`lib/bulk-runner.ts`).
library;

import 'dart:async';

import 'package:dashboard_api/dashboard_api.dart'
    show AddonItem, Category, GroupAttachInput, GroupOut;

import '../shared/menu_text.dart';

/// The three tabs of the page.
enum MenuTab { items, addons, categories }

/// The recipe filter (`all` / `missing` / `has`).
enum RecipeFilter { all, missing, has }

/// `has_recipe` for a filter: omitted, false or true.
bool? hasRecipeParam(RecipeFilter f) => switch (f) {
  RecipeFilter.all => null,
  RecipeFilter.missing => false,
  RecipeFilter.has => true,
};

// ponytail: a hand table for the Latin letters a café menu uses, not full
// NFKD (Dart has no Unicode normaliser without a package); widen it if a
// name with another precomposed letter fails to match.
const Map<String, String> _latinFold = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', //
  'ç': 'c', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', //
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ñ': 'n', //
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', //
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ý': 'y', 'ÿ': 'y',
};

final RegExp _marks = RegExp('[̀-ًͯ-ْ]');

/// `normalize`: lower case, Latin accents and Arabic tashkeel dropped,
/// trimmed (accent-insensitive search).
String normalizeSearch(String s) {
  final lower = s.toLowerCase().replaceAll(_marks, '');
  final b = StringBuffer();
  for (final ch in lower.split('')) {
    b.write(_latinFold[ch] ?? ch);
  }
  return b.toString().trim();
}

/// The rows whose [text] contains [query] (folded); all when it is blank.
List<T> searchRows<T>(List<T> rows, String query, String Function(T) text) {
  final q = normalizeSearch(query);
  if (q.isEmpty) return rows;
  return [
    for (final r in rows)
      if (normalizeSearch(text(r)).contains(q)) r,
  ];
}

/// `formatRate`: a fraction as a percent, 4 decimals at most (`0.14` →
/// `14%`).
String formatRate(num fraction) =>
    '${jsNumberText(jsRound(fraction * 100 * 10000) / 10000)}%';

// ── paste rows ─────────────────────────────────────────────────────────────

/// The paste columns, in default order.
const List<String> pasteKeys = [
  'name',
  'base_price',
  'category',
  'description',
];

/// Why a pasted row cannot be created, as an i18n key, or null when it can
/// (`pasteValidate`): name, then price (`parseFloat`, ≥ 0), then the
/// category (an existing category's English name, trimmed, any case).
String? pasteRowError(Map<String, String> row, List<Category> categories) {
  if ((row['name'] ?? '').trim().isEmpty) return 'menu.grid.nameRequired';
  final p = jsParseFloat(row['base_price'] ?? '');
  if (!p.isFinite || p < 0) return 'menu.grid.priceInvalid';
  final cat = (row['category'] ?? '').trim().toLowerCase();
  if (!categories.any((c) => c.name.trim().toLowerCase() == cat)) {
    return 'menu.grid.categoryUnknown';
  }
  return null;
}

/// The category id a pasted row names (by English name), or null.
String? pasteCategoryId(Map<String, String> row, List<Category> categories) {
  final cat = (row['category'] ?? '').trim().toLowerCase();
  for (final c in categories) {
    if (c.name.trim().toLowerCase() == cat) return c.id;
  }
  return null;
}

/// A pasted price in piastres (`Math.round(parseFloat(x) * 100)`).
int pastePricePiastres(Map<String, String> row) =>
    jsRound(jsParseFloat(row['base_price'] ?? '') * 100);

/// What a bulk run came to (`runBulk`).
typedef BulkResult<T> = ({List<T> ok, List<T> failed});

/// Runs [op] over [rows], [concurrency] at a time; one failure never stops
/// the rest.
Future<BulkResult<T>> runBulk<T>(
  List<T> rows,
  Future<void> Function(T row) op, {
  int concurrency = 4,
}) async {
  final ok = <T>[];
  final failed = <T>[];
  var next = 0;
  Future<void> worker() async {
    while (next < rows.length) {
      final row = rows[next++];
      try {
        await op(row);
        ok.add(row);
      } on Object {
        failed.add(row);
      }
    }
  }

  final n = rows.isEmpty
      ? 1
      : (rows.length < concurrency ? rows.length : concurrency);
  await Future.wait([for (var i = 0; i < n; i++) worker()]);
  return (ok: ok, failed: failed);
}

// ── item dialog ────────────────────────────────────────────────────────────

/// A selection of add-on ids as one comparable value, order-free.
String selectionKey(Iterable<String> ids) => ([...ids]..sort()).join(',');

/// The selected add-ons as group attachments: each add-on's type → the group
/// whose `legacy_addon_type` (else name) is that type, one attachment per
/// type in first-seen order, the selection as `included_option_ids`.
List<GroupAttachInput> addonAttachments(
  Iterable<String> selected,
  List<AddonItem> addons,
  List<GroupOut> groups,
) {
  final typeOf = {for (final a in addons) a.id: a.addonType};
  final groupByType = <String, GroupOut>{
    for (final g in groups) g.legacyAddonType ?? g.name: g,
  };
  final byType = <String, List<String>>{};
  for (final id in selected) {
    final ty = typeOf[id];
    if (ty == null) continue;
    (byType[ty] ??= []).add(id);
  }
  return [
    for (final (i, e) in byType.entries.indexed)
      if (groupByType[e.key] case final g?)
        GroupAttachInput(groupId: g.id, sort: i, includedOptionIds: e.value),
  ];
}

/// The add-on picker's groups: [addons] whose name contains [query] (any
/// case), by type in first-seen order.
List<(String, List<AddonItem>)> addonPickerGroups(
  List<AddonItem> addons,
  String query,
) {
  final q = query.trim().toLowerCase();
  final byType = <String, List<AddonItem>>{};
  for (final a in addons) {
    if (q.isNotEmpty && !a.name.toLowerCase().contains(q)) continue;
    (byType[a.addonType] ??= []).add(a);
  }
  return [for (final e in byType.entries) (e.key, e.value)];
}

/// A price box's text in piastres (`egpToPiastres(parseFloat)`), or null.
int? egpTextToPiastres(String text) {
  final v = jsParseFloat(text);
  return v.isFinite ? jsRound(v * 100) : null;
}
