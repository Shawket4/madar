/// Mock handlers of the `items` unit (the `/menu/items` page: the catalog,
/// add-ons and categories, their dialogs, paste rows, the export), the
/// backend's way (`MadarRust/src/menu/handlers.rs`, `menu/studio.rs`,
/// `menu/modifiers.rs`, `costing/handlers.rs`, `uploads/handlers.rs`).
///
/// Data lives in the area's tables ([MenuTables], [CatalogMenuData]) so every
/// unit's numbers agree.
///
/// | route | backend | gate |
/// |---|---|---|
/// | `GET /costing/catalog` | `list_menu_catalog` | `menu.items.read` (+ `recipes.read` with `has_recipe`), same org |
/// | `GET /costing/addon-items` | `list_addon_costs` | `orders.read`, same org |
/// | `GET /branch-menu-overrides`, `GET /branch-addon-overrides` | `list_branch_*_overrides` | `menu.items.read`, branch in scope |
/// | `PUT`/`DELETE /menu-price-overrides` | `put_price_override` / `delete_price_override` | `menu.items.edit`, claims org, shape, tenancy |
/// | `GET /menu-items/{id}` | `get_menu_item` | `menu.items.read`, same org |
/// | `POST /menu-items` | `create_menu_item` | `menu.items.create`, same org |
/// | `PATCH /menu-items/{id}` | `update_menu_item` | `menu.items.edit`, same org |
/// | `DELETE /menu-items/{id}` | `delete_menu_item` | `menu.items.delete` |
/// | `POST /menu-items/{id}/duplicate` | `duplicate_item` | `menu.items.edit`, same org |
/// | `POST /uploads/menu-items/{menu_item_id}` | `upload_menu_item_image` | `menu.items.edit`, org |
/// | `GET /assets/jobs/{id}` | `get_job` | the job's org |
/// | `POST /categories`, `PATCH`/`DELETE /categories/{id}`, `PUT /categories/order` | category handlers | `menu.categories.create` / `.edit` / `.delete` / `.edit`, same org |
///
/// The item dialog's other writes (`PUT /menu-items/{id}/sizes`,
/// `PUT /menu-item-sizes/{size_id}/recipe`, `PUT /menu-items/{id}/modifier-groups`)
/// and `GET /menu-items/{id}/studio` (the branch switch reads it) are the
/// studio unit's (`studio_mock.dart`).
///
/// Two places follow the web's intent over the backend's letter (see
/// `docs/fdash/divergences/catalog_menu-items.md`): the branch override
/// lists are derived from the unified override table the toggles write, and
/// `GET /menu-items/{id}` answers the item's current own recipe lines and
/// offered add-ons.
library;

import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';
import '../shared/menu_text.dart';

const String _read = 'menu.items.read';
const String _create = 'menu.items.create';
const String _edit = 'menu.items.edit';
const String _delete = 'menu.items.delete';

/// Upload jobs (`{id, org_id, item_id, polls, status, error}`).
const String assetJobsTable = 'asset_jobs';

