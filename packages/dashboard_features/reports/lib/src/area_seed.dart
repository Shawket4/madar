/// The reports area's own domain data and the rules several units read it
/// by, so their figures agree with each other and with the core seed:
///
/// - **Branch narrowing** for `/reports/branches/{scopeBranchId}/…`: the
///   all-branches sentinel means every Sabah branch the persona may see
///   (REP-OPS-066); a named branch must be one of them.
/// - **The sold set and its sums** over the core seed's orders — the same
///   definition the backend uses (`status NOT IN ('voided','refunded')`,
///   revenue by the tendered legs), so Operations › Overview, Financial ›
///   Revenue/Channel, Legal › Tax and Till sessions agree to the piastre.
/// - **What each menu item costs to make** (Financial profitability, Bundles
///   cost, Staff drinks cost-to-make), with two items whose recipe is
///   incomplete (cost unknown).
/// - **The inventory catalog**: suppliers, ingredients by catalog category,
///   each delivery's unit cost over the last weeks, per-branch stock and
///   daily use (Financial valuation / supplier spend / material cost trend;
///   Inventory reports consumption / PO lead time / low stock).
///
/// Units extend this in their own `mock/<unit>_mock.dart`; nothing here is
/// mutated, so a test's handlers can rely on it.
library;

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart' show allBranchesId;

// ── branch narrowing ──────────────────────────────────────────────────────

/// The branches a report read covers: [branchId] itself (403 unless the
/// persona sees it), or for the all-branches sentinel every Sabah branch the
/// persona sees.
List<String> reportBranchIds(MockRequest req, String branchId) {
  if (branchId == allBranchesId) {
    return [
      for (final b in SeedIds.sabahBranches)
        if (req.persona.seesBranch(b)) b,
    ];
  }
  req.requireBranch(branchId);
  return [branchId];
}

// ── orders and the sold set ───────────────────────────────────────────────

/// The core seed's orders at [branchIds] created within [from]…[to]
/// (inclusive, as the web's day-bounded instants are), oldest first.
List<MockRow> reportOrders(
  MockDb db, {
  required Iterable<String> branchIds,
  DateTime? from,
  DateTime? to,
}) {
  final ids = branchIds.toSet();
  final fromMs = from?.toUtc().millisecondsSinceEpoch;
  final toMs = to?.toUtc().millisecondsSinceEpoch;
  return [
    for (final o in db['orders'].rows)
      if (ids.contains(o['branch_id']) &&
          _within(o['created_at'], fromMs, toMs))
        o,
  ];
}

bool _within(Object? iso, int? fromMs, int? toMs) {
  if (iso is! String) return false;
  final at = DateTime.tryParse(iso)?.millisecondsSinceEpoch;
  if (at == null) return false;
  if (fromMs != null && at < fromMs) return false;
  if (toMs != null && at > toMs) return false;
  return true;
}

/// Whether an order is in the sold set (not voided, not refunded).
bool isSold(MockRow order) {
  final s = order['status'];
  return s != 'voided' && s != 'refunded';
}

int _int(Object? v) => v is num ? v.toInt() : 0;

/// The sums every sales figure in the area is built from. Money in piastres.
class ReportSales {
  ReportSales._();

  /// Sold orders (`total_orders`).
  int orders = 0;

  /// Voided orders (`voided_orders`).
  int voided = 0;
  int subtotal = 0;
  int discount = 0;
  int tax = 0;

  /// `total_revenue`: Σ total_amount over the sold set (the seed has no
  /// refunds, so gross = net).
  int revenue = 0;

  /// Revenue by the method actually tendered (each payment leg), so a split
  /// bill counts under cash and card, never under "mixed".
  final Map<String, int> byMethod = {};

  /// Revenue and orders by `order_type` (dine_in, takeaway, delivery).
  final Map<String, int> revenueByChannel = {};
  final Map<String, int> ordersByChannel = {};

  /// Average order value, rounded (0 with no orders).
  int get aov => orders == 0 ? 0 : (revenue / orders).round();

  /// `subtotal − discount_amount` (the Tax tab's taxable sales).
  int get taxable => subtotal - discount;
}

