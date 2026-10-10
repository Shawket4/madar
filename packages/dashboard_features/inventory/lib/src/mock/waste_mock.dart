/// Waste log: the mock backend for the INV-WST rows. Routes this unit owns
/// (the only file that registers them):
///
/// - POST /inventory/branches/{branch_id}/waste (createWaste) — also used by Today and Ingredients
/// - GET /reports/branches/{branch_id}/waste-report (branchWasteReport)
///
/// The log (`GET /inventory/branches/{branch_id}/waste`) and the branch
/// stock are shared reads. A recorded waste is a `waste` movement in
/// `InvTables.movements` and lowers `InvTables.branchStock`.
///
/// As the backend (`MadarRust/src/inventory/handlers.rs` `create_waste`,
/// `src/reports/handlers.rs` `branch_waste_report`):
/// - create: `inventory.waste.record` first, then the branch (404 / 403),
///   the reason, the quantity, the ingredient, then the on-hand check
///   ("Only `<x>` on hand — cannot waste `<y>`."). The cap's `max_value` limit
///   is not modelled (no persona carries one).
/// - report: `inventory.read`; a branch or the all-branches sentinel (403
///   "No organization in scope" without an org); waste movements whose
///   `created_at` falls in [from, to], per reason and ingredient.
library;

import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';
import 'inventory_views.dart';

const String _allBranches = '00000000-0000-0000-0000-000000000000';

/// The reasons a person may send (`validate_waste_reason`).
const List<String> _reasons = [
  'expired',
  'spoiled',
  'damaged',
  'overproduction',
  'order_cancelled',
  'theft',
  'other',
];

/// `{:.3}`, as the backend's refusal prints a figure.
String _fixed3(num v) => v.toStringAsFixed(3);

void registerWasteMocks(MockServer server, MockDb db) {
  server.on('POST', '/inventory/branches/{branch_id}/waste', (req) {
    req.requireCap('inventory.waste.record');
    final branchId = req.param('branch_id');
    final branch = db['branches'].find(branchId);
    if (branch == null) req.notFound('Branch not found');
    req.requireSameOrg(branch['org_id'] as String?);
    req.requireBranch(branchId);

    final body = req.json;
    final reason = body['reason'];
    if (reason is! String || !_reasons.contains(reason)) {
      req.badRequest('reason must be one of: ${_reasons.join(', ')}');
    }
    final qty = (body['quantity'] as num?)?.toDouble();
    if (qty == null || qty <= 0) {
      req.badRequest('quantity must be greater than 0');
    }
    final ingId = body['org_ingredient_id'];
    final ing = ingId is String ? db[InvTables.ingredients].find(ingId) : null;
    if (ing == null || ing['org_id'] != branch['org_id']) {
      req.badRequest("Ingredient not found in this organization's catalog");
    }
    final id = ingId as String;

    final rec = InvViews.stockRecord(db, branchId, id);
    final cost =
        (rec?['cost_per_unit'] as num?)?.toDouble() ??
        (ing['cost_per_unit'] as num?)?.toDouble();
    // madar-money `waste::value_of`: a negative cost, or a value past i64.
    if (cost != null &&
        (cost < 0 || (qty * cost).roundToDouble() > 9223372036854775807.0)) {
      req.badRequest(
        "This waste does not come to a real amount. Check the quantity and "
        "the ingredient's cost.",
      );
    }
    final onHand = (rec?['on_hand'] as num?)?.toDouble() ?? 0;
    if (rec == null || onHand < qty) {
      req.badRequest(
        'Only ${_fixed3(onHand)} on hand — cannot waste ${_fixed3(qty)}.',
      );
    }

    final now = db.nowIso;
    final balance = onHand - qty;
    rec
      ..['on_hand'] = balance
      ..['last_movement_at'] = now;
    final note = body['note'];
    final row = db[InvTables.movements].insert({
      'branch_id': branchId,
      'branch_name': branch['name'],
      'branch_stock_id': rec['id'],
      'org_ingredient_id': id,
      'ingredient_name': ing['name'],
      'unit': ing['unit'],
      'movement_type': 'waste',
      'quantity': -qty,
      'balance_after': balance,
      'below_zero': balance < 0,
      'unit_cost': cost == null ? null : (cost + 0.5).floor(),
      'unit_cost_exact': cost,
      'reason': reason,
      'note': note is String && note.trim().isNotEmpty ? note : null,
      'source_type': 'waste',
      'source_id': null,
      'created_at': now,
      'created_by': req.persona.userId,
      'created_by_name': req.persona.displayName,
      // What the log's SQL answers for a waste typed here (no till event).
      'waste_source': 'dashboard',
      'occurred_at': now,
      'received_at': now,
    }, timestamps: false);
    return MockResponse.created(row);
  });

  server.on('GET', '/reports/branches/{branch_id}/waste-report', (req) {
    req.requireCap('inventory.read');
    final id = req.param('branch_id');
    if (id == _allBranches && req.orgId == null) {
      req.fail(MockResponse.forbidden('No organization in scope'));
    }
    return MockResponse.ok(
      wasteReport(
        db,
        InvScope.branchIds(req, db, id),
        from: req.qDateTime('from'),
        to: req.qDateTime('to'),
      ),
    );
  });
}

/// `WasteReportRow`s over [branchIds]: waste movements received in [from,
/// to] (inclusive), per reason (null → `other`) and ingredient; the value is
/// unknown (null) when any line has no cost, else the rounded Σ |qty| ×
/// exact cost. Largest quantity first.
List<MockRow> wasteReport(
  MockDb db,
  Iterable<String> branchIds, {
  DateTime? from,
  DateTime? to,
}) {
  final ids = branchIds.toSet();
  final groups = <String, MockRow>{};
  final values = <String, double?>{};
  for (final m in db[InvTables.movements].rows) {
    if (m['movement_type'] != 'waste' || !ids.contains(m['branch_id'])) {
      continue;
    }
    final at = DateTime.parse(m['created_at']! as String);
    if (from != null && at.isBefore(from)) continue;
    if (to != null && at.isAfter(to)) continue;
    final reason = (m['reason'] as String?) ?? 'other';
    final key = '$reason|${m['org_ingredient_id']}';
    final q = -(m['quantity']! as num).toDouble();
    final cost = (m['unit_cost_exact'] ?? m['unit_cost']) as num?;
    final g = groups[key] ??= {
      'reason': reason,
      'org_ingredient_id': m['org_ingredient_id'],
      'ingredient_name': m['ingredient_name'],
      'unit': m['unit'],
      'waste_qty': 0.0,
    };
    g['waste_qty'] = (g['waste_qty']! as double) + q;
    final had = values.containsKey(key) ? values[key] : 0.0;
    values[key] = had == null || cost == null ? null : had + q * cost;
  }
  final rows = [
    for (final e in groups.entries)
      {
        ...e.value,
        'waste_value': values[e.key] == null
            ? null
            : (values[e.key]! + 0.5).floor(),
      },
  ];
  rows.sort(
    (a, b) => (b['waste_qty']! as double).compareTo(a['waste_qty']! as double),
  );
  return rows;
}