void registerItemsMocks(MockServer server, MockDb db) {
  final b = ItemsBackend(db);

  // GET /costing/catalog: the org's live items by name, paged (per_page
  // 1..500, 50 by default; total_pages 0 when empty), each with its per-SKU
  // costs.
  server.on('GET', '/costing/catalog', (req) {
    req.requireCap(_read);
    final org = req.q('org_id');
    if (org == null) {
      req.badRequest('Query deserialize error: missing field `org_id`');
    }
    req.requireSameOrg(org);
    final hasRecipe = req.qBool('has_recipe');
    if (hasRecipe != null) req.requireCap('recipes.read');
    return MockResponse.ok(
      b.catalogPage(
        req,
        org: org,
        categoryId: req.q('category_id'),
        search: req.q('search'),
        hasRecipe: hasRecipe,
      ),
    );
  });

  // GET /costing/addon-items (orders read): every add-on's cost rollup.
  server.on('GET', '/costing/addon-items', (req) {
    req.requireCap('orders.read');
    final org = req.q('org_id');
    req.requireSameOrg(org);
    return MockResponse.ok([
      for (final c in b.data.addonCosts())
        if (b.addonOrg(c['addon_item_id'] as String) == org) c,
    ]);
  });

  // GET /branch-menu-overrides?branch_id.
  server.on('GET', '/branch-menu-overrides', (req) {
    req.requireCap(_read);
    final branch = b.branchInScope(req, req.q('branch_id'));
    return MockResponse.ok(b.branchMenuOverrides(branch));
  });

  // GET /branch-addon-overrides?branch_id.
  server.on('GET', '/branch-addon-overrides', (req) {
    req.requireCap(_read);
    final branch = b.branchInScope(req, req.q('branch_id'));
    return MockResponse.ok(b.branchAddonOverrides(branch));
  });

  // PUT /menu-price-overrides: upsert on the scope's key.
  server.on('PUT', '/menu-price-overrides', (req) {
    req.requireCap(_edit);
    final org = b.claimsOrg(req);
    final body = req.json;
    final price = body['price'];
    if (price == null && body['is_available'] == null) {
      req.badRequest(
        'an override must set at least one of price / is_available',
      );
    }
    if (price is num && price < 0) req.badRequest('price must be >= 0');
    b.checkOverrideShape(req, body);
    b.checkOverrideTenancy(req, org, body);
    return MockResponse.ok(b.putOverride(body));
  });

  // DELETE /menu-price-overrides: the exact row (no-op when absent).
  server.on('DELETE', '/menu-price-overrides', (req) {
    req.requireCap(_edit);
    final org = b.claimsOrg(req);
    final body = req.json;
    b.checkOverrideShape(req, body);
    b.checkOverrideTenancy(req, org, body, branch: false);
    b.deleteOverride(body);
    return MockResponse.empty();
  });

  // GET /menu-items/{id}: MenuItemFull.
  server.on('GET', '/menu-items/{id}', (req) {
    req.requireCap(_read);
    final item = b.item(req.param('id'));
    req.requireSameOrg(item['org_id'] as String?);
    return MockResponse.ok(b.menuItemFull(item));
  });

  // POST /menu-items: the item and its `one_size` row at `base_price`.
  server.on('POST', '/menu-items', (req) {
    req.requireCap(_create);
    final body = req.json;
    req.requireSameOrg(body['org_id'] as String?);
    final item = b.createItem(req, body);
    return MockResponse.created(b.menuItemFull(item, created: true));
  });

  // PATCH /menu-items/{id}.
  server.on('PATCH', '/menu-items/{id}', (req) {
    req.requireCap(_edit);
    final item = b.item(req.param('id'));
    req.requireSameOrg(item['org_id'] as String?);
    return MockResponse.ok(b.updateItem(req, item));
  });

  // DELETE /menu-items/{id}: soft delete (no org check, 204 even when gone,
  // as the backend).
  server.on('DELETE', '/menu-items/{id}', (req) {
    req.requireCap(_delete);
    final row = db[MenuTables.menuItems].find(req.param('id'));
    if (row != null && row['deleted_at'] == null) {
      row['deleted_at'] = db.nowIso;
    }
    return MockResponse.empty();
  });

  // POST /menu-items/{id}/duplicate: the deep copy, `name (Copy)`.
  server.on('POST', '/menu-items/{id}/duplicate', (req) {
    req.requireCap(_edit);
    final item = b.item(req.param('id'));
    req.requireSameOrg(item['org_id'] as String?);
    return MockResponse.created(b.studio(b.duplicate(item)));
  });

  // POST /uploads/menu-items/{menu_item_id}: accepted for processing.
  server.on('POST', '/uploads/menu-items/{menu_item_id}', (req) {
    req.requireCap(_edit);
    final id = req.param('menu_item_id');
    final item = db[MenuTables.menuItems].find(id);
    if (item == null || item['deleted_at'] != null) {
      req.notFound('Menu item not found');
    }
    if (!req.persona.isPlatform && req.persona.orgId != item['org_id']) {
      req.fail(MockResponse.forbidden('Menu item belongs to a different org'));
    }
    final file = req.file('image');
    if (file == null || file.bytes.isEmpty) {
      req.badRequest('No image field found in upload');
    }
    final job = db[assetJobsTable].insert({
      'org_id': item['org_id'],
      'item_id': id,
      'polls': 0,
      'status': 'processing',
      'error': null,
    });
    return MockResponse.ok({
      'image_url': item['image_url'],
      'asset_job_id': job['id'],
      'status': 'processing',
    });
  });

  // GET /assets/jobs/{id}: processing on the first look, then done (the
  // item's picture is set) unless a test marked it failed.
  server.on('GET', '/assets/jobs/{id}', (req) {
    final job = db[assetJobsTable].get(req.param('id'), what: 'Job not found');
    req.requireSameOrg(job['org_id'] as String?);
    return MockResponse.ok(b.pollJob(job));
  });

  // POST /categories: last in POS order.
  server.on('POST', '/categories', (req) {
    req.requireCap('menu.categories.create');
    final body = req.json;
    final org = body['org_id'] as String?;
    req.requireSameOrg(org);
    return MockResponse.created(b.createCategory(body, org!));
  });

  // PUT /categories/order: exactly the org's live categories.
  server.on('PUT', '/categories/order', (req) {
    req.requireCap('menu.categories.edit');
    final body = req.json;
    final org = body['org_id'] as String?;
    req.requireSameOrg(org);
    return MockResponse.ok(b.reorderCategories(req, org!, body));
  });

  // PATCH /categories/{id}.
  server.on('PATCH', '/categories/{id}', (req) {
    req.requireCap('menu.categories.edit');
    final c = b.category(req.param('id'));
    req.requireSameOrg(c['org_id'] as String?);
    return MockResponse.ok(b.updateCategory(c, req.json));
  });

  // DELETE /categories/{id}: soft; its items lose the category.
  server.on('DELETE', '/categories/{id}', (req) {
    req.requireCap('menu.categories.delete');
    final c = b.category(req.param('id'));
    req.requireSameOrg(c['org_id'] as String?);
    c['deleted_at'] = db.nowIso;
    for (final m in db[MenuTables.menuItems].where(
      (m) => m['category_id'] == c['id'],
    )) {
      m['category_id'] = null;
    }
    return MockResponse.empty();
  });
}

