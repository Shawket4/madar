/// The customers unit's mock backend: `/customers` and the customer sheet:
/// GET/POST /customers, GET/PATCH /customers/{id}, POST /customers/{id}/merge
/// and /erase, GET /customers/{id}/addresses and /bookings,
/// GET /loyalty/settings, GET/DELETE /loyalty/members/{id}, POST
/// /loyalty/adjust, GET /loyalty/members/{id}/google-object, POST
/// /loyalty/members/{id}/google-refresh, and GET /orders/{order_id} when the
/// orders unit has not answered it (the order sheet a customer's order
/// opens).
///
/// Handlers behave like the backend (`MadarRust src/customers/handlers.rs`,
/// `src/loyalty/{handlers,model}.rs`): the capability refusals as a 403
/// envelope WITHOUT a code (SELL-ALL-017), the 400/404/409 refusals with the
/// backend's sentences and codes (`CUSTOMER_PHONE_EXISTS`,
/// `CUSTOMER_MERGE_MEMBER_SURVIVES`), `limit`/`offset` windows, the
/// merge chain (a merged id resolves to the customer kept), the export
/// throttle (`EXPORT_RATE_LIMITED`, SELL-ALL-018), and state (a write shows
/// in the next read).
///
/// Shared records: the core seed's `customers` (normalised here to the
/// backend's vocabulary), `orders` and `branches`, the area seed's
/// `bookings`, and `loyalty_settings` (the same rows the setup area seeds;
/// whichever area seeds first wins). The loyalty routes are registered only
/// when no other unit answers them, so the setup area's loyalty admin and
/// this sheet share one implementation over the same tables.
library;

import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';
import '../shared/phone.dart';

/// The tables this unit reads and writes.
abstract final class CustomerTables {
  /// [Customer] rows (the core seed's), live customers only.
  static const String customers = 'customers';

  /// A customer merged away: its last row, plus `merged_into` / `merged_at`.
  static const String merged = 'customers_merged';

  /// `{id}` of every erased customer.
  static const String erased = 'customers_erased';

  /// [CustomerAddress] rows.
  static const String addresses = 'customer_addresses';

  /// [LedgerEntry] rows, plus `customer_id` (stripped when answered).
  static const String ledger = 'loyalty_ledger';

  /// One row per membership: `{id, enrolled_at, left_at?}`.
  static const String members = 'loyalty_members';

  /// [LoyaltySettings] rows (no `id`): the org's (`branch_id` null) and a
  /// branch's own.
  static const String loyaltySettings = 'loyalty_settings';

  /// Export reads, per person (`{id, user, at}`), for the throttle.
  static const String exportHits = 'export_hits';
}

/// The backend's per-person export budget (`MADAR_EXPORT_MAX_PER_MINUTE`).
const int mockExportsPerMinute = 10;

void registerCustomersMocks(MockServer server, MockDb db) {
  loadCustomersSeed(db);
  final h = _Handlers(db);

  server
    ..on('GET', '/customers', h.list)
    ..on('POST', '/customers', h.create)
    ..on('GET', '/customers/{id}', h.get)
    ..on('PATCH', '/customers/{id}', h.update)
    ..on('POST', '/customers/{id}/merge', h.merge)
    ..on('POST', '/customers/{id}/erase', h.erase)
    ..on('GET', '/customers/{id}/addresses', h.addresses)
    ..on('GET', '/customers/{id}/bookings', h.bookings);

  void onIfAbsent(String method, String template, MockHandler handler) {
    if (!server.handles(method, template)) server.on(method, template, handler);
  }

  onIfAbsent('GET', '/loyalty/settings', h.settings);
  onIfAbsent('GET', '/loyalty/members/{id}', h.member);
  onIfAbsent('DELETE', '/loyalty/members/{id}', h.leave);
  onIfAbsent('POST', '/loyalty/adjust', h.adjust);
  onIfAbsent('GET', '/loyalty/members/{id}/google-object', h.googleObject);
  onIfAbsent('POST', '/loyalty/members/{id}/google-refresh', h.googleRefresh);
  onIfAbsent('GET', '/orders/{order_id}', h.order);
}

// ── Seed ─────────────────────────────────────────────────────────────────

/// Brings the core seed's customers to the backend's vocabulary and adds
/// this unit's own rows (addresses, the loyalty programme when no other area
/// seeded it, memberships, the ledger). Safe to call twice.
void loadCustomersSeed(MockDb db) {
  if (db.hasTable(CustomerTables.addresses)) return;
  loadSellSeed(db);
  final customers = db[CustomerTables.customers].rows;
  for (final (i, c) in customers.indexed) {
    // `order_now` is not a source the backend knows: those came online.
    if (c['source'] == 'order_now') c['source'] = 'online';
    // A sprinkle of every other source, so the filter has something to find.
    if (i > 0) {
      if (i % 23 == 3) c['source'] = 'booking';
      if (i % 29 == 4) c['source'] = 'table_qr';
      if (i % 31 == 6) c['source'] = 'aggregator';
      if (i % 41 == 8) c['source'] = 'dashboard';
    }
    // A membership shares the customer's id.
    c['loyalty_customer_id'] = c['is_member'] == true ? c['id'] : null;
  }
  if (!db.hasTable(CustomerTables.loyaltySettings)) {
    db.lazyTable(
      CustomerTables.loyaltySettings,
      () => [for (final s in _programme) s.toJson()],
    );
  }
  db.table(CustomerTables.merged);
  db.table(CustomerTables.erased);
  db.table(CustomerTables.exportHits);
  db.lazyTable(CustomerTables.members, () => _members(db));
  db.lazyTable(CustomerTables.ledger, () => _ledger(db));
  db.table(CustomerTables.addresses).insertAll(_addresses(db));
}

