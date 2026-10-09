/// The mock backend for Kitchen stations and order routing
/// (`/settings/kitchen-stations`, `/settings/kitchen-routing`, SET-KST and
/// SET-KRT rows), as MadarRust `src/kitchen/stations.rs` answers. Resource
/// `kitchen_stations`: read → `kitchen.stations.read`, create →
/// `.create`, update → `.edit`, delete → `.delete`; every route checks the
/// branch is the person's (`require_branch_access`).
///
/// - `GET /kitchen/stations?branch_id`: the branch's live stations by
///   `sort_order`, then name (case-blind).
/// - `POST /kitchen/stations` (201): a blank name is 400; an unknown branch
///   404; `is_default` takes the flag from the branch's other stations.
/// - `PATCH /kitchen/stations/{id}`: 404 when gone; a blank name 400; the
///   printer fields change when sent (an explicit null clears them).
/// - `DELETE /kitchen/stations/{id}` (204): a soft delete; its routes stay
///   (the KDS ignores a deleted station's routes, as the backend's do).
/// - `GET /kitchen/routes?branch_id`, `PUT|DELETE /kitchen/routes/category`,
///   `PUT|DELETE /kitchen/routes/item`: an upsert keyed by (branch, category
///   | item); a station of another branch is 400.
/// - `GET|PUT /kitchen/routing-mode`: the stored override (null = auto) and
///   the effective mode (the override, else `kds` when an active station
///   exists, else `till`); a mode outside kds/till/both/off is 400.
/// - `GET /categories?org_id`, `GET /costing/catalog?org_id&search&page&
///   per_page`: only when no other area answers them (catalog_menu does in
///   the app), over the core seed's menu.
///
/// Data ([KitchenSeed]): Zamalek runs a Bar (default, Epson), a Kitchen
/// (Star) and a retired Pastry station, on auto; Heliopolis a Bar and a
/// Kitchen on "both"; Maadi has none (auto → the till); New Cairo none and
/// the kitchen switched off.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';

import 'support.dart';

/// The routes, for tests.
abstract final class KitchenRoutes {
  static const String stations = '/kitchen/stations';
  static const String station = '/kitchen/stations/{id}';
  static const String routes = '/kitchen/routes';
  static const String categoryRoute = '/kitchen/routes/category';
  static const String itemRoute = '/kitchen/routes/item';
  static const String routingMode = '/kitchen/routing-mode';
  static const String categories = '/categories';
  static const String catalog = '/costing/catalog';
}

/// The backend's refusal sentences (tests build the same responses).
abstract final class KitchenRefusals {
  static const String nameRequired = 'Station name is required';
  static const String nameEmpty = 'Station name cannot be empty';
  static const String notFound = 'Station not found';
  static const String otherBranch = 'Station does not belong to this branch';
  static const String badMode = 'mode must be kds, till, both, or off';
}

abstract final class KitchenSeed {
  static const String stationsTable = 'kitchen_stations';
  static const String categoryRoutesTable = 'category_station_routes';
  static const String itemRoutesTable = 'menu_item_station_routes';
  static const String modesTable = 'kitchen_routing_modes';

  /// A seeded station's id by branch key and station key.
  static String stationId(String branch, String key) =>
      mockUuid('kitchen-station:$branch:$key');

  static KitchenStation _station(
    String branch,
    String key,
    String name,
    String ar, {
    required int sort,
    PrinterBrand? brand,
    String? ip,
    bool isDefault = false,
    bool isActive = true,
    DateTime? updated,
  }) => KitchenStation(
    id: stationId(branch, key),
    orgId: SeedIds.sabahOrg,
    branchId: MockSeed.branchIdOf(branch),
    name: name,
    nameTranslations: {'en': name, 'ar': ar},
    sortOrder: sort,
    printerBrand: brand,
    printerIp: ip,
    printerPort: brand == null ? null : 9100,
    isDefault: isDefault,
    isActive: isActive,
    createdAt: DateTime.utc(2026, 3, 2, 8),
    updatedAt: updated ?? DateTime.utc(2026, 3, 2, 8),
  );