/// What the items handlers compute, over the area's tables.
class ItemsBackend {
  ItemsBackend(this.db);

  final MockDb db;

  CatalogMenuData get data => CatalogMenuData(db);
  MockTable get _items => db[MenuTables.menuItems];
  MockTable get _sizes => db[MenuTables.sizes];
  MockTable get _lines => db[MenuTables.recipeLines];
  MockTable get _overrides => db[MenuTables.priceOverrides];
  MockTable get _categories => db[MenuTables.categories];

  static Never _bad(String reason) =>
      throw MockHttpError(MockResponse.badRequest(reason));

  MockRow item(String id) {
    final row = _items.find(id);
    if (row == null || row['deleted_at'] != null) {
      throw MockHttpError(MockResponse.notFound('Menu item not found'));
    }
    return row;
  }

  MockRow category(String id) {
    final row = _categories.find(id);
    if (row == null || row['deleted_at'] != null) {
      throw MockHttpError(MockResponse.notFound('Category not found'));
    }
    return row;
  }

  /// `claims.org_id()`: a platform admin without an org picked is refused.
  String claimsOrg(MockRequest req) =>
      req.orgId ??
      req.fail(
        MockResponse.forbidden('A super admin must scope this to an org'),
      );

  /// `branch_in_scope`: the branch exists in the caller's org and the caller
  /// may act there.
  String branchInScope(MockRequest req, String? branchId) {
    if (branchId == null) {
      req.badRequest('Query deserialize error: missing field `branch_id`');
    }
    final branch = db['branches'].find(branchId);
    if (branch == null) req.notFound('Branch not found');
    req.requireSameOrg(branch['org_id'] as String?);
    req.requireBranch(branchId);
    return branchId;
  }

  // ── catalog ──────────────────────────────────────────────────────────

  Map<String, Object?> catalogPage(
    MockRequest req, {
    required String org,
    String? categoryId,
    String? search,
    bool? hasRecipe,
  }) {
    final needle = search?.trim().toLowerCase();
    final d = data;
    final rows = _items.query(
      filters: {'org_id': org, 'category_id': categoryId},
      where: (m) =>
          m['deleted_at'] == null &&
          (needle == null ||
              needle.isEmpty ||
              '${m['name']}'.toLowerCase().contains(needle)) &&
          (hasRecipe == null || d.hasRecipe(m['id'] as String) == hasRecipe),
      sort: 'name',
    );
    final page = pageOf(
      [
        for (final m in rows) {...m, 'sku_costs': d.skuCosts(m)},
      ],
      req,
      maxPerPage: 500,
    );
    if (rows.isEmpty) page['total_pages'] = 0;
    return page;
  }

