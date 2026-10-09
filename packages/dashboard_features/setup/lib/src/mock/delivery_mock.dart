/// The mock backend for Delivery settings and zones (`/settings/delivery`,
/// `/settings/delivery-zones`, SET-DLV and SET-DZN rows), as MadarRust
/// `src/delivery/settings.rs`:
///
/// - `GET /delivery/settings?branch_id=`: `delivery.settings.read` (or a
///   teller's `delivery.orders.read`), the branch check; the branch's row,
///   else the backend's defaults (prep 20, OTP and GPS on, all channels off);
/// - `PUT /delivery/settings`: `delivery.settings.edit`, the branch check,
///   400s for a negative fee or prep time, a distance or auto-reject ≤ 0, an
///   unreadable time, and a channel discount that is not an active discount
///   of the org; an upsert that keeps the POS-owned `*_override` columns;
/// - zones: list (`delivery.settings.read`, closest first), create
///   (`.create`, 201), update (`.edit`), delete (`.delete`, 204); distance
///   > 0 and fee ≥ 0 (400), one ring per distance per branch (409), 404
///   "Zone not found" for a zone of another branch. A body without
///   `name_translations` stores JSON null, as the backend's serde default;
/// - `GET /discounts?org_id=` only where no other area answers it
///   (catalog_offers owns it in the app), over the same seven discounts.
///
/// The branch check is `authz::scope::require_branch_access`: 404 "Branch
/// not found", 403 "Branch belongs to a different org", 403 "Not assigned
/// to this branch"; a platform admin passes.
library;

import 'package:collection/collection.dart';
import 'package:dashboard_api/dashboard_api.dart'
    show BranchDeliverySettings, BranchSettingsInput, ZoneInput;
import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';
import 'support.dart';

/// The routes this unit answers.
abstract final class DeliveryRoutes {
  static const String settings = '/delivery/settings';
  static const String zones = '/delivery/zones';
  static const String zone = '/delivery/zones/{id}';
  static const String discounts = '/discounts';
}

/// The unit's seed: zone rings per branch and (when no other area seeded
/// them) the org's discounts, the same rows catalog_offers seeds.
abstract final class DeliverySeed {
  static const String zonesTable = 'delivery_zones';
  static const String discountsTable = 'discounts';

  static String zoneId(String branch, int n) =>
      mockUuid('delivery-zone:$branch:$n');

  /// catalog_offers' `OffersSeed.discountId`.
  static String discountId(String key) => mockUuid('discount:$key');

  /// `(branch key, n, name, metres, fee in piastres, active)`, in insertion
  /// order (not ring order: the page sorts). Heliopolis, Maadi and New
  /// Cairo deliver outside; Zamalek does not and has no rings.
  static const List<(String, int, String, int, int, bool)> zones = [
    ('heliopolis', 2, 'Zone 2', 4000, 2500, true),
    ('heliopolis', 1, 'Zone 1', 2000, 1500, true),
    ('heliopolis', 3, 'Korba & Merghany', 6000, 3500, true),
    ('maadi', 1, 'Zone 1', 1500, 1000, true),
    ('maadi', 2, 'Zone 2', 3000, 2000, true),
    ('maadi', 3, 'Degla & Zahraa', 5000, 3000, false),
    ('new-cairo', 1, 'Zone 1', 3000, 2000, true),
    ('new-cairo', 2, 'Fifth Settlement', 5500, 3000, true),
    ('new-cairo', 3, 'Zone 3', 8000, 4500, true),
  ];

  static String branch(String key) => switch (key) {
    'heliopolis' => SeedIds.heliopolis,
    'maadi' => SeedIds.maadi,
    'new-cairo' => SeedIds.newCairo,
    _ => SeedIds.zamalek,
  };

  static Iterable<MockRow> zoneRows() => [
    for (final (b, n, name, m, fee, active) in zones)
      {
        'id': zoneId(b, n),
        'branch_id': branch(b),
        'name': name,
        'name_translations': <String, Object?>{},
        'max_road_distance_meters': m,
        'fee': fee,
        'is_active': active,
      },
  ];

