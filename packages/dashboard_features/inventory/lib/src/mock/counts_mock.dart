/// Stock counts: the mock backend for the INV-CNT rows. Routes this unit owns
/// (the only file that registers them):
///
/// - POST /stocktakes/branches/{branch_id} (createStocktake) — also used by Ingredients' "Count this item"
/// - GET /stocktakes/{id} (getStocktake)
/// - PUT /stocktakes/{id}/items (upsertItems)
/// - POST /stocktakes/{id}/finalize (finalizeStocktake)
/// - POST /stocktakes/{id}/cancel (cancelStocktake)
/// - GET /stocktakes/{id}/variance-report (varianceReport)
///
/// The list (`GET /stocktakes/branches/{branch_id}`) is a shared read.
///
/// As the backend (`MadarRust/src/stocktakes/handlers.rs`): start needs
/// `inventory.counts.create`, reads `inventory.counts.read`, saving,
/// finalizing and cancelling `inventory.counts.edit`, each at the count's
/// branch. Book stock is the LIVE on-hand while a count is open and the
/// frozen figure once it is finalized; finalize posts one `stock_count`
/// movement per difference and stamps the count date.
library;

import 'package:dashboard_api/mock.dart';
import 'package:rust_bridge_dashboard/rules.dart' as rules;

import '../area_seed.dart';
import 'inventory_views.dart';

const String _allBranches = '00000000-0000-0000-0000-000000000000';

/// `VARIANCE_REASONS` as the backend validates them.
const List<String> _reasons = [
  'theft',
  'spoilage',
  'breakage',
  'miscount',
  'supplier_short',
  'transfer_error',
  'other',
];

bool _isOpen(MockRow st) =>
    st['status'] == 'in_progress' || st['status'] == 'draft';

/// Postgres `round()`: halves away from zero.
int _pgRound(num v) => v < 0 ? -((-v) + 0.5).floor() : (v + 0.5).floor();

/// The backend's `is_variance_flagged` (madar-inventory, through the core).
bool _flagged(double book, double counted, double pct) =>
    rules.isVarianceFlagged(book: book, counted: counted, pct: pct);

