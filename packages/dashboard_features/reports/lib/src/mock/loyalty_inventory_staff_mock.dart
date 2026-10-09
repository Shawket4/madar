/// The mock backend for Loyalty, Inventory reports and Staff discipline
/// (REP-LOY, REP-INV, REP-STF):
///
/// - GET /loyalty/behavior, /loyalty/campaign-effectiveness,
///   /loyalty/liability-trend (MadarRust `loyalty/handlers.rs`);
/// - GET /reports/{branches/{branch_id},orgs/{org_id}}/{consumption,
///   shrinkage,waste-report,po-lead-time,low-stock}
///   (`reports/handlers.rs`);
/// - GET /staff/discipline-report (`staff/discipline.rs`).
///
/// Figures are computed, the backend's way, from the core seed (orders,
/// customers, employees, branches) and the area seed (the inventory
/// catalog, stock, deliveries), so the reports agree with the other pages.
/// The loyalty ledger is derived from the seed's member orders (one earn a
/// visit, a seven-visit reward redeemed on the seventh); waste, stock-count
/// variances and attendance are deterministic plans below.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart'
    show allBranchesId, inZone, wallClock;

import '../area_seed.dart';

void registerLoyaltyInventoryStaffMocks(MockServer server, MockDb db) {
  _registerLoyalty(server, db);
  _registerInventory(server, db);
  _registerDiscipline(server, db);
}

// ── shared ───────────────────────────────────────────────────────────────

double _round(double v, [int dp = 1]) {
  var f = 1.0;
  for (var i = 0; i < dp; i++) {
    f *= 10;
  }
  return (v * f).round() / f;
}

/// The scope's zone (`scope_tz_name`): the branch's own, else its org's,
/// else Cairo.
String lisScopeZone(MockDb db, String? branchId, String? orgId) {
  String? zone(MockRow? r) {
    final z = r?['timezone'];
    return z is String && z.isNotEmpty ? z : null;
  }

  final branch = branchId == null || branchId == allBranchesId
      ? null
      : db['branches'].find(branchId);
  final org = db['orgs'].find('${branch?['org_id'] ?? orgId}');
  return zone(branch) ?? zone(org) ?? 'Africa/Cairo';
}

/// `require_org` (`reports/handlers.rs`): 403 "Not your org" for another
/// org (a platform admin may read any).
void _requireOrg(MockRequest req, String orgId) {
  if (req.persona.isPlatform) return;
  if (req.persona.orgId != orgId) {
    req.fail(MockResponse.forbidden('Not your org'));
  }
}

/// Every live branch of [orgId].
List<String> _orgBranchIds(MockDb db, String orgId) => [
  for (final b in db['branches'].rows)
    if (b['org_id'] == orgId) b['id']! as String,
];

/// `org_read_branches`: the branch asked for (403 elsewhere), else every
/// branch for an owner (null = no narrowing) or the person's own.
List<String>? _orgReadBranches(MockRequest req, MockDb db, String orgId) {
  if (!req.persona.isPlatform && req.persona.orgId != orgId) {
    req.fail(MockResponse.forbidden('Not your org'));
  }
  final asked = req.q('branch_id');
  if (asked != null) {
    req.requireBranch(asked);
    final b = db['branches'].find(asked);
    if (b == null || b['org_id'] != orgId) {
      req.fail(MockResponse.forbidden('Branch belongs to a different org'));
    }
    return [asked];
  }
  final mine = req.persona.branchIds;
  if (mine == null) return null;
  return [
    for (final b in _orgBranchIds(db, orgId))
      if (mine.contains(b)) b,
  ];
}

// ── loyalty ──────────────────────────────────────────────────────────────

/// One loyalty member: when they enrolled and their birthday.
class LoyaltyMember {
  const LoyaltyMember(this.id, this.enrolledAt, this.birthMonth, this.birthDay);

  final String id;
  final DateTime enrolledAt;
  final int? birthMonth;
  final int? birthDay;
}

/// One signed ledger row (`loyalty_transactions`): `earn` +1 a visit,
/// `redeem` −7 for the reward.
class LoyaltyTxn {
  const LoyaltyTxn(this.memberId, this.branchId, this.at, this.kind, this.points);

  final String memberId;
  final String branchId;
  final DateTime at;
  final String kind;
  final int points;
}

/// A sent nudge (`loyalty_winbacks` / `loyalty_birthday_greetings`).
class LoyaltyNudge {
  const LoyaltyNudge(this.campaign, this.memberId, this.sentAt);

  final String campaign;
  final String memberId;
  final DateTime sentAt;
}

/// Visits a reward costs (Sabah runs a visits programme: "7 orders, a
/// free drink").
const int loyaltyRewardVisits = 7;

