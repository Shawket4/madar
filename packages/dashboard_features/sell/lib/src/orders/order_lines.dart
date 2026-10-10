/// Reading an order's lines for the sheet and the export, ported from the
/// web's pure helpers: `orders/reward-lines.ts`, `orders/staff-drink-lines.ts`,
/// `combos/order-lines.ts`, `discounts/discount-attribution.ts`,
/// `lib/translation.ts` and the sheet's COGS summary.
///
/// Stored totals are already NET (a staff comp, a deal, a reward are off
/// every stored figure): nothing here subtracts them again, it only adds them
/// back to show the price a line would have rung at.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show OrderDeal, OrderFull, OrderItemAddon, OrderItemFull;
import 'package:dashboard_core/dashboard_core.dart' show Translator;

// ── Names ────────────────────────────────────────────────────────────────

/// `getTranslatedName`: the Arabic name when the language is Arabic and a
/// translation is there, else the stored name.
String translatedName(
  String name,
  Map<String, Object?>? translations,
  String lang,
) {
  final ar = translations?['ar'];
  if (lang.startsWith('ar') && ar is String) return ar;
  return name;
}

/// The size label nobody chose (`ONE_SIZE`, `features/menu/util.ts`).
const String oneSize = 'one_size';

/// `order_ref`, else `#display_number`, else `#order_number` (table, sheet).
String orderDisplayRef({
  required String? orderRef,
  required String? displayNumber,
  required int orderNumber,
}) => orderRef ?? '#${displayNumber ?? orderNumber}';

/// `order_ref`, else `#order_number` (void title, export).
String orderPlainRef({required String? orderRef, required int orderNumber}) =>
    orderRef ?? '#$orderNumber';

// ── Rewards (`reward-lines.ts`) ──────────────────────────────────────────

/// One line a loyalty reward paid for.
class RewardLine {
  const RewardLine({
    required this.lineId,
    required this.units,
    required this.covered,
  });

  final String lineId;

  /// Units of the line the reward covered; null when the server did not say.
  final int? units;

  /// Minor units taken off the line.
  final int covered;
}

/// An order's loyalty rewards.
class OrderRewards {
  const OrderRewards({
    required this.memberId,
    required this.memberName,
    required this.lines,
    required this.totalCovered,
    required this.refused,
  });

  /// The member the rewards were redeemed for (a customer id).
  final String? memberId;

  /// Null once that member was forgotten.
  final String? memberName;
  final Map<String, RewardLine> lines;
  final int totalCovered;

  /// Why the server refused to charge points for this sale's rewards.
  final String? refused;
}

String? _nonEmpty(String? s) => (s == null || s.isEmpty) ? null : s;

OrderRewards orderRewards(OrderFull? order) {
  final lines = <String, RewardLine>{};
  var total = 0;
  for (final it in order?.items ?? const <OrderItemFull>[]) {
    final raw = it.rewardCovered ?? 0;
    final covered = raw < 0 ? 0 : raw;
    if (it.isReward != true && covered <= 0) continue;
    lines[it.id] = RewardLine(
      lineId: it.id,
      units: it.rewardUnits,
      covered: covered,
    );
    total += covered;
  }
  return OrderRewards(
    memberId: _nonEmpty(order?.loyaltyCustomerId),
    memberName: _nonEmpty(order?.loyaltyMemberName),
    lines: lines,
    totalCovered: total,
    refused: _nonEmpty(order?.loyaltyRedemptionRefused),
  );
}

// ── Staff drinks (`staff-drink-lines.ts`) ────────────────────────────────

/// What a pooled line rang at normally, what the pool gave free, and what
/// was still charged.
class StaffDrinkLine {
  const StaffDrinkLine({
    required this.normal,
    required this.comp,
    required this.charged,
  });

  final int normal;
  final int comp;
  final int charged;
}

int _pos(int? v) => (v ?? 0) < 0 ? 0 : (v ?? 0);

