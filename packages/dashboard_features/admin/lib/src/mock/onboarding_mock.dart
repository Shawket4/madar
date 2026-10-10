/// `/onboarding` (ADM-ONB rows): the checklist and its completion, plus every
/// endpoint the wizard's inline editors call.
///
/// Own routes (the backend's `orgs/onboarding.rs`):
/// - `GET /orgs/{id}/onboarding` — derived on every read from the org's data
///   (logo, branches, active payment methods, categories, live active items,
///   ingredients, items with a recipe, active add-ons, non-owner users,
///   orders), as `load_status` counts them; `org.settings.read` + same org.
/// - `POST /orgs/{id}/onboarding/complete` — `org.settings.edit` + same org;
///   409 "Onboarding cannot be completed: required steps missing (…)" until
///   every required step is done; idempotent once completed. The decision is
///   stored in [onboardingTable]; an org without a row keeps the core seed's
///   (Sabah Coffee finished its checklist long ago).
///
/// The editors' endpoints are FALLBACKS, registered only when no area before
/// this one answers them (in the full app the menu, inventory and setup areas
/// own them; the admin area registers last): categories, menu items with
/// their sizes / recipes / add-on groups / image, add-ons, choice groups and
/// their options, the ingredient catalog and its categories, and payment
/// methods. They gate, validate and persist like the backend handlers
/// (`menu/handlers.rs`, `menu/studio.rs`, `menu/modifiers.rs`,
/// `inventory/handlers.rs`, `payment_methods/handlers.rs`,
/// `uploads/handlers.rs`), over the same table names the other areas use.
library;

import 'dart:convert';

import 'package:dashboard_api/mock.dart';

/// The stored completion decisions: `{id: orgId, completed_at}`.
const String onboardingTable = 'org_onboarding';

/// The tables the checklist counts (shared names with the other areas).
abstract final class OnbTables {
  static const String categories = 'categories';
  static const String menuItems = 'menu_items';
  static const String sizes = 'item_sizes';
  static const String recipeLines = 'size_recipe_lines';
  static const String groups = 'modifier_groups';
  static const String groupLinks = 'item_group_links';
  static const String ingredients = 'org_ingredients';
  static const String ingredientCategories = 'ingredient_categories';
  static const String paymentMethods = 'payment_methods';
}

const String _oneSize = 'one_size';
const Set<String> _units = {'g', 'kg', 'ml', 'l', 'pcs'};

/// The checklist of [orgId] as `load_status` derives it (the
/// `OnboardingStatus` JSON).
Map<String, Object?> onboardingStatus(MockDb db, String orgId) {
  final org = db['orgs'].get(orgId, what: 'Organization not found');
  bool mine(MockRow r) => r['org_id'] == orgId;
  int count(String table, bool Function(MockRow r) test) =>
      db.hasTable(table) ? db[table].rows.where(test).length : 0;

  final branchIds = {
    for (final b in db['branches'].rows)
      if (mine(b)) b['id'],
  };
  final logo = org['logo_url'] != null ? 1 : 0;
  final methods = count(
    OnbTables.paymentMethods,
    (r) => mine(r) && r['is_active'] == true,
  );
  final categories = count(OnbTables.categories, mine);
  final liveItems = {
    for (final i in db[OnbTables.menuItems].rows)
      if (mine(i) && i['deleted_at'] == null && i['is_active'] == true) i['id'],
  };
  final ingredients = count(OnbTables.ingredients, mine);
  final withRecipes = db.hasTable(OnbTables.recipeLines)
      ? {
          for (final l in db[OnbTables.recipeLines].rows)
            if (liveItems.contains(l['menu_item_id'])) l['menu_item_id'],
        }.length
      : 0;
  final addons = [
    for (final a in addonItemRows(db))
      if (mine(a) && a['is_active'] == true) a,
  ].length;
  final team = count('users', (u) => mine(u) && u['role'] != 'org_admin');
  final orders = db['orders'].rows
      .where((o) => branchIds.contains(o['branch_id']))
      .length;

  Map<String, Object?> step(String key, int n, {bool required = false}) => {
    'key': key,
    'done': n > 0,
    'count': n,
    'required': required,
  };
  final steps = [
    step('org_profile', logo),
    step('branch', branchIds.length, required: true),
    step('payment_methods', methods, required: true),
    step('categories', categories, required: true),
    step('menu_items', liveItems.length, required: true),
    step('ingredients', ingredients),
    step('recipes', withRecipes),
    step('addons', addons),
    step('team', team),
    step('first_order', orders),
  ];
  final decided = db[onboardingTable].find(orgId);
  final completedAt = decided != null
      ? decided['completed_at']
      : MockSeed.instance.onboarding(orgId).completedAt?.toIso8601String();
  return {
    'org_id': orgId,
    'completed': completedAt != null,
    'completed_at': completedAt,
    'can_complete': steps
        .where((s) => s['required'] == true)
        .every((s) => s['done'] == true),
    'recipe_coverage': liveItems.isEmpty ? 0.0 : withRecipes / liveItems.length,
    'steps': steps,
  };
}

