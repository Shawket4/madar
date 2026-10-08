/// Mock handlers of the `bases` unit: recipe bases (their writes and usage)
/// and packaging rules (their reads, writes and `POST /packaging-rules/apply`),
/// as the backend answers them (`MadarRust/src/menu/bases.rs`,
/// `src/menu/packaging.rs`):
///
/// - reads need `menu.items.read`, writes `menu.items.edit`, apply its own
///   `menu.packaging_rules.apply`; the org is the session's (a platform admin
///   must have picked one);
/// - names are trimmed and 1 to 120 characters; base names are unique per org
///   (case-insensitive, 409); a rule must match something (400); matches must
///   be the org's own category / live item (400);
/// - lines: a quantity >= 0, the org's own live ingredient, converted to its
///   unit, no duplicate (size label, ingredient) in a base or ingredient in a
///   rule (400);
/// - a base write re-expands every item using it and says how many sizes
///   changed; deleting a base detaches its sizes; rule writes only store the
///   rule (Apply re-expands every item).
///
/// `GET /recipe-bases` is the area's shared read (`shared_mock.dart`).
/// `GET /costing/catalog` is the items unit's; this file answers it only when
/// nobody else does (the item names of the rule rows and picker).
library;

import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';
import '../shared/menu_text.dart';
import 'shared_mock.dart' show recipeBaseOut;

const String _read = 'menu.items.read';
const String _edit = 'menu.items.edit';
const String _apply = 'menu.packaging_rules.apply';

/// The per-org catalog revision a modeling write bumps.
const String _revisions = 'menu_catalog_revisions';