  /// Zamalek: the bar makes the drinks and catches the rest, the kitchen
  /// the breakfasts; the pastry counter closed in August. Heliopolis: a bar
  /// and a kitchen.
  static List<KitchenStation> get stations => [
    _station(
      'zamalek',
      'bar',
      'Bar',
      'البار',
      sort: 0,
      brand: PrinterBrand.epson,
      ip: '192.168.10.21',
      isDefault: true,
    ),
    _station(
      'zamalek',
      'kitchen',
      'Kitchen',
      'المطبخ',
      sort: 1,
      brand: PrinterBrand.star,
      ip: '192.168.10.22',
    ),
    _station(
      'zamalek',
      'pastry',
      'Pastry',
      'المعجنات',
      sort: 2,
      isActive: false,
      updated: DateTime.utc(2026, 8, 14, 9),
    ),
    _station(
      'heliopolis',
      'bar',
      'Bar',
      'البار',
      sort: 0,
      brand: PrinterBrand.epson,
      ip: '192.168.1.60',
      isDefault: true,
    ),
    _station(
      'heliopolis',
      'kitchen',
      'Kitchen',
      'المطبخ',
      sort: 1,
      brand: PrinterBrand.star,
      ip: '192.168.1.61',
    ),
  ];

  /// (branch, category key, station key).
  static const List<(String, String, String)> categoryRoutes = [
    ('zamalek', 'hot', 'bar'),
    ('zamalek', 'iced', 'bar'),
    ('zamalek', 'tea', 'bar'),
    ('zamalek', 'juice', 'bar'),
    ('zamalek', 'bakery', 'pastry'),
    ('zamalek', 'breakfast', 'kitchen'),
    ('heliopolis', 'hot', 'bar'),
    ('heliopolis', 'iced', 'bar'),
    ('heliopolis', 'breakfast', 'kitchen'),
  ];

  /// (branch, item key, station key): Zamalek warms its croissants in the
  /// kitchen oven, and the cookies still name the closed pastry counter.
  static const List<(String, String, String)> itemRoutes = [
    ('zamalek', 'croissant', 'kitchen'),
    ('zamalek', 'cookie', 'pastry'),
  ];

  /// The stored overrides (absent = auto).
  static const Map<String, String> modes = {
    'heliopolis': 'both',
    'new-cairo': 'off',
  };

  static List<MockRow> get categoryRouteRows => [
    for (final (b, c, s) in categoryRoutes)
      {
        'branch_id': MockSeed.branchIdOf(b),
        'category_id': MockSeed.categoryId(c),
        'station_id': stationId(b, s),
      },
  ];

  static List<MockRow> get itemRouteRows => [
    for (final (b, i, s) in itemRoutes)
      {
        'branch_id': MockSeed.branchIdOf(b),
        'menu_item_id': MockSeed.menuItemId(i),
        'station_id': stationId(b, s),
      },
  ];

  static List<MockRow> get modeRows => [
    for (final e in modes.entries)
      {'branch_id': MockSeed.branchIdOf(e.key), 'mode': e.value},
  ];
}

/// The effective mode at [branchId] (`effective_routing_mode`).
String kitchenEffectiveMode(MockDb db, String branchId) {
  final stored = db[KitchenSeed.modesTable]
      .firstWhere((r) => r['branch_id'] == branchId)?['mode'];
  if (stored is String) return stored;
  final hasStation = db[KitchenSeed.stationsTable].rows.any(
    (s) =>
        s['branch_id'] == branchId &&
        s['is_active'] == true &&
        s['deleted_at'] == null,
  );
  return hasStation ? 'kds' : 'till';
}

