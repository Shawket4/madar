/// The inventory area's own domain data, over the core seed's org (Sabah
/// Coffee), branches and people: ingredient categories, suppliers, the
/// ingredient catalog, each branch's stock, 30 days of stock movements
/// (sales, deliveries, waste, transfers, count adjustments), stock counts,
/// purchase orders with their receipts, and the org's inventory settings.
///
/// Every figure agrees with every other: each branch's on-hand is fixed by
/// design and the ledger is walked BACKWARD from it, so a movement's
/// `balance_after`, a count's book stock, the waste log, Today's KPIs and the
/// drawer's stock history all tell the same story.
///
/// The story on the seed's clock (2026-10-08 10:00 Cairo):
/// - Zamalek (Karim's branch): 5 items low, 2 critical (Oat Milk below zero
///   after an offline till's sales, Croissant Dough at 0); two deliveries
///   due today (PO-1042, and an unreferenced Delta Dairy order); four waste
///   lines logged this morning; a full count on 20 Sep (so most items are due
///   a count), a milk recount on 4 Oct, a cancelled bakery count on 27 Sep;
///   Hazelnut Syrup and Chai Spice Mix were added after the full count and
///   were never counted there.
/// - Maadi: counted on 30 Sep; a partly received Delta Dairy order overdue
///   since yesterday; Almond Milk and Cup Lids low; it never stocked Blueberry
///   Muffins or Matcha.
/// - New Cairo: a full count is OPEN (started 08:15 today by Dina, 9 rows
///   counted, one flagged row still needs a reason); a draft (Open) syrup
///   order; Sugar and House Blend low; never stocked Dried Hibiscus.
/// - Heliopolis: inventory not started yet — no stock, no counts (the
///   first-run state); one cancelled bakery order.
///
/// Units read these tables through `mock/inventory_views.dart` and may add
/// rows of their own in their mock files.
library;

import 'package:dashboard_api/mock.dart';

/// The [MockDb] tables the inventory area keeps its rows in (JSON in the
/// spec's shape unless noted).
abstract final class InvTables {
  /// `IngredientCategory` (its `ingredient_count` is recomputed on read).
  static const String categories = 'ingredient_categories';

  /// `Supplier`.
  static const String suppliers = 'suppliers';

  /// `OrgIngredient` (its `category_*`/`supplier_name` are refreshed on read).
  static const String ingredients = 'org_ingredients';

  /// One row per (branch, ingredient) the branch has touched — the
  /// backend's `branch_stock`: `{id, branch_id, org_ingredient_id, on_hand,
  /// par_min, par_max, cost_per_unit, last_counted_at, last_movement_at}`.
  /// A pair with no row has `has_activity = false`.
  static const String branchStock = 'branch_stock';

  /// `StockMovement` (sale, purchase_in, waste, transfer_in/out,
  /// stock_count), oldest first.
  static const String movements = 'stock_movements';

  /// `StockTransfer`.
  static const String transfers = 'stock_transfers';

  /// `Stocktake` (without `counted_items`/`total_items`, computed on read).
  static const String stocktakes = 'stocktakes';

  /// `StocktakeItem`.
  static const String stocktakeItems = 'stocktake_items';

  /// `PurchaseOrder`.
  static const String purchaseOrders = 'purchase_orders';

  /// `PurchaseOrderLine`.
  static const String poLines = 'purchase_order_lines';

  /// `GoodsReceipt` (lines inline).
  static const String receipts = 'goods_receipts';

  /// `{id: org_id, org_id, stocktake_variance_threshold_pct}`.
  static const String settings = 'inventory_settings';
}

/// Stable ids of the area's rows.
abstract final class InvIds {
  static String category(String slug) => mockUuid('inv-category:$slug');
  static String supplier(String key) => mockUuid('supplier:$key');
  static String ingredient(String key) => mockUuid('ingredient:$key');
  static String stocktake(String key) => mockUuid('stocktake:$key');
  static String purchaseOrder(String key) => mockUuid('purchase-order:$key');
  static String poLine(String po, int n) =>
      mockUuid('purchase-order:$po:line:$n');
  static String receipt(String key) => mockUuid('goods-receipt:$key');
  static String transfer(String key) => mockUuid('transfer:$key');
  static String branchStock(String branchKey, String ingredientKey) =>
      mockUuid('branch-stock:$branchKey:$ingredientKey');

  /// The till the core seed's orders come from (`Counter 1`).
  static String device(String branchKey) => mockUuid('device:$branchKey:T1');
}

// ── The facts ──────────────────────────────────────────────────────────────

class InvCategorySpec {
  const InvCategorySpec(
    this.slug,
    this.name,
    this.sortOrder, {
    this.packaging = false,
  });

  final String slug;
  final String name;
  final int sortOrder;
  final bool packaging;
}

const List<InvCategorySpec> invCategories = [
  InvCategorySpec('general', 'General', 0),
  InvCategorySpec('coffee_bean', 'Coffee Beans', 1),
  InvCategorySpec('milk', 'Milk', 2),
  InvCategorySpec('dairy', 'Dairy & Eggs', 3),
  InvCategorySpec('syrup', 'Syrups & Sauces', 4),
  InvCategorySpec('dry_goods', 'Dry Goods', 5),
  InvCategorySpec('bakery', 'Bakery', 6),
  InvCategorySpec('packaging', 'Packaging', 7, packaging: true),
];

class InvSupplierSpec {
  const InvSupplierSpec(
    this.key,
    this.name,
    this.contact,
    this.phone,
    this.email, {
    this.active = true,
  });

  final String key;
  final String name;
  final String contact;
  final String phone;
  final String email;
  final bool active;
}

const List<InvSupplierSpec> invSuppliers = [
  InvSupplierSpec(
    'nile-roasters',
    'Nile Roasters',
    'Omar Hassan',
    '+20 100 111 2233',
    'orders@nileroasters.example',
  ),
  InvSupplierSpec(
    'delta-dairy',
    'Delta Dairy',
    'Mona Adel',
    '+20 100 222 3344',
    'sales@deltadairy.example',
  ),
  InvSupplierSpec(
    'metro',
    'Metro Wholesale',
    'Laila Farouk',
    '+20 100 444 5566',
    'b2b@metro.example',
  ),
  InvSupplierSpec(
    'golden-bakery',
    'Golden Bakery Supply',
    'Sherif Nabil',
    '+20 100 555 6677',
    'hello@goldenbakery.example',
  ),
  InvSupplierSpec(
    'packright',
    'PackRight Egypt',
    'Amr Tarek',
    '+20 100 666 7788',
    'sales@packright.example',
  ),
  // Inactive: listed on the Suppliers tab, never offered in a picker, yet
  // still the default supplier of Dried Hibiscus (INV-ALL-023).
  InvSupplierSpec(
    'cairo-fresh',
    'Cairo Fresh Produce',
    'Mahmoud Said',
    '+20 100 333 4455',
    'mahmoud@cairofresh.example',
    active: false,
  ),
];

/// One catalog ingredient. Costs are piastres per base unit; pars and daily
/// use are base units at Zamalek's scale (see [invBranchScale]).
class InvIngredientSpec {
  const InvIngredientSpec(
    this.key,
    this.name,
    this.unit,
    this.cost,
    this.category,
    this.supplier, {
    this.packUnit,
    this.packSize,
    this.yieldPct,
    this.density,
    this.description,
    this.parMin,
    this.parMax,
    this.dailyUse = 0,
    this.active = true,
    this.addedOn,
  });

