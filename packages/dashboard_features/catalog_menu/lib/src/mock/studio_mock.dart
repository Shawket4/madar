/// Mock handlers of the `studio` unit: the Menu Studio, the backend's way
/// (`MadarRust/src/menu/studio.rs`, `linked.rs`, `bases.rs`, `preview.rs`,
/// `modifiers.rs` (item options), `src/recipes/steps.rs`, `src/combos`).
///
/// Every route refuses like the backend: `menu.items.read` to read,
/// `menu.items.edit` to write, `recipes.read` / `recipes.edit` for the step
/// library and steps, `menu.combos.edit` for the meal; the org guard; 404s;
/// the 400 / 409 of each handler's validation.
///
/// Owned here: `GET /menu-items/{id}/studio`, `PUT /menu-items/{id}/sizes`,
/// `PUT /menu-item-sizes/{size_id}/recipe`, `PUT /menu-item-sizes/{size_id}/base`,
/// `PUT /menu-items/{id}/modifier-groups`, `PUT /menu-items/{id}/options`,
/// `GET|PUT /recipes/steps…`, `GET /recipes/step-presets` (+ an animation
/// file), `GET|DELETE /menu-items/{id}/recipe-link`,
/// `POST /menu-items/{id}/preview`.
///
/// Registered only when no unit before this one answers them (the items unit
/// and other areas may own them): `GET /menu-items`, `GET|PATCH
/// /menu-items/{id}`, `POST /menu-items/{id}/duplicate`, `POST
/// /uploads/menu-items/{menu_item_id}`, `PUT /menu-items/{id}/meal`,
/// `PATCH /inventory/orgs/{org_id}/catalog/{id}`, `GET /combos`,
/// `GET /combos/{id}` (the combos area's tables: `kind: combo` menu items and
/// `combo_specs`).
///
/// An item's own priced options live, as on the backend, in an item-private
/// `Options` group (`is_item_options`) attached to it; the studio lists them
/// under `options`, never under `modifier_groups`.
library;

import 'dart:convert';

import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';
import '../shared/menu_text.dart';

const String _read = 'menu.items.read';
const String _edit = 'menu.items.edit';

/// The combos area's table of slots per combo (`{id, slots, windows}`, the
/// id being the combo's), read by the combo fallbacks.
const String comboSpecsTable = 'combo_specs';