void registerKitchenMocks(MockServer server, MockDb db) {
  seedTableIfAbsent(
    db,
    KitchenSeed.stationsTable,
    () => [for (final s in KitchenSeed.stations) s.toJson()],
  );
  seedTableIfAbsent(
    db,
    KitchenSeed.categoryRoutesTable,
    () => KitchenSeed.categoryRouteRows,
  );
  seedTableIfAbsent(
    db,
    KitchenSeed.itemRoutesTable,
    () => KitchenSeed.itemRouteRows,
  );
  seedTableIfAbsent(db, KitchenSeed.modesTable, () => KitchenSeed.modeRows);
  MockTable stations() => db[KitchenSeed.stationsTable];

  /// `require_branch_access`: a live branch the person may act on.
  void branchAccess(MockRequest req, String branchId) {
    final b = db['branches'].find(branchId);
    if (b == null || b['deleted_at'] != null) req.notFound('Branch not found');
    if (!req.persona.isPlatform && b['org_id'] != req.orgId) {
      req.fail(MockResponse.forbidden('Not assigned to this branch'));
    }
    req.requireBranch(branchId);
  }

  String branchParam(MockRequest req) =>
      req.q('branch_id') ??
      req.badRequest('Query deserialize error: missing field `branch_id`');

  String bodyString(MockRequest req, String field) {
    final v = req.json[field];
    if (v is String) return v;
    req.badRequest('Json deserialize error: missing field `$field`');
  }

  MockRow liveStation(MockRequest req, String id) {
    final row = stations().find(id);
    if (row == null || row['deleted_at'] != null) {
      req.notFound(KitchenRefusals.notFound);
    }
    return row;
  }

  void clearDefault(String branchId, {String? except}) {
    for (final s in stations().rows) {
      if (s['branch_id'] == branchId &&
          s['is_default'] == true &&
          s['deleted_at'] == null &&
          s['id'] != except) {
        stations().update(s['id']! as String, {'is_default': false});
      }
    }
  }

  void stationInBranch(MockRequest req, String stationId, String branchId) {
    final s = stations().find(stationId);
    if (s == null || s['branch_id'] != branchId || s['deleted_at'] != null) {
      req.badRequest(KitchenRefusals.otherBranch);
    }
  }

  // ── stations ───────────────────────────────────────────────────────────

  server.on('GET', KitchenRoutes.stations, (req) {
    req.requireCap('kitchen.stations.read');
    final branchId = branchParam(req);
    branchAccess(req, branchId);
    final rows =
        stations().where(
          (s) => s['branch_id'] == branchId && s['deleted_at'] == null,
        )..sort((a, b) {
          final bySort = (a['sort_order']! as int).compareTo(
            b['sort_order']! as int,
          );
          return bySort != 0
              ? bySort
              : '${a['name']}'.toLowerCase().compareTo(
                  '${b['name']}'.toLowerCase(),
                );
        });
    return MockResponse.ok(rows);
  });

  server.on('POST', KitchenRoutes.stations, (req) {
    req.requireCap('kitchen.stations.create');
    final body = req.bodyAs(CreateStationRequest.fromJson);
    branchAccess(req, body.branchId);
    final name = body.name.trim();
    if (name.isEmpty) req.badRequest(KitchenRefusals.nameRequired);
    final isDefault = body.isDefault ?? false;
    if (isDefault) clearDefault(body.branchId);
    final row = stations().insert({
      'org_id': db['branches'].find(body.branchId)!['org_id'],
      'branch_id': body.branchId,
      'name': name,
      'name_translations': const <String, Object?>{},
      'sort_order': body.sortOrder ?? 0,
      'printer_brand': body.printerBrand?.value,
      'printer_ip': body.printerIp,
      'printer_port': body.printerPort,
      'is_default': isDefault,
      'is_active': body.isActive ?? true,
    });
    return MockResponse.created(row);
  });

  server.on('PATCH', KitchenRoutes.station, (req) {
    req.requireCap('kitchen.stations.edit');
    final existing = liveStation(req, req.param('id'));
    final branchId = existing['branch_id']! as String;
    branchAccess(req, branchId);
    final body = req.json;
    final name = body['name'];
    if (name is String && name.trim().isEmpty) {
      req.badRequest(KitchenRefusals.nameEmpty);
    }
    if (body['is_default'] == true) {
      clearDefault(branchId, except: existing['id']! as String);
    }
    final b = req.bodyAs(UpdateStationRequest.fromJson);
    return MockResponse.ok(
      stations().update(existing['id']! as String, {
        if (name is String) 'name': name.trim(),
        'sort_order': ?b.sortOrder,
        if (body.containsKey('printer_brand'))
          'printer_brand': b.printerBrand?.value,
        if (body.containsKey('printer_ip')) 'printer_ip': b.printerIp,
        if (body.containsKey('printer_port')) 'printer_port': b.printerPort,
        'is_default': ?b.isDefault,
        'is_active': ?b.isActive,
      }),
    );
  });

  server.on('DELETE', KitchenRoutes.station, (req) {
    req.requireCap('kitchen.stations.delete');
    final existing = liveStation(req, req.param('id'));
    branchAccess(req, existing['branch_id']! as String);
    stations().update(existing['id']! as String, {'deleted_at': db.nowIso});
    return MockResponse.empty();
  });

  // ── routes ─────────────────────────────────────────────────────────────

  server.on('GET', KitchenRoutes.routes, (req) {
    req.requireCap('kitchen.stations.read');
    final branchId = branchParam(req);
    branchAccess(req, branchId);
    List<MockRow> of(String table, String key) => [
      for (final r in db[table].rows)
        if (r['branch_id'] == branchId)
          {key: r[key], 'station_id': r['station_id']},
    ];
    return MockResponse.ok({
      'categories': of(KitchenSeed.categoryRoutesTable, 'category_id'),
      'items': of(KitchenSeed.itemRoutesTable, 'menu_item_id'),
    });
  });

  for (final (template, table, key) in [
    (
      KitchenRoutes.categoryRoute,
      KitchenSeed.categoryRoutesTable,
      'category_id',
    ),
    (KitchenRoutes.itemRoute, KitchenSeed.itemRoutesTable, 'menu_item_id'),
  ]) {
    server.on('PUT', template, (req) {
      req.requireCap('kitchen.stations.edit');
      final branchId = bodyString(req, 'branch_id');
      final target = bodyString(req, key);
      final stationId = bodyString(req, 'station_id');
      branchAccess(req, branchId);
      stationInBranch(req, stationId, branchId);
      db[table]
        ..removeWhere((r) => r['branch_id'] == branchId && r[key] == target)
        ..insert({
          'branch_id': branchId,
          key: target,
          'station_id': stationId,
        }, timestamps: false);
      return MockResponse.empty();
    });

    server.on('DELETE', template, (req) {
      req.requireCap('kitchen.stations.edit');
      final branchId = branchParam(req);
      final target =
          req.q(key) ??
          req.badRequest('Query deserialize error: missing field `$key`');
      branchAccess(req, branchId);
      db[table].removeWhere(
        (r) => r['branch_id'] == branchId && r[key] == target,
      );
      return MockResponse.empty();
    });
  }

  // ── routing mode ───────────────────────────────────────────────────────

  server.on('GET', KitchenRoutes.routingMode, (req) {
    req.requireCap('kitchen.stations.read');
    final branchId = branchParam(req);
    branchAccess(req, branchId);
    return MockResponse.ok({
      'mode': db[KitchenSeed.modesTable].firstWhere(
        (r) => r['branch_id'] == branchId,
      )?['mode'],
      'effective': kitchenEffectiveMode(db, branchId),
    });
  });

  server.on('PUT', KitchenRoutes.routingMode, (req) {
    req.requireCap('kitchen.stations.edit');
    final body = req.bodyAs(SetRoutingModeRequest.fromJson);
    branchAccess(req, body.branchId);
    final mode = body.mode;
    if (mode != null && !const ['kds', 'till', 'both', 'off'].contains(mode)) {
      req.badRequest(KitchenRefusals.badMode);
    }
    final modes = db[KitchenSeed.modesTable]
      ..removeWhere((r) => r['branch_id'] == body.branchId);
    if (mode != null) {
      modes.insert({'branch_id': body.branchId, 'mode': mode}, timestamps: false);
    }
    return MockResponse.ok({
      'mode': mode,
      'effective': kitchenEffectiveMode(db, body.branchId),
    });
  });

  // ── the menu (catalog_menu's in the app) ───────────────────────────────

  onIfAbsent(server, 'GET', KitchenRoutes.categories, (req) {
    req.requireCap('menu.categories.read');
    final org = req.q('org_id');
    if (org == null) {
      req.badRequest('Query deserialize error: missing field `org_id`');
    }
    req.requireSameOrg(org);
    return MockResponse.ok(
      db['categories'].where((c) => c['org_id'] == org && c['deleted_at'] == null)
        ..sort((a, b) {
          final byOrder = (a['display_order']! as int).compareTo(
            b['display_order']! as int,
          );
          return byOrder != 0
              ? byOrder
              : '${a['name']}'.compareTo('${b['name']}');
        }),
    );
  });

  onIfAbsent(server, 'GET', KitchenRoutes.catalog, (req) {
    req.requireCap('menu.items.read');
    final org = req.q('org_id');
    if (org == null) {
      req.badRequest('Query deserialize error: missing field `org_id`');
    }
    req.requireSameOrg(org);
    final search = req.q('search')?.trim().toLowerCase();
    final category = req.q('category_id');
    final rows =
        db['menu_items'].where(
          (m) =>
              m['org_id'] == org &&
              m['deleted_at'] == null &&
              (category == null || m['category_id'] == category) &&
              (search == null ||
                  search.isEmpty ||
                  '${m['name']}'.toLowerCase().contains(search)),
        )..sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
    return MockResponse.ok(
      pageOf(
        [
          for (final m in rows) {...m, 'sku_costs': const <Object?>[]},
        ],
        req,
        maxPerPage: 500,
      ),
    );
  });
}