/// The org's stamp card (six stamps buy a drink) and Zamalek's own five —
/// the same programme the setup area seeds.
final List<LoyaltySettings> _programme = [
  LoyaltySettings(
    orgId: SeedIds.sabahOrg,
    enabled: true,
    programName: 'Sabah Stamps',
    programNameAr: 'طوابع صباح',
    mode: 'visits',
    earnPiastresPerPoint: 1000,
    earnOnDiscounted: true,
    earnIncludeTax: true,
    stampPerLineItem: false,
    defaultRewardCost: 6,
    rewardAnyItem: false,
    balanceCapEnabled: false,
    effectiveBalanceCap: 6,
    maxRewardsPerOrder: 1,
    requireOtp: true,
    birthdayEnabled: true,
    birthdayRewardAmount: 1,
    winbackEnabled: false,
    allowNegativeBalance: false,
    terms: 'One stamp per order. Six stamps buy any regular hot drink.',
    termsAr: 'طابع واحد لكل طلب. ستة طوابع تساوي أي مشروب ساخن بالحجم العادي.',
    geofencedBranches: 2,
  ),
  LoyaltySettings(
    orgId: SeedIds.sabahOrg,
    branchId: SeedIds.zamalek,
    enabled: true,
    programName: 'Sabah Stamps — Zamalek',
    programNameAr: 'طوابع صباح — الزمالك',
    mode: 'visits',
    earnPiastresPerPoint: 1000,
    earnOnDiscounted: true,
    earnIncludeTax: true,
    stampPerLineItem: false,
    defaultRewardCost: 5,
    rewardAnyItem: false,
    balanceCapEnabled: false,
    effectiveBalanceCap: 5,
    maxRewardsPerOrder: 1,
    requireOtp: false,
    birthdayEnabled: false,
    winbackEnabled: false,
    allowNegativeBalance: false,
    terms: 'One stamp per order. Five stamps buy any regular hot drink.',
    geofencedBranches: 2,
  ),
];

/// Saved delivery addresses: Nada Kamal has a labelled home and an
/// unlabelled in-mall drop; every ninth customer one or two more.
List<MockRow> _addresses(MockDb db) {
  final customers = db[CustomerTables.customers].rows;
  final out = <MockRow>[];
  final rng = MockRandom('sabah-customer-addresses');
  const streets = [
    ('12 El-Thawra St', 'Heliopolis', 'Next to Korba metro'),
    ('7 Road 9', 'Maadi', 'Behind the Sporting Club'),
    ('45 South 90th St', 'New Cairo', 'Building C, gate 2'),
    ('3 Brazil St', 'Zamalek', 'Opposite the embassy'),
  ];
  void add(
    MockRow c,
    int n, {
    String? label,
    required String channel,
    String? place,
    String? unit,
    String? floor,
    String? line,
    String? landmark,
    String? notes,
    required int uses,
    required int daysAgo,
    String? branchKey,
  }) {
    final created = MockSeed.now.subtract(Duration(days: daysAgo + 40));
    out.add(
      CustomerAddress(
        id: mockUuid('customer-address:${c['id']}:$n'),
        customerId: c['id']! as String,
        label: label,
        channel: channel,
        placeName: place,
        unitNumber: unit,
        floor: floor,
        addressLine: line,
        landmark: landmark,
        deliveryNotes: notes,
        useCount: uses,
        branchId: branchKey == null ? null : MockSeed.branchIdOf(branchKey),
        createdAt: created,
        lastUsedAt: MockSeed.now.subtract(Duration(days: daysAgo, hours: 3)),
      ).toJson(),
    );
  }

  final nada = customers.first;
  add(
    nada,
    0,
    label: 'Home',
    channel: 'outside',
    unit: '14',
    floor: '3',
    line: '12 El-Thawra St, Heliopolis',
    landmark: 'Next to Korba metro',
    notes: 'Ring twice, the bell is quiet.',
    uses: 9,
    daysAgo: 2,
    branchKey: 'heliopolis',
  );
  add(
    nada,
    1,
    channel: 'in_mall',
    place: 'City Stars, Phase 2',
    unit: 'Shop 214',
    floor: '2',
    uses: 3,
    daysAgo: 11,
    branchKey: 'heliopolis',
  );
  for (final (i, c) in customers.indexed) {
    if (i == 0 || i % 9 != 4) continue;
    final (line, area, landmark) = streets[rng.nextInt(streets.length)];
    add(
      c,
      0,
      label: rng.chance(0.5) ? 'Work' : null,
      channel: 'outside',
      unit: '${1 + rng.nextInt(30)}',
      floor: '${rng.nextInt(9)}',
      line: '$line, $area',
      landmark: landmark,
      uses: 1 + rng.nextInt(6),
      daysAgo: 1 + rng.nextInt(25),
    );
    if (rng.chance(0.3)) {
      add(
        c,
        1,
        channel: 'umbrella',
        place: 'Marassi, North Coast',
        landmark: 'Umbrella 42, row C',
        uses: 1,
        daysAgo: 60 + rng.nextInt(30),
      );
    }
  }
  return out;
}