  final String key;
  final String name;
  final String unit;
  final double? cost;
  final String category;
  final String? supplier;
  final String? packUnit;
  final double? packSize;
  final double? yieldPct;
  final double? density;
  final String? description;
  final double? parMin;
  final double? parMax;
  final double dailyUse;
  final bool active;

  /// When it joined the catalog (`yyyy-mm-dd`); default the catalog's start.
  final String? addedOn;
}

const List<InvIngredientSpec> invIngredients = [
  InvIngredientSpec(
    'house-blend',
    'House Blend Beans',
    'g',
    90,
    'coffee_bean',
    'nile-roasters',
    packUnit: 'bag',
    packSize: 1000,
    description: 'Medium roast espresso blend',
    parMin: 3000,
    parMax: 7000,
    dailyUse: 1400,
  ),
  InvIngredientSpec(
    'ethiopia',
    'Ethiopia Single Origin Beans',
    'g',
    140,
    'coffee_bean',
    'nile-roasters',
    packUnit: 'bag',
    packSize: 1000,
    description: 'Yirgacheffe, washed, light roast',
    parMin: 500,
    parMax: 1500,
    dailyUse: 250,
  ),
  InvIngredientSpec(
    'decaf',
    'Decaf Beans',
    'g',
    110,
    'coffee_bean',
    'nile-roasters',
    packUnit: 'bag',
    packSize: 1000,
    description: 'Swiss-water decaf',
    parMin: 300,
    parMax: 1000,
    dailyUse: 120,
  ),
  InvIngredientSpec(
    'turkish',
    'Turkish Coffee Ground',
    'g',
    60,
    'coffee_bean',
    'nile-roasters',
    packUnit: 'bag',
    packSize: 500,
    description: 'Extra-fine grind',
    parMin: 600,
    parMax: 1500,
    dailyUse: 300,
  ),
  InvIngredientSpec(
    'full-cream',
    'Full Cream Milk',
    'ml',
    4.5,
    'milk',
    'delta-dairy',
    packUnit: 'carton',
    packSize: 1000,
    density: 1.03,
    description: '3% fat',
    parMin: 28000,
    parMax: 70000,
    dailyUse: 14000,
  ),
  InvIngredientSpec(
    'skimmed',
    'Skimmed Milk',
    'ml',
    4.2,
    'milk',
    'delta-dairy',
    packUnit: 'carton',
    packSize: 1000,
    density: 1.03,
    parMin: 5000,
    parMax: 12000,
    dailyUse: 2500,
  ),
  InvIngredientSpec(
    'oat',
    'Oat Milk',
    'ml',
    12,
    'milk',
    'metro',
    packUnit: 'carton',
    packSize: 1000,
    density: 1.02,
    description: 'Barista edition',
    parMin: 4000,
    parMax: 9000,
    dailyUse: 1800,
  ),
  InvIngredientSpec(
    'almond',
    'Almond Milk',
    'ml',
    14,
    'milk',
    'metro',
    packUnit: 'carton',
    packSize: 1000,
    density: 1.02,
    description: 'Unsweetened',
    parMin: 2000,
    parMax: 5000,
    dailyUse: 900,
  ),
  InvIngredientSpec(
    'soy',
    'Soy Milk',
    'ml',
    11,
    'milk',
    'metro',
    packUnit: 'carton',
    packSize: 1000,
    density: 1.02,
    description: 'Discontinued — kept for history',
    active: false,
  ),
  InvIngredientSpec(
    'heavy-cream',
    'Heavy Cream',
    'ml',
    16,
    'dairy',
    'delta-dairy',
    packUnit: 'carton',
    packSize: 1000,
    density: 1.01,
    description: '35% fat',
    parMin: 1500,
    parMax: 3000,
    dailyUse: 600,
  ),
  InvIngredientSpec(
    'whipped-cream',
    'Whipped Cream',
    'g',
    20,
    'dairy',
    'delta-dairy',
    packUnit: 'can',
    packSize: 500,
    parMin: 500,
    parMax: 1500,
    dailyUse: 250,
  ),
  InvIngredientSpec(
    'ice-cream',
    'Vanilla Ice Cream',
    'g',
    18,
    'dairy',
    'delta-dairy',
    packUnit: 'tub',
    packSize: 5000,
    parMin: 1500,
    parMax: 5000,
    dailyUse: 700,
  ),
  InvIngredientSpec(
    'vanilla-syrup',
    'Vanilla Syrup',
    'ml',
    30,
    'syrup',
    'metro',
    packUnit: 'bottle',
    packSize: 750,
    density: 1.3,
    parMin: 1500,
    parMax: 3000,
    dailyUse: 450,
  ),
  InvIngredientSpec(
    'caramel-syrup',
    'Caramel Syrup',
    'ml',
    30,
    'syrup',
    'metro',
    packUnit: 'bottle',
    packSize: 750,
    density: 1.3,
    parMin: 1500,
    parMax: 3000,
    dailyUse: 380,
  ),
  InvIngredientSpec(
    'hazelnut-syrup',
    'Hazelnut Syrup',
    'ml',
    32,
    'syrup',
    'metro',
    packUnit: 'bottle',
    packSize: 750,
    density: 1.3,
    parMin: 750,
    parMax: 1500,
    dailyUse: 200,
    addedOn: '2026-09-25',
  ),
  InvIngredientSpec(
    'chocolate-sauce',
    'Chocolate Sauce',
    'g',
    22,
    'syrup',
    'metro',
    packUnit: 'bottle',
    packSize: 1000,
    parMin: 1000,
    parMax: 2000,
    dailyUse: 300,
  ),
  InvIngredientSpec(
    'sugar',
    'Sugar',
    'g',
    3.5,
    'dry_goods',
    'metro',
    packUnit: 'sack',
    packSize: 10000,
    description: 'White granulated',
    parMin: 3000,
    parMax: 10000,
    dailyUse: 1500,
  ),
  InvIngredientSpec(
    'cocoa',
    'Cocoa Powder',
    'g',
    25,
    'dry_goods',
    'metro',
    packUnit: 'bag',
    packSize: 1000,
    parMin: 300,
    parMax: 1000,
    dailyUse: 150,
  ),
  InvIngredientSpec(
    'matcha',
    'Matcha Powder',
    'g',
    250,
    'dry_goods',
    'metro',
    packUnit: 'tin',
    packSize: 100,
    description: 'Ceremonial grade',
    parMin: 150,
    parMax: 400,
    dailyUse: 45,
  ),
  InvIngredientSpec(
    'chai',
    'Chai Spice Mix',
    'g',
    60,
    'dry_goods',
    'metro',
    packUnit: 'bag',
    packSize: 500,
    parMin: 200,
    parMax: 500,
    dailyUse: 80,
    addedOn: '2026-09-25',
  ),
  InvIngredientSpec(
    'hibiscus',
    'Dried Hibiscus',
    'g',
    null,
    'dry_goods',
    'cairo-fresh',
    packUnit: 'bag',
    packSize: 1000,
    description: 'Cost pending from supplier',
    parMin: 500,
    parMax: 1000,
    dailyUse: 200,
  ),
  InvIngredientSpec(
    'croissant',
    'Croissant Dough',
    'pcs',
    900,
    'bakery',
    'golden-bakery',
    packUnit: 'box',
    packSize: 48,
    description: 'Frozen, bake-off',
    parMin: 30,
    parMax: 96,
    dailyUse: 22,
  ),
  InvIngredientSpec(
    'blueberry-muffin',
    'Blueberry Muffin',
    'pcs',
    1200,
    'bakery',
    'golden-bakery',
    packUnit: 'box',
    packSize: 12,
    parMin: 12,
    parMax: 36,
    dailyUse: 10,
  ),
  InvIngredientSpec(
    'paper-cup-12',
    'Paper Cup 12oz',
    'pcs',
    180,
    'packaging',
    'packright',
    packUnit: 'sleeve',
    packSize: 50,
    parMin: 200,
    parMax: 600,
    dailyUse: 90,
  ),
  InvIngredientSpec(
    'cup-lid',
    'Cup Lid',
    'pcs',
    60,
    'packaging',
    'packright',
    packUnit: 'sleeve',
    packSize: 100,
    parMin: 300,
    parMax: 1000,
    dailyUse: 140,
  ),
  InvIngredientSpec(
    'ice',
    'Ice Cubes',
    'g',
    0.1,
    'general',
    null,
    dailyUse: 9000,
  ),
];

