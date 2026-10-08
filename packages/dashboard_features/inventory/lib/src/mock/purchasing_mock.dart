/// Purchasing: the mock backend for the INV-PUR rows. Routes this unit owns
/// (the only file that registers them):
///
/// - POST /purchasing/orgs/{org_id}/suppliers (createSupplier)
/// - PATCH /purchasing/suppliers/{id} (updateSupplier)
/// - DELETE /purchasing/suppliers/{id} (deleteSupplier)
/// - POST /purchasing/branches/{branch_id}/orders (createPurchaseOrder) — also used by Today
/// - POST /purchasing/orders/{id}/submit (submitPurchaseOrder)
/// - POST /purchasing/orders/{id}/cancel (cancelPurchaseOrder)
/// - POST /purchasing/orders/{id}/receive (receivePurchaseOrder) — also used by Today
/// - GET /purchasing/orders/{id}/receipts (listPoReceipts) — also used by Today
/// - GET /purchasing/branches/{branch_id}/reorder-suggestions (reorderSuggestions)
///
/// The suppliers list, the order lists and `GET /purchasing/orders/{id}`
/// are shared reads.
///
/// Each handler follows `MadarRust/src/purchasing/handlers.rs`: the
/// capability first (inventory §11), then the 404, then the org / branch
/// check, then the backend's own refusals in its words. Writes persist: a
/// created order is listed next, a receipt moves the branch's stock (a
/// `purchase_in` movement, the weighted-average cost, a goods receipt), so
/// Today, Ingredients and the reports read the same story.
library;

import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';
import 'inventory_views.dart';

/// Rust's `f64` Display (`5`, `2.5`), for the backend's sentences.
String _rustNumber(num v) {
  final d = v.toDouble();
  if (d.isFinite && d == d.truncateToDouble() && d.abs() < 1e16) {
    return d.toInt().toString();
  }
  return d.toString();
}

/// A whole number of piastres from a decimal (`round_piastres`: half away
/// from zero).
int _roundPiastres(num v) => v < 0 ? -((-v) + 0.5).floor() : (v + 0.5).floor();

/// Six decimals, as the backend's `round_dp(6)` keeps costs.
double _dp6(num v) => (v * 1e6).roundToDouble() / 1e6;

const Map<String, num> _unitScale = {
  'g': 1,
  'kg': 1000,
  'ml': 1,
  'l': 1000,
  'pcs': 1,
};

String _family(String unit) => switch (unit) {
  'g' || 'kg' => 'weight',
  'ml' || 'l' => 'volume',
  _ => 'count',
};