/// One membership per member customer: enrolled a day after they were
/// first met.
List<MockRow> _members(MockDb db) => [
  for (final c in db[CustomerTables.customers].rows)
    if (c['is_member'] == true)
      {
        'id': c['id'],
        'enrolled_at': DateTime.parse(
          c['created_at']! as String,
        ).add(const Duration(days: 1)).toUtc().toIso8601String(),
      },
];

/// Each member's ledger, built so it sums to the customer's stamp balance: a
/// stamp per completed order (a voided order's stamp reversed), a reward
/// redeemed at every sixth, the paper card's stamps carried over at
/// enrolment, and for Nada Kamal a stamp added by hand.
List<MockRow> _ledger(MockDb db) {
  final members = {
    for (final m in db[CustomerTables.members].rows) m['id']! as String: m,
  };
  final byCustomer = <String, List<MockRow>>{};
  for (final o in db['orders'].rows) {
    final id = o['customer_id'];
    if (id is String && members.containsKey(id)) {
      (byCustomer[id] ??= []).add(o);
    }
  }
  final branchNames = {
    for (final b in db['branches'].rows) b['id']! as String: b['name'] as String?,
  };
  const cost = 6;
  final out = <MockRow>[];
  for (final c in db[CustomerTables.customers].rows) {
    final id = c['id']! as String;
    final m = members[id];
    if (m == null) continue;
    final balance = (c['visits_balance'] as num?)?.toInt() ?? 0;
    final orders = [...?byCustomer[id]]
      ..sort(
        (a, b) =>
            (a['created_at']! as String).compareTo(b['created_at']! as String),
      );
    final enrolled = DateTime.parse(m['enrolled_at']! as String);
    var n = 0;
    MockRow row({
      required String kind,
      required String source,
      required int points,
      required DateTime at,
      String? branchId,
      String? orderId,
      String? by,
      String? byName,
      String? note,
      String? reward,
      String? reverses,
      int? basis,
    }) {
      final rowId = mockUuid('ledger:$id:${n++}');
      final b = branchId ?? SeedIds.heliopolis;
      return {
        ...LedgerEntry(
          id: rowId,
          branchId: b,
          branchName: branchNames[b],
          createdAt: at,
          createdBy: by,
          createdByName: byName,
          currency: 'visits',
          kind: kind,
          source: source,
          points: points,
          orderId: orderId,
          note: note,
          rewardName: reward,
          reversesId: reverses,
          basisPiastres: basis,
        ).toJson(),
        'customer_id': id,
      };
    }

    final completed = [
      for (final o in orders)
        if (o['status'] == 'completed') o,
    ];
    final manual = c == db[CustomerTables.customers].rows.first ? 1 : 0;
    final earned = completed.length + manual;
    var redeems = earned > balance ? ((earned - balance) / cost).ceil() : 0;
    var carried = balance - (earned - cost * redeems);
    if (carried < 0) {
      redeems += 1;
      carried += cost;
    }
    final rows = <MockRow>[];
    if (carried > 0) {
      rows.add(
        row(
          kind: 'adjust',
          source: 'manual',
          points: carried,
          at: enrolled,
          by: SeedIds.owner,
          byName: 'Nour El-Sayed',
          note: 'Stamps carried over from the paper card',
        ),
      );
    }
    var running = carried;
    var done = 0;
    for (final o in orders) {
      final at = DateTime.parse(o['created_at']! as String);
      if (at.isBefore(enrolled)) continue;
      final earn = row(
        kind: 'earn',
        source: 'sale',
        points: 1,
        at: at,
        branchId: o['branch_id'] as String?,
        orderId: o['id'] as String?,
        by: o['teller_id'] as String?,
        byName: o['teller_name'] as String?,
        basis: (o['total_amount'] as num?)?.toInt(),
      );
      rows.add(earn);
      if (o['status'] != 'completed') {
        final voidAt = DateTime.tryParse('${o['voided_at']}') ?? at;
        rows.add(
          row(
            kind: 'reverse_earn',
            source: 'void',
            points: -1,
            at: voidAt,
            branchId: o['branch_id'] as String?,
            orderId: o['id'] as String?,
            by: o['voided_by'] as String?,
            reverses: earn['id']! as String,
          ),
        );
        continue;
      }
      running++;
      if (done < redeems && running >= cost) {
        running -= cost;
        done++;
        rows.add(
          row(
            kind: 'redeem',
            source: 'redemption',
            points: -cost,
            at: at.add(const Duration(minutes: 1)),
            branchId: o['branch_id'] as String?,
            orderId: o['id'] as String?,
            by: o['teller_id'] as String?,
            byName: o['teller_name'] as String?,
            reward: 'Any regular hot drink',
          ),
        );
      }
    }
    if (manual > 0) {
      rows.add(
        row(
          kind: 'adjust',
          source: 'manual',
          points: 1,
          at: MockSeed.now.subtract(const Duration(days: 3, hours: 2)),
          by: SeedIds.owner,
          byName: 'Nour El-Sayed',
          note: 'Stamp missed on 12 Sep order',
        ),
      );
      running++;
    }
    // Orders from before enrolment earned nothing: whatever the walk left
    // over the balance is settled by redemptions it could not place.
    while (running > balance && running - cost >= balance - cost) {
      if (running - cost < 0) break;
      running -= cost;
      rows.add(
        row(
          kind: 'redeem',
          source: 'redemption',
          points: -cost,
          at: MockSeed.now.subtract(const Duration(days: 1)),
          reward: 'Any regular hot drink',
        ),
      );
    }
    if (running != balance) {
      rows.add(
        row(
          kind: 'adjust',
          source: 'manual',
          points: balance - running,
          at: MockSeed.now.subtract(const Duration(days: 1, hours: 1)),
          by: SeedIds.owner,
          byName: 'Nour El-Sayed',
          note: 'Balance corrected after the till count',
        ),
      );
    }
    out.addAll(rows);
  }
  return out;
}

