/// The mock backend for Operations (REP-OPS, REP-ALL): `/metrics/query`
/// (the `tables` dataset), `/floor/tables`, `/floor/tables/{id}/history`,
/// branch sales, items-combined, addons, tellers, waiters, the org
/// comparison, the menu list the exclude control reads, the read-only
/// customer and order a table's history links to, and the 429 export
/// throttle.
///
/// Handlers behave like the backend (capability refusals, branch scoping,
/// the shared figures in `../area_seed.dart`); see SPEC section 3.2.
///
/// The unit's own domain data lives here, built on the core seed:
///
/// - **The floor plan**: the same sections, labels and ids as the sell
///   area's plan (`floor-table:<branch>:<label>`), so the Floor page and this
///   report name the same tables; plus Zamalek's retired "T10", which still
///   has sittings in the period but is no longer on the plan (REP-OPS-026).
///   When another area has loaded `floor_tables` into the db, the live rows
///   win.
/// - **Sittings**: every dine-in order of the core seed was eaten at one of
///   its branch's tables, seated some minutes before it was paid, with a
///   guest count; a voided dine-in order is a voided bill. The tables seated
///   right now (the sell area's open tickets) are open bills.
/// - **Waiters**: Zamalek's two waiters carry most of its dine-in orders; at
///   the other branches the manager takes a share of the tables. Counter and
///   delivery orders never carry a waiter.
library;

import 'dart:math' as math;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart' show allBranchesId;

import '../area_seed.dart';

// ── the floor plan ────────────────────────────────────────────────────────

/// One table of the plan.
class OpsTable {
  const OpsTable(
    this.branchKey,
    this.sectionKey,
    this.sectionName,
    this.label,
    this.seats,
    this.shape, {
    this.active = true,
    this.retired,
  });

  final String branchKey;

  /// Null = a table without a section ("No section" in the metrics).
  final String? sectionKey;
  final String sectionName;
  final String label;
  final int seats;
  final String shape;
  final bool active;

  /// When it left the floor plan (no longer listed), if it did.
  final DateTime? retired;

  String get id => mockUuid('floor-table:$branchKey:$label');
  String get branchId => MockSeed.branchIdOf(branchKey);
  String? get sectionId => sectionKey == null
      ? null
      : mockUuid('floor-section:$branchKey:$sectionKey');

  /// The metrics' section dimension (`COALESCE(fs.name, 'No section')`).
  String get sectionLabel => sectionKey == null ? 'No section' : sectionName;
}

/// Zamalek's T10 stood on the Nile terrace until 26 Sept 2026.
final DateTime opsRetiredAt = MockClock.fromCairo(2026, 9, 26, 8, 0);

/// The plan, branch by branch, in plan order.
final List<OpsTable> opsTables = [
  // Heliopolis
  for (final (l, s, sh) in const [
    ('T1', 4, 'rect'),
    ('T2', 4, 'rect'),
    ('T3', 2, 'circle'),
    ('T4', 2, 'circle'),
    ('T5', 6, 'rect'),
    ('T6', 4, 'rect'),
  ])
    OpsTable('heliopolis', 'main', 'Main hall', l, s, sh),
  const OpsTable('heliopolis', 'terrace', 'Terrace', 'T7', 2, 'circle'),
  const OpsTable('heliopolis', 'terrace', 'Terrace', 'T8', 2, 'circle'),
  const OpsTable(
    'heliopolis',
    'terrace',
    'Terrace',
    'T9',
    4,
    'rect',
    active: false,
  ),
  // Maadi
  for (final (l, s, sh) in const [
    ('T1', 2, 'circle'),
    ('T2', 4, 'rect'),
    ('T3', 4, 'rect'),
    ('T4', 6, 'rect'),
  ])
    OpsTable('maadi', 'indoor', 'Indoor', l, s, sh),
  for (final (l, s, sh) in const [
    ('T5', 4, 'rect'),
    ('T6', 4, 'rect'),
    ('T7', 2, 'circle'),
    ('T8', 2, 'circle'),
  ])
    OpsTable('maadi', 'garden', 'Garden', l, s, sh),
  // New Cairo
  for (final (l, s, sh) in const [
    ('T1', 4, 'rect'),
    ('T2', 4, 'rect'),
    ('T3', 2, 'circle'),
    ('T4', 2, 'circle'),
    ('T5', 6, 'rect'),
    ('T6', 4, 'rect'),
  ])
    OpsTable('new-cairo', 'ground', 'Ground floor', l, s, sh),
  for (final (l, s, sh) in const [
    ('T7', 2, 'circle'),
    ('T8', 2, 'circle'),
    ('T9', 4, 'rect'),
  ])
    OpsTable('new-cairo', 'mezzanine', 'Mezzanine', l, s, sh),
  for (final (l, s, sh) in const [
    ('T10', 4, 'rect'),
    ('T11', 4, 'rect'),
    ('T12', 8, 'rect'),
  ])
    OpsTable('new-cairo', 'outdoor', 'Outdoor', l, s, sh),
  // Zamalek
  for (final (l, s, sh) in const [
    ('T1', 2, 'circle'),
    ('T2', 4, 'rect'),
    ('T3', 4, 'rect'),
    ('T4', 2, 'circle'),
    ('T5', 6, 'rect'),
  ])
    OpsTable('zamalek', 'main', 'Main hall', l, s, sh),
  for (final (l, s, sh) in const [
    ('T6', 2, 'circle'),
    ('T7', 2, 'circle'),
    ('T8', 4, 'rect'),
    ('T9', 4, 'rect'),
  ])
    OpsTable('zamalek', 'nile', 'Nile terrace', l, s, sh),
  OpsTable(
    'zamalek',
    'nile',
    'Nile terrace',
    'T10',
    4,
    'rect',
    retired: opsRetiredAt,
  ),
  const OpsTable('zamalek', null, '', 'Bar 1', 2, 'circle'),
];