  /// The org of the shared group holding option [optionId].
  String? addonOrg(String optionId) {
    for (final g in db[MenuTables.groups].rows) {
      for (final o in (g['options'] as List).cast<Map<String, Object?>>()) {
        if (o['id'] == optionId) return g['org_id'] as String?;
      }
    }
    return null;
  }

  // ── branch overrides ─────────────────────────────────────────────────

  /// The item-level view of one branch's size rows: an item with any
  /// branch-scope size row is listed, unavailable when every active size is
  /// switched off there; its priced sizes as `sizes`.
  List<Map<String, Object?>> branchMenuOverrides(String branchId) {
    final byItem = <String, List<(MockRow, MockRow)>>{};
    for (final o in _overrides.where(
      (o) =>
          o['scope'] == 'branch' &&
          o['branch_id'] == branchId &&
          o['target_type'] == 'menu_item_size',
    )) {
      final size = _sizes.find(o['target_id'] as String);
      if (size == null) continue;
      final m = _items.find(size['menu_item_id'] as String);
      if (m == null || m['deleted_at'] != null) continue;
      (byItem[m['id'] as String] ??= []).add((size, o));
    }
    return [
      for (final e in byItem.entries)
        () {
          final off = {
            for (final (s, o) in e.value)
              if (o['is_available'] == false) s['id'],
          };
          final active = [
            for (final s in data.sizesOf(e.key))
              if (s['is_active'] == true) s['id'],
          ];
          return <String, Object?>{
            'branch_id': branchId,
            'menu_item_id': e.key,
            'price_override': null,
            'is_available': !(active.isNotEmpty && active.every(off.contains)),
            'sizes': [
              for (final (s, o) in e.value)
                if (o['price'] != null)
                  {'size_label': s['label'], 'price_override': o['price']},
            ],
            'updated_at':
                (e.value.first.$2['updated_at'] as String?) ?? db.nowIso,
          };
        }(),
    ];
  }

  List<Map<String, Object?>> branchAddonOverrides(String branchId) => [
    for (final o in _overrides.where(
      (o) =>
          o['scope'] == 'branch' &&
          o['branch_id'] == branchId &&
          o['target_type'] == 'modifier_option',
    ))
      {
        'branch_id': branchId,
        'addon_item_id': o['target_id'],
        'price_override': o['price'],
        'is_available': o['is_available'] ?? true,
        'updated_at': (o['updated_at'] as String?) ?? db.nowIso,
      },
  ];

  void checkOverrideShape(MockRequest req, Map<String, Object?> b) {
    final hasBranch = b['branch_id'] != null;
    final hasChannel = b['channel'] != null;
    switch (b['scope']) {
      case 'branch':
        if (!hasBranch || hasChannel) {
          req.badRequest("scope 'branch' requires branch_id and no channel");
        }
      case 'channel':
        if (hasBranch || !hasChannel) {
          req.badRequest("scope 'channel' requires channel and no branch_id");
        }
      case 'branch_channel':
        if (!hasBranch || !hasChannel) {
          req.badRequest(
            "scope 'branch_channel' requires both branch_id and channel",
          );
        }
      default:
        req.badRequest(
          "scope must be 'branch', 'channel', or 'branch_channel'",
        );
    }
  }

  void checkOverrideTenancy(
    MockRequest req,
    String org,
    Map<String, Object?> b, {
    bool branch = true,
  }) {
    final target = b['target_id'] as String?;
    final ok = switch (b['target_type']) {
      'menu_item_size' => () {
        final s = target == null ? null : _sizes.find(target);
        final m = s == null ? null : _items.find(s['menu_item_id'] as String);
        return m != null && m['org_id'] == org && m['deleted_at'] == null;
      }(),
      _ => target != null && addonOrg(target) == org,
    };
    if (!ok) {
      req.badRequest('Override target does not exist in this organization');
    }
    final bid = b['branch_id'] as String?;
    if (branch && bid != null && db['branches'].find(bid)?['org_id'] != org) {
      req.badRequest('Branch does not exist in this organization');
    }
  }