/// The add-on view: every option of a shared group (one with a legacy type),
/// as `AddonItem` rows, by type then position.
List<MockRow> addonItemRows(MockDb db) {
  final out = <(String, int, MockRow)>[];
  for (final g in db[OnbTables.groups].rows) {
    final type = g['legacy_addon_type'] as String?;
    if (type == null) continue;
    for (final (n, o) in _options(g).indexed) {
      out.add((
        type,
        n,
        {
          'id': o['id'],
          'org_id': g['org_id'],
          'name': o['name'],
          'name_translations':
              o['name_translations'] ?? const <String, Object?>{},
          'addon_type': type,
          'default_price': o['price'],
          'is_active': o['is_active'],
          'created_at': g['created_at'] ?? '2026-01-10T09:00:00.000Z',
          'updated_at': g['updated_at'] ?? '2026-01-10T09:00:00.000Z',
        },
      ));
    }
  }
  out.sort((a, b) {
    final c = a.$1.compareTo(b.$1);
    return c != 0 ? c : a.$2 - b.$2;
  });
  return [for (final e in out) e.$3];
}

List<Map<String, Object?>> _options(MockRow g) =>
    ((g['options'] as List?) ?? const []).cast<Map<String, Object?>>();

void registerOnboardingMocks(MockServer server, MockDb db) {
  // GET /orgs/{id}/onboarding (`get_onboarding`).
  server.on('GET', '/orgs/{id}/onboarding', (req) {
    req.requireCap('org.settings.read');
    final id = req.param('id');
    req.requireSameOrg(id);
    return MockResponse.ok(onboardingStatus(db, id));
  });

  // POST /orgs/{id}/onboarding/complete (`complete_onboarding`).
  server.on('POST', '/orgs/{id}/onboarding/complete', (req) {
    req.requireCap('org.settings.edit');
    final id = req.param('id');
    req.requireSameOrg(id);
    final status = onboardingStatus(db, id);
    if (status['completed'] == true) return MockResponse.ok(status);
    if (status['can_complete'] != true) {
      final missing = [
        for (final s in (status['steps']! as List).cast<Map<String, Object?>>())
          if (s['required'] == true && s['done'] != true) s['key'],
      ];
      req.conflict(
        'Onboarding cannot be completed: required steps missing '
        '(${missing.join(', ')})',
      );
    }
    db[onboardingTable].put({'id': id, 'completed_at': db.nowIso});
    return MockResponse.ok(onboardingStatus(db, id));
  });

  _registerEditorFallbacks(server, db);
}

// ── the editors' endpoints (fallbacks) ───────────────────────────────────