void registerStudioMocks(MockServer server, MockDb db) {
  final b = StudioBackend(db);

  void maybe(String method, String template, MockHandler handler) {
    if (!server.handles(method, template)) server.on(method, template, handler);
  }

  // GET /menu-items/{id}/studio (menu_items read).
  server.on('GET', '/menu-items/{id}/studio', (req) {
    req.requireCap(_read);
    final item = b.item(req.param('id'));
    req.requireSameOrg(item['org_id'] as String?);
    return MockResponse.ok(b.studio(item));
  });

  // PUT /menu-items/{id}/sizes (menu_items update): the replace-set.
  server.on('PUT', '/menu-items/{id}/sizes', (req) {
    req.requireCap(_edit);
    final item = b.item(req.param('id'));
    req.requireSameOrg(item['org_id'] as String?);
    b.putSizes(req, item);
    return MockResponse.ok(b.studio(item));
  });

  // PUT /menu-item-sizes/{size_id}/recipe (menu_items update).
  server.on('PUT', '/menu-item-sizes/{size_id}/recipe', (req) {
    req.requireCap(_edit);
    return MockResponse.ok(b.putSizeRecipe(req, req.param('size_id')));
  });

  // PUT /menu-item-sizes/{size_id}/base (menu_items update).
  server.on('PUT', '/menu-item-sizes/{size_id}/base', (req) {
    req.requireCap(_edit);
    return MockResponse.ok(b.putSizeBase(req, req.param('size_id')));
  });

  // PUT /menu-items/{id}/modifier-groups (menu_items update).
  server.on('PUT', '/menu-items/{id}/modifier-groups', (req) {
    req.requireCap(_edit);
    final item = b.item(req.param('id'));
    req.requireSameOrg(item['org_id'] as String?);
    b.putAttachments(req, item);
    return MockResponse.ok(b.studio(item));
  });

  // PUT /menu-items/{id}/options (menu_items update).
  server.on('PUT', '/menu-items/{id}/options', (req) {
    req.requireCap(_edit);
    final item = b.item(req.param('id'));
    req.requireSameOrg(item['org_id'] as String?);
    return MockResponse.ok(b.putItemOptions(req, item));
  });

  // GET /recipes/step-presets (recipes read): the live library.
  server.on('GET', '/recipes/step-presets', (req) {
    req.requireCap('recipes.read');
    return MockResponse.ok(
      db[MenuTables.stepPresets].query(
        where: (p) => p['is_active'] != false,
        sort: 'sort_order',
      ),
    );
  });

  // The library's animation files (a small Lottie document per step).
  server.on('GET', '/recipes/step-presets/{slug}/animation', (req) {
    final slug = req.param('slug');
    if (db[MenuTables.stepPresets].find(slug) == null) {
      req.notFound('Step animation not found');
    }
    return MockResponse.bytes(
      utf8.encode(stepAnimationJson(slug)),
      contentType: 'application/json',
    );
  });

  // GET /recipes/steps/{menu_item_id} (recipes read).
  server.on('GET', '/recipes/steps/{menu_item_id}', (req) {
    req.requireCap('recipes.read');
    final item = b.item(req.param('menu_item_id'));
    req.requireSameOrg(item['org_id'] as String?);
    return MockResponse.ok(b.steps(item['id'] as String));
  });

  // PUT /recipes/steps/{menu_item_id} (recipes update): the replace-set.
  server.on('PUT', '/recipes/steps/{menu_item_id}', (req) {
    req.requireCap('recipes.edit');
    final item = b.item(req.param('menu_item_id'));
    req.requireSameOrg(item['org_id'] as String?);
    return MockResponse.ok(b.putSteps(req, item));
  });

  // GET /menu-items/{id}/recipe-link (menu_items read).
  server.on('GET', '/menu-items/{id}/recipe-link', (req) {
    req.requireCap(_read);
    final item = b.item(req.param('id'));
    req.requireSameOrg(item['org_id'] as String?);
    return MockResponse.ok(b.linkInfo(item));
  });

  // DELETE /menu-items/{id}/recipe-link (menu_items update): the copied
  // lines become the item's own.
  server.on('DELETE', '/menu-items/{id}/recipe-link', (req) {
    req.requireCap(_edit);
    final item = b.item(req.param('id'));
    req.requireSameOrg(item['org_id'] as String?);
    b.unlink(item);
    return MockResponse.ok(b.linkInfo(item));
  });

  // POST /menu-items/{id}/preview (menu_items read): a dry run.
  server.on('POST', '/menu-items/{id}/preview', (req) {
    req.requireCap(_read);
    final item = b.item(req.param('id'));
    req.requireSameOrg(item['org_id'] as String?);
    return MockResponse.ok(b.preview(req, item));
  });

  // ── shared with other units / areas ────────────────────────────────────

  maybe('GET', '/menu-items', (req) {
    req.requireCap(_read);
    final org = req.q('org_id') ?? req.orgId;
    req.requireSameOrg(org);
    final full = req.qBool('full') ?? false;
    final rows = db[MenuTables.menuItems].query(
      filters: {'org_id': org, 'category_id': req.q('category_id')},
      where: (i) => i['deleted_at'] == null,
      sort: 'name',
    );
    return MockResponse.ok([
      for (final r in rows) full ? b.menuItemFull(r) : r,
    ]);
  });

  maybe('GET', '/menu-items/{id}', (req) {
    req.requireCap(_read);
    final item = b.item(req.param('id'));
    req.requireSameOrg(item['org_id'] as String?);
    return MockResponse.ok(b.menuItemFull(item));
  });

  maybe('PATCH', '/menu-items/{id}', (req) {
    req.requireCap(_edit);
    final item = b.item(req.param('id'));
    req.requireSameOrg(item['org_id'] as String?);
    b.patchItem(req, item);
    return MockResponse.ok(item);
  });

  maybe('POST', '/menu-items/{id}/duplicate', (req) {
    req.requireCap(_edit);
    final item = b.item(req.param('id'));
    req.requireSameOrg(item['org_id'] as String?);
    return MockResponse.created(b.studio(b.duplicate(item)));
  });

  maybe('POST', '/uploads/menu-items/{menu_item_id}', (req) {
    req.requireCap(_edit);
    final item = b.item(req.param('menu_item_id'));
    req.requireSameOrg(item['org_id'] as String?);
    final file = req.file('image');
    if (file == null) req.badRequest('Missing image file');
    if (!(file.contentType ?? '').startsWith('image/')) {
      req.badRequest('The file is not an image');
    }
    if (file.bytes.length > 5 * 1024 * 1024) {
      req.badRequest('Image is larger than 5 MB');
    }
    final url =
        'https://cdn.sabah.test/menu-items/${item['id']}/'
        '${db.newId('menu_item_images')}.webp';
    db[MenuTables.menuItems].update(item['id'] as String, {'image_url': url});
    return MockResponse.ok({
      'asset_job_id': db.newId('asset_jobs'),
      'image_url': url,
      'status': 'done',
    });
  });

  maybe('PUT', '/menu-items/{id}/meal', (req) {
    req.requireCap('menu.combos.edit');
    return b.putMeal(req);
  });

  maybe('PATCH', '/inventory/orgs/{org_id}/catalog/{id}', (req) {
    req.requireCap('inventory.adjust');
    final org = req.param('org_id');
    req.requireSameOrg(org);
    final row = db[MenuTables.ingredients].find(req.param('id'));
    if (row == null || row['org_id'] != org) {
      req.notFound('Ingredient not found');
    }
    final cost = req.json['cost_per_unit'];
    if (cost is num && cost < 0) {
      req.badRequest('cost_per_unit must be zero or more');
    }
    for (final k in const ['name', 'unit', 'is_active', 'cost_per_unit']) {
      if (req.json.containsKey(k)) row[k] = req.json[k];
    }
    row['updated_at'] = db.nowIso;
    return MockResponse.ok(row);
  });

  maybe('GET', '/combos', (req) {
    req.requireCap(_read);
    final perPage = (req.qInt('per_page') ?? 50).clamp(1, 200);
    final page = (req.qInt('page') ?? 1).clamp(1, 1 << 30);
    final all = b.combos(req.orgId);
    final from = (page - 1) * perPage;
    return MockResponse.ok({
      'data': [for (final c in all.skip(from).take(perPage)) b.comboSummary(c)],
      'page': page,
      'per_page': perPage,
      'total': all.length,
      'total_pages': all.isEmpty ? 0 : (all.length + perPage - 1) ~/ perPage,
    });
  });

  maybe('GET', '/combos/{id}', (req) {
    req.requireCap(_read);
    final row = db[MenuTables.menuItems].find(req.param('id'));
    if (row == null || row['kind'] != 'combo' || row['deleted_at'] != null) {
      req.notFound('Combo not found');
    }
    req.requireSameOrg(row['org_id'] as String?);
    return MockResponse.ok(b.combo(row));
  });
}

/// A tiny Lottie document: a dot travelling across the frame.
String stepAnimationJson(String slug) => jsonEncode({
  'v': '5.7.4',
  'fr': 30,
  'ip': 0,
  'op': 60,
  'w': 100,
  'h': 100,
  'nm': slug,
  'ddd': 0,
  'assets': const <Object?>[],
  'layers': [
    {
      'ddd': 0,
      'ind': 1,
      'ty': 4,
      'nm': 'dot',
      'sr': 1,
      'ks': {
        'o': {'a': 0, 'k': 100},
        'r': {'a': 0, 'k': 0},
        'p': {
          'a': 1,
          'k': [
            {
              't': 0,
              's': [30, 50, 0],
              'i': {
                'x': [0.5],
                'y': [1],
              },
              'o': {
                'x': [0.5],
                'y': [0],
              },
            },
            {
              't': 60,
              's': [70, 50, 0],
            },
          ],
        },
        'a': {
          'a': 0,
          'k': [0, 0, 0],
        },
        's': {
          'a': 0,
          'k': [100, 100, 100],
        },
      },
      'ao': 0,
      'shapes': [
        {
          'ty': 'el',
          'p': {
            'a': 0,
            'k': [0, 0],
          },
          's': {
            'a': 0,
            'k': [24, 24],
          },
          'nm': 'circle',
        },
        {
          'ty': 'fl',
          'c': {
            'a': 0,
            'k': [0.2, 0.5, 0.5, 1],
          },
          'o': {'a': 0, 'k': 100},
          'nm': 'fill',
        },
      ],
      'ip': 0,
      'op': 60,
      'st': 0,
      'bm': 0,
    },
  ],
});

/// The studio backend over the area's tables (one per server).
class StudioBackend {
  StudioBackend(this.db);

  final MockDb db;
  int _revision = 1;

  CatalogMenuData get _data => CatalogMenuData(db);
  MockTable get _items => db[MenuTables.menuItems];
  MockTable get _sizes => db[MenuTables.sizes];
  MockTable get _lines => db[MenuTables.recipeLines];
  MockTable get _groups => db[MenuTables.groups];
  MockTable get _links => db[MenuTables.groupLinks];
  MockTable get _steps => db[MenuTables.steps];