/// Branches that keep stock, with their size against Zamalek. Heliopolis has
/// not started inventory (no stock rows, no counts).
const Map<String, double> invBranchScale = {
  'zamalek': 1.0,
  'maadi': 0.9,
  'new-cairo': 1.2,
};

/// Ingredients a stocking branch has never touched (`has_activity = false`).
const Map<String, Set<String>> invNotStocked = {
  'zamalek': {},
  'maadi': {'blueberry-muffin', 'matcha'},
  'new-cairo': {'hibiscus'},
};

/// On-hand figures set by design (the rest are drawn between the pars).
const Map<String, Map<String, double>> invOnHandOverride = {
  'zamalek': {
    'oat': -350,
    'vanilla-syrup': 600,
    'paper-cup-12': 120,
    'croissant': 0,
    'matcha': 80,
    'full-cream': 30000,
  },
  'maadi': {'almond': 600, 'cup-lid': 90, 'full-cream': 26000},
  'new-cairo': {'sugar': 1800, 'house-blend': 2400},
};

/// A branch's own (moving-average) cost where it differs from the catalog's.
const Map<String, Map<String, double>> invBranchCost = {
  'zamalek': {'house-blend': 92.4},
};

/// The org's count tolerance (`stocktake_variance_threshold_pct`).
const double invVarianceThresholdPct = 5;

// ── Movements by design ────────────────────────────────────────────────────

class InvWasteSpec {
  const InvWasteSpec(
    this.branch,
    this.ingredient,
    this.qty,
    this.reason,
    this.source,
    this.at, {
    required this.by,
    this.occurredAt,
    this.note,
    this.approvedBy,
    this.order,
    this.subject,
    this.subjectSize,
    this.subjectQty,
  });

  final String branch;
  final String ingredient;

  /// Base units wasted (positive; stored negative).
  final double qty;
  final String reason;

  /// `dashboard` | `pos` | `refund` | `order`.
  final String source;

  /// When the server got it (`created_at`).
  final String at;

  /// When it happened on the till, when that differs.
  final String? occurredAt;

  /// Who recorded it (seed person key).
  final String by;
  final String? note;
  final String? approvedBy;

  /// The order's display number (refund / voided order).
  final String? order;

  /// A menu item wasted whole (`From Latte × 2`).
  final String? subject;
  final String? subjectSize;
  final double? subjectQty;
}

const List<InvWasteSpec> invWaste = [
  // This morning at Zamalek.
  InvWasteSpec(
    'zamalek',
    'full-cream',
    500,
    'expired',
    'dashboard',
    '2026-10-08T05:40:00Z',
    by: 'karim',
    note: 'Two cartons past their date',
  ),
  InvWasteSpec(
    'zamalek',
    'croissant',
    4,
    'damaged',
    'pos',
    '2026-10-08T06:12:00Z',
    occurredAt: '2026-10-08T06:10:00Z',
    by: 'mariam',
  ),
  InvWasteSpec(
    'zamalek',
    'house-blend',
    36,
    'spoiled',
    'pos',
    '2026-10-08T06:30:00Z',
    occurredAt: '2026-10-08T06:29:00Z',
    by: 'youssef',
    approvedBy: 'karim',
    subject: 'Latte',
    subjectSize: 'Medium',
    subjectQty: 2,
  ),
  InvWasteSpec(
    'zamalek',
    'full-cream',
    440,
    'spoiled',
    'pos',
    '2026-10-08T06:30:00Z',
    occurredAt: '2026-10-08T06:29:00Z',
    by: 'youssef',
    approvedBy: 'karim',
    subject: 'Latte',
    subjectSize: 'Medium',
    subjectQty: 2,
  ),
  // A till that was offline: logged on the 6th, received on the 7th.
  InvWasteSpec(
    'zamalek',
    'whipped-cream',
    250,
    'expired',
    'pos',
    '2026-10-07T07:05:00Z',
    occurredAt: '2026-10-06T16:20:00Z',
    by: 'mariam',
  ),
  InvWasteSpec(
    'maadi',
    'oat',
    200,
    'refund',
    'refund',
    '2026-10-06T11:15:00Z',
    by: 'hana',
    order: 'MD-261006-T1-0031',
  ),
  InvWasteSpec(
    'new-cairo',
    'blueberry-muffin',
    1,
    'order_cancelled',
    'order',
    '2026-10-05T09:40:00Z',
    by: 'salma',
    order: 'NC-261005-T1-0057',
  ),
  InvWasteSpec(
    'maadi',
    'heavy-cream',
    1000,
    'spoiled',
    'dashboard',
    '2026-10-03T08:20:00Z',
    by: 'tarek',
    note: 'Fridge door left open overnight',
  ),
  InvWasteSpec(
    'new-cairo',
    'sugar',
    500,
    'damaged',
    'dashboard',
    '2026-10-01T10:05:00Z',
    by: 'dina',
    note: 'Sack torn on delivery',
  ),
  InvWasteSpec(
    'zamalek',
    'matcha',
    20,
    'theft',
    'dashboard',
    '2026-09-29T12:30:00Z',
    by: 'karim',
    note: 'Missing from the bar shelf',
  ),
  InvWasteSpec(
    'zamalek',
    'ice-cream',
    500,
    'expired',
    'dashboard',
    '2026-09-25T09:00:00Z',
    by: 'karim',
  ),
  InvWasteSpec(
    'maadi',
    'full-cream',
    1000,
    'expired',
    'dashboard',
    '2026-09-22T08:45:00Z',
    by: 'tarek',
  ),
  InvWasteSpec(
    'new-cairo',
    'croissant',
    6,
    'overproduction',
    'pos',
    '2026-09-18T15:30:00Z',
    occurredAt: '2026-09-18T15:28:00Z',
    by: 'omar',
  ),
  InvWasteSpec(
    'zamalek',
    'cocoa',
    100,
    'other',
    'dashboard',
    '2026-09-15T11:10:00Z',
    by: 'karim',
    note: 'Spilled during restock',
  ),
];