void _registerEditorFallbacks(MockServer server, MockDb db) {
  void fallback(String method, String template, MockHandler handler) {
    if (!server.handles(method, template)) server.on(method, template, handler);
  }

  final b = _MenuBackend(db);

  // ── payment methods (`payment_methods/handlers.rs`) ───────────────────
  fallback('POST', '/payment-methods', (req) {
    req.requireCap('payment_methods.create');
    final org = req.orgId;
    if (org == null) req.fail(MockResponse.forbidden('No org id'));
    final body = req.json;
    final name = body['name'];
    if (name is! String) {
      req.badRequest('Json deserialize error: missing field `name`');
    }
    final methods = db[OnbTables.paymentMethods];
    if (methods.rows.any((m) => m['org_id'] == org && m['name'] == name)) {
      req.conflict(
        'A payment method with this name already exists for the organization',
      );
    }
    final row = methods.insert({
      'org_id': org,
      'name': name,
      'label_translations':
          body['label_translations'] ?? const <String, Object?>{},
      'color': body['color'],
      'icon': body['icon'],
      'is_cash': body['is_cash'] ?? false,
      'is_active': body['is_active'] ?? true,
      'visible_in_integrations': body['visible_in_integrations'] ?? true,
    });
    return MockResponse.created(row);
  });

  // ── categories (`menu/handlers.rs`) ───────────────────────────────────
  fallback('GET', '/categories', (req) {
    req.requireCap('menu.categories.read');
    final org = req.q('org_id');
    if (org == null) {
      req.badRequest('Query deserialize error: missing field `org_id`');
    }
    req.requireSameOrg(org);
    final rows =
        db[OnbTables.categories].query(
          filters: {'org_id': org},
          where: (c) => c['deleted_at'] == null,
        )..sort((a, b) {
          final c =
              ((a['display_order'] as int?) ?? 0) -
              ((b['display_order'] as int?) ?? 0);
          return c != 0 ? c : compareJson(a['name'], b['name']);
        });
    return MockResponse.ok(rows);
  });

  fallback('POST', '/categories', (req) {
    req.requireCap('menu.categories.create');
    final body = req.json;
    final org = body['org_id'] as String?;
    req.requireSameOrg(org);
    final name = body['name'];
    if (name is! String) {
      req.badRequest('Json deserialize error: missing field `name`');
    }
    final mine = db[OnbTables.categories].where(
      (c) => c['org_id'] == org && c['deleted_at'] == null,
    );
    final next = mine.isEmpty
        ? 0
        : mine
                  .map((c) => (c['display_order'] as int?) ?? 0)
                  .reduce((a, b) => a > b ? a : b) +
              1;
    final row = db[OnbTables.categories].insert({
      'org_id': org,
      'name': name,
      'name_translations': {
        ...?(body['name_translations'] as Map?)?.cast<String, Object?>(),
        'en': name,
      },
      'image_url': body['image_url'],
      'is_active': true,
      'display_order': next,
      'deleted_at': null,
    });
    return MockResponse.created(row);
  });

  // ── menu items (`menu/handlers.rs`, `menu/studio.rs`) ─────────────────
  fallback('GET', '/menu-items', (req) {
    req.requireCap('menu.items.read');
    final org = req.q('org_id');
    if (org == null) {
      req.badRequest('Query deserialize error: missing field `org_id`');
    }
    req.requireSameOrg(org);
    return MockResponse.ok(
      db[OnbTables.menuItems].query(
        filters: {'org_id': org, 'category_id': req.q('category_id')},
        where: (i) => i['deleted_at'] == null,
        sort: 'name',
      ),
    );
  });

  fallback('GET', '/menu-items/{id}', (req) {
    req.requireCap('menu.items.read');
    final item = b.item(req.param('id'));
    req.requireSameOrg(item['org_id'] as String?);
    return MockResponse.ok(b.full(item));
  });

  fallback('POST', '/menu-items', (req) {
    req.requireCap('menu.items.create');
    final body = req.json;
    final org = body['org_id'] as String?;
    req.requireSameOrg(org);
    final name = body['name'];
    final price = body['base_price'];
    if (name is! String) {
      req.badRequest('Json deserialize error: missing field `name`');
    }
    if (price is! num) {
      req.badRequest('Json deserialize error: missing field `base_price`');
    }
    final category = db[OnbTables.categories].find('${body['category_id']}');
    if (category == null || category['org_id'] != org) {
      req.badRequest('Category not found in this organization');
    }
    final item = db[OnbTables.menuItems].insert({
      'org_id': org,
      'category_id': category['id'],
      'name': name,
      'name_translations': {
        ...?(body['name_translations'] as Map?)?.cast<String, Object?>(),
        'en': name,
      },
      'description': body['description'],
      'description_translations':
          body['description_translations'] ?? const <String, Object?>{},
      'image_url': body['image_url'],
      'base_price': price.toInt(),
      'is_active': true,
      'deleted_at': null,
      'kind': 'item',
    });
    // Born with a `one_size` row carrying its price (schema trigger).
    b.sizesOf(item);
    return MockResponse.created(b.full(item));
  });

  fallback('PATCH', '/menu-items/{id}', (req) {
    req.requireCap('menu.items.edit');
    final item = b.item(req.param('id'));
    req.requireSameOrg(item['org_id'] as String?);
    final body = req.json;
    final category = body['category_id'];
    if (category != null) {
      final c = db[OnbTables.categories].find('$category');
      if (c == null || c['org_id'] != item['org_id']) {
        req.badRequest('Category not found in this organization');
      }
    }
    for (final k in const [
      'category_id',
      'name',
      'description',
      'base_price',
      'is_active',
    ]) {
      if (body[k] != null) item[k] = body[k];
    }
    for (final k in const ['name_translations', 'description_translations']) {
      final tr = body[k];
      if (tr is Map) {
        item[k] = {
          ...?(item[k] as Map?)?.cast<String, Object?>(),
          ...tr.cast<String, Object?>(),
        };
      }
    }
    if (body.containsKey('image_url')) item['image_url'] = body['image_url'];
    item['updated_at'] = db.nowIso;
    return MockResponse.ok(item);
  });

  fallback('PUT', '/menu-items/{id}/sizes', (req) {
    req.requireCap('menu.items.edit');
    final item = b.item(req.param('id'));
    req.requireSameOrg(item['org_id'] as String?);
    final raw = req.json['sizes'];
    if (raw is! List) {
      req.badRequest('Json deserialize error: missing field `sizes`');
    }
    final incoming = raw.cast<Map<String, Object?>>();
    if (!incoming.any((s) => s['is_active'] != false)) {
      req.badRequest(
        'A menu item must keep at least one active size — that is where '
        'its price lives.',
      );
    }
    final seen = <Object?>{};
    for (final s in incoming) {
      if (!seen.add(s['label'])) {
        req.badRequest("Duplicate size label '${s['label']}' in request");
      }
    }
    b.putSizes(item, incoming);
    return MockResponse.ok(b.studio(item));
  });

  fallback('PUT', '/menu-item-sizes/{size_id}/recipe', (req) {
    req.requireCap('menu.items.edit');
    final size = db[OnbTables.sizes].find(req.param('size_id'));
    final item = size == null
        ? null
        : db[OnbTables.menuItems].find('${size['menu_item_id']}');
    if (size == null || item == null || item['deleted_at'] != null) {
      req.notFound('Size not found');
    }
    req.requireSameOrg(item['org_id'] as String?);
    final raw = req.json['lines'];
    if (raw is! List) {
      req.badRequest('Json deserialize error: missing field `lines`');
    }
    return MockResponse.ok(
      b.putSizeRecipe(item, size, raw.cast<Map<String, Object?>>()),
    );
  });

  fallback('PUT', '/menu-items/{id}/modifier-groups', (req) {
    req.requireCap('menu.items.edit');
    final item = b.item(req.param('id'));
    req.requireSameOrg(item['org_id'] as String?);
    final raw = req.json['groups'];
    if (raw is List) b.putAttachments(item, raw.cast<Map<String, Object?>>());
    return MockResponse.ok(b.studio(item));
  });

  fallback('POST', '/uploads/menu-items/{menu_item_id}', (req) {
    req.requireCap('menu.items.edit');
    final item = db[OnbTables.menuItems].find(req.param('menu_item_id'));
    if (item == null || item['deleted_at'] != null) {
      req.notFound('Menu item not found');
    }
    req.requireSameOrg(item['org_id'] as String?);
    final file = req.file('image');
    if (file == null) req.badRequest("No image file received in field 'image'");
    // The asset worker finishes at once: the picture itself, as a data URI.
    final url =
        'data:${file.contentType ?? 'image/png'};base64,'
        '${base64Encode(file.bytes)}';
    item
      ..['image_url'] = url
      ..['updated_at'] = db.nowIso;
    return MockResponse.ok({
      'asset_job_id': db.newId('asset_jobs'),
      'image_url': url,
      'status': 'processing',
    });
  });

  // ── add-ons and choice groups (`menu/modifiers.rs`) ───────────────────
  fallback('GET', '/addon-items', (req) {
    req.requireCap('menu.items.read');
    final org = req.q('org_id');
    req.requireSameOrg(org);
    return MockResponse.ok([
      for (final a in addonItemRows(db))
        if (a['org_id'] == org) a,
    ]);
  });

  fallback('GET', '/modifier-groups', (req) {
    req.requireCap('menu.items.read');
    final org = req.q('org_id');
    req.requireSameOrg(org);
    final all = req.qBool('include_inactive') ?? false;
    final rows =
        db[OnbTables.groups].query(
          filters: {'org_id': org},
          where: (g) => all || g['is_active'] == true,
        )..sort((a, b) {
          final c = ((a['sort'] as int?) ?? 0) - ((b['sort'] as int?) ?? 0);
          return c != 0 ? c : compareJson(a['name'], b['name']);
        });
    return MockResponse.ok(rows);
  });

  fallback('POST', '/modifier-groups', (req) {
    req.requireCap('menu.items.edit');
    final org = req.orgId;
    if (org == null) {
      req.fail(
        MockResponse.forbidden('A super admin must scope this to an org'),
      );
    }
    return MockResponse.created(b.createGroup(req, org));
  });

  fallback('PATCH', '/modifier-groups/{gid}', (req) {
    req.requireCap('menu.items.edit');
    final g = b.group(req.param('gid'));
    req.requireSameOrg(g['org_id'] as String?);
    final body = req.json;
    for (final k in const [
      'name',
      'name_translations',
      'selection_type',
      'min_selections',
      'is_required',
      'sort',
      'is_active',
    ]) {
      if (body[k] != null) g[k] = body[k];
    }
    if (body.containsKey('max_selections')) {
      g['max_selections'] = body['max_selections'];
    }
    return MockResponse.ok(g);
  });

  fallback('POST', '/modifier-groups/{gid}/options', (req) {
    req.requireCap('menu.items.edit');
    final g = b.group(req.param('gid'));
    req.requireSameOrg(g['org_id'] as String?);
    return MockResponse.created(b.createOption(req, g));
  });

  fallback('PATCH', '/modifier-options/{oid}', (req) {
    req.requireCap('menu.items.edit');
    final (g, o) = b.option(req.param('oid'));
    req.requireSameOrg(g['org_id'] as String?);
    final body = req.json;
    final swaps = body['replaces_ingredient_id'];
    if (swaps != null) b.checkIngredient(g['org_id'] as String, swaps);
    for (final k in const [
      'name',
      'name_translations',
      'is_default',
      'is_active',
      'price',
      'sort',
    ]) {
      if (body[k] != null) o[k] = body[k];
    }
    if (body.containsKey('replaces_ingredient_id')) {
      o['replaces_ingredient_id'] = swaps;
    }
    b.sortOptions(g);
    return MockResponse.ok(o);
  });

  fallback('PUT', '/modifier-options/{oid}/recipe', (req) {
    req.requireCap('menu.items.edit');
    final (g, o) = b.option(req.param('oid'));
    req.requireSameOrg(g['org_id'] as String?);
    return MockResponse.ok(b.putOptionRecipe(req, g, o));
  });

  // ── the ingredient catalog (`inventory/handlers.rs`) ──────────────────
  fallback('GET', '/inventory/orgs/{org_id}/catalog', (req) {
    req.requireCap('inventory.read');
    final org = req.param('org_id');
    req.requireSameOrg(org);
    return MockResponse.ok(
      db[OnbTables.ingredients].query(
        filters: {'org_id': org},
        where: (i) => i['deleted_at'] == null,
        sort: 'name',
      ),
    );
  });

  fallback('GET', '/inventory/orgs/{org_id}/categories', (req) {
    req.requireCap('inventory.read');
    final org = req.param('org_id');
    req.requireSameOrg(org);
    b.generalCategory(org);
    final ingredients = db[OnbTables.ingredients].rows;
    return MockResponse.ok([
      for (final c in db[OnbTables.ingredientCategories].query(
        filters: {'org_id': org},
        sort: 'sort_order',
      ))
        {
          ...c,
          'ingredient_count': ingredients
              .where((i) => i['category_id'] == c['id'])
              .length,
        },
    ]);
  });

  fallback('POST', '/inventory/orgs/{org_id}/catalog', (req) {
    req.requireCap('inventory.items.create');
    final org = req.param('org_id');
    req.requireSameOrg(org);
    final body = req.json;
    final unit = body['unit'];
    if (unit is! String || !_units.contains(unit)) {
      req.badRequest('Unit must be one of: g, kg, ml, l, pcs');
    }
    final name = ((body['name'] as String?) ?? '').trim();
    if (name.isEmpty) req.badRequest('name cannot be empty');
    final categoryId = body['category_id'] as String?;
    final MockRow category;
    if (categoryId != null) {
      final found = db[OnbTables.ingredientCategories].find(categoryId);
      if (found == null || found['org_id'] != org) {
        req.badRequest('Category does not belong to this organization');
      }
      category = found;
    } else {
      category = b.generalCategory(org);
    }
    final ingredients = db[OnbTables.ingredients];
    if (ingredients.rows.any(
      (i) => i['org_id'] == org && i['name'] == name && i['deleted_at'] == null,
    )) {
      req.conflict(
        'An ingredient with this name already exists in the catalog',
      );
    }
    final cost = body['cost_per_unit'];
    final row = ingredients.insert({
      'org_id': org,
      'name': name,
      'category_id': category['id'],
      'category_name': category['name'],
      'category_slug': category['slug'],
      'unit': unit,
      'cost_per_unit': cost is num ? cost.toDouble() : null,
      'is_active': true,
      'deleted_at': null,
    });
    return MockResponse.created(row);
  });
}

