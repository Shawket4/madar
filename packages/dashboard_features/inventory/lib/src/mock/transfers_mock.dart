/// Transfers: the mock backend for the INV-TRF rows (af50aa63: a transfer is
/// a document with lines that is requested, drafted, sent, received or
/// cancelled). Routes this unit owns (the only file that registers them):
///
/// - GET /inventory/branches/{branch_id}/transfers (listTransfers)
/// - GET /inventory/orgs/{org_id}/transfer-locations (transferLocations)
/// - GET /inventory/orgs/{org_id}/transfer-differences (transferDifferences)
/// - GET /inventory/warehouses/{warehouse_id}/replenishment (replenishment)
/// - POST /inventory/transfers (createTransfer)
/// - PATCH /inventory/transfers/{id} (updateTransfer)
/// - POST /inventory/transfers/{id}/accept | decline | dispatch | receive |
///   cancel
///
/// As the backend (`MadarRust/src/inventory/transfers.rs` @ 87340e2): every
/// step reads the transfer (404 / same org), looks it up in the step table
/// (409 `TRANSFER_STEP_NOT_OPEN`) and requires the step's capability AT its
/// side (403 when the persona does not work there). Dispatch takes the stock
/// off the source (`transfer_out`, 409 `TRANSFER_INSUFFICIENT_STOCK` when
/// short) and freezes each line's cost; receive lands what arrived at the
/// destination (`transfer_in`); cancelling in transit lands it back.
///
/// Data: the area seed's five one-line transfers become received documents
/// (TR-1…TR-5, their stock already moved); TR-6 (requested), TR-7 (draft)
/// and TR-8 (cancelled) move nothing. A transfer in transit or received
/// short is made through [transferDispatch] / [transferReceive], which move
/// stock like the handlers.
library;

import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';
import 'inventory_views.dart';

const String _allBranches = '00000000-0000-0000-0000-000000000000';

/// The step table (`madar_inventory::transfer::step`): status → action →
/// (side is the source, next status).
const Map<String, Map<String, (bool, String)>> _steps = {
  'requested': {
    'edit': (false, 'requested'),
    'cancel': (false, 'cancelled'),
    'accept': (true, 'draft'),
    'decline': (true, 'cancelled'),
  },
  'draft': {
    'edit': (true, 'draft'),
    'dispatch': (true, 'dispatched'),
    'cancel': (true, 'cancelled'),
  },
  'dispatched': {
    'receive': (false, 'received'),
    'cancel': (true, 'cancelled'),
  },
};

String _stepCap(String status, String action) => action == 'receive'
    ? 'inventory.transfers.edit'
    : action == 'cancel' && status == 'dispatched'
    ? 'inventory.transfers.delete'
    : 'inventory.transfers.create';

String _past(String action) =>
    action.endsWith('e') ? '${action}d' : '${action}ed';

/// A quantity in whole thousandths (`madar_inventory::milli`).
int _milli(num q) {
  final m = (q.abs() * 1000).round();
  return q < 0 ? -m : m;
}

double _round3(num q) => _milli(q) / 1000;

/// `Decimal::round()`: half to even.
int _roundEven(double v) {
  final f = v.floorToDouble();
  final d = v - f;
  if (d != 0.5) return v.round();
  return f.toInt().isEven ? f.toInt() : f.toInt() + 1;
}

String? _trimmed(Object? v) {
  final s = v is String ? v.trim() : null;
  return s == null || s.isEmpty ? null : s;
}

Map<String, Object?> _stamp(String at, String by, String name) => {
  'at': at,
  'by': by,
  'by_name': name,
};

/// A seed transfer of [lines] (ingredient key, quantity).
class _Doc {
  const _Doc(
    this.key,
    this.status,
    this.from,
    this.to,
    this.by,
    this.at,
    this.lines, {
    this.note,
    this.closedAt,
  });

  final String key;
  final String status;
  final String from;
  final String to;
  final String by;
  final String at;
  final List<(String, double)> lines;
  final String? note;
  final String? closedAt;
}