/// Sabah's programme currency (the members carry a visits balance).
const String loyaltyCurrency = 'visits';

/// The org's members (every seed customer is Sabah's). Most joined when
/// they first came in; about one in seven joined the programme in the
/// last four weeks.
List<LoyaltyMember> loyaltyMembers(MockDb db, String orgId) {
  if (orgId != SeedIds.sabahOrg) return const [];
  final now = MockSeed.now;
  return [
    for (final c in db['customers'].rows)
      if (c['is_member'] == true)
        () {
          final id = c['id']! as String;
          final created = DateTime.parse(c['created_at']! as String);
          final rng = MockRandom('reports:loyalty:enrolled:$id');
          final recent = rng.chance(0.15);
          final enrolled = recent
              ? now.subtract(
                  Duration(days: 1 + rng.nextInt(27), hours: rng.nextInt(10)),
                )
              : created;
          return LoyaltyMember(
            id,
            enrolled,
            c['birth_month'] as int?,
            c['birth_day'] as int?,
          );
        }(),
  ];
}

/// The ledger, oldest first: an earn for every sold order a member placed
/// after enrolling, and a redemption on every seventh visit.
List<LoyaltyTxn> loyaltyLedger(MockDb db, List<LoyaltyMember> members) {
  final byId = {for (final m in members) m.id: m};
  final visits = <String, int>{};
  final out = <LoyaltyTxn>[];
  final orders = [
    for (final o in db['orders'].rows)
      if (o['customer_id'] is String && isSold(o)) o,
  ]..sort((a, b) => '${a['created_at']}'.compareTo('${b['created_at']}'));
  for (final o in orders) {
    final m = byId[o['customer_id']];
    if (m == null) continue;
    final at = DateTime.parse(o['created_at']! as String);
    if (at.isBefore(m.enrolledAt)) continue;
    final branch = o['branch_id']! as String;
    out.add(LoyaltyTxn(m.id, branch, at, 'earn', 1));
    final n = (visits[m.id] ?? 0) + 1;
    visits[m.id] = n;
    if (n % loyaltyRewardVisits == 0) {
      out.add(
        LoyaltyTxn(
          m.id,
          branch,
          at.add(const Duration(minutes: 1)),
          'redeem',
          -loyaltyRewardVisits,
        ),
      );
    }
  }
  return out;
}

/// Members who redeemed before the seeded history began (lifetime figure).
bool _redeemedBefore(LoyaltyMember m) =>
    m.enrolledAt.isBefore(MockSeed.now.subtract(const Duration(days: 120))) &&
    MockRandom('reports:loyalty:redeemed:${m.id}').chance(0.4);

/// The nudges sent: a win-back to about one member in eight, and a
/// birthday greeting at 09:00 Cairo on each member's birthday this year
/// (up to today).
List<LoyaltyNudge> loyaltyNudges(List<LoyaltyMember> members) {
  final now = MockSeed.now;
  final out = <LoyaltyNudge>[];
  for (final m in members) {
    final rng = MockRandom('reports:loyalty:winback:${m.id}');
    if (rng.chance(0.12)) {
      final sent = MockClock.fromCairo(
        now.year,
        now.month,
        now.day,
        11,
      ).subtract(Duration(days: 2 + rng.nextInt(40)));
      out.add(LoyaltyNudge('winback', m.id, sent));
    }
    final bm = m.birthMonth, bd = m.birthDay;
    if (bm != null && bd != null) {
      final sent = MockClock.fromCairo(now.year, bm, bd, 9);
      if (!sent.isAfter(now)) out.add(LoyaltyNudge('birthday', m.id, sent));
    }
  }
  return out;
}

double _ratio(int num, int den) => den == 0 ? 0.0 : num / den;

bool _inRange(DateTime at, DateTime from, DateTime to) =>
    !at.isBefore(from) && at.isBefore(to);