void registerCountsMocks(MockServer server, MockDb db) {
  final stocktakes = db.table(InvTables.stocktakes);
  final items = db.table(InvTables.stocktakeItems);

  /// The count [req] names, after the backend's gate: the capability, 404,
  /// then access to its branch.
  MockRow load(MockRequest req, String cap) {
    req.requireCap(cap);
    final st = stocktakes.get(req.param('id'), what: 'Stocktake not found');
    req.requireSameOrg(st['org_id'] as String?);
    req.requireBranch(st['branch_id']! as String);
    return st;
  }

  double onHand(String branchId, String ingId) =>
      (InvViews.stockRecord(db, branchId, ingId)?['on_hand'] as num?)
          ?.toDouble() ??
      0;

  /// `BOOK_EXPR`: live while open, frozen (or the opening) once closed.
  double book(MockRow st, MockRow it) => _isOpen(st)
      ? onHand(st['branch_id']! as String, it['org_ingredient_id']! as String)
      : ((it['book_qty'] ?? it['opening_qty'])! as num).toDouble();

  int? costOf(String branchId, MockRow ing) {
    final rec = InvViews.stockRecord(db, branchId, ing['id']! as String);
    final c = (rec?['cost_per_unit'] ?? ing['cost_per_unit']) as num?;
    return c == null ? null : _pgRound(c);
  }

  /// The count's items as `fetch_items` answers them: names, units and
  /// categories from the live catalog, book stock per [book], by category
  /// order, category name, then name.
  List<MockRow> itemsOf(MockRow st) {
    final cats = {for (final c in db[InvTables.categories].rows) c['id']: c};
    final out = <(num, String, String, MockRow)>[];
    for (final it in items.where((i) => i['stocktake_id'] == st['id'])) {
      final ing = db[InvTables.ingredients].find(
        it['org_ingredient_id']! as String,
      );
      final catId = ing?['category_id'] ?? it['category_id'];
      final cat = cats[catId];
      final b = book(st, it);
      final counted = (it['counted_qty'] as num?)?.toDouble();
      final row = <String, Object?>{
        ...it,
        'ingredient_name': ing?['name'] ?? it['ingredient_name'],
        'unit': ing?['unit'] ?? it['unit'],
        'category_id': catId,
        'category_name': cat?['name'] ?? it['category_name'],
        'opening_qty': (it['opening_qty']! as num).toDouble(),
        'book_qty': b,
        'counted_qty': counted,
        'variance': counted == null ? null : counted - b,
      };
      out.add((
        (cat?['sort_order'] as num?) ?? 0,
        row['category_name']! as String,
        row['ingredient_name']! as String,
        row,
      ));
    }
    out.sort((a, b) {
      final s = a.$1.compareTo(b.$1);
      if (s != 0) return s;
      final c = compareJson(a.$2, b.$2);
      return c != 0 ? c : compareJson(a.$3, b.$3);
    });
    return [for (final e in out) e.$4];
  }

  /// `Stocktake` as `fetch_stocktake` answers it (no list-only fields).
  MockRow header(MockRow st) => {
    ...st,
    'branch_name': null,
    'counted_items': null,
    'total_items': null,
  };

  MockRow full(MockRow st) => {
    ...header(st),
    'items': itemsOf(st),
    'variance_threshold_pct': InvViews.thresholdPct(
      db,
      st['org_id'] as String?,
    ),
  };

  MockRow newItem(MockRow st, MockRow ing, MockRow extra) {
    final branchId = st['branch_id']! as String;
    final ingId = ing['id']! as String;
    final rec = InvViews.stockRecord(db, branchId, ingId);
    return items.insert({
      'id': db.newId(InvTables.stocktakeItems),
      'stocktake_id': st['id'],
      'org_ingredient_id': ingId,
      'ingredient_name': ing['name'],
      'unit': ing['unit'],
      'category_id': ing['category_id'],
      'category_name': ing['category_name'],
      'opening_qty': (rec?['on_hand'] as num?)?.toDouble() ?? 0.0,
      'book_qty': null,
      'counted_qty': null,
      'variance': null,
      'variance_reason': null,
      'unit_cost': costOf(branchId, ing),
      'is_new': rec == null,
      'counted_by': null,
      'note': null,
      'created_at': db.nowIso,
      ...extra,
    }, timestamps: false);
  }

  server.on('POST', '/stocktakes/branches/{branch_id}', (req) {
    req.requireCap('inventory.counts.create');
    final branchId = req.param('branch_id');
    if (branchId == _allBranches) req.notFound('Branch not found');
    InvScope.branchIds(req, db, branchId);
    final orgId = InvScope.orgOf(db, branchId)!;
    final b = req.json;
    final categoryId = b['category_id'] as String?;
    final rawIds = b['org_ingredient_ids'] as List?;
    if (categoryId != null && rawIds != null) {
      req.badRequest('Pass either category_id or org_ingredient_ids, not both');
    }
    if (categoryId != null &&
        db[InvTables.categories].firstWhere(
              (c) => c['id'] == categoryId && c['org_id'] == orgId,
            ) ==
            null) {
      req.badRequest('Category not found in this organization');
    }
    final ids = rawIds?.cast<String>();
    if (ids != null) {
      if (ids.isEmpty) req.badRequest('org_ingredient_ids cannot be empty');
      final found = db[InvTables.ingredients]
          .where((i) => i['org_id'] == orgId && ids.contains(i['id']))
          .length;
      if (found != ids.length) {
        req.badRequest(
          "One or more ingredients are not in this organization's catalog",
        );
      }
    }
    if (stocktakes.firstWhere(
          (s) => s['branch_id'] == branchId && _isOpen(s),
        ) !=
        null) {
      req.conflict(
        'An open stocktake already exists for this branch. Finalize or '
        'cancel it first.',
      );
    }
    final now = db.nowIso;
    final st = stocktakes.insert({
      'id': db.newId(InvTables.stocktakes),
      'org_id': orgId,
      'branch_id': branchId,
      'branch_name': InvScope.branchName(db, branchId),
      'status': 'in_progress',
      'note': b['note'],
      'scope': categoryId != null
          ? {'kind': 'category', 'category_id': categoryId}
          : ids != null
          ? {'kind': 'items', 'org_ingredient_ids': ids}
          : {'kind': 'full'},
      'started_at': now,
      'started_by': req.persona.userId,
      'started_by_name': req.persona.displayName,
      'finalized_at': null,
      'finalized_by': null,
      'created_at': now,
    }, timestamps: false);
    // Every live catalog ingredient in scope, stocked here or not.
    for (final ing in db[InvTables.ingredients].where(
      (i) =>
          i['org_id'] == orgId &&
          (ids == null || ids.contains(i['id'])) &&
          (categoryId == null || i['category_id'] == categoryId),
    )) {
      newItem(st, ing, const {});
    }
    return MockResponse.created(full(st));
  });

  server.on('GET', '/stocktakes/{id}', (req) {
    final st = load(req, 'inventory.counts.read');
    return MockResponse.ok(full(st));
  });

  server.on('PUT', '/stocktakes/{id}/items', (req) {
    final st = load(req, 'inventory.counts.edit');
    if (!_isOpen(st)) {
      req.conflict('Cannot edit counts on a finalized or cancelled stocktake');
    }
    final input = req.json['items'];
    if (input is! List) req.badRequest('Json deserialize error: items');
    // One transaction: the first bad line refuses the whole save.
    final work = <(MockRow, MockRow)>[];
    final uncount = <MockRow>[];
    for (final raw in input) {
      final line = raw as Map<String, Object?>;
      final qty = line['counted_qty'];
      final ingId = line['org_ingredient_id'];
      // Required but nullable: null un-counts the line (B2).
      if (!line.containsKey('counted_qty') ||
          (qty != null && qty is! num) ||
          ingId is! String) {
        req.badRequest('Json deserialize error: counted_qty');
      }
      if (qty == null) {
        uncount.add(line);
        continue;
      }
      if ((qty as num) < 0) req.badRequest('counted_qty cannot be negative');
      final reason = line['variance_reason'] as String?;
      if (reason != null && !_reasons.contains(reason)) {
        req.badRequest(
          "Invalid variance reason '$reason'. Allowed: ${_reasons.join(', ')}",
        );
      }
      final ing = db[InvTables.ingredients].find(ingId);
      if (ing == null || ing['org_id'] != st['org_id']) {
        req.badRequest("Ingredient not found in this organization's catalog");
      }
      work.add((ing, line));
    }
    // A line with no row was never counted: nothing to do.
    for (final line in uncount) {
      items
          .firstWhere(
            (i) =>
                i['stocktake_id'] == st['id'] &&
                i['org_ingredient_id'] == line['org_ingredient_id'],
          )
          ?.addAll({
            'counted_qty': null,
            'counted_by': null,
            'variance_reason': null,
            'note': line['note'],
          });
    }
    for (final (ing, line) in work) {
      final set = {
        'counted_qty': (line['counted_qty']! as num).toDouble(),
        'note': line['note'],
        'counted_by': req.persona.userId,
        'variance_reason': line['variance_reason'],
      };
      final it = items.firstWhere(
        (i) =>
            i['stocktake_id'] == st['id'] &&
            i['org_ingredient_id'] == ing['id'],
      );
      if (it == null) {
        newItem(st, ing, set); // a found item outside the count's scope
      } else {
        it.addAll(set);
      }
    }
    return MockResponse.ok(full(st));
  });

  server.on('POST', '/stocktakes/{id}/finalize', (req) {
    final st = load(req, 'inventory.counts.edit');
    if (!_isOpen(st)) req.conflict('Stocktake is not open');
    final branchId = st['branch_id']! as String;
    final threshold = InvViews.thresholdPct(db, st['org_id'] as String?);
    final counted = items.where(
      (i) => i['stocktake_id'] == st['id'] && i['counted_qty'] != null,
    );
    String nameOf(MockRow it) =>
        (db[InvTables.ingredients].find(
                  it['org_ingredient_id']! as String,
                )?['name'] ??
                it['ingredient_name'])!
            as String;
    counted.sort((a, b) => compareJson(nameOf(a), nameOf(b)));
    final unexplained = [
      for (final it in counted)
        if (_flagged(
              onHand(branchId, it['org_ingredient_id']! as String),
              (it['counted_qty']! as num).toDouble(),
              threshold,
            ) &&
            it['variance_reason'] == null)
          nameOf(it),
    ];
    if (unexplained.isNotEmpty) {
      req.conflict(
        'These items have a large difference and need a reason before '
        'finalizing: ${unexplained.join(', ')}',
      );
    }
    final now = db.nowIso;
    for (final it in counted) {
      final ingId = it['org_ingredient_id']! as String;
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
      final bookQty = (rec['on_hand']! as num).toDouble();
      final qty = (it['counted_qty']! as num).toDouble();
      it['book_qty'] = bookQty;
      final delta = qty - bookQty;
      if (delta.abs() > 1e-9) {
        rec
          ..['on_hand'] = qty
          ..['last_movement_at'] = now;
        db[InvTables.movements].insert({
          'branch_id': branchId,
          'branch_name': InvScope.branchName(db, branchId),
          'branch_stock_id': rec['id'],
          'org_ingredient_id': ingId,
          'ingredient_name': nameOf(it),
          'unit': it['unit'],
          'movement_type': 'stock_count',
          'quantity': delta,
          'balance_after': qty,
          'below_zero': qty < 0,
          'unit_cost': it['unit_cost'],
          'reason': it['variance_reason'],
          'note': 'Stock count',
          'source_type': 'stocktake',
          'source_id': st['id'],
          'created_at': now,
          'created_by': req.persona.userId,
          'created_by_name': req.persona.displayName,
        }, timestamps: false);
      }
      rec['last_counted_at'] = now;
    }
    st
      ..['status'] = 'finalized'
      ..['finalized_by'] = req.persona.userId
      ..['finalized_at'] = now;
    return MockResponse.ok(full(st));
  });

  server.on('POST', '/stocktakes/{id}/cancel', (req) {
    final st = load(req, 'inventory.counts.edit');
    if (!_isOpen(st)) req.conflict('Only an open stocktake can be cancelled');
    st['status'] = 'cancelled';
    return MockResponse.ok(header(st));
  });

  server.on('GET', '/stocktakes/{id}/variance-report', (req) {
    final st = load(req, 'inventory.counts.read');
    final threshold = InvViews.thresholdPct(db, st['org_id'] as String?);
    final rows = [
      for (final it in itemsOf(st))
        () {
          final b = it['book_qty']! as double;
          final counted = it['counted_qty'] as double?;
          final cost = it['unit_cost'] as num?;
          return <String, Object?>{
            'org_ingredient_id': it['org_ingredient_id'],
            'ingredient_name': it['ingredient_name'],
            'unit': it['unit'],
            'category_name': it['category_name'],
            'opening_qty': it['opening_qty'],
            'book_qty': b,
            'counted_qty': counted,
            'variance': counted == null ? null : counted - b,
            'unit_cost': cost,
            'variance_value': cost == null || counted == null
                ? null
                : _pgRound((counted - b) * cost),
            'variance_reason': it['variance_reason'],
            'is_flagged': counted != null && _flagged(b, counted, threshold),
          };
        }(),
    ]..sort((a, b) => compareJson(a['ingredient_name'], b['ingredient_name']));
    var shrink = 0;
    var over = 0;
    var unknown = 0;
    for (final r in rows) {
      if (r['counted_qty'] == null) continue;
      final v = r['variance_value'] as int?;
      if (v == null) {
        unknown++;
      } else if (v < 0) {
        shrink += -v;
      } else {
        over += v;
      }
    }
    return MockResponse.ok({
      'stocktake_id': st['id'],
      'rows': rows,
      'total_shrinkage_value': shrink,
      'total_overage_value': over,
      'net_variance_value': over - shrink,
      'unknown_cost_count': unknown,
      'variance_threshold_pct': threshold,
    });
  });
}
