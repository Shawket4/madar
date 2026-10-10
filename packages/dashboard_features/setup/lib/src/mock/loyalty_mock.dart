/// The mock backend for Loyalty settings and members admin
/// (`/settings/loyalty`, SET-LOY rows), after `MadarRust src/loyalty/
/// {settings,handlers,model,birthdays}.rs` and `src/qr_card/handlers.rs`.
///
/// Owned here (registered over any other area's): GET/PUT/DELETE
/// /loyalty/settings, GET/PUT /loyalty/reward-items and /earning-items,
/// GET /loyalty/members, GET /loyalty/analytics, GET /loyalty/wallet-status,
/// POST /loyalty/birthday-preview, GET /branches/{id}/loyalty-qr and
/// /orgs/{id}/loyalty-qr.
///
/// Shared with the sell area's customer sheet (registered only when no other
/// area answers them, so one implementation serves both over the same
/// tables): GET /customers, GET /menu-items, GET/DELETE /loyalty/members/{id},
/// POST /loyalty/adjust, the two Google Wallet routes.
///
/// Tables: `loyalty_settings` (the area seed), `loyalty_reward_items`,
/// `loyalty_earning_items` (here), and `loyalty_members` / `loyalty_ledger`
/// (the sell area's shape; seeded here only when absent). Figures are
/// computed from these rows as the backend computes them, so the Overview,
/// the members list and a member's card agree.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';
import 'support.dart';

/// The tables this unit reads and writes.
abstract final class LoyaltyTables {
  static const String settings = SetupSeed.loyaltySettingsTable;

  /// `{org_id, branch_id, menu_item_id, cost_currency, cost_amount,
  /// sort_order}`.
  static const String rewards = 'loyalty_reward_items';

  /// `{org_id, branch_id, menu_item_id, sort_order}`.
  static const String earning = 'loyalty_earning_items';

  /// `{id, enrolled_at, left_at?}`, one per membership (id = customer id).
  static const String members = 'loyalty_members';

  /// [LedgerEntry] rows plus `customer_id` (and, here, the reward's
  /// `reward_menu_item_id` / `reward_value_minor`).
  static const String ledger = 'loyalty_ledger';
}

/// The org's reward catalogue: what six stamps buy, and a cookie for four.
const List<(String key, int cost)> loyaltySeedRewards = [
  ('espresso', 6),
  ('americano', 6),
  ('cappuccino', 6),
  ('latte', 6),
  ('cookie', 4),
];

/// The base of the public join links when the shop has no host of its own.
const String mockLoyaltyBase = 'https://loyalty.madar-pos.cloud';

void registerLoyaltyMocks(MockServer server, MockDb db) {
  _seed(db);
  final h = _Handlers(db);
  server
    ..on('GET', '/loyalty/settings', h.getSettings)
    ..on('PUT', '/loyalty/settings', h.putSettings)
    ..on('DELETE', '/loyalty/settings', h.deleteSettings)
    ..on('GET', '/loyalty/reward-items', h.getRewards)
    ..on('PUT', '/loyalty/reward-items', h.putRewards)
    ..on('GET', '/loyalty/earning-items', h.getEarning)
    ..on('PUT', '/loyalty/earning-items', h.putEarning)
    ..on('GET', '/loyalty/members', h.listMembers)
    ..on('GET', '/loyalty/analytics', h.analytics)
    ..on('GET', '/loyalty/wallet-status', h.walletStatus)
    ..on('POST', '/loyalty/birthday-preview', h.birthdayPreview)
    ..on('GET', '/branches/{id}/loyalty-qr', h.branchQr)
    ..on('GET', '/orgs/{id}/loyalty-qr', h.orgQr);
  onIfAbsent(server, 'GET', '/customers', h.customers);
  onIfAbsent(server, 'GET', '/menu-items', h.menuItems);
  onIfAbsent(server, 'GET', '/loyalty/members/{id}', h.member);
  onIfAbsent(server, 'DELETE', '/loyalty/members/{id}', h.leave);
  onIfAbsent(server, 'POST', '/loyalty/adjust', h.adjust);
  onIfAbsent(
    server,
    'GET',
    '/loyalty/members/{id}/google-object',
    h.googleObject,
  );
  onIfAbsent(
    server,
    'POST',
    '/loyalty/members/{id}/google-refresh',
    h.googleRefresh,
  );
}

// ── Seed ─────────────────────────────────────────────────────────────────

void _seed(MockDb db) {
  seedTableIfAbsent(
    db,
    LoyaltyTables.rewards,
    () => [
      for (final (i, (key, cost)) in loyaltySeedRewards.indexed)
        {
          'org_id': SeedIds.sabahOrg,
          'branch_id': null,
          'menu_item_id': MockSeed.menuItemId(key),
          'cost_currency': 'visits',
          'cost_amount': cost,
          'sort_order': i,
        },
    ],
  );
  seedTableIfAbsent(db, LoyaltyTables.earning, () => const []);
  seedTableIfAbsent(
    db,
    LoyaltyTables.members,
    () => [
      for (final c in db['customers'].rows)
        if (c['is_member'] == true)
          {
            'id': c['id'],
            'enrolled_at': DateTime.parse(
              c['created_at']! as String,
            ).add(const Duration(days: 1)).toUtc().toIso8601String(),
          },
    ],
  );
  seedTableIfAbsent(db, LoyaltyTables.ledger, () => _ledgerSeed(db));
}