  static Never _bad(String reason) =>
      throw MockHttpError(MockResponse.badRequest(reason));

  MockRow item(String id) {
    final row = _items.find(id);
    if (row == null || row['deleted_at'] != null) {
      throw MockHttpError(MockResponse.notFound('Menu item not found'));
    }
    return row;
  }

  List<Map<String, Object?>> _options(MockRow g) =>
      ((g['options'] as List?) ?? const []).cast<Map<String, Object?>>();

  /// The item's own Options group, if it has one.
  MockRow? optionsGroup(String itemId) {
    for (final l in _links.where((l) => l['menu_item_id'] == itemId)) {
      final g = _groups.find(l['group_id'] as String);
      if (g != null && g['is_item_options'] == true) return g;
    }
    return null;
  }

  // ── reading ──────────────────────────────────────────────────────────

  /// A stored line as `RecipeLineOut` (the quantity as a decimal string).
  Map<String, Object?> lineOut(Map<String, Object?> l, String id) {
    final ingId = l['ingredient_id'] as String;
    final q = jsNumber('${l['quantity']}');
    return {
      'id': id,
      'ingredient_id': ingId,
      'ingredient_name': _data.ingredientName(ingId),
      'quantity': q.isFinite ? q.toStringAsFixed(3) : '0.000',
      'usable_quantity': _data.usableOf(ingId, q).toStringAsFixed(3),
      'unit': l['unit'],
      'size_label': l['size_label'],
      'source': l['source'],
      'line_cost_piastres': _data.lineCost(l),
    };
  }

  Map<String, Object?> _sizeOut(MockRow item, MockRow s) {
    final lines = _data.linesOf(s['id'] as String);
    final cost = _data.costOf(lines);
    return {
      'id': s['id'],
      'label': s['label'],
      'price': _data.priceOf(s, item),
      'is_active': s['is_active'] ?? true,
      'sort': s['sort'] ?? 0,
      'base_id': s['base_id'],
      'cost_piastres': lines.isEmpty ? null : cost.cost,
      'cost_incomplete': lines.isEmpty ? false : cost.incomplete,
      'recipe': [for (final l in lines) lineOut(l, l['id'] as String)],
    };
  }

  bool _included(Map<String, Object?> link, Map<String, Object?> o) {
    final ids = link['included_option_ids'] as List?;
    return ids == null || ids.contains(o['id']);
  }

  List<Map<String, Object?>> _optionRecipe(Map<String, Object?> o) => [
    for (final (n, r)
        in ((o['recipe'] as List?) ?? const [])
            .cast<Map<String, Object?>>()
            .indexed)
      lineOut(r, mockUuid('option-line:${o['id']}:$n')),
  ];

  /// `GET /recipes/steps/{id}` rows: named by the library (a preset) or by
  /// what was typed; a step's own note falls back to the library's.
  List<Map<String, Object?>> steps(String itemId) {
    final presets = db[MenuTables.stepPresets];
    final rows = _steps.query(
      filters: {'menu_item_id': itemId},
      sort: 'position',
    );
    return [
      for (final s in rows)
        () {
          final p = s['preset_slug'] == null
              ? null
              : presets.find(s['preset_slug'] as String);
          final live = p != null && p['is_active'] != false;
          return {
            'position': s['position'],
            'kind': s['kind'],
            'preset_slug': s['preset_slug'],
            'name': p?['name'] ?? s['name'] ?? '',
            'name_ar': p?['name_ar'] ?? s['name_ar'] ?? '',
            'note': s['note'] ?? p?['note'],
            'note_ar': s['note_ar'] ?? p?['note_ar'],
            'animation_hash': live ? p['animation_hash'] : null,
            'animation_is_global': true,
            'animation_url': live ? p['animation_url'] : null,
            'animation_sha256': live ? p['animation_sha256'] : null,
          };
        }(),
    ];
  }

  /// The `StudioAggregate` of [item].
  Map<String, Object?> studio(MockRow item) {
    final itemId = item['id'] as String;
    final own = optionsGroup(itemId);
    final links =
        _links.where(
          (l) => l['menu_item_id'] == itemId && l['group_id'] != own?['id'],
        )..sort((a, b) {
          final c = ((a['sort'] as int?) ?? 0) - ((b['sort'] as int?) ?? 0);
          if (c != 0) return c;
          return compareJson(
            _groups.find(a['group_id'] as String)?['name'],
            _groups.find(b['group_id'] as String)?['name'],
          );
        });
    final sizes = _data.sizesOf(itemId);
    return {
      'id': itemId,
      'org_id': item['org_id'],
      'name': item['name'],
      'name_translations': item['name_translations'],
      'description': item['description'],
      'category_id': item['category_id'],
      'is_active': item['is_active'],
      'image_url': item['image_url'],
      'image': item['image'],
      'catalog_revision': _revision,
      'recipe_source_item_id': item['recipe_source_item_id'],
      'linked_copy_ids': _copiesOf(itemId),
      'availability': _availability(item, sizes),
      'sizes': [for (final s in sizes) _sizeOut(item, s)],
      'modifier_groups': [
        for (final l in links)
          if (_groups.find(l['group_id'] as String) case final g?)
            {
              'attachment_id': l['id'],
              'group_id': g['id'],
              'name': g['name'],
              'name_translations': g['name_translations'],
              'legacy_addon_type': g['legacy_addon_type'],
              'selection_type': g['selection_type'],
              'is_required': l['is_required_override'] ?? g['is_required'],
              'min': l['min_override'] ?? g['min_selections'],
              'max': l.containsKey('max_override') && l['max_override'] != null
                  ? l['max_override']
                  : g['max_selections'],
              'sort': l['sort'] ?? 0,
              'options': [
                for (final o in _options(g))
                  () {
                    final cost = _data.optionCost(o);
                    final recipe = (o['recipe'] as List?) ?? const [];
                    return {
                      'id': o['id'],
                      'name': o['name'],
                      'price': o['price'],
                      'is_active': o['is_active'],
                      'is_default': o['is_default'] ?? false,
                      'included': _included(l, o),
                      'replaces_ingredient_id': o['replaces_ingredient_id'],
                      'cost_piastres': recipe.isEmpty ? null : cost.cost,
                      'cost_incomplete': recipe.isEmpty
                          ? false
                          : cost.incomplete,
                      'recipe': _optionRecipe(o),
                    };
                  }(),
              ],
            },
      ],
      'options': own == null ? const <Object?>[] : _itemOptionsOut(own),
      'recipe_steps': steps(itemId),
    };
  }

