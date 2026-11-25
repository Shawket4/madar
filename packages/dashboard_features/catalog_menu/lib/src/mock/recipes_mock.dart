/// Mock handlers of the `recipes` unit: the recipe builder and the create-
/// ingredient dialog (add-on ingredients, catalog writes).
///
/// Read and write the area's tables through [MenuTables] and
/// [CatalogMenuData] so every unit's numbers agree.
///
/// | route | backend | guards |
/// |---|---|---|
/// | `POST /inventory/orgs/{org_id}/catalog` | `inventory::create_catalog_item` | `inventory.items.create`, org access, unit, name, category in org, unique name |
/// | `GET /recipes/addons/{addon_item_id}` | `recipes::list_addon_ingredients` | `recipes.read`, the add-on's org |
/// | `GET /recipes/book` | `recipes::book::get_recipe_book` | same org, `menu.items.read`, `recipes.read` |
library;

import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';
import '../shared/menu_text.dart';
import 'studio_mock.dart' show StudioBackend;

void registerRecipesMocks(MockServer server, MockDb db) {
  // GET /recipes/book — get_recipe_book: the org first, then the menu read,
  // then recipes.read (on Free the plan's ceiling holds no recipes).
  server.on('GET', '/recipes/book', (req) {
    final org = req.q('org_id');
    if (org == null) {
      req.badRequest('Query deserialize error: missing field `org_id`');
    }
    req.requireSameOrg(org);
    req.requireCap('menu.items.read');
    req.requireCap('recipes.read');
    return MockResponse.ok(
      recipeBook(
        db,
        org: org,
        categoryId: req.q('category_id'),
        search: req.q('search'),
        hasRecipe: req.qBool('has_recipe'),
      ),
    );
  });

  // POST /inventory/orgs/{org_id}/catalog — create_catalog_item: the
  // permission first, then org access, the unit, the name, the category
  // (absent = the org's `general`), then the (org, name) unique index.
  server.on('POST', '/inventory/orgs/{org_id}/catalog', (req) {
    req.requireCap('inventory.items.create');
    final org = req.param('org_id');
    req.requireSameOrg(org);
    final body = req.json;
    final unit = body['unit'];
    if (unit is! String || !ingredientUnits.contains(unit)) {
      req.badRequest('Unit must be one of: g, kg, ml, l, pcs');
    }
    final name = ((body['name'] as String?) ?? '').trim();
    if (name.isEmpty) req.badRequest('name cannot be empty');

    final categories = db[MenuTables.ingredientCategories];
    final categoryId = body['category_id'] as String?;
    final MockRow category;
    if (categoryId != null) {
      final found = categories.find(categoryId);
      if (found == null || found['org_id'] != org) {
        req.badRequest('Category does not belong to this organization');
      }
      category = found;
    } else {
      category =
          categories.firstWhere(
            (c) => c['org_id'] == org && c['slug'] == 'general',
          ) ??
          categories.insert({
            'org_id': org,
            'name': 'General',
            'slug': 'general',
            'sort_order': 0,
            'is_packaging': false,
            'ingredient_count': 0,
          });
    }

    final ingredients = db[MenuTables.ingredients];
    if (ingredients.firstWhere(
          (i) =>
              i['org_id'] == org &&
              i['name'] == name &&
              i['deleted_at'] == null,
        ) !=
        null) {
      req.conflict(
        'An ingredient with this name already exists in the catalog',
      );
    }

    final cost = body['cost_per_unit'];
    final row = ingredients.insert({
      'id': db.newId(MenuTables.ingredients),
      'org_id': org,
      'name': name,
      'category_id': category['id'],
      'category_name': category['name'],
      'category_slug': category['slug'],
      'unit': unit,
      'description': body['description'],
      'cost_per_unit': cost is num ? cost.toDouble() : null,
      'supplier_id': body['supplier_id'],
      'pack_unit': body['pack_unit'],
      'pack_size': body['pack_size'],
      'yield_pct': body['yield_pct'],
      'density_g_per_ml': body['density_g_per_ml'],
      'is_active': true,
    });
    return MockResponse.created(row);
  });

  // GET /recipes/addons/{addon_item_id} — list_addon_ingredients: the
  // add-on's (shared-group option's) all-sizes recipe lines, named by the
  // catalog, by ingredient name (the `addon_item_ingredients` view).
  server.on('GET', '/recipes/addons/{addon_item_id}', (req) {
    req.requireCap('recipes.read');
    final id = req.param('addon_item_id');
    MockRow? group;
    Map<String, Object?>? option;
    for (final g in db[MenuTables.groups].rows) {
      if (g['legacy_addon_type'] == null) continue;
      for (final o in (g['options'] as List).cast<Map<String, Object?>>()) {
        if (o['id'] == id) {
          group = g;
          option = o;
        }
      }
    }
    if (group == null || option == null) {
      req.notFound('Addon item not found');
    }
    if (!req.persona.isPlatform && req.persona.orgId != group['org_id']) {
      req.fail(MockResponse.forbidden('Addon item belongs to a different org'));
    }
    final data = CatalogMenuData(db);
    final lines = <Map<String, Object?>>[];
    for (final (n, l)
        in ((option['recipe'] as List?) ?? const [])
            .cast<Map<String, Object?>>()
            .indexed) {
      if (l['size_label'] != null) continue;
      final ingredientId = l['ingredient_id'] as String;
      if (data.ingredient(ingredientId) == null) continue;
      final q = l['quantity'];
      lines.add({
        'id': mockUuid('option-recipe-line:$id:$n'),
        'addon_item_id': id,
        'org_ingredient_id': ingredientId,
        'ingredient_name': data.ingredientName(ingredientId),
        'unit': l['unit'],
        'quantity_used': q is num ? q.toDouble() : jsParseFloat('$q'),
        'usable_quantity': data.usableOf(ingredientId, q),
      });
    }
    lines.sort(
      (a, b) => compareJson(a['ingredient_name'], b['ingredient_name']),
    );
    return MockResponse.ok(lines);
  });
}

