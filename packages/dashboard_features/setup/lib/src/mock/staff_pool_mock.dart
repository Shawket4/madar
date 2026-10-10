/// The mock backend for Staff drinks settings (`/settings/staff-pool`,
/// SET-SPL rows), as MadarRust `src/staff_pool/settings.rs` answers:
///
/// - `GET /staff-pool/settings[?branch_id]`: `orders.staff_drink.record` (the
///   till's own capability: whoever may record a drink may read the rule).
///   A branch answers with what it RUNS ON (`load_effective`): its own row,
///   else the org's reported under the branch, else off.
/// - `PUT /staff-pool/settings`: `org.settings.edit`; the org comes from the
///   body's branch (or the caller), never the body's `org_id`; a negative
///   allowance and an item not live on the org's menu are 400s.
/// - `DELETE /staff-pool/settings?branch_id`: `org.settings.edit` first, then
///   the branch is required.
///
/// The rows live in `staff_pool_settings`, the table the reports area's
/// staff drinks report reads too (`StaffPoolMock` there): same name, same
/// shape, same seed (org 3 a day; Heliopolis 4, Zamalek 5, New Cairo off;
/// Maadi follows the org), so whichever area seeds it first, both agree.
library;

import 'package:dashboard_api/mock.dart';

import 'support.dart';

abstract final class StaffPoolSettingsMock {
  static const String table = 'staff_pool_settings';

  /// The org default.
  static const int orgAllowance = 3;

  /// The items that count (the reports seed's list).
  static const List<String> eligibleKeys = [
    'americano',
    'latte',
    'cappuccino',
    'iced_latte',
    'iced_americano',
    'mint_lemonade',
    'green_tea',
    'v60',
  ];

  static List<String> get eligibleItemIds => [
    for (final k in eligibleKeys) MockSeed.menuItemId(k),
  ];

  static MockRow _row(
    String key,
    String? branchId,
    int allowance, {
    bool enabled = true,
  }) => {
    'id': mockUuid('staff-pool-settings:$key'),
    'org_id': SeedIds.sabahOrg,
    'branch_id': branchId,
    'enabled': enabled,
    'daily_allowance': allowance,
    'eligible_item_ids': eligibleItemIds,
  };

  static List<MockRow> rows() => [
    _row('sabah', null, orgAllowance),
    _row('heliopolis', SeedIds.heliopolis, 4),
    _row('zamalek', SeedIds.zamalek, 5),
    _row('new-cairo', SeedIds.newCairo, orgAllowance, enabled: false),
  ];

  /// The scope's own row (`load_scope`), or null.
  static MockRow? own(MockDb db, String orgId, String? branchId) => db[table]
      .firstWhere((r) => r['org_id'] == orgId && r['branch_id'] == branchId);

  /// The row as the API states it (`COLS`).
  static Map<String, Object?> wire(MockRow r, {String? branchId}) => {
    'org_id': r['org_id'],
    'branch_id': branchId ?? r['branch_id'],
    'enabled': r['enabled'] ?? false,
    'daily_allowance': r['daily_allowance'] ?? 0,
    'eligible_item_ids': [...(r['eligible_item_ids'] as List? ?? const [])],
  };

  /// `StaffPoolSettings::defaults`: off, nothing allowed.
  static Map<String, Object?> defaults(String orgId, String? branchId) => {
    'org_id': orgId,
    'branch_id': branchId,
    'enabled': false,
    'daily_allowance': 0,
    'eligible_item_ids': const <String>[],
  };
}

final RegExp _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?'
  r'[0-9a-fA-F]{12}$',
);

