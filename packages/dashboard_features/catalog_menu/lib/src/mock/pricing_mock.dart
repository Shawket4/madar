/// Mock handlers of the `pricing` unit (`/menu/pricing`), the backend's way:
///
/// | route | backend | gate |
/// |---|---|---|
/// | `GET /addon-items/catalog` | `list_addon_catalog` (`menu/handlers.rs`) | `menu.items.read`, same org |
/// | `GET /delivery/channel-addon-overrides` | `list_channel_addon_overrides` (`delivery/settings.rs`) | `menu.addons.read`, branch access, channel |
///
/// The page's other calls are served by the items unit (`items_mock.dart`:
/// `/costing/catalog`, `/branch-addon-overrides`, `PUT`/`DELETE
/// /menu-price-overrides`) and the studio unit (`/menu-items/{id}/studio`),
/// all over the one unified override table ([MenuTables.priceOverrides]),
/// which the legacy add-on lists are views of on the backend
/// (`deploy/menu_unification_shim.sql`).
library;

import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';

/// `VALID_CHANNELS` / `validate_channel`.
const List<String> _channels = ['in_mall', 'outside', 'umbrella', 'pickup'];

void registerPricingMocks(MockServer server, MockDb db) {
  final data = CatalogMenuData(db);
  MockTable overrides() => db[MenuTables.priceOverrides];

  // GET /addon-items/catalog: the org's add-ons by type then name, paged
  // (per_page 1..500, 50 by default; total_pages 0 when empty), with the
  // optional per-branch override filter / sort.
  server.on('GET', '/addon-items/catalog', (req) {
    req.requireCap('menu.items.read');
    final org = req.q('org_id');
    if (org == null) {
      req.badRequest('Query deserialize error: missing field `org_id`');
    }
    req.requireSameOrg(org);
    final type = req.q('addon_type');
    final search = req.q('search')?.trim().toLowerCase();
    final branch = req.q('branch_id');
    final overridden = req.qBool('overridden');
    bool hasBranchRow(String id) => overrides().rows.any(
      (o) =>
          o['scope'] == 'branch' &&
          o['branch_id'] == branch &&
          o['target_type'] == 'modifier_option' &&
          o['target_id'] == id,
    );
    final rows = [
      for (final a in data.addonItems())
        if (a['org_id'] == org &&
            (type == null || a['addon_type'] == type) &&
            (search == null ||
                search.isEmpty ||
                '${a['name']}'.toLowerCase().contains(search)) &&
            (overridden == null ||
                hasBranchRow(a['id']! as String) == overridden))
          a,
    ];
    int byName(Map<String, Object?> a, Map<String, Object?> b) =>
        '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase());
    rows.sort(
      req.q('sort') == 'overridden'
          ? (a, b) {
              final x = hasBranchRow(a['id']! as String) ? 0 : 1;
              final y = hasBranchRow(b['id']! as String) ? 0 : 1;
              return x != y ? x - y : byName(a, b);
            }
          : (a, b) {
              final c = '${a['addon_type']}'.compareTo('${b['addon_type']}');
              return c != 0 ? c : byName(a, b);
            },
    );
    return MockResponse.ok(pageOf(rows, req, maxPerPage: 500));
  });

  // GET /delivery/channel-addon-overrides?branch_id&channel: one branch's
  // add-on rows on one channel, by add-on id.
  server.on('GET', '/delivery/channel-addon-overrides', (req) {
    req.requireCap('menu.addons.read');
    final branchId = req.q('branch_id');
    final channel = req.q('channel');
    if (branchId == null) {
      req.badRequest('Query deserialize error: missing field `branch_id`');
    }
    if (channel == null) {
      req.badRequest('Query deserialize error: missing field `channel`');
    }
    // require_branch_access: exists, same org, assigned (a platform admin
    // passes).
    final branch = db['branches'].find(branchId);
    if (branch == null || branch['deleted_at'] != null) {
      req.notFound('Branch not found');
    }
    if (!req.persona.isPlatform) {
      if (branch['org_id'] != req.orgId) {
        req.fail(MockResponse.forbidden('Branch belongs to a different org'));
      }
      req.requireBranch(branchId);
    }
    if (!_channels.contains(channel)) {
      req.badRequest(
        "channel must be 'in_mall', 'outside', 'umbrella' or 'pickup'",
      );
    }
    final addonIds = {for (final a in data.addonItems()) a['id']};
    final rows = overrides().where(
      (o) =>
          o['scope'] == 'branch_channel' &&
          o['branch_id'] == branchId &&
          o['channel'] == channel &&
          o['target_type'] == 'modifier_option' &&
          addonIds.contains(o['target_id']),
    )..sort((a, b) => '${a['target_id']}'.compareTo('${b['target_id']}'));
    return MockResponse.ok([
      for (final o in rows)
        {
          'branch_id': o['branch_id'],
          'addon_item_id': o['target_id'],
          'channel': o['channel'],
          'price_override': o['price'],
          'is_available': o['is_available'],
        },
    ]);
  });
}