OpsTable? opsTableById(String id) =>
    opsTables.where((t) => t.id == id).firstOrNull;

String _branchKeyOf(String branchId) =>
    seedBranches.firstWhere((b) => MockSeed.branchIdOf(b.key) == branchId).key;

String _branchName(String branchId) =>
    seedBranches.firstWhere((b) => MockSeed.branchIdOf(b.key) == branchId).name;

/// The plan as `/floor/tables` answers it ([FloorTable] JSON), retired
/// tables left out.
MockRow _floorTableJson(OpsTable t, int index) {
  final inSection = opsTables
      .where((x) => x.branchKey == t.branchKey && x.sectionKey == t.sectionKey)
      .toList()
      .indexOf(t);
  final created = DateTime.utc(2026, 2, 1, 8);
  return FloorTable(
    branchId: t.branchId,
    createdAt: created,
    height: t.shape == 'circle' ? 80 : 90,
    id: t.id,
    isActive: t.active,
    label: t.label,
    orgId: SeedIds.sabahOrg,
    posX: t.sectionKey == null ? 620 : 40.0 + (inSection % 3) * 180,
    posY: t.sectionKey == null ? 420 : 40.0 + (inSection ~/ 3) * 140,
    rotation: 0,
    seats: t.seats,
    sectionId: t.sectionId,
    shape: t.shape,
    status: 'available',
    updatedAt: DateTime.utc(2026, 9, 20, 8),
    width: t.shape == 'circle' ? 80 : 120,
  ).toJson();
}

/// The floor's tables at [branchId] as the floor read answers: the live
/// `floor_tables` rows when another area loaded them, else this plan.
List<MockRow> opsFloorRows(MockDb db, String branchId) {
  final List<MockRow> rows;
  if (db.hasTable('floor_tables') && db['floor_tables'].length > 0) {
    rows = [
      for (final r in db['floor_tables'].rows)
        if (r['branch_id'] == branchId) r,
    ];
  } else {
    rows = [
      for (final (i, t) in opsTables.indexed)
        if (t.branchId == branchId && t.retired == null) _floorTableJson(t, i),
    ];
  }
  rows.sort(
    (a, b) =>
        '${a['label']}'.toLowerCase().compareTo('${b['label']}'.toLowerCase()),
  );
  return rows;
}

// ── sittings, waiters, lines ──────────────────────────────────────────────

/// One bill opened on a table: the dine-in order it settled into (or the
/// voided bill), or a bill still open now.
class OpsSitting {
  const OpsSitting({
    required this.ticketId,
    required this.ticketRef,
    required this.table,
    required this.seatedAt,
    required this.covers,
    this.orderId,
    this.closedAt,
    this.customerId,
    this.customerName,
  });

  final String ticketId;
  final String ticketRef;
  final OpsTable table;
  final DateTime seatedAt;

  /// When it was paid (the order's `created_at`) or voided; null = open.
  final DateTime? closedAt;
  final int covers;

  /// The settled (or voided) order; null for a bill still open.
  final String? orderId;
  final String? customerId;
  final String? customerName;

  int get dwellMinutes =>
      closedAt == null ? 0 : closedAt!.difference(seatedAt).inMinutes;
}

/// Who served each dine-in order (user id), when a waiter did.
class OpsWaiter {
  const OpsWaiter(this.key, this.weight);

  final String key;
  final double weight;

  String get id => SeedIds.user(key);
  String get name => sabahStaff.firstWhere((p) => p.key == key).name;
}

/// The waiters of each branch and the share of its dine-in orders they
/// carry: Zamalek has two; elsewhere the manager runs some tables.
const Map<String, (double, List<OpsWaiter>)> _waiters = {
  'zamalek': (0.88, [OpsWaiter('laila', 0.55), OpsWaiter('adham', 0.45)]),
  'heliopolis': (0.35, [OpsWaiter('rana', 1)]),
  'new-cairo': (0.3, [OpsWaiter('dina', 1)]),
  'maadi': (0.25, [OpsWaiter('tarek', 1)]),
};

/// The tables seated right now (the sell area's open tickets): branch,
/// table, opened at Cairo h:m, customer index, guests.
const List<(String, String, int, int, int?, int)> _seatedNow = [
  ('heliopolis', 'T1', 9, 32, 0, 3),
  ('heliopolis', 'T2', 6, 58, null, 2),
  ('maadi', 'T2', 9, 40, 7, 4),
  ('new-cairo', 'T1', 8, 15, 3, 2),
  ('new-cairo', 'T3', 9, 50, null, 2),
  ('zamalek', 'T1', 9, 5, 12, 2),
];

/// The unit's derived data, built once from the immutable core seed.
class OpsSeed {
  OpsSeed._();

  static final OpsSeed instance = OpsSeed._();

  final Map<String, List<OrderItemFull>> _lines = {};

  /// An order's lines: the row's own `items` when it carries them (an order
  /// another area created), else the core seed's.
  List<OrderItemFull> linesOf(MockRow order) {
    final id = order['id']! as String;
    final own = order['items'];
    if (own is List) {
      return [
        for (final l in own)
          if (l is Map) OrderItemFull.fromJson(l.cast<String, Object?>()),
      ];
    }
    return _lines[id] ??= MockSeed.instance.orderItems(id);
  }

  /// The waiter of each dine-in order that had one.
  late final Map<String, OpsWaiter> waiterOf = () {
    final out = <String, OpsWaiter>{};
    for (final o in MockSeed.instance.orders) {
      if (o.orderType != 'dine_in') continue;
      final key = _branchKeyOf(o.branchId);
      final (share, people) = _waiters[key]!;
      final rng = MockRandom('reports:waiter:${o.id}');
      if (!rng.chance(share)) continue;
      out[o.id] = rng.weighted(people, [for (final p in people) p.weight]);
    }
    return out;
  }();

  /// Every sitting, oldest first.
  late final List<OpsSitting> sittings = _buildSittings();