/// `GET /loyalty/behavior` over [branches] (null = every branch).
LoyaltyBehavior loyaltyBehavior(
  MockDb db, {
  required String orgId,
  required List<String>? branches,
  required DateTime from,
  required DateTime to,
}) {
  final members = loyaltyMembers(db, orgId);
  final ledger = loyaltyLedger(db, members);
  final byId = {for (final m in members) m.id: m};
  var earned = 0, redeemed = 0;
  final earnVisits = <String, int>{};
  final active = <String>{};
  for (final t in ledger) {
    if (branches != null && !branches.contains(t.branchId)) continue;
    if (!_inRange(t.at, from, to)) continue;
    active.add(t.memberId);
    if (t.kind == 'earn') {
      earned += t.points;
      earnVisits[t.memberId] = (earnVisits[t.memberId] ?? 0) + 1;
    } else {
      redeemed += -t.points;
    }
  }
  final everRedeemed = {
    for (final t in ledger)
      if (t.kind == 'redeem') t.memberId,
    for (final m in members)
      if (_redeemedBefore(m)) m.id,
  };
  final repeat = earnVisits.values.where((v) => v >= 2).length;
  final oneTime = earnVisits.values.where((v) => v == 1).length;
  final newActive = active
      .where((id) => !byId[id]!.enrolledAt.isBefore(from))
      .length;
  return LoyaltyBehavior(
    from: from,
    to: to,
    totalMembers: members.length,
    activeMembers: active.length,
    activeMemberRate: _ratio(active.length, members.length),
    membersEverRedeemed: everRedeemed.length,
    redemptionRate: _ratio(everRedeemed.length, members.length),
    redemptionRatio: _ratio(redeemed, earned),
    repeatMembers: repeat,
    oneTimeMembers: oneTime,
    repeatVisitRate: _ratio(repeat, repeat + oneTime),
    newMembersActive: newActive,
    returningMembersActive: active.length - newActive,
    newMemberShare: _ratio(newActive, active.length),
  );
}

/// `GET /loyalty/campaign-effectiveness`: org-wide (the nudges are not
/// branch-scoped), nudges sent in [from, to).
CampaignEffectiveness loyaltyCampaigns(
  MockDb db, {
  required String orgId,
  required DateTime from,
  required DateTime to,
}) {
  final members = loyaltyMembers(db, orgId);
  final earns = <String, List<DateTime>>{};
  for (final t in loyaltyLedger(db, members)) {
    if (t.kind == 'earn') (earns[t.memberId] ??= []).add(t.at);
  }
  CampaignEffectivenessRow row(String campaign) {
    var sent = 0, back = 0;
    for (final n in loyaltyNudges(members)) {
      if (n.campaign != campaign || !_inRange(n.sentAt, from, to)) continue;
      sent++;
      final until = n.sentAt.add(const Duration(days: 30));
      if ((earns[n.memberId] ?? const []).any(
        (at) => at.isAfter(n.sentAt) && !at.isAfter(until),
      )) {
        back++;
      }
    }
    return CampaignEffectivenessRow(
      campaign: campaign,
      sent: sent,
      returnedWithin30d: back,
      returnRate: _ratio(back, sent),
    );
  }

  return CampaignEffectiveness(
    from: from,
    to: to,
    campaigns: [row('winback'), row('birthday')],
  );
}

/// The instant a local week starts in [zone] (Saturday 00:00,
/// `tz::WEEK_START`).
DateTime loyaltyWeekStart(DateTime at, String zone) {
  final w = inZone(at, zone);
  // Dart: Monday 1 … Sunday 7; days back to Saturday.
  final back = (w.weekday + 1) % 7;
  return wallClock(zone, w.year, w.month - 1, w.day - back);
}

/// `GET /loyalty/liability-trend`: each local week's net change, org-wide
/// (the ledger query names no branch), weeks cut in the scope's zone.
LiabilityTrend loyaltyLiability(
  MockDb db, {
  required String orgId,
  required String zone,
  required DateTime from,
  required DateTime to,
}) {
  final members = loyaltyMembers(db, orgId);
  final weeks = <DateTime, int>{};
  for (final t in loyaltyLedger(db, members)) {
    if (!_inRange(t.at, from, to)) continue;
    final w = loyaltyWeekStart(t.at, zone);
    weeks[w] = (weeks[w] ?? 0) + t.points;
  }
  final keys = weeks.keys.toList()..sort();
  return LiabilityTrend(
    from: from,
    to: to,
    currency: loyaltyCurrency,
    points: [
      for (final k in keys) LiabilityTrendPoint(week: k, outstanding: weeks[k]!),
    ],
  );
}

void _registerLoyalty(MockServer server, MockDb db) {
  /// `scope_org` + the capability + `org_read_branches` + the range check.
  ({String orgId, List<String>? branches, DateTime from, DateTime to}) gate(
    MockRequest req,
  ) {
    final asked = req.q('branch_id');
    String orgId;
    if (asked != null) {
      final b = db['branches'].find(asked);
      if (b == null) req.notFound('Branch not found');
      orgId = b['org_id']! as String;
    } else {
      final o = req.orgId;
      if (o == null) req.badRequest('Pick an organisation first');
      orgId = o;
    }
    req.requireCap('loyalty.members.list', branchId: asked);
    final branches = _orgReadBranches(req, db, orgId);
    final to = req.qDateTime('to') ?? req.now;
    final from = req.qDateTime('from') ?? to.subtract(const Duration(days: 30));
    if (!from.isBefore(to)) req.badRequest('`from` must be before `to`');
    return (orgId: orgId, branches: branches, from: from, to: to);
  }

  server.on('GET', '/loyalty/behavior', (req) {
    final g = gate(req);
    return MockResponse.ok(
      loyaltyBehavior(
        db,
        orgId: g.orgId,
        branches: g.branches,
        from: g.from,
        to: g.to,
      ),
    );
  });

  server.on('GET', '/loyalty/campaign-effectiveness', (req) {
    final g = gate(req);
    return MockResponse.ok(
      loyaltyCampaigns(db, orgId: g.orgId, from: g.from, to: g.to),
    );
  });

  server.on('GET', '/loyalty/liability-trend', (req) {
    final g = gate(req);
    return MockResponse.ok(
      loyaltyLiability(
        db,
        orgId: g.orgId,
        zone: lisScopeZone(db, req.q('branch_id'), g.orgId),
        from: g.from,
        to: g.to,
      ),
    );
  });
}