const List<_Doc> _docs = [
  _Doc(
    't6',
    'requested',
    'maadi',
    'zamalek',
    'karim',
    '2026-10-07T09:10:00Z',
    [('oat', 1500), ('house-blend', 1000)],
    note: 'Weekend rush: please send before Friday',
  ),
  _Doc('t7', 'draft', 'maadi', 'heliopolis', 'tarek', '2026-10-07T15:30:00Z', [
    ('croissant', 10),
    ('vanilla-syrup', 300),
  ]),
  _Doc(
    't8',
    'cancelled',
    'new-cairo',
    'zamalek',
    'dina',
    '2026-10-02T11:00:00Z',
    [('caramel-syrup', 500)],
    note: 'Zamalek got its own delivery instead',
    closedAt: '2026-10-02T13:20:00Z',
  ),
];

String _branchId(String key) => switch (key) {
  'heliopolis' => SeedIds.heliopolis,
  'maadi' => SeedIds.maadi,
  'new-cairo' => SeedIds.newCairo,
  _ => SeedIds.zamalek,
};

MockRow? _branch(MockDb db, String id) => db['branches'].find(id);

String _kind(MockRow? b) => b?['kind'] as String? ?? 'branch';

/// The cost a line carries out of [branchId] (the branch's, else the
/// catalog's), in piastres per unit.
double? _cost(MockDb db, String branchId, MockRow ing) =>
    (InvViews.stockRecord(db, branchId, ing['id']! as String)?['cost_per_unit']
            as num?)
        ?.toDouble() ??
    (ing['cost_per_unit'] as num?)?.toDouble();

MockRow _line(
  String transferId,
  int n,
  MockRow ing, {
  required double qty,
  double? received,
  double? cost,
  String? note,
}) => {
  'id': mockUuid('transfer-line:$transferId:$n'),
  'org_ingredient_id': ing['id'],
  'ingredient_name': ing['name'],
  'unit': ing['unit'],
  'qty_sent': qty,
  'qty_received': received,
  'unit_cost': cost,
  'note': note,
};

List<MockRow> _linesOf(MockRow t) =>
    (t['lines']! as List).cast<MockRow>().toList();

void _sortLines(MockRow t) => t['lines'] = _linesOf(t)
  ..sort(
    (a, b) => (a['ingredient_name']! as String).compareTo(
      b['ingredient_name']! as String,
    ),
  );

/// Rewrites the area seed's one-line rows as received documents and adds
/// the documents in [_docs]; a second call changes nothing.
void _seed(MockDb db) {
  final table = db[InvTables.transfers];
  if (table.rows.any((r) => r.containsKey('lines'))) return;
  final old = table.rows.toList()
    ..sort(
      (a, b) => (a['initiated_at']! as String).compareTo(
        b['initiated_at']! as String,
      ),
    );
  var n = 0;
  for (final r in old) {
    final id = r['id']! as String;
    final src = r['source_branch_id']! as String;
    final dst = r['destination_branch_id']! as String;
    final ing = db[InvTables.ingredients].find(
      r['org_ingredient_id']! as String,
    )!;
    final qty = (r['quantity']! as num).toDouble();
    final at = r['initiated_at']! as String;
    final stamp = _stamp(
      at,
      r['initiated_by']! as String,
      r['initiated_by_name']! as String,
    );
    table.put({
      'id': id,
      'org_id': r['org_id'],
      'number': ++n,
      'reference': 'TR-$n',
      'status': 'received',
      'source_branch_id': src,
      'source_branch_name': r['source_branch_name'],
      'source_kind': _kind(_branch(db, src)),
      'destination_branch_id': dst,
      'destination_branch_name': r['destination_branch_name'],
      'destination_kind': _kind(_branch(db, dst)),
      'note': r['note'],
      'created': stamp,
      'requested': null,
      'dispatched': stamp,
      'received': stamp,
      'cancelled': null,
      'lines': [
        _line(id, 1, ing, qty: qty, received: qty, cost: _cost(db, src, ing)),
      ],
    });
  }
  for (final d in _docs) {
    final id = InvIds.transfer(d.key);
    final src = _branchId(d.from), dst = _branchId(d.to);
    final stamp = _stamp(
      d.at,
      SeedIds.user(d.by),
      InventorySeed.personName(d.by),
    );
    var i = 0;
    final doc = table.insert({
      'id': id,
      'org_id': SeedIds.sabahOrg,
      'number': ++n,
      'reference': 'TR-$n',
      'status': d.status,
      'source_branch_id': src,
      'source_branch_name': InvScope.branchName(db, src),
      'source_kind': _kind(_branch(db, src)),
      'destination_branch_id': dst,
      'destination_branch_name': InvScope.branchName(db, dst),
      'destination_kind': _kind(_branch(db, dst)),
      'note': d.note,
      'created': stamp,
      'requested': d.status == 'requested' ? stamp : null,
      'dispatched': null,
      'received': null,
      'cancelled': d.closedAt == null
          ? null
          : _stamp(
              d.closedAt!,
              SeedIds.user(d.by),
              InventorySeed.personName(d.by),
            ),
      'lines': [
        for (final (key, qty) in d.lines)
          _line(
            id,
            ++i,
            db[InvTables.ingredients].find(InvIds.ingredient(key))!,
            qty: qty,
          ),
      ],
    }, timestamps: false);
    _sortLines(doc);
  }
}