  List<Map<String, Object?>> _itemOptionsOut(MockRow g) => [
    for (final o in _options(g))
      if (o['deleted'] != true)
        () {
          final recipe = (o['recipe'] as List?) ?? const [];
          final cost = _data.optionCost(o);
          return {
            'id': o['id'],
            'name': o['name'],
            'price': o['price'],
            'is_active': o['is_active'],
            'cost_piastres': recipe.isEmpty ? null : cost.cost,
            'cost_incomplete': recipe.isEmpty ? false : cost.incomplete,
            'recipe': _optionRecipe(o),
          };
        }(),
  ];

  Map<String, Object?> _availability(MockRow item, List<MockRow> sizes) {
    final ids = {for (final s in sizes) s['id']};
    final byBranch = <String, List<MockRow>>{};
    for (final o in db[MenuTables.priceOverrides].rows) {
      if (o['target_type'] == 'menu_item_size' &&
          ids.contains(o['target_id'])) {
        byBranch.putIfAbsent(o['branch_id'] as String, () => []).add(o);
      }
    }
    Map<String, Object?> size(MockRow o) => {
      'size_id': o['target_id'],
      'price': o['price'],
      'is_available': o['is_available'],
    };
    final branches = byBranch.keys.toList()..sort();
    return {
      'org_active': item['is_active'] ?? true,
      'branches': [
        for (final b in branches)
          {
            'branch_id': b,
            'sizes': [
              for (final o in byBranch[b]!)
                if (o['scope'] == 'branch') size(o),
            ],
            'channels': () {
              final byChannel = <String, List<MockRow>>{};
              for (final o in byBranch[b]!) {
                if (o['scope'] == 'branch_channel') {
                  byChannel
                      .putIfAbsent(o['channel'] as String, () => [])
                      .add(o);
                }
              }
              final names = byChannel.keys.toList()..sort();
              return [
                for (final c in names)
                  {
                    'channel': c,
                    'sizes': [for (final o in byChannel[c]!) size(o)],
                  },
              ];
            }(),
          },
      ],
    };
  }

  List<String> _copiesOf(String itemId) {
    final copies = _items.where(
      (i) => i['recipe_source_item_id'] == itemId && i['deleted_at'] == null,
    )..sort((a, b) => compareJson(a['name'], b['name']));
    return [for (final c in copies) c['id'] as String];
  }

  /// `MenuItemFull`: the legacy `sizes` (no `one_size`) and `all_sizes`.
  Map<String, Object?> menuItemFull(MockRow item) {
    final all = [
      for (final s in _data.sizesOf(item['id'] as String))
        {
          'id': s['id'],
          'menu_item_id': s['menu_item_id'],
          'label': s['label'],
          'price_override': _data.priceOf(s, item),
          'is_active': s['is_active'] ?? true,
        },
    ];
    return {
      ...item,
      'sizes': [
        for (final s in all)
          if (s['label'] != oneSize) s,
      ],
      'all_sizes': all,
      'addon_slots': const <Object?>[],
      'allowed_addon_ids': const <Object?>[],
      'optional_fields': const <Object?>[],
      'recipes': const <Object?>[],
      'recipe_steps': steps(item['id'] as String),
    };
  }

  // ── writing ──────────────────────────────────────────────────────────

  void _bump() => _revision++;

  /// `PUT /menu-items/{id}/sizes`: upsert by label, drop the rest (their
  /// lines go too), re-expand bases, rules and copies.
  void putSizes(MockRequest req, MockRow item) {
    final itemId = item['id'] as String;
    final incoming = ((req.json['sizes'] as List?) ?? const [])
        .cast<Map<String, Object?>>();
    if (!incoming.any((s) => s['is_active'] != false)) {
      _bad(
        'A menu item must keep at least one active size — that is where its '
        'price lives.',
      );
    }
    final seen = <String>{};
    for (final s in incoming) {
      final label = s['label'];
      if (label is! String) {
        _bad('Json deserialize error: missing field `label`');
      }
      if (!seen.add(label)) _bad("Duplicate size label '$label' in request");
      final price = s['price'];
      if (price is! int) _bad('Json deserialize error: invalid type: price');
    }
    final existing = _data.sizesOf(itemId);
    for (final (n, s) in incoming.indexed) {
      final label = s['label']! as String;
      final row = existing.where((e) => e['label'] == label).firstOrNull;
      final patch = {
        'price_override': s['price'],
        'sort': (s['sort'] as num?)?.toInt() ?? n,
        'is_active': s['is_active'] ?? true,
      };
      if (row != null) {
        row.addAll(patch);
      } else {
        _sizes.insert({
          'menu_item_id': itemId,
          'label': label,
          'base_id': null,
          ...patch,
        }, timestamps: false);
      }
    }
    for (final e in existing) {
      if (seen.contains(e['label'])) continue;
      _lines.removeWhere((l) => l['size_id'] == e['id']);
      _sizes.delete(e['id'] as String);
    }
    final active = [
      for (final s in _data.sizesOf(itemId))
        if (s['is_active'] != false) _data.priceOf(s, item),
    ];
    if (active.isNotEmpty) {
      item['base_price'] = active.reduce((a, b) => a < b ? a : b);
    }
    _data.rebuildItem(itemId);
    _rebuildCopies(itemId);
    _bump();
  }

  void _rebuildCopies(String sourceId) {
    for (final c in _copiesOf(sourceId)) {
      _data.rebuildItem(c);
    }
  }

  ({MockRow size, MockRow item}) _size(MockRequest req, String sizeId) {
    final size = _sizes.find(sizeId);
    final it = size == null
        ? null
        : _items.find(size['menu_item_id'] as String);
    if (size == null || it == null || it['deleted_at'] != null) {
      req.notFound('Size not found');
    }
    req.requireSameOrg(it['org_id'] as String?);
    return (size: size, item: it);
  }

  void _checkIngredient(String org, Object? id) {
    final ing = id is String ? db[MenuTables.ingredients].find(id) : null;
    if (ing == null || ing['org_id'] != org) {
      _bad('Ingredient not found in this organization');
    }
  }