// ── inventory ────────────────────────────────────────────────────────────

/// One stock movement out of a branch: waste (`reason` a waste code) or a
/// stock-count shortfall (`reason` a variance code, null = unexplained).
class StockLoss {
  const StockLoss(
    this.branchId,
    this.ingredient,
    this.reason,
    this.at,
    this.qty,
  );

  final String branchId;
  final String ingredient;
  final String? reason;
  final DateTime at;

  /// Positive: how much left the shelf, in the ingredient's unit.
  final double qty;
}

/// What each branch throws away, by ingredient and waste reason, with a
/// typical quantity per event (scaled to the branch).
const List<(String, String, double)> _wastePlan = [
  ('whole_milk', 'expired', 1.5),
  ('strawberries', 'spoiled', 0.8),
  ('croissant_dough', 'overproduction', 6),
  ('cups_12oz', 'damaged', 12),
  ('espresso_beans', 'order_cancelled', 0.12),
  ('oat_milk', 'refund', 0.6),
  ('avocados', 'spoiled', 3),
  ('chai', 'expired', 0.5),
  ('cream', 'other', 0.4),
  ('butter', 'theft', 0.25),
];

/// What the weekly counts come up short on, by variance reason (null =
/// nobody gave one).
const List<(String, String?, double)> _shrinkPlan = [
  ('espresso_beans', 'miscount', 0.3),
  ('whole_milk', 'spoilage', 2),
  ('cups_12oz', 'breakage', 15),
  ('vanilla_syrup', null, 0.2),
  ('chocolate_sauce', 'theft', 0.15),
  ('oranges', 'supplier_short', 1.5),
  ('lids', 'transfer_error', 20),
  ('chai', null, 0.3),
];

/// Waste over the last four weeks at every Sabah branch.
final List<StockLoss> inventoryWaste = () {
  final today = MockClock.startOfCairoDay(MockSeed.now);
  final out = <StockLoss>[];
  for (final b in SeedIds.sabahBranches) {
    final scale = branchScale(b);
    for (final (ing, reason, base) in _wastePlan) {
      final rng = MockRandom('reports:waste:$b:$ing:$reason');
      final events = 1 + rng.nextInt(3);
      for (var e = 0; e < events; e++) {
        final at = today
            .subtract(Duration(days: 1 + rng.nextInt(27)))
            .add(Duration(hours: 8 + rng.nextInt(12), minutes: rng.nextInt(60)));
        final qty = _round(base * scale * (0.6 + rng.nextDouble() * 0.8), 2);
        out.add(StockLoss(b, ing, reason, at, qty));
      }
    }
  }
  return List<StockLoss>.unmodifiable(out);
}();

/// Stock-count shortfalls from the weekly counts (3, 10, 17 and 24 days
/// ago, after closing) at every Sabah branch.
final List<StockLoss> inventoryShrinkage = () {
  final today = MockClock.startOfCairoDay(MockSeed.now);
  final out = <StockLoss>[];
  for (final b in SeedIds.sabahBranches) {
    final scale = branchScale(b);
    for (final daysAgo in const [3, 10, 17, 24]) {
      final at = today
          .subtract(Duration(days: daysAgo))
          .add(const Duration(hours: 22));
      for (final (ing, reason, base) in _shrinkPlan) {
        final rng = MockRandom('reports:count:$b:$daysAgo:$ing');
        if (!rng.chance(0.5)) continue;
        final qty = _round(base * scale * (0.5 + rng.nextDouble()), 2);
        out.add(StockLoss(b, ing, reason, at, qty));
      }
    }
  }
  return List<StockLoss>.unmodifiable(out);
}();

bool _within(DateTime at, DateTime? from, DateTime? to) =>
    (from == null || !at.isBefore(from)) && (to == null || !at.isAfter(to));

