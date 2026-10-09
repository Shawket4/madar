/// The orders unit's mock backend: `/orders` and the order sheet.
///
/// | Route | Backend | Gate |
/// |---|---|---|
/// | GET /orders | `orders::list_orders` | `orders.read`; a till or a branch the persona works; nil/absent = the org |
/// | GET /orders/{order_id} | `orders::get_order` | `orders.read` + branch; 404 `Order not found` |
/// | POST /orders/{order_id}/void | `orders::void_order` | `orders.void` + branch; a teller only their own sale within 10 min and never on a closed shift; 400 note for "other"; 409 once refunded; a voided order answers as it is |
/// | GET /orders/export | `orders::export_orders` | `orders.read`; the export throttle (`EXPORT_RATE_LIMITED`) |
/// | GET /reports/branches/{branch_id}/delivery-sales | `reports::branch_delivery_sales` | `orders.read` |
/// | GET /delivery-orders/{id} | `delivery::staff::get_delivery_order` | `delivery.orders.read` + branch |
/// | GET /inventory/orgs/{org_id}/catalog | `inventory::list_catalog` | `inventory.read` + same org (only when no other area answers it) |
/// | GET /menu-items | `menu::list_menu_items` | `menu.items.read` + same org (only when no other area answers it) |
///
/// Capability refusals are the 403 envelope WITHOUT a code (SELL-ALL-017).
///
/// Data: the core seed's 30 days of orders, plus this unit's own rows
/// ([loadOrdersSeed]): the branch's own deliveries (Heliopolis in-mall and
/// outside, Zamalek outside, a cancellation every sixth day) materialised as
/// sales, and a morning of Heliopolis/Zamalek sales that show every part of
/// the order sheet (a combo with a deal, a loyalty reward, a refused reward,
/// a staff drink, an offline price, a void with a note, a split payment with
/// a waiter, an in-mall delivery and an outside one still on the road). The
/// added sales ring on each branch's second counter (device T2, "Counter 2",
/// the second teller's till), numbered in that till's own sequence; past
/// days' Counter 2 tills are closed with the float plus their cash. Every
/// line carries its ingredient deductions (the recipe the catalogue
/// describes, `ingredient:<key>` ids shared with the menu and inventory
/// areas), so COGS and the ingredient sheets have figures.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';
import 'customers_mock.dart' show CustomerTables, mockExportsPerMinute;

/// The backend's "every branch of my org" id (`ALL_BRANCHES_ID`).
const String _allBranches = '00000000-0000-0000-0000-000000000000';

/// The tables this unit reads and writes.
abstract final class OrderTables {
  /// [Order] rows (the core seed's, plus [loadOrdersSeed]'s).
  static const String orders = 'orders';

  /// One row per order this unit wrote lines for (`id` is the order's):
  /// `items`, `deals`, `delivery`, `loyalty_redemption_refused`. Other
  /// orders take the core seed's lines.
  static const String details = 'order_details';

  /// [DeliveryOrder] rows (shared with the overview's delivery card).
  static const String deliveryOrders = 'delivery_orders';

  /// Refunds against orders (`order_refunds`): `{id, order_id, amount}`.
  static const String refunds = 'order_refunds';
}

/// Minor units refunded against [orderId] (this unit's table, and the legal
/// report's when the reports area seeded one).
int refundedOn(MockDb db, String orderId) {
  var total = 0;
  for (final t in [OrderTables.refunds, 'legal_refunds']) {
    if (!db.hasTable(t)) continue;
    for (final r in db[t].rows) {
      if (r['order_id'] == orderId)
        total += (r['amount'] as num?)?.toInt() ?? 0;
    }
  }
  return total;
}

/// The stable ids of this unit's rows.
abstract final class OrderSeedIds {
  /// A morning sale that shows one part of the sheet (`combo`, `reward`,
  /// `refused`, `staff`, `offline`, `voided`, `split`, `inMall`, `outside`).
  static String showcase(String key) => mockUuid('order:showcase:$key');

  static String delivery(String branchKey, String date, int n) =>
      mockUuid('delivery-order:$branchKey:$date:$n');

  static String deliverySale(String branchKey, String date, int n) =>
      mockUuid('order:delivery:$branchKey:$date:$n');

  static String ingredient(String key) => mockUuid('ingredient:$key');

  static String line(String orderId, int i) =>
      mockUuid('order-item:$orderId:$i');
}

void registerOrdersMocks(MockServer server, MockDb db) {
  loadOrdersSeed(db);
  final h = _Handlers(db);
  server
    ..on('GET', '/orders', h.list)
    ..on('GET', '/orders/export', h.export)
    ..on('GET', '/orders/{order_id}', h.get)
    ..on('POST', '/orders/{order_id}/void', h.voidOrder)
    ..on('GET', '/reports/branches/{branch_id}/delivery-sales', h.deliverySales)
    ..on('GET', '/delivery-orders/{id}', h.deliveryOrder);
  void onIfAbsent(String method, String template, MockHandler handler) {
    if (!server.handles(method, template)) server.on(method, template, handler);
  }

  onIfAbsent('GET', '/inventory/orgs/{org_id}/catalog', h.catalog);
  onIfAbsent('GET', '/menu-items', h.menuItems);
}

// ── Ingredients and recipes ──────────────────────────────────────────────

/// (key, name, category, unit, piastres per unit or null) — the same
/// catalogue the menu area seeds.
const List<(String, String, String, String, double?)> _ingredients = [
  ('house_blend', 'House espresso blend', 'Coffee beans', 'g', 95),
  ('turkish_coffee', 'Turkish coffee with cardamom', 'Coffee beans', 'g', 90),
  ('full_milk', 'Full cream milk', 'Milk', 'ml', 4.2),
  ('oat_milk', 'Oat milk', 'Milk', 'ml', 14),
  ('condensed_milk', 'Condensed milk', 'Dairy', 'g', 9),
  ('chocolate_sauce', 'Chocolate sauce', 'Syrups & sauces', 'g', 10),
  ('pistachio_paste', 'Pistachio paste', 'Syrups & sauces', 'g', null),
  ('green_tea', 'Green tea leaves', 'Tea & botanicals', 'g', 60),
  ('ice', 'Ice', 'General', 'g', 0.2),
  ('oranges', 'Oranges', 'Fruit', 'g', 3),
  ('croissant_dough', 'Butter croissant (frozen)', 'Bakery stock', 'pcs', 1800),
  ('cup_12oz', '12oz paper cup', 'Packaging', 'pcs', 180),
  ('hot_lid', 'Hot cup lid', 'Packaging', 'pcs', 60),
  ('cup_16oz_clear', '16oz clear cup', 'Packaging', 'pcs', 220),
  ('straw', 'Paper straw', 'Packaging', 'pcs', 40),
];