class InvTransferSpec {
  const InvTransferSpec(
    this.key,
    this.from,
    this.to,
    this.ingredient,
    this.qty,
    this.at,
    this.by, {
    this.note,
  });

  final String key;
  final String from;
  final String to;
  final String ingredient;
  final double qty;
  final String at;
  final String by;
  final String? note;
}

const List<InvTransferSpec> invTransfers = [
  InvTransferSpec(
    't1',
    'maadi',
    'zamalek',
    'oat',
    2000,
    '2026-10-06T08:30:00Z',
    'tarek',
    note: 'Zamalek ran short over the weekend',
  ),
  InvTransferSpec(
    't2',
    'new-cairo',
    'maadi',
    'house-blend',
    1000,
    '2026-10-03T07:50:00Z',
    'dina',
  ),
  InvTransferSpec(
    't3',
    'zamalek',
    'new-cairo',
    'paper-cup-12',
    100,
    '2026-09-30T09:15:00Z',
    'karim',
    note: 'Cups for the New Cairo pop-up stand',
  ),
  InvTransferSpec(
    't4',
    'new-cairo',
    'zamalek',
    'vanilla-syrup',
    750,
    '2026-09-24T08:00:00Z',
    'nour',
  ),
  InvTransferSpec(
    't5',
    'maadi',
    'new-cairo',
    'croissant',
    12,
    '2026-09-19T07:40:00Z',
    'tarek',
  ),
];

class InvPoLineSpec {
  const InvPoLineSpec(
    this.ingredient,
    this.purchaseUnit,
    this.qty,
    this.unitCost, {
    this.received = 0,
  });

  final String ingredient;
  final String purchaseUnit;

  /// In purchase units.
  final double qty;

  /// Piastres per purchase unit.
  final int unitCost;
  final double received;
}

class InvPoSpec {
  const InvPoSpec(
    this.key,
    this.branch,
    this.supplier,
    this.status,
    this.createdAt,
    this.by,
    this.lines, {
    this.reference,
    this.expectedAt,
    this.receivedAt,
    this.receivedBy,
    this.note,
  });

  final String key;
  final String branch;
  final String? supplier;
  final String status;
  final String createdAt;
  final String by;
  final List<InvPoLineSpec> lines;
  final String? reference;
  final String? expectedAt;
  final String? receivedAt;
  final String? receivedBy;
  final String? note;
}

/// End of 2026-10-08 in Cairo (the "expected" instant the web sends).
const String _endOfToday = '2026-10-08T20:59:59.999Z';

const List<InvPoSpec> invPurchaseOrders = [
  InvPoSpec(
    'po-1044',
    'zamalek',
    'delta-dairy',
    'ordered',
    '2026-10-06T10:20:00Z',
    'karim',
    [
      InvPoLineSpec('full-cream', 'l', 48, 4500),
      InvPoLineSpec('skimmed', 'l', 12, 4200),
    ],
    expectedAt: _endOfToday,
  ),
  InvPoSpec(
    'po-1043',
    'new-cairo',
    'nile-roasters',
    'ordered',
    '2026-10-07T12:00:00Z',
    'dina',
    [
      InvPoLineSpec('house-blend', 'kg', 10, 90000),
      InvPoLineSpec('decaf', 'kg', 2, 110000),
    ],
    reference: 'PO-1043',
    expectedAt: '2026-10-10T20:59:59.999Z',
  ),
  InvPoSpec(
    'po-1042',
    'zamalek',
    'nile-roasters',
    'ordered',
    '2026-10-05T09:00:00Z',
    'karim',
    [
      InvPoLineSpec('house-blend', 'kg', 5, 90000),
      InvPoLineSpec('ethiopia', 'kg', 1, 140000),
    ],
    reference: 'PO-1042',
    expectedAt: _endOfToday,
    note: 'Weekly beans',
  ),
  InvPoSpec(
    'po-1041',
    'maadi',
    'delta-dairy',
    'partially_received',
    '2026-10-04T11:30:00Z',
    'tarek',
    [
      InvPoLineSpec('full-cream', 'l', 60, 4500, received: 36),
      InvPoLineSpec('heavy-cream', 'l', 2, 16000, received: 2),
    ],
    reference: 'PO-1041',
    expectedAt: '2026-10-07T20:59:59.999Z',
  ),
  InvPoSpec(
    'po-1040',
    'new-cairo',
    'metro',
    'draft',
    '2026-10-07T15:10:00Z',
    'dina',
    [
      InvPoLineSpec('vanilla-syrup', 'l', 6, 30000),
      InvPoLineSpec('caramel-syrup', 'l', 3, 30000),
    ],
    reference: 'PO-1040',
    note: 'Syrups for the weekend',
  ),
  InvPoSpec(
    'po-1039',
    'zamalek',
    'packright',
    'received',
    '2026-09-29T10:00:00Z',
    'karim',
    [
      InvPoLineSpec('paper-cup-12', 'pcs', 500, 180, received: 500),
      InvPoLineSpec('cup-lid', 'pcs', 1000, 60, received: 1000),
    ],
    reference: 'PO-1039',
    expectedAt: '2026-10-02T20:59:59.999Z',
    receivedAt: '2026-10-02T09:10:00Z',
    receivedBy: 'karim',
  ),
  InvPoSpec(
    'po-1038',
    'heliopolis',
    'golden-bakery',
    'cancelled',
    '2026-09-26T13:00:00Z',
    'rana',
    [InvPoLineSpec('croissant', 'pcs', 96, 900)],
    reference: 'PO-1038',
    note: 'Supplier closed for the holiday',
  ),
  InvPoSpec(
    'po-1037',
    'new-cairo',
    'nile-roasters',
    'received',
    '2026-09-26T09:30:00Z',
    'dina',
    [InvPoLineSpec('house-blend', 'kg', 8, 90000, received: 8)],
    reference: 'PO-1037',
    expectedAt: '2026-09-29T20:59:59.999Z',
    receivedAt: '2026-09-29T08:15:00Z',
    receivedBy: 'dina',
  ),
  InvPoSpec(
    'po-1036',
    'maadi',
    'golden-bakery',
    'received',
    '2026-10-02T14:00:00Z',
    'tarek',
    [InvPoLineSpec('croissant', 'pcs', 48, 900, received: 48)],
    reference: 'PO-1036',
    expectedAt: '2026-10-05T20:59:59.999Z',
    receivedAt: '2026-10-05T06:30:00Z',
    receivedBy: 'tarek',
  ),
];

class InvReceiptLineSpec {
  const InvReceiptLineSpec(this.line, this.qty, this.cost);

  /// Index of the PO line.
  final int line;

  /// Base units (+ received, − returned).
  final double qty;

  /// Piastres (negative for a return).
  final int cost;
}

class InvReceiptSpec {
  const InvReceiptSpec(
    this.key,
    this.po,
    this.at,
    this.by,
    this.lines, {
    this.isReturn = false,
    this.note,
  });

  final String key;
  final String po;
  final String at;
  final String by;
  final List<InvReceiptLineSpec> lines;
  final bool isReturn;
  final String? note;
}

