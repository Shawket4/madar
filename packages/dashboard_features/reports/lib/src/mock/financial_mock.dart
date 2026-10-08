/// The mock backend for Financial (REP-FIN): menu-margin ledger, decisions,
/// margin targets, repricing, sales timeseries / peak hours / peak days,
/// channel breakdown, valuation, catalog, supplier spend and material cost
/// trend, plus the org's users (the Decisions log names who decided).
///
/// Handlers behave like the backend (MadarRust `insights/handlers.rs`,
/// `reports/handlers.rs`, `users/handlers.rs`): the same capability checks,
/// branch narrowing, validation refusals (400 in the backend's envelope) and
/// state that persists across calls (a decision suppresses its flag; a new
/// target re-ranks the ledger). Figures come from the core seed's orders and
/// the area seed (`../area_seed.dart`), so Revenue/Channel agree with
/// Operations, Legal and Tills to the piastre.
library;

import 'dart:math' as math;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart' show allBranchesId;

import '../area_seed.dart';

// ── tables ──────────────────────────────────────────────────────────────

/// Margin targets: `{id, org_id, branch_id (null = org default), target_pct}`.
const String finTargetsTable = 'insights_margin_targets';

/// The decision log: [DecisionOut] rows plus `org_id`.
const String finDecisionsTable = 'insights_decisions';

/// The backend's built-in default target (`DEFAULT_TARGET_PCT`).
const double finBuiltinTargetPct = 60;

/// Sabah's seeded org default and Zamalek's override.
const double finSeedOrgTargetPct = 68;
const double finSeedZamalekTargetPct = 72;

const int _minSignalQty = 5;
const double _priceBufferPct = 5;
const int _priceRound = 100;
const int _baselineDays = 28;

/// Requests carrying `X-Madar-Export: 1` allowed per person per minute
/// (`MADAR_EXPORT_MAX_PER_MINUTE`, REP-ALL-027).
const int finExportPerMinute = 10;

// ── the menu as the ledger reads it ─────────────────────────────────────

final Map<String, SeedItem> _itemById = {
  for (final m in seedMenu) MockSeed.menuItemId(m.key): m,
};

/// The SKU retired from the active menu: its historical sales show as an
/// "Off menu" row (Turkish coffee's double, dropped in September).
const Set<(String, String)> finOffMenuSkus = {('turkish', 'Double')};

/// One sellable SKU of the catalog: item key + the wire size label.
typedef FinSku = (String item, String size);

/// Every active SKU, in menu order.
final List<FinSku> finCatalogSkus = [
  for (final m in seedMenu)
    for (var i = 0; i < m.sizes.length; i++)
      if (!finOffMenuSkus.contains((m.key, reportSizeLabel(m, i))))
        (m.key, reportSizeLabel(m, i)),
];

/// The SKU's price in piastres.
int finSkuPrice(FinSku sku) {
  final m = seedMenuItem(sku.$1)!;
  final s = m.sizes.length == 1
      ? m.sizes.first
      : m.sizes.firstWhere((x) => x.$1 == sku.$2);
  return s.$2 * 100;
}

/// Today's recipe costs against the snapshot taken at sale time: coffee
/// drinks carry the espresso-bean and milk rises, avocado toast the avocado
/// rises (the material cost trend's three streaks).
double _todayFactor(SeedItem m) => switch (m.category) {
  'hot' || 'iced' => 1.06,
  _ when m.key == 'avocado' => 1.12,
  _ => 1.0,
};

/// One unit's cost in piastres under [current] (today's) or the snapshot
/// basis; null when the recipe is incomplete.
int? finUnitCost(FinSku sku, {bool current = false}) {
  final base = menuUnitCost(sku.$1, sku.$2);
  if (base == null) return null;
  if (!current) return base;
  final m = seedMenuItem(sku.$1)!;
  return ((base * _todayFactor(m)) / 25).round() * 25;
}

/// Recent cost spikes per SKU (the `cost_spike` evidence).
Map<FinSku, Map<String, Object?>> get _costSpikes => {
  ('avocado', 'one_size'): {
    'ingredient': reportIngredient('avocados').name,
    'pct': (reportIngredient('avocados').streakPct * 10).round() / 10,
  },
  ('latte', 'Regular'): {
    'ingredient': reportIngredient('whole_milk').name,
    'pct': (reportIngredient('whole_milk').streakPct * 10).round() / 10,
  },
};

// ── order lines ─────────────────────────────────────────────────────────

class _Line {
  const _Line(this.sku, this.qty, this.total, this.addons);
  final FinSku sku;
  final int qty;
  final int total;
  final int addons;
}

final Map<String, List<_Line>> _lineCache = {};

List<_Line> _linesOf(String orderId) => _lineCache[orderId] ??= [
  for (final l in MockSeed.instance.orderItems(orderId))
    if (_itemById[l.menuItemId] case final m?)
      _Line(
        (m.key, l.sizeLabel ?? 'one_size'),
        l.quantity,
        l.lineTotal,
        l.addons.fold<int>(0, (s, a) => s + a.quantity),
      ),
];

int _int(Object? v) => v is num ? v.toInt() : 0;

/// The Cairo wall-clock fields of an order's `created_at`.
DateTime _wallOf(MockRow o) =>
    MockClock.wall(DateTime.parse(o['created_at']! as String));

// ── branch / org narrowing ──────────────────────────────────────────────

/// `resolve_report_branches`, plus the org the branches belong to.
List<String> _branches(MockRequest req, String branchId) =>
    reportBranchIds(req, branchId);

/// `require_org` / `require_org_access`: 403 for another org.
void _requireOrg(MockRequest req, String orgId) {
  if (req.persona.isPlatform) return;
  if (req.persona.orgId != orgId) {
    req.fail(MockResponse.forbidden('Not your org'));
  }
}

/// An org's branches (only Sabah carries this area's data).
List<String> _orgBranches(String orgId) =>
    orgId == SeedIds.sabahOrg ? SeedIds.sabahBranches : const [];

// ── margin targets ──────────────────────────────────────────────────────