  /// `PUT /menu-item-sizes/{size_id}/recipe`: the size's own lines.
  Map<String, Object?> putSizeRecipe(MockRequest req, String sizeId) {
    final (:size, :item) = _size(req, sizeId);
    if (item['recipe_source_item_id'] != null) {
      req.conflict("This item's recipe follows another item; unlink it first");
    }
    final lines = ((req.json['lines'] as List?) ?? const [])
        .cast<Map<String, Object?>>();
    final seen = <Object?>{};
    for (final l in lines) {
      if (!seen.add(l['ingredient_id'])) _bad('Duplicate ingredient in recipe');
      _checkIngredient(item['org_id'] as String, l['ingredient_id']);
      final q = l['quantity'];
      if (q is! num || q <= 0) _bad('Quantity must be more than 0');
    }
    // What each own line stores now: one sent back unchanged keeps it.
    final before = {
      for (final l in _lines.where(
        (l) =>
            l['size_id'] == sizeId &&
            (l['source'] == null || l['source'] == 'own'),
      ))
        l['ingredient_id']: jsNumber('${l['quantity']}'),
    };
    _lines.removeWhere(
      (l) =>
          l['size_id'] == sizeId &&
          (l['source'] == null ||
              l['source'] == 'own' ||
              seen.contains(l['ingredient_id'])),
    );
    for (final (n, l) in lines.indexed) {
      _lines.insert({
        'size_id': sizeId,
        'menu_item_id': item['id'],
        'ingredient_id': l['ingredient_id'],
        'quantity': fmtQty(
          _data.storedOf(
                l['ingredient_id']! as String,
                l['quantity']! as num,
                '${l['unit']}',
                '${l['unit']}',
                before[l['ingredient_id']],
              ) ??
              l['quantity']! as num,
        ),
        'unit': l['unit'],
        'source': 'own',
        'sort': n,
      }, timestamps: false);
    }
    _data.rebuildItem(item['id'] as String);
    _rebuildCopies(item['id'] as String);
    _bump();
    final out = _data.linesOf(sizeId);
    final cost = _data.costOf(out);
    return {
      'size_id': sizeId,
      'recipe': [for (final l in out) lineOut(l, l['id'] as String)],
      'cost_piastres': out.isEmpty ? null : cost.cost,
      'cost_incomplete': out.isEmpty ? false : cost.incomplete,
      'catalog_revision': _revision,
    };
  }

  /// `PUT /menu-item-sizes/{size_id}/base`.
  Map<String, Object?> putSizeBase(MockRequest req, String sizeId) {
    final (:size, :item) = _size(req, sizeId);
    final baseId = req.json['base_id'] as String?;
    if (item['recipe_source_item_id'] != null && baseId != null) {
      req.conflict("This item's recipe follows another item; unlink it first");
    }
    if (baseId != null) {
      final base = db[MenuTables.bases].find(baseId);
      if (base == null ||
          base['org_id'] != item['org_id'] ||
          base['deleted_at'] != null) {
        _bad('Recipe base not found in this organization');
      }
    }
    size['base_id'] = baseId;
    final changed = _data.rebuildItem(item['id'] as String);
    _bump();
    return {
      'size_id': sizeId,
      'base_id': baseId,
      'sizes_changed': changed,
      'catalog_revision': _revision,
    };
  }

  /// `PUT /menu-items/{id}/modifier-groups`: the attachment set (the item's
  /// own Options group is neither detached nor re-attached). Omitted or null
  /// changes nothing; `[]` detaches every group.
  void putAttachments(MockRequest req, MockRow item) {
    final raw = req.json['groups'];
    if (raw == null) return;
    final itemId = item['id'] as String;
    final org = item['org_id'] as String;
    final groups = (raw as List).cast<Map<String, Object?>>();
    final seen = <String>{};
    for (final a in groups) {
      final gid = a['group_id'] as String?;
      if (gid == null || !seen.add(gid)) {
        _bad('Duplicate group in attach-set');
      }
      final g = _groups.find(gid);
      if (g == null || g['org_id'] != org) {
        _bad('One or more modifier groups do not exist in this organization');
      }
    }
    final own = optionsGroup(itemId)?['id'];
    final next = <Map<String, Object?>>[];
    for (final (n, a) in groups.indexed) {
      final gid = a['group_id']! as String;
      if (gid == own) continue;
      final g = _groups.find(gid)!;
      final attachedHere = _links.firstWhere(
        (l) => l['menu_item_id'] == itemId && l['group_id'] == gid,
      );
      if (g['is_item_options'] == true && attachedHere == null) {
        _bad(
          '"${g['name']}" is another item\'s own options, not a group that '
          'can be attached',
        );
      }
      final included = a['included_option_ids'] as List?;
      if (included != null) {
        final ids = {for (final o in _options(g)) o['id']};
        if (!included.every(ids.contains)) {
          _bad('included_option_ids must be options of the group');
        }
      }
      next.add({
        'id': attachedHere?['id'] ?? db.newId(MenuTables.groupLinks),
        'menu_item_id': itemId,
        'group_id': gid,
        'sort': (a['sort'] as num?)?.toInt() ?? n,
        'min_override': (a['min_override'] as num?)?.toInt(),
        'max_override': (a['max_override'] as num?)?.toInt(),
        'is_required_override': a['is_required_override'] as bool?,
        'included_option_ids': included,
      });
    }
    _links.removeWhere(
      (l) => l['menu_item_id'] == itemId && l['group_id'] != own,
    );
    for (final l in next) {
      _links.insert(l, timestamps: false);
    }
    _bump();
  }

