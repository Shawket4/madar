/// Transfers: the mock backend for the INV-TRF rows. Routes this unit owns
/// (the only file that registers them):
///
/// - GET /inventory/branches/{branch_id}/transfers (listTransfers)
/// - POST /inventory/transfers (createTransfer)
/// - PATCH /inventory/transfers/{id} (updateTransfer)
/// - DELETE /inventory/transfers/{id} (deleteTransfer) — removes the row (INV-TRF-029)
///
/// Branches come from the core (`GET /branches`); the source stock is a
/// shared read.
///
/// As the backend (`MadarRust/src/inventory/handlers.rs` `create_transfer`,
/// `list_transfers`, `update_transfer`, `delete_transfer`):
/// - list: `inventory.transfers.read`; a branch (404 / 403) or the
///   all-branches id (every branch of the org; 403 "No organization in
///   scope" without one); `direction` incoming / outgoing / both; latest
///   first; `limit` 200 by default (1..1000), `offset`.
/// - create: `inventory.transfers.create`, the source branch's access, then
///   quantity > 0, two different branches, both found, one org, the
///   ingredient in the org, then the source's on hand ("Only `<x>` on hand at
///   the source branch — cannot transfer `<y>`."). Moves the stock (the
///   destination's cost blended), writes `transfer_out` / `transfer_in`.
/// - note: `inventory.transfers.edit`; 404 "Transfer not found"; same org.
/// - reverse: `inventory.transfers.delete`; 404; same org; 409 when the
///   destination holds less than was sent; two "Transfer reversal"
///   movements, then the row is DELETED (204).
library;

import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';
import 'inventory_views.dart';

const String _allBranches = '00000000-0000-0000-0000-000000000000';

/// `{:.3}`, as the backend's refusals print a figure.
String _fixed3(num v) => v.toStringAsFixed(3);

/// The transfers touching [branchIds] in [direction], latest first.
List<MockRow> transfersOf(
  MockDb db,
  Set<String> branchIds, {
  String? direction,
}) {
  bool hit(MockRow t) {
    final out = branchIds.contains(t['source_branch_id']);
    final into = branchIds.contains(t['destination_branch_id']);
    return switch (direction) {
      'incoming' => into,
      'outgoing' => out,
      _ => out || into,
    };
  }

  final rows = db[InvTables.transfers].where(hit);
  rows.sort(
    (a, b) => DateTime.parse(
      b['initiated_at']! as String,
    ).compareTo(DateTime.parse(a['initiated_at']! as String)),
  );
  return rows;
}

/// Moves [qty] (signed) of [ingId] at [branchId], with its movement; a
/// positive move at [cost] blends into the branch's average cost.
void _move(
  MockRequest req,
  MockDb db, {
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
  final balance = prior + qty;
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
    'unit_cost': cost == null ? null : (cost + 0.5).floor(),
    'reason': null,
    'note': note,
    'source_type': 'transfer',
    'source_id': transferId,
    'created_at': now,
    'created_by': req.persona.userId,
    'created_by_name': req.persona.displayName,
  }, timestamps: false);
}

/// The source branch's cost of [ingId] (the catalog's when it has none).
double? _cost(MockDb db, String branchId, MockRow ing) =>
    (InvViews.stockRecord(db, branchId, ing['id']! as String)?['cost_per_unit']
            as num?)
        ?.toDouble() ??
    (ing['cost_per_unit'] as num?)?.toDouble();