final Map<String, (String, String, String, double?)> _ingredientByKey = {
  for (final (k, n, c, u, cost) in _ingredients) k: (n, c, u, cost),
};

const Set<String> _milkDrinks = {
  'cortado',
  'flatwhite',
  'cappuccino',
  'latte',
  'spanish',
  'mocha',
  'pistachio_latte',
};

/// What one unit of [item] (size [size], 0 = the first) deducts:
/// (ingredient, quantity, source).
List<(String, double, String)> _recipe(String item, String category, int size) {
  final big = size > 0;
  if (category == 'hot' && item == 'turkish') {
    return [('turkish_coffee', big ? 14 : 7, 'recipe')];
  }
  if (category == 'hot') {
    return [
      ('house_blend', item == 'espresso' && big ? 36 : 18, 'recipe'),
      if (_milkDrinks.contains(item)) ('full_milk', big ? 220 : 160, 'recipe'),
      if (item == 'spanish') ('condensed_milk', big ? 35 : 25, 'recipe'),
      if (item == 'mocha') ('chocolate_sauce', big ? 35 : 25, 'recipe'),
      if (item == 'pistachio_latte')
        ('pistachio_paste', big ? 20 : 15, 'recipe'),
      ('cup_12oz', 1, 'packaging'),
      ('hot_lid', 1, 'packaging'),
    ];
  }
  if (category == 'iced') {
    return [
      ('house_blend', 18, 'recipe'),
      ('full_milk', 150, 'recipe'),
      ('ice', 150, 'recipe'),
      ('cup_16oz_clear', 1, 'packaging'),
      ('straw', 1, 'packaging'),
    ];
  }
  if (category == 'tea') {
    return [('green_tea', 3, 'recipe'), ('cup_12oz', 1, 'packaging')];
  }
  if (category == 'juice') {
    return [
      ('oranges', 400, 'recipe'),
      ('cup_16oz_clear', 1, 'packaging'),
      ('straw', 1, 'packaging'),
    ];
  }
  if (category == 'bakery') return [('croissant_dough', 1, 'recipe')];
  // Desserts and breakfast plates are bought in: no recipe, cost unknown.
  return const [];
}

final Map<String, SeedItem> _itemById = {
  for (final m in seedMenu) MockSeed.menuItemId(m.key): m,
};

/// [line] (a line's JSON) with its deductions, and its cost when every
/// deduction is priced: what the backend snapshots when the sale lands.
/// Packaging deductions carry no cost of their own: the sheet prices them
/// from the catalogue, as it does on the web.
Map<String, Object?> _withDeductions(Map<String, Object?> line) {
  final kind = line['line_kind'];
  if (kind == 'combo') return line;
  final existing = line['deductions_snapshot'];
  if (existing is List && existing.isNotEmpty) return line;
  final item = _itemById[line['menu_item_id']];
  if (item == null) return line;
  final sizeLabel = line['size_label'] as String?;
  final size = sizeLabel == null
      ? 0
      : item.sizes.indexWhere((s) => s.$1 == sizeLabel).clamp(0, 9);
  final qty = (line['quantity']! as num).toInt();
  final recipe = _recipe(item.key, item.category, size);
  final out = Map<String, Object?>.of(line);
  if (recipe.isEmpty) {
    out['cost_missing'] = true;
    out['line_cost'] = null;
    return out;
  }
  var cost = 0.0;
  var missing = false;
  final snaps = <Map<String, Object?>>[];
  for (final (key, per, source) in recipe) {
    final (name, category, unit, cpu) = _ingredientByKey[key]!;
    final q = per * qty;
    final c = cpu == null ? null : q * cpu;
    if (c == null) {
      missing = true;
    } else {
      cost += c;
    }
    snaps.add({
      'ingredient_name': name,
      'quantity': q,
      'unit': unit,
      'source': source,
      'category': category,
      'org_ingredient_id': OrderSeedIds.ingredient(key),
      if (source == 'recipe') 'cost': c,
    });
  }
  out['deductions_snapshot'] = snaps;
  out['cost_missing'] = missing;
  out['line_cost'] = missing ? null : cost.round();
  out['unit_cost'] = missing ? null : (cost / qty).round();
  return out;
}

// ── The seed ─────────────────────────────────────────────────────────────

/// Adds this unit's rows to [db] once (a second call is a no-op).
void loadOrdersSeed(MockDb db) {
  if (db.hasTable(OrderTables.details)) return;
  loadSellSeed(db);
  db.table(OrderTables.details);
  db.table(OrderTables.deliveryOrders);
  _OrdersSeed(db).build();
}

class _OrdersSeed {
  _OrdersSeed(this.db);

  final MockDb db;

  DateTime get now => db.clock.now;

  late final DateTime today = MockClock.startOfCairoDay(now);

  final Map<String, String> _names = {
    for (final p in sabahStaff) p.key: p.name,
  };

  Map<String, Object?> _customer(int i) =>
      db['customers'].find(MockSeed.customerId(i)) ?? const {};

  /// One line of [item] (a seed key), [size] index, [qty], with optional
  /// add-ons `(group, option index)`.
  Map<String, Object?> _line(
    String orderId,
    int i,
    String item, {
    int size = 0,
    int qty = 1,
    List<(String, int)> addons = const [],
    Map<String, Object?> extra = const {},
  }) {
    final m = seedMenu.firstWhere((x) => x.key == item);
    final (label, egp) = m.sizes[size.clamp(0, m.sizes.length - 1)];
    final id = OrderSeedIds.line(orderId, i);
    final addonRows = [
      for (final (group, opt) in addons)
        () {
          final g = seedGroups.firstWhere((x) => x.key == group);
          final o = g.options[opt];
          return OrderItemAddon(
            id: mockUuid('order-item-addon:$id:$group'),
            orderItemId: id,
            addonItemId: MockSeed.addonItemId(group, o.key),
            addonName: o.name,
            nameTranslations: {'ar': o.ar},
            quantity: qty,
            unitPrice: o.egp * 100,
            lineTotal: o.egp * 100 * qty,
          ).toJson();
        }(),
    ];
    return _withDeductions({
      ...OrderItemFull(
        id: id,
        orderId: orderId,
        menuItemId: MockSeed.menuItemId(m.key),
        itemName: m.name,
        nameTranslations: {'ar': m.ar},
        sizeLabel: m.sizes.length > 1 ? label : null,
        quantity: qty,
        unitPrice: egp * 100,
        lineTotal: egp * 100 * qty,
        costMissing: false,
        deductionsSnapshot: const <Object?>[],
        addons: const [],
        optionals: const [],
      ).toJson(),
      'addons': addonRows,
      ...extra,
    });
  }