  MockRow? _overrideRow(Map<String, Object?> b) => _overrides.firstWhere(
    (o) =>
        o['scope'] == b['scope'] &&
        o['branch_id'] == b['branch_id'] &&
        o['channel'] == b['channel'] &&
        o['target_type'] == b['target_type'] &&
        o['target_id'] == b['target_id'],
  );

  Map<String, Object?> putOverride(Map<String, Object?> b) {
    final values = {
      'price': (b['price'] as num?)?.toInt(),
      'is_available': b['is_available'],
      'updated_at': db.nowIso,
    };
    var row = _overrideRow(b);
    if (row != null) {
      row.addAll(values);
    } else {
      row = _overrides.insert({
        'scope': b['scope'],
        'branch_id': b['branch_id'],
        'channel': b['channel'],
        'target_type': b['target_type'],
        'target_id': b['target_id'],
        ...values,
      }, timestamps: false);
    }
    return {
      'id': row['id'],
      'scope': row['scope'],
      'branch_id': row['branch_id'],
      'channel': row['channel'],
      'target_type': row['target_type'],
      'target_id': row['target_id'],
      'price': row['price'],
      'is_available': row['is_available'],
    };
  }

  void deleteOverride(Map<String, Object?> b) {
    final row = _overrideRow(b);
    if (row != null) _overrides.delete(row['id'] as String);
  }

  // ── items ────────────────────────────────────────────────────────────

  /// `ensure_translations_json`: the base language follows the name.
  static Map<String, Object?> _translations(
    Object? existing,
    Object? incoming,
    String? base,
  ) {
    final out = <String, Object?>{
      if (existing is Map) ...existing.cast<String, Object?>(),
      if (incoming is Map) ...incoming.cast<String, Object?>(),
    };
    if (base != null) out['en'] = base;
    return out;
  }

  MockRow createItem(MockRequest req, Map<String, Object?> body) {
    final price = body['base_price'];
    if (price is! num) req.badRequest('Json deserialize error: base_price');
    final name = body['name'];
    if (name is! String) req.badRequest('Json deserialize error: name');
    final desc = body['description'] as String?;
    final now = db.nowIso;
    final item = _items.insert({
      'org_id': body['org_id'],
      'category_id': body['category_id'],
      'name': name,
      'name_translations': _translations(null, body['name_translations'], name),
      'description': desc,
      'description_translations': _translations(
        null,
        body['description_translations'],
        desc,
      ),
      'image_url': body['image_url'],
      'base_price': price.toInt(),
      'is_active': true,
      'kind': 'item',
      'created_at': now,
      'updated_at': now,
    }, timestamps: false);
    _sizes.insert({
      'menu_item_id': item['id'],
      'label': oneSize,
      'price_override': price.toInt(),
      'is_active': true,
      'sort': 0,
      'base_id': null,
    }, timestamps: false);
    data.rebuildItem(item['id'] as String);
    return item;
  }

  Map<String, Object?> updateItem(MockRequest req, MockRow item) {
    final body = req.json;
    final name = body['name'] as String?;
    item['name_translations'] = _translations(
      item['name_translations'],
      body['name_translations'],
      name ?? item['name'] as String?,
    );
    final desc = body['description'] as String?;
    item['description_translations'] = _translations(
      item['description_translations'],
      body['description_translations'],
      desc ?? item['description'] as String?,
    );
    if (name != null) item['name'] = name;
    if (desc != null) item['description'] = desc;
    if (body['category_id'] != null) item['category_id'] = body['category_id'];
    if (body['is_active'] != null) item['is_active'] = body['is_active'];
    if (body.containsKey('image_url')) {
      item['image_url'] = body['image_url'];
      if (body['image_url'] == null) item['image'] = null;
    }
    final price = body['base_price'];
    if (price is num) {
      final active = [
        for (final s in data.sizesOf(item['id'] as String))
          if (s['is_active'] == true) s,
      ];
      if (active.length == 1) active.single['price_override'] = price.toInt();
      item['base_price'] = price.toInt();
    }
    item['updated_at'] = db.nowIso;
    return _menuItem(item);
  }

  /// The `MenuItem` wire row (no area-only columns).
  Map<String, Object?> _menuItem(MockRow item) => {
    for (final e in item.entries)
      if (e.key != 'recipe_source_item_id') e.key: e.value,
  };

