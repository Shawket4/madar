/// The mock backend for Staff drinks and Bundles (REP-SPL, REP-BUN):
///
/// - `GET /staff-pool/today`, `GET /staff-pool/drinks`,
///   `GET /staff-pool/drinks/summary` (`staff_pool/record.rs`): the pool's
///   day, the drinks of a range of business days (newest first) and their
///   totals, over the `staff_drinks` table;
/// - `GET /reports/bundles`, `GET /reports/bundles/combos/{id}/mix`
///   (`reports/bundles.rs`): each combo and deal sold, and what went into a
///   combo, over the `reports_bundle_sales` table;
/// - `GET /orders/{order_id}` for the sale a staff drink was rung on, when no
///   other area answers that route (the orders area owns it in the app).
///
/// Handlers behave like the backend: the capability (`orders.staff_drink
/// .record`, `reports.bundles`) and branch refusals in its 403 envelope, 400
/// for a range that ends before it starts or a kind that is neither, 404 for
/// an unknown branch or combo, the branch-local business dates, and the
/// effective pool settings (a branch's override, else the org's, else off).
///
/// The data is fictional and deterministic: Sabah's four branches over the
/// month before the seed's "now" (2026-10-08 10:00 Cairo), the combos and
/// deals the offers area seeds (same ids and names), item prices from the core
/// seed's menu and costs from `../area_seed.dart` (V60 and shakshuka have no
/// known cost). A test changes a table's rows to set up its case.
library;

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart' show allBranchesId;

import '../area_seed.dart';

void registerStaffPoolBundlesMocks(MockServer server, MockDb db) {
  StaffPoolMock.register(server, db);
  BundlesMock.register(server, db);
}

// ── shared ────────────────────────────────────────────────────────────────

const String _sabahOrgKey = 'sabah';

final RegExp _ymdPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

String _two(int v) => v.toString().padLeft(2, '0');