const List<InvReceiptSpec> invReceipts = [
  InvReceiptSpec('r-1041-a', 'po-1041', '2026-10-07T08:40:00Z', 'tarek', [
    InvReceiptLineSpec(0, 36000, 162000),
    InvReceiptLineSpec(1, 2000, 32000),
  ]),
  InvReceiptSpec('r-1039-a', 'po-1039', '2026-10-02T09:10:00Z', 'karim', [
    InvReceiptLineSpec(0, 500, 90000),
    InvReceiptLineSpec(1, 1000, 60000),
  ]),
  InvReceiptSpec(
    'r-1039-b',
    'po-1039',
    '2026-10-03T07:30:00Z',
    'karim',
    [InvReceiptLineSpec(1, -50, -3000)],
    isReturn: true,
    note: 'Crushed sleeve returned to the driver',
  ),
  InvReceiptSpec('r-1037-a', 'po-1037', '2026-09-29T08:15:00Z', 'dina', [
    InvReceiptLineSpec(0, 8000, 720000),
  ]),
  InvReceiptSpec('r-1036-a', 'po-1036', '2026-10-05T06:30:00Z', 'tarek', [
    InvReceiptLineSpec(0, 48, 43200),
  ]),
];

/// A stock count. [deltas]: (counted − book) / book per ingredient for the
/// counted rows (0 when absent); [counted]: which rows hold a figure (null =
/// every row in scope that the branch stocks).
class InvCountSpec {
  const InvCountSpec(
    this.key,
    this.branch,
    this.status,
    this.startedAt,
    this.by, {
    this.finalizedAt,
    this.category,
    this.items,
    this.deltas = const {},
    this.reasons = const {},
    this.counted,
    this.note,
  });

  final String key;
  final String branch;

  /// `finalized` | `cancelled` | `in_progress`.
  final String status;
  final String startedAt;
  final String by;
  final String? finalizedAt;

  /// Category scope (slug).
  final String? category;

  /// Items scope (ingredient keys).
  final List<String>? items;
  final Map<String, double> deltas;
  final Map<String, String> reasons;
  final Set<String>? counted;
  final String? note;

  bool get finalized => status == 'finalized';
}

const List<InvCountSpec> invCounts = [
  InvCountSpec(
    'zamalek-0920',
    'zamalek',
    'finalized',
    '2026-09-20T18:40:00Z',
    'karim',
    finalizedAt: '2026-09-20T19:30:00Z',
    note: 'End-of-month full count',
    deltas: {
      'oat': -0.08,
      'matcha': -0.12,
      'croissant': -0.07,
      'sugar': 0.02,
      'house-blend': -0.03,
      'full-cream': 0.01,
    },
    reasons: {'oat': 'spoilage', 'matcha': 'theft', 'croissant': 'miscount'},
  ),
  InvCountSpec(
    'zamalek-0927',
    'zamalek',
    'cancelled',
    '2026-09-27T19:00:00Z',
    'karim',
    category: 'bakery',
    counted: {'croissant'},
    deltas: {'croissant': -0.05},
    note: 'Started by mistake',
  ),
  InvCountSpec(
    'zamalek-1004',
    'zamalek',
    'finalized',
    '2026-10-04T19:50:00Z',
    'karim',
    finalizedAt: '2026-10-04T20:10:00Z',
    category: 'milk',
    deltas: {'full-cream': -0.06, 'oat': 0.04},
    reasons: {'full-cream': 'spoilage'},
  ),
  InvCountSpec(
    'maadi-0902',
    'maadi',
    'finalized',
    '2026-09-02T19:30:00Z',
    'tarek',
    finalizedAt: '2026-09-02T19:45:00Z',
    items: ['full-cream', 'heavy-cream'],
    deltas: {'full-cream': -0.02},
    note: 'Dairy spot check',
  ),
  InvCountSpec(
    'maadi-0930',
    'maadi',
    'finalized',
    '2026-09-30T20:00:00Z',
    'tarek',
    finalizedAt: '2026-09-30T20:45:00Z',
    deltas: {'heavy-cream': -0.09, 'cocoa': 0.06, 'turkish': -0.01},
    reasons: {'heavy-cream': 'spoilage', 'cocoa': 'miscount'},
  ),
  InvCountSpec(
    'new-cairo-0912',
    'new-cairo',
    'finalized',
    '2026-09-12T20:15:00Z',
    'dina',
    finalizedAt: '2026-09-12T21:00:00Z',
    deltas: {'sugar': -0.10, 'vanilla-syrup': -0.06, 'house-blend': 0.02},
    reasons: {'sugar': 'breakage', 'vanilla-syrup': 'spoilage'},
  ),
  // Open now: started this morning, 9 rows counted, Croissant Dough flagged
  // with no reason yet.
  InvCountSpec(
    'new-cairo-1008',
    'new-cairo',
    'in_progress',
    '2026-10-08T05:15:00Z',
    'dina',
    counted: {
      'house-blend',
      'croissant',
      'full-cream',
      'skimmed',
      'oat',
      'sugar',
      'paper-cup-12',
      'cup-lid',
      'vanilla-syrup',
    },
    deltas: {
      'house-blend': -0.125,
      'croissant': -0.23,
      'oat': 0.02,
      'cup-lid': 0.01,
    },
    reasons: {'house-blend': 'miscount'},
  ),
];

// ── Loading ────────────────────────────────────────────────────────────────

/// Loads the area's rows into a [MockDb] holding the core seed.
abstract final class InventorySeed {
  static Map<String, List<Map<String, Object?>>>? _built;

  /// The rows, built once per process (each [loadInto] copies them).
  static Map<String, List<Map<String, Object?>>> get tables =>
      _built ??= _InvBuilder().build();

  /// Copies the area's rows into [db]; a second call does nothing.
  static void loadInto(MockDb db) {
    if (db.hasTable(InvTables.ingredients) &&
        !db[InvTables.ingredients].isEmpty) {
      return;
    }
    for (final e in tables.entries) {
      db.table(e.key).insertAll([
        for (final r in e.value) _copy(r),
      ], timestamps: false);
    }
  }

  static Map<String, Object?> _copy(Map<String, Object?> r) => {
    for (final e in r.entries)
      e.key: switch (e.value) {
        final List<Object?> l => [
          for (final x in l) x is Map<String, Object?> ? _copy(x) : x,
        ],
        final Map<String, Object?> m => _copy(m),
        final v => v,
      },
  };

  /// The ingredient spec of [key].
  static InvIngredientSpec ingredient(String key) =>
      invIngredients.firstWhere((i) => i.key == key);

  /// A seed person's display name by key.
  static String personName(String key) => _people[key] ?? key;
}

final Map<String, String> _people = {for (final p in sabahStaff) p.key: p.name};

String _branchName(String key) =>
    seedBranches.firstWhere((b) => b.key == key).name;

String _branchId(String key) => switch (key) {
  'heliopolis' => SeedIds.heliopolis,
  'maadi' => SeedIds.maadi,
  'new-cairo' => SeedIds.newCairo,
  _ => SeedIds.zamalek,
};

/// One ledger event of a (branch, ingredient) pair, walked backward.
class _Event {
  _Event(this.at, this.kind, {this.qty = 0, this.row, this.count});

  final DateTime at;

