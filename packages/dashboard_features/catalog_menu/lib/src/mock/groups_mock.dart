/// Mock handlers of the `groups` unit: choice groups (groups, options, usage,
/// option recipes), the backend's way (`MadarRust/src/menu/modifiers.rs`).
///
/// Data: the core seed's Milk and Extras groups (with the area seed's option
/// recipes) plus four shared groups Sabah Coffee also runs, loaded once per db
/// by [GroupsSeed]: Coffee beans (swaps the beans; espresso drinks),
/// Sweetness (a note on Turkish coffee), Toppings (adds syrup with per-size
/// amounts; Frappé and Iced Mocha) and Serving cup (switched off).
///
/// Endpoints (each refuses like the backend: `menu.items.read` /
/// `menu.items.edit`, the org guard, 404s, the 400s of its validation):
/// - `GET /modifier-groups/{gid}/usage`
/// - `POST /modifier-groups`, `PATCH|DELETE /modifier-groups/{gid}`
/// - `POST /modifier-groups/{gid}/options`,
///   `PATCH|DELETE /modifier-options/{oid}`, `PUT /modifier-options/{oid}/recipe`
///
/// `GET /modifier-groups` is the shared read (`shared_mock.dart`).
///
/// Fallbacks, registered only when no unit before this one answers them (the
/// items and studio units own them): `GET /menu-items`, `GET /menu-items/{id}`,
/// `GET /menu-items/{id}/studio` and `PUT /menu-items/{id}/modifier-groups`.
/// The attachments live in [MenuTables.groupLinks] with the per-item override
/// fields of `GroupAttachInput` (`min_override`, `max_override`,
/// `is_required_override`, `included_option_ids`).
library;

import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';
import '../shared/menu_text.dart';

const String _read = 'menu.items.read';
const String _edit = 'menu.items.edit';

/// The swap families old tills understand (`is_swap_family`).
const Set<String> _magicTypes = {'milk_type', 'coffee_type'};

void registerGroupsMocks(MockServer server, MockDb db) {
  GroupsSeed.loadInto(db);
  final b = GroupsBackend(db);

  // GET /modifier-groups/{gid}/usage (menu_items read).
  server.on('GET', '/modifier-groups/{gid}/usage', (req) {
    req.requireCap(_read);
    final g = b.group(req.param('gid'));
    req.requireSameOrg(g['org_id'] as String?);
    return MockResponse.ok(b.usage(g));
  });

  // POST /modifier-groups (menu_items update).
  server.on('POST', '/modifier-groups', (req) {
    req.requireCap(_edit);
    final org = req.orgId;
    if (org == null) {
      req.fail(
        MockResponse.forbidden('A super admin must scope this to an org'),
      );
    }
    return MockResponse.created(b.createGroup(req, org));
  });

  // PATCH /modifier-groups/{gid} (menu_items update).
  server.on('PATCH', '/modifier-groups/{gid}', (req) {
    req.requireCap(_edit);
    final g = b.group(req.param('gid'));
    req.requireSameOrg(g['org_id'] as String?);
    return MockResponse.ok(b.patchGroup(req, g));
  });

  // DELETE /modifier-groups/{gid}: hard, or switched off when an item still
  // offers it or an order used one of its options.
  server.on('DELETE', '/modifier-groups/{gid}', (req) {
    req.requireCap(_edit);
    final g = b.group(req.param('gid'));
    req.requireSameOrg(g['org_id'] as String?);
    b.deleteGroup(g);
    return MockResponse.empty();
  });

  // POST /modifier-groups/{gid}/options (menu_items update).
  server.on('POST', '/modifier-groups/{gid}/options', (req) {
    req.requireCap(_edit);
    final g = b.group(req.param('gid'));
    req.requireSameOrg(g['org_id'] as String?);
    return MockResponse.created(b.createOption(req, g));
  });

  // PATCH /modifier-options/{oid} (menu_items update).
  server.on('PATCH', '/modifier-options/{oid}', (req) {
    req.requireCap(_edit);
    final (g, o) = b.option(req.param('oid'));
    req.requireSameOrg(g['org_id'] as String?);
    return MockResponse.ok(b.patchOption(req, g, o));
  });

  // DELETE /modifier-options/{oid}: hard, or switched off when ordered.
  server.on('DELETE', '/modifier-options/{oid}', (req) {
    req.requireCap(_edit);
    final (g, o) = b.option(req.param('oid'));
    req.requireSameOrg(g['org_id'] as String?);
    b.deleteOption(g, o);
    return MockResponse.empty();
  });

  // PUT /modifier-options/{oid}/recipe: the option's replace-set of lines.
  server.on('PUT', '/modifier-options/{oid}/recipe', (req) {
    req.requireCap(_edit);
    final (g, o) = b.option(req.param('oid'));
    req.requireSameOrg(g['org_id'] as String?);
    return MockResponse.ok(b.putRecipe(req, g, o));
  });

  // ── fallbacks (the items / studio units own these) ─────────────────────

  void fallback(String method, String template, MockHandler handler) {
    if (!server.handles(method, template)) server.on(method, template, handler);
  }

  fallback('GET', '/menu-items', (req) {
    req.requireCap(_read);
    final org = req.q('org_id');
    req.requireSameOrg(org);
    return MockResponse.ok(
      db[MenuTables.menuItems].query(
        filters: {'org_id': org, 'category_id': req.q('category_id')},
        where: (i) => i['deleted_at'] == null,
        sort: 'name',
      ),
    );
  });

  fallback('GET', '/menu-items/{id}', (req) {
    req.requireCap(_read);
    final item = b.item(req.param('id'));
    req.requireSameOrg(item['org_id'] as String?);
    return MockResponse.ok(b.menuItemFull(item));
  });

  fallback('GET', '/menu-items/{id}/studio', (req) {
    req.requireCap(_read);
    final item = b.item(req.param('id'));
    req.requireSameOrg(item['org_id'] as String?);
    return MockResponse.ok(b.studio(item));
  });

  fallback('PUT', '/menu-items/{id}/modifier-groups', (req) {
    req.requireCap(_edit);
    final item = b.item(req.param('id'));
    req.requireSameOrg(item['org_id'] as String?);
    b.putAttachments(req, item);
    return MockResponse.ok(b.studio(item));
  });
}