  static int _lineSum(Map<String, Object?> l) =>
      (l['line_total']! as num).toInt() +
      [
        for (final a in (l['addons'] as List? ?? const []))
          ((a as Map)['line_total']! as num).toInt(),
      ].fold<int>(0, (s, v) => s + v);

  /// The sales this unit adds, numbered per till once all are known.
  final List<Map<String, Object?>> _pending = [];

  /// Counter 2's till of [branchKey] on [date]: the second teller's.
  static String counterTill(String branchKey, String date) =>
      MockSeed.tillId(branchKey, date, 'counter2');

  /// A sale on [branchKey]'s Counter 2 (device T2) till of [at]'s day, with
  /// [lines]; numbered later in that till's own sequence.
  Map<String, Object?> _sale({
    required String id,
    required String branchKey,
    required DateTime at,
    required List<Map<String, Object?>> lines,
    required String method,
    List<PaymentLeg>? legs,
    String orderType = 'dine_in',
    String status = 'completed',
    int deliveryFee = 0,
    int discount = 0,
    Map<String, Object?> extra = const {},
    Map<String, Object?> details = const {},
  }) {
    final date = MockClock.cairoDate(at);
    final teller = branchTellers[branchKey]![1];
    final till = counterTill(branchKey, date);
    final subtotal = lines
        .where((l) => l['line_kind'] != 'combo')
        .fold<int>(0, (s, l) => s + _lineSum(l));
    final total = subtotal - discount + deliveryFee;
    final payLegs =
        legs ??
        [PaymentLeg(method: method, amount: total, isCash: method == 'cash')];
    final row = Order(
      id: id,
      branchId: MockSeed.branchIdOf(branchKey),
      tillId: till,
      shiftId: till,
      tellerId: SeedIds.user(teller),
      tellerName: _names[teller]!,
      deviceId: mockUuid('device:$branchKey:T2'),
      deviceCode: 'T2',
      orderNumber: 0,
      status: status,
      orderType: orderType,
      deliveryFee: deliveryFee,
      paymentMethod: method,
      paymentLegs: payLegs,
      subtotal: subtotal,
      discountAmount: discount,
      discountValue: 0,
      taxAmount: ((total - deliveryFee) * 14 / 114).round(),
      taxInclusive: true,
      taxRateApplied: MockSeed.taxRate,
      serviceChargeAmount: 0,
      totalAmount: total,
      timezone: MockClock.timezone,
      verification: 'server',
      createdAt: at,
    ).toJson()..addAll(extra);
    _pending.add(row);
    db[OrderTables.details].insert({
      'id': id,
      'items': lines,
      ...details,
    }, timestamps: false);
    return row;
  }

  void build() {
    _deliveries();
    _showcase();
    _ring();
  }

  /// Numbers the added sales per till by time (`T2-1`, `T2-2`…), stores
  /// them, and opens (and, on past days, closes) each Counter 2 till: the
  /// drawer holds the float plus the cash those sales took.
  void _ring() {
    final byTill = <String, List<Map<String, Object?>>>{};
    for (final o in _pending) {
      (byTill[o['till_id']! as String] ??= []).add(o);
    }
    for (final MapEntry(key: tillId, value: sales) in byTill.entries) {
      sales.sort(
        (a, b) =>
            (a['created_at']! as String).compareTo(b['created_at']! as String),
      );
      final first = sales.first;
      final branchId = first['branch_id']! as String;
      final b = seedBranches.firstWhere(
        (x) => MockSeed.branchIdOf(x.key) == branchId,
      );
      final at0 = DateTime.parse(first['created_at']! as String);
      final date = MockClock.cairoDate(at0);
      final ymd = date.substring(2).replaceAll('-', '');
      var cash = 0;
      for (final (i, o) in sales.indexed) {
        final n = i + 1;
        o
          ..['order_number'] = n
          ..['display_number'] = 'T2-$n'
          ..['order_ref'] = '${b.code}-$ymd-T2-${n.toString().padLeft(4, '0')}';
        if (o['status'] != 'voided') {
          for (final l
              in (o['payment_legs']! as List).cast<Map<String, Object?>>()) {
            if (l['is_cash'] == true) cash += (l['amount']! as num).toInt();
          }
        }
        db[OrderTables.orders].insert(o, timestamps: false);
      }
      final day = MockClock.startOfCairoDay(at0);
      final isToday = day == today;
      final opened = day.add(
        isToday
            ? Duration(hours: b.key == 'zamalek' ? 8 : 7, minutes: 55)
            : const Duration(hours: 11, minutes: 50),
      );
      final closed = day.add(const Duration(hours: 21, minutes: 10));
      final open = isToday;
      final teller = branchTellers[b.key]![1];
      final system = MockSeed.floatPiastres + cash;
      db['tills'].insert(
        Till(
          id: tillId,
          branchId: branchId,
          branchName: b.name,
          tellerId: SeedIds.user(teller),
          tellerName: _names[teller]!,
          deviceId: mockUuid('device:${b.key}:T2'),
          deviceCode: 'T2',
          deviceLabel: 'Counter 2',
          openedAt: opened,
          openingCash: MockSeed.floatPiastres,
          openingCashWasEdited: false,
          openedWhileAnotherOpen: false,
          disagreementCount: 0,
          status: open ? TillStatus.open : TillStatus.closed,
          verification: TillVerification.server,
          closedAt: open ? null : closed,
          closedBy: open ? null : SeedIds.user(teller),
          closingCashSystem: open ? null : system,
          closingCashDeclared: open ? null : system,
          cashDiscrepancy: open ? null : 0,
          openBillsAtClose: open ? null : 0,
          oldBillsAtClose: open ? null : 0,
          timezone: MockClock.timezone,
        ).toJson(),
        timestamps: false,
      );
    }
  }

  // ── the branch's own deliveries, 30 days ─────────────────────────────

  static const List<String> _deliveryItems = [
    'spanish',
    'latte',
    'cappuccino',
    'mocha',
    'americano',
    'flatwhite',
  ];