  /// sale | waste | purchase_in | transfer_in | transfer_out | count |
  /// snapshot
  final String kind;
  final double qty;
  final Map<String, Object?>? row;
  final InvCountSpec? count;
}

class _InvBuilder {
  final DateTime now = MockSeed.now;
  final String org = SeedIds.sabahOrg;
  final DateTime catalogStart = DateTime.utc(2026, 1, 12, 9);

  final Map<String, List<Map<String, Object?>>> out = {
    for (final t in [
      InvTables.categories,
      InvTables.suppliers,
      InvTables.ingredients,
      InvTables.branchStock,
      InvTables.movements,
      InvTables.transfers,
      InvTables.stocktakes,
      InvTables.stocktakeItems,
      InvTables.purchaseOrders,
      InvTables.poLines,
      InvTables.receipts,
      InvTables.settings,
    ])
      t: <Map<String, Object?>>[],
  };

  /// (branch, ingredient) → its events.
  final Map<String, List<_Event>> _events = {};

  /// count key + ingredient → (opening, book, counted).
  final Map<String, (double, double, double?)> _countFigures = {};

  String iso(DateTime d) => d.toUtc().toIso8601String();

  double step(String unit) => unit == 'pcs' ? 1 : 10;

  double roundTo(double v, String unit) {
    final s = step(unit);
    return (v / s).roundToDouble() * s;
  }

  bool stocks(String branch, InvIngredientSpec i) =>
      invBranchScale.containsKey(branch) &&
      i.active &&
      !(invNotStocked[branch] ?? const {}).contains(i.key);

  List<_Event> events(String branch, String ing) =>
      _events.putIfAbsent('$branch|$ing', () => []);

  Map<String, List<Map<String, Object?>>> build() {
    _settings();
    _categories();
    _suppliers();
    _catalog();
    _sales();
    _waste();
    _transfers();
    _purchasing();
    for (final c in invCounts) {
      for (final i in _scope(c)) {
        events(c.branch, i.key).add(
          _Event(
            DateTime.parse(c.finalizedAt ?? c.startedAt),
            c.finalized ? 'count' : 'snapshot',
            count: c,
          ),
        );
      }
    }
    _walk();
    _stocktakes();
    out[InvTables.movements]!.sort(
      (a, b) =>
          (a['created_at']! as String).compareTo(b['created_at']! as String),
    );
    return out;
  }

  void _settings() => out[InvTables.settings]!.add({
    'id': org,
    'org_id': org,
    'stocktake_variance_threshold_pct': invVarianceThresholdPct,
  });

  void _categories() {
    for (final c in invCategories) {
      out[InvTables.categories]!.add({
        'id': InvIds.category(c.slug),
        'org_id': org,
        'slug': c.slug,
        'name': c.name,
        'sort_order': c.sortOrder,
        'is_packaging': c.packaging,
        'ingredient_count': invIngredients
            .where((i) => i.category == c.slug)
            .length,
        'created_at': iso(catalogStart),
        'updated_at': iso(catalogStart),
      });
    }
  }

  void _suppliers() {
    for (final s in invSuppliers) {
      out[InvTables.suppliers]!.add({
        'id': InvIds.supplier(s.key),
        'org_id': org,
        'name': s.name,
        'contact_name': s.contact,
        'email': s.email,
        'phone': s.phone,
        'is_active': s.active,
        'created_at': iso(catalogStart),
        'updated_at': iso(
          s.active ? catalogStart : DateTime.utc(2026, 8, 30, 10),
        ),
      });
    }
  }

  void _catalog() {
    for (final i in invIngredients) {
      final cat = invCategories.firstWhere((c) => c.slug == i.category);
      final sup = i.supplier == null
          ? null
          : invSuppliers.firstWhere((s) => s.key == i.supplier);
      final created = i.addedOn == null
          ? catalogStart
          : DateTime.parse('${i.addedOn}T09:00:00Z');
      out[InvTables.ingredients]!.add({
        'id': InvIds.ingredient(i.key),
        'org_id': org,
        'name': i.name,
        'unit': i.unit,
        'category_id': InvIds.category(cat.slug),
        'category_slug': cat.slug,
        'category_name': cat.name,
        'cost_per_unit': i.cost,
        'density_g_per_ml': i.density,
        'description': i.description,
        'is_active': i.active,
        'pack_size': i.packSize,
        'pack_unit': i.packUnit,
        'supplier_id': sup == null ? null : InvIds.supplier(sup.key),
        'supplier_name': sup?.name,
        'yield_pct': i.yieldPct,
        'created_at': iso(created),
        'updated_at': iso(i.active ? created : DateTime.utc(2026, 8, 1, 9)),
      });
    }
  }

  DateTime _added(InvIngredientSpec i) => i.addedOn == null
      ? catalogStart
      : DateTime.parse('${i.addedOn}T09:00:00Z');

  /// Daily sales: one aggregated movement per evening for 29 days, and this
  /// morning's so far.
  void _sales() {
    final today = DateTime.utc(now.year, now.month, now.day);
    for (final b in invBranchScale.keys) {
      final scale = invBranchScale[b]!;
      for (final i in invIngredients) {
        if (!stocks(b, i) || i.dailyUse <= 0) continue;
        final rng = MockRandom('inventory-sales:$b:${i.key}');
        for (var d = 29; d >= 1; d--) {
          final at = today
              .subtract(Duration(days: d))
              .add(const Duration(hours: 18));
          if (at.isBefore(_added(i))) continue;
          final q = roundTo(
            i.dailyUse * scale * (0.75 + 0.5 * rng.nextDouble()),
            i.unit,
          );
          if (q > 0) events(b, i.key).add(_Event(at, 'sale', qty: -q));
        }
        final morning = roundTo(i.dailyUse * scale * 0.22, i.unit);
        if (morning > 0) {
          events(b, i.key).add(
            _Event(
              today.add(const Duration(hours: 6, minutes: 45)),
              'sale',
              qty: -morning,
            ),
          );
        }
      }
    }
  }

  Map<String, Object?> _movement({
    required String branch,
    required InvIngredientSpec ing,
    required String type,
    required double qty,
    required String at,
    String? id,
    String? by,
    String? note,
    String? reason,
    String? sourceType,
    String? sourceId,
  }) {
    final cost = branchCost(branch, ing);
    return {
      'id': id ?? mockUuid('movement:$branch:${ing.key}:$type:$at'),
      'branch_id': _branchId(branch),
      'branch_name': _branchName(branch),
      'branch_stock_id': InvIds.branchStock(branch, ing.key),
      'org_ingredient_id': InvIds.ingredient(ing.key),
      'ingredient_name': ing.name,
      'unit': ing.unit,
      'movement_type': type,
      'quantity': qty,
      'balance_after': 0.0,
      'below_zero': false,
      'unit_cost': cost == null ? null : (cost + 0.5).floor(),
      'reason': reason,
      'note': note,
      'source_type': sourceType,
      'source_id': sourceId,
      'created_at': iso(DateTime.parse(at)),
      'created_by': by == null ? null : SeedIds.user(by),
      'created_by_name': by == null ? null : InventorySeed.personName(by),
    };
  }

  double? branchCost(String branch, InvIngredientSpec i) =>
      invBranchCost[branch]?[i.key] ?? i.cost;