  /// `PUT /menu-items/{id}/options`: the item's own priced options. A
  /// missing recipe leaves an option's lines as they are; `[]` clears them.
  List<Map<String, Object?>> putItemOptions(MockRequest req, MockRow item) {
    final itemId = item['id'] as String;
    final org = item['org_id'] as String;
    final incoming = ((req.json['options'] as List?) ?? const [])
        .cast<Map<String, Object?>>();
    for (final o in incoming) {
      if (o['name'] is! String) {
        _bad('Json deserialize error: missing field `name`');
      }
      if (o['price'] is! int) {
        _bad('Json deserialize error: invalid type: price');
      }
      final recipe = (o['recipe'] as List?)?.cast<Map<String, Object?>>();
      final seen = <Object?>{};
      for (final l in recipe ?? const <Map<String, Object?>>[]) {
        if (!seen.add(l['ingredient_id'])) {
          _bad('Duplicate ingredient in an option recipe');
        }
        _checkIngredient(org, l['ingredient_id']);
      }
    }
    var g = optionsGroup(itemId);
    if (g == null) {
      g = _groups.insert({
        'org_id': org,
        'name': 'Options',
        'name_translations': const <String, Object?>{},
        'selection_type': 'multi',
        'min_selections': 0,
        'max_selections': null,
        'is_required': false,
        'is_active': true,
        'effect': 'none',
        'legacy_addon_type': null,
        'sort': _groups.length,
        'swap_category_id': null,
        'swap_category_slug': null,
        'is_item_options': true,
        'options': <Map<String, Object?>>[],
      });
      _links.insert({
        'menu_item_id': itemId,
        'group_id': g['id'],
        'sort': 0,
        'included_option_ids': null,
        'legacy_origin': 'options',
      }, timestamps: false);
    }
    final existing = _options(g);
    final byId = {for (final o in existing) o['id']: o};
    final kept = <Map<String, Object?>>[];
    for (final (n, o) in incoming.indexed) {
      final current = byId[o['id']];
      final row =
          current ??
          <String, Object?>{
            'id': db.newId('modifier_options'),
            'name_translations': const <String, Object?>{},
            'is_default': false,
            'replaces_ingredient_id': null,
            'recipe': const <Object?>[],
          };
      row
        ..['name'] = o['name']
        ..['price'] = o['price']
        ..['is_active'] = o['is_active'] ?? true
        ..['sort'] = n;
      final recipe = (o['recipe'] as List?)?.cast<Map<String, Object?>>();
      if (recipe != null) {
        final before = ((row['recipe'] as List?) ?? const [])
            .cast<Map<String, Object?>>();
        row['recipe'] = [
          for (final l in recipe)
            () {
              final id = l['ingredient_id']! as String;
              final sent = (l['quantity'] as num?)?.toDouble() ?? 0;
              final prev = before
                  .where(
                    (b) =>
                        b['ingredient_id'] == id &&
                        b['size_label'] == l['size_label'],
                  )
                  .firstOrNull?['quantity'];
              final q =
                  _data.storedOf(
                    id,
                    sent,
                    '${l['unit']}',
                    '${l['unit']}',
                    prev as num?,
                  ) ??
                  sent;
              return <String, Object?>{
                'ingredient_id': id,
                'ingredient_name': _data.ingredientName(id),
                'quantity': q,
                'usable_quantity': _data.usableOf(id, q),
                'unit': l['unit'],
                'size_label': l['size_label'],
              };
            }(),
        ];
      }
      kept.add(row);
    }
    g['options'] = kept;
    _bump();
    return _itemOptionsOut(g);
  }

  /// `PUT /recipes/steps/{id}`: every step resolved before anything is
  /// written.
  List<Map<String, Object?>> putSteps(MockRequest req, MockRow item) {
    final itemId = item['id'] as String;
    final input = ((req.json['steps'] as List?) ?? const [])
        .cast<Map<String, Object?>>();
    if (input.length > 40) _bad('At most 40 steps');
    String? clean(Object? s) {
      final t = (s as String?)?.trim();
      return t == null || t.isEmpty ? null : t;
    }

    final rows = <Map<String, Object?>>[];
    for (final (i, s) in input.indexed) {
      final n = i + 1;
      final note = clean(s['note']);
      final noteAr = clean(s['note_ar']);
      if ((note?.length ?? 0) > 280 || (noteAr?.length ?? 0) > 280) {
        _bad("Step $n's note is too long");
      }
      switch (s['kind']) {
        case 'preset':
          final slug = clean(s['preset_slug']);
          if (slug == null) _bad('Step $n needs a preset');
          final p = db[MenuTables.stepPresets].find(slug);
          if (p == null || p['is_active'] == false) {
            _bad("Step $n: no such step '$slug'");
          }
          rows.add({
            'kind': 'preset',
            'preset_slug': slug,
            'name': null,
            'name_ar': null,
            'note': note,
            'note_ar': noteAr,
          });
        case 'custom':
          final title = clean(s['title']);
          final titleAr = clean(s['title_ar']);
          if (title == null && titleAr == null) _bad('Step $n needs a name');
          if ((title?.length ?? 0) > 120 || (titleAr?.length ?? 0) > 120) {
            _bad("Step $n's name is too long");
          }
          rows.add({
            'kind': 'custom',
            'preset_slug': null,
            'name': title ?? titleAr,
            'name_ar': titleAr ?? title,
            'note': note,
            'note_ar': noteAr,
          });
        default:
          _bad("Step $n: unknown kind '${s['kind']}'");
      }
    }
    _steps.removeWhere((s) => s['menu_item_id'] == itemId);
    for (final (i, r) in rows.indexed) {
      _steps.insert({
        'menu_item_id': itemId,
        'position': i + 1,
        ...r,
      }, timestamps: false);
    }
    return steps(itemId);
  }

  /// `RecipeLinkInfo` of [item].
  Map<String, Object?> linkInfo(MockRow item) {
    final itemId = item['id'] as String;
    final sourceId = item['recipe_source_item_id'] as String?;
    final source = sourceId == null ? null : _items.find(sourceId);
    bool? inSync;
    if (source != null) {
      String fingerprint(String id, Set<String> labels) => [
        for (final s in _data.sizesOf(id))
          if (labels.contains(s['label']))
            for (final l in _data.linesOf(s['id'] as String))
              '${s['label']}|${l['ingredient_id']}|${jsNumber('${l['quantity']}')}|${l['unit']}',
      ].join(',');
      final labels = {
        for (final s in _data.sizesOf(itemId)) s['label'] as String,
      };
      inSync = fingerprint(itemId, labels) == fingerprint(sourceId!, labels);
    }
    return {
      'menu_item_id': itemId,
      'recipe_source_item_id': sourceId,
      'recipe_source_item_name': source?['name'],
      'linked_copy_ids': _copiesOf(itemId),
      'in_sync': inSync,
    };
  }

  /// `DELETE /menu-items/{id}/recipe-link`: the linked lines become own.
  void unlink(MockRow item) {
    if (item['recipe_source_item_id'] == null) return;
    item['recipe_source_item_id'] = null;
    for (final l in _lines.where(
      (l) => l['menu_item_id'] == item['id'] && l['source'] == 'linked',
    )) {
      l['source'] = 'own';
    }
    _bump();
  }

  /// `PATCH /menu-items/{id}`: translations merge (emptying a language never
  /// removes it); `image_url` only when the key is sent.
  void patchItem(MockRequest req, MockRow item) {
    final b = req.json;
    if (b.containsKey('name')) {
      final name = b['name'];
      if (name is! String || name.trim().isEmpty) _bad('Name is required');
      item['name'] = name;
    }
    Map<String, Object?> merged(Object? current, Object? next) => {
      ...((current as Map?)?.cast<String, Object?>() ?? const {}),
      for (final e
          in ((next as Map?)?.cast<String, Object?>() ?? const {}).entries)
        if (e.value is String && (e.value! as String).isNotEmpty)
          e.key: e.value,
    };
    if (b['name_translations'] != null) {
      item['name_translations'] = merged(
        item['name_translations'],
        b['name_translations'],
      );
    }
    if (b.containsKey('description')) item['description'] = b['description'];
    if (b['description_translations'] != null) {
      item['description_translations'] = merged(
        item['description_translations'],
        b['description_translations'],
      );
    }
    if (b.containsKey('category_id')) {
      final cat = b['category_id'] as String?;
      if (cat != null && db[MenuTables.categories].find(cat) == null) {
        _bad('Category not found');
      }
      item['category_id'] = cat;
    }
    if (b['is_active'] is bool) item['is_active'] = b['is_active'];
    if (b.containsKey('image_url')) {
      item['image_url'] = b['image_url'];
      if (b['image_url'] == null) item['image'] = null;
    }
    if (b['base_price'] is int) item['base_price'] = b['base_price'];
    item['updated_at'] = db.nowIso;
    _bump();
  }