/// Sums [orders] the backend's way.
ReportSales summarizeSales(Iterable<MockRow> orders) {
  final s = ReportSales._();
  for (final o in orders) {
    if (o['status'] == 'voided') {
      s.voided++;
      continue;
    }
    if (!isSold(o)) continue;
    final total = _int(o['total_amount']);
    s
      ..orders += 1
      ..subtotal += _int(o['subtotal'])
      ..discount += _int(o['discount_amount'])
      ..tax += _int(o['tax_amount'])
      ..revenue += total;
    final legs = o['payment_legs'];
    if (legs is List && legs.isNotEmpty) {
      for (final l in legs) {
        if (l is Map) {
          final m = '${l['method']}';
          s.byMethod[m] = (s.byMethod[m] ?? 0) + _int(l['amount']);
        }
      }
    } else {
      final m = '${o['payment_method']}';
      s.byMethod[m] = (s.byMethod[m] ?? 0) + total;
    }
    final channel = '${o['order_type']}';
    s.revenueByChannel[channel] = (s.revenueByChannel[channel] ?? 0) + total;
    s.ordersByChannel[channel] = (s.ordersByChannel[channel] ?? 0) + 1;
  }
  return s;
}

// ── menu costs ────────────────────────────────────────────────────────────

/// Items whose recipe is incomplete: their cost is unknown (the ledger's
/// "No recipe" flag, a Bundles cost floor, a Staff drink's "—").
const Set<String> costUnknownItems = {'v60', 'shakshuka'};

/// Cost to make as a share of the price, by seed category.
const Map<String, double> _costShare = {
  'hot': 0.24,
  'iced': 0.27,
  'tea': 0.22,
  'juice': 0.36,
  'bakery': 0.38,
  'dessert': 0.33,
  'breakfast': 0.41,
};

/// The wire's size label for a line: the size's label, or `one_size` for a
/// single-size item (how the ledger, repricing and the mix name it).
String reportSizeLabel(SeedItem item, int sizeIndex) =>
    item.sizes.length > 1 ? item.sizes[sizeIndex].$1 : 'one_size';

/// What one unit of [itemKey] at [sizeLabel] (`one_size` or a size label)
/// costs to make, in piastres; null when the recipe is incomplete or the
/// item/size is unknown.
int? menuUnitCost(String itemKey, String sizeLabel) {
  if (costUnknownItems.contains(itemKey)) return null;
  final item = seedMenuItem(itemKey);
  if (item == null) return null;
  final size = item.sizes.length == 1
      ? item.sizes.first
      : item.sizes.where((s) => s.$1 == sizeLabel).firstOrNull;
  if (size == null) return null;
  final share = _costShare[item.category] ?? 0.3;
  // Rounded to a whole 25 piastres, as recipe costs read.
  return ((size.$2 * 100 * share) / 25).round() * 25;
}

/// A seed menu item by key.
SeedItem? seedMenuItem(String key) =>
    seedMenu.where((m) => m.key == key).firstOrNull;

/// A seed menu item by its menu item id.
SeedItem? seedMenuItemById(String menuItemId) =>
    seedMenu.where((m) => MockSeed.menuItemId(m.key) == menuItemId).firstOrNull;

// ── the inventory catalog ─────────────────────────────────────────────────

/// A supplier the org buys from.
class ReportSupplier {
  const ReportSupplier(this.key, this.name, this.leadDays);

  final String key;
  final String name;

  /// Days from ordering to receiving, typically.
  final double leadDays;

  String get id => mockUuid('reports:supplier:$key');
}

const List<ReportSupplier> reportSuppliers = [
  ReportSupplier('nile_roastery', 'Nile Roastery', 2.5),
  ReportSupplier('horizon_coffee', 'Horizon Coffee Traders', 4),
  ReportSupplier('delta_dairy', 'Delta Dairy Co.', 1),
  ReportSupplier('green_valley', 'Green Valley Farms', 1.5),
  ReportSupplier('obour_produce', 'Obour Fresh Produce', 1),
  ReportSupplier('sweet_line', 'Sweet Line Syrups', 3),
  ReportSupplier('golden_mill', 'Golden Mill Supplies', 2),
  ReportSupplier('cairo_pack', 'Cairo Packaging Supply', 5),
];