  void _waste() {
    for (final w in invWaste) {
      final ing = InventorySeed.ingredient(w.ingredient);
      final cost = branchCost(w.branch, ing);
      final row = _movement(
        branch: w.branch,
        ing: ing,
        type: 'waste',
        qty: -w.qty,
        at: w.at,
        id: mockUuid('waste:${w.branch}:${w.ingredient}:${w.at}'),
        by: w.by,
        note: w.note,
        reason: w.reason,
        sourceType: switch (w.source) {
          'refund' => 'refund',
          'order' => 'order',
          _ => w.source,
        },
      );
      row.addAll({
        'occurred_at': w.occurredAt == null
            ? null
            : iso(DateTime.parse(w.occurredAt!)),
        'received_at': w.occurredAt == null ? null : iso(DateTime.parse(w.at)),
        'waste_source': w.source,
        'waste_value_minor': cost == null ? null : (w.qty * cost + 0.5).floor(),
        'approved_by_name': w.approvedBy == null
            ? null
            : InventorySeed.personName(w.approvedBy!),
        'device_id': w.source == 'pos' ? InvIds.device(w.branch) : null,
        'device_name': w.source == 'pos' ? 'Counter 1' : null,
        'order_display_number': w.order,
        'waste_subject_kind': w.subject == null ? 'ingredient' : 'item',
        'waste_subject_name': w.subject ?? ing.name,
        'waste_size_label': w.subjectSize,
        'waste_quantity': w.subjectQty ?? w.qty,
        'waste_unit': w.subject == null ? ing.unit : 'pcs',
      });
      events(
        w.branch,
        w.ingredient,
      ).add(_Event(DateTime.parse(w.at), 'waste', qty: -w.qty, row: row));
    }
  }

  void _transfers() {
    for (final t in invTransfers) {
      final ing = InventorySeed.ingredient(t.ingredient);
      final id = InvIds.transfer(t.key);
      out[InvTables.transfers]!.add({
        'id': id,
        'org_id': org,
        'org_ingredient_id': InvIds.ingredient(ing.key),
        'ingredient_name': ing.name,
        'unit': ing.unit,
        'quantity': t.qty,
        'source_branch_id': _branchId(t.from),
        'source_branch_name': _branchName(t.from),
        'destination_branch_id': _branchId(t.to),
        'destination_branch_name': _branchName(t.to),
        'initiated_at': t.at,
        'initiated_by': SeedIds.user(t.by),
        'initiated_by_name': InventorySeed.personName(t.by),
        'note': t.note,
      });
      for (final (branch, type, qty) in [
        (t.from, 'transfer_out', -t.qty),
        (t.to, 'transfer_in', t.qty),
      ]) {
        final row = _movement(
          branch: branch,
          ing: ing,
          type: type,
          qty: qty,
          at: t.at,
          by: t.by,
          note: t.note,
          sourceType: 'transfer',
          sourceId: id,
        );
        events(
          branch,
          ing.key,
        ).add(_Event(DateTime.parse(t.at), type, qty: qty, row: row));
      }
    }
  }

  void _purchasing() {
    for (final p in invPurchaseOrders) {
      final id = InvIds.purchaseOrder(p.key);
      final sup = p.supplier == null
          ? null
          : invSuppliers.firstWhere((s) => s.key == p.supplier);
      out[InvTables.purchaseOrders]!.add({
        'id': id,
        'org_id': org,
        'branch_id': _branchId(p.branch),
        'branch_name': _branchName(p.branch),
        'supplier_id': sup == null ? null : InvIds.supplier(sup.key),
        'supplier_name': sup?.name,
        'status': p.status,
        'reference': p.reference,
        'note': p.note,
        'expected_at': p.expectedAt,
        'received_at': p.receivedAt,
        'received_by': p.receivedBy == null
            ? null
            : SeedIds.user(p.receivedBy!),
        'created_by': SeedIds.user(p.by),
        'created_at': p.createdAt,
        'updated_at': p.receivedAt ?? p.createdAt,
      });
      for (var n = 0; n < p.lines.length; n++) {
        final l = p.lines[n];
        final ing = InventorySeed.ingredient(l.ingredient);
        out[InvTables.poLines]!.add({
          'id': InvIds.poLine(p.key, n),
          'purchase_order_id': id,
          'org_ingredient_id': InvIds.ingredient(ing.key),
          'ingredient_name': ing.name,
          'unit': ing.unit,
          'purchase_unit': l.purchaseUnit,
          'units_per_purchase_unit': _unitsPer(l.purchaseUnit, ing.unit),
          'quantity_ordered': l.qty,
          'quantity_received': l.received,
          'unit_cost': l.unitCost,
          'unit_cost_exact': l.unitCost.toDouble(),
          'line_cost': (l.qty * l.unitCost).round(),
        });
      }
    }
    for (final r in invReceipts) {
      final p = invPurchaseOrders.firstWhere((o) => o.key == r.po);
      final sup = invSuppliers.firstWhere((s) => s.key == p.supplier);
      final id = InvIds.receipt(r.key);
      final lines = <Map<String, Object?>>[];
      for (final l in r.lines) {
        final pl = p.lines[l.line];
        final ing = InventorySeed.ingredient(pl.ingredient);
        final exact = l.cost / l.qty;
        lines.add({
          'id': mockUuid('goods-receipt:${r.key}:line:${l.line}'),
          'purchase_order_line_id': InvIds.poLine(p.key, l.line),
          'org_ingredient_id': InvIds.ingredient(ing.key),
          'ingredient_name': ing.name,
          'quantity': l.qty,
          'line_cost': l.cost,
          'unit_cost': (exact + 0.5).floor(),
          'unit_cost_exact': exact,
        });
        final row = _movement(
          branch: p.branch,
          ing: ing,
          type: 'purchase_in',
          qty: l.qty,
          at: r.at,
          by: r.by,
          note: r.note,
          sourceType: 'goods_receipt',
          sourceId: id,
        );
        events(p.branch, ing.key).add(
          _Event(DateTime.parse(r.at), 'purchase_in', qty: l.qty, row: row),
        );
      }
      out[InvTables.receipts]!.add({
        'id': id,
        'branch_id': _branchId(p.branch),
        'purchase_order_id': InvIds.purchaseOrder(p.key),
        'supplier_id': InvIds.supplier(sup.key),
        'supplier_name': sup.name,
        'reference': p.reference,
        'note': r.note,
        'is_return': r.isReturn,
        'received_at': r.at,
        'received_by': SeedIds.user(r.by),
        'received_by_name': InventorySeed.personName(r.by),
        'lines': lines,
      });
    }
  }

  double _unitsPer(String purchaseUnit, String stockUnit) {
    const scale = {'g': 1, 'kg': 1000, 'ml': 1, 'l': 1000, 'pcs': 1};
    final p = scale[purchaseUnit];
    final s = scale[stockUnit];
    if (p == null || s == null) return 1;
    return p / s;
  }

  /// The ingredients a count covers (live, active, in the catalog by then).
  List<InvIngredientSpec> _scope(InvCountSpec c) => [
    for (final i in invIngredients)
      if (i.active &&
          !_added(i).isAfter(DateTime.parse(c.startedAt)) &&
          (c.items == null || c.items!.contains(i.key)) &&
          (c.category == null || i.category == c.category))
        i,
  ];