// ── data ──────────────────────────────────────────────────────────────────

/// One extra option: (key, name, Arabic, piastres, default, lines:
/// (size label or null, ingredient key, quantity), swap ingredient key).
typedef _Opt = (
  String key,
  String name,
  String ar,
  int price,
  bool isDefault,
  List<(String?, String, num)> lines,
  String? swaps,
);

/// One extra group: (key, name, Arabic, selection, min, max, required,
/// effect, legacy type, swap category key, active, options, attached items).
typedef _Group = (
  String key,
  String name,
  String ar,
  String selection,
  int min,
  int? max,
  bool required,
  String effect,
  String legacy,
  String? swapCategory,
  bool active,
  List<_Opt> options,
  List<String> items,
);

const List<_Group> _groups = [
  (
    'beans',
    'Coffee beans',
    'البن',
    'single',
    1,
    1,
    true,
    'swaps',
    'coffee_type',
    'coffee_bean',
    true,
    [
      (
        'house',
        'House blend',
        'الخلطة الأساسية',
        0,
        true,
        [(null, 'house_blend', 1)],
        'house_blend',
      ),
      (
        'ethiopia',
        'Ethiopia Yirgacheffe',
        'إثيوبيا يرغاتشيفي',
        2500,
        false,
        [(null, 'ethiopia', 1)],
        'ethiopia',
      ),
    ],
    ['espresso', 'americano', 'cortado'],
  ),
  (
    'sweetness',
    'Sweetness',
    'درجة السكر',
    'single',
    1,
    1,
    true,
    'none',
    'sweetness',
    null,
    true,
    [
      ('plain', 'Plain', 'سادة', 0, false, [], null),
      ('hint', 'A hint of sugar', 'على الريحة', 0, false, [], null),
      ('medium', 'Medium', 'مظبوط', 0, true, [], null),
      ('sweet', 'Sweet', 'زيادة', 0, false, [], null),
    ],
    ['turkish'],
  ),
  (
    'toppings',
    'Toppings',
    'الإضافات العلوية',
    'multi',
    0,
    2,
    false,
    'adds',
    'toppings',
    null,
    true,
    [
      (
        'caramel',
        'Caramel drizzle',
        'صوص كراميل',
        1000,
        false,
        [(null, 'caramel_syrup', 10), ('Large', 'caramel_syrup', 15)],
        null,
      ),
      (
        'chocolate',
        'Chocolate drizzle',
        'صوص شوكولاتة',
        1000,
        false,
        [(null, 'chocolate_sauce', 10), ('Large', 'chocolate_sauce', 15)],
        null,
      ),
      (
        'cream',
        'Whipped cream',
        'كريمة مخفوقة',
        1500,
        false,
        [(null, 'whipped_cream', 25)],
        null,
      ),
    ],
    ['frappe', 'iced_mocha'],
  ),
  (
    'serving',
    'Serving cup',
    'نوع الكوب',
    'multi',
    0,
    null,
    false,
    'none',
    'serving_cup',
    null,
    false,
    [
      ('mug', 'Ceramic mug', 'كوب سيراميك', 0, true, [], null),
      ('paper', 'Paper cup', 'كوب ورقي', 0, false, [], null),
    ],
    [],
  ),
];