MockTable _targets(MockDb db) {
  if (!db.hasTable(finTargetsTable)) {
    db.lazyTable(
      finTargetsTable,
      () => [
        {
          'id': 'org:${SeedIds.sabahOrg}',
          'org_id': SeedIds.sabahOrg,
          'branch_id': null,
          'target_pct': finSeedOrgTargetPct,
        },
        {
          'id': 'branch:${SeedIds.zamalek}',
          'org_id': SeedIds.sabahOrg,
          'branch_id': SeedIds.zamalek,
          'target_pct': finSeedZamalekTargetPct,
        },
      ],
    );
  }
  return db[finTargetsTable];
}

/// `resolve_target`: the branch override, else the org default, else the
/// built-in 60%.
(double, String) finResolveTarget(
  MockDb db,
  String orgId,
  String? branchScope,
) {
  final rows = _targets(db).where((r) => r['org_id'] == orgId);
  if (branchScope != null) {
    final b = rows.where((r) => r['branch_id'] == branchScope).firstOrNull;
    if (b != null) return ((b['target_pct']! as num).toDouble(), 'branch');
  }
  final o = rows.where((r) => r['branch_id'] == null).firstOrNull;
  if (o != null) return ((o['target_pct']! as num).toDouble(), 'org');
  return (finBuiltinTargetPct, 'default');
}

MarginTargets _targetsOf(MockDb db, String orgId) {
  final rows = _targets(db).where((r) => r['org_id'] == orgId);
  final org = rows.where((r) => r['branch_id'] == null).firstOrNull;
  return MarginTargets(
    orgDefaultPct: (org?['target_pct'] as num?)?.toDouble(),
    branches: [
      for (final r in rows)
        if (r['branch_id'] is String)
          BranchTarget(
            branchId: r['branch_id']! as String,
            targetPct: (r['target_pct']! as num).toDouble(),
          ),
    ],
    builtinDefaultPct: finBuiltinTargetPct,
  );
}

// ── SKU windows ─────────────────────────────────────────────────────────

class _SkuAgg {
  int qty = 0;
  int revenue = 0;
  int? cost = 0;
}

/// Quantity, line revenue and cost per SKU over the sold orders of
/// [branchIds] within [from]…[to], costed at the snapshot or today's basis.
Map<FinSku, _SkuAgg> _skuSales(
  MockDb db,
  Iterable<String> branchIds, {
  DateTime? from,
  DateTime? to,
  bool current = false,
}) {
  final out = <FinSku, _SkuAgg>{};
  for (final o in reportOrders(db, branchIds: branchIds, from: from, to: to)) {
    if (!isSold(o)) continue;
    for (final l in _linesOf(o['id']! as String)) {
      final a = out[l.sku] ??= _SkuAgg();
      a
        ..qty += l.qty
        ..revenue += l.total;
    }
  }
  for (final e in out.entries) {
    final unit = finUnitCost(e.key, current: current);
    e.value.cost = unit == null ? null : unit * e.value.qty;
  }
  return out;
}

/// A decision's measurement window (`sku_window`): quantity, revenue, cost,
/// margin, margin % and quantity per day.
Map<String, Object?> _window(
  MockDb db,
  Iterable<String> branchIds,
  FinSku sku,
  DateTime from,
  DateTime to,
) {
  final a = _skuSales(db, branchIds, from: from, to: to)[sku] ?? _SkuAgg();
  final days = math.max(0.01, to.difference(from).inSeconds / 86400);
  final margin = a.cost == null ? null : a.revenue - a.cost!;
  return {
    'window_days': (days * 10).round() / 10,
    'quantity': a.qty,
    'revenue': a.revenue,
    'cost': a.cost,
    'margin': margin,
    'margin_pct': margin != null && a.revenue > 0
        ? (margin / a.revenue * 1000).round() / 10
        : null,
    'qty_per_day': (a.qty / days * 100).round() / 100,
  };
}

// ── decisions ───────────────────────────────────────────────────────────

MockTable _decisions(MockDb db) {
  if (!db.hasTable(finDecisionsTable)) {
    db.lazyTable(finDecisionsTable, () => _seedDecisions(db));
  }
  return db[finDecisionsTable];
}

List<MockRow> _seedDecisions(MockDb db) {
  final now = MockSeed.now;
  MockRow d(
    String key,
    FinSku sku,
    String kind,
    String action,
    Duration ago,
    String by, {
    String? branch,
    Map<String, Object?> detail = const {},
  }) {
    final at = now.subtract(ago);
    final branches = branch == null ? SeedIds.sabahBranches : [branch];
    return {
      'id': mockUuid('insights:decision:$key'),
      'org_id': SeedIds.sabahOrg,
      'branch_id': branch,
      'menu_item_id': MockSeed.menuItemId(sku.$1),
      'size_label': sku.$2,
      'item_name': seedMenuItem(sku.$1)!.name,
      'signal_kind': kind,
      'action': action,
      'detail': detail,
      'baseline': _window(
        db,
        branches,
        sku,
        at.subtract(const Duration(days: _baselineDays)),
        at,
      ),
      'created_by': by,
      'created_at': at.toIso8601String(),
    };
  }

  // Newest first is the handler's job; the table keeps insertion order.
  return [
    d(
      'avocado-spike',
      ('avocado', 'one_size'),
      'cost_spike',
      'acted',
      const Duration(days: 29, hours: 2),
      SeedIds.owner,
      detail: {'ingredient': 'Avocados', 'pct': 9.4},
    ),
    d(
      'croissant-target',
      ('croissant', 'one_size'),
      'below_target',
      'acted',
      const Duration(days: 21, hours: 3),
      SeedIds.owner,
      detail: {'margin_pct': 58.3, 'target_pct': finSeedOrgTargetPct},
    ),
    d(
      'hibiscus-removal',
      ('hibiscus', 'one_size'),
      'removal_candidate',
      'dismissed',
      const Duration(days: 12, hours: 5),
      SeedIds.manager,
      branch: SeedIds.zamalek,
    ),
    d(
      'banana-target',
      ('banana_bread', 'one_size'),
      'below_target',
      'snoozed',
      const Duration(days: 2, hours: 4),
      SeedIds.user('rana'),
      detail: {'margin_pct': 66.9, 'target_pct': finSeedOrgTargetPct},
    ),
    d(
      'tart-target',
      ('lemon_tart', 'one_size'),
      'below_target',
      'snoozed',
      const Duration(hours: 5),
      SeedIds.owner,
      detail: {'margin_pct': 66.7, 'target_pct': finSeedOrgTargetPct},
    ),
  ];
}