void registerTransfersMocks(MockServer server, MockDb db) {
  MockRow found(MockRequest req) {
    final t = db[InvTables.transfers].find(req.param('id'));
    if (t == null) req.notFound('Transfer not found');
    req.requireSameOrg(t['org_id'] as String?);
    return t;
  }

  server.on('GET', '/inventory/branches/{branch_id}/transfers', (req) {
    req.requireCap('inventory.transfers.read');
    final id = req.param('branch_id');
    final Set<String> ids;
    if (id == _allBranches) {
      final org = req.orgId;
      if (org == null) req.fail(MockResponse.forbidden('No organization in scope'));
      ids = {
        for (final b in db['branches'].where((b) => b['org_id'] == org))
          b['id']! as String,
      };
    } else {
      final b = db['branches'].find(id);
      if (b == null) req.notFound('Branch not found');
      req.requireSameOrg(b['org_id'] as String?);
      req.requireBranch(id);
      ids = {id};
    }
    return MockResponse.ok(
      sliceOf(
        transfersOf(db, ids, direction: req.q('direction')),
        req,
        defaultLimit: 200,
        maxLimit: 1000,
      ),
    );
  });

  server.on('POST', '/inventory/transfers', (req) {
    req.requireCap('inventory.transfers.create');
    final body = req.json;
    final srcId = body['source_branch_id'];
    final dstId = body['destination_branch_id'];
    if (srcId is! String || dstId is! String) {
      req.badRequest('source_branch_id and destination_branch_id are required');
    }
    final src = db['branches'].find(srcId);
    if (src == null) req.notFound('Source branch not found');
    req.requireSameOrg(src['org_id'] as String?);
    req.requireBranch(srcId);
    final qty = (body['quantity'] as num?)?.toDouble();
    if (qty == null || qty <= 0) {
      req.badRequest('quantity must be greater than 0');
    }
    if (srcId == dstId) {
      req.badRequest('Source and destination branches must be different');
    }
    final dst = db['branches'].find(dstId);
    if (dst == null) req.notFound('Destination branch not found');
    if (dst['org_id'] != src['org_id']) {
      req.badRequest('Both branches must belong to the same organization');
    }
    final ingId = body['org_ingredient_id'];
    final ing = ingId is String ? db[InvTables.ingredients].find(ingId) : null;
    if (ing == null || ing['org_id'] != src['org_id']) {
      req.badRequest("Ingredient not found in this organization's catalog");
    }
    final onHand =
        (InvViews.stockRecord(db, srcId, ing['id']! as String)?['on_hand']
                as num?)
            ?.toDouble() ??
        0;
    if (onHand < qty) {
      req.badRequest(
        'Only ${_fixed3(onHand)} on hand at the source branch — cannot '
        'transfer ${_fixed3(qty)}.',
      );
    }
    final note = body['note'];
    final row = db[InvTables.transfers].insert({
      'id': db.newId(InvTables.transfers),
      'org_id': src['org_id'],
      'org_ingredient_id': ing['id'],
      'ingredient_name': ing['name'],
      'unit': ing['unit'],
      'quantity': qty,
      'source_branch_id': srcId,
      'source_branch_name': src['name'],
      'destination_branch_id': dstId,
      'destination_branch_name': dst['name'],
      'initiated_at': db.nowIso,
      'initiated_by': req.persona.userId,
      'initiated_by_name': req.persona.displayName,
      'note': note is String ? note : null,
    }, timestamps: false);
    final cost = _cost(db, srcId, ing);
    for (final (b, type, q, n) in [
      (srcId, 'transfer_out', -qty, 'Transfer out'),
      (dstId, 'transfer_in', qty, 'Transfer in'),
    ]) {
      _move(
        req,
        db,
        branchId: b,
        ing: ing,
        type: type,
        qty: q,
        cost: cost,
        transferId: row['id']! as String,
        note: n,
      );
    }
    return MockResponse.created(row);
  });

  server.on('PATCH', '/inventory/transfers/{id}', (req) {
    req.requireCap('inventory.transfers.edit');
    final t = found(req);
    final note = req.json['note'];
    t['note'] = note is String ? note : null;
    return MockResponse.ok(t);
  });

  server.on('DELETE', '/inventory/transfers/{id}', (req) {
    req.requireCap('inventory.transfers.delete');
    final t = found(req);
    final qty = (t['quantity']! as num).toDouble();
    final src = t['source_branch_id']! as String;
    final dst = t['destination_branch_id']! as String;
    final ing = db[InvTables.ingredients].find(t['org_ingredient_id']! as String)!;
    final left =
        (InvViews.stockRecord(db, dst, ing['id']! as String)?['on_hand']
                as num?)
            ?.toDouble() ??
        0;
    if (left < qty) {
      req.conflict(
        'Cannot reverse transfer: the destination branch only has '
        '${_fixed3(left)} left of the ${_fixed3(qty)} transferred.',
      );
    }
    final cost = _cost(db, src, ing);
    for (final (b, type, q) in [
      (dst, 'transfer_out', -qty),
      (src, 'transfer_in', qty),
    ]) {
      _move(
        req,
        db,
        branchId: b,
        ing: ing,
        type: type,
        qty: q,
        cost: cost,
        transferId: t['id']! as String,
        note: 'Transfer reversal',
      );
    }
    db[InvTables.transfers].delete(t['id']! as String);
    return MockResponse.empty();
  });
}
