/// Ingredients: the mock backend for the INV-ING rows. Routes this unit owns
/// (the only file that registers them):
///
/// - POST /inventory/orgs/{org_id}/catalog (createCatalogItem)
/// - PATCH /inventory/orgs/{org_id}/catalog/{id} (updateCatalogItem)
/// - DELETE /inventory/orgs/{org_id}/catalog/{id} (deleteCatalogItem)
/// - PUT /inventory/branches/{branch_id}/stock/{org_ingredient_id}/par (setParLevels)
/// - GET /inventory/branches/{branch_id}/movements (listMovements)
///
/// The catalog, branch stock and categories reads are shared reads; the
/// category create is Settings' and the stocktake create Counts'. Until those
/// units answer them, [registerIngredientsMocks] answers them too (a fallback
/// registered only when the route is free, and replaced by the owner's
/// handler when it registers later), so "New category…" and "Count this
/// item" work in mock mode either way.
///
/// As the backend (`MadarRust/src/inventory/handlers.rs`): create needs
/// `inventory.items.create`, edit and par levels `inventory.adjust`, delete
/// `inventory.items.delete`, the ledger `inventory.read`; a PATCH leaves a
/// field it gets as null unchanged (`COALESCE`).
library;

import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';
import 'inventory_views.dart';

const List<String> _units = ['g', 'kg', 'ml', 'l', 'pcs'];

/// Grams in a kilogram, millilitres in a litre: a unit's size in its family's
/// base, and its family.
const Map<String, (String, double)> _unitScale = {
  'g': ('weight', 1),
  'kg': ('weight', 1000),
  'ml': ('volume', 1),
  'l': ('volume', 1000),
  'pcs': ('count', 1),
};

double _round(double v, int places) {
  var f = 1.0;
  for (var i = 0; i < places; i++) {
    f *= 10;
  }
  return (v * f).round() / f;
}

/// The backend's `slugify`: ASCII letters and digits, lower case, runs of
/// anything else as one `_`, at most 64.
String? ingredientCategorySlug(String name) {
  final out = StringBuffer();
  var pending = false;
  for (final ch in name.trim().split('')) {
    if (RegExp('[A-Za-z0-9]').hasMatch(ch)) {
      if (pending && out.isNotEmpty) out.write('_');
      out.write(ch.toLowerCase());
      pending = false;
    } else {
      pending = true;
    }
  }
  final s = out.toString();
  if (s.isEmpty) return null;
  return s.length > 64 ? s.substring(0, 64) : s;
}