void registerPurchasingMocks(MockServer server, MockDb db) {
  final suppliers = db[InvTables.suppliers];
  final orders = db[InvTables.purchaseOrders];
  final lines = db[InvTables.poLines];
  final receipts = db[InvTables.receipts];

  /// `require_org` for an org in the path.
  String org(MockRequest req) {
    final id = req.param('org_id');
    req.requireSameOrg(id);
    return id;
  }

  /// `require_branch_access`: the branch exists, is in the persona's org and
  /// the persona works there.
  MockRow branch(MockRequest req, String branchId) {
    final b = db['branches'].find(branchId);
    if (b == null) req.notFound('Branch not found');
    req.requireSameOrg(b['org_id'] as String?);
    req.requireBranch(branchId);
    return b;
  }

  /// `fetch_order_or_404` + the branch check.
  MockRow order(MockRequest req) {
    final po = orders.get(req.param('id'), what: 'Purchase order not found');
    req.requireSameOrg(po['org_id'] as String?);
    req.requireBranch(po['branch_id']! as String);
    return po;
  }

  MockRow supplier(MockRequest req) {
    final s = suppliers.get(req.param('id'), what: 'Supplier not found');
    req.requireSameOrg(s['org_id'] as String?);
    return s;
  }

  // ── Suppliers ───────────────────────────────────────────────────────────

  server.on('POST', '/purchasing/orgs/{org_id}/suppliers', (req) {
    req.requireCap('purchasing.suppliers.create');
    final orgId = org(req);
    final body = req.json;
    final name = (body['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) req.badRequest('name cannot be empty');
    final row = suppliers.insert({
      'org_id': orgId,
      'name': name,
      'contact_name': body['contact_name'],
      'phone': body['phone'],
      'email': body['email'],
      'is_active': true,
    });
    return MockResponse.created(row);
  });

  server.on('PATCH', '/purchasing/suppliers/{id}', (req) {
    req.requireCap('purchasing.suppliers.edit');
    final s = supplier(req);
    final body = req.json;
    // `COALESCE($n, column)`: a field left out (or null) keeps its value.
    final patch = <String, Object?>{
      for (final k in ['name', 'contact_name', 'phone', 'email', 'is_active'])
        if (body[k] != null) k: body[k],
    };
    return MockResponse.ok(suppliers.update(s['id']! as String, patch));
  });

  server.on('DELETE', '/purchasing/suppliers/{id}', (req) {
    req.requireCap('purchasing.suppliers.delete');
    final s = supplier(req);
    // Soft-deleted on the server: gone from the list; past orders keep the
    // name they were placed with.
    suppliers.delete(s['id']! as String);
    return MockResponse.empty();
  });

  // ── Purchase orders ─────────────────────────────────────────────────────

  server.on('POST', '/purchasing/branches/{branch_id}/orders', (req) {
    req.requireCap('purchasing.orders.create');
    final b = branch(req, req.param('branch_id'));
    final body = req.json;
    final input = (body['lines'] as List?) ?? const [];
    if (input.isEmpty) {
      req.badRequest('a purchase order needs at least one line');
    }
    final orgId = b['org_id']! as String;
    final supplierId = body['supplier_id'] as String?;
    MockRow? sup;
    if (supplierId != null) {
      sup = suppliers.find(supplierId);
      if (sup == null || sup['org_id'] != orgId) {
        req.badRequest('Supplier does not belong to this organization');
      }
    }

    // Every line is checked before anything is written (the backend's
    // transaction rolls back on the first refusal).
    final newLines = <MockRow>[];
    for (final raw in input) {
      final l = raw is Map
          ? raw.cast<String, Object?>()
          : const <String, Object?>{};
      final qty = (l['quantity_ordered'] as num?)?.toDouble() ?? 0;
      if (qty <= 0) req.badRequest('quantity_ordered must be greater than 0');
      final lineCost = (l['line_cost'] as num?)?.toInt();
      final unitCost = (l['unit_cost'] as num?)?.toInt();
      final int cost;
      final double exact;
      if (lineCost != null) {
        if (lineCost < 0) req.badRequest('line_cost cannot be negative');
        cost = lineCost;
        exact = _dp6(lineCost / qty);
      } else if (unitCost != null) {
        if (unitCost < 0) req.badRequest('unit_cost cannot be negative');
        cost = _roundPiastres(unitCost * qty);
        exact = unitCost.toDouble();
      } else {
        req.badRequest(
          'each line needs its cost: line_cost (the invoice total for the line)',
        );
      }
      final ing = db[InvTables.ingredients].find(
        (l['org_ingredient_id'] as String?) ?? '',
      );
      if (ing == null || ing['org_id'] != orgId) {
        req.badRequest('Ingredient not found in this organization');
      }
      final base = ing['unit']! as String;
      final pu = (l['purchase_unit'] as String?) ?? '';
      final packUnit = ing['pack_unit'] as String?;
      final double factor;
      if (packUnit != null &&
          packUnit.isNotEmpty &&
          pu.toLowerCase() == packUnit.toLowerCase()) {
        final size = (ing['pack_size'] as num?)?.toDouble();
        if (size == null || size <= 0) {
          req.badRequest(
            "This ingredient's pack size is not configured (set pack_size on the catalog item).",
          );
        }
        factor = size;
      } else {
        if (!_unitScale.containsKey(pu)) {
          final pack = packUnit != null && packUnit.isNotEmpty
              ? ' or the configured pack "$packUnit"'
              : '';
          req.badRequest(
            'Purchase unit must be one of g, kg, ml, l, pcs$pack.',
          );
        }
        if (_family(pu) != _family(base)) {
          req.badRequest(
            "Purchase unit must match the ingredient's measure (g/kg for weight, ml/l for volume, pcs for count).",
          );
        }
        factor = (_unitScale[pu]! / _unitScale[base]!).toDouble();
      }
      newLines.add({
        'org_ingredient_id': ing['id'],
        'ingredient_name': ing['name'],
        'unit': base,
        'purchase_unit': pu,
        'units_per_purchase_unit': factor,
        'quantity_ordered': qty,
        'quantity_received': 0.0,
        'unit_cost': _roundPiastres(exact),
        'unit_cost_exact': exact,
        'line_cost': cost,
      });
    }

    final po = orders.insert({
      'org_id': orgId,
      'branch_id': b['id'],
      'branch_name': b['name'],
      'supplier_id': supplierId,
      'supplier_name': sup?['name'],
      'status': 'draft',
      'reference': body['reference'],
      'note': body['note'],
      'expected_at': body['expected_at'],
      'received_at': null,
      'received_by': null,
      'created_by': req.persona.userId,
    });
    for (final l in newLines) {
      lines.insert({...l, 'purchase_order_id': po['id']}, timestamps: false);
    }
    return MockResponse.created(InvViews.purchaseOrderFull(db, po));
  });

  server.on('POST', '/purchasing/orders/{id}/submit', (req) {
    req.requireCap('purchasing.orders.edit');
    final po = order(req);
    if (po['status'] != 'draft') {
      req.conflict('Only a draft purchase order can be placed (submitted).');
    }
    orders.update(po['id']! as String, {'status': 'ordered'});
    return MockResponse.ok(InvViews.purchaseOrder(db, po));
  });

  server.on('POST', '/purchasing/orders/{id}/cancel', (req) {
    req.requireCap('purchasing.orders.edit');
    final po = order(req);
    final status = po['status'];
    if (status == 'received' || status == 'partially_received') {
      req.conflict(
        'Cannot cancel a purchase order that has already received stock. '
        'Reverse the received goods (return to supplier / stock adjustment) first.',
      );
    }
    orders.update(po['id']! as String, {'status': 'cancelled'});
    return MockResponse.ok(InvViews.purchaseOrder(db, po));
  });

  server.on('POST', '/purchasing/orders/{id}/receive', (req) {
    req.requireCap('purchasing.orders.edit');
    final po = order(req);
    if (po['status'] == 'received' || po['status'] == 'cancelled') {
      req.conflict('Purchase order is already received or cancelled');
    }
    final input = (req.json['lines'] as List?) ?? const [];
    if (input.isEmpty) req.badRequest('no lines to receive');
    final seen = <String>{};
    for (final raw in input) {
      final id = raw is Map ? raw['line_id'] as String? : null;
      if (id != null && !seen.add(id)) {
        req.badRequest('Duplicate line_id in receive request');
      }
    }

    // Check every line first (the transaction would roll back).
    final work = <(MockRow line, double qty, double cost)>[];
    for (final raw in input) {
      final r = raw is Map
          ? raw.cast<String, Object?>()
          : const <String, Object?>{};
      final qty = (r['quantity_received'] as num?)?.toDouble() ?? 0;
      if (qty <= 0) continue;
      final line = lines.firstWhere(
        (l) => l['id'] == r['line_id'] && l['purchase_order_id'] == po['id'],
      );
      if (line == null) {
        req.badRequest('Line does not belong to this purchase order');
      }
      final ordered = (line['quantity_ordered']! as num).toDouble();
      final already = (line['quantity_received']! as num).toDouble();
      if (already + qty > ordered + 1e-6) {
        final left = ordered - already;
        req.badRequest(
          'Cannot receive ${_rustNumber(qty)} — only '
          '${_rustNumber(left < 0 ? 0 : left)} of ${_rustNumber(ordered)} '
          'ordered remain on this line.',
        );
      }
      final lineCost = (r['line_cost'] as num?)?.toInt();
      final unitCost = (r['unit_cost'] as num?)?.toInt();
      final double cost;
      if (lineCost != null) {
        if (lineCost < 0) req.badRequest('line_cost cannot be negative');
        cost = lineCost.toDouble();
      } else if (unitCost != null) {
        if (unitCost < 0) req.badRequest('unit_cost cannot be negative');
        cost = unitCost * qty;
      } else {
        cost = ordered > 0 ? (line['line_cost']! as num) * qty / ordered : 0.0;
      }
      work.add((line, qty, cost));
    }

    final now = db.nowIso;
    final branchId = po['branch_id']! as String;
    final receiptLines = <MockRow>[];
    for (final (line, qty, cost) in work) {
      final factor = (line['units_per_purchase_unit']! as num).toDouble();
      final stockQty = qty * factor;
      final costPerStock = stockQty > 0 ? _dp6(cost / stockQty) : 0.0;
      final ingId = line['org_ingredient_id']! as String;
      final ing = db[InvTables.ingredients].find(ingId);

      // Weighted-average cost from this branch's prior on hand and cost
      // (the catalog's cost when the branch has none yet).
      var bs = InvViews.stockRecord(db, branchId, ingId);
      final prior = (bs?['on_hand'] as num?)?.toDouble() ?? 0;
      final priorCost =
          (bs?['cost_per_unit'] as num?)?.toDouble() ??
          (ing?['cost_per_unit'] as num?)?.toDouble();
      final newCost = prior <= 0 || priorCost == null
          ? costPerStock
          : _dp6(
              (prior * priorCost + stockQty * costPerStock) /
                  (prior + stockQty),
            );
      final onHand = prior + stockQty;
      if (bs == null) {
        bs = db[InvTables.branchStock].insert({
          'branch_id': branchId,
          'org_ingredient_id': ingId,
          'on_hand': onHand,
          'par_min': null,
          'par_max': null,
          'cost_per_unit': newCost,
          'last_counted_at': null,
          'last_movement_at': now,
        }, timestamps: false);
      } else {
        bs
          ..['on_hand'] = onHand
          ..['cost_per_unit'] = newCost
          ..['last_movement_at'] = now;
      }
      db[InvTables.movements].insert({
        'branch_id': branchId,
        'branch_name': InvScope.branchName(db, branchId),
        'branch_stock_id': bs['id'],
        'org_ingredient_id': ingId,
        'ingredient_name': line['ingredient_name'],
        'unit': line['unit'],
        'movement_type': 'purchase_in',
        'quantity': stockQty,
        'balance_after': onHand,
        'below_zero': onHand < 0,
        'unit_cost': _roundPiastres(costPerStock),
        'reason': null,
        'note': 'Purchase received',
        'source_type': 'purchase',
        'source_id': po['id'],
        'created_at': now,
        'created_by': req.persona.userId,
        'created_by_name': req.persona.displayName,
      }, timestamps: false);
      line['quantity_received'] =
          (line['quantity_received']! as num).toDouble() + qty;
      receiptLines.add({
        'id': db.newId('goods_receipt_lines'),
        'purchase_order_line_id': line['id'],
        'org_ingredient_id': ingId,
        'ingredient_name': line['ingredient_name'],
        'quantity': stockQty,
        'line_cost': _roundPiastres(cost),
        'unit_cost': _roundPiastres(costPerStock),
        'unit_cost_exact': costPerStock,
      });
    }

    final poLines = lines.where((l) => l['purchase_order_id'] == po['id']);
    final full = poLines.every(
      (l) =>
          (l['quantity_received']! as num) >= (l['quantity_ordered']! as num),
    );
    final any = poLines.any((l) => (l['quantity_received']! as num) > 0);
    orders.update(po['id']! as String, {
      'status': full
          ? 'received'
          : any
          ? 'partially_received'
          : po['status'],
      'received_at': now,
      'received_by': req.persona.userId,
    });
    if (receiptLines.isNotEmpty) {
      receipts.insert({
        'branch_id': branchId,
        'purchase_order_id': po['id'],
        'supplier_id': po['supplier_id'],
        'supplier_name': po['supplier_name'],
        'reference': po['reference'],
        'note': null,
        'is_return': false,
        'received_at': now,
        'received_by': req.persona.userId,
        'received_by_name': req.persona.displayName,
        'lines': receiptLines,
      }, timestamps: false);
    }
    return MockResponse.ok(InvViews.purchaseOrderFull(db, po));
  });

  server.on('GET', '/purchasing/orders/{id}/receipts', (req) {
    req.requireCap('purchasing.orders.read');
    final po = order(req);
    final rows = receipts.query(
      filters: {'purchase_order_id': po['id']},
      sort: '-received_at',
    );
    return MockResponse.ok([
      for (final r in rows)
        {
          ...r,
          'supplier_name':
              suppliers.find((r['supplier_id'] as String?) ?? '')?['name'] ??
              r['supplier_name'],
          'lines': [
            for (final l in queryRows(
              ((r['lines'] as List?) ?? const []).cast<MockRow>(),
              sort: 'ingredient_name',
            ))
              l,
          ],
        },
    ]);
  });

  server.on('GET', '/purchasing/branches/{branch_id}/reorder-suggestions', (
    req,
  ) {
    req.requireCap('purchasing.orders.read');
    final b = branch(req, req.param('branch_id'));
    final rows = <MockRow>[];
    for (final ing in db[InvTables.ingredients].query(
      filters: {'org_id': b['org_id']},
    )) {
      final bs = InvViews.stockRecord(
        db,
        b['id']! as String,
        ing['id']! as String,
      );
      if (bs == null) continue;
      final parMin = (bs['par_min'] as num?)?.toDouble() ?? 0;
      final onHand = (bs['on_hand'] as num?)?.toDouble() ?? 0;
      if (parMin <= 0 || onHand > parMin) continue;
      final target = (bs['par_max'] as num?)?.toDouble() ?? parMin;
      final supId = ing['supplier_id'] as String?;
      rows.add({
        'supplier_id': supId,
        'supplier_name': supId == null ? null : suppliers.find(supId)?['name'],
        'org_ingredient_id': ing['id'],
        'ingredient_name': ing['name'],
        'unit': ing['unit'],
        'on_hand': onHand,
        'suggested_qty': target - onHand > 0 ? target - onHand : 0.0,
      });
    }
    // `ORDER BY oi.supplier_id NULLS LAST, oi.name`, then consecutive rows
    // of one supplier form a group.
    rows.sort((a, b) {
      final c = compareJson(a['supplier_id'], b['supplier_id']);
      return c != 0
          ? c
          : compareJson(a['ingredient_name'], b['ingredient_name']);
    });
    final groups = <MockRow>[];
    for (final r in rows) {
      final last = groups.isEmpty ? null : groups.last;
      final line = {
        'org_ingredient_id': r['org_ingredient_id'],
        'ingredient_name': r['ingredient_name'],
        'unit': r['unit'],
        'on_hand': r['on_hand'],
        'suggested_qty': r['suggested_qty'],
      };
      if (last != null && last['supplier_id'] == r['supplier_id']) {
        (last['lines']! as List).add(line);
      } else {
        groups.add({
          'supplier_id': r['supplier_id'],
          'supplier_name': r['supplier_name'],
          'lines': [line],
        });
      }
    }
    return MockResponse.ok(groups);
  });
}