ReportSupplier reportSupplier(String key) =>
    reportSuppliers.firstWhere((s) => s.key == key);

/// An inventory catalog category.
class ReportCatalogCategory {
  const ReportCatalogCategory(this.key, this.name, this.ar);

  final String key;
  final String name;
  final String ar;

  String get id => mockUuid('reports:catalog-category:$key');
}

const List<ReportCatalogCategory> reportCatalogCategories = [
  ReportCatalogCategory('coffee', 'Coffee', 'قهوة'),
  ReportCatalogCategory('dairy', 'Dairy', 'ألبان'),
  ReportCatalogCategory('syrups', 'Syrups & sauces', 'شراب وصوصات'),
  ReportCatalogCategory('tea', 'Tea & powders', 'شاي ومساحيق'),
  ReportCatalogCategory('produce', 'Fruit & produce', 'فواكه وخضروات'),
  ReportCatalogCategory('bakery', 'Bakery supplies', 'مستلزمات المخبز'),
  ReportCatalogCategory('packaging', 'Packaging', 'تغليف'),
];

/// One ingredient: where it is bought, what each delivery cost, how much a
/// branch keeps and uses.
class ReportIngredient {
  const ReportIngredient(
    this.key,
    this.name,
    this.ar,
    this.category,
    this.unit,
    this.supplier,
    this.deliveries, {
    required this.parMin,
    required this.dailyUse,
    this.cheaper,
  });

  final String key;
  final String name;
  final String ar;

  /// [ReportCatalogCategory.key].
  final String category;

  /// `g`, `kg`, `ml`, `L` or `pcs`.
  final String unit;

  /// [ReportSupplier.key] of the current supplier.
  final String supplier;

  /// Unit cost of each delivery this period, oldest first, in piastres per
  /// [unit]. Empty = never delivered: its cost (and stock value) is unknown.
  final List<int> deliveries;

  /// Reorder point per branch, in [unit].
  final double parMin;

  /// Typical use per branch per day, in [unit].
  final double dailyUse;

  /// A cheaper current offer: (supplier key, unit cost in piastres).
  final (String, int)? cheaper;

  String get id => mockUuid('reports:ingredient:$key');

  /// The current unit cost (the last delivery), or null when unknown.
  int? get unitCost => deliveries.isEmpty ? null : deliveries.last;

  /// Straight price rises at the end of [deliveries] (the material cost
  /// trend lists three or more).
  int get risingStreak {
    var n = 0;
    for (var i = deliveries.length - 1; i > 0; i--) {
      if (deliveries[i] > deliveries[i - 1]) {
        n++;
      } else {
        break;
      }
    }
    return n;
  }

  /// The rise over the streak, as a percent of where it started.
  double get streakPct {
    final n = risingStreak;
    if (n == 0) return 0;
    final start = deliveries[deliveries.length - 1 - n];
    return (deliveries.last - start) / start * 100;
  }

  /// Par level to order up to (three times the reorder point).
  double get parMax => parMin * 3;
}