void registerIngredientsMocks(MockServer server, MockDb db) {
  final ingredients = db[InvTables.ingredients];

  String org(MockRequest req) {
    final id = req.param('org_id');
    req.requireSameOrg(id);
    return id;
  }

  void validateUnit(MockRequest req, Object? unit) {
    if (unit is! String || !_units.contains(unit)) {
      req.badRequest('Unit must be one of: g, kg, ml, l, pcs');
    }
  }

  void supplierInOrg(MockRequest req, Object? id, String orgId) {
    if (id == null) return;
    final s = db[InvTables.suppliers].find(id as String);
    if (s == null || s['org_id'] != orgId) {
      req.badRequest('Supplier does not belong to this organization');
    }
  }

  void categoryInOrg(MockRequest req, Object? id, String orgId) {
    final c = id is String ? db[InvTables.categories].find(id) : null;
    if (c == null || c['org_id'] != orgId) {
      req.badRequest('Category does not belong to this organization');
    }
  }

  void uniqueName(MockRequest req, String orgId, String name, {String? not}) {
    final taken = ingredients.firstWhere(
      (r) => r['org_id'] == orgId && r['name'] == name && r['id'] != not,
    );
    if (taken != null) {
      req.conflict(
        'An ingredient with this name already exists in the catalog',
      );
    }
  }

  /// The org's `general` category, created when missing.
  String generalCategory(String orgId) {
    final g = db[InvTables.categories].firstWhere(
      (c) => c['org_id'] == orgId && c['slug'] == 'general',
    );
    if (g != null) return g['id']! as String;
    return db[InvTables.categories].insert({
          'id': db.newId(InvTables.categories),
          'org_id': orgId,
          'slug': 'general',
          'name': 'General',
          'sort_order': 0,
          'is_packaging': false,
        })['id']!
        as String;
  }

  server.on('POST', '/inventory/orgs/{org_id}/catalog', (req) {
    req.requireCap('inventory.items.create');
    final orgId = org(req);
    final b = req.json;
    validateUnit(req, b['unit']);
    final name = ((b['name'] as String?) ?? '').trim();
    if (name.isEmpty) req.badRequest('name cannot be empty');
    supplierInOrg(req, b['supplier_id'], orgId);
    if (b['category_id'] != null) categoryInOrg(req, b['category_id'], orgId);
    uniqueName(req, orgId, name);
    final categoryId = b['category_id'] as String? ?? generalCategory(orgId);
    final row = ingredients.insert({
      'id': db.newId(InvTables.ingredients),
      'org_id': orgId,
      'name': name,
      'unit': b['unit'],
      'category_id': categoryId,
      'category_slug': null,
      'category_name': null,
      'description': b['description'],
      'cost_per_unit': (b['cost_per_unit'] as num?)?.toDouble(),
      'supplier_id': b['supplier_id'],
      'pack_unit': b['pack_unit'],
      'pack_size': (b['pack_size'] as num?)?.toDouble(),
      'yield_pct': (b['yield_pct'] as num?)?.toDouble(),
      'density_g_per_ml': (b['density_g_per_ml'] as num?)?.toDouble(),
      'is_active': true,
    });
    return MockResponse.created(InvViews.ingredient(db, row));
  });

  server.on('PATCH', '/inventory/orgs/{org_id}/catalog/{id}', (req) {
    req.requireCap('inventory.adjust');
    final orgId = org(req);
    final b = req.json;
    if (b['unit'] != null) validateUnit(req, b['unit']);
    supplierInOrg(req, b['supplier_id'], orgId);
    if (b['category_id'] != null) categoryInOrg(req, b['category_id'], orgId);
    final id = req.param('id');
    final row = ingredients.find(id);
    if (row == null || row['org_id'] != orgId) {
      req.notFound('Ingredient not found');
    }
    final current = row['unit']! as String;
    final next = b['unit'] as String?;
    if (next != null && next != current) {
      if (b['cost_per_unit'] != null) {
        req.badRequest(
          'Change the unit and the cost in separate requests — the cost is '
          'converted automatically when the unit changes.',
        );
      }
      final (fromFamily, fromSize) = _unitScale[current]!;
      final (toFamily, toSize) = _unitScale[next]!;
      if (fromFamily != toFamily || fromFamily == 'count') {
        req.badRequest(
          'A unit can only change within the same measure: g ↔ kg or ml ↔ l.',
        );
      }
      // F: how many old units fit in one new unit (g per kg = 1000).
      final f = toSize / fromSize;
      double? div(Object? v) =>
          v == null ? null : _round((v as num).toDouble() / f, 3);
      double? mul(Object? v) =>
          v == null ? null : _round((v as num).toDouble() * f, 2);
      for (final s in db[InvTables.branchStock].where(
        (s) => s['org_ingredient_id'] == id,
      )) {
        db[InvTables.branchStock].update(s['id']! as String, {
          'on_hand': div(s['on_hand']),
          'par_min': div(s['par_min']),
          'par_max': div(s['par_max']),
          'cost_per_unit': mul(s['cost_per_unit']),
        });
      }
      for (final m in db[InvTables.movements].where(
        (m) => m['org_ingredient_id'] == id,
      )) {
        db[InvTables.movements].update(m['id']! as String, {
          'quantity': div(m['quantity']),
          'balance_after': div(m['balance_after']),
          'unit': next,
        });
      }
      ingredients.update(id, {'cost_per_unit': mul(row['cost_per_unit'])});
    }
    final name = (b['name'] as String?)?.trim();
    if (name != null) uniqueName(req, orgId, name, not: id);
    // COALESCE: a field sent as null (or not sent) keeps its value.
    final patch = <String, Object?>{
      'name': ?name,
      'unit': ?next,
      for (final k in [
        'category_id',
        'description',
        'is_active',
        'supplier_id',
        'pack_unit',
      ])
        if (b[k] != null) k: b[k],
      for (final k in [
        'cost_per_unit',
        'pack_size',
        'yield_pct',
        'density_g_per_ml',
      ])
        if (b[k] != null) k: (b[k]! as num).toDouble(),
    };
    final updated = ingredients.update(id, patch);
    return MockResponse.ok(InvViews.ingredient(db, updated));
  });

  server.on('DELETE', '/inventory/orgs/{org_id}/catalog/{id}', (req) {
    req.requireCap('inventory.items.delete');
    final orgId = org(req);
    final id = req.param('id');
    final row = ingredients.find(id);
    if (row == null || row['org_id'] != orgId) {
      req.notFound('Ingredient not found');
    }
    final stocked = db[InvTables.branchStock].firstWhere(
      (s) => s['org_ingredient_id'] == id && ((s['on_hand'] as num?) ?? 0) != 0,
    );
    if (stocked != null) {
      req.conflict(
        'Ingredient still has stock at a branch. Count or waste it to zero first.',
      );
    }
    ingredients.delete(id);
    return MockResponse.empty();
  });

  server.on(
    'PUT',
    '/inventory/branches/{branch_id}/stock/{org_ingredient_id}/par',
    (req) {
      req.requireCap('inventory.adjust');
      final branchId = InvScope.branchIds(
        req,
        db,
        req.param('branch_id'),
      ).single;
      final orgId = InvScope.orgOf(db, branchId);
      final ingId = req.param('org_ingredient_id');
      final ing = ingredients.find(ingId);
      if (ing == null || ing['org_id'] != orgId) {
        req.badRequest("Ingredient not found in this organization's catalog");
      }
      final b = req.json;
      final lo = (b['par_min'] as num?)?.toDouble();
      final hi = (b['par_max'] as num?)?.toDouble();
      if ((lo ?? 0) < 0 || (hi ?? 0) < 0) {
        req.badRequest('Par levels cannot be negative');
      }
      if (lo != null && hi != null && hi < lo) {
        req.badRequest('Max par must be at least the min par');
      }
      final existing = InvViews.stockRecord(db, branchId, ingId);
      if (existing != null) {
        db[InvTables.branchStock].update(existing['id']! as String, {
          'par_min': lo,
          'par_max': hi,
        });
      } else {
        db[InvTables.branchStock].insert({
          'id': db.newId(InvTables.branchStock),
          'branch_id': branchId,
          'org_ingredient_id': ingId,
          'on_hand': 0.0,
          'par_min': lo,
          'par_max': hi,
          'cost_per_unit': null,
          'last_counted_at': null,
          'last_movement_at': null,
        }, timestamps: false);
      }
      return MockResponse.ok(
        InvViews.branchStock(
          db,
          branchId,
        ).firstWhere((r) => r['org_ingredient_id'] == ingId),
      );
    },
  );

  server.on('GET', '/inventory/branches/{branch_id}/movements', (req) {
    req.requireCap('inventory.read');
    final branchId = InvScope.branchIds(req, db, req.param('branch_id')).single;
    final ingId = req.q('org_ingredient_id');
    final type = req.q('type');
    final from = req.qDateTime('from');
    final to = req.qDateTime('to');
    final perPage = (req.qInt('per_page') ?? 100).clamp(1, 500);
    final page = (req.qInt('page') ?? 1).clamp(1, 1 << 30);
    final rows = db[InvTables.movements].where((m) {
      if (m['branch_id'] != branchId) return false;
      if (ingId != null && m['org_ingredient_id'] != ingId) return false;
      if (type != null && m['movement_type'] != type) return false;
      final at = DateTime.parse(m['created_at']! as String);
      if (from != null && at.isBefore(from)) return false;
      if (to != null && at.isAfter(to)) return false;
      return true;
    });
    rows.sort((a, b) {
      final c = DateTime.parse(
        b['created_at']! as String,
      ).compareTo(DateTime.parse(a['created_at']! as String));
      return c != 0 ? c : compareJson(b['id'], a['id']);
    });
    return MockResponse.ok([
      for (final m in rows.skip((page - 1) * perPage).take(perPage))
        () {
          final ing = ingredients.find(m['org_ingredient_id']! as String);
          return {
            ...m,
            'ingredient_name': ing?['name'] ?? m['ingredient_name'],
            'unit': ing?['unit'] ?? m['unit'],
          };
        }(),
    ]);
  });

  // ── Fallbacks for routes other units own ───────────────────────────────

  if (!server.handles('POST', '/inventory/orgs/{org_id}/categories')) {
    server.on('POST', '/inventory/orgs/{org_id}/categories', (req) {
      req.requireCap('inventory.items.create');
      final orgId = org(req);
      final b = req.json;
      final name = ((b['name'] as String?) ?? '').trim();
      if (name.isEmpty || name.length > 80) {
        req.badRequest('Category name must be 1–80 characters');
      }
      final slug = ingredientCategorySlug(name);
      if (slug == null) {
        req.badRequest('Category name must contain a letter or digit');
      }
      if (db[InvTables.categories].firstWhere(
            (c) => c['org_id'] == orgId && c['slug'] == slug,
          ) !=
          null) {
        req.conflict("A category with the key '$slug' already exists");
      }
      final row = db[InvTables.categories].insert({
        'id': db.newId(InvTables.categories),
        'org_id': orgId,
        'slug': slug,
        'name': name,
        'sort_order': (b['sort_order'] as num?)?.toInt() ?? 10,
        'is_packaging': b['is_packaging'] ?? slug == 'packaging',
      });
      return MockResponse.created({...row, 'ingredient_count': 0});
    });
  }

  if (!server.handles('POST', '/stocktakes/branches/{branch_id}')) {
    server.on('POST', '/stocktakes/branches/{branch_id}', (req) {
      req.requireCap('inventory.counts.create');
      final branchId = InvScope.branchIds(
        req,
        db,
        req.param('branch_id'),
      ).single;
      final orgId = InvScope.orgOf(db, branchId)!;
      final open = db[InvTables.stocktakes].firstWhere(
        (s) =>
            s['branch_id'] == branchId &&
            (s['status'] == 'in_progress' || s['status'] == 'draft'),
      );
      if (open != null) {
        req.conflict(
          'An open stocktake already exists for this branch. Finalize or '
          'cancel it first.',
        );
      }
      final b = req.json;
      final ids = [for (final i in (b['org_ingredient_ids'] as List?) ?? []) i];
      if (b['category_id'] != null && ids.isNotEmpty) {
        req.badRequest(
          'Pass either category_id or org_ingredient_ids, not both',
        );
      }
      final stock = InvViews.branchStock(db, branchId);
      final rows = [
        for (final r in stock)
          if (ids.isEmpty
              ? (b['category_id'] == null ||
                    r['category_id'] == b['category_id'])
              : ids.contains(r['org_ingredient_id']))
            r,
      ];
      if (ids.isNotEmpty && rows.length != ids.length) {
        req.badRequest("Ingredient not found in this organization's catalog");
      }
      final id = db.newId(InvTables.stocktakes);
      final st = db[InvTables.stocktakes].insert({
        'id': id,
        'org_id': orgId,
        'branch_id': branchId,
        'branch_name': InvScope.branchName(db, branchId),
        'status': 'in_progress',
        'note': b['note'],
        'scope': ids.isNotEmpty
            ? {'kind': 'items', 'org_ingredient_ids': ids}
            : b['category_id'] != null
            ? {'kind': 'category', 'category_id': b['category_id']}
            : {'kind': 'full'},
        'started_at': db.nowIso,
        'started_by': req.persona.userId,
        'started_by_name': req.persona.displayName,
        'finalized_at': null,
        'finalized_by': null,
      });
      for (final r in rows) {
        db[InvTables.stocktakeItems].insert({
          'id': db.newId(InvTables.stocktakeItems),
          'stocktake_id': id,
          'org_ingredient_id': r['org_ingredient_id'],
          'ingredient_name': r['ingredient_name'],
          'unit': r['unit'],
          'category_id': r['category_id'],
          'category_name': r['category_name'],
          'opening_qty': r['on_hand'],
          'book_qty': r['on_hand'],
          'counted_qty': null,
          'variance': null,
          'variance_reason': null,
          'unit_cost': r['cost_per_unit'] == null
              ? null
              : ((r['cost_per_unit']! as num) + 0.5).floor(),
          'is_new': r['has_activity'] != true,
          'counted_by': null,
          'note': null,
        });
      }
      return MockResponse.created({
        ...InvViews.stocktake(db, st),
        'items': InvViews.stocktakeItems(db, id),
        'variance_threshold_pct': InvViews.thresholdPct(db, orgId),
      });
    });
  }
}