  List<OpsSitting> _buildSittings() {
    final out = <OpsSitting>[];
    final seqByDay = <String, int>{};
    String ref(String branchKey, DateTime at) {
      final date = MockClock.cairoDate(at);
      final k = '$branchKey|$date';
      final n = seqByDay[k] = (seqByDay[k] ?? 0) + 1;
      final code = seedBranches.firstWhere((b) => b.key == branchKey).code;
      return 'T-$code-${date.substring(2).replaceAll('-', '')}-'
          '${n.toString().padLeft(4, '0')}';
    }

    final byBranch = <String, List<OpsTable>>{};
    for (final t in opsTables) {
      if (!t.active) continue;
      byBranch.putIfAbsent(t.branchKey, () => []).add(t);
    }
    // Today's open bills take their refs first, as they were opened first
    // in the sell seed's numbering.
    final customers = MockSeed.instance.customers;
    for (final (b, label, h, m, ci, guests) in _seatedNow) {
      final table = opsTables.firstWhere(
        (t) => t.branchKey == b && t.label == label,
      );
      final today = MockClock.cairoDate(MockSeed.now);
      final p = today.split('-').map(int.parse).toList();
      final opened = MockClock.fromCairo(p[0], p[1], p[2], h, m);
      final c = ci == null ? null : customers[ci];
      out.add(
        OpsSitting(
          ticketId: mockUuid('open-ticket:$b:$label'),
          ticketRef: ref(b, opened),
          table: table,
          seatedAt: opened,
          covers: guests,
          customerId: c?.id,
          customerName: c?.name,
        ),
      );
    }
    for (final o in MockSeed.instance.orders) {
      if (o.orderType != 'dine_in') continue;
      final key = _branchKeyOf(o.branchId);
      final rng = MockRandom('reports:sitting:${o.id}');
      final tables = [
        for (final t in byBranch[key]!)
          if (t.retired == null || o.createdAt.isBefore(t.retired!)) t,
      ];
      final table = rng.weighted(tables, [
        for (final t in tables) t.sectionKey == null ? 0.6 : 1.0,
      ]);
      final covers = math.min(
        table.seats,
        rng.weighted(const [1, 2, 3, 4, 5, 6], const [18, 40, 16, 16, 5, 5]),
      );
      final dwell = 22 + rng.nextInt(38) + covers * (6 + rng.nextInt(9));
      final paid = o.voidedAt ?? o.createdAt;
      final seated = o.createdAt.subtract(Duration(minutes: dwell));
      out.add(
        OpsSitting(
          ticketId: mockUuid('reports:ticket:${o.id}'),
          ticketRef: ref(key, seated),
          table: table,
          seatedAt: seated,
          closedAt: paid,
          covers: covers,
          orderId: o.id,
          customerId: o.customerId,
          customerName: o.customerName,
        ),
      );
    }
    out.sort((a, b) => a.seatedAt.compareTo(b.seatedAt));
    return List.unmodifiable(out);
  }

  late final Map<String, OpsSitting> _byOrder = {
    for (final s in sittings)
      if (s.orderId != null) s.orderId!: s,
  };

  /// The sitting a dine-in order settled, if it was eaten at a table.
  OpsSitting? sittingOf(String orderId) => _byOrder[orderId];
}

int _int(Object? v) => v is num ? v.toInt() : 0;

DateTime _at(MockRow r) => DateTime.parse(r['created_at']! as String).toUtc();

bool _sold(MockRow o) => isSold(o);

// ── /metrics/query: the `tables` dataset ──────────────────────────────────

/// One settled dine-in bill eaten at a table: a `tables` dataset row.
class OpsTableFact {
  const OpsTableFact(this.order, this.sitting);

  final MockRow order;
  final OpsSitting sitting;

  int get revenue => _int(order['total_amount']);
  DateTime get at => _at(order);
  String get hour => '${MockClock.wall(at).hour.toString().padLeft(2, '0')}:00';
  String get localDate => MockClock.cairoDate(at);
}

/// The dataset's rows: sold dine-in orders at [branchIds] within
/// [from]…[to] that sat at a table.
List<OpsTableFact> opsTableFacts(
  MockDb db, {
  required Iterable<String> branchIds,
  DateTime? from,
  DateTime? to,
}) {
  final seed = OpsSeed.instance;
  return [
    for (final o in reportOrders(db, branchIds: branchIds, from: from, to: to))
      if (_sold(o) && o['order_type'] == 'dine_in')
        if (seed.sittingOf(o['id']! as String) case final s?)
          OpsTableFact(o, s),
  ];
}

const List<String> _tableMeasures = [
  'turns',
  'turns_per_day',
  'covers',
  'table_revenue',
  'revenue_per_table',
  'revenue_per_cover',
  'avg_dwell_minutes',
  'active_tables',
];

const Map<String, (String, String)> _measureMeta = {
  'turns': ('Turns', 'count'),
  'turns_per_day': ('Turns per day', 'number'),
  'covers': ('Covers', 'count'),
  'table_revenue': ('Revenue', 'money'),
  'revenue_per_table': ('Revenue per table', 'money'),
  'revenue_per_cover': ('Revenue per cover', 'money'),
  'avg_dwell_minutes': ('Avg minutes seated', 'minutes'),
  'active_tables': ('Tables used', 'count'),
};

const Map<String, (String, String)> _dimMeta = {
  'table': ('Table', 'label'),
  'section': ('Section', 'label'),
  'branch': ('Branch', 'label'),
  'hour': ('Hour', 'label'),
  'day': ('Day', 'date'),
  'weekday': ('Weekday', 'label'),
};

double _round(double v, int dp) {
  final f = math.pow(10, dp);
  return (v * f).round() / f;
}