void registerBasesMocks(MockServer server, MockDb db) {
  final data = CatalogMenuData(db);
  MockTable bases() => db[MenuTables.bases];
  MockTable rules() => db[MenuTables.rules];

  // ── recipe bases ────────────────────────────────────────────────────────

  // POST /recipe-bases → 201 RecipeBaseOut.
  server.on('POST', '/recipe-bases', (req) {
    req.requireCap(_edit);
    final org = _claimsOrg(req);
    final b = req.json;
    final name = _cleanName(req, b['name']);
    final lines = b['lines'] == null
        ? const <Map<String, Object?>>[]
        : _baseLines(req, data, org, b['lines']);
    _uniqueBaseName(req, db, org, name);
    final now = db.nowIso;
    final id = db.newId(MenuTables.bases);
    final row = bases().insert({
      'id': id,
      'org_id': org,
      'name': name,
      'name_ar': _cleanOpt(b['name_ar']),
      'is_active': (b['is_active'] as bool?) ?? true,
      'lines': _storedBaseLines(db, id, lines),
      'created_at': now,
      'updated_at': now,
    }, timestamps: false);
    return MockResponse.created(_baseOut(db, data, row));
  });

  // PATCH /recipe-bases/{id} → RecipeBaseSaveResult. `name_ar: null` (or
  // absent) leaves the Arabic name; `""` clears it.
  server.on('PATCH', '/recipe-bases/{id}', (req) {
    req.requireCap(_edit);
    final row = _base(req, db);
    final b = req.json;
    final name = b['name'] == null ? null : _cleanName(req, b['name']);
    if (name != null) {
      _uniqueBaseName(req, db, row['org_id'] as String, name, except: row['id']);
    }
    if (name != null) row['name'] = name;
    if (b['name_ar'] != null) row['name_ar'] = _cleanOpt(b['name_ar']);
    final active = b['is_active'];
    if (active is bool) row['is_active'] = active;
    row['updated_at'] = db.nowIso;
    final changed = _rebuildUsing(db, data, row['id'] as String);
    return MockResponse.ok(_saveResult(db, data, row, changed));
  });

  // DELETE /recipe-bases/{id} → 204: sizes detached (their base lines go),
  // the base soft-deleted.
  server.on('DELETE', '/recipe-bases/{id}', (req) {
    req.requireCap(_edit);
    final row = _base(req, db);
    final id = row['id'] as String;
    final items = _itemsUsing(db, id);
    for (final s in db[MenuTables.sizes].where((s) => s['base_id'] == id)) {
      s['base_id'] = null;
    }
    row
      ..['deleted_at'] = db.nowIso
      ..['is_active'] = false;
    items.forEach(data.rebuildItem);
    _bumpRevision(db, row['org_id'] as String);
    return MockResponse.empty();
  });

  // PUT /recipe-bases/{id}/lines → RecipeBaseSaveResult.
  server.on('PUT', '/recipe-bases/{id}/lines', (req) {
    req.requireCap(_edit);
    final row = _base(req, db);
    final lines = _baseLines(req, data, row['org_id'] as String, req.json['lines']);
    row
      ..['lines'] = _storedBaseLines(db, row['id'] as String, lines)
      ..['updated_at'] = db.nowIso;
    final changed = _rebuildUsing(db, data, row['id'] as String);
    return MockResponse.ok(_saveResult(db, data, row, changed));
  });

  // GET /recipe-bases/{id}/usage → RecipeBaseUsage (live items only, by
  // item name, then size order, then label).
  server.on('GET', '/recipe-bases/{id}/usage', (req) {
    req.requireCap(_read);
    final row = _base(req, db);
    final sizes = _usingSizes(db, row['id'] as String)
      ..sort((a, b) {
        final c = compareJson(a.$2['name'], b.$2['name']);
        if (c != 0) return c;
        final s = ((a.$1['sort'] as int?) ?? 0) - ((b.$1['sort'] as int?) ?? 0);
        return s != 0 ? s : compareJson(a.$1['label'], b.$1['label']);
      });
    return MockResponse.ok({
      'base_id': row['id'],
      'item_count': {for (final s in sizes) s.$2['id']}.length,
      'size_count': sizes.length,
      'sizes': [
        for (final (s, item) in sizes)
          {
            'size_id': s['id'],
            'size_label': s['label'],
            'menu_item_id': item['id'],
            'menu_item_name': item['name'],
          },
      ],
    });
  });

  // ── packaging rules ─────────────────────────────────────────────────────

  // GET /packaging-rules: by sort, then name, then creation.
  server.on('GET', '/packaging-rules', (req) {
    req.requireCap(_read);
    final org = _claimsOrg(req);
    final rows = rules().where((r) => r['org_id'] == org)
      ..sort((a, b) {
        final s = ((a['sort'] as int?) ?? 0) - ((b['sort'] as int?) ?? 0);
        if (s != 0) return s;
        final n = compareJson(a['name'], b['name']);
        return n != 0 ? n : compareJson(a['created_at'], b['created_at']);
      });
    return MockResponse.ok([for (final r in rows) _ruleOut(data, r)]);
  });

  // POST /packaging-rules → 201 PackagingRuleOut (not applied yet).
  server.on('POST', '/packaging-rules', (req) {
    req.requireCap(_edit);
    final org = _claimsOrg(req);
    final b = req.json;
    final name = _cleanName(req, b['name']);
    final label = _cleanOpt(b['match_size_label']);
    final cat = b['match_category_id'] as String?;
    final item = b['match_item_id'] as String?;
    if (cat == null && label == null && item == null) {
      req.badRequest('A rule must match a category, a size label or an item');
    }
    _validateMatches(req, db, org, cat, item);
    final lines = _ruleLines(req, data, org, b['lines']);
    final now = db.nowIso;
    final row = rules().insert({
      'id': db.newId(MenuTables.rules),
      'org_id': org,
      'name': name,
      'match_category_id': cat,
      'match_size_label': label,
      'match_item_id': item,
      'sort': (b['sort'] as int?) ?? 0,
      'is_active': (b['is_active'] as bool?) ?? true,
      'lines': lines,
      'created_at': now,
      'updated_at': now,
    }, timestamps: false);
    return MockResponse.created(_ruleOut(data, row));
  });

  // PATCH /packaging-rules/{id}: a match key present replaces (null clears),
  // absent keeps; `lines` present replaces them all.
  server.on('PATCH', '/packaging-rules/{id}', (req) {
    req.requireCap(_edit);
    final row = _rule(req, db);
    final org = row['org_id'] as String;
    final b = req.json;
    final cat = b.containsKey('match_category_id')
        ? b['match_category_id'] as String?
        : row['match_category_id'] as String?;
    final label = b.containsKey('match_size_label')
        ? _cleanOpt(b['match_size_label'])
        : row['match_size_label'] as String?;
    final item = b.containsKey('match_item_id')
        ? b['match_item_id'] as String?
        : row['match_item_id'] as String?;
    if (cat == null && label == null && item == null) {
      req.badRequest('A rule must match a category, a size label or an item');
    }
    _validateMatches(req, db, org, cat, item);
    final name = b['name'] == null ? null : _cleanName(req, b['name']);
    final lines = b['lines'] == null
        ? null
        : _ruleLines(req, data, org, b['lines']);
    row
      ..['match_category_id'] = cat
      ..['match_size_label'] = label
      ..['match_item_id'] = item
      ..['updated_at'] = db.nowIso;
    if (name != null) row['name'] = name;
    if (b['sort'] is int) row['sort'] = b['sort'];
    if (b['is_active'] is bool) row['is_active'] = b['is_active'];
    if (lines != null) row['lines'] = lines;
    return MockResponse.ok(_ruleOut(data, row));
  });

  // DELETE /packaging-rules/{id} → 204 (its expanded lines stay until the
  // next apply).
  server.on('DELETE', '/packaging-rules/{id}', (req) {
    req.requireCap(_edit);
    final row = _rule(req, db);
    rules().delete(row['id'] as String);
    return MockResponse.empty();
  });

  // POST /packaging-rules/apply → ApplyPackagingRulesResult.
  server.on('POST', '/packaging-rules/apply', (req) {
    req.requireCap(_apply);
    final org = _claimsOrg(req);
    final r = data.applyRules();
    // Sizes that now carry at least one rule line (the backend counts after
    // the re-expansion).
    final live = {
      for (final m in db[MenuTables.menuItems].rows)
        if (m['org_id'] == org && m['deleted_at'] == null) m['id'],
    };
    final withRule = {
      for (final l in db[MenuTables.recipeLines].rows)
        if (l['source'] == 'rule' && live.contains(l['menu_item_id']))
          l['size_id'],
    }.length;
    return MockResponse.ok({
      ...r,
      'sizes_with_rule': withRule,
      'catalog_revision': _bumpRevision(db, org),
    });
  });

  // GET /costing/catalog (the items unit's; answered here only when no
  // handler is registered yet): the org's live items by name with their
  // per-size costs, paged (`per_page` 1..500, 50 by default).
  if (!server.handles('GET', '/costing/catalog')) {
    server.on('GET', '/costing/catalog', (req) {
      req.requireCap(_read);
      final org = req.q('org_id');
      if (org == null) {
        req.badRequest('Query deserialize error: missing field `org_id`');
      }
      req.requireSameOrg(org);
      final hasRecipe = req.qBool('has_recipe');
      if (hasRecipe != null) req.requireCap('recipes.read');
      final category = req.q('category_id');
      final search = req.q('search')?.trim().toLowerCase();
      final rows = db[MenuTables.menuItems].query(
        filters: {'org_id': org, 'category_id': category},
        where: (m) =>
            m['deleted_at'] == null &&
            (search == null ||
                search.isEmpty ||
                '${m['name']}'.toLowerCase().contains(search)) &&
            (hasRecipe == null ||
                data.hasRecipe(m['id'] as String) == hasRecipe),
        sort: 'name',
      );
      return MockResponse.ok(
        pageOf(
          [
            for (final m in rows) {...m, 'sku_costs': data.skuCosts(m)},
          ],
          req,
          maxPerPage: 500,
        ),
      );
    });
  }
}