/// The menu side of the backend the editors write through.
class _MenuBackend {
  _MenuBackend(this.db);

  final MockDb db;
  int _revision = 1;

  static Never _bad(String reason) =>
      throw MockHttpError(MockResponse.badRequest(reason));

  MockRow item(String id) {
    final row = db[OnbTables.menuItems].find(id);
    if (row == null || row['deleted_at'] != null) {
      throw MockHttpError(MockResponse.notFound('Menu item not found'));
    }
    return row;
  }

  MockRow group(String gid) =>
      db[OnbTables.groups].find(gid) ??
      (throw MockHttpError(MockResponse.notFound('Modifier group not found')));

  (MockRow, Map<String, Object?>) option(String oid) {
    for (final g in db[OnbTables.groups].rows) {
      for (final o in _options(g)) {
        if (o['id'] == oid) return (g, o);
      }
    }
    throw MockHttpError(MockResponse.notFound('Modifier option not found'));
  }

  /// The org's `general` ingredient category, made on first need (every
  /// org has one from birth).
  MockRow generalCategory(String org) {
    final cats = db[OnbTables.ingredientCategories];
    return cats.firstWhere(
          (c) => c['org_id'] == org && c['slug'] == 'general',
        ) ??
        cats.insert({
          'org_id': org,
          'name': 'General',
          'slug': 'general',
          'sort_order': 0,
          'is_packaging': false,
          'ingredient_count': 0,
        });
  }