  double _onHand(String branch, InvIngredientSpec i) {
    final o = invOnHandOverride[branch]?[i.key];
    if (o != null) return o;
    final scale = invBranchScale[branch]!;
    final rng = MockRandom('inventory-on-hand:$branch:${i.key}');
    final lo = (i.parMin ?? i.dailyUse * 1.2) * scale * 1.3;
    final hi = (i.parMax ?? i.dailyUse * 4) * scale * 0.9;
    return roundTo(lo + (hi - lo) * rng.nextDouble(), i.unit);
  }

  /// Walks each stocked pair backward from its on-hand: every movement gets
  /// its balance, counts get their book figure, and a delivery lands on the
  /// evening a balance would otherwise climb past the order-up-to level.
  void _walk() {
    for (final b in invBranchScale.keys) {
      final scale = invBranchScale[b]!;
      for (final i in invIngredients) {
        if (!stocks(b, i)) continue;
        final evs = events(b, i.key)..sort((x, y) => y.at.compareTo(x.at));
        final onHand = _onHand(b, i);
        final cap = (i.parMax ?? i.dailyUse * 5) * scale * 1.05;
        final floor = (i.parMin ?? i.dailyUse * 2) * scale;
        final rng = MockRandom('inventory-deliveries:$b:${i.key}');
        // Designed deliveries and transfers in: a synthetic delivery leaves
        // room for any that land in the week before it.
        final inflows = [
          for (final e in evs)
            if (e.row != null && e.qty > 0) e,
        ];
        double pendingBefore(DateTime t) {
          var sum = 0.0;
          for (final e in inflows) {
            if (e.at.isBefore(t) &&
                !e.at.isBefore(t.subtract(const Duration(days: 7)))) {
              sum += e.qty;
            }
          }
          return sum;
        }

        var bal = onHand;
        DateTime? lastMove;
        DateTime? lastCount;
        final rows = <Map<String, Object?>>[];
        for (final e in evs) {
          switch (e.kind) {
            case 'snapshot':
              final c = e.count!;
              final isOpen = c.status == 'in_progress';
              final counted = c.counted == null || c.counted!.contains(i.key)
                  ? roundTo(
                      (isOpen ? onHand : bal) * (1 + (c.deltas[i.key] ?? 0)),
                      i.unit,
                    )
                  : null;
              _countFigures['${c.key}|${i.key}'] = (
                bal,
                isOpen ? onHand : bal,
                counted,
              );
            case 'count':
              final c = e.count!;
              final d = c.deltas[i.key] ?? 0;
              final v = roundTo(bal * d / (1 + d), i.unit);
              _countFigures['${c.key}|${i.key}'] = (bal - v, bal - v, bal);
              lastCount ??= e.at;
              if (v != 0) {
                rows.add(
                  _movement(
                      branch: b,
                      ing: i,
                      type: 'stock_count',
                      qty: v,
                      at: iso(e.at),
                      by: c.by,
                      reason: c.reasons[i.key],
                      sourceType: 'stocktake',
                      sourceId: InvIds.stocktake(c.key),
                    )
                    ..['balance_after'] = bal
                    ..['below_zero'] = bal < 0,
                );
                lastMove ??= e.at;
              }
              bal -= v;
            default:
              final row =
                  e.row ??
                  _movement(
                    branch: b,
                    ing: i,
                    type: e.kind,
                    qty: e.qty,
                    at: iso(e.at),
                    sourceType: 'order',
                  );
              row['balance_after'] = bal;
              row['below_zero'] = bal < 0;
              rows.add(row);
              lastMove ??= e.at;
              bal -= e.qty;
              if (e.kind == 'sale' && bal > cap) {
                // A delivery that same evening, before the sale.
                final target = floor * (1.1 + 0.3 * rng.nextDouble());
                final dq = roundTo(bal - target - pendingBefore(e.at), i.unit);
                if (dq > 0) {
                  final at = e.at.subtract(const Duration(minutes: 30));
                  rows.add(
                    _movement(
                        branch: b,
                        ing: i,
                        type: 'purchase_in',
                        qty: dq,
                        at: iso(at),
                        note: 'Supplier delivery',
                        sourceType: 'goods_receipt',
                      )
                      ..['balance_after'] = bal
                      ..['below_zero'] = bal < 0,
                  );
                  bal -= dq;
                }
              }
          }
        }
        out[InvTables.movements]!.addAll(rows);
        out[InvTables.branchStock]!.add({
          'id': InvIds.branchStock(b, i.key),
          'branch_id': _branchId(b),
          'org_ingredient_id': InvIds.ingredient(i.key),
          'on_hand': onHand,
          'par_min': i.parMin == null
              ? null
              : roundTo(i.parMin! * scale, i.unit),
          'par_max': i.parMax == null
              ? null
              : roundTo(i.parMax! * scale, i.unit),
          'cost_per_unit': branchCost(b, i),
          'last_counted_at': lastCount == null ? null : iso(lastCount),
          'last_movement_at': lastMove == null ? null : iso(lastMove),
        });
      }
    }
  }

  void _stocktakes() {
    for (final c in invCounts) {
      final id = InvIds.stocktake(c.key);
      out[InvTables.stocktakes]!.add({
        'id': id,
        'org_id': org,
        'branch_id': _branchId(c.branch),
        'branch_name': _branchName(c.branch),
        'status': c.status,
        'note': c.note,
        'scope': c.category != null
            ? {'kind': 'category', 'category_id': InvIds.category(c.category!)}
            : c.items != null
            ? {
                'kind': 'items',
                'org_ingredient_ids': [
                  for (final k in c.items!) InvIds.ingredient(k),
                ],
              }
            : {'kind': 'full'},
        'started_at': c.startedAt,
        'started_by': SeedIds.user(c.by),
        'started_by_name': InventorySeed.personName(c.by),
        'finalized_at': c.finalizedAt,
        'finalized_by': c.finalized ? SeedIds.user(c.by) : null,
        'created_at': c.startedAt,
      });
      for (final i in _scope(c)) {
        final cat = invCategories.firstWhere((x) => x.slug == i.category);
        final figures = _countFigures['${c.key}|${i.key}'];
        final stocked = stocks(c.branch, i);
        final opening = figures?.$1 ?? 0;
        final book = figures?.$2 ?? 0;
        final counted = stocked ? figures?.$3 : null;
        final cost = branchCost(c.branch, i);
        out[InvTables.stocktakeItems]!.add({
          'id': mockUuid('stocktake-item:${c.key}:${i.key}'),
          'stocktake_id': id,
          'org_ingredient_id': InvIds.ingredient(i.key),
          'ingredient_name': i.name,
          'unit': i.unit,
          'category_id': InvIds.category(cat.slug),
          'category_name': cat.name,
          'opening_qty': opening,
          'book_qty': book,
          'counted_qty': counted,
          'variance': counted == null ? null : counted - book,
          'variance_reason': counted == null ? null : c.reasons[i.key],
          'unit_cost': cost == null ? null : (cost + 0.5).floor(),
          'is_new': !stocked,
          'counted_by': counted == null ? null : SeedIds.user(c.by),
          'note': null,
          'created_at': c.startedAt,
        });
      }
    }
  }
}