// ── helpers ───────────────────────────────────────────────────────────────

/// `claims_org`: the session's org; a platform admin must have picked one.
String _claimsOrg(MockRequest req) =>
    req.orgId ??
    req.fail(
      MockResponse.forbidden('A super admin must scope this to an org'),
    );

/// `clean_name`: trimmed, 1 to 120 characters, else 400.
String _cleanName(MockRequest req, Object? raw) {
  final n = (raw is String ? raw : '').trim();
  if (n.isEmpty || n.runes.length > 120) {
    req.badRequest('Name must be 1–120 characters');
  }
  return n;
}

/// `clean_opt`: trimmed, blank = null.
String? _cleanOpt(Object? raw) {
  if (raw is! String) return null;
  final s = raw.trim();
  return s.isEmpty ? null : s;
}

void _uniqueBaseName(
  MockRequest req,
  MockDb db,
  String org,
  String name, {
  Object? except,
}) {
  final taken = db[MenuTables.bases].rows.any(
    (b) =>
        b['org_id'] == org &&
        b['deleted_at'] == null &&
        b['id'] != except &&
        '${b['name']}'.toLowerCase() == name.toLowerCase(),
  );
  if (taken) req.conflict('A recipe base with this name already exists');
}

/// A live base of the caller's org (404, then the same-org 403).
MockRow _base(MockRequest req, MockDb db) {
  final row = db[MenuTables.bases].find(req.param('id'));
  if (row == null || row['deleted_at'] != null) {
    req.notFound('Recipe base not found');
  }
  req.requireSameOrg(row['org_id'] as String?);
  return row;
}