  void checkIngredient(String org, Object? id) {
    final ing = db[OnbTables.ingredients].find('$id');
    if (ing == null || ing['org_id'] != org || ing['deleted_at'] != null) {
      _bad("Ingredient not found in this organization's catalog");
    }
  }

  /// The item's size rows; an item with none gets its `one_size` row from
  /// its base price (every item always has one).
  List<MockRow> sizesOf(MockRow item) {
    final table = db[OnbTables.sizes];
    final mine = table.where((s) => s['menu_item_id'] == item['id']);
    if (mine.isNotEmpty) {
      return mine..sort(
        (a, b) => ((a['sort'] as int?) ?? 0) - ((b['sort'] as int?) ?? 0),
      );
    }
    return [
      table.insert({
        'menu_item_id': item['id'],
        'label': _oneSize,
        'price_override': item['base_price'],
        'is_active': true,
        'sort': 0,
      }, timestamps: false),
    ];
  }

  void putSizes(MockRow item, List<Map<String, Object?>> incoming) {
    final table = db[OnbTables.sizes];
    final existing = sizesOf(item);
    final labels = {for (final s in incoming) s['label']};
    for (final s in incoming) {
      final row = existing.where((e) => e['label'] == s['label']).firstOrNull;
      final fields = {
        'price_override': (s['price']! as num).toInt(),
        'sort': (s['sort'] as num?)?.toInt() ?? 0,
        'is_active': s['is_active'] ?? true,
      };
      if (row != null) {
        row.addAll(fields);
      } else {
        table.insert({
          'menu_item_id': item['id'],
          'label': s['label'],
          ...fields,
        }, timestamps: false);
      }
    }
    // A dropped size is removed with its recipe; one the seed's orders sold
    // is only switched off (order history keeps naming it).
    final sold = MockSeed.instance.menuItems.any((m) => m.id == item['id']);
    for (final e in existing) {
      if (labels.contains(e['label'])) continue;
      if (sold) {
        e['is_active'] = false;
      } else {
        table.delete(e['id']! as String);
        db[OnbTables.recipeLines].removeWhere((l) => l['size_id'] == e['id']);
      }
    }
    // The item's own price mirrors its cheapest active size.
    final prices = [
      for (final s in sizesOf(item))
        if (s['is_active'] == true) s['price_override']! as int,
    ];
    if (prices.isNotEmpty) {
      item['base_price'] = prices.reduce((a, b) => a < b ? a : b);
    }
    _revision++;
  }