/// The value of [qty] of [ingredient] at its cost; null when unknown.
int? _valueOf(String ingredient, double qty) {
  final cost = reportIngredient(ingredient).unitCost;
  return cost == null ? null : (qty * cost).round();
}

/// Losses grouped by (reason, ingredient), largest quantity first.
List<(String, ReportIngredient, double, int?)> _groupLosses(
  Iterable<StockLoss> losses,
  String Function(StockLoss) reasonOf,
) {
  final sums = <(String, String), double>{};
  for (final l in losses) {
    final k = (reasonOf(l), l.ingredient);
    sums[k] = (sums[k] ?? 0) + l.qty;
  }
  final rows = [
    for (final e in sums.entries)
      (
        e.key.$1,
        reportIngredient(e.key.$2),
        _round(e.value, 2),
        _valueOf(e.key.$2, e.value),
      ),
  ]..sort((a, b) => b.$3.compareTo(a.$3));
  return rows;
}

/// `GET …/waste-report`.
List<WasteReportRow> inventoryWasteReport(
  List<String> branches, {
  DateTime? from,
  DateTime? to,
}) => [
  for (final (reason, ing, qty, value) in _groupLosses(
    inventoryWaste.where(
      (w) => branches.contains(w.branchId) && _within(w.at, from, to),
    ),
    (l) => l.reason ?? 'other',
  ))
    WasteReportRow(
      reason: reason,
      orgIngredientId: ing.id,
      ingredientName: ing.name,
      unit: ing.unit,
      wasteQty: qty,
      wasteValue: value,
    ),
];

/// `GET …/shrinkage`.
List<ShrinkageRow> inventoryShrinkageReport(
  List<String> branches, {
  DateTime? from,
  DateTime? to,
}) => [
  for (final (reason, ing, qty, value) in _groupLosses(
    inventoryShrinkage.where(
      (w) => branches.contains(w.branchId) && _within(w.at, from, to),
    ),
    (l) => l.reason ?? 'unexplained',
  ))
    ShrinkageRow(
      reason: reason,
      orgIngredientId: ing.id,
      ingredientName: ing.name,
      unit: ing.unit,
      shrinkageQty: qty,
      shrinkageValue: value,
    ),
];

/// Days of selling at a branch inside [from, to]: the seeded history is
/// the last 30 days up to now; part days count in part.
double _sellingDays(DateTime? from, DateTime? to) {
  final now = MockSeed.now;
  final start0 = now.subtract(const Duration(days: MockSeed.historyDays));
  final start = from == null || from.isBefore(start0) ? start0 : from;
  final end = to == null || to.isAfter(now) ? now : to;
  final minutes = end.difference(start).inMinutes;
  return minutes <= 0 ? 0 : minutes / (24 * 60);
}

/// `GET …/consumption`: what the sales used (each ingredient's daily use at
/// the branch's size) plus what was thrown away, largest first.
List<ConsumptionRow> inventoryConsumption(
  List<String> branches, {
  DateTime? from,
  DateTime? to,
}) {
  final days = _sellingDays(from, to);
  final rows = <ConsumptionRow>[];
  for (final ing in reportIngredients) {
    var qty = 0.0;
    for (final b in branches) {
      qty += ing.dailyUse * branchScale(b) * days;
    }
    for (final w in inventoryWaste) {
      if (w.ingredient == ing.key &&
          branches.contains(w.branchId) &&
          _within(w.at, from, to)) {
        qty += w.qty;
      }
    }
    qty = _round(qty, 2);
    if (qty <= 0) continue;
    rows.add(
      ConsumptionRow(
        orgIngredientId: ing.id,
        ingredientName: ing.name,
        unit: ing.unit,
        consumedQty: qty,
        consumedValue: _valueOf(ing.key, qty),
      ),
    );
  }
  rows.sort((a, b) => b.consumedQty.compareTo(a.consumedQty));
  return rows;
}

/// A purchase order received: its supplier, branch, and when it was
/// created and received (its lines' first order, last receipt).
typedef ReceivedPo = ({
  String id,
  String supplier,
  String branchId,
  DateTime createdAt,
  DateTime receivedAt,
});

/// Every received purchase order of the area seed's deliveries.
final List<ReceivedPo> receivedPurchaseOrders = () {
  final byPo = <String, List<ReportDelivery>>{};
  for (final d in reportDeliveries) {
    (byPo[d.poId] ??= []).add(d);
  }
  return [
    for (final e in byPo.entries)
      (
        id: e.key,
        supplier: e.value.first.supplier,
        branchId: e.value.first.branchId,
        createdAt: e.value
            .map((d) => d.orderedAt)
            .reduce((a, b) => a.isBefore(b) ? a : b),
        receivedAt: e.value
            .map((d) => d.receivedAt)
            .reduce((a, b) => a.isAfter(b) ? a : b),
      ),
  ];
}();