  void _deliveries() {
    for (var d = MockSeed.historyDays - 1; d >= 0; d--) {
      final day = today.subtract(Duration(days: d));
      final date = MockClock.cairoDate(day.add(const Duration(hours: 12)));
      final runs = [
        ('heliopolis', 'in_mall', const Duration(hours: 12, minutes: 30), 1),
        ('heliopolis', 'outside', const Duration(hours: 19, minutes: 15), 2),
        ('zamalek', 'outside', const Duration(hours: 13, minutes: 10), 1),
      ];
      for (final (branchKey, channel, offset, n) in runs) {
        final at = day.add(offset);
        if (at.isAfter(now)) continue;
        _delivery(
          branchKey: branchKey,
          date: date,
          n: n,
          at: at,
          channel: channel,
          dayIndex: d,
        );
      }
      if (d % 6 == 3) {
        final at = day.add(const Duration(hours: 20));
        if (!at.isAfter(now)) {
          _delivery(
            branchKey: 'heliopolis',
            date: date,
            n: 3,
            at: at,
            channel: 'outside',
            dayIndex: d,
            status: 'cancelled',
          );
        }
      }
    }
  }

  /// Heliopolis's mall is Korba Plaza; outside runs go to a few streets.
  static const List<(String, String, String, int, double, double)> _streets = [
    (
      'Al Ahram St 21',
      'Next to Roxy Square',
      'Heliopolis — Zone A',
      2100,
      30.0915,
      31.3189,
    ),
    (
      'El-Merghany St 14',
      'Opposite Baron Palace',
      'Heliopolis — Zone B',
      3400,
      30.0868,
      31.3302,
    ),
    (
      'Abou Bakr El-Seddik St 7',
      'Behind Triumph Hotel',
      'Heliopolis — Zone A',
      2700,
      30.0997,
      31.3305,
    ),
    (
      'Hassan Sabry St 9',
      'Near Gezira Club gate',
      'Zamalek — Island',
      1600,
      30.0581,
      31.2196,
    ),
  ];

  Map<String, Object?> _delivery({
    required String branchKey,
    required String date,
    required int n,
    required DateTime at,
    required String channel,
    required int dayIndex,
    String status = 'delivered',
    int customerIndex = -1,
    bool contactOverride = false,
    List<Map<String, Object?>> Function(String orderId)? lines,
    String method = 'card',
  }) {
    final id = OrderSeedIds.delivery(branchKey, date, n);
    final saleId = OrderSeedIds.deliverySale(branchKey, date, n);
    final ci = customerIndex >= 0 ? customerIndex : (dayIndex * 3 + n) % 60 + 5;
    final c = _customer(ci);
    final fee = channel == 'in_mall' ? 1000 : 2500;
    final street = _streets[branchKey == 'zamalek' ? 3 : (dayIndex + n) % 3];
    final item = _deliveryItems[(dayIndex + n) % _deliveryItems.length];
    final saleLines =
        lines?.call(saleId) ??
        [
          _line(
            saleId,
            0,
            item,
            size: dayIndex % 2,
            qty: 1 + (dayIndex % 3 == 0 ? 1 : 0),
          ),
          _line(saleId, 1, 'croissant'),
        ];
    final subtotal = saleLines
        .where((l) => l['line_kind'] != 'combo')
        .fold<int>(0, (s, l) => s + _lineSum(l));
    final inMall = channel == 'in_mall';
    final phone = (c['phone'] as String?) ?? '01001234567';
    final name = (c['name'] as String?) ?? 'Guest';
    final steps = const [
      'received',
      'confirmed',
      'preparing',
      'ready',
      'out_for_delivery',
      'delivered',
    ];
    final reached = steps.indexOf(status);
    DateTime? stamp(int step, int minutes) =>
        reached >= step ? at.add(Duration(minutes: minutes)) : null;
    final ref =
        'DLV-${date.substring(5).replaceAll('-', '')}${branchKey == 'zamalek' ? 'Z' : 'H'}$n';
    final materialised = status != 'cancelled' && reached >= 3;
    final row = DeliveryOrder(
      id: id,
      orgId: SeedIds.sabahOrg,
      branchId: MockSeed.branchIdOf(branchKey),
      orderId: materialised ? saleId : null,
      customerId: c['id'] as String?,
      customerName: name,
      customerPhone: phone,
      channel: channel,
      status: status,
      cart: const {},
      subtotal: subtotal,
      deliveryFee: fee,
      total: subtotal + fee,
      extraPrepMinutes: 0,
      otpVerified: false,
      contactOverride: contactOverride,
      placeName: inMall ? 'Korba Plaza' : null,
      addressLine: inMall ? null : street.$1,
      landmark: inMall ? null : street.$2,
      floor: inMall ? '2' : '${3 + n}',
      unitNumber: inMall ? '2${10 + n}' : '${8 + dayIndex % 6}',
      deliveryNotes: inMall
          ? 'Leave it at the shop counter.'
          : (n == 2 ? 'Ring twice, the bell is weak.' : null),
      deliveryRef: ref,
      roadDistanceMeters: inMall ? null : street.$4,
      customerLat: inMall ? null : street.$5,
      customerLng: inMall ? null : street.$6,
      paymentMethod: method,
      confirmedAt: stamp(1, 2),
      preparingAt: stamp(2, 4),
      readyAt: stamp(3, 12),
      outForDeliveryAt: inMall ? null : stamp(4, 15),
      deliveredAt: stamp(5, inMall ? 18 : 34),
      cancelledAt: status == 'cancelled'
          ? at.add(const Duration(minutes: 9))
          : null,
      cancelReason: status == 'cancelled' ? 'Customer unreachable' : null,
      createdAt: at,
      updatedAt: at.add(const Duration(minutes: 34)),
    ).toJson();
    db[OrderTables.deliveryOrders].insert(row, timestamps: false);
    if (materialised) {
      _sale(
        id: saleId,
        branchKey: branchKey,
        at: at.add(const Duration(minutes: 12)),
        lines: saleLines,
        method: method,
        orderType: 'delivery',
        deliveryFee: fee,
        extra: {
          'delivery_channel': channel,
          'delivery_order_id': id,
          'customer_id': c['id'],
          'customer_name': name,
          'delivery_lat': inMall ? null : street.$5,
          'delivery_lng': inMall ? null : street.$6,
        },
        details: {
          'delivery': OrderDeliveryInfo(
            channel: channel,
            customerPhone: phone,
            placeName: row['place_name'] as String?,
            addressLine: row['address_line'] as String?,
            landmark: row['landmark'] as String?,
            floor: row['floor'] as String?,
            unitNumber: row['unit_number'] as String?,
            deliveryNotes: row['delivery_notes'] as String?,
            zoneName: inMall ? null : street.$3,
            roadDistanceMeters: inMall ? null : street.$4,
            deliveryRef: ref,
          ).toJson(),
        },
      );
    }
    return row;
  }

  // ── this morning's sales that show the whole sheet ───────────────────

