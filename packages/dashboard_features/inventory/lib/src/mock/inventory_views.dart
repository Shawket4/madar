/// The backend's reads over the area's tables ([InvTables]), as the handlers
/// answer them: the catalog with its category and supplier names, a branch's
/// whole-catalog stock view, low stock, valuation, a count with its figures,
/// a purchase order with its lines, the waste log. Every unit's handlers
/// answer from these so the pages' numbers agree.
library;

import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';

/// Org/branch scoping as the backend resolves it.
abstract final class InvScope {
  /// The org's branches [req]'s persona may see, by name.
  static List<MockRow> branches(MockRequest req, MockDb db, String orgId) =>
      db['branches'].query(
        filters: {'org_id': orgId},
        where: (b) => req.persona.seesBranch(b['id']! as String),
        sort: 'name',
      );

  /// The branch ids a branch-scoped read covers: the branch itself (403 when
  /// the persona does not work there), or for the all-branches sentinel every
  /// branch of the persona's org it may see.
  static List<String> branchIds(MockRequest req, MockDb db, String branchId) {
    if (branchId == _allBranches) {
      final org = req.orgId;
      if (org == null) return const [];
      return [for (final b in branches(req, db, org)) b['id']! as String];
    }
    final b = db['branches'].find(branchId);
    if (b == null) req.notFound('Branch not found');
    req.requireSameOrg(b['org_id'] as String?);
    req.requireBranch(branchId);
    return [branchId];
  }

  /// The org a branch belongs to.
  static String? orgOf(MockDb db, String branchId) =>
      db['branches'].find(branchId)?['org_id'] as String?;

  static String? branchName(MockDb db, String branchId) =>
      db['branches'].find(branchId)?['name'] as String?;
}

const String _allBranches = '00000000-0000-0000-0000-000000000000';

/// Reads the area's tables the way the backend's SQL does.
abstract final class InvViews {
  // ── Catalog ─────────────────────────────────────────────────────────────

  static MockRow? _category(MockDb db, Object? id) =>
      id is String ? db[InvTables.categories].find(id) : null;

  static MockRow? _supplier(MockDb db, Object? id) =>
      id is String ? db[InvTables.suppliers].find(id) : null;

  /// One `OrgIngredient` with its category and supplier names fresh.
  static MockRow ingredient(MockDb db, MockRow row) {
    final cat = _category(db, row['category_id']);
    final sup = _supplier(db, row['supplier_id']);
    return {
      ...row,
      'category_slug': cat?['slug'] ?? row['category_slug'],
      'category_name': cat?['name'] ?? row['category_name'],
      'supplier_name': sup?['name'],
    };
  }

  /// `GET /inventory/orgs/{org_id}/catalog`: every ingredient, by name.
  static List<MockRow> catalog(MockDb db, String orgId) => [
    for (final r in db[InvTables.ingredients].query(
      filters: {'org_id': orgId},
      sort: 'name',
    ))
      ingredient(db, r),
  ];

  /// `GET /inventory/orgs/{org_id}/categories`: by sort order then name,
  /// with live ingredient counts.
  static List<MockRow> categories(MockDb db, String orgId) {
    final rows = db[InvTables.categories].query(filters: {'org_id': orgId});
    rows.sort((a, b) {
      final s = (a['sort_order']! as num).compareTo(b['sort_order']! as num);
      return s != 0 ? s : compareJson(a['name'], b['name']);
    });
    final ings = db[InvTables.ingredients].rows;
    return [
      for (final c in rows)
        {
          ...c,
          'ingredient_count': ings
              .where((i) => i['category_id'] == c['id'])
              .length,
        },
    ];
  }

  /// `GET /purchasing/orgs/{org_id}/suppliers`: by name.
  static List<MockRow> suppliers(MockDb db, String orgId) =>
      db[InvTables.suppliers].query(filters: {'org_id': orgId}, sort: 'name');

  /// The org's variance tolerance.
  static double thresholdPct(MockDb db, String? orgId) {
    final s = orgId == null ? null : db[InvTables.settings].find(orgId);
    return (s?['stocktake_variance_threshold_pct'] as num?)?.toDouble() ??
        invVarianceThresholdPct;
  }

  // ── Branch stock ────────────────────────────────────────────────────────

  /// The stored stock record of a pair (null = no activity there).
  static MockRow? stockRecord(
    MockDb db,
    String branchId,
    String ingredientId,
  ) => db[InvTables.branchStock].firstWhere(
    (r) => r['branch_id'] == branchId && r['org_ingredient_id'] == ingredientId,
  );