// ── Handlers ─────────────────────────────────────────────────────────────

final RegExp _nonDigit = RegExp(r'[^0-9]');

/// `search_digits`: the typed digits (Arabic ones read as Latin), without a
/// leading `00` or `0`; at least three.
String? _searchDigits(String raw) {
  final ascii = String.fromCharCodes(
    raw.runes.map(
      (r) => r >= 0x0660 && r <= 0x0669
          ? 0x30 + r - 0x0660
          : (r >= 0x06F0 && r <= 0x06F9 ? 0x30 + r - 0x06F0 : r),
    ),
  );
  var d = ascii.replaceAll(_nonDigit, '');
  if (d.startsWith('00')) {
    d = d.substring(2);
  } else if (d.startsWith('0')) {
    d = d.substring(1);
  }
  return d.length >= 3 ? d : null;
}

class _Handlers {
  _Handlers(this.db);

  final MockDb db;

  MockTable get _customers => db[CustomerTables.customers];

  // ── customers ──────────────────────────────────────────────────────────

  /// The org a request acts in (`org_of`): 403 without one.
  String _org(MockRequest req) {
    final org = req.orgId;
    if (org == null) {
      req.fail(MockResponse.forbidden('No organization selected'));
    }
    return org;
  }

  /// The live customer [id] of the request's org, else null.
  MockRow? _live(String id) => _customers.find(id);

  /// `customers_resolve`: a merged id answers for its survivor.
  String? _resolve(String id) {
    var cur = id;
    for (var i = 0; i < 16; i++) {
      if (_live(cur) != null) return cur;
      final m = db[CustomerTables.merged].find(cur);
      if (m == null) return null;
      cur = m['merged_into']! as String;
    }
    return null;
  }

  /// Every id merged into [id], [id] first (`chain_ids`).
  List<String> _chain(String id) {
    final out = [id];
    for (var i = 0; i < out.length; i++) {
      for (final m in db[CustomerTables.merged].rows) {
        if (m['merged_into'] == out[i]) out.add(m['id']! as String);
      }
    }
    return out;
  }

  Map<String, Object?> _public(MockRow c) => Customer.fromJson(c).toJson();

  MockResponse list(MockRequest req) {
    _org(req);
    req.requireCap('customers.view');
    if (req.headers['X-Madar-Export'] == '1' ||
        req.headers['x-madar-export'] == '1') {
      _throttleExport(req);
    }
    final text = req.q('q')?.trim();
    final digits = text == null || text.isEmpty ? null : _searchDigits(text);
    final source = req.q('source')?.trim();
    const known = [
      'pos',
      'online',
      'loyalty',
      'booking',
      'table_qr',
      'aggregator',
      'dashboard',
    ];
    if (source != null && source.isNotEmpty && !known.contains(source)) {
      req.badRequest('Unknown customer source `$source`');
    }
    final member = req.qBool('member');
    final limit = (req.qInt('limit') ?? 100).clamp(1, 500);
    final offset = (req.qInt('offset') ?? 0).clamp(0, 1 << 30);
    final needle = text?.toLowerCase();
    final rows = _customers.where((c) {
      if (needle != null && needle.isNotEmpty) {
        final byName = (c['name'] as String? ?? '').toLowerCase().contains(
          needle,
        );
        final key = canonicalPhone(c['phone'] as String?);
        final byPhone = digits != null && key != null && key.contains(digits);
        if (!byName && !byPhone) return false;
      }
      if (member != null && (c['is_member'] == true) != member) return false;
      if (source != null && source.isNotEmpty && c['source'] != source) {
        return false;
      }
      return true;
    });
    String lastSeen(MockRow c) =>
        (c['last_order_at'] ?? c['created_at'])! as String;
    rows.sort((a, b) {
      final byLast = DateTime.parse(
        lastSeen(b),
      ).compareTo(DateTime.parse(lastSeen(a)));
      return byLast != 0
          ? byLast
          : (a['id']! as String).compareTo(b['id']! as String);
    });
    final page = rows.skip(offset).take(limit);
    return MockResponse.ok([for (final c in page) _public(c)]);
  }