/// Each member's history, summing to their stamp balance: a stamp per order
/// since they joined (a voided order's stamp reversed), a reward at every
/// sixth (from the catalogue, in turn), the paper card's stamps carried over
/// at enrolment, and for Nada Kamal a stamp added by hand.
List<MockRow> _ledgerSeed(MockDb db) {
  final customers = db['customers'].rows;
  final enrolled = {
    for (final m in db[LoyaltyTables.members].rows)
      m['id']! as String: DateTime.parse(m['enrolled_at']! as String),
  };
  final branchNames = {
    for (final b in db['branches'].rows) b['id']! as String: b['name'],
  };
  final menu = {for (final m in db['menu_items'].rows) m['id']! as String: m};
  final byCustomer = <String, List<MockRow>>{};
  for (final o in db['orders'].rows) {
    final id = o['customer_id'];
    if (id is String && enrolled.containsKey(id)) {
      (byCustomer[id] ??= []).add(o);
    }
  }
  final out = <MockRow>[];
  var rewardTurn = 0;
  for (final c in customers) {
    final id = c['id']! as String;
    final joined = enrolled[id];
    if (joined == null) continue;
    final balance = (c['visits_balance'] as num?)?.toInt() ?? 0;
    final orders =
        [
          for (final o in byCustomer[id] ?? const <MockRow>[])
            if (DateTime.parse(o['created_at']! as String).isAfter(joined)) o,
        ]..sort(
          (a, b) => (a['created_at']! as String).compareTo(
            b['created_at']! as String,
          ),
        );
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
      String? reverses,
      String? rewardItem,
    }) {
      final b = branchId ?? SeedIds.heliopolis;
      final item = rewardItem == null ? null : menu[rewardItem];
      return {
        ...LedgerEntry(
          id: mockUuid('ledger:$id:${n++}'),
          branchId: b,
          branchName: branchNames[b] as String?,
          createdAt: at,
          createdBy: by,
          createdByName: byName,
          currency: 'visits',
          kind: kind,
          source: source,
          points: points,
          orderId: orderId,
          note: note,
          rewardName: item?['name'] as String?,
          reversesId: reverses,
        ).toJson(),
        'customer_id': id,
        'reward_menu_item_id': ?rewardItem,
        'reward_value_minor': ?item?['base_price'],
      };
    }

    final rows = <MockRow>[];
    var running = 0;
    for (final o in orders) {
      final at = DateTime.parse(o['created_at']! as String);
      final earn = row(
        kind: 'earn',
        source: 'sale',
        points: 1,
        at: at,
        branchId: o['branch_id'] as String?,
        orderId: o['id'] as String?,
        by: o['teller_id'] as String?,
        byName: o['teller_name'] as String?,
      );
      rows.add(earn);
      if (o['status'] != 'completed') {
        rows.add(
          row(
            kind: 'reverse_earn',
            source: 'void',
            points: -1,
            at: DateTime.tryParse('${o['voided_at']}') ?? at,
            branchId: o['branch_id'] as String?,
            orderId: o['id'] as String?,
            by: o['voided_by'] as String?,
            reverses: earn['id']! as String,
          ),
        );
        continue;
      }
      running++;
      if (running >= 6) {
        running -= 6;
        final (key, _) =
            loyaltySeedRewards[rewardTurn++ % (loyaltySeedRewards.length - 1)];
        rows.add(
          row(
            kind: 'redeem',
            source: 'redemption',
            points: -6,
            at: at.add(const Duration(minutes: 1)),
            branchId: o['branch_id'] as String?,
            orderId: o['id'] as String?,
            by: o['teller_id'] as String?,
            byName: o['teller_name'] as String?,
            rewardItem: MockSeed.menuItemId(key),
          ),
        );
      }
    }
    if (c == customers.first) {
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
    final gap = balance - running;
    if (gap > 0) {
      rows.insert(
        0,
        row(
          kind: 'adjust',
          source: 'manual',
          points: gap,
          at: joined,
          by: SeedIds.owner,
          byName: 'Nour El-Sayed',
          note: 'Stamps carried over from the paper card',
        ),
      );
    } else if (gap < 0) {
      rows.add(
        row(
          kind: 'adjust',
          source: 'manual',
          points: gap,
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

int _i(Object? v) => (v as num?)?.toInt() ?? 0;

class _Handlers {
  _Handlers(this.db);

  final MockDb db;

  // ── scope ──────────────────────────────────────────────────────────────

  /// `scope_org`: the branch's org when one is named, else the caller's
  /// (a platform admin's picked one); none is a 400.
  String _scopeOrg(MockRequest req, String? branchId) {
    if (branchId != null) {
      final b =
          db['branches'].find(branchId) ?? req.notFound('Branch not found');
      return b['org_id']! as String;
    }
    return req.orgId ?? req.badRequest('Pick an organisation first');
  }

  MockRow? _row(String org, String? branchId) => db[LoyaltyTables.settings]
      .firstWhere((r) => r['org_id'] == org && r['branch_id'] == branchId);

  /// `LoyaltySettings::defaults`.
  Map<String, Object?> _defaults(String org, String? branchId) =>
      LoyaltySettings(
        orgId: org,
        branchId: branchId,
        enabled: false,
        programName: 'Rewards',
        mode: 'points',
        earnPiastresPerPoint: 1000,
        earnOnDiscounted: true,
        earnIncludeTax: false,
        defaultRewardCost: 100,
        requireOtp: true,
        birthdayEnabled: false,
        winbackEnabled: false,
        rewardAnyItem: false,
        stampPerLineItem: true,
        balanceCapEnabled: false,
        allowNegativeBalance: false,
        geofencedBranches: 0,
      ).toJson();

  /// `load_effective`: the branch's own row, else the org's, else defaults.
  Map<String, Object?> _effective(String org, String? branchId) {
    final own = branchId == null ? null : _row(org, branchId);
    return {...(own ?? _row(org, null) ?? _defaults(org, null))};
  }

  String _mode(Map<String, Object?> s) =>
      s['mode'] == 'visits' ? 'visits' : 'points';

  int _geofenced(String org) => db['branches']
      .where(
        (b) =>
            b['org_id'] == org &&
            b['is_active'] == true &&
            b['latitude'] != null &&
            b['longitude'] != null,
      )
      .length;

  /// A scope's own reward rows joined to the live menu, in order.
  List<RewardItem> _rewardRows(String org, String? branchId, {String? mode}) {
    final rows =
        db[LoyaltyTables.rewards].where(
          (r) => r['org_id'] == org && r['branch_id'] == branchId,
        )..sort((a, b) {
          final s = _i(a['sort_order']).compareTo(_i(b['sort_order']));
          return s != 0
              ? s
              : _i(a['cost_amount']).compareTo(_i(b['cost_amount']));
        });
    return [
      for (final r in rows)
        if (db['menu_items'].find(r['menu_item_id']! as String) case final m?
            when m['deleted_at'] == null)
          RewardItem(
            menuItemId: m['id']! as String,
            name: m['name']! as String,
            imageUrl: m['image_url'] as String?,
            basePrice: _i(m['base_price']),
            costCurrency: mode ?? r['cost_currency']! as String,
            costAmount: _i(r['cost_amount']),
            sortOrder: _i(r['sort_order']),
          ),
    ];
  }

  /// `load_effective_rewards`: a branch's own list, else the org's
  /// (inherited), priced in the scope's mode.
  (List<RewardItem>, bool) _effectiveRewards(String org, String? branchId) {
    final mode = _mode(_effective(org, branchId));
    if (branchId != null) {
      final own = _rewardRows(org, branchId, mode: mode);
      if (own.isNotEmpty) return (own, false);
      return (_rewardRows(org, null, mode: mode), true);
    }
    return (_rewardRows(org, null, mode: mode), false);
  }

  /// `effective_balance_cap`.
  int? _effectiveCap(Map<String, Object?> s, List<RewardItem> rewards) {
    if (s['balance_cap_enabled'] != true) return null;
    final explicit = s['balance_cap'] as num?;
    if (explicit != null) return math.max(explicit.toInt(), 1);
    final dearest = rewards.fold<int>(0, (m, r) => math.max(m, r.costAmount));
    return dearest > 0 ? dearest : math.max(_i(s['default_reward_cost']), 1);
  }

  /// The settings as GET answers them: in force at the scope, with the
  /// read-only facts filled in.
  Map<String, Object?> _answer(String org, String? branchId) {
    final s = _effective(org, branchId);
    s['geofenced_branches'] = _geofenced(org);
    final b = (s['branch_id'] as String?) ?? branchId;
    s['effective_balance_cap'] = _effectiveCap(s, _effectiveRewards(org, b).$1);
    return s;
  }

  /// Keeps the stored copies of the read-only facts current, so a reader
  /// that returns the row as stored agrees with this one.
  void _refreshFacts(String org) {
    for (final r in db[LoyaltyTables.settings].rows) {
      if (r['org_id'] != org) continue;
      r['geofenced_branches'] = _geofenced(org);
      r['effective_balance_cap'] = _effectiveCap(
        r,
        _effectiveRewards(org, r['branch_id'] as String?).$1,
      );
    }
  }

  // ── settings ───────────────────────────────────────────────────────────

  MockResponse getSettings(MockRequest req) {
    final branchId = req.q('branch_id');
    final org = _scopeOrg(req, branchId);
    req.requireCap('loyalty.read');
    if (branchId != null) req.requireBranch(branchId);
    return MockResponse.ok(_answer(org, branchId));
  }

  MockResponse putSettings(MockRequest req) {
    final body = req.json;
    final branchId = body['branch_id'] as String?;
    final org = _scopeOrg(req, branchId);
    req.requireCap('loyalty.use');
    if (branchId != null) {
      req.requireBranch(branchId);
      if (body['org_id'] != null && body['org_id'] != org) {
        req.fail(MockResponse.forbidden('Branch belongs to a different org'));
      }
    }
    int? n(String k) => (body[k] as num?)?.toInt();
    if ((n('earn_piastres_per_point') ?? 0) <= 0) {
      req.badRequest('earn_piastres_per_point must be greater than zero');
    }
    if ((n('default_reward_cost') ?? 0) <= 0) {
      req.badRequest('default_reward_cost must be greater than zero');
    }
    if (body['mode'] != 'points' && body['mode'] != 'visits') {
      req.badRequest("mode must be 'points' or 'visits'");
    }
    if ((body['program_name'] as String? ?? '').trim().isEmpty) {
      req.badRequest('program_name is required');
    }
    if ((n('balance_cap') ?? 1) <= 0) {
      req.badRequest(
        'A balance cap must be greater than zero — leave it empty for no cap',
      );
    }
    if ((n('max_rewards_per_order') ?? 1) <= 0) {
      req.badRequest(
        'Rewards per order must be at least 1 — leave it empty for no limit',
      );
    }
    if ((n('winback_reward_amount') ?? 1) <= 0) {
      req.badRequest('a win-back reward must be worth more than nothing');
    }
    if ((n('birthday_reward_amount') ?? 1) <= 0) {
      req.badRequest('a birthday reward must be worth more than nothing');
    }
    final existing = _row(org, branchId);
    final row = <String, Object?>{
      'org_id': org,
      'branch_id': branchId,
      'enabled': body['enabled'] == true,
      'program_name': (body['program_name']! as String).trim(),
      'program_name_ar': body['program_name_ar'],
      'mode': body['mode'],
      'earn_piastres_per_point': n('earn_piastres_per_point'),
      'earn_on_discounted': body['earn_on_discounted'] == true,
      'earn_include_tax': body['earn_include_tax'] == true,
      'default_reward_cost': n('default_reward_cost'),
      'require_otp': body['require_otp'] == true,
      'birthday_enabled': body['birthday_enabled'] == true,
      'birthday_reward_amount': n('birthday_reward_amount'),
      'birthday_message': body['birthday_message'],
      'birthday_message_ar': body['birthday_message_ar'],
      'winback_enabled': body['winback_enabled'] == true,
      'winback_message': body['winback_message'],
      'winback_reward_amount': n('winback_reward_amount'),
      'reward_any_item': body['reward_any_item'] == true,
      // `None` keeps the row's value; a new scope resolves to per-item.
      'stamp_per_line_item':
          body['stamp_per_line_item'] ??
          existing?['stamp_per_line_item'] ??
          true,
      'balance_cap_enabled': body['balance_cap_enabled'] == true,
      'balance_cap': n('balance_cap'),
      'max_rewards_per_order': n('max_rewards_per_order'),
      'allow_negative_balance': body['allow_negative_balance'] == true,
      'terms': body['terms'],
      'terms_ar': body['terms_ar'],
    };
    final table = db[LoyaltyTables.settings];
    if (existing != null) {
      existing.addAll(row);
    } else {
      table.insert(row, timestamps: false);
    }
    // A programme collects ONE thing: the scope's catalogue is re-priced.
    for (final r in db[LoyaltyTables.rewards].rows) {
      if (r['org_id'] == org && r['branch_id'] == branchId) {
        r['cost_currency'] = row['mode'];
      }
    }
    _refreshFacts(org);
    final saved = {...?_row(org, branchId)};
    return MockResponse.ok(saved);
  }

  MockResponse deleteSettings(MockRequest req) {
    final branchId = req.q('branch_id');
    final org = _scopeOrg(req, branchId);
    req.requireCap('loyalty.use');
    if (branchId == null) {
      req.badRequest(
        'branch_id is required: only a branch override may be removed',
      );
    }
    req.requireBranch(branchId);
    db[LoyaltyTables.settings].removeWhere(
      (r) => r['org_id'] == org && r['branch_id'] == branchId,
    );
    return MockResponse.empty();
  }

  /// `birthdays::message_for`, for a stand-in member called Sara.
  MockResponse birthdayPreview(MockRequest req) {
    req.requireCap('loyalty.use');
    final s = req.json;
    String message(bool arabic) {
      const name = 'Sara';
      final custom = arabic
          ? ((s['birthday_message_ar'] as String?) ??
                (s['birthday_message'] as String?))
          : s['birthday_message'] as String?;
      if (custom != null && custom.trim().isNotEmpty) {
        return custom.trim().replaceAll('{name}', name);
      }
      final program = s['program_name'] as String? ?? '';
      final gift = (s['birthday_reward_amount'] as num?)?.toInt();
      final visits = s['mode'] == 'visits';
      final unit = visits
          ? (arabic ? 'أختام' : 'stamps')
          : (arabic ? 'نقطة' : 'points');
      if (!arabic) {
        return gift != null
            ? "Happy birthday, $name! 🎉 We've put $gift $unit on your "
                  '$program card — come and enjoy something on us.'
            : 'Happy birthday, $name! 🎉 Everyone at $program is thinking of '
                  'you today.';
      }
      return gift != null
          ? 'كل سنة وأنت طيب يا $name! 🎉 أضفنا $gift $unit إلى بطاقتك في '
                '$program — تعال واستمتع بشيء على حسابنا.'
          : 'كل سنة وأنت طيب يا $name! 🎉 نتمنى لك يوماً سعيداً من $program.';
    }

    return MockResponse.ok(
      BirthdayPreview(en: message(false), ar: message(true)),
    );
  }

  /// Apple signs and Google answers; Apple's push keys were never set.
  MockResponse walletStatus(MockRequest req) {
    req.requireCap('loyalty.use');
    req.requirePlatform();
    final branchId = req.q('branch_id');
    if (branchId != null) req.requireBranch(branchId);
    return MockResponse.ok(
      WalletStatus(
        apple: WalletProvider(configured: true, missing: const []),
        apns: WalletProvider(
          configured: false,
          missing: const ['LOYALTY_APNS_KEY_ID', 'LOYALTY_APNS_KEY_FILE'],
        ),
        google: WalletProvider(
          configured: true,
          missing: const [],
          reachable: true,
          detail:
              'Issuer 3388000000022001234 answered; class sabah-coffee is '
              'UNDER_REVIEW.',
        ),
      ),
    );
  }

  // ── the reward catalogue and the items that collect ────────────────────

  MockResponse getRewards(MockRequest req) {
    final branchId = req.q('branch_id');
    final org = _scopeOrg(req, branchId);
    req.requireCap('loyalty.read');
    if (branchId != null) req.requireBranch(branchId);
    final (items, inherited) = _effectiveRewards(org, branchId);
    return MockResponse.ok(
      RewardCatalogue(
        orgId: org,
        branchId: branchId,
        inherited: inherited,
        items: items,
      ),
    );
  }

  /// Every id is a live, active menu item of [org].
  bool _allOffered(String org, Iterable<String> ids) => ids.toSet().every((id) {
    final m = db['menu_items'].find(id);
    return m != null &&
        m['org_id'] == org &&
        m['deleted_at'] == null &&
        m['is_active'] == true;
  });

  MockResponse putRewards(MockRequest req) {
    final body = req.json;
    final branchId = body['branch_id'] as String?;
    final org = _scopeOrg(req, branchId);
    req.requireCap('loyalty.use');
    if (branchId != null) req.requireBranch(branchId);
    final scope = _effective(org, branchId);
    final items = [
      for (final i in (body['items'] as List? ?? const []))
        (i as Map).cast<String, Object?>(),
    ];
    if (!_allOffered(org, items.map((i) => i['menu_item_id']! as String))) {
      req.badRequest('reward items must be active menu items of this org');
    }
    for (final i in items) {
      final c = i['cost_currency'];
      if (c != null && c != 'points' && c != 'visits') {
        req.badRequest("cost_currency must be 'points' or 'visits'");
      }
      if ((i['cost_amount'] as num?) case final a? when a <= 0) {
        req.badRequest('a reward must cost more than nothing');
      }
    }
    final table = db[LoyaltyTables.rewards]
      ..removeWhere((r) => r['org_id'] == org && r['branch_id'] == branchId);
    final seen = <String>{};
    for (final (n, i) in items.indexed) {
      final id = i['menu_item_id']! as String;
      if (!seen.add(id)) continue; // ON CONFLICT DO NOTHING
      table.insert({
        'org_id': org,
        'branch_id': branchId,
        'menu_item_id': id,
        'cost_currency': i['cost_currency'] ?? _mode(scope),
        'cost_amount':
            (i['cost_amount'] as num?)?.toInt() ??
            _i(scope['default_reward_cost']),
        'sort_order': n,
      }, timestamps: false);
    }
    _refreshFacts(org);
    return MockResponse.ok(
      RewardCatalogue(
        orgId: org,
        branchId: branchId,
        inherited: false,
        items: _rewardRows(org, branchId),
      ),
    );
  }

  List<EarningItem> _earningRows(String org, String? branchId) {
    final rows = db[LoyaltyTables.earning].where(
      (r) => r['org_id'] == org && r['branch_id'] == branchId,
    )..sort((a, b) => _i(a['sort_order']).compareTo(_i(b['sort_order'])));
    return [
      for (final r in rows)
        if (db['menu_items'].find(r['menu_item_id']! as String) case final m?
            when m['deleted_at'] == null)
          EarningItem(
            menuItemId: m['id']! as String,
            name: m['name']! as String,
            imageUrl: m['image_url'] as String?,
            basePrice: _i(m['base_price']),
            sortOrder: _i(r['sort_order']),
          ),
    ];
  }

  MockResponse getEarning(MockRequest req) {
    final branchId = req.q('branch_id');
    final org = _scopeOrg(req, branchId);
    req.requireCap('loyalty.read');
    var items = _earningRows(org, branchId);
    var inherited = false;
    if (branchId != null) {
      req.requireBranch(branchId);
      if (items.isEmpty) {
        items = _earningRows(org, null);
        inherited = true;
      }
    }
    return MockResponse.ok(
      EarningItemList(
        orgId: org,
        branchId: branchId,
        inherited: inherited,
        items: items,
      ),
    );
  }

  MockResponse putEarning(MockRequest req) {
    final body = req.json;
    final branchId = body['branch_id'] as String?;
    final org = _scopeOrg(req, branchId);
    req.requireCap('loyalty.use');
    if (branchId != null) req.requireBranch(branchId);
    final ids = [
      for (final id in (body['menu_item_ids'] as List? ?? const [])) '$id',
    ];
    if (!_allOffered(org, ids)) {
      req.badRequest('earning items must be active menu items of this org');
    }
    final table = db[LoyaltyTables.earning]
      ..removeWhere((r) => r['org_id'] == org && r['branch_id'] == branchId);
    for (final (n, id) in ids.toSet().indexed) {
      table.insert({
        'org_id': org,
        'branch_id': branchId,
        'menu_item_id': id,
        'sort_order': n,
      }, timestamps: false);
    }
    return MockResponse.ok(
      EarningItemList(
        orgId: org,
        branchId: branchId,
        inherited: false,
        items: _earningRows(org, branchId),
      ),
    );
  }

  MockResponse menuItems(MockRequest req) {
    req.requireCap('menu.items.read');
    final org = req.q('org_id');
    if (org == null) {
      req.badRequest('Query deserialize error: missing field `org_id`');
    }
    req.requireSameOrg(org);
    return MockResponse.ok(
      db['menu_items'].query(filters: {'org_id': org}, sort: 'name'),
    );
  }

  // ── people ─────────────────────────────────────────────────────────────

  MockResponse customers(MockRequest req) {
    if (req.orgId == null) {
      req.fail(MockResponse.forbidden('No organization selected'));
    }
    req.requireCap('customers.view');
    final source = req.q('source')?.trim();
    if (source != null &&
        source.isNotEmpty &&
        !const [
          'pos',
          'online',
          'loyalty',
          'booking',
          'table_qr',
          'aggregator',
          'dashboard',
        ].contains(source)) {
      req.badRequest('Unknown customer source `$source`');
    }
    final member = req.qBool('member');
    final limit = (req.qInt('limit') ?? 100).clamp(1, 500);
    final offset = math.max(req.qInt('offset') ?? 0, 0);
    final needle = req.q('q')?.trim().toLowerCase() ?? '';
    final digits = needle.replaceAll(RegExp('[^0-9]'), '');
    final rows = db['customers'].where((c) {
      if (needle.isNotEmpty) {
        final byName = '${c['name']}'.toLowerCase().contains(needle);
        final phone = '${c['phone'] ?? ''}'.replaceAll(RegExp('[^0-9]'), '');
        final byPhone = digits.length >= 3 && phone.contains(digits);
        if (!byName && !byPhone) return false;
      }
      if (member != null && (c['is_member'] == true) != member) return false;
      if (source != null && source.isNotEmpty && _source(c) != source) {
        return false;
      }
      return true;
    });
    String seen(MockRow c) =>
        (c['last_order_at'] ?? c['created_at'])! as String;
    rows.sort((a, b) {
      final d = seen(b).compareTo(seen(a));
      return d != 0 ? d : (a['id']! as String).compareTo(b['id']! as String);
    });
    return MockResponse.ok([
      for (final c in rows.skip(offset).take(limit))
        {...Customer.fromJson(c).toJson(), 'source': _source(c)},
    ]);
  }

  /// `order_now` is not a source the backend knows: those came online.
  static Object? _source(MockRow c) =>
      c['source'] == 'order_now' ? 'online' : c['source'];

  /// A live member [id], else 404.
  MockRow _memberRow(
    MockRequest req,
    String id, {
    String what = 'Member not found',
  }) {
    final c = db['customers'].find(id);
    if (c == null || c['is_member'] != true) req.notFound(what);
    return c;
  }

  /// `MemberRow::view` under the scope's programme and reward target.
  MemberView _view(MockRow c, String org, String? branchId) {
    final s = _effective(org, branchId);
    final mode = _mode(s);
    final rewards = _effectiveRewards(org, branchId).$1;
    final cheapest = rewards.isEmpty
        ? null
        : rewards.map((r) => r.costAmount).reduce(math.min);
    final target = s['reward_any_item'] == true
        ? _i(s['default_reward_cost'])
        : (cheapest ?? _i(s['default_reward_cost']));
    final visits = _i(c['visits_balance']);
    final points = _i(c['points_balance']);
    final balance = mode == 'visits' ? visits : points;
    final id = c['id']! as String;
    var lifeVisits = 0;
    var lifePoints = 0;
    for (final e in db[LoyaltyTables.ledger].rows) {
      if (e['customer_id'] != id) continue;
      if (e['kind'] != 'earn' && e['kind'] != 'reverse_earn') continue;
      if (e['currency'] == 'visits') {
        lifeVisits += _i(e['points']);
      } else {
        lifePoints += _i(e['points']);
      }
    }
    final ready = target <= 0 || balance <= 0 ? 0 : balance ~/ target;
    final progress = target <= 0 || balance <= 0
        ? math.max(balance, 0)
        : balance % target;
    final m = db[LoyaltyTables.members].find(id);
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
      nextRewardCost: target,
      progressToNext: progress,
      pointsToNextReward: math.max(target - progress, 0),
      rewardsReady: ready,
      canRedeem: ready > 0,
    );
  }

  DateTime _enrolled(MockRow c) => DateTime.parse(
    (db[LoyaltyTables.members].find(c['id']! as String)?['enrolled_at'] ??
            c['created_at'])!
        as String,
  );

  MockResponse listMembers(MockRequest req) {
    final branchId = req.q('branch_id');
    final org = _scopeOrg(req, branchId);
    req.requireCap('loyalty.read');
    req.requireCap('loyalty.members.list');
    if (branchId != null) req.requireBranch(branchId);
    final limit = (req.qInt('limit') ?? 50).clamp(1, 200);
    final offset = math.max(req.qInt('offset') ?? 0, 0);
    final needle = req.q('q')?.trim().toLowerCase() ?? '';
    final rows = db['customers'].where(
      (c) =>
          c['is_member'] == true &&
          (needle.isEmpty ||
              '${c['name']}'.toLowerCase().contains(needle) ||
              '${c['phone'] ?? ''}'.toLowerCase().contains(needle)),
    )..sort((a, b) => _enrolled(b).compareTo(_enrolled(a)));
    return MockResponse.ok(
      MembersPage(
        members: [
          for (final c in rows.skip(offset).take(limit))
            _view(c, org, branchId),
        ],
        total: rows.length,
      ),
    );
  }

  MockResponse member(MockRequest req) {
    final branchId = req.q('branch_id');
    final org = _scopeOrg(req, branchId);
    req.requireAnyCap(['loyalty.read', 'loyalty.members.list']);
    if (branchId != null) req.requireBranch(branchId);
    final c = _memberRow(req, req.param('id'));
    final id = c['id']! as String;
    final ledger = db[LoyaltyTables.ledger].where((e) => e['customer_id'] == id)
      ..sort(
        (a, b) =>
            (b['created_at']! as String).compareTo(a['created_at']! as String),
      );
    return MockResponse.ok(
      MemberDetail(
        member: _view(c, org, branchId),
        ledger: [for (final e in ledger.take(200)) LedgerEntry.fromJson(e)],
      ),
    );
  }

  MockResponse leave(MockRequest req) {
    req.requireCap('loyalty.members.delete');
    final c = db['customers'].find(req.param('id'));
    // A card already gone is not a failure.
    if (c == null || c['is_member'] != true) return MockResponse.empty();
    // The memberships and the ledger are read from the customers lazily:
    // load them before this one stops being a member.
    final members = db[LoyaltyTables.members]..rows;
    db[LoyaltyTables.ledger].rows;
    c
      ..['is_member'] = false
      ..['loyalty_customer_id'] = null
      ..['updated_at'] = req.now.toIso8601String();
    members.find(c['id']! as String)?['left_at'] = req.now.toIso8601String();
    return MockResponse.empty();
  }

  MockResponse adjust(MockRequest req) {
    final body = req.json;
    final branchId = body['branch_id'] as String?;
    final org = _scopeOrg(req, branchId);
    req.requireCap('loyalty.points.adjust');
    final note = (body['note'] as String?)?.trim() ?? '';
    if (note.isEmpty) {
      req.badRequest('Say why the points are being adjusted (note)');
    }
    final customerId = body['customer_id'] as String?;
    final points = (body['points'] as num?)?.toInt();
    if (branchId == null || customerId == null || points == null) {
      req.badRequest('Json deserialize error: missing field');
    }
    req.requireBranch(branchId);
    final c = _memberRow(req, customerId, what: 'No member for that card');
    if (points == 0) {
      req.badRequest('An adjustment of zero points changes nothing');
    }
    final mode = _mode(_effective(org, branchId));
    final field = mode == 'visits' ? 'visits_balance' : 'points_balance';
    final have = _i(c[field]);
    if (have + points < 0) {
      req.badRequest(
        '${c['name']} has $have; that adjustment would go negative',
      );
    }
    final ledger = db[LoyaltyTables.ledger]..rows;
    ledger.insert({
      ...LedgerEntry(
        id: db.newId(LoyaltyTables.ledger),
        branchId: branchId,
        branchName: db['branches'].find(branchId)?['name'] as String?,
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

  Map<String, Object?> _googleObject(MockRow c, String org, int locations) => {
    'id': '3388000000022001234.member-${c['id']}',
    'classId': '3388000000022001234.sabah-coffee',
    'state': 'ACTIVE',
    'accountId': c['id'],
    'accountName': c['name'],
    'loyaltyPoints': {
      'label': 'Stamps',
      'balance': {'int': c['visits_balance'] ?? 0},
    },
    'locations': [
      for (final b
          in db['branches']
              .where((b) => b['org_id'] == org && b['is_active'] == true)
              .take(locations))
        {'latitude': b['latitude'], 'longitude': b['longitude']},
    ],
  };

  MockResponse googleObject(MockRequest req) {
    final org = _scopeOrg(req, null);
    req.requirePlatform();
    final c = _memberRow(req, req.param('id'));
    final expected = _geofenced(org);
    // Customer #3's card never got its locations: the gap is the answer.
    final stored = c['id'] == MockSeed.customerId(3) ? 0 : expected;
    return MockResponse.ok(
      GoogleObjectDump(
        expectedLocations: expected,
        storedLocations: stored,
        object: _googleObject(c, org, stored),
      ),
    );
  }

  MockResponse googleRefresh(MockRequest req) {
    final org = _scopeOrg(req, null);
    req.requirePlatform();
    final c = _memberRow(req, req.param('id'));
    final sent = _geofenced(org);
    final object = _googleObject(c, org, sent);
    final cls = {
      'id': '3388000000022001234.sabah-coffee',
      'programName': 'Sabah Stamps',
      'reviewStatus': 'UNDER_REVIEW',
      'locations': object['locations'],
    };
    const pretty = JsonEncoder.withIndent('  ');
    return MockResponse.ok(
      GoogleRefreshReport(
        sentLocations: sent,
        classLocations: sent,
        objectLocations: sent,
        steps: [
          WalletStep(
            step: 'loyaltyClass.patch',
            status: 200,
            body: pretty.convert(cls),
          ),
          WalletStep(
            step: 'loyaltyObject.get',
            status: 404,
            body: '{"error": {"code": 404, "message": "Resource not found."}}',
          ),
          WalletStep(
            step: 'loyaltyObject.insert',
            status: 200,
            body: pretty.convert(object),
          ),
        ],
        class_: cls,
        object: object,
      ),
    );
  }

  // ── the report ─────────────────────────────────────────────────────────

  MockResponse analytics(MockRequest req) {
    final branchId = req.q('branch_id');
    final org = _scopeOrg(req, branchId);
    req.requireCap('loyalty.read');
    req.requireCap('loyalty.members.list');
    if (branchId != null) req.requireBranch(branchId);
    final to = req.qDateTime('to') ?? req.now;
    final from = req.qDateTime('from') ?? to.subtract(const Duration(days: 30));
    if (!from.isBefore(to)) req.badRequest('`from` must be before `to`');
    return MockResponse.ok(
      loyaltyAnalyticsOf(
        db,
        org: org,
        branchId: branchId,
        from: from,
        to: to,
      ).toJson(),
    );
  }

  // ── the sign-up codes ──────────────────────────────────────────────────

  /// The shop's own host on the branding tier, else none.
  String? _shop(String org) {
    final o = db['orgs'].find(org);
    final slug = o?['slug'] as String?;
    if (o?['custom_branding'] != true || slug == null) return null;
    final url = SetupSeed.publicUrl(slug);
    return url.substring(0, url.length - 1);
  }

  MockResponse branchQr(MockRequest req) {
    req.requireCap('loyalty.read');
    final id = req.param('id');
    final b = db['branches'].find(id) ?? req.notFound('Branch not found');
    req.requireBranch(id);
    final org = b['org_id']! as String;
    if (_effective(org, id)['enabled'] != true) {
      req.conflict('The loyalty program is switched off for this branch');
    }
    final base = _shop(org) ?? mockLoyaltyBase;
    return MockResponse.ok(
      mockQrResponse(
        kind: 'branch_loyalty',
        longUrl: '$base/join/$id',
        key: 'branch_loyalty:$id',
      ),
    );
  }

  MockResponse orgQr(MockRequest req) {
    req.requireCap('loyalty.read');
    final org = req.param('id');
    req.requireSameOrg(org);
    if (_effective(org, null)['enabled'] != true) {
      req.conflict('The loyalty program is switched off for this organisation');
    }
    final shop = _shop(org);
    return MockResponse.ok(
      mockQrResponse(
        kind: 'org_loyalty',
        longUrl: shop != null
            ? '$shop${SetupSeed.modulePaths['rewards']}'
            : '$mockLoyaltyBase/join/org/$org',
        key: 'org_loyalty:$org',
      ),
    );
  }
}

/// `GET /loyalty/analytics` over the ledger, as the backend computes it:
/// redemptions, earned and spent in the range (narrowed to [branchId]), the
/// ten most-redeemed rewards, and the org-wide liability valued at what a
/// unit has bought on average.
LoyaltyAnalytics loyaltyAnalyticsOf(
  MockDb db, {
  required String org,
  String? branchId,
  required DateTime from,
  required DateTime to,
}) {
  bool inRange(MockRow e) {
    final at = DateTime.parse(e['created_at']! as String);
    return !at.isBefore(from) &&
        at.isBefore(to) &&
        (branchId == null || e['branch_id'] == branchId);
  }

  final orgCustomers = {
    for (final c in db['customers'].rows) c['id']! as String: c,
  };
  final ledger = [
    for (final e in db[LoyaltyTables.ledger].rows)
      if (orgCustomers.containsKey(e['customer_id'])) e,
  ];
  final range = ledger.where(inRange).toList();
  var redemptions = 0;
  var spent = 0;
  var earned = 0;
  var value = 0;
  final top = <String, ({String name, int n, int points, int value})>{};
  for (final e in range) {
    final kind = e['kind'];
    final p = _i(e['points']);
    if (kind == 'earn' || kind == 'reverse_earn') earned += p;
    if (kind == 'redeem' || kind == 'reverse_redeem') spent -= p;
    if (kind != 'redeem') continue;
    redemptions++;
    final v = _i(e['reward_value_minor']);
    value += v;
    final name = e['reward_name'] as String? ?? '';
    final id = e['reward_menu_item_id'] as String? ?? mockUuid('reward:$name');
    final t = top[id];
    top[id] = (
      name: name,
      n: (t?.n ?? 0) + 1,
      points: (t?.points ?? 0) - p,
      value: (t?.value ?? 0) + v,
    );
  }
  final refused = db['orders'].rows.where((o) {
    if (o['loyalty_redemption_refused'] == null) return false;
    final at = DateTime.parse(o['created_at']! as String);
    return !at.isBefore(from) &&
        at.isBefore(to) &&
        (branchId == null || o['branch_id'] == branchId);
  }).length;

  final settings =
      db[LoyaltyTables.settings].firstWhere(
        (r) => r['org_id'] == org && r['branch_id'] == branchId,
      ) ??
      db[LoyaltyTables.settings].firstWhere(
        (r) => r['org_id'] == org && r['branch_id'] == null,
      );
  final currency = settings?['mode'] == 'visits' ? 'visits' : 'points';
  var withBalance = 0;
  var outPoints = 0;
  var outVisits = 0;
  for (final c in orgCustomers.values) {
    if (c['is_member'] != true) continue;
    final pts = _i(c['points_balance']);
    final vis = _i(c['visits_balance']);
    if ((currency == 'visits' ? vis : pts) > 0) withBalance++;
    outPoints += math.max(pts, 0);
    outVisits += math.max(vis, 0);
  }
  var allValue = 0;
  var allSpent = 0;
  for (final e in ledger) {
    final v = _i(e['reward_value_minor']);
    if (e['kind'] != 'redeem' || e['currency'] != currency || v <= 0) continue;
    allValue += v;
    allSpent -= _i(e['points']);
  }
  final perUnit = allSpent > 0 ? allValue / allSpent : null;
  final outstanding = currency == 'visits' ? outVisits : outPoints;
  final ranked = top.entries.toList()
    ..sort((a, b) {
      final d = b.value.n.compareTo(a.value.n);
      return d != 0 ? d : a.value.name.compareTo(b.value.name);
    });
  return LoyaltyAnalytics(
    from: from,
    to: to,
    redemptions: redemptions,
    redeemedUnits: redemptions,
    redeemedPoints: spent,
    redeemedValueMinor: value,
    earnedPoints: earned,
    refusedRedemptions: refused,
    topRewards: [
      for (final e in ranked.take(10))
        TopReward(
          menuItemId: e.key,
          name: e.value.name,
          redemptions: e.value.n,
          units: e.value.n,
          points: e.value.points,
          valueMinor: e.value.value,
        ),
    ],
    liability: PointsLiability(
      membersWithBalance: withBalance,
      outstandingPoints: outPoints,
      outstandingVisits: outVisits,
      valuePerUnitMinor: perUnit,
      valuedMinor: perUnit == null ? null : (perUnit * outstanding).round(),
      currency: currency,
    ),
  );
}