/// Loads the unit's extra groups and their attachments (once per db).
abstract final class GroupsSeed {
  static void loadInto(MockDb db) {
    final groups = db[MenuTables.groups];
    if (groups.find(MenuSeedIds.group('beans')) != null) return;
    final data = CatalogMenuData(db);
    final base = groups.length;
    for (final (n, g) in _groups.indexed) {
      final (
        key,
        name,
        ar,
        selection,
        min,
        max,
        required,
        effect,
        legacy,
        swapCategory,
        active,
        options,
        items,
      ) = g;
      groups.insert({
        'id': MenuSeedIds.group(key),
        'org_id': SeedIds.sabahOrg,
        'name': name,
        'name_translations': {'en': name, 'ar': ar},
        'selection_type': selection,
        'min_selections': min,
        'max_selections': max,
        'is_required': required,
        'is_active': active,
        'effect': effect,
        'legacy_addon_type': legacy,
        'sort': base + n,
        'swap_category_id': swapCategory == null
            ? null
            : MenuSeedIds.ingredientCategory(swapCategory),
        'swap_category_slug': swapCategory,
        'is_item_options': false,
        'options': [
          for (final (s, (okey, oname, oar, price, isDefault, lines, swaps))
              in options.indexed)
            {
              'id': MenuSeedIds.option(key, okey),
              'name': oname,
              'name_translations': {'en': oname, 'ar': oar},
              'price': price,
              'is_default': isDefault,
              'is_active': true,
              'sort': s,
              'replaces_ingredient_id': swaps == null
                  ? null
                  : MenuSeedIds.ingredient(swaps),
              'recipe': [
                for (final (label, ing, qty) in lines)
                  {
                    'ingredient_id': MenuSeedIds.ingredient(ing),
                    'ingredient_name': data.ingredientName(
                      MenuSeedIds.ingredient(ing),
                    ),
                    'quantity': qty.toDouble(),
                    'unit':
                        data.ingredient(MenuSeedIds.ingredient(ing))?['unit'] ??
                        'g',
                    'size_label': label,
                  },
              ],
            },
        ],
      }, timestamps: false);
      final links = db[MenuTables.groupLinks];
      for (final item in items) {
        final itemId = MenuSeedIds.item(item);
        final sort = links.where((l) => l['menu_item_id'] == itemId).length;
        links.insert({
          'id': mockUuid('group-link:$item:$key'),
          'menu_item_id': itemId,
          'group_id': MenuSeedIds.group(key),
          'sort': sort,
        }, timestamps: false);
      }
    }
  }
}

// ── the backend's rules ─────────────────────────────────────────────────

/// The groups backend over the area's tables (one per server).
class GroupsBackend {
  GroupsBackend(this.db);

  final MockDb db;

  MockTable get _groups => db[MenuTables.groups];
  MockTable get _links => db[MenuTables.groupLinks];
  CatalogMenuData get _data => CatalogMenuData(db);