bool isStaffDrinkLine(OrderItemFull it) =>
    (it.staffCompMinor ?? 0) > 0 || _nonEmpty(it.staffDrinkId) != null;

StaffDrinkLine? staffDrinkLine(OrderItemFull it) {
  if (!isStaffDrinkLine(it)) return null;
  final comp = _pos(it.staffCompMinor);
  final addons = it.addons.fold<int>(0, (s, a) => s + a.lineTotal);
  // An optional carries a per-unit price and no total of its own.
  final optionals =
      it.optionals.fold<int>(0, (s, o) => s + o.price) * it.quantity;
  final charged = it.lineTotal + addons + optionals;
  return StaffDrinkLine(normal: charged + comp, comp: comp, charged: charged);
}

/// What an add-on rings at normally: its stored total with its comp back.
int addonNormalTotal(OrderItemAddon a) => a.lineTotal + _pos(a.staffCompMinor);

/// Everything the pool gave free across an order (0 on an ordinary sale).
int orderStaffComp(Iterable<OrderItemFull> items) =>
    items.fold<int>(0, (s, it) => s + _pos(it.staffCompMinor));

// ── Combos and deals (`combos/order-lines.ts`) ───────────────────────────

/// One row of the sheet's Items card.
sealed class OrderRow {
  const OrderRow(this.line);
  final OrderItemFull line;
}

/// A combo's header line, its parts, and what the whole combo rang at.
class ComboRow extends OrderRow {
  const ComboRow(super.line, {required this.parts, required this.total});
  final List<OrderItemFull> parts;
  final int total;
}

/// A plain line, or one part of a combo (indented under its header).
class LineRow extends OrderRow {
  const LineRow(super.line, {required this.part});
  final bool part;
}

int _withAddons(OrderItemFull l) =>
    l.lineTotal + l.addons.fold<int>(0, (s, a) => s + a.lineTotal);

/// The lines in the order to show them: each combo header followed by its
/// parts, everything else as it came. A part whose header is missing still
/// shows, as a plain line — money is never hidden.
List<OrderRow> orderRows(List<OrderItemFull> items) {
  final headers = {
    for (final l in items)
      if (l.lineKind == 'combo') l.id,
  };
  bool partOfHeader(OrderItemFull l) =>
      l.lineKind == 'combo_part' &&
      l.comboLineId != null &&
      l.comboLineId!.isNotEmpty &&
      headers.contains(l.comboLineId);
  final partsOf = <String, List<OrderItemFull>>{};
  for (final l in items) {
    if (partOfHeader(l)) (partsOf[l.comboLineId!] ??= []).add(l);
  }
  final out = <OrderRow>[];
  for (final l in items) {
    if (l.lineKind == 'combo') {
      final parts = partsOf[l.id] ?? const <OrderItemFull>[];
      out.add(
        ComboRow(
          l,
          parts: parts,
          total: parts.fold<int>(0, (s, p) => s + _withAddons(p)),
        ),
      );
      for (final p in parts) {
        out.add(LineRow(p, part: true));
      }
    } else if (!partOfHeader(l)) {
      out.add(LineRow(l, part: false));
    }
  }
  return out;
}

/// The deals on an order (an older server sends none).
List<OrderDeal> dealsOf(OrderFull? order) => order?.deals ?? const [];

/// Everything the order's deals took off.
int orderDealsTotal(Iterable<OrderDeal> deals) =>
    deals.fold<int>(0, (s, d) => s + (d.discount < 0 ? 0 : d.discount));

/// The deal that cut [lineId], if listed.
OrderDeal? dealOfLine(List<OrderDeal> deals, String lineId) {
  for (final d in deals) {
    if (d.lines.any((l) => l.orderItemId == lineId)) return d;
  }
  return null;
}

// ── Discount attribution (`discounts/discount-attribution.ts`) ──────────

/// A label for a discount kind; null / unknown reads as "Not recorded".
String discountKindLabel(Translator t, String? kind) => switch (kind) {
  'preset' => t('discounts.kind.preset'),
  'manual_amount' => t('discounts.kind.manualAmount'),
  'manual_percent' => t('discounts.kind.manualPercent'),
  _ => t('discounts.kind.unattributed'),
};

