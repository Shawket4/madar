/// Ingredients' own read (the drawer's stock history) and what the web
/// computes in the browser for the page, its dialog and its drawer
/// (`items-page.tsx`, `item-dialog.tsx`, `item-drawer.tsx`), as pure
/// functions.
///
/// The page's other reads (catalog, branch stock, stocktakes, the dialog's
/// suppliers and categories) are `shared/inventory_data.dart`'s; the org's
/// branches are the shell's [branchesProvider] (the web's `listBranches`
/// key is the one the branch picker reads).
library;

import 'package:dashboard_api/dashboard_api.dart'
    show BranchStockRow, OrgIngredient, StockMovement;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart' show dashParseNumber;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/inventory_lib.dart' show jsNumberString;

/// The drawer's history: which branch, which ingredient.
typedef IngredientMovementsKey = ({String branchId, String ingredientId});

/// `GET /inventory/branches/{branch_id}/movements?org_ingredient_id=&per_page=50`
/// (listMovements): the latest 50 movements of one ingredient at a branch,
/// newest first. Read only while the drawer is open with a branch
/// (INV-ING-048).
final ingredientMovementsProvider = FutureProvider.autoDispose
    .family<List<StockMovement>, IngredientMovementsKey>((ref, k) {
      ref.webCache();
      ref.watch(
        realtimeEpochProvider('/inventory/branches/${k.branchId}/movements'),
      );
      return ref
          .watch(apiProvider)
          .inventory
          .listMovements(
            branchId: k.branchId,
            orgIngredientId: k.ingredientId,
            perPage: 50,
          );
    });

/// The segmented filter under the header (branch selected, Active view
/// only).
enum IngredientFilter { all, low, uncounted }

/// Active or archived ingredients (always offered).
enum IngredientView { active, archived }

/// Branch stock by ingredient id (`stockByIngredient`).
Map<String, BranchStockRow> stockByIngredient(List<BranchStockRow>? rows) => {
  for (final s in rows ?? const <BranchStockRow>[]) s.orgIngredientId: s,
};

/// The table's rows: the catalog in [view] (archived or not), narrowed by
/// [filter] only in the Active view with a branch (INV-ING-006, -054). Low =
/// the branch row is below par; never counted = no branch row or no
/// `last_counted_at`.
List<OrgIngredient> filterIngredients(
  List<OrgIngredient> all,
  Map<String, BranchStockRow> stock,
  IngredientFilter filter, {
  required bool hasBranch,
  IngredientView view = IngredientView.active,
}) {
  final archived = view == IngredientView.archived;
  final catalog = [
    for (final it in all)
      if ((it.archivedAt != null) == archived) it,
  ];
  if (!hasBranch || archived) return catalog;
  return switch (filter) {
    IngredientFilter.all => catalog,
    IngredientFilter.low => [
      for (final it in catalog)
        if (stock[it.id]?.belowPar ?? false) it,
    ],
    IngredientFilter.uncounted => [
      for (final it in catalog)
        if (stock[it.id]?.lastCountedAt == null) it,
    ],
  };
}

/// The Status pill of a branch row: none without a row (INV-ING-009).
enum StockStatus { neverCounted, low, ok }

StockStatus? stockStatus(BranchStockRow? s) => s == null
    ? null
    : s.lastCountedAt == null
    ? StockStatus.neverCounted
    : s.belowPar
    ? StockStatus.low
    : StockStatus.ok;

/// The export's Status cell: "Never counted" also without a row.
StockStatus exportStatus(BranchStockRow? s) =>
    stockStatus(s) ?? StockStatus.neverCounted;

/// `parseFloat` of a number input: blank or unreadable is null (the web's
/// NaN goes out as `null` in JSON). Arabic digits are read too.
double? parseNumberInput(String raw) =>
    raw.trim().isEmpty ? null : dashParseNumber(raw);

/// The Standard cost field (EGP) as piastres per unit: blank = unknown
/// (null). Kept to the hundredth of a piastre the field's 0.0001 EGP step
/// allows (divergence INV-ING-020: the web's whole-piastre rounding turned a
/// 0.1-piastre gram of ice into a free one on any save).
double? costInputToPiastres(String raw) {
  final egp = parseNumberInput(raw);
  if (egp == null) return null;
  return (egp * 10000).round() / 100;
}

/// A stored piastre cost as the field shows it (`String(piastres / 100)`).
String costFieldText(double? piastres) =>
    piastres == null ? '' : jsNumberString(piastres / 100);

/// A stored number as its field shows it (`String(n)`), blank for null.
String numberFieldText(num? n) => n == null ? '' : jsNumberString(n);

/// The drawer's cost line (INV-ING-033): the label is "Branch cost" when the
/// branch row has activity and its own cost, else "Standard cost"; the
/// figure is the branch row's cost whenever it has one, else the catalog's.
({bool branchLabel, double? cost}) drawerCost(
  OrgIngredient item,
  BranchStockRow? row,
) => (
  branchLabel: (row?.hasActivity ?? false) && row?.costPerUnit != null,
  cost: row?.costPerUnit ?? item.costPerUnit,
);