  /// Options of the core seed's groups appear in Sabah's order history (the
  /// till sold them), so the backend only switches them off.
  static final Set<String> _orderedOptions = {
    for (final g in seedGroups)
      for (final o in g.options) MockSeed.optionId(g.key, o.key),
  };

  MockRow group(String gid) =>
      _groups.find(gid) ??
      (throw MockHttpError(MockResponse.notFound('Modifier group not found')));

  MockRow item(String id) {
    final row = db[MenuTables.menuItems].find(id);
    if (row == null || row['deleted_at'] != null) {
      throw MockHttpError(MockResponse.notFound('Menu item not found'));
    }
    return row;
  }

  List<Map<String, Object?>> _options(MockRow g) =>
      (g['options'] as List).cast<Map<String, Object?>>();

  (MockRow, Map<String, Object?>) option(String oid) {
    for (final g in _groups.rows) {
      for (final o in _options(g)) {
        if (o['id'] == oid) return (g, o);
      }
    }
    throw MockHttpError(MockResponse.notFound('Modifier option not found'));
  }

  /// Options as the backend orders them (`ORDER BY sort, name`).
  void _sortOptions(MockRow g) {
    final opts = _options(g)
      ..sort((a, b) {
        final c = ((a['sort'] as int?) ?? 0) - ((b['sort'] as int?) ?? 0);
        return c != 0 ? c : compareJson(a['name'], b['name']);
      });
    g['options'] = opts;
  }

  // ── groups ──────────────────────────────────────────────────────────

  static Never _bad(String reason) =>
      throw MockHttpError(MockResponse.badRequest(reason));

  static void _checkSelection(Object? st) {
    if (st != null && st != 'single' && st != 'multi') {
      _bad("selection_type must be 'single' or 'multi'");
    }
  }

  static void _checkEffect(String effect) {
    if (!const ['none', 'adds', 'swaps'].contains(effect)) {
      _bad("effect must be 'none', 'adds' or 'swaps'");
    }
  }

  /// `category_slug_in_org`: the category's slug, or 400.
  String _categorySlug(String org, Object? categoryId) {
    final c = db[MenuTables.ingredientCategories].find('$categoryId');
    if (c == null || c['org_id'] != org) {
      _bad('Swap category not found in this organization');
    }
    return c['slug'] as String;
  }

  /// `derive_legacy_addon_type`: [requested] is null when the key was not
  /// sent, `(value,)` when it was (value may be null).
  static String? _deriveType(
    String effect,
    String? swapSlug,
    (String?,)? requested,
    String? current,
  ) {
    bool magic(String? t) => t != null && _magicTypes.contains(t);
    if (effect == 'swaps') {
      final wanted = switch (swapSlug) {
        'milk' => 'milk_type',
        'coffee_bean' => 'coffee_type',
        _ => null,
      };
      if (wanted != null) {
        final r = requested?.$1;
        if (r != null && r != wanted) {
          _bad(
            "a group that swaps this category is presented to old tills as "
            "'$wanted', not '$r'",
          );
        }
        return wanted;
      }
      final r = requested?.$1;
      if (r != null && magic(r)) {
        _bad("'$r' swaps milk / coffee beans; pick that category as the swap target");
      }
      if (requested != null && r != null) return r;
      if (magic(current) || current == null) return 'extra';
      return current;
    }
    final r = requested?.$1;
    if (r != null && magic(r)) {
      _bad("'$r' groups swap an ingredient; set effect to 'swaps'");
    }
    if (requested != null) return r;
    if (magic(current)) return 'extra';
    return current;
  }

  static void _forceSwapShape(MockRow g) {
    if (g['effect'] == 'swaps' ||
        _magicTypes.contains(g['legacy_addon_type'])) {
      g['selection_type'] = 'single';
      g['max_selections'] = 1;
      final min = (g['min_selections'] as int?) ?? 0;
      g['min_selections'] = min.clamp(0, 1);
    }
  }