  void _showcase() {
    final date = MockClock.cairoDate(today.add(const Duration(hours: 12)));
    DateTime at(int h, int m) => today.add(Duration(hours: h, minutes: m));

    // A breakfast box (a combo) and a cappuccino a deal took 10 off.
    final combo = OrderSeedIds.showcase('combo');
    final header = mockUuid('order-item:$combo:0');
    final dealRule = mockUuid('deal-rule:morning-duo');
    final comboLines = [
      {
        ...OrderItemFull(
          id: header,
          orderId: combo,
          itemName: 'Breakfast Box',
          nameTranslations: const {'ar': 'بوكس الفطور'},
          quantity: 1,
          unitPrice: 0,
          lineTotal: 0,
          costMissing: false,
          deductionsSnapshot: const <Object?>[],
          addons: const [],
          optionals: const [],
        ).toJson(),
        'line_kind': 'combo',
        'combo_unit_price': 18500,
        'notes': 'Croissant warmed, please',
        'cost_missing': false,
        'line_cost': 0,
      },
      _line(
        combo,
        1,
        'latte',
        extra: {
          'line_kind': 'combo_part',
          'combo_line_id': header,
          'combo_slot_name': 'Hot drink',
          'combo_slot_name_translations': {'ar': 'مشروب ساخن'},
          'unit_price': 11000,
          'line_total': 11000,
        },
      ),
      _line(
        combo,
        2,
        'croissant',
        extra: {
          'line_kind': 'combo_part',
          'combo_line_id': header,
          'combo_slot_name': 'Pastry',
          'combo_slot_name_translations': {'ar': 'معجنات'},
          'combo_surcharge': 1500,
          'unit_price': 9000,
          'line_total': 9000,
        },
      ),
      _line(
        combo,
        3,
        'cappuccino',
        extra: {'deal_minor': 1000, 'line_total': 10000},
      ),
    ];
    _sale(
      id: combo,
      branchKey: 'heliopolis',
      at: at(8, 5),
      lines: comboLines,
      method: 'cash',
      details: {
        'deals': [
          OrderDeal(
            id: mockUuid('order-deal:$combo'),
            dealRuleId: dealRule,
            name: 'Morning Duo',
            nameTranslations: const {'ar': 'ثنائي الصباح'},
            discount: 1000,
            times: 1,
            lines: [
              OrderDealLine(
                orderItemId: OrderSeedIds.line(combo, 3),
                discount: 1000,
                units: 1,
              ),
            ],
          ).toJson(),
        ],
      },
    );

    // A loyalty member's free latte, and a croissant paid for.
    final member = _customer(0);
    final reward = OrderSeedIds.showcase('reward');
    _sale(
      id: reward,
      branchKey: 'heliopolis',
      at: at(8, 20),
      lines: [
        _line(
          reward,
          0,
          'latte',
          extra: {
            'is_reward': true,
            'reward_covered': 11500,
            'reward_units': 1,
            'line_total': 0,
          },
        ),
        _line(reward, 1, 'croissant'),
      ],
      method: 'cash',
      extra: {
        'customer_id': member['id'],
        'customer_name': member['name'],
        'loyalty_customer_id': member['id'],
        'loyalty_member_name': member['name'],
      },
    );

    // A reward the till gave offline that the balance could not pay for.
    final regular = _customer(1);
    final refused = OrderSeedIds.showcase('refused');
    _sale(
      id: refused,
      branchKey: 'heliopolis',
      at: at(8, 40),
      lines: [
        _line(
          refused,
          0,
          'spanish',
          extra: {
            'is_reward': true,
            'reward_covered': 13000,
            'reward_units': 1,
            'line_total': 0,
          },
        ),
        _line(refused, 1, 'americano'),
      ],
      method: 'card',
      extra: {
        'customer_id': regular['id'],
        'customer_name': regular['name'],
        'loyalty_customer_id': regular['id'],
        'loyalty_member_name': regular['name'],
        'verification': 'replayed',
      },
      details: {
        'loyalty_redemption_refused':
            'Not enough stamps: the card holds 3 and the reward needs 6.',
      },
    );

    // A staff drink: the base drink free, oat milk paid, the extra shot the
    // pool covered.
    final staff = OrderSeedIds.showcase('staff');
    final staffLine = OrderSeedIds.line(staff, 0);
    _sale(
      id: staff,
      branchKey: 'heliopolis',
      at: at(9, 0),
      lines: [
        {
          ..._line(staff, 0, 'spanish'),
          'line_total': 0,
          'staff_comp_minor': 16000,
          'staff_drink_id': mockUuid('staff-drink:$staff'),
          'addons': [
            OrderItemAddon(
              id: mockUuid('order-item-addon:$staffLine:milk'),
              orderItemId: staffLine,
              addonItemId: MockSeed.addonItemId('milk', 'oat'),
              addonName: 'Oat milk',
              nameTranslations: const {'ar': 'حليب الشوفان'},
              quantity: 1,
              unitPrice: 2500,
              lineTotal: 2500,
            ).toJson(),
            OrderItemAddon(
              id: mockUuid('order-item-addon:$staffLine:extras'),
              orderItemId: staffLine,
              addonItemId: MockSeed.addonItemId('extras', 'shot'),
              addonName: 'Extra shot',
              nameTranslations: const {'ar': 'شوت إضافي'},
              quantity: 1,
              unitPrice: 0,
              lineTotal: 0,
              staffCompMinor: 3000,
            ).toJson(),
          ],
          'optionals': [
            OrderItemOptional(
              id: mockUuid('order-item-optional:$staffLine:sugar'),
              orderItemId: staffLine,
              fieldName: 'Less sugar',
              nameTranslations: const {'ar': 'سكر أقل'},
              price: 0,
            ).toJson(),
          ],
          'notes': 'For Ali, end of shift',
        },
      ],
      method: 'cash',
    );

    // Rung offline against yesterday's menu.
    final offline = OrderSeedIds.showcase('offline');
    _sale(
      id: offline,
      branchKey: 'heliopolis',
      at: at(9, 15),
      lines: [
        _line(offline, 0, 'mocha', size: 1),
        _line(offline, 1, 'cappuccino'),
      ],
      method: 'card',
      extra: {
        'price_flagged': true,
        'price_expected_total': 27000,
        'verification': 'replayed',
      },
    );

    // Voided: the guest left before it was ready.
    final voided = OrderSeedIds.showcase('voided');
    _sale(
      id: voided,
      branchKey: 'heliopolis',
      at: at(9, 25),
      lines: [_line(voided, 0, 'iced_latte'), _line(voided, 1, 'croissant')],
      method: 'cash',
      status: 'voided',
      extra: {
        'void_reason': 'other',
        'void_note': 'Guest left before it was ready',
        'voided_at': at(9, 31).toIso8601String(),
        'voided_by': SeedIds.user(branchManagers['heliopolis']!),
      },
    );

    // Zamalek: a table's bill split cash + card, started by another teller.
    final split = OrderSeedIds.showcase('split');
    final splitLines = [
      _line(split, 0, 'flatwhite', qty: 2),
      _line(split, 1, 'cheesecake'),
      _line(split, 2, 'orange'),
    ];
    final splitTotal = splitLines.fold<int>(0, (s, l) => s + _lineSum(l));
    _sale(
      id: split,
      branchKey: 'zamalek',
      at: at(9, 30),
      lines: splitLines,
      method: 'mixed',
      legs: [
        PaymentLeg(method: 'cash', amount: 30000, isCash: true),
        PaymentLeg(method: 'card', amount: splitTotal - 30000, isCash: false),
      ],
      extra: {
        'waiter_id': SeedIds.user('adham'),
        'waiter_name': _names['adham'],
        'started_by': SeedIds.user('mariam'),
        'started_by_name': _names['mariam'],
        'tip_amount': 2000,
        'tip_payment_method': 'card',
      },
    );

    // This morning's own deliveries: one to a shop in the mall, one still
    // on the road, ordered by a customer for her mother.
    _delivery(
      branchKey: 'heliopolis',
      date: date,
      n: 7,
      at: at(9, 10),
      channel: 'in_mall',
      dayIndex: 0,
      customerIndex: 3,
      method: 'cash',
    );
    _delivery(
      branchKey: 'heliopolis',
      date: date,
      n: 8,
      at: at(9, 40),
      channel: 'outside',
      dayIndex: 0,
      customerIndex: 2,
      status: 'out_for_delivery',
      contactOverride: true,
      method: 'cash',
    );
    final onRoad = db[OrderTables.deliveryOrders].find(
      OrderSeedIds.delivery('heliopolis', date, 8),
    )!;
    onRoad['customer_name'] = 'Mona Adel';
    onRoad['customer_phone'] = '01223456781';
  }
}