  /// Ten export reads a minute per person, then 429 `EXPORT_RATE_LIMITED`.
  void _throttleExport(MockRequest req) {
    final hits = db[CustomerTables.exportHits];
    final now = req.now;
    final recent = hits.where(
      (h) =>
          h['user'] == req.persona.userId &&
          now.difference(DateTime.parse(h['at']! as String)).inSeconds < 60,
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

  CustomerDetail _detail(String asked) {
    final id = _resolve(asked);
    if (id == null) {
      throw MockHttpError(MockResponse.notFound('Customer not found'));
    }
    final c = _live(id)!;
    final branches = {
      for (final b in db['branches'].rows) b['id']! as String: b['name'],
    };
    final orders =
        db['orders'].where((o) => o['customer_id'] == id)..sort(
          (a, b) => (b['created_at']! as String).compareTo(
            a['created_at']! as String,
          ),
        );
    final merged = [
      for (final m in db[CustomerTables.merged].rows)
        if (m['merged_into'] == id) m,
    ]..sort((a, b) => '${a['merged_at']}'.compareTo('${b['merged_at']}'));
    return CustomerDetail(
      customer: Customer.fromJson(c),
      resolvedFrom: asked == id ? null : asked,
      mergedFrom: [for (final m in merged) m['id']! as String],
      recentOrders: [
        for (final o in orders.take(50))
          CustomerOrder(
            id: o['id']! as String,
            orderRef: o['order_ref'] as String?,
            branchId: o['branch_id']! as String,
            branchName: branches[o['branch_id']] as String?,
            status: o['status']! as String,
            totalAmount: (o['total_amount']! as num).toInt(),
            createdAt: DateTime.parse(o['created_at']! as String),
          ),
      ],
    );
  }

  MockResponse get(MockRequest req) {
    _org(req);
    req.requireCap('customers.view');
    return MockResponse.ok(_detail(req.param('id')));
  }

  static String _cleanName(MockRequest req, Object? raw) {
    final n = (raw as String? ?? '').trim();
    if (n.isEmpty) req.badRequest('A customer needs a name');
    return n.length > 120 ? n.substring(0, 120) : n;
  }

  /// The phone as typed (kept without a key when it is not a phone); text
  /// with no digit in it is nothing.
  static String? _cleanPhone(Object? raw) {
    final p = (raw as String?)?.trim();
    if (p == null || p.replaceAll(_nonDigit, '').isEmpty) return null;
    return p.length > 40 ? p.substring(0, 40) : p;
  }

  static String? _cleanNotes(Object? raw) {
    final n = (raw as String?)?.trim();
    if (n == null || n.isEmpty) return null;
    return n.length > 2000 ? n.substring(0, 2000) : n;
  }

  /// 409 `CUSTOMER_PHONE_EXISTS` when another live customer has [phone]'s
  /// number.
  void _phoneFree(MockRequest req, String? phone, {String? except}) {
    final key = canonicalPhone(phone);
    if (key == null) return;
    final holder = _customers.firstWhere(
      (c) => c['id'] != except && canonicalPhone(c['phone'] as String?) == key,
    );
    if (holder != null) {
      req.fail(
        MockResponse.error(
          409,
          'A customer with this phone already exists (${holder['id']})',
          code: 'CUSTOMER_PHONE_EXISTS',
        ),
      );
    }
  }

  MockResponse create(MockRequest req) {
    _org(req);
    final body = req.json;
    final branchId = body['branch_id'] as String?;
    req.requireCap('customers.create', branchId: branchId);
    final name = _cleanName(req, body['name']);
    final phone = _cleanPhone(body['phone']);
    final notes = _cleanNotes(body['notes']);
    final source = body['source'] as String? ?? (branchId == null ? 'dashboard' : 'pos');
    final askedId = body['id'] as String?;
    if (askedId != null && _live(askedId) != null) {
      return MockResponse.ok(_detail(askedId));
    }
    _phoneFree(req, phone);
    final now = req.now;
    final row = _customers.insert(
      Customer(
        id: askedId ?? db.newId(CustomerTables.customers),
        name: name,
        phone: phone,
        notes: notes,
        source: source,
        isMember: false,
        ordersCount: 0,
        totalSpent: 0,
        createdAt: now,
        updatedAt: now,
      ).toJson(),
      timestamps: false,
    );
    return MockResponse.created(_detail(row['id']! as String));
  }

  MockResponse update(MockRequest req) {
    _org(req);
    req.requireCap('customers.edit');
    final id = req.param('id');
    final cur = _live(id) ?? req.notFound('Customer not found');
    final body = req.json;
    final name = body.containsKey('name') && body['name'] != null
        ? _cleanName(req, body['name'])
        : cur['name']! as String;
    final phone = body.containsKey('phone') && body['phone'] != null
        ? _cleanPhone(body['phone'])
        : cur['phone'] as String?;
    final notes = body.containsKey('notes') && body['notes'] != null
        ? _cleanNotes(body['notes'])
        : cur['notes'] as String?;
    final locale = switch (body['locale']) {
      final String l when l.startsWith('ar') => 'ar',
      final String _ => 'en',
      _ => cur['locale'],
    };
    if (cur['is_member'] == true && canonicalPhone(phone) == null) {
      req.badRequest('A loyalty member needs a valid phone number');
    }
    _phoneFree(req, phone, except: id);
    cur
      ..['name'] = name
      ..['phone'] = phone
      ..['notes'] = notes
      ..['locale'] = locale
      ..['updated_at'] = req.now.toIso8601String();
    if (body['marketing_opt_out'] is bool) {
      cur['marketing_opt_out'] = body['marketing_opt_out'];
    }
    return MockResponse.ok(_detail(id));
  }

  MockResponse merge(MockRequest req) {
    _org(req);
    req.requireCap('customers.merge');
    final fromId = req.param('id');
    final intoId = req.json['into'] as String?;
    if (intoId == null) {
      req.badRequest('Json deserialize error: missing field `into`');
    }
    if (fromId == intoId) {
      req.badRequest('A customer cannot be merged into itself');
    }
    final a = _live(fromId) ?? req.notFound('Customer not found');
    final b = _live(intoId) ?? req.notFound('Customer to keep not found');
    // The member side always survives: its id is printed in wallet passes.
    if (a['is_member'] == true && b['is_member'] != true) {
      req.fail(
        MockResponse.error(
          409,
          '${a['name']} is a loyalty member and must be the customer that '
          'stays; merge the other way ($intoId into $fromId)',
          code: 'CUSTOMER_MERGE_MEMBER_SURVIVES',
        ),
      );
    }
    final ledger = db[CustomerTables.ledger];
    final now = req.now;
    if (a['is_member'] == true && b['is_member'] == true) {
      // The loser's stamps move to the survivor, a ledger row on each side.
      ledger.rows;
      final moved = (a['visits_balance'] as num?)?.toInt() ?? 0;
      if (moved != 0) {
        for (final (who, pts, other) in [
          (fromId, -moved, intoId),
          (intoId, moved, fromId),
        ]) {
          ledger.insert({
            ...LedgerEntry(
              id: db.newId(CustomerTables.ledger),
              branchId: SeedIds.heliopolis,
              branchName: 'Heliopolis',
              createdAt: now,
              createdBy: req.persona.userId,
              createdByName: req.persona.displayName,
              currency: 'visits',
              kind: 'adjust',
              source: 'merge',
              points: pts,
              note: 'Merged with member $other',
            ).toJson(),
            'customer_id': who,
          }, timestamps: false);
        }
      }
      b['visits_balance'] = ((b['visits_balance'] as num?)?.toInt() ?? 0) + moved;
      db[CustomerTables.members].update(fromId, {
        'left_at': now.toIso8601String(),
      });
    }
    // The kept customer takes what it lacks; the orders move over.
    b['phone'] ??= a['phone'];
    b['notes'] ??= a['notes'];
    b['orders_count'] =
        ((b['orders_count'] as num?)?.toInt() ?? 0) +
        ((a['orders_count'] as num?)?.toInt() ?? 0);
    b['total_spent'] =
        ((b['total_spent'] as num?)?.toInt() ?? 0) +
        ((a['total_spent'] as num?)?.toInt() ?? 0);
    final lastA = a['last_order_at'] as String?;
    final lastB = b['last_order_at'] as String?;
    if (lastA != null && (lastB == null || lastA.compareTo(lastB) > 0)) {
      b['last_order_at'] = lastA;
    }
    b['updated_at'] = now.toIso8601String();
    for (final o in db['orders'].rows) {
      if (o['customer_id'] == fromId) o['customer_id'] = intoId;
    }
    db[CustomerTables.merged].put({
      ...a,
      'merged_into': intoId,
      'merged_at': now.toIso8601String(),
    });
    _customers.delete(fromId);
    return MockResponse.ok(_detail(intoId));
  }

  MockResponse erase(MockRequest req) {
    _org(req);
    req.requireCap('customers.erase');
    final id = req.param('id');
    if (_live(id) == null) req.notFound('Customer not found');
    for (final cid in _chain(id)) {
      _customers.delete(cid);
      db[CustomerTables.erased].put({'id': cid});
      db[CustomerTables.addresses].removeWhere((a) => a['customer_id'] == cid);
      db[CustomerTables.members].delete(cid);
      for (final o in db['orders'].rows) {
        if (o['customer_id'] == cid) o['customer_name'] = null;
      }
      for (final b in db[SellTables.bookings].rows) {
        if (b['customer_id'] == cid) {
          b['guest_name'] = '';
          b['guest_phone'] = '';
        }
      }
    }
    return MockResponse.empty();
  }

  MockResponse addresses(MockRequest req) {
    _org(req);
    req.requireCap('customers.addresses.view');
    final id = _resolve(req.param('id')) ?? req.notFound('Customer not found');
    final chain = _chain(id);
    final rows =
        db[CustomerTables.addresses].where(
          (a) => chain.contains(a['customer_id']),
        )..sort((a, b) {
          final c = (b['last_used_at']! as String).compareTo(
            a['last_used_at']! as String,
          );
          return c != 0
              ? c
              : (a['id']! as String).compareTo(b['id']! as String);
        });
    return MockResponse.ok(rows);
  }

  MockResponse bookings(MockRequest req) {
    _org(req);
    req.requireCap('customers.view');
    final id = _resolve(req.param('id')) ?? req.notFound('Customer not found');
    final chain = _chain(id);
    final limit = (req.qInt('limit') ?? 50).clamp(1, 200);
    final offset = (req.qInt('offset') ?? 0).clamp(0, 1 << 30);
    final rows = db[SellTables.bookings].where(
      (b) => chain.contains(b['customer_id']),
    )..sort((a, b) => (b['starts_at']! as String).compareTo(a['starts_at']! as String));
    return MockResponse.ok(rows.skip(offset).take(limit).toList());
  }

  // ── loyalty ────────────────────────────────────────────────────────────

  /// The programme in force at [branchId]: the branch's own, else the
  /// org's.
  MockRow _settingsRow(String org, String? branchId) {
    final rows = db[CustomerTables.loyaltySettings].rows;
    MockRow? own;
    if (branchId != null) {
      for (final r in rows) {
        if (r['org_id'] == org && r['branch_id'] == branchId) own = r;
      }
    }
    for (final r in rows) {
      if (own == null && r['org_id'] == org && r['branch_id'] == null) own = r;
    }
    return own ??
        LoyaltySettings(
          orgId: org,
          enabled: false,
          programName: 'Loyalty',
          mode: 'points',
          earnPiastresPerPoint: 1000,
          earnOnDiscounted: true,
          earnIncludeTax: true,
          defaultRewardCost: 100,
          requireOtp: true,
        ).toJson();
  }

  MockResponse settings(MockRequest req) {
    final org = _org(req);
    req.requireCap('loyalty.read');
    final branchId = req.q('branch_id');
    if (branchId != null) req.requireBranch(branchId);
    return MockResponse.ok(_settingsRow(org, branchId));
  }

  MemberView _view(MockRow c, String org, String? branchId) {
    final s = _settingsRow(org, branchId);
    final mode = s['mode'] == 'visits' ? 'visits' : 'points';
    final cost = (s['default_reward_cost'] as num?)?.toInt() ?? 1;
    final visits = (c['visits_balance'] as num?)?.toInt() ?? 0;
    final points = (c['points_balance'] as num?)?.toInt() ?? 0;
    final balance = mode == 'visits' ? visits : points;
    final id = c['id']! as String;
    final ledger = db[CustomerTables.ledger].where(
      (e) => e['customer_id'] == id,
    );
    var lifeVisits = 0;
    var lifePoints = 0;
    for (final e in ledger) {
      final kind = e['kind'];
      if (kind != 'earn' && kind != 'reverse_earn') continue;
      final p = (e['points']! as num).toInt();
      if (e['currency'] == 'visits') {
        lifeVisits += p;
      } else {
        lifePoints += p;
      }
    }
    final m = db[CustomerTables.members].find(id);
    final progress = cost <= 0 ? 0 : balance % cost;
    return MemberView(
      id: id,
      orgId: org,
      name: c['name']! as String,
      phone: c['phone'] as String? ?? '',
      locale: c['locale'] as String? ?? 'ar',
      mode: mode,
      balance: balance,
      pointsBalance: points,
      visitsBalance: visits,
      lifetimePoints: lifePoints,
      lifetimeVisits: lifeVisits,
      enrolledAt: DateTime.parse(
        (m?['enrolled_at'] ?? c['created_at'])! as String,
      ),
      nextRewardCost: cost,
      progressToNext: progress,
      pointsToNextReward: cost - progress,
      rewardsReady: cost <= 0 ? 0 : balance ~/ cost,
      canRedeem: balance >= cost,
    );
  }

  /// The member [id] (a live customer holding a card), else 404.
  MockRow _memberRow(MockRequest req, String id, {String what = 'Member not found'}) {
    final c = _live(id);
    if (c == null || c['is_member'] != true) req.notFound(what);
    return c;
  }

  MockResponse member(MockRequest req) {
    final org = _org(req);
    req.requireAnyCap(['loyalty.read', 'loyalty.members.list']);
    final branchId = req.q('branch_id');
    if (branchId != null) req.requireBranch(branchId);
    final c = _memberRow(req, req.param('id'));
    final id = c['id']! as String;
    final ledger =
        db[CustomerTables.ledger].where((e) => e['customer_id'] == id)..sort(
          (a, b) => (b['created_at']! as String).compareTo(
            a['created_at']! as String,
          ),
        );
    return MockResponse.ok(
      MemberDetail(
        member: _view(c, org, branchId),
        ledger: [for (final e in ledger.take(200)) LedgerEntry.fromJson(e)],
      ),
    );
  }

  MockResponse leave(MockRequest req) {
    _org(req);
    req.requireCap('loyalty.members.delete');
    final c = _live(req.param('id'));
    // A card already gone is not a failure.
    if (c == null || c['is_member'] != true) return MockResponse.empty();
    c
      ..['is_member'] = false
      ..['loyalty_customer_id'] = null
      ..['updated_at'] = req.now.toIso8601String();
    db[CustomerTables.members].update(c['id']! as String, {
      'left_at': req.now.toIso8601String(),
    });
    return MockResponse.empty();
  }

  MockResponse adjust(MockRequest req) {
    final org = _org(req);
    req.requireCap('loyalty.points.adjust');
    final body = req.json;
    final note = (body['note'] as String?)?.trim() ?? '';
    if (note.isEmpty) {
      req.badRequest('Say why the points are being adjusted (note)');
    }
    final branchId = body['branch_id'] as String?;
    final customerId = body['customer_id'] as String?;
    final points = (body['points'] as num?)?.toInt();
    if (branchId == null || customerId == null || points == null) {
      req.badRequest('Json deserialize error: missing field');
    }
    req.requireBranch(branchId);
    final c = _memberRow(req, customerId, what: 'No member for that card');
    if (points == 0) req.badRequest('An adjustment of zero points changes nothing');
    final s = _settingsRow(org, branchId);
    final mode = s['mode'] == 'visits' ? 'visits' : 'points';
    final field = mode == 'visits' ? 'visits_balance' : 'points_balance';
    final have = (c[field] as num?)?.toInt() ?? 0;
    if (have + points < 0) {
      req.badRequest('${c['name']} has $have; that adjustment would go negative');
    }
    final ledger = db[CustomerTables.ledger]..rows;
    final branch = db['branches'].find(branchId);
    ledger.insert({
      ...LedgerEntry(
        id: db.newId(CustomerTables.ledger),
        branchId: branchId,
        branchName: branch?['name'] as String?,
        createdAt: req.now,
        createdBy: req.persona.userId,
        createdByName: req.persona.displayName,
        currency: mode,
        kind: 'adjust',
        source: 'manual',
        points: points,
        note: note,
      ).toJson(),
      'customer_id': customerId,
    }, timestamps: false);
    c[field] = have + points;
    return MockResponse.ok(_view(c, org, branchId));
  }

  /// Branches the card is pinned to: the active branches with a location.
  int _expectedLocations(String org) => db['branches']
      .where(
        (b) =>
            b['org_id'] == org &&
            b['is_active'] == true &&
            b['latitude'] != null,
      )
      .length;

  Map<String, Object?> _googleObject(MockRow c, String org, int locations) {
    final branches = db['branches'].where(
      (b) => b['org_id'] == org && b['is_active'] == true,
    );
    return {
      'id': '3388000000022001234.member-${c['id']}',
      'classId': '3388000000022001234.sabah-coffee',
      'state': 'ACTIVE',
      'accountId': c['id'],
      'accountName': c['name'],
      'loyaltyPoints': {
        'label': 'Stamps',
        'balance': {'int': c['visits_balance'] ?? 0},
      },
      'barcode': {'type': 'QR_CODE', 'value': 'MDR-${c['id']}'},
      'locations': [
        for (final b in branches.take(locations))
          {'latitude': b['latitude'], 'longitude': b['longitude']},
      ],
    };
  }

  MockResponse googleObject(MockRequest req) {
    final org = _org(req);
    req.requirePlatform();
    final c = _memberRow(req, req.param('id'));
    final expected = _expectedLocations(org);
    // Customer #3's card never got its locations: the gap is the answer.
    final missing = c['id'] == MockSeed.customerId(3);
    final stored = missing ? 0 : expected;
    return MockResponse.ok(
      GoogleObjectDump(
        expectedLocations: expected,
        storedLocations: stored,
        object: _googleObject(c, org, stored),
      ),
    );
  }

  MockResponse googleRefresh(MockRequest req) {
    final org = _org(req);
    req.requirePlatform();
    final c = _memberRow(req, req.param('id'));
    final sent = _expectedLocations(org);
    final object = _googleObject(c, org, sent);
    final cls = {
      'id': '3388000000022001234.sabah-coffee',
      'programName': 'Sabah Stamps',
      'reviewStatus': 'UNDER_REVIEW',
      'locations': object['locations'],
    };
    return MockResponse.ok(
      GoogleRefreshReport(
        sentLocations: sent,
        classLocations: sent,
        objectLocations: sent,
        steps: [
          WalletStep(
            step: 'loyaltyClass.patch',
            status: 200,
            body: const JsonEncoder.withIndent('  ').convert(cls),
          ),
          WalletStep(
            step: 'loyaltyObject.get',
            status: 404,
            body: '{"error": {"code": 404, "message": "Resource not found."}}',
          ),
          WalletStep(
            step: 'loyaltyObject.insert',
            status: 200,
            body: const JsonEncoder.withIndent('  ').convert(object),
          ),
        ],
        class_: cls,
        object: object,
      ),
    );
  }

  // ── the order sheet's read, when the orders unit has none ─────────────

  MockResponse order(MockRequest req) {
    _org(req);
    req.requireCap('orders.read');
    final id = req.param('order_id');
    final row = db['orders'].find(id) ?? req.notFound('Order not found');
    final full = MockSeed.instance.orderFull(id);
    return MockResponse.ok({
      ...?full?.toJson(),
      ...row,
      'items': [...?full?.items.map((i) => i.toJson())],
    });
  }
}