  /// `MenuItemFull`: legacy `sizes` (without `one_size`, by label),
  /// `all_sizes` (by sort), the item's own recipe lines and the add-ons its
  /// shared groups offer.
  Map<String, Object?> menuItemFull(MockRow item, {bool created = false}) {
    final itemId = item['id'] as String;
    final all = [
      for (final s in data.sizesOf(itemId))
        {
          'id': s['id'],
          'menu_item_id': itemId,
          'label': s['label'],
          'price_override': s['price_override'] ?? item['base_price'],
          'is_active': s['is_active'],
        },
    ];
    final legacy = [
      for (final s in all)
        if (s['label'] != oneSize) s,
    ]..sort((a, b) => compareJson(a['label'], b['label']));
    final d = data;
    return {
      ..._menuItem(item),
      'sizes': created ? const <Object?>[] : legacy,
      'all_sizes': all,
      'addon_slots': const <Object?>[],
      'optional_fields': const <Object?>[],
      'recipe_steps': const <Object?>[],
      'recipes': created
          ? const <Object?>[]
          : [
              for (final s in data.sizesOf(itemId))
                for (final l in d.linesOf(s['id'] as String))
                  if (l['source'] == null || l['source'] == 'own')
                    {
                      'org_ingredient_id': l['ingredient_id'],
                      'quantity_used': jsNumber('${l['quantity']}'),
                      'ingredient_name': d.ingredientName(
                        l['ingredient_id'] as String,
                      ),
                      'ingredient_unit': l['unit'],
                      'category':
                          d.ingredient(
                            l['ingredient_id'] as String,
                          )?['category_slug'] ??
                          '',
                      'size_label': s['label'],
                    },
            ],
      'allowed_addon_ids': created
          ? const <Object?>[]
          : allowedAddonIds(itemId),
    };
  }

  /// The add-ons (shared-group options) the item offers, group by group.
  List<String> allowedAddonIds(String itemId) {
    final links = db[MenuTables.groupLinks].where(
      (l) => l['menu_item_id'] == itemId,
    )..sort((a, b) => ((a['sort'] as int?) ?? 0) - ((b['sort'] as int?) ?? 0));
    return [
      for (final l in links)
        if (db[MenuTables.groups].find(l['group_id'] as String) case final g?
            when g['legacy_addon_type'] != null)
          for (final o in (g['options'] as List).cast<Map<String, Object?>>())
            if ((l['included_option_ids'] as List?)?.contains(o['id']) ?? true)
              o['id'] as String,
    ];
  }

  /// The duplicate: basics with ` (Copy)`, sizes, own lines, attachments and
  /// overrides on new ids.
  MockRow duplicate(MockRow src) {
    final srcId = src['id'] as String;
    final now = db.nowIso;
    final copy = _items.insert({
      ..._menuItem(src),
      'id': db.newId(MenuTables.menuItems),
      'name': '${src['name']} (Copy)',
      'created_at': now,
      'updated_at': now,
    }, timestamps: false);
    final copyId = copy['id'] as String;
    for (final s in data.sizesOf(srcId)) {
      final ns = _sizes.insert({
        ...s,
        'id': db.newId(MenuTables.sizes),
        'menu_item_id': copyId,
      }, timestamps: false);
      for (final l in data.linesOf(s['id'] as String)) {
        if (l['source'] != null && l['source'] != 'own') continue;
        _lines.insert({
          ...l,
          'id': db.newId(MenuTables.recipeLines),
          'size_id': ns['id'],
          'menu_item_id': copyId,
        }, timestamps: false);
      }
      for (final o in _overrides.where((o) => o['target_id'] == s['id'])) {
        _overrides.insert({
          ...o,
          'id': db.newId(MenuTables.priceOverrides),
          'target_id': ns['id'],
        }, timestamps: false);
      }
    }
    for (final l in db[MenuTables.groupLinks].where(
      (l) => l['menu_item_id'] == srcId,
    )) {
      db[MenuTables.groupLinks].insert({
        ...l,
        'id': db.newId(MenuTables.groupLinks),
        'menu_item_id': copyId,
      }, timestamps: false);
    }
    data.rebuildItem(copyId);
    return copy;
  }