/// A decision as `GET /insights/decisions` answers it: `impact` once a day
/// of after-data exists (null before), `impact_complete` after 28 days.
Map<String, Object?> _decisionOut(MockDb db, MockRow r, DateTime now) {
  final at = DateTime.parse(r['created_at']! as String);
  final branch = r['branch_id'] as String?;
  final branches = branch == null
      ? _orgBranches(r['org_id']! as String)
      : [branch];
  final sku = (_keyOfItem(r['menu_item_id']! as String), r['size_label']! as String);
  final measurable = now.isAfter(at.add(const Duration(days: 1)));
  final end = at.add(const Duration(days: _baselineDays));
  return {
    for (final e in r.entries)
      if (e.key != 'org_id') e.key: e.value,
    'impact': measurable
        ? _window(db, branches, sku, at, end.isBefore(now) ? end : now)
        : null,
    'impact_complete': !now.isBefore(end),
  };
}

String _keyOfItem(String menuItemId) => _itemById[menuItemId]?.key ?? '';

/// The decisions that keep a flag quiet at [branchScope] (`suppressions`):
/// org-wide ones and the branch's own.
Iterable<MockRow> _suppressions(
  MockDb db,
  String orgId,
  String? branchScope,
) => _decisions(db).where(
  (d) =>
      d['org_id'] == orgId &&
      (d['branch_id'] == null || d['branch_id'] == branchScope),
);

// ── the ledger ──────────────────────────────────────────────────────────