  static const Map<String, double> _factor = {
    'g': 1,
    'kg': 1000,
    'ml': 1,
    'l': 1000,
    'pcs': 1,
  };
  static const Map<String, String> _family = {
    'g': 'mass',
    'kg': 'mass',
    'ml': 'volume',
    'l': 'volume',
    'pcs': 'count',
  };

  /// A quantity in [from] as the ingredient's [base] unit, or 400.
  static double _toBase(double qty, String from, String base) {
    if (_family[from] == null || _family[from] != _family[base]) {
      _bad('cannot convert $from to $base');
    }
    final q = ((qty * _factor[from]! / _factor[base]!) * 1000).round() / 1000;
    if (qty > 0 && q <= 0) {
      _bad(
        'quantity $qty $from is too small for base unit $base (rounds to 0)',
      );
    }
    return q;
  }

  static String _qtyText(double q) =>
      q == q.truncateToDouble() ? q.toInt().toString() : q.toString();

  Map<String, Object?> putSizeRecipe(
    MockRow item,
    MockRow size,
    List<Map<String, Object?>> lines,
  ) {
    final org = item['org_id'] as String;
    final seen = <Object?>{};
    for (final l in lines) {
      if (!seen.add(l['ingredient_id'])) _bad('Duplicate ingredient in recipe');
    }
    final normalized = <MockRow>[];
    for (final (n, l) in lines.indexed) {
      final id = l['ingredient_id'];
      final ing = db[OnbTables.ingredients].find('$id');
      if (ing == null || ing['org_id'] != org || ing['deleted_at'] != null) {
        _bad("Linked ingredient not found in this organization's catalog");
      }
      final base = ing['unit'] as String;
      final q = _toBase(
        (l['quantity']! as num).toDouble(),
        '${l['unit']}',
        base,
      );
      normalized.add({
        'id': db.newId(OnbTables.recipeLines),
        'size_id': size['id'],
        'menu_item_id': item['id'],
        'ingredient_id': id,
        'quantity': _qtyText(q),
        'unit': base,
        'source': 'own',
        'sort': n,
      });
    }
    db[OnbTables.recipeLines]
      ..removeWhere((l) => l['size_id'] == size['id'])
      ..insertAll(normalized);
    _revision++;
    final out = _recipeOut(size);
    return {
      'size_id': size['id'],
      'recipe': out.lines,
      'cost_piastres': out.cost,
      'cost_incomplete': out.incomplete,
      'catalog_revision': _revision,
    };
  }

  ({List<Map<String, Object?>> lines, int? cost, bool incomplete}) _recipeOut(
    MockRow size,
  ) {
    var sum = 0.0;
    var incomplete = false;
    final lines = <Map<String, Object?>>[];
    for (final l in db[OnbTables.recipeLines].rows) {
      if (l['size_id'] != size['id']) continue;
      final ing = db[OnbTables.ingredients].find('${l['ingredient_id']}');
      final cost = (ing?['cost_per_unit'] as num?)?.toDouble();
      final qty = double.parse('${l['quantity']}');
      final line = cost == null ? null : (cost * qty).round();
      if (line == null) {
        incomplete = true;
      } else {
        sum += line;
      }
      lines.add({
        'id': l['id'],
        'ingredient_id': l['ingredient_id'],
        'ingredient_name': ing?['name'] ?? '',
        'quantity': l['quantity'],
        'unit': l['unit'],
        'line_cost_piastres': line,
        'size_label': null,
        'source': l['source'] ?? 'own',
      });
    }
    return (
      lines: lines,
      cost: lines.isEmpty || incomplete ? null : sum.round(),
      incomplete: incomplete,
    );
  }