  /// `GET /inventory/branches/{branch_id}/stock`: the WHOLE catalog as seen
  /// from the branch (`BranchStockRow`), by category order then name.
  static List<MockRow> branchStock(MockDb db, String branchId) {
    final orgId = InvScope.orgOf(db, branchId);
    if (orgId == null) return const [];
    final cats = {for (final c in db[InvTables.categories].rows) c['id']: c};
    final rows = <MockRow>[];
    for (final i in db[InvTables.ingredients].query(
      filters: {'org_id': orgId},
    )) {
      final bs = stockRecord(db, branchId, i['id']! as String);
      final cat = cats[i['category_id']];
      final onHand = (bs?['on_hand'] as num?)?.toDouble() ?? 0;
      final parMin = (bs?['par_min'] as num?)?.toDouble();
      rows.add({
        'branch_id': branchId,
        'org_ingredient_id': i['id'],
        'ingredient_name': i['name'],
        'unit': i['unit'],
        'category_id': i['category_id'],
        'category_slug': cat?['slug'] ?? i['category_slug'],
        'category_name': cat?['name'] ?? i['category_name'],
        'description': i['description'],
        'cost_per_unit': bs?['cost_per_unit'] ?? i['cost_per_unit'],
        'on_hand': onHand,
        'par_min': parMin,
        'par_max': (bs?['par_max'] as num?)?.toDouble(),
        'below_par': (parMin ?? 0) > 0 && onHand <= parMin!,
        'last_counted_at': bs?['last_counted_at'],
        'last_movement_at': bs?['last_movement_at'],
        'has_activity': bs != null,
        '_sort': cat?['sort_order'] ?? 0,
      });
    }
    rows.sort((a, b) {
      final s = (a['_sort']! as num).compareTo(b['_sort']! as num);
      if (s != 0) return s;
      final c = compareJson(a['category_name'], b['category_name']);
      return c != 0
          ? c
          : compareJson(a['ingredient_name'], b['ingredient_name']);
    });
    for (final r in rows) {
      r.remove('_sort');
    }
    return rows;
  }

  // ── Reports ─────────────────────────────────────────────────────────────

  /// Low stock (`LowStockRow`) over [branchIds]: `par_min > 0` and on hand at
  /// or under it; by branch name then ingredient name.
  static List<MockRow> lowStock(MockDb db, Iterable<String> branchIds) {
    final ids = branchIds.toSet();
    final out = <MockRow>[];
    for (final bs in db[InvTables.branchStock].rows) {
      if (!ids.contains(bs['branch_id'])) continue;
      final parMin = (bs['par_min'] as num?)?.toDouble();
      final onHand = (bs['on_hand']! as num).toDouble();
      if (parMin == null || parMin <= 0 || onHand > parMin) continue;
      final ing = db[InvTables.ingredients].find(
        bs['org_ingredient_id']! as String,
      );
      if (ing == null) continue;
      final parMax = (bs['par_max'] as num?)?.toDouble();
      final target = parMax ?? parMin;
      final sup = _supplier(db, ing['supplier_id']);
      out.add({
        'branch_id': bs['branch_id'],
        'branch_name': InvScope.branchName(db, bs['branch_id']! as String),
        'org_ingredient_id': ing['id'],
        'ingredient_name': ing['name'],
        'unit': ing['unit'],
        'on_hand': onHand,
        'par_min': parMin,
        'par_max': parMax,
        'suggested_qty': target - onHand > 0 ? target - onHand : 0.0,
        'supplier_id': ing['supplier_id'],
        'supplier_name': sup?['name'],
      });
    }
    out.sort((a, b) {
      final c = compareJson(a['branch_name'], b['branch_name']);
      return c != 0
          ? c
          : compareJson(a['ingredient_name'], b['ingredient_name']);
    });
    return out;
  }

  /// `InventoryValuationReport` over [branchIds]: per ingredient, the summed
  /// on hand valued at each branch's own cost (catalog cost as fallback);
  /// an unknown cost makes the row's value null and counts it as unknown.
  static Map<String, Object?> valuation(MockDb db, Iterable<String> branchIds) {
    final ids = branchIds.toSet();
    final byIng = <String, List<MockRow>>{};
    for (final bs in db[InvTables.branchStock].rows) {
      if (!ids.contains(bs['branch_id'])) continue;
      (byIng[bs['org_ingredient_id']! as String] ??= []).add(bs);
    }
    final items = <MockRow>[];
    var total = 0;
    var unknown = 0;
    for (final e in byIng.entries) {
      final ing = db[InvTables.ingredients].find(e.key);
      if (ing == null) continue;
      final catalogCost = (ing['cost_per_unit'] as num?)?.toDouble();
      var qty = 0.0;
      var value = 0.0;
      var known = true;
      for (final bs in e.value) {
        final q = (bs['on_hand']! as num).toDouble();
        final cost = (bs['cost_per_unit'] as num?)?.toDouble() ?? catalogCost;
        qty += q;
        if (cost == null) {
          known = false;
        } else {
          value += q * cost;
        }
      }
      final rounded = known ? (value + 0.5).floor() : null;
      if (rounded == null) {
        unknown++;
      } else {
        total += rounded;
      }
      final blended = qty != 0 && known
          ? (value / qty + 0.5).floor()
          : (catalogCost == null ? null : (catalogCost + 0.5).floor());
      items.add({
        'org_ingredient_id': e.key,
        'ingredient_name': ing['name'],
        'unit': ing['unit'],
        'on_hand': qty,
        'cost_per_unit': blended,
        'value': rounded,
      });
    }
    items.sort(
      (a, b) => compareJson(a['ingredient_name'], b['ingredient_name']),
    );
    return {
      'total_value': total,
      'unknown_cost_count': unknown,
      'items': items,
    };
  }