/// Basis points → `12.5%` (an integer percentage has no decimals; otherwise
/// two, with one trailing 0 dropped).
String? bpsLabel(int? bps) {
  if (bps == null) return null;
  final pct = bps / 100;
  if (pct == pct.truncateToDouble()) return '${pct.toStringAsFixed(0)}%';
  final two = pct.toStringAsFixed(2);
  return '${two.endsWith('0') ? two.substring(0, two.length - 1) : two}%';
}

/// "Amount by hand · 12.5% · by Sara · approved by Omar", or null when the
/// sale recorded no kind.
String? discountAttribution(Translator t, OrderFull o) {
  final kind = o.discountKind;
  if (kind == null || kind.isEmpty) return null;
  final parts = [discountKindLabel(t, kind)];
  final pct = bpsLabel(o.discountPercentBps);
  if (pct != null) parts.add(pct);
  final by = _nonEmpty(o.discountAppliedByName);
  if (by != null) parts.add(t('discounts.appliedBy', args: {'name': by}));
  final ok = _nonEmpty(o.discountApprovedByName);
  if (ok != null) parts.add(t('discounts.approvedBy', args: {'name': ok}));
  return parts.join(' · ');
}

// ── COGS (`order-detail-sheet.tsx:134-138`) ──────────────────────────────

/// The known cost of the lines, whether any line's cost is missing (then the
/// COGS is a lower bound and the profit an upper one), the profit and its
/// share of the total (null when the total is not positive).
class OrderCogs {
  const OrderCogs({
    required this.known,
    required this.anyMissing,
    required this.profit,
    required this.profitShare,
  });

  final int known;
  final bool anyMissing;
  final int profit;
  final double? profitShare;
}

OrderCogs orderCogs(OrderFull o) {
  var known = 0;
  var missing = false;
  for (final li in o.items) {
    if (li.lineCost != null) known += li.lineCost!;
    if (li.costMissing || li.lineCost == null) missing = true;
  }
  final profit = o.totalAmount - known;
  return OrderCogs(
    known: known,
    anyMissing: missing,
    profit: profit,
    profitShare: o.totalAmount > 0 ? profit / o.totalAmount : null,
  );
}

// ── Ingredient deductions (`order-detail-sheet.tsx:39-46`, `:99-105`) ────

/// One ingredient a line used, read leniently off `deductions_snapshot`.
class Deduction {
  const Deduction({
    required this.ingredientName,
    required this.quantity,
    required this.unit,
    this.source,
    this.category,
    this.orgIngredientId,
    this.cost,
  });

  final String ingredientName;
  final double quantity;
  final String unit;
  final String? source;
  final String? category;
  final String? orgIngredientId;

  /// The snapshot's own cost (piastres), when it carried one.
  final double? cost;

  /// The snapshot's cost, else quantity × the catalogue's cost per unit.
  double? costWith(Map<String, double> costPerUnit) {
    if (cost != null) return cost;
    final id = orgIngredientId;
    final per = id == null ? null : costPerUnit[id];
    return per == null ? null : quantity * per;
  }
}

double _num(Object? v) => v is num ? v.toDouble() : 0;

/// The deductions of a line (`[]` when the snapshot is not a list).
List<Deduction> deductionsOf(OrderItemFull it) {
  final raw = it.deductionsSnapshot;
  if (raw is! List) return const [];
  return [
    for (final d in raw)
      if (d is Map)
        Deduction(
          ingredientName: (d['ingredient_name'] ?? '').toString(),
          quantity: _num(d['quantity']),
          unit: (d['unit'] ?? '').toString(),
          source: d['source']?.toString(),
          category: d['category']?.toString(),
          orgIngredientId: d['org_ingredient_id']?.toString(),
          cost: d['cost'] is num ? (d['cost']! as num).toDouble() : null,
        ),
  ];
}