  /// `(key, name, Arabic, dtype, value_rate, active, created)`.
  static const List<(String, String, String, String, num, bool, String)>
  discounts = [
    (
      'staff-meal',
      'Staff Meal',
      'وجبة الموظفين',
      'percentage',
      0.5,
      true,
      '2025-12-02T09:00:00.000Z',
    ),
    (
      'student',
      'Student Discount',
      'خصم الطلاب',
      'percentage',
      0.15,
      true,
      '2026-01-12T09:00:00.000Z',
    ),
    (
      'loyalty-welcome',
      'Loyalty Welcome',
      'ترحيب برنامج الولاء',
      'fixed',
      2500,
      true,
      '2026-02-03T09:00:00.000Z',
    ),
    (
      'manager-comp',
      'Manager Comp',
      'ضيافة المدير',
      'percentage',
      1,
      true,
      '2025-12-02T09:00:00.000Z',
    ),
    (
      'opening-week',
      'Opening Week',
      'أسبوع الافتتاح',
      'percentage',
      0.2,
      false,
      '2025-12-01T09:00:00.000Z',
    ),
    (
      'late-order',
      'Late Order Apology',
      'اعتذار عن تأخر الطلب',
      'fixed',
      5000,
      true,
      '2026-04-08T09:00:00.000Z',
    ),
    (
      'corporate-vodafone',
      'Corporate: Vodafone',
      'الشركات: فودافون',
      'percentage',
      0.125,
      true,
      '2026-06-15T09:00:00.000Z',
    ),
  ];

  /// The legacy integer `value`: a fraction as a whole percent (half away
  /// from zero), an amount as it is.
  static int legacyValue(num rate) =>
      (rate > 0 && rate <= 1 ? rate * 100 : rate).round();

  static Iterable<MockRow> discountRows() => [
    for (final (key, name, ar, dtype, rate, active, at) in discounts)
      {
        'id': discountId(key),
        'org_id': SeedIds.sabahOrg,
        'name': name,
        'name_translations': {'ar': ar},
        'dtype': dtype,
        'value': legacyValue(rate),
        'value_rate': rate,
        'is_active': active,
        'created_at': at,
        'updated_at': at,
      },
  ];

  /// `BranchDeliverySettings::defaults`: what a branch never set up reads.
  static BranchDeliverySettings defaults(String branchId) =>
      BranchDeliverySettings(
        branchId: branchId,
        inMallEnabled: false,
        outsideEnabled: false,
        umbrellaEnabled: false,
        pickupEnabled: false,
        inMallOverride: 'auto',
        outsideOverride: 'auto',
        umbrellaOverride: 'auto',
        pickupOverride: 'auto',
        inMallFee: 0,
        umbrellaFee: 0,
        pickupFee: 0,
        prepTimeMinutes: 20,
        otpRequired: true,
        inMallRequireLocation: true,
      );
}

final RegExp _naiveTime = RegExp(r'^([01]\d|2[0-3]):[0-5]\d(:[0-5]\d)?$');