  Map<String, Object?> createGroup(MockRequest req, String org) {
    final b = req.json;
    final name = b['name'];
    final selection = b['selection_type'];
    if (name is! String) _bad('Json deserialize error: missing field `name`');
    if (selection is! String) {
      _bad('Json deserialize error: missing field `selection_type`');
    }
    _checkSelection(selection);
    final cat = b['swap_category_id'];
    final slug = cat == null ? null : _categorySlug(org, cat);
    final effect = b['effect'] as String?;
    String? type = b['legacy_addon_type'] as String?;
    if (effect != null) {
      _checkEffect(effect);
      if (effect == 'swaps' && cat == null) {
        _bad("effect 'swaps' needs swap_category_id");
      }
      if (effect != 'swaps' && cat != null) {
        _bad("swap_category_id is only valid with effect 'swaps'");
      }
      type = _deriveType(effect, slug, (type,), null);
    } else if (cat != null) {
      _bad("swap_category_id is only valid with effect 'swaps'");
    }
    final row = _groups.insert({
      'id': db.newId(MenuTables.groups),
      'org_id': org,
      'name': name,
      'name_translations': b['name_translations'] ?? const <String, Object?>{},
      'selection_type': selection,
      'min_selections': (b['min_selections'] as num?)?.toInt() ?? 0,
      'max_selections': (b['max_selections'] as num?)?.toInt(),
      'is_required': b['is_required'] as bool? ?? false,
      'sort': (b['sort'] as num?)?.toInt() ?? 0,
      'is_active': true,
      'legacy_addon_type': type,
      'effect': effect ?? 'adds',
      'swap_category_id': cat,
      'swap_category_slug': slug,
      'is_item_options': false,
      'options': <Map<String, Object?>>[],
    }, timestamps: false);
    _forceSwapShape(row);
    return row;
  }

  Map<String, Object?> patchGroup(MockRequest req, MockRow g) {
    final b = req.json;
    _checkSelection(b['selection_type']);
    final org = g['org_id'] as String;
    final touches =
        b['effect'] != null ||
        b.containsKey('swap_category_id') ||
        b.containsKey('legacy_addon_type');
    var effect = g['effect'] as String;
    var cat = g['swap_category_id'] as String?;
    var type = g['legacy_addon_type'] as String?;
    String? slug = g['swap_category_slug'] as String?;
    if (touches) {
      effect = (b['effect'] as String?) ?? effect;
      _checkEffect(effect);
      cat = b.containsKey('swap_category_id')
          ? b['swap_category_id'] as String?
          : (effect == 'swaps' ? cat : null);
      if (effect != 'swaps' && cat != null) {
        _bad("swap_category_id is only valid with effect 'swaps'");
      }
      slug = cat == null ? null : _categorySlug(org, cat);
      final requested = b.containsKey('legacy_addon_type')
          ? (b['legacy_addon_type'] as String?,)
          : null;
      final effective = requested == null ? type : requested.$1;
      if (effect == 'swaps' &&
          cat == null &&
          !(effective != null && _magicTypes.contains(effective))) {
        _bad("effect 'swaps' needs swap_category_id");
      }
      type = effect == 'swaps' && cat == null
          ? effective
          : _deriveType(effect, slug, requested, type);
    }
    void set(String key) {
      if (b[key] != null) g[key] = b[key];
    }

    set('name');
    set('name_translations');
    set('selection_type');
    if (b['min_selections'] != null) {
      g['min_selections'] = (b['min_selections'] as num).toInt();
    }
    if (b.containsKey('max_selections')) {
      g['max_selections'] = (b['max_selections'] as num?)?.toInt();
    }
    set('is_required');
    if (b['sort'] != null) g['sort'] = (b['sort'] as num).toInt();
    set('is_active');
    g
      ..['effect'] = effect
      ..['swap_category_id'] = cat
      ..['swap_category_slug'] = slug
      ..['legacy_addon_type'] = type;
    _forceSwapShape(g);
    return g;
  }

  void deleteGroup(MockRow g) {
    final gid = g['id'] as String;
    final attached = _links.rows.any((l) => l['group_id'] == gid);
    final ordered = _options(
      g,
    ).any((o) => _orderedOptions.contains(o['id']));
    if (attached || ordered) {
      g['is_active'] = false;
    } else {
      _groups.delete(gid);
    }
  }