/// `build_ledger`: the ranked margin ledger for [branchIds] over
/// [from]…[to] (the previous equal-length window for trends), at the
/// snapshot or today's ([current]) cost basis, flags and classes included.
MarginLedgerReport finLedger(
  MockDb db, {
  required String orgId,
  required String branchId,
  required List<String> branchIds,
  DateTime? from,
  DateTime? to,
  bool current = false,
  DateTime? now,
}) {
  final at = now ?? db.clock.now;
  final branchScope = branchId == allBranchesId ? null : branchId;
  final (targetPct, targetSource) = finResolveTarget(db, orgId, branchScope);
  final sabah = orgId == SeedIds.sabahOrg;
  final sales = sabah
      ? _skuSales(db, branchIds, from: from, to: to, current: current)
      : <FinSku, _SkuAgg>{};
  DateTime? prevFrom;
  DateTime? prevTo;
  if (from != null && to != null && to.isAfter(from)) {
    prevFrom = from.subtract(to.difference(from));
    prevTo = from;
  }
  final prev = sabah && prevFrom != null
      ? _skuSales(db, branchIds, from: prevFrom, to: prevTo)
      : <FinSku, _SkuAgg>{};
  final windowDays = from == null
      ? null
      : math.max(0.01, (to ?? at).difference(from).inSeconds / 86400);

  final keys = <FinSku>{if (sabah) ...finCatalogSkus, ...sales.keys};
  final rows = <_Row>[];
  for (final k in keys) {
    final m = seedMenuItem(k.$1)!;
    final s = sales[k];
    final p = prev[k];
    final r = _Row(k, m)
      ..onMenu = !finOffMenuSkus.contains(k)
      ..qty = s?.qty ?? 0
      ..revenue = s?.revenue ?? 0
      ..prevQty = p?.qty ?? 0
      ..prevMargin = p == null || p.cost == null ? null : p.revenue - p.cost!;
    if (s != null) {
      r
        ..cost = s.cost
        ..margin = s.cost == null ? null : s.revenue - s.cost!
        ..marginPct = s.cost != null && s.revenue > 0
            ? (s.revenue - s.cost!) / s.revenue * 100
            : null;
    }
    rows.add(r);
  }

  // Signals.
  final sold = [
    for (final r in rows)
      if (r.qty > 0) r.qty,
  ]..sort();
  final q3 = sold.isEmpty ? 1 << 62 : sold[(sold.length - 1) * 3 ~/ 4];
  final supp = _suppressions(db, orgId, branchScope).toList();
  bool suppressed(_Row r, String kind) => supp.any(
    (d) =>
        d['menu_item_id'] == MockSeed.menuItemId(r.sku.$1) &&
        d['size_label'] == r.sku.$2 &&
        d['signal_kind'] == kind,
  );
  bool priorWorked(_Row r) => supp.any(
    (d) =>
        d['menu_item_id'] == MockSeed.menuItemId(r.sku.$1) &&
        d['size_label'] == r.sku.$2 &&
        d['action'] == 'acted' &&
        at.isAfter(
          DateTime.parse(
            d['created_at']! as String,
          ).add(const Duration(days: 1)),
        ),
  );
  for (final r in rows) {
    final flags = <Signal>[];
    final pct = r.marginPct;
    if (r.margin != null && r.qty > 0 && r.margin! < 0) {
      flags.add(
        Signal(
          kind: 'below_cost',
          link: 'pricing',
          params: {'margin': r.margin, 'revenue': r.revenue, 'cost': r.cost},
        ),
      );
    } else if (pct != null && pct < targetPct && r.qty >= _minSignalQty) {
      flags.add(
        Signal(
          kind: 'below_target',
          link: 'pricing',
          params: {
            'margin_pct': (pct * 10).round() / 10,
            'target_pct': targetPct,
          },
        ),
      );
    }
    if (pct != null &&
        r.qty >= q3 &&
        pct < targetPct - _priceBufferPct &&
        r.cost != null &&
        r.qty >= _minSignalQty) {
      final unit = r.cost! / r.qty;
      final raw = unit / (1 - targetPct / 100);
      int up(double v) => (v / _priceRound).ceil() * _priceRound;
      var suggested = up(raw);
      final params = <String, Object?>{
        'margin_pct': (pct * 10).round() / 10,
        'target_pct': targetPct,
      };
      if (priorWorked(r) && windowDays != null && r.revenue > 0) {
        // The last price change on this SKU worked: walk the price grid
        // under the measured elasticity (q ∝ p^E), up to 25% higher.
        const e = -1.2;
        final p0 = r.revenue / r.qty;
        final qpd0 = r.qty / windowDays;
        final mpd0 = (p0 - unit) * qpd0;
        final cap = math.min(p0 * 1.25, math.max(raw, p0 + _priceRound));
        var best = (up(p0), mpd0);
        for (var p = p0 + _priceRound; p <= cap + 0.001; p += _priceRound) {
          final mpd = (p - unit) * qpd0 * math.pow(p / p0, e);
          if (mpd > best.$2) best = (up(p), mpd.toDouble());
        }
        suggested = best.$1;
        params
          ..['suggested_price'] = suggested
          ..['last_worked'] = true
          ..['elasticity'] = e
          ..['expected_margin_per_day_delta'] = (best.$2 - mpd0).round();
      } else {
        params
          ..['suggested_price'] = suggested
          ..['last_worked'] = null;
      }
      flags.add(Signal(kind: 'price_candidate', link: 'pricing', params: params));
    }
    if (r.onMenu && r.qty == 0 && from != null) {
      flags.add(
        const Signal(kind: 'removal_candidate', link: 'studio', params: {}),
      );
    }
    if (r.onMenu && finUnitCost(r.sku, current: true) == null) {
      flags.add(
        const Signal(
          kind: 'recipe_incomplete',
          link: 'studio_recipe',
          params: {},
        ),
      );
    }
    final spike = _costSpikes[r.sku];
    if (spike != null && r.qty > 0) {
      flags.add(Signal(kind: 'cost_spike', link: 'studio_recipe', params: spike));
    }
    r.flags = [
      for (final f in flags)
        if (!suppressed(r, f.kind)) f,
    ];
  }

  // Totals + share.
  final revenue = rows.fold<int>(0, (s, r) => s + r.revenue);
  final costKnown = rows.fold<int>(0, (s, r) => s + (r.cost ?? 0));
  final marginKnown = rows.fold<int>(0, (s, r) => s + (r.margin ?? 0));
  final revenueKnown = rows
      .where((r) => r.cost != null)
      .fold<int>(0, (s, r) => s + r.revenue);
  final revenueUnknown = rows
      .where((r) => r.cost == null && r.qty > 0)
      .fold<int>(0, (s, r) => s + r.revenue);
  final prevRevenue = prev.values.fold<int>(0, (s, a) => s + a.revenue);
  final prevMarginKnown = rows.fold<int>(0, (s, r) => s + (r.prevMargin ?? 0));
  var gap = 0;
  for (final r in rows) {
    if (r.margin != null && r.marginPct != null && r.marginPct! < targetPct) {
      gap += (targetPct / 100 * r.revenue - r.margin!).truncate();
    }
  }
  if (marginKnown > 0) {
    for (final r in rows) {
      if (r.margin != null) {
        r.sharePct = (r.margin! / marginKnown * 1000).round() / 10;
      }
    }
  }

  // Kasavana–Smith classes over the rows that sold with a known margin.
  final classified = [
    for (final r in rows)
      if (r.qty > 0 && r.margin != null) r,
  ];
  if (classified.isNotEmpty) {
    final units = classified.fold<int>(0, (s, r) => s + r.qty);
    final profit = classified.fold<int>(0, (s, r) => s + r.margin!);
    final popThreshold = 0.70 / classified.length;
    final avgUnit = units > 0 ? profit / units : 0.0;
    for (final r in classified) {
      final pop = r.qty / math.max(1, units);
      final unit = r.margin! / r.qty;
      r
        ..popularity = (pop * 1000).round() / 10
        ..klass = switch ((pop >= popThreshold, unit >= avgUnit)) {
          (true, true) => 'star',
          (true, false) => 'workhorse',
          (false, true) => 'challenge',
          (false, false) => 'dog',
        };
    }
  }
  final rowsCostUnknown = rows.where((r) => r.qty > 0 && r.cost == null).length;

  rows.sort((a, b) {
    if (a.margin != null && b.margin != null) {
      return b.margin!.compareTo(a.margin!);
    }
    if (a.margin != null) return -1;
    if (b.margin != null) return 1;
    return b.revenue.compareTo(a.revenue);
  });

  return MarginLedgerReport(
    branchId: branchId,
    costBasis: current ? 'current' : 'snapshot',
    from: from,
    to: to,
    rows: [for (final r in rows) r.toModel()],
    rowsCostUnknown: rowsCostUnknown,
    targetPct: targetPct,
    targetSource: targetSource,
    totals: LedgerTotals(
      revenue: revenue,
      costKnown: costKnown,
      marginKnown: marginKnown,
      marginPct: revenueKnown > 0 ? marginKnown / revenueKnown * 100 : null,
      revenueCostUnknown: revenueUnknown,
      prevRevenue: prevRevenue,
      prevMarginKnown: prevMarginKnown,
      belowTargetGap: gap,
    ),
  );
}

class _Row {
  _Row(this.sku, this.item);

  final FinSku sku;
  final SeedItem item;
  bool onMenu = true;
  int qty = 0;
  int revenue = 0;
  int? cost;
  int? margin;
  double? marginPct;
  double? sharePct;
  int prevQty = 0;
  int? prevMargin;
  String? klass;
  double? popularity;
  List<Signal> flags = const [];

  MarginLedgerRow toModel() => MarginLedgerRow(
    menuItemId: MockSeed.menuItemId(sku.$1),
    sizeLabel: sku.$2,
    itemName: item.name,
    categoryId: MockSeed.categoryId(item.category),
    onMenu: onMenu,
    quantitySold: qty,
    revenue: revenue,
    cost: cost,
    margin: margin,
    marginPct: marginPct,
    marginSharePct: sharePct,
    prevQuantity: prevQty,
    prevMargin: prevMargin,
    class_: klass,
    popularityPct: popularity,
    flags: flags,
  );
}

