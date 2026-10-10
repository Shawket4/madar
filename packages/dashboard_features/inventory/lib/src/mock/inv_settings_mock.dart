/// Inventory settings: the mock backend for the INV-SET rows. Routes this unit owns
/// (the only file that registers them):
///
/// - GET /inventory/orgs/{org_id}/settings (getInventorySettings)
/// - PUT /inventory/orgs/{org_id}/settings (updateInventorySettings)
/// - POST /inventory/orgs/{org_id}/categories (createIngredientCategory) — also used by Ingredients' "New category…"
/// - PATCH /inventory/orgs/{org_id}/categories/{id} (updateIngredientCategory)
/// - DELETE /inventory/orgs/{org_id}/categories/{id} (deleteIngredientCategory)
///
/// The categories list is a shared read. Gates, words and checks are the
/// backend's (`MadarRust src/inventory/handlers.rs`): read = inventory.read,
/// create = inventory.items.create, update = inventory.adjust,
/// delete = inventory.items.delete.
library;

import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';
import 'ingredients_mock.dart' show ingredientCategorySlug;
import 'inventory_views.dart';

void registerInvSettingsMocks(MockServer server, MockDb db) {
  final cats = db[InvTables.categories];

  String org(MockRequest req) {
    final id = req.param('org_id');
    req.requireSameOrg(id);
    return id;
  }

  /// The backend's 1–80 character name rule.
  String checkedName(MockRequest req, Object? raw) {
    final name = ((raw as String?) ?? '').trim();
    if (name.isEmpty || name.runes.length > 80) {
      req.badRequest('Category name must be 1–80 characters');
    }
    return name;
  }

  MockRow category(MockRequest req, String orgId) {
    final c = cats.find(req.param('id'));
    if (c == null || c['org_id'] != orgId) req.notFound('Category not found');
    return c;
  }

  MockRow view(MockRow c) => {
    ...c,
    'ingredient_count': db[InvTables.ingredients]
        .where((i) => i['category_id'] == c['id'])
        .length,
  };

  server.on('GET', '/inventory/orgs/{org_id}/settings', (req) {
    req.requireCap('inventory.read');
    final orgId = org(req);
    return MockResponse.ok({
      'stocktake_variance_threshold_pct': InvViews.thresholdPct(db, orgId),
    });
  });

  server.on('PUT', '/inventory/orgs/{org_id}/settings', (req) {
    req.requireCap('inventory.adjust');
    final orgId = org(req);
    final pct = req.json['stocktake_variance_threshold_pct'];
    if (pct is! num || pct < 0 || pct > 100) {
      req.badRequest(
        'stocktake_variance_threshold_pct must be between 0 and 100',
      );
    }
    db[InvTables.settings].put({
      'id': orgId,
      'org_id': orgId,
      'stocktake_variance_threshold_pct': pct.toDouble(),
    });
    return MockResponse.ok({'stocktake_variance_threshold_pct': pct});
  });

  server.on('POST', '/inventory/orgs/{org_id}/categories', (req) {
    req.requireCap('inventory.items.create');
    final orgId = org(req);
    final b = req.json;
    final name = checkedName(req, b['name']);
    final given = (b['slug'] as String?)?.trim() ?? '';
    final String slug;
    if (given.isNotEmpty) {
      if (!RegExp(r'^[a-z0-9_]{1,64}$').hasMatch(given)) {
        req.badRequest('slug may only contain a-z, 0-9 and _ (max 64)');
      }
      slug = given;
    } else {
      slug =
          ingredientCategorySlug(name) ??
          req.badRequest('Category name must contain a letter or digit');
    }
    if (cats.firstWhere((c) => c['org_id'] == orgId && c['slug'] == slug) !=
        null) {
      req.conflict("A category with the key '$slug' already exists");
    }
    final row = cats.insert({
      'org_id': orgId,
      'slug': slug,
      'name': name,
      'sort_order': (b['sort_order'] as num?)?.toInt() ?? 10,
      'is_packaging': b['is_packaging'] ?? slug == 'packaging',
    });
    return MockResponse.created(view(row));
  });

  server.on('PATCH', '/inventory/orgs/{org_id}/categories/{id}', (req) {
    req.requireCap('inventory.adjust');
    final orgId = org(req);
    final b = req.json;
    final c = category(req, orgId);
    final row = cats.update(c['id']! as String, {
      if (b['name'] != null) 'name': checkedName(req, b['name']),
      if (b['sort_order'] is num)
        'sort_order': (b['sort_order']! as num).toInt(),
      if (b['is_packaging'] is bool) 'is_packaging': b['is_packaging'],
    });
    return MockResponse.ok(view(row));
  });

  server.on('DELETE', '/inventory/orgs/{org_id}/categories/{id}', (req) {
    req.requireCap('inventory.items.delete');
    final orgId = org(req);
    final c = category(req, orgId);
    if (c['slug'] == 'general') {
      req.badRequest('The general category cannot be deleted');
    }
    final users = db[InvTables.ingredients].where(
      (i) => i['category_id'] == c['id'],
    );
    if (users.isNotEmpty) {
      final target = req.q('reassign_to');
      if (target == null) {
        req.conflict(
          '${users.length} ingredient(s) use this category. Pass reassign_to '
          'to move them first.',
        );
      }
      if (target == c['id']) {
        req.badRequest('reassign_to must be a different category');
      }
      final to = cats.find(target);
      if (to == null || to['org_id'] != orgId) {
        req.badRequest('Category does not belong to this organization');
      }
      for (final i in users) {
        i['category_id'] = target;
        i['category_slug'] = to['slug'];
        i['category_name'] = to['name'];
      }
    }
    cats.delete(c['id']! as String);
    return MockResponse.empty();
  });
}
