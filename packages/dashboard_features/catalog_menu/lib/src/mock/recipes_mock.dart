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
library;

import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';
import '../shared/menu_text.dart';

void registerRecipesMocks(MockServer server, MockDb db) {
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
      });
    }
    lines.sort(
      (a, b) => compareJson(a['ingredient_name'], b['ingredient_name']),
    );
    return MockResponse.ok(lines);
  });
}