  /// `POST /menu-items/{id}/duplicate`: a deep copy named "… (Copy)": sizes,
  /// own recipe lines, attachments, own options and price overrides (not the
  /// steps, as the backend).
  MockRow duplicate(MockRow src) {
    final srcId = src['id'] as String;
    final copy = _items.insert({
      ...src,
      'id': null,
      'name': '${src['name']} (Copy)',
      'recipe_source_item_id': null,
      'meal': null,
      'created_at': null,
      'updated_at': null,
    });
    final copyId = copy['id'] as String;
    final sizeMap = <String, String>{};
    for (final s in _data.sizesOf(srcId)) {
      final row = _sizes.insert({
        ...s,
        'id': null,
        'menu_item_id': copyId,
      }, timestamps: false);
      sizeMap[s['id'] as String] = row['id'] as String;
      for (final l in _data.linesOf(s['id'] as String)) {
        if (l['source'] != null && l['source'] != 'own') continue;
        _lines.insert({
          ...l,
          'id': null,
          'size_id': row['id'],
          'menu_item_id': copyId,
        }, timestamps: false);
      }
    }
    final own = optionsGroup(srcId);
    for (final l in _links.where((l) => l['menu_item_id'] == srcId)) {
      var gid = l['group_id'];
      if (gid == own?['id']) {
        final g = _groups.insert({
          ...own!,
          'id': null,
          'options': [
            for (final o in _options(own))
              {...o, 'id': db.newId('modifier_options')},
          ],
        });
        gid = g['id'];
      }
      _links.insert({
        ...l,
        'id': null,
        'menu_item_id': copyId,
        'group_id': gid,
      }, timestamps: false);
    }
    final overrides = db[MenuTables.priceOverrides];
    for (final o in overrides.where(
      (o) => sizeMap.containsKey(o['target_id']),
    )) {
      overrides.insert({
        ...o,
        'id': null,
        'target_id': sizeMap[o['target_id']],
      }, timestamps: false);
    }
    _data.rebuildItem(copyId);
    _bump();
    return copy;
  }

  /// `PUT /menu-items/{id}/meal`: both or neither; only an item, only into a
  /// slot that admits it.
  MockResponse putMeal(MockRequest req) {
    MockResponse invalid(String reason) =>
        MockResponse.error(400, reason, code: 'MEAL_TARGET_INVALID');
    final it = _items.find(req.param('id'));
    if (it == null || it['org_id'] != req.orgId || it['deleted_at'] != null) {
      return MockResponse.notFound('Menu item not found');
    }
    final comboId = req.json['combo_id'] as String?;
    final slotId = req.json['slot_id'] as String?;
    if ((comboId == null) != (slotId == null)) {
      return invalid('Give both the combo and its slot, or neither.');
    }
    if (comboId != null) {
      if ((it['kind'] ?? 'item') != 'item') {
        return invalid('Only an item can be made a meal.');
      }
      final combo = _items.find(comboId);
      final spec = db[comboSpecsTable].find(comboId);
      final slot = ((spec?['slots'] as List?) ?? const [])
          .cast<Map<String, Object?>>()
          .where((s) => s['id'] == slotId)
          .firstOrNull;
      final admits =
          combo != null &&
          combo['kind'] == 'combo' &&
          combo['deleted_at'] == null &&
          combo['org_id'] == it['org_id'] &&
          slot != null &&
          ((slot['choices'] as List?) ?? const [])
              .cast<Map<String, Object?>>()
              .any(
                (c) =>
                    c['menu_item_id'] == it['id'] ||
                    (c['menu_item_id'] == null &&
                        c['category_id'] != null &&
                        c['category_id'] == it['category_id']),
              );
      if (!admits) return invalid('That combo has no slot for this item.');
    }
    it['meal'] = comboId == null
        ? null
        : {'combo_id': comboId, 'slot_id': slotId};
    _bump();
    return MockResponse.empty();
  }

  // ── preview ──────────────────────────────────────────────────────────

  String? _swapSlug(MockRow g) {
    final slug = g['swap_category_slug'] as String?;
    if (g['effect'] == 'swaps' && slug != null) return slug;
    return switch (g['legacy_addon_type']) {
      'milk_type' => 'milk',
      'coffee_type' => 'coffee_bean',
      _ => null,
    };
  }

  String _slugOf(String? ingredientId) =>
      (ingredientId == null
          ? null
          : _data.ingredient(ingredientId)?['category_slug'] as String?) ??
      '';

  bool _isPackaging(String? ingredientId) {
    final cat = ingredientId == null
        ? null
        : _data.ingredient(ingredientId)?['category_id'];
    final row = cat == null
        ? null
        : db[MenuTables.ingredientCategories].find(cat as String);
    return row?['is_packaging'] == true || row?['slug'] == 'packaging';
  }