  /// `PUT /menu-items/{id}/modifier-groups`: the item's whole set of shared
  /// groups.
  void putAttachments(MockRow item, List<Map<String, Object?>> attaches) {
    final seen = <Object?>{};
    for (final a in attaches) {
      if (!seen.add(a['group_id'])) _bad('Duplicate group in attach-set');
      final g = db[OnbTables.groups].find('${a['group_id']}');
      if (g == null || g['org_id'] != item['org_id']) {
        _bad('One or more modifier groups do not exist in this organization');
      }
    }
    final links = db[OnbTables.groupLinks]
      ..removeWhere((l) => l['menu_item_id'] == item['id']);
    for (final (n, a) in attaches.indexed) {
      links.insert({
        'menu_item_id': item['id'],
        'group_id': a['group_id'],
        'sort': (a['sort'] as num?)?.toInt() ?? n,
        'included_option_ids': a['included_option_ids'],
      }, timestamps: false);
    }
    _revision++;
  }

  /// The add-on ids the item offers: each shared group it is attached to,
  /// narrowed to the attachment's picks when it has some.
  List<String> allowedAddonIds(MockRow item) => [
    for (final l in db[OnbTables.groupLinks].rows)
      if (l['menu_item_id'] == item['id'])
        if (db[OnbTables.groups].find('${l['group_id']}') case final g?
            when g['legacy_addon_type'] != null)
          for (final o in _options(g))
            if ((l['included_option_ids'] as List?)?.contains(o['id']) ?? true)
              o['id']! as String,
  ];

  /// `MenuItemFull`: the item, its sizes, recipes and add-ons.
  Map<String, Object?> full(MockRow item) {
    final sizes = sizesOf(item);
    final ingredients = db[OnbTables.ingredients];
    Map<String, Object?> sizeJson(MockRow s) => {
      'id': s['id'],
      'menu_item_id': item['id'],
      'label': s['label'],
      'price_override': s['price_override'],
      'is_active': s['is_active'],
    };
    return {
      ...item,
      'sizes': [
        for (final s in sizes)
          if (s['label'] != _oneSize) sizeJson(s),
      ],
      'all_sizes': [for (final s in sizes) sizeJson(s)],
      'addon_slots': const <Object?>[],
      'optional_fields': const <Object?>[],
      'recipes': [
        for (final s in sizes)
          for (final l in db[OnbTables.recipeLines].rows)
            if (l['size_id'] == s['id'])
              {
                'size_label': s['label'],
                'org_ingredient_id': l['ingredient_id'],
                'ingredient_name':
                    ingredients.find('${l['ingredient_id']}')?['name'] ?? '',
                'ingredient_unit': l['unit'],
                'quantity_used': double.parse('${l['quantity']}'),
                'category':
                    ingredients.find(
                      '${l['ingredient_id']}',
                    )?['category_slug'] ??
                    'general',
              },
      ],
      'recipe_steps': const <Object?>[],
      'allowed_addon_ids': allowedAddonIds(item),
    };
  }

  /// `StudioAggregate` (what the size, recipe and group writes answer).
  Map<String, Object?> studio(MockRow item) => {
    'id': item['id'],
    'org_id': item['org_id'],
    'category_id': item['category_id'],
    'name': item['name'],
    'name_translations': item['name_translations'] ?? const {},
    'description': item['description'],
    'image_url': item['image_url'],
    'is_active': item['is_active'],
    'availability': {
      'branches': const <Object?>[],
      'org_active': item['is_active'],
    },
    'catalog_revision': _revision,
    'modifier_groups': const <Object?>[],
    'options': const <Object?>[],
    'recipe_steps': const <Object?>[],
    'sizes': [
      for (final s in sizesOf(item))
        if (s['is_active'] == true)
          () {
            final r = _recipeOut(s);
            return {
              'id': s['id'],
              'label': s['label'],
              'price': s['price_override'],
              'sort': s['sort'] ?? 0,
              'is_active': true,
              'recipe': r.lines,
              'cost_piastres': r.cost,
              'cost_incomplete': r.incomplete,
            };
          }(),
    ],
  };

  // ── groups and options ────────────────────────────────────────────────

  void sortOptions(MockRow g) {
    g['options'] = _options(g)
      ..sort((a, b) {
        final c = ((a['sort'] as int?) ?? 0) - ((b['sort'] as int?) ?? 0);
        return c != 0 ? c : compareJson(a['name'], b['name']);
      });
  }

