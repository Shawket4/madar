/// The inventory area's shared vocabulary and pure helpers: the port of the
/// web's `src/features/inventory/lib.ts` (its `lib.test.ts` vectors are the
/// reference; see `test/shared/inventory_lib_test.dart`).
///
/// Model (inventory v2): the org catalog is the only setup. Every branch sees
/// the whole catalog; a row with `has_activity = false` has simply never moved
/// or been counted there. Stock only changes through the ledger — the
/// dashboard never writes an on-hand figure, it counts, wastes, transfers or
/// receives.
library;

import 'package:dashboard_api/dashboard_api.dart' show ItemCountInput;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart' show DashTone;

// ── Enums (mirror the backend) ─────────────────────────────────────────────

/// `VARIANCE_REASONS`, in the web's order (labels `inventory.varianceReasons.*`).
const List<String> varianceReasons = [
  'theft',
  'spoilage',
  'breakage',
  'miscount',
  'supplier_short',
  'transfer_error',
  'other',
];

/// `WASTE_REASONS` a person may pick (labels `inventory.waste.reasons.*`;
/// the server also writes `refund` and `order_cancelled`).
const List<String> wasteReasons = [
  'expired',
  'spoiled',
  'damaged',
  'overproduction',
  'theft',
  'other',
];

/// `PO_STATUSES` (labels `inventory.purchasing.statuses.*`; `draft` reads
/// "Open").
const List<String> poStatuses = [
  'draft',
  'ordered',
  'partially_received',
  'received',
  'cancelled',
];

/// The stock units the catalog supports (`UNITS`; labels `units.*`).
const List<String> inventoryUnits = ['g', 'kg', 'ml', 'l', 'pcs'];

/// The all-branches sentinel branch-scoped endpoints accept
/// (`ALL_BRANCHES_ID`); [Scope.scopeBranchId] gives it.
const String inventoryAllBranchesId = allBranchesId;

// ── Measure families (the backend converts only within a family) ───────────

enum MeasureFamily { weight, volume, count }

MeasureFamily unitFamily(String unit) => switch (unit) {
  'g' || 'kg' => MeasureFamily.weight,
  'ml' || 'l' => MeasureFamily.volume,
  _ => MeasureFamily.count,
};

/// The units an ingredient of [unit] may be bought or re-measured in.
List<String> unitsForFamily(String unit) => switch (unitFamily(unit)) {
  MeasureFamily.weight => const ['g', 'kg'],
  MeasureFamily.volume => const ['ml', 'l'],
  MeasureFamily.count => const ['pcs'],
};

// ── Purchase costs: the invoice total is the truth ─────────────────────────

const Map<String, num> _unitScale = {
  'g': 1,
  'kg': 1000,
  'ml': 1,
  'l': 1000,
  'pcs': 1,
};

/// Base stock units in one purchase unit (a kg of a gram item → 1000). A
/// named pack, an unknown unit or another measure reads as 1.
num stockUnitsPer(String purchaseUnit, String stockUnit) {
  final p = _unitScale[purchaseUnit];
  final s = _unitScale[stockUnit];
  if (p == null || s == null) return 1;
  if (unitFamily(purchaseUnit) != unitFamily(stockUnit)) return 1;
  return p / s;
}

/// A line's unit cost DERIVED from its total, in piastres per purchase unit,
/// unrounded; null until both are known.
double? unitCostFromTotal(num linePiastres, num qty) =>
    linePiastres.isFinite && linePiastres >= 0 && qty.isFinite && qty > 0
    ? linePiastres / qty
    : null;

/// The catalog's estimate of a line's total in whole piastres; null when the
/// catalog has no cost or the quantity is not positive.
int? estimateLineTotal(
  num? catalogCostPerStockUnit,
  num qty,
  String purchaseUnit,
  String stockUnit,
) => catalogCostPerStockUnit != null && qty.isFinite && qty > 0
    ? jsRound(
        catalogCostPerStockUnit * qty * stockUnitsPer(purchaseUnit, stockUnit),
      )
    : null;

/// Fraction digits a unit cost is shown with (EGP), always all of them.
const int unitCostDigits = 6;

/// A unit cost in EGP from piastres per unit, at exactly [unitCostDigits]
/// decimals (`0.045680`), in the active language's grouping.
String formatUnitCost(DashFormat f, num piastresPerUnit) => f.fmtNumber(
  piastresPerUnit / 100,
  const NumberOptions(
    minimumFractionDigits: unitCostDigits,
    maximumFractionDigits: unitCostDigits,
  ),
);

/// `Math.round`: halves go up (also for negatives, unlike Dart's `round`).
int jsRound(num v) => (v + 0.5).floor();

// ── Stock counts ───────────────────────────────────────────────────────────

/// A counted row is flagged when |counted − book| is at least [thresholdPct]
/// percent of book stock, or when stock appears from / vanishes to zero.
bool isVarianceFlagged(num book, num? counted, num thresholdPct) {
  if (counted == null) return false;
  if (book.abs() < 1e-9) return counted.abs() > 1e-9;
  return (counted - book).abs() / book.abs() * 100 >= thresholdPct;
}