double _leadDays(ReceivedPo p) =>
    p.receivedAt.difference(p.createdAt).inSeconds / 86400.0;

/// `GET …/po-lead-time`: received orders in the window, by supplier
/// (slowest first), and the overall average (0 with none).
PoLeadTimeReport inventoryPoLeadTime(
  List<String> branches, {
  DateTime? from,
  DateTime? to,
}) {
  final pos = [
    for (final p in receivedPurchaseOrders)
      if (branches.contains(p.branchId) && _within(p.receivedAt, from, to)) p,
  ];
  final bySupplier = <String, List<ReceivedPo>>{};
  for (final p in pos) {
    (bySupplier[p.supplier] ??= []).add(p);
  }
  double avg(List<ReceivedPo> ps) =>
      ps.fold<double>(0, (s, p) => s + _leadDays(p)) / ps.length;
  final rows = [
    for (final e in bySupplier.entries)
      PoLeadTimeRow(
        supplierId: reportSupplier(e.key).id,
        supplierName: reportSupplier(e.key).name,
        ordersReceived: e.value.length,
        avgLeadTimeDays: avg(e.value),
      ),
  ]..sort((a, b) => b.avgLeadTimeDays.compareTo(a.avgLeadTimeDays));
  return PoLeadTimeReport(
    from: from,
    to: to,
    overallAvgDays: pos.isEmpty ? 0.0 : avg(pos),
    bySupplier: rows,
  );
}

/// A branch's reorder point for [ing]: the catalog's, at the branch's size.
double reorderPoint(String branchId, ReportIngredient ing) =>
    _round(ing.parMin * branchScale(branchId));

/// `GET …/low-stock`: every branch-ingredient at or under its reorder
/// point, by branch name then ingredient name.
List<LowStockRow> inventoryLowStock(MockDb db, List<String> branches) {
  final rows = <LowStockRow>[];
  for (final b in branches) {
    final name = '${db['branches'].find(b)?['name'] ?? ''}';
    for (final ing in reportIngredients) {
      final par = reorderPoint(b, ing);
      final have = onHand(b, ing.key);
      if (par <= 0 || have > par) continue;
      final parMax = _round(ing.parMax * branchScale(b));
      final sup = reportSupplier(ing.supplier);
      rows.add(
        LowStockRow(
          branchId: b,
          branchName: name,
          orgIngredientId: ing.id,
          ingredientName: ing.name,
          unit: ing.unit,
          onHand: have,
          parMin: par,
          parMax: parMax,
          suggestedQty: _round(parMax - have < 0 ? 0 : parMax - have),
          supplierId: sup.id,
          supplierName: sup.name,
        ),
      );
    }
  }
  rows.sort((a, b) {
    final c = a.branchName.compareTo(b.branchName);
    return c != 0 ? c : a.ingredientName.compareTo(b.ingredientName);
  });
  return rows;
}

void _registerInventory(MockServer server, MockDb db) {
  List<String> branchScope(MockRequest req) =>
      reportBranchIds(req, req.param('branch_id'));

  List<String> orgScope(MockRequest req) {
    final orgId = req.param('org_id');
    _requireOrg(req, orgId);
    return _orgBranchIds(db, orgId);
  }

  void read(
    String report,
    Object Function(MockRequest req, List<String> branches) answer,
  ) {
    server.on('GET', '/reports/branches/{branch_id}/$report', (req) {
      req.requireCap('inventory.read');
      return MockResponse.ok(answer(req, branchScope(req)));
    });
    server.on('GET', '/reports/orgs/{org_id}/$report', (req) {
      req.requireCap('inventory.read');
      return MockResponse.ok(answer(req, orgScope(req)));
    });
  }

  read(
    'consumption',
    (req, b) => inventoryConsumption(
      b,
      from: req.qDateTime('from'),
      to: req.qDateTime('to'),
    ),
  );
  read(
    'shrinkage',
    (req, b) => inventoryShrinkageReport(
      b,
      from: req.qDateTime('from'),
      to: req.qDateTime('to'),
    ),
  );
  read(
    'waste-report',
    (req, b) => inventoryWasteReport(
      b,
      from: req.qDateTime('from'),
      to: req.qDateTime('to'),
    ),
  );
  read('low-stock', (req, b) => inventoryLowStock(db, b));

  // PO lead time is purchasing's (`require_purchasing_read`).
  server.on('GET', '/reports/branches/{branch_id}/po-lead-time', (req) {
    final id = req.param('branch_id');
    req.requireCap(
      'purchasing.orders.read',
      branchId: id == allBranchesId ? null : id,
    );
    return MockResponse.ok(
      inventoryPoLeadTime(
        branchScope(req),
        from: req.qDateTime('from'),
        to: req.qDateTime('to'),
      ),
    );
  });
  server.on('GET', '/reports/orgs/{org_id}/po-lead-time', (req) {
    req.requireCap('purchasing.orders.read');
    final orgId = req.param('org_id');
    // `org_read_branches(…, None)`: a manager reads their own branches.
    final branches = [
      for (final b in orgScope(req))
        if (req.persona.seesBranch(b)) b,
    ];
    return MockResponse.ok(
      inventoryPoLeadTime(
        orgId == SeedIds.sabahOrg ? branches : const [],
        from: req.qDateTime('from'),
        to: req.qDateTime('to'),
      ),
    );
  });
}