const List<ReportIngredient> reportIngredients = [
  ReportIngredient(
    'espresso_beans',
    'Espresso beans (house blend)',
    'بن إسبريسو (خلطة البيت)',
    'coffee',
    'kg',
    'nile_roastery',
    [128000, 132000, 138000, 144000],
    parMin: 6,
    dailyUse: 2.4,
    cheaper: ('horizon_coffee', 136000),
  ),
  ReportIngredient(
    'decaf_beans',
    'Decaf beans',
    'بن منزوع الكافيين',
    'coffee',
    'kg',
    'nile_roastery',
    [152000, 152000],
    parMin: 1,
    dailyUse: 0.2,
  ),
  ReportIngredient(
    'whole_milk',
    'Whole milk',
    'حليب كامل الدسم',
    'dairy',
    'L',
    'delta_dairy',
    [3800, 3950, 4100, 4300],
    parMin: 40,
    dailyUse: 22,
    cheaper: ('green_valley', 3900),
  ),
  ReportIngredient(
    'oat_milk',
    'Oat milk',
    'حليب الشوفان',
    'dairy',
    'L',
    'delta_dairy',
    [11500, 11500, 11000],
    parMin: 8,
    dailyUse: 3,
  ),
  ReportIngredient(
    'cream',
    'Whipping cream',
    'كريمة خفق',
    'dairy',
    'L',
    'delta_dairy',
    [18500, 19000],
    parMin: 4,
    dailyUse: 1.2,
  ),
  ReportIngredient(
    'halloumi',
    'Halloumi',
    'جبنة حلومي',
    'dairy',
    'kg',
    'delta_dairy',
    [42000],
    parMin: 3,
    dailyUse: 0.8,
  ),
  ReportIngredient(
    'vanilla_syrup',
    'Vanilla syrup',
    'شراب الفانيليا',
    'syrups',
    'L',
    'sweet_line',
    [42000, 42000],
    parMin: 3,
    dailyUse: 0.6,
  ),
  ReportIngredient(
    'caramel_sauce',
    'Caramel sauce',
    'صوص الكراميل',
    'syrups',
    'kg',
    'sweet_line',
    [38000, 39500],
    parMin: 3,
    dailyUse: 0.5,
  ),
  ReportIngredient(
    'chocolate_sauce',
    'Chocolate sauce',
    'صوص الشوكولاتة',
    'syrups',
    'kg',
    'sweet_line',
    [41000],
    parMin: 3,
    dailyUse: 0.7,
  ),
  ReportIngredient(
    'matcha',
    'Matcha powder',
    'مسحوق الماتشا',
    'tea',
    'kg',
    'golden_mill',
    [520000, 545000],
    parMin: 1,
    dailyUse: 0.15,
  ),
  ReportIngredient(
    'chai',
    'Chai concentrate',
    'مركز التشاي',
    'tea',
    'L',
    'sweet_line',
    [],
    parMin: 3,
    dailyUse: 0.5,
  ),
  ReportIngredient(
    'oranges',
    'Oranges',
    'برتقال',
    'produce',
    'kg',
    'obour_produce',
    [1800, 2000, 2300],
    parMin: 25,
    dailyUse: 9,
  ),
  ReportIngredient(
    'strawberries',
    'Strawberries',
    'فراولة',
    'produce',
    'kg',
    'obour_produce',
    [6000, 6500],
    parMin: 6,
    dailyUse: 2,
  ),
  ReportIngredient(
    'avocados',
    'Avocados',
    'أفوكادو',
    'produce',
    'pcs',
    'obour_produce',
    [3500, 3600, 3800, 4100],
    parMin: 20,
    dailyUse: 7,
  ),
  ReportIngredient(
    'butter',
    'Butter',
    'زبدة',
    'bakery',
    'kg',
    'golden_mill',
    [52000, 53500],
    parMin: 4,
    dailyUse: 1,
  ),
  ReportIngredient(
    'croissant_dough',
    'Croissant dough',
    'عجينة كرواسون',
    'bakery',
    'pcs',
    'golden_mill',
    [900, 950],
    parMin: 60,
    dailyUse: 30,
  ),
  ReportIngredient(
    'cups_12oz',
    'Cups 12 oz',
    'أكواب 12 أونصة',
    'packaging',
    'pcs',
    'cairo_pack',
    [140, 150],
    parMin: 400,
    dailyUse: 70,
  ),
  ReportIngredient(
    'lids',
    'Cup lids',
    'أغطية أكواب',
    'packaging',
    'pcs',
    'cairo_pack',
    [60],
    parMin: 400,
    dailyUse: 70,
  ),
];

ReportIngredient reportIngredient(String key) =>
    reportIngredients.firstWhere((i) => i.key == key);

/// A branch's size relative to the average (its weekday orders), so a busy
/// branch uses and keeps more.
double branchScale(String branchId) {
  for (final b in seedBranches) {
    if (MockSeed.branchIdOf(b.key) == branchId) {
      final mean =
          seedBranches.fold<int>(0, (s, x) => s + x.dailyOrders) /
          seedBranches.length;
      return b.dailyOrders / mean;
    }
  }
  return 1;
}