// ── Handlers ─────────────────────────────────────────────────────────────

class _Handlers {
  _Handlers(this.db);

  final MockDb db;

  /// Lines per order, read once (the core seed builds them on demand).
  final Map<String, List<Map<String, Object?>>> _lines = {};

  List<Map<String, Object?>> linesOf(String orderId) => _lines[orderId] ??= () {
    final own = db[OrderTables.details].find(orderId)?['items'];
    if (own is List) {
      return [
        for (final l in own) Map<String, Object?>.of(l as Map<String, Object?>),
      ];
    }
    return [
      for (final it in MockSeed.instance.orderItems(orderId))
        _withDeductions(it.toJson()),
    ];
  }();

  String _org(MockRequest req) =>
      req.orgId ??
      (throw MockHttpError(MockResponse.forbidden('No org in token')));

  /// The org's live branches.
  List<String> _orgBranches(String org) => [
    for (final b in db['branches'].rows)
      if (b['org_id'] == org && b['deleted_at'] == null) b['id']! as String,
  ];

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  String? _uuidParam(MockRequest req, String key) {
    final v = req.q(key);
    if (v == null) return null;
    if (!_uuid.hasMatch(v)) {
      req.badRequest('Query deserialize error: UUID parsing failed');
    }
    return v.toLowerCase();
  }

  /// The scope rule `list_orders` and `export_orders` share: one till, one
  /// branch, or every branch of the org (no branch, or the nil id).
  bool Function(MockRow) _scope(MockRequest req, String org) {
    final till = _uuidParam(req, 'till_id') ?? _uuidParam(req, 'shift_id');
    if (till != null) {
      final t = db['tills'].find(till);
      if (t == null) req.notFound('Shift not found');
      req.requireBranch(t['branch_id']! as String);
      return (o) => o['till_id'] == till;
    }
    final branch = _uuidParam(req, 'branch_id');
    if (branch == null || branch == _allBranches) {
      final ids = _orgBranches(org).toSet();
      return (o) => ids.contains(o['branch_id']);
    }
    req.requireBranch(branch);
    return (o) => o['branch_id'] == branch;
  }

  /// `parse_payment_methods`: each name an active method of the org.
  Set<String>? _methods(MockRequest req, String org) {
    final raw = req.q('payment_method');
    if (raw == null) return null;
    final names = [
      for (final p in raw.split(','))
        if (p.trim().isNotEmpty) p.trim(),
    ];
    for (final n in names) {
      final ok = db['payment_methods'].rows.any(
        (m) => m['org_id'] == org && m['name'] == n && m['is_active'] == true,
      );
      if (!ok) req.badRequest('Invalid or inactive payment_method: $n');
    }
    return names.isEmpty ? null : names.toSet();
  }

  static bool _ilike(Object? value, String? needle) =>
      needle == null ||
      (value is String && value.toLowerCase().contains(needle.toLowerCase()));

  static bool _paidBy(MockRow o, Set<String> methods) {
    if (methods.contains(o['payment_method'])) return true;
    final legs = o['payment_legs'];
    return legs is List &&
        legs.any((l) => l is Map && methods.contains(l['method']));
  }

  /// The filters both reads share; [full] adds the list's own (type,
  /// channel, `updated_after`), which the export does not know.
  List<MockRow> _filtered(MockRequest req, {required bool full}) {
    final org = _org(req);
    final inScope = _scope(req, org);
    final methods = _methods(req, org);
    final teller = req.q('teller_name');
    final waiter = req.q('waiter_name');
    final status = req.q('status');
    final from = req.qDateTime('from');
    final to = req.qDateTime('to');
    final updatedAfter = full ? req.qDateTime('updated_after') : null;
    final type = full ? req.q('order_type') : null;
    final channel = full ? req.q('channel') : null;
    final rows = db[OrderTables.orders].where((o) {
      if (!inScope(o)) return false;
      if (!_ilike(o['teller_name'], teller)) return false;
      if (waiter != null && !_ilike(o['waiter_name'], waiter)) return false;
      if (methods != null && !_paidBy(o, methods)) return false;
      if (status != null && o['status'] != status) return false;
      final at = DateTime.parse(o['created_at']! as String);
      if (from != null && at.isBefore(from)) return false;
      if (to != null && at.isAfter(to)) return false;
      if (updatedAfter != null) {
        final u = DateTime.parse(
          (o['updated_at'] ?? o['created_at'])! as String,
        );
        if (!u.isAfter(updatedAfter)) return false;
      }
      if (type != null && o['order_type'] != type) return false;
      if (channel != null && o['delivery_channel'] != channel) return false;
      return true;
    });
    rows.sort(
      (a, b) =>
          (b['created_at']! as String).compareTo(a['created_at']! as String),
    );
    return rows;
  }