/// The measures over one group of facts, as the backend's SQL computes them.
Map<String, Object?> opsTableMeasures(List<OpsTableFact> facts) {
  final orders = facts.length;
  final tables = {for (final f in facts) f.sitting.table.id};
  final tableDays = {
    for (final f in facts) '${f.sitting.table.id}|${f.localDate}',
  };
  final covers = facts.fold<int>(0, (s, f) => s + f.sitting.covers);
  final revenue = facts.fold<int>(0, (s, f) => s + f.revenue);
  final dwell = facts.fold<int>(0, (s, f) => s + f.sitting.dwellMinutes);
  return {
    'turns': orders,
    'turns_per_day': tableDays.isEmpty
        ? null
        : _round(orders / tableDays.length, 2),
    'covers': covers,
    'table_revenue': revenue,
    'revenue_per_table': tables.isEmpty ? 0 : (revenue / tables.length).round(),
    'revenue_per_cover': covers == 0 ? 0 : (revenue / covers).round(),
    'avg_dwell_minutes': orders == 0 ? 0.0 : _round(dwell / orders, 1),
    'active_tables': tables.length,
  };
}

String _dimValue(OpsTableFact f, String dim) => switch (dim) {
  'table' => f.sitting.table.label,
  'section' => f.sitting.table.sectionLabel,
  'branch' => _branchName(f.sitting.table.branchId),
  'hour' => f.hour,
  'day' => f.localDate,
  _ => '',
};

/// One widget of the `tables` dataset: its rows, or a reason it failed.
Object _runTablesWidget(
  Map<String, Object?> spec,
  List<OpsTableFact> facts,
  Map<String, Object?> period,
) {
  final dataset = spec['dataset'];
  if (dataset != 'tables') {
    return "Unknown dataset '$dataset'";
  }
  final dims = [
    for (final d in (spec['dimensions'] as List?) ?? const []) '$d',
  ];
  final measures = [
    for (final m
        in (spec['measures'] as List?) ??
            const ['turns', 'covers', 'table_revenue'])
      '$m',
  ];
  if (dims.length > 2) return 'At most 2 dimensions per query';
  for (final d in dims) {
    if (!_dimMeta.containsKey(d)) return "Unknown dimension '$d' for tables";
  }
  for (final m in measures) {
    if (!_tableMeasures.contains(m)) return "Unknown measure '$m' for tables";
  }
  final limit = ((spec['limit'] as num?)?.toInt() ?? 200).clamp(1, 5000);
  final groups = <String, List<OpsTableFact>>{};
  final keys = <String, List<String>>{};
  if (dims.isEmpty) {
    groups[''] = facts;
    keys[''] = const [];
  } else {
    for (final f in facts) {
      final vals = [for (final d in dims) _dimValue(f, d)];
      final k = vals.join('\u0000');
      groups.putIfAbsent(k, () => []).add(f);
      keys[k] = vals;
    }
  }
  var rows = [
    for (final e in groups.entries)
      {
        for (final (i, d) in dims.indexed) d: keys[e.key]![i],
        ...{for (final m in measures) m: opsTableMeasures(e.value)[m]},
      },
  ];
  final sort = spec['sort'];
  if (sort is Map && sort['measure'] is String) {
    final m = sort['measure']! as String;
    final desc = sort['dir'] != 'asc';
    final full = {
      for (final e in groups.entries) e.key: opsTableMeasures(e.value)[m],
    };
    final order = groups.keys.toList()
      ..sort((a, b) {
        final va = (full[a] as num?) ?? 0;
        final vb = (full[b] as num?) ?? 0;
        final c = desc ? vb.compareTo(va) : va.compareTo(vb);
        return c != 0 ? c : a.compareTo(b);
      });
    rows = [
      for (final k in order)
        {
          for (final (i, d) in dims.indexed) d: keys[k]![i],
          for (final m in measures) m: opsTableMeasures(groups[k]!)[m],
        },
    ];
  } else if (dims.isNotEmpty) {
    rows.sort((a, b) => '${a[dims.first]}'.compareTo('${b[dims.first]}'));
  }
  final truncated = rows.length > limit;
  if (truncated) rows = rows.sublist(0, limit);
  final timeDim = dims.any((d) => d == 'hour' || d == 'day' || d == 'weekday');
  return WidgetOutcomeOk(
    columns: [
      for (final d in dims)
        Column(
          key: d,
          kind: ColumnKind.fromJson(_dimMeta[d]!.$2),
          label: _dimMeta[d]!.$1,
        ),
      for (final m in measures)
        Column(
          key: m,
          kind: ColumnKind.fromJson(_measureMeta[m]!.$2),
          label: _measureMeta[m]!.$1,
        ),
    ],
    grain: dims.isEmpty
        ? Grain.scalar
        : (timeDim ? Grain.series : Grain.categorical),
    period: PeriodInfo(
      from: period['from'] as String?,
      to: period['to'] as String?,
    ),
    rowCount: rows.length,
    rows: rows,
    truncated: truncated,
    viz: dims.isEmpty ? Viz.kpi : Viz.bar,
  ).toJson();
}

// ── branch sales and the analytics reads ──────────────────────────────────

final RegExp _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// `parse_uuid_csv("exclude_items", raw)`: 400 on an id that is not one.
Set<String>? _excludeItems(MockRequest req) {
  final raw = req.q('exclude_items');
  if (raw == null) return null;
  final out = <String>{};
  for (final part in raw.split(',')) {
    final p = part.trim();
    if (p.isEmpty) continue;
    if (!_uuid.hasMatch(p)) {
      req.badRequest('exclude_items: invalid UUID `$p`');
    }
    out.add(p.toLowerCase());
  }
  return out;
}

String? _categoryKeyOf(String menuItemId) {
  for (final m in seedMenu) {
    if (MockSeed.menuItemId(m.key) == menuItemId) return m.category;
  }
  return null;
}