void registerStaffPoolMocks(MockServer server, MockDb db) {
  seedTableIfAbsent(
    db,
    StaffPoolSettingsMock.table,
    StaffPoolSettingsMock.rows,
  );

  String? branchParam(MockRequest req) {
    final b = req.q('branch_id');
    if (b != null && !_uuid.hasMatch(b)) {
      req.badRequest('Query deserialize error: UUID parsing failed');
    }
    return b;
  }

  /// `scope_org`: the branch's org (404 for an unknown or closed branch),
  /// else the caller's.
  String scopeOrg(MockRequest req, String? branchId) {
    if (branchId != null) {
      final b = db['branches'].find(branchId);
      if (b == null || b['is_active'] == false || b['deleted_at'] != null) {
        req.notFound('Branch not found');
      }
      return '${b['org_id']}';
    }
    final org = req.orgId;
    if (org == null) req.badRequest('Pick an organisation first');
    return org;
  }

  /// `require_branch_access`: the caller's org, and a branch they work at.
  void branchAccess(MockRequest req, String orgId, String branchId) {
    req.requireSameOrg(orgId);
    req.requireBranch(branchId);
  }

  server.on('GET', '/staff-pool/settings', (req) {
    final branchId = branchParam(req);
    final org = scopeOrg(req, branchId);
    req.requireCap('orders.staff_drink.record', branchId: branchId);
    if (branchId != null) branchAccess(req, org, branchId);
    final own = StaffPoolSettingsMock.own(db, org, branchId);
    if (own != null) return MockResponse.ok(StaffPoolSettingsMock.wire(own));
    if (branchId != null) {
      final orgRow = StaffPoolSettingsMock.own(db, org, null);
      if (orgRow != null) {
        // Reported under the branch that asked (`load_effective`).
        return MockResponse.ok(
          StaffPoolSettingsMock.wire(orgRow, branchId: branchId),
        );
      }
    }
    return MockResponse.ok(StaffPoolSettingsMock.defaults(org, branchId));
  });

  server.on('PUT', '/staff-pool/settings', (req) {
    final body = req.json;
    final rawBranch = body['branch_id'];
    if (body['org_id'] is! String) {
      req.badRequest('Json deserialize error: missing field `org_id`');
    }
    if (rawBranch != null &&
        (rawBranch is! String || !_uuid.hasMatch(rawBranch))) {
      req.badRequest('Json deserialize error: UUID parsing failed');
    }
    final allowance = body['daily_allowance'] ?? 0;
    if (allowance is! int) {
      req.badRequest(
        'Json deserialize error: invalid type: expected i32 at '
        '`daily_allowance`',
      );
    }
    final rawIds = body['eligible_item_ids'] ?? const <Object?>[];
    if (rawIds is! List ||
        rawIds.any((e) => e is! String || !_uuid.hasMatch(e))) {
      req.badRequest('Json deserialize error: UUID parsing failed');
    }
    final enabled = body['enabled'] ?? false;
    if (enabled is! bool) {
      req.badRequest(
        'Json deserialize error: invalid type: expected a boolean',
      );
    }
    final branchId = rawBranch as String?;
    final org = scopeOrg(req, branchId);
    req.requireCap('org.settings.edit', branchId: branchId);
    if (branchId != null) branchAccess(req, org, branchId);
    if (allowance < 0) {
      req.badRequest('A daily allowance cannot be less than zero');
    }
    final ids = [for (final e in rawIds) '$e'];
    final asked = ids.toSet();
    if (asked.isNotEmpty) {
      final live = db['menu_items']
          .where(
            (m) =>
                m['org_id'] == org &&
                m['deleted_at'] == null &&
                asked.contains(m['id']),
          )
          .length;
      if (live != asked.length) {
        req.badRequest(
          "Some of those drinks are not on this organisation's menu any more",
        );
      }
    }
    final values = <String, Object?>{
      'enabled': enabled,
      'daily_allowance': allowance,
      'eligible_item_ids': ids,
    };
    final own = StaffPoolSettingsMock.own(db, org, branchId);
    final row = own != null
        ? db[StaffPoolSettingsMock.table].update('${own['id']}', values)
        : db[StaffPoolSettingsMock.table].insert({
            'id': mockUuid('staff-pool-settings:$org:${branchId ?? 'org'}'),
            'org_id': org,
            'branch_id': branchId,
            ...values,
          }, timestamps: false);
    return MockResponse.ok(StaffPoolSettingsMock.wire(row));
  });

  server.on('DELETE', '/staff-pool/settings', (req) {
    final branchId = branchParam(req);
    final org = scopeOrg(req, branchId);
    req.requireCap('org.settings.edit', branchId: branchId);
    if (branchId == null) {
      req.badRequest('Name the branch whose override you want to remove');
    }
    branchAccess(req, org, branchId);
    db[StaffPoolSettingsMock.table].removeWhere(
      (r) => r['org_id'] == org && r['branch_id'] == branchId,
    );
    return MockResponse.empty();
  });

  // The org menu the picker lists (`list_menu_items`), when no other unit
  // or area answers it.
  onIfAbsent(server, 'GET', '/menu-items', (req) {
    req.requireCap('menu.items.read');
    final org = req.q('org_id');
    if (org == null) {
      req.badRequest('Query deserialize error: missing field `org_id`');
    }
    req.requireSameOrg(org);
    return MockResponse.ok(
      db['menu_items'].query(filters: {'org_id': org}, sort: 'name'),
    );
  });
}