// ── staff discipline ─────────────────────────────────────────────────────

/// A person's department, by job title (the team area's departments; new
/// waiters have not been placed in one yet: "Unassigned").
({String id, String name})? disciplineDepartment(MockRow employee) {
  final org = employee['org_id'] == SeedIds.nakhlaOrg ? 'nakhla' : 'sabah';
  final key = switch (employee['job_title']) {
    'Branch manager' || 'Shift lead' => 'management',
    'Barista' => 'bar',
    'Cashier' => 'front',
    'Chef' => 'kitchen',
    'Head baker' || 'Baker' => 'bakery',
    _ => null,
  };
  if (key == null) return null;
  final name = switch (key) {
    'management' => 'Management',
    'bar' => 'Bar',
    'front' => org == 'nakhla' ? 'Counter' : 'Front of house',
    'kitchen' => 'Kitchen',
    _ => 'Bakery',
  };
  return (id: mockUuid('department:$org:$key'), name: name);
}

/// One day's attendance record (`attendance_records`).
typedef AttendanceDay = ({
  String employeeId,
  String branchId,
  String date,
  String status,
  int lateMinutes,
  String? covers,
  String? coverStatus,
});

/// How far back the seeded attendance goes.
const int disciplineHistoryDays = 90;

/// The attendance of [orgId]'s payroll staff on every day of the last
/// [disciplineHistoryDays] up to yesterday: a weekly day off each, about
/// one late day in nine, one absence in thirty; a colleague at the same
/// branch covers some absences (confirmed, pending or turned down).
List<AttendanceDay> disciplineAttendance(MockDb db, String orgId) {
  final staff = [
    for (final e in db['employees'].rows)
      if (e['org_id'] == orgId &&
          e['on_payroll'] == true &&
          e['employment_status'] == 'active' &&
          (e['branch_ids'] as List?)?.isNotEmpty == true)
        e,
  ];
  int dayOff(int i) => i % 7;
  final today = MockClock.startOfCairoDay(MockSeed.now);
  final out = <AttendanceDay>[];
  for (var back = disciplineHistoryDays; back >= 1; back--) {
    final day = today.subtract(Duration(days: back));
    final date = MockClock.cairoDate(day.add(const Duration(hours: 12)));
    final dow = DateTime.parse(date).weekday % 7;
    for (final (i, e) in staff.indexed) {
      if (dayOff(i) == dow) continue;
      final id = e['id']! as String;
      final branch = (e['branch_ids']! as List).first as String;
      final rng = MockRandom('reports:attendance:$id:$date');
      final r = rng.nextDouble();
      final status = r < 0.034 ? 'absent' : (r < 0.145 ? 'late' : 'present');
      out.add((
        employeeId: id,
        branchId: branch,
        date: date,
        status: status,
        lateMinutes: status == 'late' ? 4 + rng.nextInt(38) : 0,
        covers: null,
        coverStatus: null,
      ));
      if (status != 'absent' || !rng.chance(0.6)) continue;
      // The next colleague at the branch who is not off that day.
      for (var k = 1; k < staff.length; k++) {
        final j = (i + k) % staff.length;
        final c = staff[j];
        if ((c['branch_ids']! as List).first != branch || dayOff(j) == dow) {
          continue;
        }
        final s = rng.nextDouble();
        out.add((
          employeeId: c['id']! as String,
          branchId: branch,
          date: date,
          status: 'present',
          lateMinutes: 0,
          covers: id,
          coverStatus: s < 0.7 ? 'confirmed' : (s < 0.9 ? 'pending' : 'rejected'),
        ));
        break;
      }
    }
  }
  return out;
}