void registerDeliveryMocks(MockServer server, MockDb db) {
  seedTableIfAbsent(db, DeliverySeed.zonesTable, DeliverySeed.zoneRows);
  seedTableIfAbsent(db, DeliverySeed.discountsTable, DeliverySeed.discountRows);
  MockTable settings() => db[SetupSeed.deliverySettingsTable];
  MockTable zones() => db[DeliverySeed.zonesTable];

  void branchAccess(MockRequest req, String branchId) {
    if (req.persona.isPlatform) return;
    final b = db['branches'].find(branchId);
    if (b == null || b['deleted_at'] != null) req.notFound('Branch not found');
    if (b['org_id'] != req.orgId) {
      req.fail(MockResponse.forbidden('Branch belongs to a different org'));
    }
    req.requireBranch(branchId);
  }

  String branchQuery(MockRequest req) {
    final id = req.q('branch_id');
    if (id == null || id.isEmpty) {
      req.badRequest('Query deserialize error: missing field `branch_id`');
    }
    return id;
  }

  MockRow? settingsRow(String branchId) =>
      settings().firstWhere((r) => r['branch_id'] == branchId);

  // ── branch settings ────────────────────────────────────────────────────

  server.on('GET', DeliveryRoutes.settings, (req) {
    req.requireAnyCap(const ['delivery.settings.read', 'delivery.orders.read']);
    final branchId = branchQuery(req);
    branchAccess(req, branchId);
    return MockResponse.ok(
      settingsRow(branchId) ?? DeliverySeed.defaults(branchId).toJson(),
    );
  });

  server.on('PUT', DeliveryRoutes.settings, (req) {
    req.requireCap('delivery.settings.edit');
    final b = req.bodyAs(BranchSettingsInput.fromJson);
    branchAccess(req, b.branchId);
    for (final t in [
      b.inMallOpenTime,
      b.inMallCloseTime,
      b.outsideOpenTime,
      b.outsideCloseTime,
      b.umbrellaOpenTime,
      b.umbrellaCloseTime,
      b.pickupOpenTime,
      b.pickupCloseTime,
    ]) {
      if (t != null && !_naiveTime.hasMatch(t)) {
        req.badRequest(
          'Json deserialize error: input contains invalid characters',
        );
      }
    }
    if (b.inMallFee < 0 || (b.umbrellaFee ?? 0) < 0 || (b.pickupFee ?? 0) < 0) {
      req.badRequest('channel fees must be >= 0');
    }
    if (b.prepTimeMinutes < 0) req.badRequest('prep_time_minutes must be >= 0');
    if ((b.maxRoadDistanceMeters ?? 1) <= 0) {
      req.badRequest('max_road_distance_meters must be > 0');
    }
    if ((b.autoRejectMinutes ?? 1) <= 0) {
      req.badRequest(
        'auto_reject_minutes must be > 0, or null to never auto-reject',
      );
    }
    final ids = [
      b.inMallDiscountId,
      b.outsideDiscountId,
      b.umbrellaDiscountId,
      b.pickupDiscountId,
    ].nonNulls;
    if (ids.isNotEmpty) {
      final orgId = req.orgId;
      if (orgId == null) req.fail(MockResponse.forbidden('No org in token'));
      for (final id in ids) {
        final d = db[DeliverySeed.discountsTable].find(id);
        if (d == null || d['org_id'] != orgId || d['is_active'] != true) {
          req.badRequest('Discount not found or inactive');
        }
      }
    }
    final current = settingsRow(b.branchId);
    final was = current == null
        ? DeliverySeed.defaults(b.branchId)
        : BranchDeliverySettings.fromJson(current);
    final next = BranchDeliverySettings(
      branchId: b.branchId,
      inMallEnabled: b.inMallEnabled,
      outsideEnabled: b.outsideEnabled,
      umbrellaEnabled: b.umbrellaEnabled ?? false,
      pickupEnabled: b.pickupEnabled ?? false,
      inMallOverride: was.inMallOverride,
      outsideOverride: was.outsideOverride,
      umbrellaOverride: was.umbrellaOverride,
      pickupOverride: was.pickupOverride,
      inMallOpenTime: b.inMallOpenTime,
      inMallCloseTime: b.inMallCloseTime,
      outsideOpenTime: b.outsideOpenTime,
      outsideCloseTime: b.outsideCloseTime,
      umbrellaOpenTime: b.umbrellaOpenTime,
      umbrellaCloseTime: b.umbrellaCloseTime,
      pickupOpenTime: b.pickupOpenTime,
      pickupCloseTime: b.pickupCloseTime,
      inMallFee: b.inMallFee,
      umbrellaFee: b.umbrellaFee ?? 0,
      pickupFee: b.pickupFee ?? 0,
      prepTimeMinutes: b.prepTimeMinutes,
      maxRoadDistanceMeters: b.maxRoadDistanceMeters,
      inMallDiscountId: b.inMallDiscountId,
      outsideDiscountId: b.outsideDiscountId,
      umbrellaDiscountId: b.umbrellaDiscountId,
      pickupDiscountId: b.pickupDiscountId,
      otpRequired: b.otpRequired ?? true,
      inMallRequireLocation: b.inMallRequireLocation ?? true,
      autoRejectMinutes: b.autoRejectMinutes,
    ).toJson();
    if (current == null) {
      settings().put(next);
    } else {
      current
        ..clear()
        ..addAll(next);
    }
    return MockResponse.ok(next);
  });

  // ── zones ──────────────────────────────────────────────────────────────

  MockRow wire(MockRow r) => {
    for (final k in const [
      'id',
      'branch_id',
      'name',
      'name_translations',
      'max_road_distance_meters',
      'fee',
      'is_active',
    ])
      k: r[k],
  };

  ZoneInput zoneBody(MockRequest req) {
    final b = req.bodyAs(ZoneInput.fromJson);
    branchAccess(req, b.branchId);
    if (b.maxRoadDistanceMeters <= 0) {
      req.badRequest('max_road_distance_meters must be > 0');
    }
    if (b.fee < 0) req.badRequest('fee must be >= 0');
    return b;
  }

  void unique(MockRequest req, ZoneInput b, {String? except}) {
    final clash = zones().firstWhere(
      (z) =>
          z['branch_id'] == b.branchId &&
          z['max_road_distance_meters'] == b.maxRoadDistanceMeters &&
          z['id'] != except,
    );
    if (clash != null) {
      req.conflict('A zone with this distance already exists for the branch');
    }
  }

  MockRow fields(MockRequest req, ZoneInput b) => {
    'branch_id': b.branchId,
    'name': b.name,
    // `#[serde(default)] serde_json::Value`: omitted is JSON null.
    'name_translations': req.json['name_translations'],
    'max_road_distance_meters': b.maxRoadDistanceMeters,
    'fee': b.fee,
    'is_active': b.isActive ?? true,
  };

  MockRow zoneOf(MockRequest req, String branchId) {
    final z = zones().find(req.param('id'));
    if (z == null || z['branch_id'] != branchId) req.notFound('Zone not found');
    return z;
  }

  server.on('GET', DeliveryRoutes.zones, (req) {
    req.requireCap('delivery.settings.read');
    final branchId = branchQuery(req);
    branchAccess(req, branchId);
    final rows = zones().where((z) => z['branch_id'] == branchId)
      ..sort(
        (a, b) => (a['max_road_distance_meters']! as int).compareTo(
          b['max_road_distance_meters']! as int,
        ),
      );
    return MockResponse.ok([for (final r in rows) wire(r)]);
  });

  server.on('POST', DeliveryRoutes.zones, (req) {
    req.requireCap('delivery.settings.create');
    final b = zoneBody(req);
    unique(req, b);
    return MockResponse.created(wire(zones().insert(fields(req, b))));
  });

  server.on('PATCH', DeliveryRoutes.zone, (req) {
    req.requireCap('delivery.settings.edit');
    final b = zoneBody(req);
    final z = zoneOf(req, b.branchId);
    unique(req, b, except: z['id'] as String?);
    return MockResponse.ok(
      wire(zones().update(z['id']! as String, fields(req, b))),
    );
  });

  server.on('DELETE', DeliveryRoutes.zone, (req) {
    req.requireCap('delivery.settings.delete');
    final branchId = branchQuery(req);
    branchAccess(req, branchId);
    zones().delete(zoneOf(req, branchId)['id']! as String);
    return MockResponse.empty();
  });

  // ── discounts (catalog_offers' in the app) ─────────────────────────────

  onIfAbsent(server, 'GET', DeliveryRoutes.discounts, (req) {
    req.requireCap('discounts.read');
    final orgId = req.q('org_id');
    if (orgId == null || orgId.isEmpty) {
      req.badRequest('Query deserialize error: missing field `org_id`');
    }
    if (!req.persona.isPlatform && orgId != req.persona.orgId) {
      req.fail(MockResponse.forbidden('Not your org'));
    }
    final rows = db[DeliverySeed.discountsTable].where(
      (r) => r['org_id'] == orgId,
    )..sort((a, b) => compareAsciiLowerCase('${a['name']}', '${b['name']}'));
    return MockResponse.ok(rows);
  });
}