  static bool _sold(MockRow o) =>
      o['status'] != 'voided' && o['status'] != 'refunded';

  static int _int(Object? v) => (v as num?)?.toInt() ?? 0;

  /// `order_summary_cols`: the figures over every matching order.
  OrderSummary _summary(List<MockRow> rows, {Set<String> exclude = const {}}) {
    var revenue = 0, completed = 0, voided = 0, discounts = 0, tips = 0;
    var fees = 0, dOrders = 0, dRevenue = 0, items = 0;
    var mallOrders = 0, mallRevenue = 0, mallFees = 0;
    var outOrders = 0, outRevenue = 0, outFees = 0;
    for (final o in rows) {
      if (o['status'] == 'voided') voided++;
      if (!_sold(o)) continue;
      final total = _int(o['total_amount']);
      final fee = _int(o['delivery_fee']);
      revenue += total;
      completed++;
      discounts += _int(o['discount_amount']);
      tips += _int(o['tip_amount']);
      fees += fee;
      if (o['order_type'] == 'delivery') {
        dOrders++;
        dRevenue += total;
      }
      if (o['delivery_channel'] == 'in_mall') {
        mallOrders++;
        mallRevenue += total;
        mallFees += fee;
      } else if (o['delivery_channel'] == 'outside') {
        outOrders++;
        outRevenue += total;
        outFees += fee;
      }
      for (final l in linesOf(o['id']! as String)) {
        if (l['line_kind'] == 'combo') continue;
        if (exclude.contains(l['menu_item_id'])) continue;
        items += _int(l['quantity']);
      }
    }
    return OrderSummary(
      revenue: revenue,
      completed: completed,
      voided: voided,
      discounts: discounts,
      tips: tips,
      deliveryFees: fees,
      deliveryOrders: dOrders,
      deliveryRevenue: dRevenue,
      inMallOrders: mallOrders,
      inMallRevenue: mallRevenue,
      inMallFees: mallFees,
      outsideOrders: outOrders,
      outsideRevenue: outRevenue,
      outsideFees: outFees,
      lineItems: items,
    );
  }

  MockResponse list(MockRequest req) {
    req.requireCap('orders.read');
    final rows = _filtered(req, full: true);
    final rawExclude = req.q('exclude_items');
    final exclude = <String>{};
    if (rawExclude != null) {
      for (final p in rawExclude.split(',')) {
        final s = p.trim();
        if (s.isEmpty) continue;
        if (!_uuid.hasMatch(s))
          req.badRequest('Invalid uuid in exclude_items: $s');
        exclude.add(s.toLowerCase());
      }
    }
    final perDefault = req.q('till_id') != null || req.q('shift_id') != null
        ? 1000
        : 100;
    return MockResponse.ok(
      pageOf(
        rows,
        req,
        defaultPerPage: perDefault,
        maxPerPage: 1000,
        extra: {'summary': _summary(rows, exclude: exclude).toJson()},
      ),
    );
  }

  Map<String, Object?> _full(MockRow o) {
    final id = o['id']! as String;
    final d = db[OrderTables.details].find(id);
    return {
      ...o,
      'items': linesOf(id),
      'warnings': const <String>[],
      'delivery': d?['delivery'],
      'deals': d?['deals'] ?? const <Object?>[],
      'loyalty_redemption_refused': d?['loyalty_redemption_refused'],
    };
  }

  MockRow _order(MockRequest req) {
    final id = req.param('order_id');
    final o = _uuid.hasMatch(id) ? db[OrderTables.orders].find(id) : null;
    if (o == null) req.notFound('Order not found');
    req.requireBranch(o['branch_id']! as String);
    return o;
  }

  MockResponse get(MockRequest req) {
    req.requireCap('orders.read');
    return MockResponse.ok(_full(_order(req)));
  }

  MockResponse voidOrder(MockRequest req) {
    req.requireCap('orders.void');
    final o = _order(req);
    final body = req.bodyAs(VoidOrderRequest.fromJson);
    // A teller's grant is limited (`void_ask` + `decide`): their own sale,
    // within ten minutes; past it the same refusal as no grant at all.
    final teller = req.persona.roleKinds.contains('teller');
    if (teller) {
      final own = o['teller_id'] == req.persona.userId;
      final age = req.now.difference(
        DateTime.parse(o['created_at']! as String),
      );
      if (!own || age > const Duration(minutes: 10)) {
        req.fail(MockResponse.denied('orders.void'));
      }
    }
    if (o['status'] == 'voided') return MockResponse.ok(o);
    // A teller may not rewrite a settled (closed) shift.
    if (teller &&
        db['tills'].find(o['till_id']! as String)?['status'] != 'open') {
      req.fail(
        MockResponse.forbidden(
          "This order's shift is closed — ask a manager to void it.",
        ),
      );
    }
    // `VoidReason::read`: an older till's label reads as "other" with the
    // label kept as the note.
    const reasons = {
      'customer_request',
      'wrong_order',
      'quality_issue',
      'other',
    };
    final known = reasons.contains(body.reason);
    final reason = known ? body.reason : 'other';
    final typed = body.note?.trim();
    final note = (typed == null || typed.isEmpty)
        ? (known ? null : body.reason)
        : typed;
    if (reason == 'other' && note == null) {
      req.badRequest("A note is required when void reason is 'other'");
    }
    // A sale that has given money back did happen (owner ruling 4).
    final refunded = refundedOn(db, o['id']! as String);
    if (refunded > 0) {
      req.conflict(
        '$refunded has already been refunded against this sale, so it cannot '
        'be voided — refund the remainder instead.',
      );
    }
    o
      ..['status'] = 'voided'
      ..['void_reason'] = reason
      ..['void_note'] = note
      ..['voided_at'] = req.now.toIso8601String()
      ..['voided_by'] = req.persona.userId
      ..['updated_at'] = req.now.toIso8601String();
    return MockResponse.ok(o);
  }