  // ── options ─────────────────────────────────────────────────────────

  void _checkIngredient(String org, Object? id) {
    final ing = db[MenuTables.ingredients].find('$id');
    if (ing == null || ing['org_id'] != org || ing['deleted_at'] != null) {
      _bad("Ingredient not found in this organization's catalog");
    }
  }

  Map<String, Object?> createOption(MockRequest req, MockRow g) {
    final b = req.json;
    final name = b['name'];
    final price = b['price'];
    if (name is! String) _bad('Json deserialize error: missing field `name`');
    if (price is! num) _bad('Json deserialize error: missing field `price`');
    final swaps = b['replaces_ingredient_id'];
    if (swaps != null) _checkIngredient(g['org_id'] as String, swaps);
    final o = <String, Object?>{
      'id': db.newId('modifier_options'),
      'name': name,
      'name_translations': b['name_translations'] ?? const <String, Object?>{},
      'price': price.toInt(),
      'is_default': b['is_default'] as bool? ?? false,
      'is_active': b['is_active'] as bool? ?? true,
      'sort': 0,
      'replaces_ingredient_id': swaps,
      'recipe': <Map<String, Object?>>[],
    };
    _options(g).add(o);
    _sortOptions(g);
    return o;
  }

  Map<String, Object?> patchOption(
    MockRequest req,
    MockRow g,
    Map<String, Object?> o,
  ) {
    final b = req.json;
    final swaps = b['replaces_ingredient_id'];
    if (swaps != null) _checkIngredient(g['org_id'] as String, swaps);
    for (final k in const [
      'name',
      'name_translations',
      'is_default',
      'is_active',
    ]) {
      if (b[k] != null) o[k] = b[k];
    }
    if (b['price'] != null) o['price'] = (b['price'] as num).toInt();
    if (b['sort'] != null) o['sort'] = (b['sort'] as num).toInt();
    if (b.containsKey('replaces_ingredient_id')) {
      o['replaces_ingredient_id'] = swaps;
    }
    _sortOptions(g);
    return o;
  }

  void deleteOption(MockRow g, Map<String, Object?> o) {
    if (_orderedOptions.contains(o['id'])) {
      o['is_active'] = false;
    } else {
      _options(g).remove(o);
    }
  }

  static double _convert(double qty, String from, String to) {
    const factor = {'g': 1.0, 'kg': 1000.0, 'ml': 1.0, 'l': 1000.0, 'pcs': 1.0};
    const family = {
      'g': 'mass',
      'kg': 'mass',
      'ml': 'volume',
      'l': 'volume',
      'pcs': 'count',
    };
    if (family[from] == null || family[from] != family[to]) {
      _bad('cannot convert $from to $to');
    }
    return qty * factor[from]! / factor[to]!;
  }

  List<Map<String, Object?>> putRecipe(
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
      final ing = db[MenuTables.ingredients].find(ingId);
      if (ing == null || ing['org_id'] != org || ing['deleted_at'] != null) {
        _bad("Linked ingredient not found in this organization's catalog");
      }
      final base = ing['unit'] as String;
      final q =
          jsRound(_convert(qty.toDouble(), unit, base) * 1000) / 1000;
      if (qty > 0 && q <= 0) {
        _bad(
          'quantity $qty $unit is too small for base unit $base (rounds to 0)',
        );
      }
      lines.add({
        'ingredient_id': ingId,
        'ingredient_name': ing['name'],
        'quantity': q,
        'unit': base,
        'size_label': label,
      });
    }
    // Stored order: generic lines first, then per size, each by name.
    lines.sort((a, b) {
      final la = a['size_label'] as String?, lb = b['size_label'] as String?;
      if (la == null && lb != null) return -1;
      if (la != null && lb == null) return 1;
      final c = compareJson(la, lb);
      return c != 0 ? c : compareJson(a['ingredient_name'], b['ingredient_name']);
    });
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

  // ── usage ───────────────────────────────────────────────────────────