  Map<String, Object?> createGroup(MockRequest req, String org) {
    final body = req.json;
    final name = body['name'];
    final selection = body['selection_type'];
    if (name is! String) _bad('Json deserialize error: missing field `name`');
    if (selection != 'single' && selection != 'multi') {
      _bad("selection_type must be 'single' or 'multi'");
    }
    final effect = (body['effect'] as String?) ?? 'adds';
    if (!const ['none', 'adds', 'swaps'].contains(effect)) {
      _bad("effect must be 'none', 'adds' or 'swaps'");
    }
    final cat = body['swap_category_id'] as String?;
    if (effect == 'swaps' && cat == null) {
      _bad("effect 'swaps' needs swap_category_id");
    }
    if (effect != 'swaps' && cat != null) {
      _bad("swap_category_id is only valid with effect 'swaps'");
    }
    String? slug;
    if (cat != null) {
      final c = db[OnbTables.ingredientCategories].find(cat);
      if (c == null || c['org_id'] != org) {
        _bad('Swap category not found in this organization');
      }
      slug = c['slug'] as String?;
    }
    // `derive_legacy_addon_type`: a swap of milk / beans is that family;
    // any other swap is an extra; otherwise what was asked for.
    final type = effect == 'swaps'
        ? switch (slug) {
            'milk' => 'milk_type',
            'coffee_bean' => 'coffee_type',
            _ => 'extra',
          }
        : body['legacy_addon_type'] as String?;
    final swapShape = effect == 'swaps';
    return db[OnbTables.groups].insert({
      'org_id': org,
      'name': name,
      'name_translations':
          body['name_translations'] ?? const <String, Object?>{},
      'selection_type': swapShape ? 'single' : selection,
      'min_selections': swapShape
          ? ((body['min_selections'] as num?)?.toInt() ?? 0).clamp(0, 1)
          : (body['min_selections'] as num?)?.toInt() ?? 0,
      'max_selections': swapShape
          ? 1
          : (body['max_selections'] as num?)?.toInt(),
      'is_required': body['is_required'] as bool? ?? false,
      'sort': (body['sort'] as num?)?.toInt() ?? 0,
      'is_active': true,
      'legacy_addon_type': type,
      'effect': effect,
      'swap_category_id': cat,
      'swap_category_slug': slug,
      'is_item_options': false,
      'options': <Map<String, Object?>>[],
    }, timestamps: false);
  }

  Map<String, Object?> createOption(MockRequest req, MockRow g) {
    final body = req.json;
    final name = body['name'];
    final price = body['price'];
    if (name is! String) _bad('Json deserialize error: missing field `name`');
    if (price is! num) _bad('Json deserialize error: missing field `price`');
    final swaps = body['replaces_ingredient_id'];
    if (swaps != null) checkIngredient(g['org_id'] as String, swaps);
    final o = <String, Object?>{
      'id': db.newId('modifier_options'),
      'name': name,
      'name_translations':
          body['name_translations'] ?? const <String, Object?>{},
      'price': price.toInt(),
      'is_default': body['is_default'] as bool? ?? false,
      'is_active': body['is_active'] as bool? ?? true,
      'sort': 0,
      'replaces_ingredient_id': swaps,
      'recipe': <Map<String, Object?>>[],
    };
    g['options'] = [..._options(g), o];
    sortOptions(g);
    return o;
  }

  List<Map<String, Object?>> putOptionRecipe(
    MockRequest req,
    MockRow g,
    Map<String, Object?> o,
  ) {
    final body = req.body;
    if (body is! List) _bad('Json deserialize error: expected a sequence');
    final org = g['org_id'] as String;
    final seen = <String>{};
    final lines = <Map<String, Object?>>[];
    for (final raw in body.cast<Map<String, Object?>>()) {
      final ingId = raw['ingredient_id'];
      final qty = raw['quantity'];
      final unit = raw['unit'];
      if (ingId is! String || qty is! num || unit is! String) {
        _bad('Json deserialize error: invalid recipe line');
      }
      final rawLabel = (raw['size_label'] as String?)?.trim();
      final label = rawLabel == null || rawLabel.isEmpty ? null : rawLabel;
      if (!seen.add('$ingId|$label')) {
        _bad('Duplicate ingredient in option recipe');
      }
      final ing = db[OnbTables.ingredients].find(ingId);
      if (ing == null || ing['org_id'] != org || ing['deleted_at'] != null) {
        _bad("Linked ingredient not found in this organization's catalog");
      }
      final base = ing['unit'] as String;
      lines.add({
        'ingredient_id': ingId,
        'ingredient_name': ing['name'],
        'quantity': _toBase(qty.toDouble(), unit, base),
        'unit': base,
        'size_label': label,
      });
    }
    o['recipe'] = lines;
    return [
      for (final l in lines)
        {
          'ingredient_id': l['ingredient_id'],
          'quantity': l['quantity'],
          'unit': l['unit'],
          'size_label': l['size_label'],
        },
    ];
  }
}