/// `GET /reports/branches/{id}/sales` over [orders] (the scope's), as
/// `branch_sales` computes it.
BranchSalesReport opsBranchSales({
  required String branchId,
  required String branchName,
  required List<MockRow> orders,
  DateTime? from,
  DateTime? to,
  Set<String>? exclude,
  int limit = 20,
}) {
  final s = summarizeSales(orders);
  final seed = OpsSeed.instance;
  var lineItems = 0;
  var tips = 0;
  var cashTips = 0;
  final byItem = <String, (String, Map<String, Object?>, int, int)>{};
  for (final o in orders) {
    if (!_sold(o)) continue;
    final tip = _int(o['tip_amount']);
    tips += tip;
    final tipMethod = o['tip_payment_method'] ?? o['payment_method'];
    if (tipMethod == 'cash') cashTips += tip;
    for (final l in seed.linesOf(o)) {
      final id = l.menuItemId ?? '';
      if (exclude == null || !exclude.contains(id.toLowerCase())) {
        lineItems += l.quantity;
      }
      final prev = byItem[id];
      byItem[id] = (
        l.itemName,
        prev?.$2 ?? l.nameTranslations,
        (prev?.$3 ?? 0) + l.quantity,
        (prev?.$4 ?? 0) + l.lineTotal,
      );
    }
  }
  ItemSales item(
    MapEntry<String, (String, Map<String, Object?>, int, int)> e,
  ) => ItemSales(
    menuItemId: e.key,
    itemName: e.value.$1,
    itemNameTranslations: e.value.$2,
    quantitySold: e.value.$3,
    revenue: e.value.$4,
  );
  int rank(
    MapEntry<String, (String, Map<String, Object?>, int, int)> a,
    MapEntry<String, (String, Map<String, Object?>, int, int)> b,
  ) {
    final q = b.value.$3.compareTo(a.value.$3);
    if (q != 0) return q;
    final r = b.value.$4.compareTo(a.value.$4);
    if (r != 0) return r;
    return a.value.$1.compareTo(b.value.$1);
  }

  final ranked = byItem.entries.toList()..sort(rank);
  // Categories by name, items inside by quantity.
  final cats =
      <
        String,
        List<MapEntry<String, (String, Map<String, Object?>, int, int)>>
      >{};
  for (final e in ranked) {
    cats.putIfAbsent(_categoryKeyOf(e.key) ?? '', () => []).add(e);
  }
  String catName(String key) =>
      seedCategories.where((c) => c.key == key).firstOrNull?.name ??
      'Uncategorized';
  final catKeys = cats.keys.toList()
    ..sort((a, b) => catName(a).compareTo(catName(b)));
  return BranchSalesReport(
    branchId: branchId,
    branchName: branchName,
    from: from,
    to: to,
    totalOrders: s.orders,
    voidedOrders: s.voided,
    subtotal: s.subtotal,
    totalDiscount: s.discount,
    totalTax: s.tax,
    totalRevenue: s.revenue,
    grossSales: s.revenue,
    refundedAmount: 0,
    totalServiceCharge: 0,
    serviceChargeWaivedCount: 0,
    serviceChargeWaivedAmount: 0,
    totalDeliveryFees: 0,
    totalLineItems: lineItems,
    totalTips: tips,
    cashTips: cashTips,
    revenueByMethod: s.byMethod,
    topItems: [for (final e in ranked.take(limit.clamp(1, 1000))) item(e)],
    byCategory: [
      for (final k in catKeys)
        CategorySales(
          categoryId: k.isEmpty ? null : MockSeed.categoryId(k),
          categoryName: catName(k),
          categoryNameTranslations: () {
            final c = seedCategories.where((c) => c.key == k).firstOrNull;
            return c == null
                ? const <String, Object?>{}
                : <String, Object?>{'en': c.name, 'ar': c.ar};
          }(),
          itemCount: cats[k]!.length,
          quantitySold: cats[k]!.fold(0, (s, e) => s + e.value.$3),
          revenue: cats[k]!.fold(0, (s, e) => s + e.value.$4),
          items: [for (final e in cats[k]!) item(e)],
        ),
    ],
  );
}

/// `items-combined`: units of each menu item over the sold orders, most
/// first (the backend applies no limit).
List<CombinedItemSalesRow> opsCombinedItems(List<MockRow> orders) {
  final seed = OpsSeed.instance;
  final by = <String, (String, Map<String, Object?>, int)>{};
  for (final o in orders) {
    if (!_sold(o)) continue;
    for (final l in seed.linesOf(o)) {
      final id = l.menuItemId;
      if (id == null) continue;
      final p = by[id];
      by[id] = (
        l.itemName,
        p?.$2 ?? l.nameTranslations,
        (p?.$3 ?? 0) + l.quantity,
      );
    }
  }
  final rows = by.entries.toList()
    ..sort((a, b) {
      final q = b.value.$3.compareTo(a.value.$3);
      return q != 0 ? q : a.value.$1.compareTo(b.value.$1);
    });
  return [
    for (final e in rows)
      CombinedItemSalesRow(
        itemId: e.key,
        itemName: e.value.$1,
        itemNameTranslations: e.value.$2,
        standaloneQty: e.value.$3,
        totalQty: e.value.$3,
      ),
  ];
}

/// `addons`: units and revenue of each add-on, most first.
List<AddonSalesRow> opsAddonSales(MockDb db, List<MockRow> orders) {
  final seed = OpsSeed.instance;
  final by = <String, (String, Map<String, Object?>, int, int)>{};
  for (final o in orders) {
    if (!_sold(o)) continue;
    for (final l in seed.linesOf(o)) {
      for (final a in l.addons) {
        final p = by[a.addonItemId];
        by[a.addonItemId] = (
          a.addonName,
          p?.$2 ?? a.nameTranslations,
          (p?.$3 ?? 0) + a.quantity,
          (p?.$4 ?? 0) + a.lineTotal,
        );
      }
    }
  }
  String typeOf(String id) =>
      (db['addon_items'].find(id)?['type'] as String?) ?? 'extra';
  final rows = by.entries.toList()
    ..sort((a, b) {
      final q = b.value.$3.compareTo(a.value.$3);
      if (q != 0) return q;
      final r = b.value.$4.compareTo(a.value.$4);
      return r != 0 ? r : a.value.$1.compareTo(b.value.$1);
    });
  return [
    for (final e in rows)
      AddonSalesRow(
        addonItemId: e.key,
        addonName: e.value.$1,
        addonNameTranslations: e.value.$2,
        addonType: typeOf(e.key),
        quantitySold: e.value.$3,
        revenue: e.value.$4,
      ),
  ];
}