/// `GET /staff/discipline-report` over the dates [from]…[to] at
/// [branches] (null = every branch): per person, days (not rows) present,
/// late and absent, late minutes and covers, ranked within the department
/// by absences, then lates, then late minutes (SQL `RANK`).
List<DisciplineRow> disciplineRows(
  MockDb db, {
  required String orgId,
  required List<String>? branches,
  required String from,
  required String to,
}) {
  final days = disciplineAttendance(db, orgId);
  bool inDates(String d) => d.compareTo(from) >= 0 && d.compareTo(to) <= 0;
  final mine = <String, List<AttendanceDay>>{};
  for (final a in days) {
    if (!inDates(a.date)) continue;
    if (branches != null && !branches.contains(a.branchId)) continue;
    (mine[a.employeeId] ??= []).add(a);
  }
  final rows = <DisciplineRow>[];
  for (final e in mine.entries) {
    final emp = db['employees'].find(e.key)!;
    final own = e.value.where((a) => a.covers == null);
    Set<String> dates(String status) => {
      for (final a in own)
        if (a.status == status) a.date,
    };
    final dept = disciplineDepartment(emp);
    rows.add(
      DisciplineRow(
        employeeId: e.key,
        employeeName: '${emp['name']}',
        departmentId: dept?.id,
        departmentName: dept?.name,
        presentDays: dates('present').length,
        lateDays: dates('late').length,
        absentDays: dates('absent').length,
        totalLateMinutes: own.fold<int>(0, (s, a) => s + a.lateMinutes),
        coversGiven: e.value
            .where((a) => a.covers != null && a.coverStatus == 'confirmed')
            .length,
        coversPending: e.value
            .where((a) => a.covers != null && a.coverStatus == 'pending')
            .length,
        coveredByOthers: days
            .where(
              (a) =>
                  a.covers == e.key &&
                  inDates(a.date) &&
                  a.coverStatus != 'rejected',
            )
            .length,
        rankInDepartment: 0,
      ),
    );
  }
  int cmp(DisciplineRow a, DisciplineRow b) {
    var c = a.absentDays.compareTo(b.absentDays);
    if (c == 0) c = a.lateDays.compareTo(b.lateDays);
    if (c == 0) c = a.totalLateMinutes.compareTo(b.totalLateMinutes);
    return c;
  }

  DisciplineRow ranked(DisciplineRow r, int rank) => DisciplineRow(
    employeeId: r.employeeId,
    employeeName: r.employeeName,
    departmentId: r.departmentId,
    departmentName: r.departmentName,
    presentDays: r.presentDays,
    lateDays: r.lateDays,
    absentDays: r.absentDays,
    totalLateMinutes: r.totalLateMinutes,
    coversGiven: r.coversGiven,
    coversPending: r.coversPending,
    coveredByOthers: r.coveredByOthers,
    rankInDepartment: rank,
  );

  final out = <DisciplineRow>[];
  final byDept = <String?, List<DisciplineRow>>{};
  for (final r in rows) {
    (byDept[r.departmentId] ??= []).add(r);
  }
  for (final group in byDept.values) {
    group.sort(cmp);
    for (final r in group) {
      out.add(ranked(r, 1 + group.where((o) => cmp(o, r) < 0).length));
    }
  }
  out.sort((a, b) {
    final an = a.departmentName, bn = b.departmentName;
    if ((an == null) != (bn == null)) return an == null ? 1 : -1;
    var c = (an ?? '').compareTo(bn ?? '');
    if (c == 0) c = a.rankInDepartment.compareTo(b.rankInDepartment);
    if (c == 0) {
      c = a.employeeName.toLowerCase().compareTo(b.employeeName.toLowerCase());
    }
    return c;
  });
  return out;
}

final RegExp _date = RegExp(r'^\d{4}-\d{2}-\d{2}$');

void _registerDiscipline(MockServer server, MockDb db) {
  server.on('GET', '/staff/discipline-report', (req) {
    final orgId = req.orgId;
    if (orgId == null) req.badRequest('Pick an organisation first');
    final asked = req.q('branch_id');
    req.requireCap('hr.attendance.read', branchId: asked);
    final branches = _orgReadBranches(req, db, orgId);
    final from = req.q('from'), to = req.q('to');
    if (from == null || to == null || !_date.hasMatch(from) || !_date.hasMatch(to)) {
      req.badRequest('Query deserialize error: `from` and `to` are dates');
    }
    final f = DateTime.parse(from), t = DateTime.parse(to);
    if (t.isBefore(f)) {
      req.badRequest('`to` is before `from`', code: 'RANGE_BACKWARDS');
    }
    if (t.difference(f).inDays > 400) {
      req.badRequest(
        'Range too wide — at most 400 days per request',
        code: 'RANGE_TOO_WIDE',
      );
    }
    return MockResponse.ok(
      DisciplineReport(
        from: from,
        to: to,
        rows: disciplineRows(
          db,
          orgId: orgId,
          branches: branches,
          from: from,
          to: to,
        ),
      ),
    );
  });
}