  /// A `RecipeLineOut` (the quantity as decimal text).
  Map<String, Object?> _line(Map<String, Object?> l, [String? id]) {
    final ingId = l['ingredient_id'] as String;
    return {
      'id': id ?? l['id'],
      'ingredient_id': ingId,
      'ingredient_name': data.ingredientName(ingId),
      'quantity': fmtQty(jsNumber('${l['quantity']}')),
      'usable_quantity': fmtQty(data.usableOf(ingId, l['quantity'])),
      'unit': l['unit'],
      'size_label': l['size_label'],
      'source': l['source'],
      'line_cost_piastres': data.lineCost(l),
    };
  }

  /// A `StudioAggregate` with the item's sizes (and their lines and cost),
  /// its attached groups and the branch availability rows (options and steps
  /// are the studio unit's).
  Map<String, Object?> studio(MockRow item) {
    final itemId = item['id'] as String;
    final d = data;
    final sizes = d.sizesOf(itemId);
    final sizeIds = {for (final s in sizes) s['id']};
    final byBranch = <String, (List<Object?>, Map<String, List<Object?>>)>{};
    for (final o in _overrides.where(
      (o) =>
          o['target_type'] == 'menu_item_size' &&
          sizeIds.contains(o['target_id']) &&
          o['branch_id'] != null,
    )) {
      final e = byBranch[o['branch_id'] as String] ??= ([], {});
      final sv = {
        'size_id': o['target_id'],
        'price': o['price'],
        'is_available': o['is_available'],
      };
      if (o['scope'] == 'branch') {
        e.$1.add(sv);
      } else {
        (e.$2[o['channel'] as String] ??= []).add(sv);
      }
    }
    final links = db[MenuTables.groupLinks].where(
      (l) => l['menu_item_id'] == itemId,
    )..sort((a, b) => ((a['sort'] as int?) ?? 0) - ((b['sort'] as int?) ?? 0));
    return {
      'id': itemId,
      'org_id': item['org_id'],
      'name': item['name'],
      'name_translations': item['name_translations'],
      'description': item['description'],
      'category_id': item['category_id'],
      'image_url': item['image_url'],
      'is_active': item['is_active'],
      'recipe_source_item_id': item['recipe_source_item_id'],
      'catalog_revision': 1,
      'availability': {
        'org_active': item['is_active'],
        'branches': [
          for (final e in byBranch.entries)
            {
              'branch_id': e.key,
              'sizes': e.value.$1,
              'channels': [
                for (final c in e.value.$2.entries)
                  {'channel': c.key, 'sizes': c.value},
              ],
            },
        ],
      },
      'options': const <Object?>[],
      'recipe_steps': const <Object?>[],
      'sizes': [
        for (final s in sizes)
          () {
            final lines = d.linesOf(s['id'] as String);
            final cost = d.costOf(lines);
            return {
              'id': s['id'],
              'label': s['label'],
              'price': d.priceOf(s, item),
              'is_active': s['is_active'],
              'sort': s['sort'] ?? 0,
              'base_id': s['base_id'],
              'cost_piastres': cost.cost,
              'cost_incomplete': cost.incomplete,
              'recipe': [for (final l in lines) _line(l)],
            };
          }(),
      ],
      'modifier_groups': [
        for (final l in links)
          if (db[MenuTables.groups].find(l['group_id'] as String) case final g?)
            {
              'attachment_id': l['id'],
              'group_id': g['id'],
              'name': g['name'],
              'name_translations': g['name_translations'],
              'legacy_addon_type': g['legacy_addon_type'],
              'selection_type': g['selection_type'],
              'is_required': l['is_required_override'] ?? g['is_required'],
              'min': l['min_override'] ?? g['min_selections'],
              'max': l['max_override'] ?? g['max_selections'],
              'sort': l['sort'] ?? 0,
              'options': [
                for (final o
                    in (g['options'] as List).cast<Map<String, Object?>>())
                  () {
                    final recipe = ((o['recipe'] as List?) ?? const [])
                        .cast<Map<String, Object?>>();
                    final cost = d.costOf(recipe);
                    final included = l['included_option_ids'] as List?;
                    return {
                      'id': o['id'],
                      'name': o['name'],
                      'price': o['price'],
                      'is_active': o['is_active'],
                      'is_default': o['is_default'] ?? false,
                      'included':
                          included == null || included.contains(o['id']),
                      'replaces_ingredient_id': o['replaces_ingredient_id'],
                      'cost_piastres': cost.cost,
                      'cost_incomplete': cost.incomplete,
                      'recipe': [
                        for (final (n, r) in recipe.indexed)
                          _line(r, mockUuid('option-line:${o['id']}:$n')),
                      ],
                    };
                  }(),
              ],
            },
      ],
    };
  }