/// The transfers touching [ids] (null = every location of [orgId]) in
/// [direction] and [status], newest first.
List<MockRow> transfersOf(
  MockDb db, {
  required String orgId,
  Set<String>? ids,
  String? direction,
  String? status,
}) {
  bool at(Object? b) => ids == null || ids.contains(b);
  bool hit(MockRow t) {
    if (t['org_id'] != orgId) return false;
    if (status != null && t['status'] != status) return false;
    return switch (direction) {
      'incoming' => at(t['destination_branch_id']),
      'outgoing' => at(t['source_branch_id']),
      _ => at(t['source_branch_id']) || at(t['destination_branch_id']),
    };
  }

  String created(MockRow t) => (t['created']! as Map)['at']! as String;
  return db[InvTables.transfers].where(hit)..sort((a, b) {
    final c = DateTime.parse(created(b)).compareTo(DateTime.parse(created(a)));
    return c != 0 ? c : (b['number']! as int).compareTo(a['number']! as int);
  });
}

/// Moves [qty] (signed) of [ing] at [branchId], with its movement; stock
/// landing at [cost] blends into the branch's average cost (`land`).
void _move(
  MockDb db,
  Persona who, {
  required String branchId,
  required MockRow ing,
  required String type,
  required double qty,
  required double? cost,
  required String transferId,
  required String note,
}) {
  final now = db.nowIso;
  final ingId = ing['id']! as String;
  final rec =
      InvViews.stockRecord(db, branchId, ingId) ??
      db[InvTables.branchStock].insert({
        'id': db.newId(InvTables.branchStock),
        'branch_id': branchId,
        'org_ingredient_id': ingId,
        'on_hand': 0.0,
        'par_min': null,
        'par_max': null,
        'cost_per_unit': null,
        'last_counted_at': null,
        'last_movement_at': null,
      }, timestamps: false);
  final prior = (rec['on_hand']! as num).toDouble();
  final balance = _round3(prior + qty);
  if (qty > 0 && cost != null) {
    final priorCost = (rec['cost_per_unit'] as num?)?.toDouble();
    rec['cost_per_unit'] = prior <= 0 || priorCost == null
        ? cost
        : (prior * priorCost + qty * cost) / balance;
  }
  rec
    ..['on_hand'] = balance
    ..['last_movement_at'] = now;
  db[InvTables.movements].insert({
    'branch_id': branchId,
    'branch_name': InvScope.branchName(db, branchId),
    'branch_stock_id': rec['id'],
    'org_ingredient_id': ingId,
    'ingredient_name': ing['name'],
    'unit': ing['unit'],
    'movement_type': type,
    'quantity': qty,
    'balance_after': balance,
    'below_zero': balance < 0,
    'unit_cost': cost,
    'reason': null,
    'note': note,
    'source_type': 'transfer',
    'source_id': transferId,
    'created_at': now,
    'created_by': who.userId,
    'created_by_name': who.displayName,
  }, timestamps: false);
}