  /// The swap slug the resolver uses: the explicit category, else the
  /// family's.
  String? _swapSlug(MockRow g) {
    final slug = g['swap_category_slug'] as String?;
    if (g['effect'] == 'swaps' && slug != null) return slug;
    return switch (g['legacy_addon_type']) {
      'milk_type' => 'milk',
      'coffee_type' => 'coffee_bean',
      _ => g['effect'] == 'swaps' ? slug : null,
    };
  }

  bool _included(Map<String, Object?> link, Map<String, Object?> o) {
    final ids = link['included_option_ids'] as List?;
    return ids == null || ids.contains(o['id']);
  }

  /// `GET /modifier-groups/{gid}/usage`: the items offering [g], by name.
  List<Map<String, Object?>> usage(MockRow g) {
    final gid = g['id'] as String;
    final items = db[MenuTables.menuItems];
    final categories = db[MenuTables.categories];
    final slug = _swapSlug(g);
    final rows = <Map<String, Object?>>[];
    for (final l in _links.rows) {
      if (l['group_id'] != gid) continue;
      final item = items.find(l['menu_item_id'] as String);
      if (item == null || item['deleted_at'] != null) continue;
      final options = [
        for (final o in _options(g))
          if (_included(l, o)) o,
      ];
      final cat = item['category_id'] == null
          ? null
          : categories.find(item['category_id'] as String);
      rows.add({
        'item_id': item['id'],
        'item_name': item['name'],
        'item_is_active': item['is_active'],
        'category_id': item['category_id'],
        'category_name': cat?['name'],
        'is_required': l['is_required_override'] ?? g['is_required'],
        'min_selections': l['min_override'] ?? g['min_selections'],
        'max_selections': l['max_override'] ?? g['max_selections'],
        'legacy_origin': null,
        'included_option_ids': l['included_option_ids'],
        'included_option_count': options
            .where((o) => o['is_active'] == true)
            .length,
        'default_option_id': slug == null
            ? null
            : _defaultOption(item, options, slug),
        'warnings': const <Object?>[],
      });
    }
    rows.sort((a, b) {
      final c = compareJson(a['item_name'], b['item_name']);
      return c != 0 ? c : compareJson(a['item_id'], b['item_id']);
    });
    return rows;
  }

  /// The first offered option carrying the recipe's swap-category ingredient,
  /// on the item's first active size that has one.
  String? _defaultOption(
    MockRow item,
    List<Map<String, Object?>> options,
    String slug,
  ) {
    final active =
        options.where((o) => o['is_active'] == true).toList()..sort((a, b) {
          final c = ((a['sort'] as int?) ?? 0) - ((b['sort'] as int?) ?? 0);
          return c != 0 ? c : compareJson(a['name'], b['name']);
        });
    for (final size in _data.sizesOf(item['id'] as String)) {
      if (size['is_active'] != true) continue;
      for (final line in _data.linesOf(size['id'] as String)) {
        final ing = _data.ingredient(line['ingredient_id'] as String);
        if (ing?['category_slug'] != slug) continue;
        for (final o in active) {
          final recipe = ((o['recipe'] as List?) ?? const [])
              .cast<Map<String, Object?>>();
          if (o['replaces_ingredient_id'] == ing!['id'] ||
              recipe.any((r) => r['ingredient_id'] == ing['id'])) {
            return o['id'] as String;
          }
        }
      }
    }
    return null;
  }

  // ── fallbacks ───────────────────────────────────────────────────────

  /// `MenuItemFull`: the legacy `sizes` (without `one_size`, by label) and
  /// `all_sizes`.
  Map<String, Object?> menuItemFull(MockRow item) {
    final all = [
      for (final s in _data.sizesOf(item['id'] as String))
        {
          'id': s['id'],
          'menu_item_id': s['menu_item_id'],
          'label': s['label'],
          'price_override': s['price_override'],
          'is_active': s['is_active'],
        },
    ];
    final legacy = [
      for (final s in all)
        if (s['label'] != oneSize) s,
    ]..sort((a, b) => compareJson(a['label'], b['label']));
    return {
      ...item,
      'sizes': legacy,
      'all_sizes': all,
      'addon_slots': const <Object?>[],
      'allowed_addon_ids': const <Object?>[],
      'optional_fields': const <Object?>[],
      'recipes': const <Object?>[],
    };
  }