  // ── uploads ──────────────────────────────────────────────────────────

  /// One look at an upload job: still processing the first time, then done
  /// (the item gets its picture) or failed when a test set `fail`.
  Map<String, Object?> pollJob(MockRow job) {
    if (job['status'] == 'processing') {
      final polls = (job['polls'] as int? ?? 0) + 1;
      job['polls'] = polls;
      if (polls > 1) {
        if (job['fail'] != null) {
          job['status'] = 'failed';
          job['error'] = job['fail'];
        } else {
          job['status'] = 'done';
          final url = 'https://cdn.madar.test/assets/${job['id']}/tile.webp';
          final item = _items.find(job['item_id'] as String);
          if (item != null) item['image_url'] = url;
          job['url'] = url;
        }
      }
    }
    final done = job['status'] == 'done';
    return {
      'id': job['id'],
      'status': job['status'],
      'error': job['error'],
      'result': done ? _jobResult(job) : null,
    };
  }

  Map<String, Object?> _jobResult(MockRow job) {
    Map<String, Object?> ref(String variant) => {
      'id': mockUuid('asset:${job['id']}:$variant'),
      'group_id': mockUuid('asset-group:${job['id']}'),
      'org_id': job['org_id'],
      'kind': 'image',
      'variant': variant,
      'url': 'https://cdn.madar.test/assets/${job['id']}/$variant.webp',
      'content_type': 'image/webp',
      'ext': 'webp',
      'bytes': 24000,
      'hash': mockUuid('asset-hash:${job['id']}:$variant').replaceAll('-', ''),
      'has_alpha': false,
      'width': 512,
      'height': 512,
    };
    return {
      'full': ref('full'),
      'pos': ref('pos'),
      'variants': [ref('tile'), ref('full')],
    };
  }

  // ── categories ───────────────────────────────────────────────────────

  Map<String, Object?> createCategory(Map<String, Object?> body, String org) {
    final name = body['name'];
    if (name is! String) _bad('Json deserialize error: name');
    final live = _categories.where(
      (c) => c['org_id'] == org && c['deleted_at'] == null,
    );
    final next = live.isEmpty
        ? 0
        : live
                  .map((c) => (c['display_order'] as int?) ?? 0)
                  .reduce((a, b) => a > b ? a : b) +
              1;
    final now = db.nowIso;
    return _categories.insert({
      'org_id': org,
      'name': name,
      'name_translations': _translations(null, body['name_translations'], name),
      'image_url': body['image_url'],
      'is_active': true,
      'display_order': next,
      'created_at': now,
      'updated_at': now,
    }, timestamps: false);
  }

  Map<String, Object?> updateCategory(MockRow c, Map<String, Object?> body) {
    final name = body['name'] as String?;
    if (name != null) {
      c['name_translations'] = _translations(
        c['name_translations'],
        null,
        name,
      );
      c['name'] = name;
    } else if (body['name_translations'] is Map) {
      c['name_translations'] = _translations(
        body['name_translations'],
        null,
        c['name'] as String?,
      );
    }
    if (body['is_active'] != null) c['is_active'] = body['is_active'];
    if (body.containsKey('image_url')) c['image_url'] = body['image_url'];
    c['updated_at'] = db.nowIso;
    return c;
  }

  List<MockRow> reorderCategories(
    MockRequest req,
    String org,
    Map<String, Object?> body,
  ) {
    final ids = ((body['ordered_ids'] as List?) ?? const []).cast<String>();
    final live = _categories.where(
      (c) => c['org_id'] == org && c['deleted_at'] == null,
    );
    final want = [for (final c in live) c['id'] as String]..sort();
    final got = [...ids]..sort();
    if (want.join(',') != got.join(',')) {
      _bad('ordered_ids must contain exactly the org\'s live categories');
    }
    for (final (n, id) in ids.indexed) {
      _categories.find(id)!['display_order'] = n;
    }
    return _categories.query(
      filters: {'org_id': org},
      where: (c) => c['deleted_at'] == null,
      sort: 'display_order',
    );
  }
}