/// `GET /insights/branches/{id}/repricing`: underpriced active SKUs at
/// today's costs, biggest uplift first; cost-unknown SKUs are counted, never
/// suggested.
RepricingReport finRepricing(MockDb db, String orgId, String branchId) {
  final branchScope = branchId == allBranchesId ? null : branchId;
  final (targetPct, targetSource) = finResolveTarget(db, orgId, branchScope);
  final out = <RepricingSuggestion>[];
  var considered = 0;
  var unknown = 0;
  if (orgId == SeedIds.sabahOrg) {
    for (final sku in finCatalogSkus) {
      final price = finSkuPrice(sku);
      if (price <= 0) continue;
      considered++;
      final cost = finUnitCost(sku, current: true);
      if (cost == null) {
        unknown++;
        continue;
      }
      final pct = 100 * (price - cost) / price;
      if (pct >= targetPct) continue;
      final suggested = ((cost / (1 - targetPct / 100)) / 100).ceil() * 100;
      out.add(
        RepricingSuggestion(
          menuItemId: MockSeed.menuItemId(sku.$1),
          itemName: seedMenuItem(sku.$1)!.name,
          sizeLabel: sku.$2,
          currentPrice: price,
          cost: cost,
          marginPct: (pct * 10).round() / 10,
          targetPct: targetPct,
          suggestedPrice: suggested,
          uplift: suggested - price,
          belowCost: cost > price,
        ),
      );
    }
  }
  out.sort((a, b) => b.uplift.compareTo(a.uplift));
  return RepricingReport(
    branchId: branchId,
    targetPct: targetPct,
    targetSource: targetSource,
    suggestions: out,
    skusConsidered: considered,
    skusCostUnknown: unknown,
  );
}

// ── sales reports ───────────────────────────────────────────────────────

String _two(int v) => v.toString().padLeft(2, '0');

/// `date_trunc` in Cairo as the backend's `YYYY-MM-DDTHH24:MI:SS`.
String _bucket(DateTime wall, String gran) => switch (gran) {
  'hourly' =>
    '${wall.year}-${_two(wall.month)}-${_two(wall.day)}T${_two(wall.hour)}:00:00',
  'monthly' => '${wall.year}-${_two(wall.month)}-01T00:00:00',
  _ => '${wall.year}-${_two(wall.month)}-${_two(wall.day)}T00:00:00',
};

class _Bucket {
  int orders = 0;
  int revenue = 0;
  int voided = 0;
  int discount = 0;
  int tax = 0;
  int lineItems = 0;
  int addons = 0;
  final Map<String, int> methods = {};

  void add(MockRow o) {
    if (o['status'] == 'voided') {
      voided++;
      return;
    }
    if (!isSold(o)) return;
    orders++;
    revenue += _int(o['total_amount']);
    discount += _int(o['discount_amount']);
    tax += _int(o['tax_amount']);
    for (final l in _linesOf(o['id']! as String)) {
      lineItems += l.qty;
      addons += l.addons;
    }
    final legs = o['payment_legs'];
    if (legs is List && legs.isNotEmpty) {
      for (final l in legs) {
        if (l is Map) {
          final m = '${l['method']}';
          methods[m] = (methods[m] ?? 0) + _int(l['amount']);
        }
      }
    } else {
      final m = '${o['payment_method']}';
      methods[m] = (methods[m] ?? 0) + _int(o['total_amount']);
    }
  }
}

/// `GET …/sales/timeseries`: one point per Cairo bucket that has orders.
List<TimeseriesPoint> finTimeseries(
  MockDb db,
  List<String> branchIds, {
  DateTime? from,
  DateTime? to,
  String granularity = 'daily',
}) {
  final buckets = <String, _Bucket>{};
  for (final o in reportOrders(db, branchIds: branchIds, from: from, to: to)) {
    (buckets[_bucket(_wallOf(o), granularity)] ??= _Bucket()).add(o);
  }
  final keys = buckets.keys.toList()..sort();
  return [
    for (final k in keys)
      TimeseriesPoint(
        period: k,
        orders: buckets[k]!.orders,
        revenue: buckets[k]!.revenue,
        refunded: 0,
        voided: buckets[k]!.voided,
        discount: buckets[k]!.discount,
        tax: buckets[k]!.tax,
        revenueByMethod: buckets[k]!.methods,
        lineItems: buckets[k]!.lineItems,
        addons: buckets[k]!.addons,
      ),
  ];
}

int _localDays(DateTime from, DateTime to) {
  final a = MockClock.wall(from);
  final b = MockClock.wall(to);
  return math.max(
    1,
    DateTime.utc(b.year, b.month, b.day)
            .difference(DateTime.utc(a.year, a.month, a.day))
            .inDays +
        1,
  );
}

double _pct1(int part, int total) =>
    total == 0 ? 0 : (part / total * 1000).round() / 10;

/// `GET …/sales/peak-hours`: all 24 hours, averaged over the range's days.
List<PeakHourPoint> finPeakHours(
  MockDb db,
  List<String> branchIds, {
  required DateTime from,
  required DateTime to,
}) {
  final hours = {for (var h = 0; h < 24; h++) h: _Bucket()};
  for (final o in reportOrders(db, branchIds: branchIds, from: from, to: to)) {
    hours[_wallOf(o).hour]!.add(o);
  }
  final days = _localDays(from, to);
  final rev = hours.values.fold<int>(0, (s, b) => s + b.revenue);
  final ord = hours.values.fold<int>(0, (s, b) => s + b.orders);
  return [
    for (final e in hours.entries)
      PeakHourPoint(
        hour: e.key,
        orders: e.value.orders,
        revenue: e.value.revenue,
        voided: e.value.voided,
        discount: e.value.discount,
        tax: e.value.tax,
        lineItems: e.value.lineItems,
        addons: e.value.addons,
        avgRevenuePerDay: (e.value.revenue / days).round(),
        avgOrdersPerDay: (e.value.orders / days * 100).round() / 100,
        revenuePct: _pct1(e.value.revenue, rev),
        ordersPct: _pct1(e.value.orders, ord),
      ),
  ];
}