MockRow _rule(MockRequest req, MockDb db) {
  final row = db[MenuTables.rules].find(req.param('id'));
  if (row == null) req.notFound('Packaging rule not found');
  req.requireSameOrg(row['org_id'] as String?);
  return row;
}

/// The sizes following [baseId] whose item is live, with their item.
List<(MockRow, MockRow)> _usingSizes(MockDb db, String baseId) => [
  for (final s in db[MenuTables.sizes].where((s) => s['base_id'] == baseId))
    if (db[MenuTables.menuItems].find(s['menu_item_id'] as String)
        case final item? when item['deleted_at'] == null)
      (s, item),
];

/// Every item with a size on [baseId] (live or not), as the backend
/// re-expands them.
List<String> _itemsUsing(MockDb db, String baseId) => {
  for (final s in db[MenuTables.sizes].where((s) => s['base_id'] == baseId))
    s['menu_item_id'] as String,
}.toList();

int _rebuildUsing(MockDb db, CatalogMenuData data, String baseId) {
  var changed = 0;
  for (final item in _itemsUsing(db, baseId)) {
    changed += data.rebuildItem(item);
  }
  final org = db[MenuTables.bases].find(baseId)?['org_id'] as String?;
  if (org != null) _bumpRevision(db, org);
  return changed;
}

int _bumpRevision(MockDb db, String org) {
  final t = db[_revisions];
  final row = t.find(org) ?? t.insert({'id': org, 'revision': 1}, timestamps: false);
  final next = ((row['revision'] as int?) ?? 1) + 1;
  row['revision'] = next;
  return next;
}

int _revision(MockDb db, String org) =>
    (db[_revisions].find(org)?['revision'] as int?) ?? 1;

/// `RecipeBaseOut`, counting only live items' sizes (as `load_base` does).
Map<String, Object?> _baseOut(MockDb db, CatalogMenuData data, MockRow b) {
  final live = [
    for (final s in db[MenuTables.sizes].rows)
      if (s['base_id'] == b['id'] &&
          db[MenuTables.menuItems].find(s['menu_item_id'] as String)?['deleted_at'] ==
              null)
        s,
  ];
  return recipeBaseOut(b, data, live);
}

Map<String, Object?> _saveResult(
  MockDb db,
  CatalogMenuData data,
  MockRow b,
  int changed,
) => {
  'base': _baseOut(db, data, b),
  'sizes_changed': changed,
  'catalog_revision': _revision(db, b['org_id'] as String),
};

/// Stored base lines (ids, sorted by `sort`, then all-sizes first).
List<Map<String, Object?>> _storedBaseLines(
  MockDb db,
  String baseId,
  List<Map<String, Object?>> lines,
) {
  final out = [
    for (final l in lines) {'id': db.newId('recipe_base_lines'), ...l},
  ];
  out.sort((a, b) {
    final s = ((a['sort'] as int?) ?? 0) - ((b['sort'] as int?) ?? 0);
    if (s != 0) return s;
    final la = a['size_label'], lb = b['size_label'];
    if (la == null && lb != null) return -1;
    if (la != null && lb == null) return 1;
    return 0;
  });
  return out;
}

/// `normalize_lines` of a base: each `{size_label, ingredient_id, quantity,
/// unit, sort}` checked and converted to the ingredient's unit.
List<Map<String, Object?>> _baseLines(
  MockRequest req,
  CatalogMenuData data,
  String org,
  Object? raw,
) {
  if (raw is! List) req.badRequest('Json deserialize error: missing field `lines`');
  final seen = <String>{};
  return [
    for (final (i, l) in raw.cast<Map<String, Object?>>().indexed)
      () {
        final label = _cleanOpt(l['size_label']);
        final ing = '${l['ingredient_id']}';
        if (!seen.add('$label|$ing')) {
          req.badRequest('Duplicate ingredient for the same size in base');
        }
        final (unit, q) = _normalize(req, data, org, l);
        return <String, Object?>{
          'size_label': label,
          'ingredient_id': ing,
          'quantity': q,
          'unit': unit,
          'sort': (l['sort'] as int?) ?? i,
        };
      }(),
  ];
}