/// `tellers`: each teller's orders, revenue, average bill, voids and tills,
/// most revenue first.
List<TellerStats> opsTellerStats(List<MockRow> orders) {
  final by = <String, List<MockRow>>{};
  final names = <String, String>{};
  for (final o in orders) {
    final id = o['teller_id'] as String?;
    if (id == null) continue;
    by.putIfAbsent(id, () => []).add(o);
    names[id] = (o['teller_name'] as String?) ?? '';
  }
  final rows = [
    for (final e in by.entries)
      () {
        final sold = e.value.where(_sold).toList();
        final revenue = sold.fold<int>(
          0,
          (s, o) => s + _int(o['total_amount']),
        );
        return TellerStats(
          tellerId: e.key,
          tellerName: names[e.key]!,
          orders: sold.length,
          revenue: revenue,
          avgOrderValue: sold.isEmpty ? 0 : revenue ~/ sold.length,
          voided: e.value.where((o) => o['status'] == 'voided').length,
          shifts: {for (final o in e.value) o['till_id']}.length,
        );
      }(),
  ]..sort((a, b) => b.revenue.compareTo(a.revenue));
  return rows;
}

/// `waiters`: each waiter's orders (the orders that carry one), and how many
/// of the period's sold orders came through a waiter at all.
WaiterStatsReport opsWaiterStats(List<MockRow> orders) {
  final seed = OpsSeed.instance;
  final by = <String, (OpsWaiter, List<MockRow>)>{};
  var attributed = 0;
  var total = 0;
  for (final o in orders) {
    final w = seed.waiterOf[o['id']];
    if (_sold(o)) {
      total++;
      if (w != null) attributed++;
    }
    if (w == null) continue;
    (by[w.id] ??= (w, <MockRow>[])).$2.add(o);
  }
  final rows = [
    for (final (w, list) in by.values)
      () {
        final sold = list.where(_sold).toList();
        final revenue = sold.fold<int>(
          0,
          (s, o) => s + _int(o['total_amount']),
        );
        final items = sold.fold<int>(
          0,
          (s, o) => s + seed.linesOf(o).fold<int>(0, (a, l) => a + l.quantity),
        );
        return WaiterStats(
          waiterId: w.id,
          waiterName: w.name,
          orders: sold.length,
          revenue: revenue,
          avgOrderValue: sold.isEmpty ? 0 : revenue ~/ sold.length,
          voided: list.where((o) => o['status'] == 'voided').length,
          lineItems: items,
          avgItemsPerOrder: sold.isEmpty ? 0 : items / sold.length,
        );
      }(),
  ]..sort((a, b) => b.revenue.compareTo(a.revenue));
  return WaiterStatsReport(
    waiters: rows,
    attributedOrders: attributed,
    totalOrders: total,
  );
}

/// One branch's line of the org comparison.
BranchComparison opsBranchComparison(MockRow branch, List<MockRow> orders) {
  final s = summarizeSales(orders);
  var tips = 0;
  var cashTips = 0;
  for (final o in orders.where(_sold)) {
    final tip = _int(o['tip_amount']);
    tips += tip;
    if ((o['tip_payment_method'] ?? o['payment_method']) == 'cash') {
      cashTips += tip;
    }
  }
  return BranchComparison(
    branchId: branch['id']! as String,
    branchName: branch['name']! as String,
    totalOrders: s.orders,
    voidedOrders: s.voided,
    totalRevenue: s.revenue,
    grossSales: s.revenue,
    refundedAmount: 0,
    revenueByMethod: s.byMethod,
    totalTips: tips,
    cashTips: cashTips,
    avgOrderValue: s.orders == 0 ? 0 : s.revenue ~/ s.orders,
    voidRatePct: s.orders + s.voided == 0
        ? 0
        : s.voided / (s.orders + s.voided) * 100,
  );
}

// ── the export throttle ───────────────────────────────────────────────────

/// Exports per person per minute (`MADAR_EXPORT_MAX_PER_MINUTE`, default 10).
const int opsExportMaxPerMinute = 10;

final Expando<Map<String, List<DateTime>>> _exports = Expando();

/// The backend's export throttle (`rate_limit.rs` `throttle_exports`): a
/// request carrying `X-Madar-Export: 1` counts against the person's ten a
/// minute; past that it is refused 429 `EXPORT_RATE_LIMITED`. Shared by
/// every handler an export re-reads (one budget per server and person).
void checkExportThrottle(MockRequest req) {
  final h = req.headers['X-Madar-Export'] ?? req.headers['x-madar-export'];
  if (h != '1' && h != 'true') return;
  final log = _exports[req.server] ??= {};
  final now = req.now;
  final times = (log[req.persona.name] ??= [])
    ..removeWhere((t) => now.difference(t) >= const Duration(minutes: 1));
  if (times.length >= opsExportMaxPerMinute) {
    req.fail(
      MockResponse.error(
        429,
        'That is $opsExportMaxPerMinute exports in a minute. Give it a moment '
        'and try again — each one reads the whole filtered dataset.',
        code: 'EXPORT_RATE_LIMITED',
      ),
    );
  }
  times.add(now);
}

// ── handlers ──────────────────────────────────────────────────────────────