  /// Ten export reads a minute per person (shared with the customers
  /// export), then 429 `EXPORT_RATE_LIMITED`.
  void _throttle(MockRequest req) {
    final h = req.headers['X-Madar-Export'] ?? req.headers['x-madar-export'];
    if (h != '1') return;
    final hits = db[CustomerTables.exportHits];
    final now = req.now;
    final recent = hits.where(
      (x) =>
          x['user'] == req.persona.userId &&
          now.difference(DateTime.parse(x['at']! as String)).inSeconds < 60,
    );
    if (recent.length >= mockExportsPerMinute) {
      req.fail(
        MockResponse.error(
          429,
          'Too many exports; try again in a minute',
          code: 'EXPORT_RATE_LIMITED',
          retryAfterSeconds: 60,
        ),
      );
    }
    hits.insert({
      'user': req.persona.userId,
      'at': now.toIso8601String(),
    }, timestamps: false);
  }

  MockResponse export(MockRequest req) {
    req.requireCap('orders.read');
    _throttle(req);
    final rows = _filtered(req, full: false);
    if (rows.length > 50000) {
      req.badRequest(
        'Export too large: ${rows.length} orders match. Narrow the date range '
        'or add filters (limit: 50000).',
      );
    }
    final costs = <String, int>{};
    final data = [
      for (final o in rows)
        () {
          final id = o['id']! as String;
          final items = linesOf(id);
          for (final l in items) {
            final snaps = l['deductions_snapshot'];
            if (snaps is! List) continue;
            for (final s in snaps) {
              final ing = (s as Map)['org_ingredient_id'] as String?;
              if (ing == null) continue;
              final key = _ingredients.where(
                (i) => OrderSeedIds.ingredient(i.$1) == ing,
              );
              final cpu = key.isEmpty ? null : key.first.$5;
              if (cpu != null) costs[ing] = cpu.round();
            }
          }
          final legs = (o['payment_legs'] as List?) ?? const [];
          return {
            ...o,
            'items': items,
            'payments': [
              for (final (i, l) in legs.indexed)
                OrderPayment(
                  id: mockUuid('order-payment:$id:$i'),
                  orderId: id,
                  method: (l as Map)['method']! as String,
                  amount: _int(l['amount']),
                  reference: l['method'] == 'card'
                      ? 'RRN ${id.substring(0, 6).toUpperCase()}'
                      : null,
                ).toJson(),
            ],
          };
        }(),
    ];
    return MockResponse.ok({
      'data': data,
      'total': rows.length,
      'summary': _summary(rows).toJson(),
      'generated_at': req.now.toIso8601String(),
      'ingredient_costs': costs,
    });
  }

  MockResponse deliverySales(MockRequest req) {
    req.requireCap('orders.read');
    final org = _org(req);
    final id = req.param('branch_id');
    final Set<String> ids;
    if (id == _allBranches) {
      ids = _orgBranches(org).toSet();
    } else {
      req.requireBranch(id);
      ids = {id};
    }
    final from = req.qDateTime('from');
    final to = req.qDateTime('to');
    final rows = db[OrderTables.deliveryOrders].where((r) {
      if (!ids.contains(r['branch_id'])) return false;
      final at = DateTime.parse(r['created_at']! as String);
      if (from != null && at.isBefore(from)) return false;
      if (to != null && at.isAfter(to)) return false;
      return true;
    });
    return MockResponse.ok(deliverySalesOf(rows, from: from, to: to));
  }

  MockResponse deliveryOrder(MockRequest req) {
    req.requireCap('delivery.orders.read');
    final id = req.param('id');
    final r = _uuid.hasMatch(id)
        ? db[OrderTables.deliveryOrders].find(id)
        : null;
    if (r == null) req.notFound('Delivery order not found');
    req.requireBranch(r['branch_id']! as String);
    return MockResponse.ok(r);
  }

  MockResponse catalog(MockRequest req) {
    req.requireCap('inventory.read');
    final org = req.param('org_id');
    req.requireSameOrg(org);
    if (db.hasTable('org_ingredients') && db['org_ingredients'].length > 0) {
      return MockResponse.ok(
        db['org_ingredients'].query(filters: {'org_id': org}, sort: 'name'),
      );
    }
    final at = DateTime.utc(2025, 11, 2, 8);
    return MockResponse.ok(
      [
        for (final (key, name, category, unit, cpu) in _ingredients)
          OrgIngredient(
            id: OrderSeedIds.ingredient(key),
            orgId: org,
            name: name,
            unit: unit,
            costPerUnit: cpu,
            categoryId: mockUuid('ingredient-category:$category'),
            categoryName: category,
            categorySlug: category.toLowerCase().replaceAll(
              RegExp('[^a-z]+'),
              '_',
            ),
            isActive: true,
            createdAt: at,
            updatedAt: at,
          ),
      ]..sort((a, b) => a.name.compareTo(b.name)),
    );
  }

  MockResponse menuItems(MockRequest req) {
    req.requireCap('menu.items.read');
    final org = req.q('org_id');
    if (org == null)
      req.badRequest('Query deserialize error: missing field `org_id`');
    req.requireSameOrg(org);
    return MockResponse.ok(
      db['menu_items'].query(filters: {'org_id': org}, sort: 'name'),
    );
  }
}

/// The delivery report over delivery-order rows: per channel, delivered
/// orders' revenue, fees and average, and the cancellations.
DeliverySalesReport deliverySalesOf(
  Iterable<MockRow> rows, {
  DateTime? from,
  DateTime? to,
}) {
  int n(Object? v) => (v as num?)?.toInt() ?? 0;
  final channels = [
    for (final name in const ['in_mall', 'outside'])
      () {
        final mine = rows.where((r) => r['channel'] == name);
        final done = mine.where((r) => r['status'] == 'delivered');
        final orders = done.length;
        final revenue = done.fold<int>(0, (s, r) => s + n(r['total']));
        final fees = done.fold<int>(0, (s, r) => s + n(r['delivery_fee']));
        return DeliveryChannelSales(
          channel: name,
          orders: orders,
          revenue: revenue,
          deliveryFees: fees,
          goodsRevenue: revenue - fees,
          avgOrderValue: orders == 0 ? 0 : revenue ~/ orders,
          cancelledOrders: mine.where((r) => r['status'] == 'cancelled').length,
        );
      }(),
  ];
  final orders = channels.fold<int>(0, (s, c) => s + c.orders);
  final revenue = channels.fold<int>(0, (s, c) => s + c.revenue);
  final fees = channels.fold<int>(0, (s, c) => s + c.deliveryFees);
  return DeliverySalesReport(
    from: from,
    to: to,
    totalOrders: orders,
    totalRevenue: revenue,
    totalDeliveryFees: fees,
    totalGoodsRevenue: revenue - fees,
    avgOrderValue: orders == 0 ? 0 : revenue ~/ orders,
    cancelledOrders: channels.fold<int>(0, (s, c) => s + c.cancelledOrders),
    channels: channels,
  );
}