/// Stock exceptions the low-stock and valuation reads must show: one item
/// below zero (Maadi's oat milk), one empty (Zamalek's strawberries) and one
/// just under its reorder point (New Cairo's whole milk).
final Map<(String, String), double> _stockOverrides = {
  (SeedIds.maadi, 'oat_milk'): -2,
  (SeedIds.zamalek, 'strawberries'): 0,
  (SeedIds.newCairo, 'whole_milk'): 31,
};

/// What [branchId] holds of [ingredientKey] now, in its unit (one decimal).
double onHand(String branchId, String ingredientKey) {
  final forced = _stockOverrides[(branchId, ingredientKey)];
  if (forced != null) return forced;
  final ing = reportIngredient(ingredientKey);
  final rng = MockRandom('reports:stock:$branchId:$ingredientKey');
  // Between 1.1× and 2.6× the reorder point, scaled to the branch.
  final q = ing.parMin * branchScale(branchId) * (1.1 + rng.nextDouble() * 1.5);
  return (q * 10).round() / 10;
}

/// What [branchId] used of [ingredientKey] over [days] days, in its unit.
double usedOver(String branchId, String ingredientKey, int days) {
  final ing = reportIngredient(ingredientKey);
  return ((ing.dailyUse * branchScale(branchId) * days) * 10).round() / 10;
}

/// One received purchase-order line: the ingredient, the branch, when it
/// was ordered and received, how much and at what unit cost.
class ReportDelivery {
  const ReportDelivery({
    required this.poId,
    required this.ingredient,
    required this.supplier,
    required this.branchId,
    required this.orderedAt,
    required this.receivedAt,
    required this.quantity,
    required this.unitCost,
  });

  final String poId;
  final String ingredient;
  final String supplier;
  final String branchId;
  final DateTime orderedAt;
  final DateTime receivedAt;
  final double quantity;
  final int unitCost;

  /// The line's cost in piastres.
  int get total => (quantity * unitCost).round();

  double get leadDays => receivedAt.difference(orderedAt).inMinutes / (24 * 60);
}

/// Every delivery of the last four weeks, oldest first: each ingredient's
/// [ReportIngredient.deliveries] spread evenly over 28 days, at every Sabah
/// branch, received after the supplier's lead time. Purchase orders group a
/// supplier's lines per branch and day.
final List<ReportDelivery> reportDeliveries = () {
  final out = <ReportDelivery>[];
  final today = MockClock.startOfCairoDay(MockSeed.now);
  for (final ing in reportIngredients) {
    final n = ing.deliveries.length;
    final sup = reportSupplier(ing.supplier);
    for (var i = 0; i < n; i++) {
      // The last delivery lands two days ago; earlier ones every 28/n days.
      final daysAgo = 2 + ((n - 1 - i) * 28 / n).round();
      for (final b in SeedIds.sabahBranches) {
        final rng = MockRandom('reports:po:${ing.key}:$b:$i');
        final ordered = today
            .subtract(Duration(days: daysAgo))
            .add(Duration(hours: 9, minutes: rng.nextInt(120)));
        final lead = sup.leadDays * (0.8 + rng.nextDouble() * 0.4);
        final received = ordered.add(
          Duration(minutes: (lead * 24 * 60).round()),
        );
        final qty = (ing.parMax * branchScale(b) * 10).round() / 10;
        out.add(
          ReportDelivery(
            poId: mockUuid('reports:po:${sup.key}:$b:$daysAgo'),
            ingredient: ing.key,
            supplier: sup.key,
            branchId: b,
            orderedAt: ordered,
            receivedAt: received,
            quantity: qty,
            unitCost: ing.deliveries[i],
          ),
        );
      }
    }
  }
  out.sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
  return List<ReportDelivery>.unmodifiable(out);
}();

/// Deliveries received at [branchIds] within [from]…[to].
List<ReportDelivery> deliveriesIn({
  required Iterable<String> branchIds,
  DateTime? from,
  DateTime? to,
}) {
  final ids = branchIds.toSet();
  return [
    for (final d in reportDeliveries)
      if (ids.contains(d.branchId) &&
          (from == null || !d.receivedAt.isBefore(from)) &&
          (to == null || !d.receivedAt.isAfter(to)))
        d,
  ];
}