  Map<String, Object?> _line(Map<String, Object?> l, String id) {
    final ingId = l['ingredient_id'] as String;
    return {
      'id': id,
      'ingredient_id': ingId,
      'ingredient_name': _data.ingredientName(ingId),
      'quantity': jsNumber('${l['quantity']}'),
      'unit': l['unit'],
      'size_label': l['size_label'],
      'source': l['source'],
      'line_cost_piastres': _data.lineCost(l),
    };
  }

  /// A `StudioAggregate` whose `modifier_groups` are the item's attachments
  /// (the rest is the item's own state; the studio unit serves the full one).
  Map<String, Object?> studio(MockRow item) {
    final itemId = item['id'] as String;
    final links = _links.where((l) => l['menu_item_id'] == itemId)
      ..sort((a, b) => ((a['sort'] as int?) ?? 0) - ((b['sort'] as int?) ?? 0));
    return {
      'id': itemId,
      'org_id': item['org_id'],
      'name': item['name'],
      'name_translations': item['name_translations'],
      'description': item['description'],
      'category_id': item['category_id'],
      'is_active': item['is_active'],
      'catalog_revision': 1,
      'availability': {'branches': const <Object?>[], 'org_active': true},
      'options': const <Object?>[],
      'recipe_steps': const <Object?>[],
      'sizes': [
        for (final s in _data.sizesOf(itemId))
          () {
            final lines = _data.linesOf(s['id'] as String);
            final cost = _data.costOf(lines);
            return {
              'id': s['id'],
              'label': s['label'],
              'price': _data.priceOf(s, item),
              'is_active': s['is_active'],
              'sort': s['sort'] ?? 0,
              'base_id': s['base_id'],
              'cost_piastres': cost.cost,
              'cost_incomplete': cost.incomplete,
              'recipe': [
                for (final l in lines) _line(l, l['id'] as String),
              ],
            };
          }(),
      ],
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
              'max': l['max_override'] ?? g['max_selections'],
              'sort': l['sort'] ?? 0,
              'options': [
                for (final o in _options(g))
                  () {
                    final recipe = ((o['recipe'] as List?) ?? const [])
                        .cast<Map<String, Object?>>();
                    final cost = _data.costOf(recipe);
                    return {
                      'id': o['id'],
                      'name': o['name'],
                      'price': o['price'],
                      'is_active': o['is_active'],
                      'is_default': o['is_default'],
                      'included': _included(l, o),
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

  /// `PUT /menu-items/{id}/modifier-groups`: the item's attachment set.
  void putAttachments(MockRequest req, MockRow item) {
    final itemId = item['id'] as String;
    final org = item['org_id'] as String;
    final groups = (req.json['groups'] as List?) ?? const [];
    final seen = <String>{};
    final next = <Map<String, Object?>>[];
    for (final (n, raw) in groups.cast<Map<String, Object?>>().indexed) {
      final gid = raw['group_id'] as String?;
      final g = gid == null ? null : _groups.find(gid);
      if (g == null || g['org_id'] != org) {
        _bad('Modifier group not found in this organization');
      }
      if (!seen.add(gid!)) _bad('A group can be attached to an item once');
      final included = raw['included_option_ids'] as List?;
      if (included != null) {
        final ids = {for (final o in _options(g)) o['id']};
        if (!included.every(ids.contains)) {
          _bad('included_option_ids must be options of the group');
        }
      }
      final existing = _links.firstWhere(
        (l) => l['menu_item_id'] == itemId && l['group_id'] == gid,
      );
      next.add({
        'id': existing?['id'] ?? db.newId(MenuTables.groupLinks),
        'menu_item_id': itemId,
        'group_id': gid,
        'sort': (raw['sort'] as num?)?.toInt() ?? n,
        'min_override': (raw['min_override'] as num?)?.toInt(),
        'max_override': (raw['max_override'] as num?)?.toInt(),
        'is_required_override': raw['is_required_override'] as bool?,
        'included_option_ids': included,
      });
    }
    _links.removeWhere((l) => l['menu_item_id'] == itemId);
    for (final l in next) {
      _links.insert(l, timestamps: false);
    }
  }
}