/// `GET …/sales/peak-days`: all 7 weekdays (0 = Sunday), averaged over how
/// often each fell in the range.
List<PeakDayPoint> finPeakDays(
  MockDb db,
  List<String> branchIds, {
  required DateTime from,
  required DateTime to,
}) {
  final days = {for (var d = 0; d < 7; d++) d: _Bucket()};
  for (final o in reportOrders(db, branchIds: branchIds, from: from, to: to)) {
    days[_wallOf(o).weekday % 7]!.add(o);
  }
  final occ = {for (var d = 0; d < 7; d++) d: 0};
  final a = MockClock.wall(from);
  final b = MockClock.wall(to);
  for (
    var d = DateTime.utc(a.year, a.month, a.day);
    !d.isAfter(DateTime.utc(b.year, b.month, b.day));
    d = d.add(const Duration(days: 1))
  ) {
    occ[d.weekday % 7] = occ[d.weekday % 7]! + 1;
  }
  final rev = days.values.fold<int>(0, (s, x) => s + x.revenue);
  final ord = days.values.fold<int>(0, (s, x) => s + x.orders);
  return [
    for (final e in days.entries)
      PeakDayPoint(
        dayOfWeek: e.key,
        orders: e.value.orders,
        revenue: e.value.revenue,
        voided: e.value.voided,
        discount: e.value.discount,
        tax: e.value.tax,
        lineItems: e.value.lineItems,
        addons: e.value.addons,
        avgRevenuePerDay: (e.value.revenue / math.max(1, occ[e.key]!)).round(),
        avgOrdersPerDay:
            (e.value.orders / math.max(1, occ[e.key]!) * 100).round() / 100,
        revenuePct: _pct1(e.value.revenue, rev),
        ordersPct: _pct1(e.value.orders, ord),
      ),
  ];
}

/// `GET …/channel-breakdown`: per order type, by revenue (largest first).
List<ChannelBreakdownRow> finChannels(
  MockDb db,
  List<String> branchIds, {
  DateTime? from,
  DateTime? to,
}) {
  final s = summarizeSales(
    reportOrders(db, branchIds: branchIds, from: from, to: to),
  );
  final rows = [
    for (final e in s.revenueByChannel.entries)
      ChannelBreakdownRow(
        channel: e.key,
        orders: s.ordersByChannel[e.key] ?? 0,
        revenue: e.value,
        avgOrderValue: (s.ordersByChannel[e.key] ?? 0) == 0
            ? 0
            : e.value ~/ s.ordersByChannel[e.key]!,
      ),
  ]..sort((a, b) => b.revenue.compareTo(a.revenue));
  return rows;
}

// ── inventory reports ───────────────────────────────────────────────────

/// Stock nobody can order any more: archived from the catalog (so its
/// category is unknown on the Valuation tab) but still on Heliopolis'
/// shelf.
final String finArchivedIngredientId = mockUuid(
  'reports:ingredient:hazelnut_syrup',
);

/// `GET …/inventory-valuation` over [branchIds]: per ingredient, the stock
/// summed across the branches at its current cost (null cost = unknown).
InventoryValuationReport finValuation(List<String> branchIds) {
  final items = <ValuationRow>[];
  if (branchIds.isNotEmpty) {
    for (final ing in reportIngredients) {
      var qty = 0.0;
      for (final b in branchIds) {
        qty += onHand(b, ing.key);
      }
      qty = (qty * 10).round() / 10;
      final cost = ing.unitCost;
      items.add(
        ValuationRow(
          orgIngredientId: ing.id,
          ingredientName: ing.name,
          unit: ing.unit,
          onHand: qty,
          costPerUnit: cost,
          value: cost == null ? null : (qty * cost).round(),
        ),
      );
    }
    if (branchIds.contains(SeedIds.heliopolis)) {
      items.add(
        ValuationRow(
          orgIngredientId: finArchivedIngredientId,
          ingredientName: 'Hazelnut syrup',
          unit: 'L',
          onHand: 1.5,
          costPerUnit: 39000,
          value: 58500,
        ),
      );
    }
  }
  items.sort((a, b) => a.ingredientName.compareTo(b.ingredientName));
  var total = 0;
  var unknown = 0;
  for (final i in items) {
    if (i.value == null) {
      unknown++;
    } else {
      total += i.value!;
    }
  }
  return InventoryValuationReport(
    totalValue: total,
    unknownCostCount: unknown,
    items: items,
  );
}

/// `GET /inventory/orgs/{id}/catalog`: the active ingredients by catalog
/// category.
List<OrgIngredient> finCatalog(String orgId) {
  if (orgId != SeedIds.sabahOrg) return const [];
  final created = DateTime.utc(2026, 1, 12, 9);
  return [
    for (final ing in reportIngredients)
      () {
        final cat = reportCatalogCategories.firstWhere(
          (c) => c.key == ing.category,
        );
        final sup = reportSupplier(ing.supplier);
        return OrgIngredient(
          id: ing.id,
          orgId: orgId,
          name: ing.name,
          unit: ing.unit,
          categoryId: cat.id,
          categorySlug: cat.key,
          categoryName: cat.name,
          costPerUnit: ing.unitCost?.toDouble(),
          supplierId: sup.id,
          supplierName: sup.name,
          isActive: true,
          createdAt: created,
          updatedAt: created,
        );
      }(),
  ];
}

/// `GET …/supplier-spend`: received spend per supplier, largest first.
List<SupplierSpendRow> finSupplierSpend(
  List<String> branchIds, {
  DateTime? from,
  DateTime? to,
}) {
  final spend = <String, int>{};
  final pos = <String, Set<String>>{};
  for (final d in deliveriesIn(branchIds: branchIds, from: from, to: to)) {
    spend[d.supplier] = (spend[d.supplier] ?? 0) + d.total;
    (pos[d.supplier] ??= {}).add(d.poId);
  }
  return [
    for (final e in spend.entries)
      SupplierSpendRow(
        supplierId: reportSupplier(e.key).id,
        supplierName: reportSupplier(e.key).name,
        orders: pos[e.key]!.length,
        totalSpend: e.value,
      ),
  ]..sort((a, b) => b.totalSpend.compareTo(a.totalSpend));
}