/// Whether a route of the same shape (`/orders/{x}` ~ `/orders/{order_id}`)
/// is already registered: an area loaded earlier owns it.
bool _handlesShape(MockServer server, String method, String template) {
  String shape(String t) => t.replaceAll(RegExp(r'\{[^}]+\}'), '{}');
  final want = '${method.toUpperCase()} ${shape(template)}';
  return server.routes.any((r) => shape(r) == want);
}

void registerOperationsMocks(MockServer server, MockDb db) {
  final seed = OpsSeed.instance;

  List<MockRow> scoped(MockRequest req, String branchId) => reportOrders(
    db,
    branchIds: reportBranchIds(req, branchId),
    from: req.qDateTime('from'),
    to: req.qDateTime('to'),
  );

  String label(String branchId) =>
      branchId == allBranchesId ? 'All branches' : _branchName(branchId);

  // REP-OPS-006 — the metrics layer, `tables` dataset. Gate `[reports
  // read]`; the branch comes from `X-Branch-Id` (absent/nil = every branch
  // the person may access); a widget that cannot run fails inside the 200.
  server.on('POST', '/metrics/query', (req) {
    req.requireCap('reports.read');
    final body = req.json;
    final widgets = (body['widgets'] as List?) ?? const [];
    if (widgets.isEmpty) req.badRequest('no widgets requested');
    if (widgets.length > 24) {
      req.badRequest('too many widgets in one request (max 24)');
    }
    // `accessible_branches`: the org in scope's branches this person works.
    final accessible = req.orgId != SeedIds.sabahOrg
        ? const <String>[]
        : [
            for (final b in SeedIds.sabahBranches)
              if (req.persona.seesBranch(b)) b,
          ];
    final header = req.branchHeader;
    final selected = header == null || header == allBranchesId
        ? null
        : accessible.where((b) => b == header).firstOrNull;
    final branchIds = selected == null ? accessible : [selected];
    final period = (body['period'] as Map?)?.cast<String, Object?>() ?? {};
    DateTime? instant(Object? v) =>
        v is String ? DateTime.tryParse(v)?.toUtc() : null;
    final facts = opsTableFacts(
      db,
      branchIds: branchIds,
      from: instant(period['from']),
      to: instant(period['to']),
    );
    final results = <String, Object?>{};
    for (final w in widgets) {
      if (w is! Map) continue;
      final key = '${w['key']}';
      final spec = (w['spec'] as Map?)?.cast<String, Object?>();
      if (spec == null) {
        results[key] = {'status': 'error', 'error': 'widget has no spec'};
        continue;
      }
      final out = _runTablesWidget(spec, facts, period);
      results[key] = out is String ? {'status': 'error', 'error': out} : out;
    }
    final names = [for (final b in branchIds) _branchName(b)];
    return MockResponse.ok({
      'scope': {
        'all_branches': selected == null,
        'branches': names,
        'label': selected != null
            ? names.single
            : names.isEmpty
            ? 'No branches'
            : names.length == 1
            ? names.single
            : 'All branches (${names.length})',
      },
      'timezone': MockClock.timezone,
      'results': results,
    });
  });

  // REP-OPS-025 — the floor's tables (`[floor_plan read]` + branch access).
  if (!_handlesShape(server, 'GET', '/floor/tables')) {
    server.on('GET', '/floor/tables', (req) {
      req.requireCap('floor.layout.read');
      final branchId = req.q('branch_id');
      if (branchId == null) {
        req.badRequest('Query deserialize error: missing field `branch_id`');
      }
      req.requireBranch(branchId);
      return MockResponse.ok(opsFloorRows(db, branchId));
    });
  }

  // REP-OPS-027 — a table's history (`[open_tickets read]`).
  if (!_handlesShape(server, 'GET', '/floor/tables/{id}/history')) {
    server.on('GET', '/floor/tables/{id}/history', (req) {
      req.requireCap('tickets.read');
      final to = req.qDateTime('to') ?? req.now;
      final from =
          req.qDateTime('from') ?? to.subtract(const Duration(days: 30));
      if (!from.isBefore(to)) req.badRequest('`from` must be before `to`');
      final id = req.param('id');
      final live = db.hasTable('floor_tables')
          ? db['floor_tables'].find(id)
          : null;
      final plan = opsTableById(id);
      if (live == null && (plan == null || plan.retired != null)) {
        req.notFound('table not found');
      }
      final branchId = (live?['branch_id'] as String?) ?? plan!.branchId;
      final tableLabel = (live?['label'] as String?) ?? plan!.label;
      req.requireBranch(branchId);
      final now = req.now;
      final sittings = <TableSitting>[];
      for (final s in seed.sittings.reversed) {
        if (s.table.id != id) continue;
        if (s.seatedAt.isBefore(from) || !s.seatedAt.isBefore(to)) continue;
        if (s.seatedAt.isAfter(now)) continue;
        final order = s.orderId == null ? null : db['orders'].find(s.orderId!);
        final status = order == null
            ? 'open'
            : (order['status'] == 'voided' ? 'voided' : 'settled');
        final closed = order == null
            ? null
            : (order['status'] == 'voided'
                  ? DateTime.tryParse('${order['voided_at']}')?.toUtc() ??
                        _at(order)
                  : _at(order));
        sittings.add(
          TableSitting(
            openTicketId: s.ticketId,
            ticketRef: s.ticketRef,
            openedAt: s.seatedAt,
            seatedAt: s.seatedAt,
            closedAt: closed,
            minutes: math.max(
              0,
              (closed ?? now).difference(s.seatedAt).inMinutes,
            ),
            status: status,
            customerName: s.customerName,
            customerId: s.customerId,
            guestCount: s.covers,
            orderId: order?['id'] as String?,
            orderNumber: (order?['order_number'] as num?)?.toInt(),
            totalAmount: order == null || order['status'] == 'voided'
                ? null
                : _int(order['total_amount']),
          ),
        );
      }
      final settled = [
        for (final s in sittings)
          if (s.totalAmount != null) s,
      ];
      final total = settled.fold<int>(0, (a, s) => a + s.totalAmount!);
      final minutes = settled.fold<int>(0, (a, s) => a + s.minutes);
      final days = math.max(to.difference(from).inMinutes / (24 * 60), 1 / 24);
      return MockResponse.ok(
        TableHistory(
          tableId: id,
          label: tableLabel,
          from: from,
          to: to,
          sittings: sittings,
          covers: settled.fold<int>(0, (a, s) => a + (s.guestCount ?? 0)),
          settledCount: settled.length,
          totalMinor: total,
          averageBillMinor: settled.isEmpty ? 0 : total ~/ settled.length,
          averageMinutes: settled.isEmpty ? 0 : minutes ~/ settled.length,
          turnsPerDayX100: (settled.length / days * 100).round(),
        ),
      );
    });
  }

  // REP-OPS-034 — branch sales (`[orders read]` + branch access).
  server.on('GET', '/reports/branches/{branchId}/sales', (req) {
    req.requireCap('orders.read');
    checkExportThrottle(req);
    final id = req.param('branchId');
    final exclude = _excludeItems(req);
    return MockResponse.ok(
      opsBranchSales(
        branchId: id,
        branchName: label(id),
        orders: scoped(req, id),
        from: req.qDateTime('from'),
        to: req.qDateTime('to'),
        exclude: exclude,
        limit: req.qInt('limit') ?? 20,
      ),
    );
  });

  // REP-OPS-047 — combined item sales.
  server.on('GET', '/reports/branches/{branchId}/items-combined', (req) {
    req.requireCap('orders.read');
    checkExportThrottle(req);
    return MockResponse.ok(
      opsCombinedItems(scoped(req, req.param('branchId'))),
    );
  });

  // REP-OPS-048 — add-on sales.
  server.on('GET', '/reports/branches/{branchId}/addons', (req) {
    req.requireCap('orders.read');
    checkExportThrottle(req);
    return MockResponse.ok(
      opsAddonSales(db, scoped(req, req.param('branchId'))),
    );
  });

  // REP-OPS-049 — teller stats.
  server.on('GET', '/reports/branches/{branchId}/tellers', (req) {
    req.requireCap('orders.read');
    checkExportThrottle(req);
    return MockResponse.ok(opsTellerStats(scoped(req, req.param('branchId'))));
  });

  // REP-OPS-051 — waiter stats.
  server.on('GET', '/reports/branches/{branchId}/waiters', (req) {
    req.requireCap('orders.read');
    checkExportThrottle(req);
    return MockResponse.ok(opsWaiterStats(scoped(req, req.param('branchId'))));
  });

  // REP-OPS-054/066 — every branch of the org, NOT narrowed to the caller's
  // branches (`org_branch_comparison`).
  server.on('GET', '/reports/orgs/{orgId}/comparison', (req) {
    req.requireCap('orders.read');
    checkExportThrottle(req);
    final orgId = req.param('orgId');
    if (!req.persona.isPlatform && req.persona.orgId != orgId) {
      req.fail(MockResponse.forbidden('Not your org'));
    }
    final from = req.qDateTime('from');
    final to = req.qDateTime('to');
    final rows = [
      for (final b in db['branches'].rows)
        if (b['org_id'] == orgId && b['deleted_at'] == null)
          opsBranchComparison(
            b,
            reportOrders(
              db,
              branchIds: [b['id']! as String],
              from: from,
              to: to,
            ),
          ),
    ]..sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));
    return MockResponse.ok(
      OrgComparisonReport(orgId: orgId, from: from, to: to, branches: rows),
    );
  });

  // REP-OPS-039 — the menu the exclude control lists (catalog's route when
  // that area is loaded).
  if (!_handlesShape(server, 'GET', '/menu-items')) {
    server.on('GET', '/menu-items', (req) {
      req.requireCap('menu.items.read');
      final orgId = req.q('org_id');
      if (orgId == null) {
        req.badRequest('Query deserialize error: missing field `org_id`');
      }
      req.requireSameOrg(orgId);
      return MockResponse.ok(
        db['menu_items'].query(
          filters: {'org_id': orgId, 'category_id': req.q('category_id')},
          where: (m) => m['deleted_at'] == null,
          sort: 'name',
        ),
      );
    });
  }

  // REP-OPS-032 — the customer a sitting links to (read-only; the sell
  // area's richer route wins when it is loaded).
  if (!_handlesShape(server, 'GET', '/customers/{id}')) {
    server.on('GET', '/customers/{id}', (req) {
      req.requireCap('customers.view');
      final c = db['customers'].get(
        req.param('id'),
        what: 'Customer not found',
      );
      final id = c['id'];
      final orders = [
        for (final o in db['orders'].rows.reversed)
          if (o['customer_id'] == id) o,
      ];
      return MockResponse.ok(
        CustomerDetail(
          customer: Customer.fromJson(c),
          mergedFrom: const [],
          recentOrders: [
            for (final o in orders.take(10))
              CustomerOrder(
                branchId: o['branch_id']! as String,
                branchName: _branchName(o['branch_id']! as String),
                createdAt: _at(o),
                id: o['id']! as String,
                orderRef: o['order_ref'] as String?,
                status: '${o['status']}',
                totalAmount: _int(o['total_amount']),
              ),
          ],
        ),
      );
    });
  }

  // REP-OPS-032 — one of the customer's orders, with its lines.
  if (!_handlesShape(server, 'GET', '/orders/{order_id}')) {
    server.on('GET', '/orders/{order_id}', (req) {
      req.requireCap('orders.read');
      final o = db['orders'].get(
        req.param('order_id'),
        what: 'Order not found',
      );
      req.requireBranch(o['branch_id']! as String);
      return MockResponse.ok({
        ...o,
        'items': [for (final l in seed.linesOf(o)) l.toJson()],
      });
    });
  }
}