  /// `POST /menu-items/{id}/preview`: the price, the deductions, the cost
  /// and the swap groups' defaults of one configuration of the saved item.
  Map<String, Object?> preview(MockRequest req, MockRow item) {
    final itemId = item['id'] as String;
    final body = req.json;
    final quantity = ((body['quantity'] as num?)?.toInt() ?? 1).clamp(1, 999);
    final dineIn = body['service_mode'] == 'dine_in';
    final active = [
      for (final s in _data.sizesOf(itemId))
        if (s['is_active'] != false) s,
    ];
    final wanted = body['size_label'] as String?;
    final size = wanted == null
        ? active.firstOrNull
        : active.where((s) => s['label'] == wanted).firstOrNull;
    if (wanted != null && size == null) {
      _bad("Unknown size '$wanted' for this item");
    }
    final base = size == null
        ? (item['base_price'] as int? ?? 0)
        : _data.priceOf(size, item);
    final sizeLines = size == null
        ? const <MockRow>[]
        : _data.linesOf(size['id'] as String);

    // Attached groups (by sort) and their offered options.
    final own = optionsGroup(itemId);
    final links = _links.where((l) => l['menu_item_id'] == itemId)
      ..sort((a, b) => ((a['sort'] as int?) ?? 0) - ((b['sort'] as int?) ?? 0));
    final defaults = <String, String>{};
    final optionIndex = <String, (MockRow, Map<String, Object?>)>{};
    final warnings = <Map<String, Object?>>[];
    for (final l in links) {
      final g = _groups.find(l['group_id'] as String);
      if (g == null) continue;
      for (final o in _options(g)) {
        if (o['is_active'] == true && (g == own || _included(l, o))) {
          optionIndex[o['id'] as String] = (g, o);
        }
      }
      final slug = _swapSlug(g);
      if (slug == null || g == own) continue;
      final line = sizeLines
          .where((x) => _slugOf(x['ingredient_id'] as String?) == slug)
          .firstOrNull;
      if (line == null) {
        warnings.add({
          'rule': 'F4',
          'message':
              '"${g['name']}" swaps the drink\'s $slug but this recipe has no '
              '$slug line: no swap, no default, full option price charged',
        });
        continue;
      }
      for (final o in _options(g)) {
        if (o['is_active'] != true || !_included(l, o)) continue;
        final recipe = ((o['recipe'] as List?) ?? const [])
            .cast<Map<String, Object?>>();
        if (o['replaces_ingredient_id'] == line['ingredient_id'] ||
            recipe.any((r) => r['ingredient_id'] == line['ingredient_id'])) {
          defaults[g['id'] as String] = o['id'] as String;
          break;
        }
      }
    }

    // Price and the chosen options' lines.
    final options = <Map<String, Object?>>[];
    final swaps = <String, Map<String, Object?>>{};
    final extra = <Map<String, Object?>>[];
    for (final id
        in ((body['option_ids'] as List?) ?? const []).cast<String>()) {
      final hit = optionIndex[id];
      if (hit == null) _bad('Option $id is not offered on this item');
      final (g, o) = hit;
      final slug = _swapSlug(g);
      final recipe = ((o['recipe'] as List?) ?? const [])
          .cast<Map<String, Object?>>();
      final def = defaults[g['id']];
      if (slug != null && def != null) {
        final d = _options(g).firstWhere((x) => x['id'] == def);
        options.add({
          'option_id': id,
          'name': o['name'],
          'price_delta': (o['price']! as int) - (d['price']! as int),
          'reason': 'swap over ${d['name']}',
        });
        if (id != def && recipe.isNotEmpty) {
          swaps[slug] = {...recipe.first, 'from': o};
        }
      } else {
        options.add({
          'option_id': id,
          'name': o['name'],
          'price_delta': o['price'],
          'reason': recipe.isEmpty ? 'none' : 'adds',
        });
        extra.addAll(recipe);
      }
    }
    final unit =
        base + options.fold<int>(0, (s, o) => s + (o['price_delta']! as int));

    // Deductions.
    final deductions = <Map<String, Object?>>[];
    void add(
      Map<String, Object?> l,
      String source, {
      String? note,
      String? ingredientId,
    }) {
      final id = ingredientId ?? l['ingredient_id'] as String?;
      final packaging = _isPackaging(id);
      final skipped = dineIn && packaging;
      deductions.add({
        'ingredient_id': id,
        'name': _data.ingredientName(id ?? ''),
        'category_slug': _slugOf(id),
        'quantity': jsNumber('${l['quantity']}') * quantity,
        'unit': l['unit'],
        'source': packaging ? 'packaging' : source,
        'note': skipped ? 'skipped on dine-in' : note,
        'skipped': skipped,
      });
    }

    for (final l in sizeLines) {
      final slug = _slugOf(l['ingredient_id'] as String?);
      final swap = swaps[slug];
      if (swap != null) {
        add(
          l,
          'swap',
          ingredientId: swap['ingredient_id'] as String?,
          note:
              'swapped from ${_data.ingredientName(l['ingredient_id']! as String)}',
        );
      } else {
        add(l, 'recipe');
      }
    }
    for (final l in extra) {
      add(l, 'option');
    }

    // Cost over the deducted lines.
    var cost = 0.0;
    var missing = false;
    for (final d in deductions) {
      if (d['skipped'] == true) continue;
      final cpu = _data.ingredient(
        (d['ingredient_id'] as String?) ?? '',
      )?['cost_per_unit'];
      if (cpu is! num) {
        missing = true;
        continue;
      }
      cost += cpu * (d['quantity']! as num);
    }
    final total = unit * quantity;
    final costTotal = jsRound(cost);
    return {
      'size_label': size?['label'],
      'quantity': quantity,
      'price': {'base': base, 'options': options, 'total': total},
      'deductions': deductions,
      'cost': {
        'total': costTotal,
        'cost_missing': missing,
        'margin_pct': missing || total <= 0
            ? null
            : (total - costTotal) / total,
      },
      'warnings': warnings,
      'defaults': defaults,
    };
  }

  // ── combos (the combos area's tables) ─────────────────────────────────

  List<MockRow> combos(String? org) => _items.query(
    where: (i) =>
        i['kind'] == 'combo' && i['deleted_at'] == null && i['org_id'] == org,
    sort: 'name',
  );

  List<Map<String, Object?>> _slots(String comboId) =>
      ((db[comboSpecsTable].find(comboId)?['slots'] as List?) ?? const [])
          .cast<Map<String, Object?>>();

  Map<String, Object?> comboSummary(MockRow c) => {
    'id': c['id'],
    'name': c['name'],
    'name_translations': c['name_translations'] ?? const <String, Object?>{},
    'category_id': c['category_id'],
    'image_url': c['image_url'],
    'price': c['base_price'],
    'is_active': c['is_active'],
    'is_fixed': _slots(
      c['id'] as String,
    ).every((s) => ((s['choices'] as List?) ?? const []).length <= 1),
    'available_now': c['is_active'] == true,
    'slot_count': _slots(c['id'] as String).length,
    'window_count': 0,
    'warning_count': 0,
    'margin_default': null,
  };

  Map<String, Object?> combo(MockRow c) {
    final price = c['base_price'] as int? ?? 0;
    return {
      ...comboSummary(c),
      'kind': 'combo',
      'description': c['description'],
      'description_translations':
          c['description_translations'] ?? const <String, Object?>{},
      'created_at': c['created_at'],
      'updated_at': c['updated_at'],
      'slots': _slots(c['id'] as String),
      'windows': const <Object?>[],
      'economics': {
        'price': price,
        'list_default': price,
        'list_min': price,
        'list_max': price,
        'saving_default': 0,
        'warnings': const <Object?>[],
      },
    };
  }
}