/// `normalize_rule_lines`: `{ingredient_id, quantity, unit}` checked and
/// converted, sorted in the order sent.
List<Map<String, Object?>> _ruleLines(
  MockRequest req,
  CatalogMenuData data,
  String org,
  Object? raw,
) {
  if (raw is! List) req.badRequest('Json deserialize error: missing field `lines`');
  final seen = <String>{};
  return [
    for (final (i, l) in raw.cast<Map<String, Object?>>().indexed)
      () {
        final ing = '${l['ingredient_id']}';
        if (!seen.add(ing)) req.badRequest('Duplicate ingredient in rule');
        final (unit, q) = _normalize(req, data, org, l);
        return <String, Object?>{
          'ingredient_id': ing,
          'quantity': q,
          'unit': unit,
          'sort': i,
        };
      }(),
  ];
}

/// `normalize_recipe_unit`: the org's own live ingredient, the quantity
/// converted to its unit and rounded to 3 decimals (as decimal text).
(String, String) _normalize(
  MockRequest req,
  CatalogMenuData data,
  String org,
  Map<String, Object?> l,
) {
  final q = l['quantity'];
  if (q is! num || !q.isFinite || q < 0) {
    req.badRequest('quantity must be >= 0');
  }
  final ing = data.ingredient('${l['ingredient_id']}');
  if (ing == null || ing['org_id'] != org || ing['deleted_at'] != null) {
    req.badRequest("Linked ingredient not found in this organization's catalog");
  }
  final from = '${l['unit']}';
  final to = ing['unit'] as String;
  final base = jsRound(_convert(req, q.toDouble(), from, to) * 1000) / 1000;
  if (q > 0 && base <= 0) {
    req.badRequest(
      'quantity ${jsNumberText(q)} $from is too small for base unit $to (rounds to 0)',
    );
  }
  return (to, fmtQty(base));
}

const Map<String, (String, double)> _units = {
  'g': ('mass', 1),
  'kg': ('mass', 1000),
  'ml': ('volume', 1),
  'l': ('volume', 1000),
  'pcs': ('count', 1),
};

/// `madar_units::convert_with_density` without a density on the ingredient.
double _convert(MockRequest req, double q, String from, String to) {
  final a = _units[from];
  final b = _units[to];
  if (a == null) req.badRequest("Unknown unit '$from'");
  if (b == null) req.badRequest("Unknown unit '$to'");
  if (a.$1 == b.$1) return q * a.$2 / b.$2;
  if (a.$1 == 'count' || b.$1 == 'count') {
    req.badRequest(
      "Cannot convert '$from' to '$to': incompatible unit families (${a.$1} vs ${b.$1})",
    );
  }
  req.badRequest(
    "Cannot convert '$from' to '$to': set a density (g/ml) on the ingredient to convert between weight and volume.",
  );
}

void _validateMatches(
  MockRequest req,
  MockDb db,
  String org,
  String? cat,
  String? item,
) {
  if (cat != null && db[MenuTables.categories].find(cat)?['org_id'] != org) {
    req.badRequest('match_category_id is not a menu category of this organization');
  }
  if (item != null) {
    final m = db[MenuTables.menuItems].find(item);
    if (m == null || m['org_id'] != org || m['deleted_at'] != null) {
      req.badRequest('match_item_id is not a menu item of this organization');
    }
  }
}

/// `PackagingRuleOut`: the lines named, by sort then name.
Map<String, Object?> _ruleOut(CatalogMenuData data, MockRow r) {
  final lines = [
    for (final l in (r['lines'] as List).cast<Map<String, Object?>>())
      {...l, 'ingredient_name': data.ingredientName(l['ingredient_id'] as String)},
  ]
    ..sort((a, b) {
      final s = ((a['sort'] as int?) ?? 0) - ((b['sort'] as int?) ?? 0);
      return s != 0 ? s : compareJson(a['ingredient_name'], b['ingredient_name']);
    });
  return {
    'id': r['id'],
    'org_id': r['org_id'],
    'name': r['name'],
    'match_category_id': r['match_category_id'],
    'match_size_label': r['match_size_label'],
    'match_item_id': r['match_item_id'],
    'sort': r['sort'] ?? 0,
    'is_active': r['is_active'],
    'lines': lines,
    'created_at': r['created_at'],
    'updated_at': r['updated_at'],
  };
}