/// `GET …/material-cost-trend`: ingredients whose current supplier raised
/// the price on three or more deliveries in a row within the period, with a
/// cheaper current offer when there is one.
List<MaterialCostTrendRow> finMaterialCostTrend(
  List<String> branchIds, {
  DateTime? from,
  DateTime? to,
}) {
  final out = <MaterialCostTrendRow>[];
  final inWindow = deliveriesIn(branchIds: branchIds, from: from, to: to);
  for (final ing in reportIngredients) {
    // Each delivery round once (every branch pays the same price).
    final costs = <int>[];
    DateTime? last;
    for (final d in inWindow.where((d) => d.ingredient == ing.key)) {
      if (last == null || d.receivedAt.difference(last).inHours > 48) {
        costs.add(d.unitCost);
        last = d.receivedAt;
      }
    }
    var streak = 0;
    for (var i = costs.length - 1; i > 0; i--) {
      if (costs[i] > costs[i - 1]) {
        streak++;
      } else {
        break;
      }
    }
    if (streak < 3) continue;
    final base = costs[costs.length - 1 - streak];
    final current = costs.last;
    final cheaper = ing.cheaper;
    final cheap = cheaper != null && cheaper.$2 < current ? cheaper : null;
    final sup = reportSupplier(ing.supplier);
    out.add(
      MaterialCostTrendRow(
        orgIngredientId: ing.id,
        ingredientName: ing.name,
        currentSupplierId: sup.id,
        currentSupplierName: sup.name,
        currentCost: current,
        streakLength: streak,
        baseCost: base,
        pctIncrease: ((current - base) / base * 1000).round() / 10,
        cheaperSupplierId: cheap == null ? null : reportSupplier(cheap.$1).id,
        cheaperSupplierName: cheap == null
            ? null
            : reportSupplier(cheap.$1).name,
        cheaperCost: cheap?.$2,
      ),
    );
  }
  out.sort((a, b) => b.pctIncrease.compareTo(a.pctIncrease));
  return out;
}

// ── the export throttle ─────────────────────────────────────────────────

/// Counts a request marked `X-Madar-Export: 1` against the person's
/// per-minute budget (REP-ALL-027): past [finExportPerMinute] in one minute
/// it answers 429 `EXPORT_RATE_LIMITED`.
void finCountExport(MockRequest req, MockDb db) {
  final h = req.headers['X-Madar-Export'] ?? req.headers['x-madar-export'];
  if (h != '1') return;
  final minute = req.now.millisecondsSinceEpoch ~/ 60000;
  final t = db['mock_export_budget'];
  final id = '${req.persona.name}:$minute';
  final row = t.find(id) ?? t.put({'id': id, 'count': 0});
  final n = _int(row['count']) + 1;
  row['count'] = n;
  if (n > finExportPerMinute) {
    req.fail(
      MockResponse.error(
        429,
        'Too many exports just now. Try again in a minute.',
        code: 'EXPORT_RATE_LIMITED',
        retryAfterSeconds: 60,
      ),
    );
  }
}

// ── registration ────────────────────────────────────────────────────────