void _setStatus(MockDb db, MockRow t, String to, Persona who) {
  t['status'] = to;
  final col = switch (to) {
    'dispatched' => 'dispatched',
    'received' => 'received',
    'cancelled' => 'cancelled',
    _ => null,
  };
  if (col != null) t[col] = _stamp(db.nowIso, who.userId, who.displayName);
}

/// Adds [note] (trimmed) as a new line of the transfer's note.
void _appendNote(MockRow t, String? note) {
  if (note == null) return;
  final was = t['note'] as String?;
  t['note'] = was == null || was.isEmpty ? note : '$was\n$note';
}

/// The dispatch step's effect (no gate): checks the source holds every
/// line (409 `TRANSFER_INSUFFICIENT_STOCK`), freezes each line's cost and
/// takes the stock off the source. [req] carries the refusal; without one a
/// short source throws [StateError].
void transferDispatch(MockDb db, MockRow t, Persona who, {MockRequest? req}) {
  final src = t['source_branch_id']! as String;
  final lines = _linesOf(t);
  final short = [
    for (final l in lines)
      if (_milli(_onHand(db, src, l['org_ingredient_id']! as String)) <
          _milli(l['qty_sent']! as num))
        '${l['ingredient_name']} '
            '(${_onHand(db, src, l['org_ingredient_id']! as String).toStringAsFixed(3)} on hand)',
  ];
  if (short.isNotEmpty) {
    final reason = 'Not enough stock to send: ${short.join(', ')}.';
    if (req == null) throw StateError(reason);
    req.conflict(reason, code: 'TRANSFER_INSUFFICIENT_STOCK');
  }
  for (final l in lines) {
    final ing = db[InvTables.ingredients].find(
      l['org_ingredient_id']! as String,
    )!;
    final cost = _cost(db, src, ing);
    l['unit_cost'] = cost;
    _move(
      db,
      who,
      branchId: src,
      ing: ing,
      type: 'transfer_out',
      qty: -(l['qty_sent']! as num).toDouble(),
      cost: cost,
      transferId: t['id']! as String,
      note: 'Transfer out',
    );
  }
  _setStatus(db, t, 'dispatched', who);
}

/// The receive step's effect (no gate, no checks): [got] maps a line id to
/// what arrived (and its note); missing lines arrive as sent.
void transferReceive(
  MockDb db,
  MockRow t,
  Persona who, {
  Map<String, (double, String?)> got = const {},
}) {
  for (final l in _linesOf(t)) {
    final (qty, note) =
        got[l['id']] ?? ((l['qty_sent']! as num).toDouble(), null);
    l['qty_received'] = _round3(qty);
    if (note != null) {
      final was = l['note'] as String?;
      l['note'] = was == null ? note : '$was\n$note';
    }
    if (_milli(qty) > 0) {
      _move(
        db,
        who,
        branchId: t['destination_branch_id']! as String,
        ing: db[InvTables.ingredients].find(l['org_ingredient_id']! as String)!,
        type: 'transfer_in',
        qty: _round3(qty),
        cost: (l['unit_cost'] as num?)?.toDouble(),
        transferId: t['id']! as String,
        note: 'Transfer in',
      );
    }
  }
  _setStatus(db, t, 'received', who);
}

double _onHand(MockDb db, String branchId, String ingId) =>
    (InvViews.stockRecord(db, branchId, ingId)?['on_hand'] as num?)
        ?.toDouble() ??
    0;

