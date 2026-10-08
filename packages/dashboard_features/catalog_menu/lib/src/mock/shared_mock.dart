/// Mock handlers for the reads several menu units share (see
/// `shared/menu_providers.dart`), over the area seed's tables. Writes stay in
/// each unit's own mock file.
///
/// NOTE for the full app: the inventory area may also answer
/// `/inventory/orgs/{org_id}/catalog`; both read [MenuTables.ingredients], so
/// whichever registers last answers with the same rows.
library;

import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';

void registerSharedMenuMocks(MockServer server, MockDb db) {
  // GET /inventory/orgs/{org_id}/catalog (require_org_access).
  server.on('GET', '/inventory/orgs/{org_id}/catalog', (req) {
    final org = req.param('org_id');
    req.requireSameOrg(org);
    return MockResponse.ok(
      db[MenuTables.ingredients].query(filters: {'org_id': org}, sort: 'name'),
    );
  });

  // GET /inventory/orgs/{org_id}/categories (require_org_access).
  server.on('GET', '/inventory/orgs/{org_id}/categories', (req) {
    final org = req.param('org_id');
    req.requireSameOrg(org);
    final ingredients = db[MenuTables.ingredients].rows;
    return MockResponse.ok([
      for (final c in db[MenuTables.ingredientCategories].query(
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

  // GET /categories?org_id (require_same_org), POS order.
  server.on('GET', '/categories', (req) {
    final org = req.q('org_id');
    req.requireSameOrg(org);
    return MockResponse.ok(
      db[MenuTables.categories].query(
        filters: {'org_id': org},
        where: (c) => c['deleted_at'] == null,
        sort: 'display_order',
      ),
    );
  });

  // GET /modifier-groups?org_id[&include_inactive] (require_same_org).
  server.on('GET', '/modifier-groups', (req) {
    final org = req.q('org_id');
    req.requireSameOrg(org);
    final all = req.qBool('include_inactive') ?? false;
    final rows =
        db[MenuTables.groups].query(
          filters: {'org_id': org},
          where: (g) => all || g['is_active'] == true,
        )..sort((a, b) {
          final c = ((a['sort'] as int?) ?? 0) - ((b['sort'] as int?) ?? 0);
          return c != 0 ? c : compareJson(a['name'], b['name']);
        });
    return MockResponse.ok(rows);
  });

  // GET /addon-items?org_id[&addon_type&search] (require_same_org): the
  // shared groups' options, by type then creation.
  server.on('GET', '/addon-items', (req) {
    final org = req.q('org_id');
    req.requireSameOrg(org);
    final type = req.q('addon_type');
    final search = req.q('search')?.trim().toLowerCase();
    return MockResponse.ok([
      for (final a in CatalogMenuData(db).addonItems())
        if (a['org_id'] == org &&
            (type == null || a['addon_type'] == type) &&
            (search == null ||
                search.isEmpty ||
                '${a['name']}'.toLowerCase().contains(search)))
          a,
    ]);
  });

  // GET /recipe-bases (menu.items.read; the org from the session).
  server.on('GET', '/recipe-bases', (req) {
    req.requireCap('menu.items.read');
    final org = req.orgId;
    final data = CatalogMenuData(db);
    final sizes = db[MenuTables.sizes].rows;
    return MockResponse.ok([
      for (final b in db[MenuTables.bases].query(
        filters: {'org_id': org},
        where: (b) => b['deleted_at'] == null,
        sort: 'name',
      ))
        recipeBaseOut(b, data, sizes),
    ]);
  });
}

/// A stored base as `RecipeBaseOut`: lines named, with how many items and
/// sizes use it.
Map<String, Object?> recipeBaseOut(
  MockRow b,
  CatalogMenuData data,
  List<MockRow> sizes,
) {
  final using = sizes.where((s) => s['base_id'] == b['id']).toList();
  return {
    'id': b['id'],
    'org_id': b['org_id'],
    'name': b['name'],
    'name_ar': b['name_ar'],
    'is_active': b['is_active'],
    'item_count': {for (final s in using) s['menu_item_id']}.length,
    'size_count': using.length,
    'lines': [
      for (final l in (b['lines'] as List).cast<Map<String, Object?>>())
        {
          ...l,
          'ingredient_name': data.ingredientName(l['ingredient_id'] as String),
        },
    ],
    'created_at': b['created_at'],
    'updated_at': b['updated_at'],
  };
}