/// `recipes::book::build`: the org's live, non-combo items the filters keep
/// (category, a case-insensitive name search, has a recipe on some size), in
/// menu order (category display order, then name; uncategorised last; then
/// the item name), each laid out as its table: a column per size (by `sort`),
/// a row per (source, ingredient, unit) in the Studio grid's order (own and
/// linked, then base, then rule; first appearance within one), a cell per
/// size with the usable amount and the line's cost, the size's cost rolled
/// up as the Studio rolls it, graded only when complete, and the steps.
Map<String, Object?> recipeBook(
  MockDb db, {
  required String org,
  String? categoryId,
  String? search,
  bool? hasRecipe,
}) {
  final data = CatalogMenuData(db);
  final studio = StudioBackend(db);
  final needle = search?.trim().toLowerCase();
  final items = db[MenuTables.menuItems];
  final liveCategories = {
    for (final c in db[MenuTables.categories].where(
      (c) => c['org_id'] == org && c['deleted_at'] == null,
    ))
      c['id'] as String: c,
  };
  final rows = items.where(
    (m) =>
        m['org_id'] == org &&
        m['deleted_at'] == null &&
        m['kind'] != 'combo' &&
        (categoryId == null || m['category_id'] == categoryId) &&
        (needle == null ||
            needle.isEmpty ||
            '${m['name']}'.toLowerCase().contains(needle)) &&
        (hasRecipe == null || data.hasRecipe(m['id'] as String) == hasRecipe),
  );
  MockRow? categoryOf(MockRow m) => liveCategories[m['category_id']];
  int compareText(Object? a, Object? b) => '${a ?? ''}'.compareTo('${b ?? ''}');
  rows.sort((a, b) {
    final ca = categoryOf(a);
    final cb = categoryOf(b);
    if ((ca == null) != (cb == null)) return ca == null ? 1 : -1;
    if (ca != null && cb != null) {
      final o =
          ((ca['display_order'] as int?) ?? 0) -
          ((cb['display_order'] as int?) ?? 0);
      if (o != 0) return o;
      final n = compareText(ca['name'], cb['name']);
      if (n != 0) return n;
      final i = compareText(ca['id'], cb['id']);
      if (i != 0) return i;
    }
    final n = compareText(a['name'], b['name']);
    return n != 0 ? n : compareText(a['id'], b['id']);
  });

  final categories = <Map<String, Object?>>[];
  final cards = <Map<String, Object?>>[];
  for (final item in rows) {
    final itemId = item['id'] as String;
    final category = categoryOf(item);
    if (category != null && categories.lastOrNull?['id'] != category['id']) {
      categories.add({
        'id': category['id'],
        'name': category['name'],
        'name_translations':
            category['name_translations'] ?? const <String, Object?>{},
      });
    }
    final sizes = data.sizesOf(itemId);
    final sizeOut = <Map<String, Object?>>[];
    final tableRows = <Map<String, Object?>>[];
    final rowAt = <String, int>{};
    for (final (col, size) in sizes.indexed) {
      final lines = data.linesOf(size['id'] as String);
      final cost = data.costOf(lines);
      final price = data.priceOf(size, item);
      final total = lines.isEmpty ? null : cost.cost;
      final incomplete = lines.isNotEmpty && cost.incomplete;
      final graded = total != null && !incomplete && price > 0;
      final base = size['base_id'] == null
          ? null
          : db[MenuTables.bases].find(size['base_id'] as String);
      sizeOut.add({
        'size_id': size['id'],
        'label': size['label'],
        'price': price,
        'is_active': size['is_active'] ?? true,
        'base_name': base == null || base['deleted_at'] != null
            ? null
            : base['name'],
        'cost_piastres': total,
        'cost_incomplete': incomplete,
        'food_cost_pct': graded ? total / price : null,
        'margin_pct': graded ? (price - total) / price : null,
      });
      for (final l in lines) {
        final out = studio.lineOut(l, l['id'] as String);
        final source = switch (out['source']) {
          final String s when s == 'base' || s == 'rule' || s == 'linked' => s,
          _ => 'own',
        };
        final key = '$source|${out['ingredient_id']}|${out['unit']}';
        final at = rowAt.putIfAbsent(key, () {
          tableRows.add({
            'ingredient_id': out['ingredient_id'],
            'ingredient_name': out['ingredient_name'],
            'unit': out['unit'],
            'source': source,
            'cells': <Map<String, Object?>>[
              for (var i = 0; i < sizes.length; i++)
                {'quantity': null, 'line_cost_piastres': null},
            ],
          });
          return tableRows.length - 1;
        });
        (tableRows[at]['cells']! as List)[col] = {
          'quantity': double.tryParse('${out['usable_quantity']}'),
          'line_cost_piastres': out['line_cost_piastres'],
        };
      }
    }
    // Stable: first appearance within a source's place.
    int rank(Object? source) => switch (source) {
      'base' => 1,
      'rule' => 2,
      _ => 0,
    };
    final ordered = [for (final (i, r) in tableRows.indexed) (i, r)]
      ..sort((a, b) {
        final c = rank(a.$2['source']) - rank(b.$2['source']);
        return c != 0 ? c : a.$1 - b.$1;
      });
    final sourceId = item['recipe_source_item_id'] as String?;
    final source = sourceId == null ? null : items.find(sourceId);
    cards.add({
      'menu_item_id': itemId,
      'name': item['name'],
      'name_translations':
          item['name_translations'] ?? const <String, Object?>{},
      'category_id': category?['id'],
      'is_active': item['is_active'] ?? true,
      'follows_item_name': source == null || source['deleted_at'] != null
          ? null
          : source['name'],
      'sizes': sizeOut,
      'rows': [for (final (_, r) in ordered) r],
      'steps': [
        for (final s in studio.steps(itemId))
          {
            'position': s['position'],
            'name': s['name'],
            'name_ar': s['name_ar'],
            'note': s['note'],
            'note_ar': s['note_ar'],
          },
      ],
    });
  }
  return {'categories': categories, 'items': cards};
}