void registerFinancialMocks(MockServer server, MockDb db) {
  // ── insights ──────────────────────────────────────────────────────
  server.on('GET', '/insights/branches/{branch_id}/menu-margin', (req) {
    req.requireCap('orders.read');
    final id = req.param('branch_id');
    final basis = req.q('cost_basis');
    if (basis != null && basis != 'snapshot' && basis != 'current') {
      req.badRequest("cost_basis must be 'snapshot' or 'current', got '$basis'");
    }
    final branches = _branches(req, id);
    return MockResponse.ok(
      finLedger(
        db,
        orgId: req.orgId ?? SeedIds.sabahOrg,
        branchId: id,
        branchIds: branches,
        from: req.qDateTime('from'),
        to: req.qDateTime('to'),
        current: basis == 'current',
      ),
    );
  });

  server.on('GET', '/insights/branches/{branch_id}/repricing', (req) {
    req.requireCap('orders.read');
    final id = req.param('branch_id');
    _branches(req, id);
    return MockResponse.ok(
      finRepricing(db, req.orgId ?? SeedIds.sabahOrg, id),
    );
  });

  server.on('GET', '/insights/decisions', (req) {
    req.requireCap('orders.read');
    final orgId = req.q('org_id');
    if (orgId == null) {
      req.badRequest('Query deserialize error: missing field `org_id`');
    }
    req.requireSameOrg(orgId);
    final branch = req.q('branch_id');
    final limit = (req.qInt('limit') ?? 50).clamp(1, 100);
    final rows =
        _decisions(db).where(
          (d) =>
              d['org_id'] == orgId &&
              (branch == null || d['branch_id'] == branch),
        )..sort(
          (a, b) => (b['created_at']! as String).compareTo(
            a['created_at']! as String,
          ),
        );
    return MockResponse.ok([
      for (final r in rows.take(limit)) _decisionOut(db, r, req.now),
    ]);
  });

  server.on('POST', '/insights/decisions', (req) {
    req.requireCap('menu.items.edit');
    final orgId = req.q('org_id');
    if (orgId == null) {
      req.badRequest('Query deserialize error: missing field `org_id`');
    }
    req.requireSameOrg(orgId);
    final b = req.bodyAs(CreateDecisionRequest.fromJson);
    const kinds = [
      'below_cost',
      'below_target',
      'cost_spike',
      'price_candidate',
      'removal_candidate',
      'recipe_incomplete',
    ];
    if (!kinds.contains(b.signalKind)) {
      req.badRequest("unknown signal_kind '${b.signalKind}'");
    }
    if (!['acted', 'dismissed', 'snoozed'].contains(b.action)) {
      req.badRequest("action must be 'acted', 'dismissed' or 'snoozed'");
    }
    final item = _itemById[b.menuItemId];
    if (item == null) req.notFound('Menu item not found');
    final size = b.sizeLabel ?? 'one_size';
    final branches = b.branchId == null
        ? _orgBranches(orgId!)
        : [b.branchId!];
    final now = req.now;
    final row = _decisions(db).insert({
      'org_id': orgId,
      'branch_id': b.branchId,
      'menu_item_id': b.menuItemId,
      'size_label': size,
      'item_name': item.name,
      'signal_kind': b.signalKind,
      'action': b.action,
      'detail': b.detail ?? const <String, Object?>{},
      'baseline': _window(
        db,
        branches,
        (item.key, size),
        now.subtract(const Duration(days: _baselineDays)),
        now,
      ),
      'created_by': req.persona.userId,
      'created_at': now.toIso8601String(),
    }, timestamps: false);
    return MockResponse.created(_decisionOut(db, row, now));
  });

  server.on('GET', '/insights/margin-target', (req) {
    req.requireCap('orders.read');
    final orgId = req.q('org_id');
    if (orgId == null) {
      req.badRequest('Query deserialize error: missing field `org_id`');
    }
    req.requireSameOrg(orgId);
    return MockResponse.ok(_targetsOf(db, orgId!));
  });

  server.on('PUT', '/insights/margin-target', (req) {
    req.requireCap('menu.items.edit');
    final orgId = req.q('org_id');
    if (orgId == null) {
      req.badRequest('Query deserialize error: missing field `org_id`');
    }
    req.requireSameOrg(orgId);
    final b = req.bodyAs(PutTargetRequest.fromJson);
    if (!(b.targetPct > 0 && b.targetPct < 100)) {
      req.badRequest('target_pct must be between 0 and 100 (exclusive)');
    }
    _targets(db).put({
      'id': b.branchId == null ? 'org:$orgId' : 'branch:${b.branchId}',
      'org_id': orgId,
      'branch_id': b.branchId,
      'target_pct': b.targetPct,
    });
    return MockResponse.ok(_targetsOf(db, orgId!));
  });

  // ── sales ─────────────────────────────────────────────────────────
  server.on('GET', '/reports/branches/{branch_id}/sales/timeseries', (req) {
    req.requireCap('orders.read');
    final branches = _branches(req, req.param('branch_id'));
    return MockResponse.ok(
      finTimeseries(
        db,
        branches,
        from: req.qDateTime('from'),
        to: req.qDateTime('to'),
        granularity: switch (req.q('granularity')) {
          'hourly' => 'hourly',
          'monthly' => 'monthly',
          _ => 'daily',
        },
      ),
    );
  });

  DateTime fromOf(MockRequest req) =>
      req.qDateTime('from') ?? req.now.subtract(const Duration(days: 30));
  DateTime toOf(MockRequest req) => req.qDateTime('to') ?? req.now;

  server.on('GET', '/reports/branches/{branch_id}/sales/peak-hours', (req) {
    req.requireCap('orders.read');
    final branches = _branches(req, req.param('branch_id'));
    return MockResponse.ok(
      finPeakHours(db, branches, from: fromOf(req), to: toOf(req)),
    );
  });

  server.on('GET', '/reports/branches/{branch_id}/sales/peak-days', (req) {
    req.requireCap('orders.read');
    final branches = _branches(req, req.param('branch_id'));
    return MockResponse.ok(
      finPeakDays(db, branches, from: fromOf(req), to: toOf(req)),
    );
  });

  server.on('GET', '/reports/branches/{branch_id}/channel-breakdown', (req) {
    req.requireCap('orders.read');
    final branches = _branches(req, req.param('branch_id'));
    finCountExport(req, db);
    return MockResponse.ok(
      finChannels(
        db,
        branches,
        from: req.qDateTime('from'),
        to: req.qDateTime('to'),
      ),
    );
  });

  // ── inventory ─────────────────────────────────────────────────────
  server.on('GET', '/reports/branches/{branch_id}/inventory-valuation', (req) {
    req.requireCap('inventory.read');
    return MockResponse.ok(
      finValuation(_branches(req, req.param('branch_id'))),
    );
  });

  server.on('GET', '/reports/orgs/{org_id}/inventory-valuation', (req) {
    req.requireCap('inventory.read');
    final orgId = req.param('org_id');
    _requireOrg(req, orgId);
    return MockResponse.ok(finValuation(_orgBranches(orgId)));
  });

  server.on('GET', '/inventory/orgs/{org_id}/catalog', (req) {
    req.requireCap('inventory.read');
    final orgId = req.param('org_id');
    _requireOrg(req, orgId);
    return MockResponse.ok(finCatalog(orgId));
  });

  server.on('GET', '/reports/branches/{branch_id}/supplier-spend', (req) {
    final id = req.param('branch_id');
    req.requireCap(
      'purchasing.orders.read',
      branchId: id == allBranchesId ? null : id,
    );
    return MockResponse.ok(
      finSupplierSpend(
        _branches(req, id),
        from: req.qDateTime('from'),
        to: req.qDateTime('to'),
      ),
    );
  });

  server.on('GET', '/reports/orgs/{org_id}/supplier-spend', (req) {
    req.requireCap('purchasing.orders.read');
    final orgId = req.param('org_id');
    _requireOrg(req, orgId);
    final branches = [
      for (final b in _orgBranches(orgId))
        if (req.persona.seesBranch(b)) b,
    ];
    return MockResponse.ok(
      finSupplierSpend(
        branches,
        from: req.qDateTime('from'),
        to: req.qDateTime('to'),
      ),
    );
  });

  server.on('GET', '/reports/branches/{branch_id}/material-cost-trend', (req) {
    final id = req.param('branch_id');
    req.requireCap(
      'purchasing.orders.read',
      branchId: id == allBranchesId ? null : id,
    );
    return MockResponse.ok(
      finMaterialCostTrend(
        _branches(req, id),
        from: req.qDateTime('from'),
        to: req.qDateTime('to'),
      ),
    );
  });

  server.on('GET', '/reports/orgs/{org_id}/material-cost-trend', (req) {
    req.requireCap('purchasing.orders.read');
    final orgId = req.param('org_id');
    _requireOrg(req, orgId);
    final branches = [
      for (final b in _orgBranches(orgId))
        if (req.persona.seesBranch(b)) b,
    ];
    return MockResponse.ok(
      finMaterialCostTrend(
        branches,
        from: req.qDateTime('from'),
        to: req.qDateTime('to'),
      ),
    );
  });

  // ── users (who made each decision) ────────────────────────────────
  server.on('GET', '/users', (req) {
    req.requireCap('staff.users.read');
    final orgId = req.persona.isPlatform ? req.q('org_id') : req.persona.orgId;
    final scoped = req.persona.branchIds;
    final rows = db['users'].where(
      (u) =>
          (orgId == null || u['org_id'] == orgId) &&
          (scoped == null ||
              u['id'] == req.persona.userId ||
              scoped.contains(u['branch_id'])),
    )..sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
    return MockResponse.ok(rows);
  });
}
