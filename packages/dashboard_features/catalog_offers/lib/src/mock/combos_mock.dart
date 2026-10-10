/// The combos list's mock backend (`/menu/combos`): `GET /combos` (`q`,
/// `category_id`, `is_active`, `page`, `per_page`), as `combos/handlers.rs`
/// `list_combos` answers it. The categories and the menu-item delete are the
/// area's shared handlers (`shared_mocks.dart`); summaries come from
/// `offers_rules.dart` (`comboRows`, `comboSummaryJson`). The backend's
/// `ComboSummary` carries no `image` asset, so the list never polls an asset
/// job.
library;

import 'package:dashboard_api/mock.dart';

import '../shared/menu_options.dart' show compareNames;
import 'offers_rules.dart';

final RegExp _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?'
  r'[0-9a-fA-F]{12}$',
);

void registerCombosMocks(MockServer server, MockDb db) {
  server.on('GET', '/combos', (req) {
    req.requireCap('menu.items.read');
    final orgId = req.orgId;
    if (orgId == null) {
      req.fail(
        MockResponse.forbidden('A super admin must scope this to an org'),
      );
    }
    // actix's query extractor: a malformed value is a 400.
    final categoryId = req.q('category_id');
    if (categoryId != null && !_uuid.hasMatch(categoryId)) {
      req.badRequest('Query deserialize error: UUID parsing failed');
    }
    final activeRaw = req.q('is_active');
    if (activeRaw != null && activeRaw != 'true' && activeRaw != 'false') {
      req.badRequest(
        'Query deserialize error: provided string was not `true` or `false`',
      );
    }
    final isActive = activeRaw == null ? null : activeRaw == 'true';
    // `%`/`_` are escaped: the search is a plain case-insensitive contains,
    // on the English name or the Arabic one.
    final q = req.q('q')?.trim().toLowerCase();
    bool hit(Map<String, Object?> r) {
      if (q == null || q.isEmpty) return true;
      final ar = (r['name_translations'] as Map?)?['ar'];
      return (r['name']! as String).toLowerCase().contains(q) ||
          (ar is String && ar.toLowerCase().contains(q));
    }

    final rows = [
      for (final r in comboRows(db, orgId))
        if (hit(r) &&
            (categoryId == null || r['category_id'] == categoryId) &&
            (isActive == null || (r['is_active'] ?? true) == isActive))
          r,
    ];
    // `ORDER BY name, id` in the database's collation, not code-unit order.
    rows.sort((a, b) {
      final c = compareNames(a['name']! as String, b['name']! as String);
      return c != 0 ? c : (a['id']! as String).compareTo(b['id']! as String);
    });
    final page = pageOf(rows, req);
    return MockResponse.ok({
      ...page,
      'data': [
        for (final r in page['data']! as List)
          comboSummaryJson(db, r as Map<String, Object?>),
      ],
    });
  });
}