/// Parses a count input; blank or non-numeric means "not counted"
/// (`parseFloat`: a leading number is read, `"12abc"` → 12).
double? parseCount(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final m = RegExp(
    r'^\s*[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?',
  ).firstMatch(raw);
  if (m == null) return null;
  final n = double.tryParse(m.group(0)!.trim());
  return n != null && n.isFinite ? n : null;
}

/// The `PUT /stocktakes/{id}/items` payload: one entry per row with a count,
/// carrying its reason (or an explicit null).
List<ItemCountInput> buildCountPayload(
  List<String> rowIds,
  Map<String, String> counts,
  Map<String, String> reasons,
) => [
  for (final id in rowIds)
    if (parseCount(counts[id]) case final qty?)
      ItemCountInput(
        orgIngredientId: id,
        countedQty: qty,
        varianceReason: (reasons[id] ?? '').isEmpty ? null : reasons[id],
        explicitNulls: (reasons[id] ?? '').isEmpty
            ? const {'variance_reason'}
            : const {},
      ),
];

/// One editor row as [missingReasons] needs it.
typedef CountRowRef = ({String orgIngredientId, String name, num bookQty});

/// Names of counted rows that are flagged but carry no reason yet.
List<String> missingReasons(
  Iterable<CountRowRef> items,
  Map<String, String> counts,
  Map<String, String> reasons,
  num thresholdPct,
) => [
  for (final it in items)
    if (parseCount(counts[it.orgIngredientId]) case final counted?)
      if (isVarianceFlagged(it.bookQty, counted, thresholdPct) &&
          (reasons[it.orgIngredientId] ?? '').isEmpty)
        it.name,
];

/// An open count: `in_progress` or `draft`.
bool isOpenStocktake(String status) =>
    status == 'in_progress' || status == 'draft';

/// True when the branch has never finalized a count (the first-run entrance);
/// false while the list is unknown.
bool needsFirstCount(Iterable<String>? statuses) =>
    statuses != null && !statuses.contains('finalized');

const int countDueDays = 14;

/// Catalog rows a branch should count: never counted, or counted longer than
/// [countDueDays] ago.
int countsDue(Iterable<String?> lastCountedAt, DateTime now) {
  const window = countDueDays * 86400000;
  var n = 0;
  for (final iso in lastCountedAt) {
    final at = iso == null ? null : DateTime.tryParse(iso);
    if (at == null ||
        now.millisecondsSinceEpoch - at.millisecondsSinceEpoch > window) {
      n++;
    }
  }
  return n;
}

// ── Badge tones ────────────────────────────────────────────────────────────

const Map<String, DashTone> poStatusTones = {
  'draft': DashTone.neutral,
  'ordered': DashTone.accent,
  'partially_received': DashTone.warning,
  'received': DashTone.success,
  'cancelled': DashTone.danger,
};

const Map<String, DashTone> stocktakeStatusTones = {
  'draft': DashTone.neutral,
  'in_progress': DashTone.accent,
  'finalized': DashTone.success,
  'cancelled': DashTone.danger,
};

// ── Waste ──────────────────────────────────────────────────────────────────

/// Where a waste line came from: `pos` (the till), `dashboard`, `refund` (a
/// refunded sale) or `order` (a made order voided). Older servers send no
/// source: a line tied to an order is a void, anything else was entered here.
String wasteSource({String? wasteSource, String? sourceType}) {
  const known = {'pos', 'order', 'refund', 'dashboard'};
  if (wasteSource != null && known.contains(wasteSource)) return wasteSource;
  if (sourceType == 'refund') return 'refund';
  return sourceType == 'order' ? 'order' : 'dashboard';
}

/// When it happened: on the device for a till's queued waste, else when it
/// was posted.
String wasteWhen({String? occurredAt, required String createdAt}) =>
    occurredAt ?? createdAt;

/// The gap past which the log shows the receive time (5 minutes, either way).
const int receivedLateMs = 5 * 60 * 1000;

/// The receive time when a queued waste reached the server more than
/// [receivedLateMs] off when it happened; null otherwise.
String? wasteReceivedLate({
  String? occurredAt,
  String? receivedAt,
  required String createdAt,
}) {
  final received = receivedAt ?? createdAt;
  if (occurredAt == null) return null;
  final a = DateTime.tryParse(received);
  final b = DateTime.tryParse(occurredAt);
  if (a == null || b == null) return null;
  final gap = (a.millisecondsSinceEpoch - b.millisecondsSinceEpoch).abs();
  return gap > receivedLateMs ? received : null;
}

/// Stock below zero is allowed (an offline till could not know), and always
/// shown as such.
bool isBelowZero(num? onHand) =>
    onHand != null && onHand.isFinite && onHand < 0;

/// More than the source holds (waste and transfer dialogs).
bool exceedsOnHand(num? quantity, num? onHand) =>
    quantity != null && onHand != null && quantity > onHand;