/// `madar_inventory::replenish::suggest`.
({double need, double available, double suggested}) replenishSuggest({
  required double onHand,
  required double parMin,
  required double? parMax,
  required double inTransit,
  required double openInbound,
  required double warehouseOnHand,
  required double warehouseDraftedOut,
}) {
  final hand = _milli(onHand), min = _milli(parMin);
  var need = 0;
  if (min > 0 && hand <= min) {
    final max = parMax == null ? min : _milli(parMax);
    final target = max > min ? max : min;
    need = target - hand - _milli(inTransit) - _milli(openInbound);
    if (need < 0) need = 0;
  }
  var available = _milli(warehouseOnHand) - _milli(warehouseDraftedOut);
  if (available < 0) available = 0;
  return (
    need: need / 1000,
    available: available / 1000,
    suggested: (need < available ? need : available) / 1000,
  );
}

void registerTransfersMocks(MockServer server, MockDb db) {
  _seed(db);

  /// `authorize`: the gate, the transfer (404, same org), the step table
  /// (409) and the step's capability at its side; returns (transfer, next).
  (MockRow, String) authorize(MockRequest req, String action) {
    req.requireCap(
      action == 'receive'
          ? 'inventory.transfers.edit'
          : 'inventory.transfers.create',
    );
    final t = db[InvTables.transfers].find(req.param('id'));
    if (t == null) req.notFound('Transfer not found');
    req.requireSameOrg(t['org_id'] as String?);
    final status = t['status']! as String;
    final step = _steps[status]?[action];
    if (step == null) {
      req.conflict(
        "A $status transfer can't be ${_past(action)}.",
        code: 'TRANSFER_STEP_NOT_OPEN',
      );
    }
    req.requireCap(
      _stepCap(status, action),
      branchId: step.$1
          ? t['source_branch_id']! as String
          : t['destination_branch_id']! as String,
    );
    return (t, step.$2);
  }

  /// `validate_lines` then the lines as stored (cost unset).
  List<MockRow> lines(MockRequest req, String orgId, String id, Object? raw) {
    final list = raw is List ? raw : const [];
    if (list.isEmpty) req.badRequest('A transfer needs at least one item.');
    if (list.length > 500) {
      req.badRequest('A transfer can carry at most 500 items.');
    }
    final seen = <String>{};
    for (final l in list) {
      final q = l is Map ? l['quantity'] : null;
      if (q is! num || !q.isFinite || _milli(q) <= 0) {
        req.badRequest('Every quantity must be greater than 0.');
      }
      if (!seen.add('${(l as Map)['org_ingredient_id']}')) {
        req.badRequest('Each item can appear only once on a transfer.');
      }
    }
    final out = <MockRow>[];
    var n = 0;
    for (final l in list.cast<Map>()) {
      final ing = db[InvTables.ingredients].find('${l['org_ingredient_id']}');
      if (ing == null || ing['org_id'] != orgId) {
        req.badRequest("An item is not in this organization's catalog.");
      }
      out.add(
        _line(
          id,
          ++n,
          ing,
          qty: _round3(l['quantity']! as num),
          note: _trimmed(l['note']),
        ),
      );
    }
    return out;
  }

  void setLines(MockRow t, List<MockRow> next) {
    // Fresh line ids on every replace, as the backend's delete + insert.
    t['lines'] = [
      for (final (i, l) in next.indexed)
        {...l, 'id': mockUuid('transfer-line:${t['id']}:${db.newId('tl')}:$i')},
    ];
    _sortLines(t);
  }

  server.on('GET', '/inventory/branches/{branch_id}/transfers', (req) {
    final id = req.param('branch_id');
    final String orgId;
    Set<String>? ids;
    if (id == _allBranches) {
      req.requireCap('inventory.transfers.read');
      final org = req.orgId;
      if (org == null) {
        req.fail(MockResponse.forbidden('No organization in scope'));
      }
      orgId = org;
      final mine = req.persona.branchIds;
      ids = mine?.toSet();
    } else {
      req.requireCap('inventory.transfers.read', branchId: id);
      final b = db['branches'].find(id);
      if (b == null) req.notFound('Branch not found');
      req.requireSameOrg(b['org_id'] as String?);
      orgId = b['org_id']! as String;
      ids = {id};
    }
    final status = req.q('status');
    const known = {'requested', 'draft', 'dispatched', 'received', 'cancelled'};
    if (status != null && status.isNotEmpty && !known.contains(status)) {
      req.badRequest('Unknown transfer status.');
    }
    return MockResponse.ok(
      sliceOf(
        transfersOf(
          db,
          orgId: orgId,
          ids: ids,
          direction: req.q('direction'),
          status: status == null || status.isEmpty ? null : status,
        ),
        req,
        defaultLimit: 100,
        maxLimit: 500,
      ),
    );
  });

  server.on('GET', '/inventory/orgs/{org_id}/transfer-locations', (req) {
    final org = req.param('org_id');
    req.requireSameOrg(org);
    req.requireCap('inventory.transfers.create');
    final rows = db['branches'].where(
      (b) => b['org_id'] == org && b['is_active'] != false,
    )..sort((a, b) {
      final k = _kind(a).compareTo(_kind(b));
      return k != 0 ? k : (a['name']! as String).compareTo(b['name']! as String);
    });
    return MockResponse.ok([
      for (final b in rows) {'id': b['id'], 'name': b['name'], 'kind': _kind(b)},
    ]);
  });

  server.on('GET', '/inventory/orgs/{org_id}/transfer-differences', (req) {
    final org = req.param('org_id');
    req.requireSameOrg(org);
    req.requireCap('inventory.transfers.read');
    final from = req.qDateTime('from'), to = req.qDateTime('to');
    final mine = req.persona.branchIds;
    final out = <MockRow>[];
    for (final t in db[InvTables.transfers].rows) {
      if (t['org_id'] != org || t['status'] != 'received') continue;
      if (mine != null &&
          !mine.contains(t['source_branch_id']) &&
          !mine.contains(t['destination_branch_id'])) {
        continue;
      }
      final at = DateTime.parse((t['received']! as Map)['at']! as String);
      if (from != null && at.isBefore(from)) continue;
      if (to != null && !at.isBefore(to)) continue;
      for (final l in _linesOf(t)) {
        final sent = (l['qty_sent']! as num).toDouble();
        final got = (l['qty_received']! as num).toDouble();
        if (_milli(got) == _milli(sent)) continue;
        final diff = (_milli(got) - _milli(sent)) / 1000;
        final cost = (l['unit_cost'] as num?)?.toDouble();
        out.add({
          'transfer_id': t['id'],
          'reference': t['reference'],
          'received_at': at.toUtc().toIso8601String(),
          'source_branch_name': t['source_branch_name'],
          'destination_branch_name': t['destination_branch_name'],
          'org_ingredient_id': l['org_ingredient_id'],
          'ingredient_name': l['ingredient_name'],
          'unit': l['unit'],
          'qty_sent': sent,
          'qty_received': got,
          'difference': diff,
          'unit_cost': cost,
          'value_difference': cost == null ? null : _roundEven(diff * cost),
          'note': l['note'],
        });
      }
    }
    out.sort((a, b) {
      final c = (b['received_at']! as String).compareTo(
        a['received_at']! as String,
      );
      return c != 0
          ? c
          : (a['ingredient_name']! as String).compareTo(
              b['ingredient_name']! as String,
            );
    });
    return MockResponse.ok(out.take(2000).toList());
  });

  server.on('GET', '/inventory/warehouses/{warehouse_id}/replenishment', (
    req,
  ) {
    final wh = req.param('warehouse_id');
    final branch = req.q('branch_id');
    if (branch == null) {
      req.badRequest('Query deserialize error: missing field `branch_id`');
    }
    req.requireCap('inventory.transfers.read', branchId: wh);
    final w = _branch(db, wh), b = _branch(db, branch);
    if (w == null || b == null || w['org_id'] != b['org_id'] || wh == branch) {
      req.notFound('Warehouse or branch not found');
    }
    if (_kind(w) != 'warehouse') {
      req.badRequest('Replenishment comes from a warehouse.');
    }
    req.requireSameOrg(w['org_id'] as String?);
    double sum(bool Function(MockRow t) hit, String ingId) {
      var s = 0.0;
      for (final t in db[InvTables.transfers].where(hit)) {
        for (final l in _linesOf(t)) {
          if (l['org_ingredient_id'] == ingId) {
            s += (l['qty_sent']! as num).toDouble();
          }
        }
      }
      return s;
    }

    final rows = [
      for (final r in InvViews.branchStock(db, branch))
        if (((r['par_min'] as num?) ?? 0) > 0 &&
            (r['on_hand']! as num) <= (r['par_min']! as num))
          r,
    ]..sort((a, b) {
      final c = (a['category_name']! as String).compareTo(
        b['category_name']! as String,
      );
      return c != 0
          ? c
          : (a['ingredient_name']! as String).compareTo(
              b['ingredient_name']! as String,
            );
    });
    return MockResponse.ok([
      for (final r in rows)
        () {
          final ing = r['org_ingredient_id']! as String;
          final inTransit = sum(
            (t) =>
                t['destination_branch_id'] == branch &&
                t['status'] == 'dispatched',
            ing,
          );
          final inbound = sum(
            (t) =>
                t['destination_branch_id'] == branch &&
                (t['status'] == 'requested' || t['status'] == 'draft'),
            ing,
          );
          final whHand = _onHand(db, wh, ing);
          final s = replenishSuggest(
            onHand: (r['on_hand']! as num).toDouble(),
            parMin: (r['par_min']! as num).toDouble(),
            parMax: (r['par_max'] as num?)?.toDouble(),
            inTransit: inTransit,
            openInbound: inbound,
            warehouseOnHand: whHand,
            warehouseDraftedOut: sum(
              (t) => t['source_branch_id'] == wh && t['status'] == 'draft',
              ing,
            ),
          );
          return {
            'org_ingredient_id': ing,
            'ingredient_name': r['ingredient_name'],
            'unit': r['unit'],
            'category_name': r['category_name'],
            'on_hand': r['on_hand'],
            'par_min': r['par_min'],
            'par_max': r['par_max'],
            'in_transit': inTransit,
            'open_inbound': inbound,
            'warehouse_on_hand': whHand,
            'need': s.need,
            'available': s.available,
            'suggested': s.suggested,
          };
        }(),
    ]);
  });

  server.on('POST', '/inventory/transfers', (req) {
    final body = req.json;
    final src = body['source_branch_id'], dst = body['destination_branch_id'];
    if (src is! String || dst is! String) {
      req.badRequest(
        'Json deserialize error: missing field `source_branch_id`',
      );
    }
    if (src == dst) req.badRequest('Pick two different locations.');
    final request = body['request'] == true;
    req.requireCap(
      'inventory.transfers.create',
      branchId: request ? dst : src,
    );
    final s = _branch(db, src), d = _branch(db, dst);
    if (s == null || d == null || s['org_id'] != d['org_id']) {
      req.badRequest(
        'Both locations must exist and belong to the same organization.',
      );
    }
    final org = s['org_id']! as String;
    req.requireSameOrg(org);
    final id = db.newId(InvTables.transfers);
    final next = lines(req, org, id, body['lines']);
    final number =
        db[InvTables.transfers].rows
            .where((t) => t['org_id'] == org)
            .fold(0, (m, t) => (t['number']! as int) > m ? t['number']! as int : m) +
        1;
    final who = req.persona;
    final stamp = _stamp(db.nowIso, who.userId, who.displayName);
    final t = db[InvTables.transfers].insert({
      'id': id,
      'org_id': org,
      'number': number,
      'reference': 'TR-$number',
      'status': request ? 'requested' : 'draft',
      'source_branch_id': src,
      'source_branch_name': s['name'],
      'source_kind': _kind(s),
      'destination_branch_id': dst,
      'destination_branch_name': d['name'],
      'destination_kind': _kind(d),
      'note': _trimmed(body['note']),
      'created': stamp,
      'requested': request ? stamp : null,
      'dispatched': null,
      'received': null,
      'cancelled': null,
      'lines': next,
    }, timestamps: false);
    _sortLines(t);
    return MockResponse.created(t);
  });

  server.on('PATCH', '/inventory/transfers/{id}', (req) {
    final (t, _) = authorize(req, 'edit');
    final body = req.json;
    if (body['lines'] != null) {
      setLines(
        t,
        lines(req, t['org_id']! as String, t['id']! as String, body['lines']),
      );
    }
    if (body.containsKey('note') && body['note'] != null) {
      t['note'] = _trimmed(body['note']);
    }
    return MockResponse.ok(t);
  });

  server.on('POST', '/inventory/transfers/{id}/accept', (req) {
    final (t, next) = authorize(req, 'accept');
    final body = req.json;
    if (body['lines'] != null) {
      setLines(
        t,
        lines(req, t['org_id']! as String, t['id']! as String, body['lines']),
      );
    }
    _setStatus(db, t, next, req.persona);
    return MockResponse.ok(t);
  });

  server.on('POST', '/inventory/transfers/{id}/decline', (req) {
    req.requireCap('inventory.transfers.create');
    final note = _trimmed(req.json['note']);
    if (note == null) req.badRequest("Say why you're declining the request.");
    final (t, next) = authorize(req, 'decline');
    _appendNote(t, 'Declined: $note');
    _setStatus(db, t, next, req.persona);
    return MockResponse.ok(t);
  });

  server.on('POST', '/inventory/transfers/{id}/dispatch', (req) {
    final (t, _) = authorize(req, 'dispatch');
    transferDispatch(db, t, req.persona, req: req);
    return MockResponse.ok(t);
  });

  server.on('POST', '/inventory/transfers/{id}/receive', (req) {
    final (t, _) = authorize(req, 'receive');
    final given = <String, (double, String?)>{};
    final raw = req.json['lines'];
    final list = raw is List ? raw.cast<Map>() : const <Map>[];
    for (final l in list) {
      final q = l['qty_received'];
      given['${l['line_id']}'] = (
        q is num ? q.toDouble() : double.nan,
        _trimmed(l['note']),
      );
    }
    final own = _linesOf(t);
    if (given.length != list.length ||
        given.length != own.length ||
        own.any((l) => !given.containsKey(l['id']))) {
      req.badRequest(
        'Say what arrived for every line on the transfer, once each.',
      );
    }
    for (final l in own) {
      final (q, note) = given[l['id']]!;
      if (!q.isFinite) req.badRequest('qty_received must be a number.');
      if (_milli(q) < 0) {
        req.badRequest("A received quantity can't be negative.");
      }
      if (_milli(q) > _milli(l['qty_sent']! as num) && note == null) {
        req.fail(
          MockResponse.error(
            400,
            'More ${l['ingredient_name']} arrived than was sent. Add a '
            'note saying why.',
            code: 'OVER_RECEIVE_NEEDS_NOTE',
          ),
        );
      }
    }
    transferReceive(db, t, req.persona, got: given);
    return MockResponse.ok(t);
  });

  server.on('POST', '/inventory/transfers/{id}/cancel', (req) {
    final (t, next) = authorize(req, 'cancel');
    if (t['status'] == 'dispatched') {
      for (final l in _linesOf(t)) {
        _move(
          db,
          req.persona,
          branchId: t['source_branch_id']! as String,
          ing: db[InvTables.ingredients].find(
            l['org_ingredient_id']! as String,
          )!,
          type: 'transfer_in',
          qty: (l['qty_sent']! as num).toDouble(),
          cost: (l['unit_cost'] as num?)?.toDouble(),
          transferId: t['id']! as String,
          note: 'Transfer cancelled',
        );
      }
    }
    _appendNote(t, _trimmed(req.json['note']));
    _setStatus(db, t, next, req.persona);
    return MockResponse.ok(t);
  });
}
