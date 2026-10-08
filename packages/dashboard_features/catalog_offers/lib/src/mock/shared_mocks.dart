/// The menu reads and the menu-item delete that several of this area's pages
/// call but that belong to the menu catalogue (`GET /menu-items`,
/// `GET /categories`, `DELETE /menu-items/{id}`).
///
/// Each is registered only when no handler answers it yet: in the whole app
/// (and its mock mode) the menu catalogue area registers first and its
/// handlers stay; in this area's own tests these answer, over the same core
/// tables (`menu_items`, `categories`, `item_sizes`).
library;

import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';
import 'offers_rules.dart';

void registerOffersSharedMocks(MockServer server, MockDb db) {
  void maybe(String method, String template, MockHandler handler) {
    if (!server.handles(method, template)) server.on(method, template, handler);
  }

  // `GET /menu-items`: the org's menu, not deleted, by name; `full=true`
  // embeds the sizes (`all_sizes` keeps a single-price item's `one_size`).
  maybe('GET', '/menu-items', (req) {
    req.requireCap('menu.items.read');
    final orgId = req.q('org_id') ?? req.orgId;
    req.requireSameOrg(orgId);
    final categoryId = req.q('category_id');
    final full = req.qBool('full') ?? false;
    final rows = db
        .table(OffersTables.menuItems)
        .where(
          (r) =>
              r['org_id'] == orgId &&
              r['deleted_at'] == null &&
              (categoryId == null || r['category_id'] == categoryId),
        );
    rows.sort((a, b) => (a['name']! as String).compareTo(b['name']! as String));
    return MockResponse.ok([
      for (final r in rows) full ? menuItemFullJson(db, r) : r,
    ]);
  });

  // `GET /categories`: the org's categories, by display order then name.
  maybe('GET', '/categories', (req) {
    req.requireCap('menu.categories.read');
    final orgId = req.q('org_id') ?? req.orgId;
    req.requireSameOrg(orgId);
    final rows = db
        .table(OffersTables.categories)
        .where((r) => r['org_id'] == orgId && r['deleted_at'] == null);
    rows.sort((a, b) {
      final c = ((a['display_order'] as num?) ?? 0).compareTo(
        (b['display_order'] as num?) ?? 0,
      );
      return c != 0
          ? c
          : (a['name']! as String).compareTo(b['name']! as String);
    });
    return MockResponse.ok(rows);
  });

  // `DELETE /menu-items/{id}`: a soft delete (combos are menu items), 204
  // whether or not it was there, as the backend answers.
  maybe('DELETE', '/menu-items/{id}', (req) {
    req.requireCap('menu.items.delete');
    final row = db.table(OffersTables.menuItems).find(req.param('id'));
    if (row != null && row['deleted_at'] == null) {
      row['deleted_at'] = db.nowIso;
    }
    return MockResponse.empty();
  });
}