String _ymdOf(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

/// A `YYYY-MM-DD` query parameter as actix's `NaiveDate` reads it: absent is
/// null; anything else that is not a real date is a 400.
String? _dateParam(MockRequest req, String key, {bool required = false}) {
  final v = req.q(key);
  if (v == null) {
    if (required) {
      req.badRequest('Query deserialize error: missing field `$key`');
    }
    return null;
  }
  final d = _ymdPattern.hasMatch(v) ? DateTime.tryParse(v) : null;
  if (d == null || _ymdOf(d) != v) {
    req.badRequest(
      'Query deserialize error: input contains invalid characters',
    );
  }
  return v;
}

/// A Sabah branch id (404 for one nobody knows, 403 for another org's).
void _requireKnownBranch(MockRequest req, String branchId) {
  if (SeedIds.sabahBranches.contains(branchId)) return;
  if (SeedIds.nakhlaBranches.contains(branchId)) {
    req.requireSameOrg(SeedIds.nakhlaOrg);
    return;
  }
  req.notFound('Branch not found');
}

SeedBranch _branch(String key) => seedBranches.firstWhere((b) => b.key == key);

/// The seed's menu item [key]; it must exist.
SeedItem _item(String key) => seedMenuItem(key)!;

/// The size label the wire carries for a line: the size for a sized item,
/// null for a single-size one.
String? _lineSize(SeedItem item, int sizeIndex) =>
    item.sizes.length > 1 ? item.sizes[sizeIndex].$1 : null;

/// What one unit costs to make at [sizeIndex] (null when unknown).
int? _unitCost(SeedItem item, int sizeIndex) =>
    menuUnitCost(item.key, reportSizeLabel(item, sizeIndex));

/// Registers [handler] unless another area already answers the route.
void _onIfAbsent(
  MockServer server,
  String method,
  String template,
  MockHandler handler,
) {
  if (server.handles(method, template)) return;
  server.on(method, template, handler);
}

// ── Staff drinks ──────────────────────────────────────────────────────────

/// One branch's pool as the seed sets it up: its own override (or the org's
/// default) and the last business day it rang drinks on.
class _PoolBranch {
  const _PoolBranch(this.key, this.allowance, {this.lastDay});
  final String key;
  final int allowance;

  /// New Cairo switched its pool off after this day.
  final String? lastDay;
}

/// The staff drinks pool: its settings, its history and its handlers.
abstract final class StaffPoolMock {
  /// The backend's tables.
  static const String drinksTable = 'staff_drinks';
  static const String settingsTable = 'staff_pool_settings';

  /// Where the sales the drinks were rung on live (read by `GET /orders/…`).
  static const String ordersTable = 'reports_staff_drink_orders';

  /// The org default: three drinks a day.
  static const int orgAllowance = 3;

  /// The items that count as a staff drink.
  static const List<String> eligibleKeys = [
    'americano',
    'latte',
    'cappuccino',
    'iced_latte',
    'iced_americano',
    'mint_lemonade',
    'green_tea',
    'v60',
  ];

  static List<String> get eligibleItemIds => [
    for (final k in eligibleKeys) MockSeed.menuItemId(k),
  ];

  /// Heliopolis 4 and Zamalek 5 (their overrides); Maadi follows the org
  /// (3); New Cairo turned its pool off on 1 October.
  static const List<_PoolBranch> _branches = [
    _PoolBranch('heliopolis', 4),
    _PoolBranch('maadi', orgAllowance),
    _PoolBranch('new-cairo', orgAllowance, lastDay: '2026-09-30'),
    _PoolBranch('zamalek', 5),
  ];

  /// Maadi's second till ran a POS from before priced staff drinks until
  /// this day: its drinks have no figures (`comp_minor` null).
  static const String maadiPricedFrom = '2026-09-15';

  /// The settings rows (`staff_pool_settings`): the org default and three
  /// branch overrides.
  static List<MockRow> settingsRows() => [
    {
      'id': mockUuid('staff-pool-settings:$_sabahOrgKey'),
      'org_id': SeedIds.sabahOrg,
      'branch_id': null,
      'enabled': true,
      'daily_allowance': orgAllowance,
      'eligible_item_ids': eligibleItemIds,
    },
    {
      'id': mockUuid('staff-pool-settings:heliopolis'),
      'org_id': SeedIds.sabahOrg,
      'branch_id': SeedIds.heliopolis,
      'enabled': true,
      'daily_allowance': 4,
      'eligible_item_ids': eligibleItemIds,
    },
    {
      'id': mockUuid('staff-pool-settings:zamalek'),
      'org_id': SeedIds.sabahOrg,
      'branch_id': SeedIds.zamalek,
      'enabled': true,
      'daily_allowance': 5,
      'eligible_item_ids': eligibleItemIds,
    },
    {
      'id': mockUuid('staff-pool-settings:new-cairo'),
      'org_id': SeedIds.sabahOrg,
      'branch_id': SeedIds.newCairo,
      'enabled': false,
      'daily_allowance': orgAllowance,
      'eligible_item_ids': eligibleItemIds,
    },
  ];

  /// What a branch runs on (`load_effective`): its own row, else the org's,
  /// else off with nothing allowed.
  static MockRow effectiveSettings(MockDb db, String orgId, String branchId) {
    final rows = db[settingsTable].rows;
    final own = rows
        .where((r) => r['org_id'] == orgId && r['branch_id'] == branchId)
        .firstOrNull;
    if (own != null) return own;
    final org = rows
        .where((r) => r['org_id'] == orgId && r['branch_id'] == null)
        .firstOrNull;
    if (org != null) return {...org, 'branch_id': branchId};
    return {
      'org_id': orgId,
      'branch_id': branchId,
      'enabled': false,
      'daily_allowance': 0,
      'eligible_item_ids': const <String>[],
    };
  }

  /// `pool_state`: what [allowance] and [used] leave.
  static Map<String, int> poolState(int allowance, int used) {
    final a = allowance < 0 ? 0 : allowance;
    final u = used < 0 ? 0 : used;
    return {
      'allowance': a,
      'used': u,
      'remaining': a - u > 0 ? a - u : 0,
      'over': u - a > 0 ? u - a : 0,
    };
  }

  /// Every drink of the seed, newest first, as `StaffDrink` JSON.
  static List<MockRow> get drinks => _history.drinks;

  /// The sale behind each priced drink, as `OrderFull` JSON.
  static List<MockRow> get orders => _history.orders;

  static final _StaffHistory _history = _StaffHistory.build();

  /// The drinks of [branchId] over [from]…[to] (business days, inclusive),
  /// newest first: `business_date DESC, recorded_at DESC, id`.
  static List<MockRow> drinksIn(
    MockDb db,
    String branchId,
    String from,
    String to, {
    bool overspentOnly = false,
  }) {
    final out = [
      for (final d in db[drinksTable].rows)
        if (d['branch_id'] == branchId &&
            '${d['business_date']}'.compareTo(from) >= 0 &&
            '${d['business_date']}'.compareTo(to) <= 0 &&
            (!overspentOnly || d['overspent'] == true))
          d,
    ];
    out.sort((a, b) {
      final day = '${b['business_date']}'.compareTo('${a['business_date']}');
      if (day != 0) return day;
      final at = '${b['recorded_at']}'.compareTo('${a['recorded_at']}');
      if (at != 0) return at;
      return '${a['id']}'.compareTo('${b['id']}');
    });
    return out;
  }

  /// `StaffDrinksSummary` over [rows].
  static Map<String, int> summarize(Iterable<MockRow> rows) {
    int n(Object? v) => v is num ? v.toInt() : 0;
    var drinks = 0;
    var quantity = 0;
    var overspent = 0;
    var comp = 0;
    var extras = 0;
    var cost = 0;
    var mismatches = 0;
    var unpriced = 0;
    for (final d in rows) {
      drinks++;
      quantity += n(d['quantity']);
      if (d['overspent'] == true) overspent++;
      comp += n(d['comp_minor']);
      extras += n(d['extras_minor']);
      cost += n(d['cost_minor']);
      final reported = d['comp_minor_reported'];
      if (reported != null && reported != d['comp_minor']) mismatches++;
      if (d['comp_minor'] == null) unpriced++;
    }
    return {
      'drinks': drinks,
      'quantity': quantity,
      'overspent': overspent,
      'comp_minor': comp,
      'extras_minor': extras,
      'cost_minor': cost,
      'comp_mismatches': mismatches,
      'unpriced': unpriced,
    };
  }

  /// The branch's business day of [now] (Cairo for every Sabah branch).
  static String today(DateTime now) => MockClock.cairoDate(now);

  static void register(MockServer server, MockDb db) {
    if (!db.hasTable(drinksTable)) db.lazyTable(drinksTable, () => drinks);
    if (!db.hasTable(settingsTable)) {
      db.lazyTable(settingsTable, settingsRows);
    }
    if (!db.hasTable(ordersTable)) db.lazyTable(ordersTable, () => orders);

    /// The branch every staff-pool read names: known, held, reachable.
    String branchOf(MockRequest req) {
      final id = req.q('branch_id');
      if (id == null) {
        req.badRequest('Query deserialize error: missing field `branch_id`');
      }
      if (_Uuid.tryParse(id) == null) {
        req.badRequest('Query deserialize error: UUID parsing failed');
      }
      _requireKnownBranch(req, id);
      req.requireCap(_Caps.ordersStaffDrinkRecord, branchId: id);
      return id;
    }

    ({String from, String to}) rangeOf(MockRequest req) {
      final today = StaffPoolMock.today(req.now);
      final from = _dateParam(req, 'from') ?? today;
      final to = _dateParam(req, 'to') ?? today;
      if (to.compareTo(from) < 0) {
        req.badRequest('The end of the range comes before its start');
      }
      return (from: from, to: to);
    }

    server.on('GET', '/staff-pool/today', (req) {
      final branchId = branchOf(req);
      final day = _dateParam(req, 'business_date') ?? today(req.now);
      final s = effectiveSettings(db, SeedIds.sabahOrg, branchId);
      final eligible = [
        for (final e in (s['eligible_item_ids'] as List? ?? const [])) '$e',
      ];
      var used = 0;
      for (final d in db[drinksTable].rows) {
        if (d['branch_id'] == branchId && d['business_date'] == day) {
          used += (d['quantity'] as num? ?? 0).toInt();
        }
      }
      final state = poolState(
        (s['daily_allowance'] as num? ?? 0).toInt(),
        used,
      );
      return MockResponse.ok({
        'branch_id': branchId,
        'business_date': day,
        // The engine's "on": the switch AND something to spend on.
        'enabled': s['enabled'] == true && eligible.isNotEmpty,
        ...state,
        'eligible_item_ids': eligible,
      });
    });

    server.on('GET', '/staff-pool/drinks', (req) {
      final branchId = branchOf(req);
      final r = rangeOf(req);
      return MockResponse.ok(
        drinksIn(
          db,
          branchId,
          r.from,
          r.to,
          overspentOnly: req.qBool('overspent_only') ?? false,
        ),
      );
    });

    server.on('GET', '/staff-pool/drinks/summary', (req) {
      final branchId = branchOf(req);
      final r = rangeOf(req);
      return MockResponse.ok(
        summarize(
          drinksIn(
            db,
            branchId,
            r.from,
            r.to,
            overspentOnly: req.qBool('overspent_only') ?? false,
          ),
        ),
      );
    });

    // The sale a drink was rung on, for the "View order" sheet. The orders
    // area answers this route in the app; here it falls back to the core
    // seed's orders.
    _onIfAbsent(server, 'GET', '/orders/{order_id}', (req) {
      req.requireCap(_Caps.ordersRead);
      final id = req.param('order_id');
      final mine = db[ordersTable].find(id);
      if (mine != null) {
        req.requireBranch('${mine['branch_id']}');
        return MockResponse.ok(mine);
      }
      final seeded = MockSeed.instance.orderFull(id);
      if (seeded == null) req.notFound('Order not found');
      req.requireBranch(seeded.branchId);
      return MockResponse.ok(seeded.toJson());
    });
  }
}

/// Who a drink was for, in the teller's own words (`{name}` is a teller of
/// the branch). English and Arabic, as tellers write them.
const List<String> _notes = [
  '{name}, opening shift',
  '{name}, closing shift',
  '{name} — double shift',
  '{name} — بداية الشيفت',
  'The electrician, waiting on the fridge',
  'Courier from the roastery, waited for the sign-off',
  'Trainee barista — first day',
  'Manager on duty',
  'Cleaner, end of shift',
  "Owner's guest (milk supplier)",
  'Delivery rider waiting on a late order',
  'AC technician',
  'عامل النظافة — آخر الشيفت',
  'ضيف المدير',
  'الكاشير الجديد — تدريب',
  'مندوب توريد الألبان',
  'فني التكييف',
];

/// The day's drinks the seed fixes by hand: the morning of 2026-10-08 up to
/// "now" (10:00). Heliopolis's fifth drink went over its four.
const Map<String, List<(int, int, String, int, int?, String)>> _todays = {
  // (hour, minute, item, size index, milk option (index in `milk`), note)
  'heliopolis': [
    (7, 40, 'americano', 0, null, 'Ali, opening shift'),
    (8, 5, 'latte', 0, 2, 'فريدة — بداية الشيفت'),
    (8, 30, 'cappuccino', 1, null, 'Rana (manager), stock count'),
    (9, 10, 'iced_latte', 0, null, 'The plumber fixing the sink'),
    (9, 45, 'americano', 0, null, 'Courier from the roastery'),
  ],
  'maadi': [
    (8, 0, 'green_tea', 0, null, 'Hana, opening shift'),
    (9, 30, 'v60', 0, null, 'Tarek, supplier meeting'),
  ],
  'zamalek': [
    (7, 35, 'americano', 0, null, 'Mariam, opening shift'),
    (8, 20, 'latte', 1, 3, 'يوسف — شيفت مزدوج'),
    (9, 15, 'mint_lemonade', 0, null, 'Laila (waiter), break'),
  ],
};

class _StaffHistory {
  _StaffHistory(this.drinks, this.orders);

  final List<MockRow> drinks;
  final List<MockRow> orders;

  static final DateTime _first = DateTime.utc(2026, 9, 1);
  static const String _lastDay = '2026-10-08';

  static _StaffHistory build() {
    final drinks = <MockRow>[];
    final orders = <MockRow>[];
    final names = {for (final p in sabahStaff) p.key: p.name};
    final milk = seedGroups.firstWhere((g) => g.key == 'milk');
    const itemWeights = [5, 4, 4, 3, 2, 2, 2, 1];

    for (final b in StaffPoolMock._branches) {
      final branch = _branch(b.key);
      final branchId = MockSeed.branchIdOf(b.key);
      final tellers = branchTellers[b.key]!;
      final rng = MockRandom('staff-drinks:${b.key}');
      for (var day = _first; ; day = day.add(const Duration(days: 1))) {
        final ymd = _ymdOf(day);
        if (ymd.compareTo(_lastDay) > 0) break;
        if (b.lastDay != null && ymd.compareTo(b.lastDay!) > 0) continue;

        // (minute of day, item key, size, quantity, milk option, note)
        final plan = <(int, String, int, int, int?, String)>[];
        if (ymd == _lastDay) {
          for (final (h, m, item, size, milkPick, note)
              in _todays[b.key] ??
                  const <(int, int, String, int, int?, String)>[]) {
            plan.add((h * 60 + m, item, size, 1, milkPick, note));
          }
        } else {
          var n = b.allowance - 1 + rng.nextInt(3);
          if (rng.chance(0.18)) n += 1 + rng.nextInt(2);
          final minutes = [
            for (var k = 0; k < n; k++) 7 * 60 + 20 + rng.nextInt(15 * 60),
          ]..sort();
          for (final minute in minutes) {
            final key = rng.weighted(StaffPoolMock.eligibleKeys, itemWeights);
            final item = _item(key);
            final size = item.sizes.length > 1 && rng.chance(0.2) ? 1 : 0;
            final qty = rng.chance(0.06) ? 2 : 1;
            int? milkPick;
            if (item.groups.contains('milk') && rng.chance(0.15)) {
              milkPick = rng.chance(0.7) ? 2 : 3; // oat, else almond
            }
            final teller = names[tellers[minute < 15 * 60 ? 0 : 1]]!;
            final note = rng
                .pick(_notes)
                .replaceAll('{name}', teller.split(' ').first);
            plan.add((minute, key, size, qty, milkPick, note));
          }
        }

        var used = 0;
        for (final (k, (minute, key, size, qty, milkPick, note))
            in plan.indexed) {
          final item = _item(key);
          final id = mockUuid('staff-drink:${b.key}:$ymd:$k');
          final at = MockClock.fromCairo(
            day.year,
            day.month,
            day.day,
            minute ~/ 60,
            minute % 60,
            (k * 7) % 60,
          );
          final tellerKey = tellers[minute < 15 * 60 ? 0 : 1];
          final overspent = used + 1 > b.allowance;
          final priced =
              !(b.key == 'maadi' &&
                  ymd.compareTo(StaffPoolMock.maadiPricedFrom) < 0);

          final base = item.sizes.first.$2 * 100;
          final unit = item.sizes[size].$2 * 100;
          final milkOption = milkPick == null ? null : milk.options[milkPick];
          final addonUnit = (milkOption?.egp ?? 0) * 100;
          final comp = base * qty;
          final extras = (unit - base) * qty + addonUnit * qty;
          final unitCost = _unitCost(item, size);
          final cost = unitCost == null ? null : unitCost * qty;

          int? reported;
          var replay = false;
          if (priced && ymd != _lastDay) {
            // An offline tablet sends its own comp; it rarely disagrees.
            if (rng.chance(0.2)) {
              reported = rng.chance(0.15)
                  ? comp + (item.sizes.length > 1 ? 2000 : 1000) * qty
                  : comp;
            }
            replay = overspent && rng.chance(0.3);
          }
          final orderId = priced ? mockUuid('staff-drink-order:$id') : null;

          drinks.add({
            'id': id,
            'branch_id': branchId,
            'order_id': orderId,
            'menu_item_id': MockSeed.menuItemId(key),
            'item_name': item.name,
            'size_label': _lineSize(item, size),
            'quantity': qty,
            'note': note,
            'business_date': ymd,
            'allowance_at_record': b.allowance,
            'used_before': used,
            'overspent': overspent,
            'overspent_on_replay': replay,
            'cost_minor': cost,
            'recorded_by': SeedIds.user(tellerKey),
            'recorded_at': at.toIso8601String(),
            'comp_minor': priced ? comp : null,
            'extras_minor': priced ? extras : null,
            'comp_minor_reported': reported,
          });
          if (orderId != null) {
            orders.add(
              _order(
                id: orderId,
                drinkId: id,
                branch: branch,
                ymd: ymd,
                seq: k + 1,
                at: at,
                tellerKey: tellerKey,
                tellerName: names[tellerKey]!,
                item: item,
                size: size,
                qty: qty,
                unit: unit,
                comp: comp,
                milkOption: milkOption,
                cost: cost,
                cardPaid: rng.chance(0.4),
              ),
            );
          }
          used += qty;
        }
      }
    }
    return _StaffHistory(drinks, orders);
  }

  /// The sale a priced staff drink was rung on: one line, its normal price,
  /// the comp off it, the extras charged (`OrderFull` JSON).
  static MockRow _order({
    required String id,
    required String drinkId,
    required SeedBranch branch,
    required String ymd,
    required int seq,
    required DateTime at,
    required String tellerKey,
    required String tellerName,
    required SeedItem item,
    required int size,
    required int qty,
    required int unit,
    required int comp,
    required SeedOption? milkOption,
    required int? cost,
    required bool cardPaid,
  }) {
    final lineId = mockUuid('order-item:$id:0');
    final addons = <MockRow>[
      if (milkOption != null)
        {
          'id': mockUuid('order-item-addon:$lineId:milk'),
          'order_item_id': lineId,
          'addon_item_id': MockSeed.addonItemId('milk', milkOption.key),
          'addon_name': milkOption.name,
          'name_translations': {'en': milkOption.name, 'ar': milkOption.ar},
          'quantity': qty,
          'unit_price': milkOption.egp * 100,
          'line_total': milkOption.egp * 100 * qty,
          'staff_comp_minor': 0,
        },
    ];
    final lineTotal = unit * qty - comp;
    final charged =
        lineTotal +
        addons.fold<int>(0, (s, a) => s + (a['line_total']! as int));
    final method = charged == 0 || !cardPaid ? 'cash' : 'card';
    final number = 500 + seq;
    final shift = MockClock.wall(at).hour < 15 ? 'morning' : 'evening';
    final till = MockSeed.tillId(branch.key, ymd, shift);
    return {
      'id': id,
      'branch_id': MockSeed.branchIdOf(branch.key),
      'till_id': till,
      'shift_id': till,
      'teller_id': SeedIds.user(tellerKey),
      'teller_name': tellerName,
      'device_code': 'T1',
      'display_number': 'T1-$number',
      'order_number': number,
      'order_ref':
          '${branch.code}-${ymd.substring(2).replaceAll('-', '')}-T1-S${_two(seq)}',
      'status': 'completed',
      'order_type': 'takeaway',
      'delivery_fee': 0,
      'payment_method': method,
      'payment_legs': [
        if (charged > 0)
          {'method': method, 'amount': charged, 'is_cash': method == 'cash'},
      ],
      'subtotal': charged,
      'discount_amount': 0,
      'discount_value': 0,
      'tax_amount': (charged * 14 / 114).round(),
      'tax_inclusive': true,
      'tax_rate_applied': MockSeed.taxRate,
      'total_amount': charged,
      'timezone': MockClock.timezone,
      'verification': 'server',
      'created_at': at.toIso8601String(),
      'items': [
        {
          'id': lineId,
          'order_id': id,
          'menu_item_id': MockSeed.menuItemId(item.key),
          'item_name': item.name,
          'name_translations': {'en': item.name, 'ar': item.ar},
          'size_label': _lineSize(item, size),
          'quantity': qty,
          'unit_price': unit,
          'line_total': lineTotal,
          'line_cost': cost,
          'cost_missing': cost == null,
          'staff_comp_minor': comp,
          'staff_drink_id': drinkId,
          'deductions_snapshot': const <Object?>[],
          'addons': addons,
          'optionals': const <Object?>[],
        },
      ],
    };
  }
}

// ── Bundles ───────────────────────────────────────────────────────────────

/// A choice a slot (or a deal's pool) offers: an item at a size, with the
/// extra it brings in and how often customers pick it.
class _Choice {
  const _Choice(
    this.item, {
    this.size = 0,
    this.surcharge = 0,
    this.weight = 1,
  });
  final String item;
  final int size;
  final int surcharge;
  final int weight;
}

class _Slot {
  const _Slot(this.key, this.name, this.ar, this.choices, {this.picks = 1});
  final String key;
  final String name;
  final String ar;
  final List<_Choice> choices;

  /// How many units of the slot one combo holds (Brunch for Two: 2).
  final int picks;
}

/// When a bundle sells: every branch but [notAt] (or only [onlyAt]) on
/// [weekdays] (Dart's, Monday = 1), between [min] and [max] a day at an
/// average branch.
class _Selling {
  const _Selling(this.min, this.max, {this.weekdays, this.onlyAt, this.notAt});
  final int min;
  final int max;
  final Set<int>? weekdays;
  final String? onlyAt;
  final String? notAt;

  bool on(String branchKey, int weekday) =>
      (onlyAt == null || onlyAt == branchKey) &&
      notAt != branchKey &&
      (weekdays == null || weekdays!.contains(weekday));
}

class _Combo {
  const _Combo(
    this.key,
    this.name,
    this.ar,
    this.price,
    this.slots,
    this.selling,
  );
  final String key;
  final String name;
  final String ar;
  final int price;
  final List<_Slot> slots;
  final _Selling? selling;
}

/// A deal: [qty] units from [pool]; [rewardQty] from [reward] at
/// [rewardPercent] off (buy-get), or the lot for [price] (n-for-price).
class _Deal {
  const _Deal(
    this.key,
    this.name,
    this.ar,
    this.pool,
    this.selling, {
    this.qty = 2,
    this.price,
    this.reward = const [],
    this.rewardQty = 0,
    this.rewardPercent = 0,
  });
  final String key;
  final String name;
  final String ar;
  final List<_Choice> pool;
  final _Selling? selling;
  final int qty;
  final int? price;
  final List<_Choice> reward;
  final int rewardQty;
  final int rewardPercent;
}

const Set<int> _weekend = {DateTime.friday, DateTime.saturday};
const Set<int> _weekdaysMonFri = {
  DateTime.monday,
  DateTime.tuesday,
  DateTime.wednesday,
  DateTime.thursday,
  DateTime.friday,
};

const List<_Choice> _hotCoffee = [
  _Choice('americano', weight: 3),
  _Choice('americano', size: 1, surcharge: 1500),
  _Choice('cappuccino', weight: 4),
  _Choice('cappuccino', size: 1, surcharge: 1500, weight: 2),
  _Choice('latte', weight: 5),
  _Choice('latte', size: 1, surcharge: 1500, weight: 2),
  _Choice('spanish', weight: 3),
  _Choice('flatwhite', weight: 2),
  _Choice('cortado'),
];

/// Sabah's combos (the offers area's seed: same keys, names and prices).
/// The Ramadan Suhoor Box is switched off, so it sells nothing.
const List<_Combo> _combos = [
  _Combo(
    'morning-croissant',
    'Morning Croissant Combo',
    'كومبو كرواسون الصباح',
    16500,
    [
      _Slot('pastry', 'Pastry', 'مخبوزات', [
        _Choice('croissant', weight: 6),
        _Choice('almond_croissant', surcharge: 2000, weight: 2),
        _Choice('pain_choc', surcharge: 1500, weight: 3),
      ]),
      _Slot('coffee', 'Coffee', 'قهوة', _hotCoffee),
    ],
    _Selling(4, 9),
  ),
  _Combo('coffee-cookie', 'Coffee & Cookie', 'قهوة وكوكيز', 12000, [
    _Slot('coffee', 'Coffee', 'قهوة', [_Choice('americano')]),
    _Slot('cookie', 'Cookie', 'كوكيز', [_Choice('cookie')]),
  ], _Selling(2, 6)),
  _Combo('brunch-for-two', 'Brunch for Two', 'برانش لشخصين', 52000, [
    _Slot('mains', 'Mains', 'أطباق رئيسية', [
      _Choice('halloumi', weight: 4),
      _Choice('turkey_croissant', weight: 3),
      _Choice('avocado', weight: 3),
      _Choice('shakshuka', weight: 2),
    ], picks: 2),
    _Slot('drinks', 'Drinks', 'مشروبات', [
      _Choice('cappuccino', weight: 3),
      _Choice('latte', weight: 3),
      _Choice('americano', weight: 2),
      _Choice('orange', weight: 2),
      _Choice('mango', weight: 2),
    ], picks: 2),
  ], _Selling(2, 5, weekdays: _weekend, onlyAt: 'zamalek')),
  _Combo('iced-afternoon', 'Iced Afternoon', 'عصرية مثلجة', 23000, [
    _Slot('iced', 'Iced coffee', 'قهوة مثلجة', [
      _Choice('iced_latte', weight: 5),
      _Choice('iced_spanish', weight: 4),
      _Choice('iced_americano', weight: 2),
      _Choice('cold_brew', weight: 2),
      _Choice('iced_mocha', weight: 2),
    ]),
    _Slot('sweet', 'Something sweet', 'شيء حلو', [
      _Choice('fudge', weight: 4),
      _Choice('cheesecake', surcharge: 1500, weight: 3),
      _Choice('lemon_tart', weight: 2),
    ]),
  ], _Selling(2, 6)),
  _Combo('suhoor-box', 'Ramadan Suhoor Box', 'صندوق السحور', 27000, [], null),
  _Combo('kids-cocoa', "Kids' Cocoa & Cookie", 'كاكاو وكوكيز للأطفال', 15000, [
    _Slot('cocoa', 'Hot chocolate', 'شوكولاتة ساخنة', [_Choice('hot_choc')]),
    _Slot('cookie', 'Cookie', 'كوكيز', [_Choice('cookie')]),
  ], _Selling(1, 4, weekdays: _weekend)),
];

/// Sabah's deals (the offers area's seed). The juice trio ran in the summer
/// only; the free cookie is off at Zamalek.
const List<_Deal> _deals = [
  _Deal(
    'pastry-pair',
    'Any 2 pastries for 150',
    'أي قطعتين مخبوزات بـ 150',
    [
      _Choice('croissant', weight: 3),
      _Choice('almond_croissant', weight: 3),
      _Choice('pain_choc', weight: 3),
      _Choice('cinnamon', weight: 2),
    ],
    _Selling(2, 6),
    price: 15000,
  ),
  _Deal(
    'coffee-cookie-free',
    'Buy 2 coffees, get a cookie free',
    'اشترِ قهوتين واحصل على كوكيز مجانًا',
    _hotCoffee,
    _Selling(1, 4, notAt: 'zamalek'),
    reward: [_Choice('cookie')],
    rewardQty: 1,
    rewardPercent: 100,
  ),
  _Deal(
    'iced-latte-half',
    'Second iced latte half price',
    'اللاتيه المثلج الثاني بنصف السعر',
    [_Choice('iced_latte', size: 1)],
    _Selling(1, 4, weekdays: _weekdaysMonFri),
    qty: 1,
    reward: [_Choice('iced_latte', size: 1)],
    rewardQty: 1,
    rewardPercent: 50,
  ),
  _Deal(
    'juice-trio',
    'Juice trio for 270',
    'ثلاثة عصائر بـ 270',
    [],
    null,
    qty: 3,
    price: 27000,
  ),
  _Deal(
    'weekend-breakfast',
    'Weekend breakfast pair for 330',
    'فطور نهاية الأسبوع لشخصين بـ 330',
    [
      _Choice('halloumi', weight: 4),
      _Choice('turkey_croissant', weight: 3),
      _Choice('avocado', weight: 3),
      _Choice('shakshuka', weight: 2),
    ],
    _Selling(1, 4, weekdays: _weekend),
    price: 33000,
  ),
];

/// The combos and deals report's data and handlers.
abstract final class BundlesMock {
  /// One row per combo or deal sold (`reports_bundle_sales`).
  static const String salesTable = 'reports_bundle_sales';

  /// The offers area's ids.
  static String comboId(String key) => mockUuid('combo:$key');
  static String dealId(String key) => mockUuid('deal:$key');
  static String slotId(String combo, String slot) =>
      mockUuid('combo-slot:$combo:$slot');

  static List<String> get comboKeys => [for (final c in _combos) c.key];
  static List<String> get dealKeys => [for (final d in _deals) d.key];

  /// Every sale of the seed (see [salesTable]).
  static List<MockRow> get sales => _sales;

  static final List<MockRow> _sales = _buildSales();

  static List<MockRow> _buildSales() {
    final out = <MockRow>[];
    final first = DateTime.utc(2026, 9, 1);
    const lastDay = '2026-10-08';
    for (final b in seedBranches) {
      final branchId = MockSeed.branchIdOf(b.key);
      final scale = branchScale(branchId);
      final rng = MockRandom('bundle-sales:${b.key}');
      for (var day = first; ; day = day.add(const Duration(days: 1))) {
        final ymd = _ymdOf(day);
        if (ymd.compareTo(lastDay) > 0) break;
        // Today, up to 10:00, only the breakfast bundles have sold.
        final morning = ymd == lastDay;
        var orderSeq = 0;
        String? lastOrder;
        String nextOrder() {
          orderSeq++;
          return lastOrder = mockUuid('bundle-order:${b.key}:$ymd:$orderSeq');
        }

        for (final c in _combos) {
          final s = c.selling;
          if (s == null || !s.on(b.key, day.weekday)) continue;
          if (morning && c.key != 'morning-croissant') continue;
          var n = ((s.min + rng.nextInt(s.max - s.min + 1)) * scale).round();
          if (morning) n = (n / 3).ceil();
          for (var i = 0; i < n; i++) {
            final picks = <MockRow>[];
            for (final slot in c.slots) {
              for (var p = 0; p < slot.picks; p++) {
                final ch = rng.weighted(slot.choices, [
                  for (final x in slot.choices) x.weight,
                ]);
                picks.add({
                  'slot': slot.key,
                  'item': ch.item,
                  'size': ch.size,
                  'surcharge': ch.surcharge,
                });
              }
            }
            final orderId = lastOrder != null && rng.chance(0.12)
                ? lastOrder!
                : nextOrder();
            out.add(_comboSale(c, b.key, ymd, orderId, picks));
          }
        }
        if (morning) continue;
        for (final d in _deals) {
          final s = d.selling;
          if (s == null || !s.on(b.key, day.weekday)) continue;
          final n = ((s.min + rng.nextInt(s.max - s.min + 1)) * scale).round();
          for (var i = 0; i < n; i++) {
            final items = <_Choice>[
              for (var k = 0; k < d.qty; k++)
                rng.weighted(d.pool, [for (final x in d.pool) x.weight]),
            ];
            final rewards = <_Choice>[
              for (var k = 0; k < d.rewardQty; k++)
                rng.weighted(d.reward, [for (final x in d.reward) x.weight]),
            ];
            final orderId = lastOrder != null && rng.chance(0.08)
                ? lastOrder!
                : nextOrder();
            final sale = _dealSale(d, b.key, ymd, orderId, items, rewards);
            if (sale != null) out.add(sale);
          }
        }
      }
    }
    return out;
  }

  static int _price(_Choice c) => _item(c.item).sizes[c.size].$2 * 100;

  static MockRow _comboSale(
    _Combo c,
    String branchKey,
    String ymd,
    String orderId,
    List<MockRow> picks,
  ) {
    var list = 0;
    var surcharge = 0;
    var cost = 0;
    var costMissing = false;
    for (final p in picks) {
      final item = _item('${p['item']}');
      final size = p['size']! as int;
      list += item.sizes[size].$2 * 100;
      surcharge += p['surcharge']! as int;
      final unitCost = _unitCost(item, size);
      if (unitCost == null) {
        costMissing = true;
      } else {
        cost += unitCost;
      }
    }
    return {
      'kind': 'combo',
      'bundle_id': comboId(c.key),
      'bundle_key': c.key,
      'branch_id': MockSeed.branchIdOf(branchKey),
      'business_date': ymd,
      'order_id': orderId,
      'revenue': c.price + surcharge,
      'list_value': list + surcharge,
      'cost': cost,
      'cost_missing': costMissing,
      'picks': picks,
    };
  }

  /// A deal applied, or null when it would not have saved anything (the
  /// engine only applies a deal that does).
  static MockRow? _dealSale(
    _Deal d,
    String branchKey,
    String ymd,
    String orderId,
    List<_Choice> items,
    List<_Choice> rewards,
  ) {
    final all = [...items, ...rewards];
    final list = all.fold<int>(0, (s, c) => s + _price(c));
    final int revenue;
    if (d.price != null) {
      revenue = d.price!;
    } else {
      final off = rewards.fold<int>(
        0,
        (s, c) => s + (_price(c) * d.rewardPercent / 100).round(),
      );
      revenue = list - off;
    }
    if (revenue >= list) return null;
    var cost = 0;
    var costMissing = false;
    for (final c in all) {
      final unitCost = _unitCost(_item(c.item), c.size);
      if (unitCost == null) {
        costMissing = true;
      } else {
        cost += unitCost;
      }
    }
    return {
      'kind': 'deal',
      'bundle_id': dealId(d.key),
      'bundle_key': d.key,
      'branch_id': MockSeed.branchIdOf(branchKey),
      'business_date': ymd,
      'order_id': orderId,
      'revenue': revenue,
      'list_value': list,
      'cost': cost,
      'cost_missing': costMissing,
      'picks': const <MockRow>[],
    };
  }

  /// `(revenue − cost) / revenue` to four places, half away from zero; null
  /// with no revenue.
  static String? margin(int revenue, int cost) {
    if (revenue == 0) return null;
    final m = (revenue - cost) / revenue;
    final scaled = (m.abs() * 10000).round() * (m < 0 ? -1 : 1);
    return (scaled / 10000).toStringAsFixed(4);
  }

  /// The branches a Bundles read covers: the named one (it must be held), or
  /// every Sabah branch the persona reads.
  static List<String> branchesOf(MockRequest req, String? branchId) {
    if (branchId == null || branchId == allBranchesId) {
      return [
        for (final b in SeedIds.sabahBranches)
          if (req.persona.seesBranch(b)) b,
      ];
    }
    _requireKnownBranch(req, branchId);
    req.requireBranch(branchId);
    return [branchId];
  }

  /// The report body (`BundlesReport` JSON) over [rows].
  static MockRow report({
    required Iterable<MockRow> sales,
    required String from,
    required String to,
    required List<String> branches,
    String? kind,
  }) {
    final names = <String, (String, String)>{
      for (final c in _combos) comboId(c.key): (c.name, c.ar),
      for (final d in _deals) dealId(d.key): (d.name, d.ar),
    };
    final rows = <MockRow>[];
    for (final k in ['combo', 'deal']) {
      if (kind != null && kind != k) continue;
      final groups = <String, List<MockRow>>{};
      for (final s in sales) {
        if (s['kind'] != k) continue;
        if (!branches.contains(s['branch_id'])) continue;
        final day = '${s['business_date']}';
        if (day.compareTo(from) < 0 || day.compareTo(to) > 0) continue;
        (groups['${s['bundle_id']}'] ??= []).add(s);
      }
      final part = <MockRow>[];
      for (final e in groups.entries) {
        final ss = e.value;
        int sum(String f) => ss.fold<int>(0, (a, s) => a + (s[f]! as int));
        final revenue = sum('revenue');
        final list = sum('list_value');
        final cost = sum('cost');
        final (name, ar) = names[e.key] ?? ('${ss.first['bundle_key']}', '');
        part.add({
          'kind': k,
          'id': e.key,
          'name': name,
          'name_translations': {'en': name, 'ar': ar},
          'sold': ss.length,
          'orders': {for (final s in ss) s['order_id']}.length,
          'revenue': revenue,
          'list_value': list,
          'saving': list - revenue,
          'cost': cost,
          'cost_missing': ss.any((s) => s['cost_missing'] == true),
          'margin': margin(revenue, cost),
        });
      }
      part.sort((a, b) {
        final r = (b['revenue']! as int).compareTo(a['revenue']! as int);
        if (r != 0) return r;
        final n = '${a['name']}'.compareTo('${b['name']}');
        if (n != 0) return n;
        return '${a['id']}'.compareTo('${b['id']}');
      });
      rows.addAll(part);
    }
    int total(String f) => rows.fold<int>(0, (a, r) => a + (r[f]! as int));
    return {
      'from': from,
      'to': to,
      'rows': rows,
      'totals': {
        'sold': total('sold'),
        'revenue': total('revenue'),
        'list_value': total('list_value'),
        'saving': total('saving'),
        'cost': total('cost'),
      },
    };
  }

  /// The combo [key]'s mix (`ComboMix` JSON) over [sales].
  static MockRow mix({
    required Iterable<MockRow> sales,
    required String key,
    required String from,
    required String to,
    required List<String> branches,
  }) {
    final combo = _combos.firstWhere((c) => c.key == key);
    final id = comboId(key);
    final slots = <MockRow>[];
    for (final slot in combo.slots) {
      final counts = <(String, int), (int, int)>{};
      for (final s in sales) {
        if (s['kind'] != 'combo' || s['bundle_id'] != id) continue;
        if (!branches.contains(s['branch_id'])) continue;
        final day = '${s['business_date']}';
        if (day.compareTo(from) < 0 || day.compareTo(to) > 0) continue;
        for (final p in (s['picks']! as List).cast<MockRow>()) {
          if (p['slot'] != slot.key) continue;
          final k = ('${p['item']}', p['size']! as int);
          final (n, extra) = counts[k] ?? (0, 0);
          counts[k] = (n + 1, extra + (p['surcharge']! as int));
        }
      }
      if (counts.isEmpty) continue;
      slots.add({
        'slot_id': slotId(key, slot.key),
        'name': slot.name,
        'name_translations': {'en': slot.name, 'ar': slot.ar},
        'picks': [
          for (final e in counts.entries)
            () {
              final item = _item(e.key.$1);
              return {
                'menu_item_id': MockSeed.menuItemId(item.key),
                'name': item.name,
                'name_translations': {'en': item.name, 'ar': item.ar},
                'size_label': reportSizeLabel(item, e.key.$2),
                'count': e.value.$1,
                'surcharge_total': e.value.$2,
              };
            }(),
        ],
      });
    }
    return {'combo_id': id, 'from': from, 'to': to, 'slots': slots};
  }

  static void register(MockServer server, MockDb db) {
    if (!db.hasTable(salesTable)) db.lazyTable(salesTable, () => sales);

    /// `scope()`: the capability, the dates, the branches.
    ({String from, String to, List<String> branches}) scopeOf(MockRequest req) {
      final branchId = req.q('branch_id');
      if (branchId != null && _Uuid.tryParse(branchId) == null) {
        req.badRequest('Query deserialize error: UUID parsing failed');
      }
      req.requireCap(_Caps.reportsBundles);
      final from = _dateParam(req, 'from', required: true)!;
      final to = _dateParam(req, 'to', required: true)!;
      if (to.compareTo(from) < 0) req.badRequest('`to` is before `from`');
      return (from: from, to: to, branches: branchesOf(req, branchId));
    }

    server.on('GET', '/reports/bundles', (req) {
      final kind = req.q('kind');
      final s = scopeOf(req);
      if (kind != null && kind != 'combo' && kind != 'deal') {
        req.badRequest('`kind` is `combo` or `deal`');
      }
      return MockResponse.ok(
        report(
          sales: db[salesTable].rows,
          from: s.from,
          to: s.to,
          branches: s.branches,
          kind: kind,
        ),
      );
    });

    server.on('GET', '/reports/bundles/combos/{id}/mix', (req) {
      final s = scopeOf(req);
      final id = req.param('id');
      final combo = _combos.where((c) => comboId(c.key) == id).firstOrNull;
      if (combo == null) req.notFound('Combo not found');
      return MockResponse.ok(
        mix(
          sales: db[salesTable].rows,
          key: combo.key,
          from: s.from,
          to: s.to,
          branches: s.branches,
        ),
      );
    });
  }
}

/// A UUID's shape, as actix's `Uuid` extractor checks it.
abstract final class _Uuid {
  static final RegExp _re = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static String? tryParse(String s) => _re.hasMatch(s) ? s : null;
}

/// The capability keys these handlers check.
abstract final class _Caps {
  static const String ordersStaffDrinkRecord = 'orders.staff_drink.record';
  static const String ordersRead = 'orders.read';
  static const String reportsBundles = 'reports.bundles';
}
