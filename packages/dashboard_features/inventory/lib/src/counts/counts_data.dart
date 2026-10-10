/// Stock counts' own reads (the open count, a variance report) and what the
/// web computes in the browser for the page and the count editor
/// (`counts-page.tsx`, `count-editor.tsx`), as pure functions.
///
/// The counts list, the catalog and the categories are
/// `shared/inventory_data.dart`'s.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show OrgIngredient, Stocktake, StocktakeFull, StocktakeItem, VarianceReport;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/inventory_lib.dart';

/// `GET /stocktakes/{id}` (getStocktake): the open count with live book
/// stock. The editor refetches it every [countPollEvery] (INV-CNT-024).
final stocktakeProvider = FutureProvider.autoDispose
    .family<StocktakeFull, String>((ref, id) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/stocktakes/$id'));
      return ref.watch(apiProvider).stocktakes.getStocktake(id: id);
    });

/// `GET /stocktakes/{id}/variance-report` (varianceReport): read only while
/// the report is open (INV-CNT-049).
final varianceReportProvider = FutureProvider.autoDispose
    .family<VarianceReport, String>((ref, id) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/stocktakes/$id/variance-report'));
      return ref.watch(apiProvider).stocktakes.varianceReport(id: id);
    });

/// The open count's `refetchInterval`: book stock keeps moving with sales
/// and deliveries while it is open.
const Duration countPollEvery = Duration(seconds: 30);

/// The autosave debounce after the last figure or reason (INV-CNT-041).
const Duration countSaveAfter = Duration(milliseconds: 1200);

/// The scope dialog's choice (INV-CNT-019).
enum CountScope { full, category, items }

/// `scope.kind` of a count: `full` (also when missing), `category`, `items`.
String stocktakeScopeKind(Map<String, Object?>? scope) =>
    (scope?['kind'] as String?) ?? 'full';

/// The history table's scope words (INV-CNT-011).
String stocktakeScopeLabel(Translator t, Stocktake s) =>
    switch (stocktakeScopeKind(s.scope)) {
      'category' => t('inventory.stocktakes.scopeCategoryShort'),
      'items' => t('inventory.stocktakes.scopeItemsShort'),
      _ => t('inventory.stocktakes.scopeFullShort'),
    };

/// The branch's open count, if the list knows one.
Stocktake? openStocktake(List<Stocktake>? list) {
  for (final s in list ?? const <Stocktake>[]) {
    if (isOpenStocktake(s.status)) return s;
  }
  return null;
}

/// Every count that is not open (INV-CNT-008: the table with a branch, and
/// the export either way).
List<Stocktake> closedStocktakes(List<Stocktake>? list) => [
  for (final s in list ?? const <Stocktake>[])
    if (!isOpenStocktake(s.status)) s,
];

/// The editor's segmented filter (INV-CNT-030).
enum CountFilter { all, uncounted, counted, flagged }

/// One row the manager can count: a snapshot item, or a found item added
/// locally (the web's `Row`).
class CountRow {
  const CountRow({
    required this.orgIngredientId,
    required this.ingredientName,
    required this.unit,
    required this.categoryId,
    required this.categoryName,
    required this.openingQty,
    required this.bookQty,
    required this.unitCost,
    required this.isNew,
  });

  factory CountRow.fromItem(StocktakeItem it) => CountRow(
    orgIngredientId: it.orgIngredientId,
    ingredientName: it.ingredientName,
    unit: it.unit,
    categoryId: it.categoryId,
    categoryName: it.categoryName,
    openingQty: it.openingQty,
    bookQty: it.bookQty,
    unitCost: it.unitCost,
    isNew: it.isNew,
  );

  /// A found item picked from the catalog: nothing on the books here yet
  /// (INV-CNT-031).
  factory CountRow.found(OrgIngredient ing) => CountRow(
    orgIngredientId: ing.id,
    ingredientName: ing.name,
    unit: ing.unit,
    categoryId: ing.categoryId,
    categoryName: ing.categoryName,
    openingQty: 0,
    bookQty: 0,
    unitCost: ing.costPerUnit,
    isNew: true,
  );

  final String orgIngredientId;
  final String ingredientName;
  final String unit;
  final String categoryId;
  final String categoryName;
  final double openingQty;
  final double bookQty;

  /// Piastres per unit; null = unknown.
  final num? unitCost;
  final bool isNew;

  CountRowRef get ref => (
    orgIngredientId: orgIngredientId,
    name: ingredientName,
    bookQty: bookQty,
  );
}

/// The server's snapshot in its order, then the found items it does not
/// hold yet (INV-CNT-055).
List<CountRow> countEditorRows(
  List<StocktakeItem>? items,
  List<CountRow> extras,
) {
  final known = {
    for (final i in items ?? const <StocktakeItem>[]) i.orgIngredientId,
  };
  return [
    for (final i in items ?? const <StocktakeItem>[]) CountRow.fromItem(i),
    for (final e in extras)
      if (!known.contains(e.orgIngredientId)) e,
  ];
}

/// The categories the rows span, in first-seen order (id → name).
List<(String, String)> countRowCategories(List<CountRow> rows) {
  final m = <String, String>{};
  for (final r in rows) {
    m[r.categoryId] = r.categoryName;
  }
  return [for (final e in m.entries) (e.key, e.value)];
}

/// The rows the search, category and filter leave (INV-CNT-028…030). The
/// search is case-insensitive and ignores outer spaces (W1): spaces alone
/// are no filter.
List<CountRow> visibleCountRows(
  List<CountRow> rows, {
  required String search,
  required String? category,
  required CountFilter filter,
  required Map<String, String> counts,
  required num threshold,
}) {
  final q = search.trim().toLowerCase();
  return [
    for (final r in rows)
      if ((q.isEmpty || r.ingredientName.toLowerCase().contains(q)) &&
          (category == null || r.categoryId == category) &&
          _passes(r, filter, parseCount(counts[r.orgIngredientId]), threshold))
        r,
  ];
}

bool _passes(CountRow r, CountFilter f, double? counted, num threshold) =>
    switch (f) {
      CountFilter.all => true,
      CountFilter.counted => counted != null,
      CountFilter.uncounted => counted == null,
      CountFilter.flagged =>
        counted != null && isVarianceFlagged(r.bookQty, counted, threshold),
    };

/// Net difference (piastres, unrounded) over counted rows with a known
/// cost, and the progress figures (INV-CNT-025, -044).
({double net, int counted, int total}) countStats(
  List<CountRow> rows,
  Map<String, String> counts,
) {
  var net = 0.0;
  var counted = 0;
  for (final r in rows) {
    final c = parseCount(counts[r.orgIngredientId]);
    if (c == null) continue;
    counted++;
    if (r.unitCost != null) net += (c - r.bookQty) * r.unitCost!;
  }
  return (net: net, counted: counted, total: rows.length);
}

/// Book stock moved since the count opened ("was X at start").
bool movedSinceStart(num book, num opening) => (book - opening).abs() > 1e-9;

/// The figure a counted row hydrates from (`String(counted_qty)`).
String countInputText(double qty) => jsNumberString(qty);