  // ── Counts ──────────────────────────────────────────────────────────────

  static List<MockRow> stocktakeItems(MockDb db, String stocktakeId) =>
      db[InvTables.stocktakeItems].query(
        filters: {'stocktake_id': stocktakeId},
        sort: 'ingredient_name',
      );

  /// A `Stocktake` as the list answers it (with counted/total items).
  static MockRow stocktake(MockDb db, MockRow row) {
    final items = stocktakeItems(db, row['id']! as String);
    return {
      ...row,
      'counted_items': items.where((i) => i['counted_qty'] != null).length,
      'total_items': items.length,
    };
  }

  /// `GET /stocktakes/branches/{branch_id}` over [branchIds], newest first.
  static List<MockRow> stocktakes(MockDb db, Iterable<String> branchIds) {
    final ids = branchIds.toSet();
    return [
      for (final r in db[InvTables.stocktakes].query(
        where: (r) => ids.contains(r['branch_id']),
        sort: '-started_at',
      ))
        stocktake(db, r),
    ];
  }

  // ── Purchasing ──────────────────────────────────────────────────────────

  /// A `PurchaseOrder` with its supplier and branch names fresh.
  static MockRow purchaseOrder(MockDb db, MockRow po) => {
    ...po,
    'branch_name':
        InvScope.branchName(db, po['branch_id']! as String) ??
        po['branch_name'],
    'supplier_name':
        _supplier(db, po['supplier_id'])?['name'] ?? po['supplier_name'],
  };

  /// `PurchaseOrderFull`: the order and its lines.
  static MockRow purchaseOrderFull(MockDb db, MockRow po) => {
    ...purchaseOrder(db, po),
    'lines': db[InvTables.poLines].where(
      (l) => l['purchase_order_id'] == po['id'],
    ),
  };

  /// Orders matching [where], `status`, `expected_before` (inclusive).
  static List<MockRow> purchaseOrders(
    MockDb db, {
    required bool Function(MockRow po) where,
    String? status,
    DateTime? expectedBefore,
    bool byExpected = false,
  }) {
    final rows = db[InvTables.purchaseOrders].query(
      filters: {'status': status},
      where: (po) {
        if (!where(po)) return false;
        if (expectedBefore == null) return true;
        final at = DateTime.tryParse((po['expected_at'] as String?) ?? '');
        return at != null && !at.isAfter(expectedBefore);
      },
      sort: '-created_at',
    );
    if (byExpected) {
      final indexed = [for (var i = 0; i < rows.length; i++) (i, rows[i])];
      indexed.sort((a, b) {
        final c = compareJson(a.$2['expected_at'], b.$2['expected_at']);
        return c != 0 ? c : a.$1 - b.$1;
      });
      return [for (final e in indexed) purchaseOrder(db, e.$2)];
    }
    return [for (final r in rows) purchaseOrder(db, r)];
  }

  // ── Movements ───────────────────────────────────────────────────────────

  /// When a waste line happened (`occurred_at ?? created_at`).
  static String wasteWhen(MockRow m) =>
      (m['occurred_at'] as String?) ?? m['created_at']! as String;

  /// The waste log over [branchIds], latest first (by when it happened).
  static List<MockRow> waste(MockDb db, Iterable<String> branchIds) {
    final ids = branchIds.toSet();
    final rows = db[InvTables.movements].where(
      (m) => m['movement_type'] == 'waste' && ids.contains(m['branch_id']),
    );
    rows.sort((a, b) {
      final c = DateTime.parse(
        wasteWhen(b),
      ).compareTo(DateTime.parse(wasteWhen(a)));
      return c != 0
          ? c
          : compareJson(a['ingredient_name'], b['ingredient_name']);
    });
    return rows;
  }
}
