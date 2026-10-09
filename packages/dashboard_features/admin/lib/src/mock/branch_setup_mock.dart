/// `/branch-setup` Branch setup (ADM-BSU rows): the mock backend for the
/// branch plan, as MadarRust `src/branch_plan/{handlers,mod}.rs` answers.
///
/// - `GET /branch-plan?branch_id=` (get_plan): `kitchen.stations.read` +
///   branch access. A saved branch (version > 0) reads its slots, printers
///   and links from the plan tables and its sections from the live kitchen
///   stations, with a printer changed on the kitchen-stations page or in the
///   branch dialog put back in (`keep_live_printers`); a never-saved branch
///   is assembled from its registered devices, its printer columns and its
///   stations. The view carries the registered devices (retired left out),
///   the org's live categories, items cooking per section and items routed
///   one by one per section; `routing_mode` is the effective mode.
/// - `GET /branch-plan/versions?branch_id=` (list_versions): the same gate;
///   the last 20 saved plans, newest first, with the saver's name.
/// - `PUT /branch-plan` (save_plan): `kitchen.stations.edit` + branch
///   access; every blocking check (400, the sentences joined by "; ");
///   `kitchen.stations.create` for a section that is not a station yet and
///   `.delete` for an active station the plan drops; 409 `PLAN_CHANGED` on a
///   stale version; 400 for a category or device that is not this org's or
///   branch's, or a piece of another branch; 409 `SECTION_HAS_OPEN_TICKETS`
///   for a dropped station with items cooking. Then, as the server does in
///   one transaction: dropped stations soft-deleted (their item routes
///   gone), slots and printers rewritten (a removed slot takes its
///   activation codes with it, so they leave `/devices`), sections upserted
///   with their screens, printers and category routes, each station's
///   printer columns set from its first network kitchen printer, the
///   branch's routing mode, till-chits flag and printer columns (from the
///   first POS printing receipts on a network printer; brand kept when the
///   plan's is Other) written, a version row stored, the version bumped and
///   `branch.plan_changed` published on the branch stream.
/// - `POST /devices/activation-codes` (create_code) is answered here too, so
///   a code made for a slot (`slot_id`) takes the slot's kind (a kitchen
///   screen runs the KDS app) and name, and a slot a save removed is 404.
///   Without `slot_id` it answers exactly as the Devices mock does.
///
/// Data: the kitchen stations, routes and routing modes are the setup
/// area's (`KitchenSeed`, the same rows, seeded only when absent, since in
/// the app both areas share one database); Heliopolis has a saved plan
/// (version 2, with version 1 in its history), the other branches have never
/// saved one. Heliopolis's Bar has three items cooking, Zamalek's Kitchen
/// two.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart'
    show TransportRealtimeGateway;

import '../area_seed.dart';
import '../branch_setup/plan.dart';

/// The routes, for tests.
abstract final class BranchPlanRoutes {
  static const String plan = '/branch-plan';
  static const String versions = '/branch-plan/versions';
  static const String codes = '/devices/activation-codes';
}

/// The tables (the first four are the setup area's kitchen tables).
abstract final class BranchPlanTables {
  static const String stations = 'kitchen_stations';
  static const String categoryRoutes = 'category_station_routes';
  static const String itemRoutes = 'menu_item_station_routes';
  static const String modes = 'kitchen_routing_modes';
  static const String slots = 'branch_device_slots';
  static const String printers = 'branch_printers';
  static const String screens = 'kitchen_station_screens';
  static const String stationPrinters = 'kitchen_station_printers';
  static const String versions = 'branch_plan_versions';

  /// `{id, branch_id, station_id, status, closed_at, bumped_at, voided_at}`:
  /// the kitchen ticket items, as far as the plan cares.
  static const String ticketItems = 'kitchen_ticket_items';
}

/// The backend's refusal sentences.
abstract final class BranchPlanRefusals {
  static const String planChanged =
      "Someone saved this branch's plan while you were editing. Reload to see their version.";
  static const String unknownCategory =
      "The plan routes a category that doesn't exist";
  static const String unknownDevice =
      "The plan assigns a device that isn't registered at this branch";
  static const String slotGone = "That slot is not in this branch's plan";
}

abstract final class BranchPlanSeed {
  static String stationId(String branch, String key) =>
      mockUuid('kitchen-station:$branch:$key');
  static String slotId(String branch, String key) =>
      mockUuid('plan-slot:$branch:$key');
  static String printerId(String branch, String key) =>
      mockUuid('plan-printer:$branch:$key');

  static KitchenStation _station(
    String branch,
    String key,
    String name, {
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
    nameTranslations: const <String, Object?>{},
    sortOrder: sort,
    printerBrand: brand,
    printerIp: ip,
    printerPort: brand == null ? null : 9100,
    isDefault: isDefault,
    isActive: isActive,
    createdAt: DateTime.utc(2026, 3, 2, 8),
    updatedAt: updated ?? DateTime.utc(2026, 3, 2, 8),
  );

  /// The setup area's `KitchenSeed.stations`, row for row.
  static List<KitchenStation> get stations => [
    _station(
      'zamalek',
      'bar',
      'Bar',
      sort: 0,
      brand: PrinterBrand.epson,
      ip: '192.168.10.21',
      isDefault: true,
    ),
    _station(
      'zamalek',
      'kitchen',
      'Kitchen',
      sort: 1,
      brand: PrinterBrand.star,
      ip: '192.168.10.22',
    ),
    _station(
      'zamalek',
      'pastry',
      'Pastry',
      sort: 2,
      isActive: false,
      updated: DateTime.utc(2026, 8, 14, 9),
    ),
    _station(
      'heliopolis',
      'bar',
      'Bar',
      sort: 0,
      brand: PrinterBrand.epson,
      ip: '192.168.1.60',
      isDefault: true,
    ),
    _station(
      'heliopolis',
      'kitchen',
      'Kitchen',
      sort: 1,
      brand: PrinterBrand.star,
      ip: '192.168.1.61',
    ),
  ];

  static const List<(String, String, String)> _categoryRoutes = [
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

  static List<MockRow> get categoryRoutes => [
    for (final (b, c, s) in _categoryRoutes)
      {
        'branch_id': MockSeed.branchIdOf(b),
        'category_id': MockSeed.categoryId(c),
        'station_id': stationId(b, s),
      },
  ];

  static List<MockRow> get itemRoutes => [
    for (final (b, i, s) in const [
      ('zamalek', 'croissant', 'kitchen'),
      ('zamalek', 'cookie', 'pastry'),
    ])
      {
        'branch_id': MockSeed.branchIdOf(b),
        'menu_item_id': MockSeed.menuItemId(i),
        'station_id': stationId(b, s),
      },
  ];

  static List<MockRow> get modes => [
    for (final (b, m) in const [('heliopolis', 'both'), ('new-cairo', 'off')])
      {'branch_id': MockSeed.branchIdOf(b), 'mode': m},
  ];

  /// Items cooking now: three at Heliopolis's Bar, two in Zamalek's Kitchen.
  static List<MockRow> get ticketItems => [
    for (final (b, s, n) in const [
      ('heliopolis', 'bar', 3),
      ('zamalek', 'kitchen', 2),
    ])
      for (var i = 0; i < n; i++)
        {
          'id': mockUuid('kitchen-ticket-item:$b:$s:$i'),
          'branch_id': MockSeed.branchIdOf(b),
          'station_id': stationId(b, s),
          'status': 'firing',
          'closed_at': null,
          'bumped_at': null,
          'voided_at': null,
        },
  ];

  static final String heliopolis = SeedIds.heliopolis;
  static final String counter = slotId('heliopolis', 'counter');
  static final String screen = slotId('heliopolis', 'screen');
  static final String receipt = printerId('heliopolis', 'receipt');
  static final String barPrinter = printerId('heliopolis', 'bar');
  static final String kitchenPrinter = printerId('heliopolis', 'kitchen');

  /// Heliopolis's plan as saved in version 2 (its tables hold the same).
  static Map<String, Object?> heliopolisPlan(String branchPrinterIp) => {
    'devices': [
      {
        'id': counter,
        'kind': 'pos',
        'name': 'Counter 1',
        'receipt_printer_id': receipt,
        'device_id': AdminSeed.deviceId('heliopolis', 'T1'),
        'x': 0.0,
        'y': 0.0,
      },
      {
        'id': screen,
        'kind': 'kitchen',
        'name': 'Kitchen screen',
        'receipt_printer_id': null,
        'device_id': AdminSeed.deviceId('heliopolis', 'K1'),
        'x': 680.0,
        'y': 0.0,
      },
    ],
    'printers': [
      _printer(receipt, 'receipt', 'Receipt printer', branchPrinterIp, 'epson', 0, 180),
      _printer(barPrinter, 'kitchen', 'Bar printer', '192.168.1.60', 'epson', 680, 120),
      _printer(kitchenPrinter, 'kitchen', 'Kitchen printer', '192.168.1.61', 'star', 680, 240),
    ],
    'sections': [
      {
        'id': stationId('heliopolis', 'bar'),
        'name': 'Bar',
        'is_default': true,
        'category_ids': [MockSeed.categoryId('hot'), MockSeed.categoryId('iced')],
        'screen_ids': [screen],
        'printer_ids': [barPrinter],
        'x': 340.0,
        'y': 0.0,
      },
      {
        'id': stationId('heliopolis', 'kitchen'),
        'name': 'Kitchen',
        'is_default': false,
        'category_ids': [MockSeed.categoryId('breakfast')],
        'screen_ids': <String>[],
        'printer_ids': [kitchenPrinter],
        'x': 340.0,
        'y': 180.0,
      },
    ],
    'till_prints_kitchen': true,
  };

  static Map<String, Object?> _printer(
    String id,
    String role,
    String name,
    String ip,
    String brand,
    double x,
    double y,
  ) => {
    'id': id,
    'role': role,
    'name': name,
    'connection': 'network',
    'brand': brand,
    'ip': ip,
    'port': 9100,
    'paper_mm': 80,
    'host_device_id': null,
    'x': x,
    'y': y,
  };

  /// Version 1: the same branch before its kitchen screen came.
  static Map<String, Object?> heliopolisV1(String branchPrinterIp) {
    final v2 = heliopolisPlan(branchPrinterIp);
    return {
      ...v2,
      'devices': [(v2['devices']! as List).first],
      'sections': [
        for (final s in (v2['sections']! as List).cast<Map<String, Object?>>())
          {...s, 'screen_ids': <String>[]},
      ],
    };
  }

  static final DateTime v1At = DateTime.utc(2026, 9, 1, 9, 30);
  static final DateTime v2At = DateTime.utc(2026, 9, 20, 10, 15);
}

final RegExp _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

void _seedIfAbsent(MockDb db, String table, Iterable<MockRow> Function() rows) {
  if (!db.hasTable(table)) db.lazyTable(table, rows);
}

void registerBranchSetupMocks(MockServer server, MockDb db) {
  _seedIfAbsent(
    db,
    BranchPlanTables.stations,
    () => [for (final s in BranchPlanSeed.stations) s.toJson()],
  );
  _seedIfAbsent(
    db,
    BranchPlanTables.categoryRoutes,
    () => BranchPlanSeed.categoryRoutes,
  );
  _seedIfAbsent(db, BranchPlanTables.itemRoutes, () => BranchPlanSeed.itemRoutes);
  _seedIfAbsent(db, BranchPlanTables.modes, () => BranchPlanSeed.modes);
  _seedIfAbsent(
    db,
    BranchPlanTables.ticketItems,
    () => BranchPlanSeed.ticketItems,
  );
  if (!db.hasTable(BranchPlanTables.versions)) _seedHeliopolis(db);

  MockTable t(String name) => db[name];

  void branchAccess(MockRequest req, String branchId) {
    if (req.persona.isPlatform) return;
    final b = db['branches'].find(branchId);
    if (b == null || b['deleted_at'] != null) req.notFound('Branch not found');
    if (b['org_id'] != req.orgId) {
      req.fail(MockResponse.forbidden('Branch belongs to a different org'));
    }
    req.requireBranch(branchId);
  }

  String branchParam(MockRequest req) {
    final raw = req.q('branch_id');
    if (raw == null) {
      req.badRequest('Query deserialize error: missing field `branch_id`');
    }
    if (!_uuid.hasMatch(raw)) {
      req.badRequest(
        'Query deserialize error: branch_id: UUID parsing failed: invalid character',
      );
    }
    return raw;
  }

  MockResponse view(String branchId) =>
      MockResponse.ok(planView(db, branchId).toJson());

  server.on('GET', BranchPlanRoutes.plan, (req) {
    final branchId = branchParam(req);
    req.requireCap('kitchen.stations.read');
    branchAccess(req, branchId);
    return view(branchId);
  });

  server.on('GET', BranchPlanRoutes.versions, (req) {
    final branchId = branchParam(req);
    req.requireCap('kitchen.stations.read');
    branchAccess(req, branchId);
    final rows = t(BranchPlanTables.versions).where(
      (v) => v['branch_id'] == branchId,
    )..sort((a, b) => (b['version']! as int).compareTo(a['version']! as int));
    return MockResponse.ok([
      for (final v in rows.take(20))
        {
          'version': v['version'],
          'saved_at': v['saved_at'],
          'saved_by_name': db['users'].find('${v['saved_by']}')?['name'],
          'plan': v['plan'],
        },
    ]);
  });

  server.on('PUT', BranchPlanRoutes.plan, (req) {
    req.requireCap('kitchen.stations.edit');
    final body = req.bodyAs(SavePlanRequest.fromJson);
    final branchId = body.branchId;
    branchAccess(req, branchId);
    final plan = fromWire(body.plan);
    final ids = [
      for (final d in plan.devices) d.id,
      for (final p in plan.printers) p.id,
      for (final s in plan.sections) s.id,
      for (final s in plan.sections) ...s.categoryIds,
      for (final d in plan.devices) ?d.deviceId,
    ];
    final bad = ids.where((id) => !_uuid.hasMatch(id)).firstOrNull;
    if (bad != null) {
      req.badRequest(
        'Json deserialize error: UUID parsing failed: invalid character ($bad)',
      );
    }
    final problems = serverCheck(plan);
    if (problems.isNotEmpty) req.badRequest(problems.join('; '));

    final stations = t(BranchPlanTables.stations).where(
      (s) => s['branch_id'] == branchId && s['deleted_at'] == null,
    );
    final planSections = {for (final s in plan.sections) s.id};
    if (plan.sections.any((s) => !stations.any((r) => r['id'] == s.id))) {
      req.requireCap('kitchen.stations.create');
    }
    if (stations.any(
      (r) => r['is_active'] == true && !planSections.contains(r['id']),
    )) {
      req.requireCap('kitchen.stations.delete');
    }

    final branch = db['branches'].get(branchId);
    final orgId = branch['org_id']! as String;
    final version = (branch['hardware_plan_version'] as int?) ?? 0;
    if (version != body.expectedVersion) {
      req.conflict(BranchPlanRefusals.planChanged, code: 'PLAN_CHANGED');
    }

    // check_references
    final cats = {for (final s in plan.sections) ...s.categoryIds};
    final liveCats = {
      for (final c in db['categories'].rows)
        if (c['org_id'] == orgId && c['deleted_at'] == null) c['id'],
    };
    if (!liveCats.containsAll(cats)) {
      req.badRequest(BranchPlanRefusals.unknownCategory);
    }
    final devs = [for (final d in plan.devices) ?d.deviceId];
    final registered = {
      for (final d in t(AdminTables.devices).rows)
        if (d['branch_id'] == branchId && d['retired_at'] == null) d['id'],
    };
    if (!devs.every(registered.contains)) {
      req.badRequest(BranchPlanRefusals.unknownDevice);
    }

    // remove_sections: a dropped station still cooking refuses the save.
    final dropped = [
      for (final s in stations)
        if (s['is_active'] == true && !planSections.contains(s['id'])) s,
    ];
    final busy = <String, int>{};
    for (final s in dropped) {
      final n = openItemsAt(db, branchId)[s['id']] ?? 0;
      if (n > 0) busy[s['name']! as String] = n;
    }
    if (busy.isNotEmpty) {
      final names = busy.keys.toList()..sort();
      final list = [for (final n in names) "'$n' (${busy[n]})"].join(', ');
      req.conflict(
        'Items are still cooking in $list. Finish or move them before removing the section.',
        code: 'SECTION_HAS_OPEN_TICKETS',
      );
    }

    // Pieces of another branch (the upserts' WHERE).
    void ownBranch(String table, String id, String what) {
      final row = t(table).find(id);
      if (row != null && row['branch_id'] != branchId) {
        req.badRequest('$what $id belongs to another branch');
      }
    }

    for (final d in plan.devices) {
      ownBranch(BranchPlanTables.slots, d.id, 'Device');
    }
    for (final p in plan.printers) {
      ownBranch(BranchPlanTables.printers, p.id, 'Printer');
    }
    for (final s in plan.sections) {
      ownBranch(BranchPlanTables.stations, s.id, 'Section');
    }

    final now = req.now.toIso8601String();
    for (final s in dropped) {
      s
        ..['deleted_at'] = now
        ..['is_default'] = false
        ..['updated_at'] = now;
      t(BranchPlanTables.itemRoutes).removeWhere(
        (r) => r['branch_id'] == branchId && r['station_id'] == s['id'],
      );
    }
    _writePieces(db, orgId, branchId, plan);
    _writeSections(db, orgId, branchId, plan, now);
    _writeBranch(db, branch, plan);
    final saved = toWire(plan).toJson();
    t(BranchPlanTables.versions).insert({
      'id': db.newId(BranchPlanTables.versions),
      'org_id': orgId,
      'branch_id': branchId,
      'version': version + 1,
      'plan': saved,
      'saved_by': req.persona.userId,
      'saved_at': now,
    }, timestamps: false);
    branch['hardware_plan_version'] = version + 1;
    server.publish(
      realtimeChannel(branchId),
      TransportRealtimeGateway.encode(
        'branch.plan_changed',
        data: {'branch_id': branchId, 'version': version + 1},
      ),
    );
    return view(branchId);
  });

  // ── a setup code for a slot ──────────────────────────────────────────

  MockRow codeOut(MockRow c, DateTime now) {
    final expires = DateTime.parse(c['expires_at']! as String);
    final state = c['revoked_at'] != null
        ? 'revoked'
        : c['used_at'] != null
        ? 'used'
        : !expires.isAfter(now)
        ? 'expired'
        : 'free';
    return {...c, 'state': state};
  }

  server.on('POST', BranchPlanRoutes.codes, (req) {
    final body = req.bodyAs(CreateActivationCodeRequest.fromJson);
    branchAccess(req, body.branchId);
    req.requireCap('branches.edit', branchId: body.branchId);
    final slotId = body.slotId;
    MockRow? slot;
    if (slotId != null) {
      slot = t(BranchPlanTables.slots).firstWhere(
        (s) => s['id'] == slotId && s['branch_id'] == body.branchId,
      );
      if (slot == null) req.notFound(BranchPlanRefusals.slotGone);
    }
    final kind = slot != null
        ? (slot['kind'] == 'kitchen' ? 'kds' : slot['kind']! as String)
        : body.kind?.value ?? 'pos';
    if (!const {'pos', 'kds', 'waiter'}.contains(kind)) {
      req.badRequest('kind must be pos, kds or waiter');
    }
    final l = body.label?.trim();
    final given = l == null || l.isEmpty ? (slot?['name'] as String?) : l;
    final label = given == null
        ? null
        : String.fromCharCodes(given.runes.take(120));
    final now = req.now;
    final codes = t(AdminTables.activationCodes);
    // Eight digits, unique among the codes still free, deterministic per run
    // (the Devices mock's sequence).
    final live = {
      for (final c in codes.rows)
        if (codeOut(c, now)['state'] == 'free') c['code'],
    };
    var n = codes.length;
    String code;
    do {
      n++;
      final h = mockUuid('activation-code#$n').replaceAll('-', '');
      code = (int.parse(h.substring(0, 12), radix: 16) % 100000000)
          .toString()
          .padLeft(8, '0');
    } while (live.contains(code));
    final row = codes.insert({
      'id': db.newId(AdminTables.activationCodes),
      'branch_id': body.branchId,
      'code': code,
      'label': label,
      'kind': kind,
      'created_at': now.toIso8601String(),
      'expires_at': now.add(const Duration(hours: 24)).toIso8601String(),
      'used_at': null,
      'used_by_device': null,
      'revoked_at': null,
      'slot_id': slotId,
    }, timestamps: false);
    return MockResponse.created(codeOut(row, now));
  });
}

/// The device side (not a dashboard call): a tablet types a slot's code and
/// takes the slot, leaving any slot it held. No version bump, no event, as
/// on the server (ADM-BSU-060).
void activateSlotCode(MockDb db, String code, String deviceId) {
  final c = db[AdminTables.activationCodes].firstWhere(
    (r) => r['code'] == code && r['used_at'] == null,
  )!;
  c
    ..['used_at'] = db.nowIso
    ..['used_by_device'] = deviceId;
  final slot = c['slot_id'];
  if (slot == null) return;
  for (final s in db[BranchPlanTables.slots].rows) {
    if (s['device_id'] == deviceId && s['id'] != slot) s['device_id'] = null;
  }
  db[BranchPlanTables.slots].find('$slot')?['device_id'] = deviceId;
}

void _seedHeliopolis(MockDb db) {
  final branch = db['branches'].find(BranchPlanSeed.heliopolis);
  if (branch == null) return;
  final ip = (branch['printer_ip'] as String?) ?? '192.168.1.40';
  final v2 = BranchPlanSeed.heliopolisPlan(ip);
  final plan = BuilderPlan.fromJson(v2);
  _writePieces(db, SeedIds.sabahOrg, BranchPlanSeed.heliopolis, plan);
  for (final s in plan.sections) {
    for (final id in s.screenIds) {
      db[BranchPlanTables.screens].insert({
        'station_id': s.id,
        'slot_id': id,
      }, timestamps: false);
    }
    for (final id in s.printerIds) {
      db[BranchPlanTables.stationPrinters].insert({
        'station_id': s.id,
        'printer_id': id,
      }, timestamps: false);
    }
  }
  for (final (i, (at, p)) in [
    (BranchPlanSeed.v1At, BranchPlanSeed.heliopolisV1(ip)),
    (BranchPlanSeed.v2At, v2),
  ].indexed) {
    db[BranchPlanTables.versions].insert({
      'id': mockUuid('plan-version:heliopolis:${i + 1}'),
      'org_id': SeedIds.sabahOrg,
      'branch_id': BranchPlanSeed.heliopolis,
      'version': i + 1,
      'plan': p,
      'saved_by': SeedIds.owner,
      'saved_at': at.toIso8601String(),
    }, timestamps: false);
  }
  branch
    ..['hardware_plan_version'] = 2
    ..['till_prints_kitchen'] = true;
}

/// Firing items not bumped or voided, per station of [branchId].
Map<Object?, int> openItemsAt(MockDb db, String branchId) {
  final out = <Object?, int>{};
  for (final r in db[BranchPlanTables.ticketItems].rows) {
    if (r['branch_id'] != branchId ||
        r['status'] != 'firing' ||
        r['closed_at'] != null ||
        r['bumped_at'] != null ||
        r['voided_at'] != null ||
        r['station_id'] == null) {
      continue;
    }
    out[r['station_id']] = (out[r['station_id']] ?? 0) + 1;
  }
  return out;
}

/// The effective kitchen routing mode (`effective_routing_mode`): the stored
/// one, else `kds` with an active station, else `till`.
String effectiveRoutingMode(MockDb db, String branchId) {
  final stored = db[BranchPlanTables.modes].firstWhere(
    (r) => r['branch_id'] == branchId,
  )?['mode'];
  if (stored is String) return stored;
  final active = db[BranchPlanTables.stations].rows.any(
    (s) =>
        s['branch_id'] == branchId &&
        s['is_active'] == true &&
        s['deleted_at'] == null,
  );
  return active ? 'kds' : 'till';
}

List<MockRow> _liveStations(MockDb db, String branchId) =>
    db[BranchPlanTables.stations].where(
      (s) =>
          s['branch_id'] == branchId &&
          s['deleted_at'] == null &&
          s['is_active'] == true,
    )..sort((a, b) {
      final o = (a['sort_order'] as int? ?? 0).compareTo(
        b['sort_order'] as int? ?? 0,
      );
      return o != 0
          ? o
          : '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase());
    });

List<MockRow> _categories(MockDb db, String orgId) =>
    db['categories'].where(
      (c) =>
          c['org_id'] == orgId &&
          c['deleted_at'] == null &&
          c['is_active'] != false,
    )..sort((a, b) {
      final da = a['display_order'] as int?, dbo = b['display_order'] as int?;
      if (da != dbo) {
        if (da == null) return 1;
        if (dbo == null) return -1;
        return da.compareTo(dbo);
      }
      return '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase());
    });

/// Category ids per station, in the menu's order.
Map<Object?, List<String>> _routes(MockDb db, String branchId, String orgId) {
  final order = [for (final c in _categories(db, orgId)) c['id']];
  final rows = db[BranchPlanTables.categoryRoutes].where(
    (r) => r['branch_id'] == branchId && order.contains(r['category_id']),
  )..sort(
      (a, b) => order
          .indexOf(a['category_id'])
          .compareTo(order.indexOf(b['category_id'])),
    );
  final out = <Object?, List<String>>{};
  for (final r in rows) {
    (out[r['station_id']] ??= []).add(r['category_id']! as String);
  }
  return out;
}

List<MockRow> _registered(MockDb db, String branchId) =>
    db[AdminTables.devices].where(
      (d) => d['branch_id'] == branchId && d['retired_at'] == null,
    )..sort((a, b) {
      final k = '${a['kind']}'.compareTo('${b['kind']}');
      return k != 0 ? k : '${a['code']}'.compareTo('${b['code']}');
    });

/// `GET /branch-plan` for [branchId].
BranchPlanView planView(MockDb db, String branchId) {
  final b = db['branches'].get(branchId);
  final orgId = b['org_id']! as String;
  final version = (b['hardware_plan_version'] as int?) ?? 0;
  final plan = version > 0
      ? _loadSaved(db, branchId, b)
      : _assemble(db, branchId, b);
  final open = openItemsAt(db, branchId);
  final overrides = <Object?, int>{};
  for (final r in db[BranchPlanTables.itemRoutes].rows) {
    if (r['branch_id'] == branchId) {
      overrides[r['station_id']] = (overrides[r['station_id']] ?? 0) + 1;
    }
  }
  return BranchPlanView.fromJson({
    'branch_id': branchId,
    'version': version,
    'saved': version > 0,
    'plan': toWire(plan).toJson(),
    'routing_mode': effectiveRoutingMode(db, branchId),
    'devices': [
      for (final d in _registered(db, branchId))
        {
          'id': d['id'],
          'code': d['code'],
          'label': d['label'],
          'kind': d['kind'],
          'platform': d['platform'],
          'app_version': d['app_version'],
          'last_seen_at': d['last_seen_at'],
        },
    ],
    'categories': [
      for (final c in _categories(db, orgId))
        {
          'id': c['id'],
          'name': c['name'],
          'name_translations': c['name_translations'],
        },
    ],
    'open_items': [
      for (final e in open.entries) {'section_id': e.key, 'count': e.value},
    ],
    'item_overrides': [
      for (final e in overrides.entries)
        {'section_id': e.key, 'count': e.value},
    ],
  });
}

const double _colFront = 0, _colSections = 340, _colOutputs = 680, _row = 120;

/// A stable id per branch and purpose (the server's `Uuid::new_v5`).
String _stableId(String branchId, String what) =>
    mockUuid('plan-stable:$branchId:$what');

/// A branch never saved: assembled from what it already has.
BuilderPlan _assemble(MockDb db, String branchId, MockRow b) {
  final ip = b['printer_ip'] as String?;
  final receiptId = ip == null ? null : _stableId(branchId, 'receipt-printer');
  final devices = <BuilderDevice>[];
  var front = 0.0, out = 0.0;
  for (final d in _registered(db, branchId)) {
    final kind = switch (d['kind']) {
      'kds' => 'kitchen',
      'waiter' => 'waiter',
      _ => 'pos',
    };
    final double x, y;
    if (kind == 'kitchen') {
      out += 1;
      (x, y) = (_colOutputs, (out - 1) * _row);
    } else {
      front += 1;
      (x, y) = (_colFront, (front - 1) * _row);
    }
    final label = (d['label'] as String?)?.trim();
    devices.add(
      BuilderDevice(
        id: _stableId(branchId, 'device:${d['id']}'),
        kind: kind,
        name: label == null || label.isEmpty ? d['code']! as String : label,
        receiptPrinterId: kind == 'kitchen' ? null : receiptId,
        deviceId: d['id']! as String,
        x: x,
        y: y,
      ),
    );
  }
  final printers = <BuilderPrinter>[
    if (receiptId != null)
      BuilderPrinter(
        id: receiptId,
        role: 'receipt',
        name: 'Receipt printer',
        connection: 'network',
        brand: b['printer_brand'] as String?,
        ip: ip,
        port: (b['printer_port'] as int?) ?? 9100,
        paperMm: 80,
        x: _colFront,
        y: front * _row + _row * 0.5,
      ),
  ];
  final cats = _routes(db, branchId, b['org_id']! as String);
  final sections = <BuilderSection>[];
  for (final (i, s) in _liveStations(db, branchId).indexed) {
    final printerIds = <String>[];
    final sip = (s['printer_ip'] as String?)?.trim();
    if (sip != null && sip.isNotEmpty) {
      final id = _stableId(branchId, 'station-printer:${s['id']}');
      out += 1;
      printers.add(
        BuilderPrinter(
          id: id,
          role: 'kitchen',
          name: '${s['name']} printer',
          connection: 'network',
          brand: s['printer_brand'] as String?,
          ip: sip,
          port: (s['printer_port'] as int?) ?? 9100,
          paperMm: 80,
          x: _colOutputs,
          y: (out - 1) * _row,
        ),
      );
      printerIds.add(id);
    }
    sections.add(
      BuilderSection(
        id: s['id']! as String,
        name: s['name']! as String,
        isDefault: s['is_default'] == true,
        categoryIds: cats[s['id']] ?? const [],
        printerIds: printerIds,
        x: (s['canvas_x'] as num?)?.toDouble() ?? _colSections,
        y: (s['canvas_y'] as num?)?.toDouble() ?? i * _row * 1.5,
      ),
    );
  }
  if (sections.isNotEmpty && !sections.any((s) => s.isDefault)) {
    sections[0] = sections[0].copyWith(isDefault: true);
  }
  final stored = db[BranchPlanTables.modes].firstWhere(
    (r) => r['branch_id'] == branchId,
  )?['mode'];
  return BuilderPlan(
    devices: devices,
    printers: printers,
    sections: sections,
    tillPrintsKitchen: stored == null || stored == 'till' || stored == 'both',
  );
}

bool _samePrinter(BuilderPrinter p, String ip, int? port) =>
    p.network && p.ip?.trim() == ip.trim() && (p.port ?? 9100) == (port ?? 9100);

/// A saved branch: its tables, with printers changed elsewhere put back.
BuilderPlan _loadSaved(MockDb db, String branchId, MockRow b) {
  int order(MockRow a, MockRow c) =>
      (a['sort_order'] as int? ?? 0).compareTo(c['sort_order'] as int? ?? 0);
  final slots = db[BranchPlanTables.slots].where(
    (s) => s['branch_id'] == branchId,
  )..sort(order);
  final printerRows = db[BranchPlanTables.printers].where(
    (p) => p['branch_id'] == branchId,
  )..sort(order);
  final devices = [
    for (final s in slots)
      BuilderDevice(
        id: s['id']! as String,
        kind: s['kind']! as String,
        name: s['name']! as String,
        receiptPrinterId: s['receipt_printer_id'] as String?,
        deviceId: s['device_id'] as String?,
        x: (s['canvas_x']! as num).toDouble(),
        y: (s['canvas_y']! as num).toDouble(),
      ),
  ];
  final printers = [
    for (final p in printerRows) BuilderPrinter.fromJson(p),
  ];
  final stations = _liveStations(db, branchId);
  final cats = _routes(db, branchId, b['org_id']! as String);
  final slotIds = [for (final s in slots) s['id']];
  final printerIds = [for (final p in printerRows) p['id']];
  List<String> linked(String table, String key, Object? station, List<Object?> order) =>
      [
        for (final r in db[table].where((r) => r['station_id'] == station))
          r[key]! as String,
      ]..sort((a, c) => order.indexOf(a).compareTo(order.indexOf(c)));
  final sections = [
    for (final (i, s) in stations.indexed)
      BuilderSection(
        id: s['id']! as String,
        name: s['name']! as String,
        isDefault: s['is_default'] == true,
        categoryIds: cats[s['id']] ?? const [],
        screenIds: linked(BranchPlanTables.screens, 'slot_id', s['id'], slotIds),
        printerIds: linked(
          BranchPlanTables.stationPrinters,
          'printer_id',
          s['id'],
          printerIds,
        ),
        x: (s['canvas_x'] as num?)?.toDouble() ?? _colSections,
        y: (s['canvas_y'] as num?)?.toDouble() ?? i * _row * 1.5,
      ),
  ];

  // keep_live_printers: a station printer changed since the last save.
  for (final (i, s) in sections.indexed) {
    final row = stations[i];
    final ip = (row['printer_ip'] as String?)?.trim();
    if (ip == null || ip.isEmpty) continue;
    final port = row['printer_port'] as int?;
    final brand = row['printer_brand'] as String?;
    final first = s.printerIds
        .map((id) => printers.where((p) => p.id == id).firstOrNull)
        .whereType<BuilderPrinter>()
        .where((p) => p.network)
        .firstOrNull;
    if (first != null && _samePrinter(first, ip, port) && first.brand == brand) {
      continue;
    }
    var id = printers
        .where(
          (p) => p.role == 'kitchen' && _samePrinter(p, ip, port) && p.brand == brand,
        )
        .firstOrNull
        ?.id;
    if (id == null) {
      final p = port ?? 9100;
      id = _stableId(branchId, 'station-printer:${row['id']}:$ip:$p');
      printers.add(
        BuilderPrinter(
          id: id,
          role: 'kitchen',
          name: '${s.name} printer',
          connection: 'network',
          brand: brand,
          ip: ip,
          port: p,
          paperMm: 80,
          x: _colOutputs,
          y: s.y,
        ),
      );
    }
    sections[i] = s.copyWith(
      printerIds: [id, ...s.printerIds.where((x) => x != id)],
    );
  }
  final bip = b['printer_ip'] as String?;
  if (bip != null) {
    final at = devices.indexWhere(
      (d) =>
          d.kind == 'pos' &&
          (printers.where((p) => p.id == d.receiptPrinterId).firstOrNull?.network ??
              false),
    );
    if (at >= 0) {
      final pos = devices[at];
      final bport = b['printer_port'] as int?;
      final bbrand = b['printer_brand'] as String?;
      bool matches(BuilderPrinter p) =>
          _samePrinter(p, bip, bport) && (p.brand == null || p.brand == bbrand);
      final current = printers
          .where((p) => p.id == pos.receiptPrinterId)
          .firstOrNull;
      if (current == null || !matches(current)) {
        var id = printers
            .where((p) => p.role == 'receipt' && matches(p))
            .firstOrNull
            ?.id;
        if (id == null) {
          final p = bport ?? 9100;
          id = _stableId(branchId, 'receipt-printer:$bip:$p');
          printers.add(
            BuilderPrinter(
              id: id,
              role: 'receipt',
              name: 'Receipt printer',
              connection: 'network',
              brand: bbrand,
              ip: bip.trim(),
              port: p,
              paperMm: 80,
              x: _colFront,
              y: pos.y + _row * 0.5,
            ),
          );
        }
        final rid = id;
        devices[at] = pos.copyWith(receiptPrinterId: () => rid);
      }
    }
  }
  return BuilderPlan(
    devices: devices,
    printers: printers,
    sections: sections,
    tillPrintsKitchen: b['till_prints_kitchen'] == true,
  );
}

/// Slots and printers: what the plan dropped goes (a slot with its
/// activation codes), the rest is upserted.
void _writePieces(MockDb db, String orgId, String branchId, BuilderPlan plan) {
  final slots = db[BranchPlanTables.slots];
  final printers = db[BranchPlanTables.printers];
  final keepSlots = {for (final d in plan.devices) d.id};
  final keepPrinters = {for (final p in plan.printers) p.id};
  final goneSlots = {
    for (final s in slots.rows)
      if (s['branch_id'] == branchId && !keepSlots.contains(s['id'])) s['id'],
  };
  slots.removeWhere((s) => goneSlots.contains(s['id']));
  printers.removeWhere(
    (p) => p['branch_id'] == branchId && !keepPrinters.contains(p['id']),
  );
  db[BranchPlanTables.screens].removeWhere(
    (r) => goneSlots.contains(r['slot_id']),
  );
  // `ON DELETE CASCADE`: the codes made for a removed slot go with it.
  db[AdminTables.activationCodes].removeWhere(
    (c) => goneSlots.contains(c['slot_id']),
  );
  for (final (i, d) in plan.devices.indexed) {
    slots.put({
      'id': d.id,
      'org_id': orgId,
      'branch_id': branchId,
      'kind': d.kind,
      'name': d.name.trim(),
      'device_id': d.deviceId,
      'receipt_printer_id': d.receiptPrinterId,
      'canvas_x': d.x,
      'canvas_y': d.y,
      'sort_order': i,
    });
  }
  for (final (i, p) in plan.printers.indexed) {
    printers.put({
      ...p.toJson(),
      'name': p.name.trim(),
      'ip': p.network ? p.ip?.trim() : null,
      'port': p.network ? p.port ?? 9100 : null,
      'host_device_id': p.network ? null : p.hostDeviceId,
      'org_id': orgId,
      'branch_id': branchId,
      'sort_order': i,
    });
  }
}

void _writeSections(
  MockDb db,
  String orgId,
  String branchId,
  BuilderPlan plan,
  String now,
) {
  final stations = db[BranchPlanTables.stations];
  for (final s in stations.rows) {
    if (s['branch_id'] == branchId && s['deleted_at'] == null) {
      s['is_default'] = false;
    }
  }
  for (final (i, s) in plan.sections.indexed) {
    final row = stations.find(s.id);
    final first = s.printerIds
        .map(plan.printer)
        .whereType<BuilderPrinter>()
        .where((p) => p.network)
        .firstOrNull;
    final patch = {
      'name': s.name.trim(),
      'sort_order': i,
      'is_default': s.isDefault,
      'is_active': true,
      'deleted_at': null,
      'canvas_x': s.x,
      'canvas_y': s.y,
      'printer_brand': first?.brand,
      'printer_ip': first?.ip?.trim(),
      'printer_port': first == null ? null : first.port ?? 9100,
      'updated_at': now,
    };
    if (row != null) {
      row.addAll(patch);
    } else {
      stations.insert({
        'id': s.id,
        'org_id': orgId,
        'branch_id': branchId,
        'name_translations': const <String, Object?>{},
        'created_at': now,
        ...patch,
      }, timestamps: false);
    }
  }
  final ids = {
    for (final s in stations.rows)
      if (s['branch_id'] == branchId) s['id'],
  };
  db[BranchPlanTables.screens].removeWhere((r) => ids.contains(r['station_id']));
  db[BranchPlanTables.stationPrinters].removeWhere(
    (r) => ids.contains(r['station_id']),
  );
  db[BranchPlanTables.categoryRoutes].removeWhere(
    (r) => r['branch_id'] == branchId,
  );
  for (final s in plan.sections) {
    for (final id in s.screenIds) {
      db[BranchPlanTables.screens].insert({
        'station_id': s.id,
        'slot_id': id,
      }, timestamps: false);
    }
    for (final id in s.printerIds) {
      db[BranchPlanTables.stationPrinters].insert({
        'station_id': s.id,
        'printer_id': id,
      }, timestamps: false);
    }
    for (final c in s.categoryIds) {
      db[BranchPlanTables.categoryRoutes].insert({
        'branch_id': branchId,
        'category_id': c,
        'station_id': s.id,
      }, timestamps: false);
    }
  }
}

void _writeBranch(MockDb db, MockRow branch, BuilderPlan plan) {
  final branchId = branch['id']! as String;
  final modes = db[BranchPlanTables.modes];
  modes.removeWhere((r) => r['branch_id'] == branchId);
  modes.insert({
    'branch_id': branchId,
    'mode': routingModeFor(plan),
  }, timestamps: false);
  branch['till_prints_kitchen'] = plan.tillPrintsKitchen;
  final receipt = plan.devices
      .where((d) => d.kind == 'pos')
      .map((d) => plan.printer(d.receiptPrinterId))
      .whereType<BuilderPrinter>()
      .where((p) => p.network)
      .firstOrNull;
  if (receipt != null) {
    branch
      ..['printer_ip'] = receipt.ip?.trim()
      ..['printer_port'] = receipt.port ?? 9100
      ..['printer_brand'] = receipt.brand ?? branch['printer_brand']
      ..['updated_at'] = db.nowIso;
  }
}

/// The server's `check_plan`: every blocking problem, as its sentences.
List<String> serverCheck(BuilderPlan plan) {
  final problems = <String>[];
  void add(String p) {
    // `dedup`: consecutive repeats only.
    if (problems.isEmpty || problems.last != p) problems.add(p);
  }

  final seen = <String>{};
  for (final id in [
    for (final d in plan.devices) d.id,
    for (final p in plan.printers) p.id,
    for (final s in plan.sections) s.id,
  ]) {
    if (!seen.add(id)) add('Piece $id appears twice in the plan');
  }
  final claimed = <String>{};
  for (final d in plan.devices) {
    if (!const {'pos', 'waiter', 'kitchen'}.contains(d.kind)) {
      add("Device ${d.id} has an unknown kind '${d.kind}'");
    }
    if (d.name.trim().isEmpty) add('Every device needs a name');
    final pid = d.receiptPrinterId;
    if (pid != null &&
        !((d.kind == 'pos' || d.kind == 'waiter') &&
            plan.printer(pid)?.role == 'receipt')) {
      add(
        "'${d.name.trim()}' prints receipts on a piece that is not a receipt printer",
      );
    }
    final dev = d.deviceId;
    if (dev != null && !claimed.add(dev)) {
      add('One device can fill only one slot');
    }
  }
  for (final p in plan.printers) {
    final name = p.name.trim();
    if (!const {'receipt', 'kitchen'}.contains(p.role)) {
      add("Printer ${p.id} has an unknown role '${p.role}'");
    }
    if (!const {'network', 'usb', 'bluetooth'}.contains(p.connection)) {
      add("Printer ${p.id} has an unknown connection '${p.connection}'");
    }
    if (name.isEmpty) add('Every printer needs a name');
    if (p.paperMm != 58 && p.paperMm != 80) {
      add("'$name' must use 58 or 80 mm paper");
    }
    final port = p.port;
    if (port != null && (port < 1 || port > 65535)) {
      add("'$name' has a port outside 1-65535");
    }
    if (p.network) {
      if (!isIpv4(p.ip)) {
        add("'$name' is on the network but has no valid IP address");
      }
    } else if (plan.device(p.hostDeviceId) == null) {
      add("'$name' is plugged in but not into a device in this plan");
    }
  }
  final names = <String>{};
  final routed = <String>{};
  for (final s in plan.sections) {
    final name = s.name.trim();
    if (name.isEmpty) {
      add('Every section needs a name');
    } else if (!names.add(name.toLowerCase())) {
      add("Two sections are called '$name'");
    }
    if (s.screenIds.isEmpty && s.printerIds.isEmpty) {
      add("'$name' has no screen or printer, so its orders would go nowhere");
    }
    for (final id in s.screenIds) {
      if (plan.device(id)?.kind != 'kitchen') {
        add("'$name' shows on a piece that is not a kitchen screen");
      }
    }
    for (final id in s.printerIds) {
      if (plan.printer(id)?.role != 'kitchen') {
        add("'$name' prints on a piece that is not a kitchen printer");
      }
    }
    for (final c in s.categoryIds) {
      if (!routed.add(c)) add("A category is in two sections (again in '$name')");
    }
  }
  if (plan.sections.isNotEmpty &&
      plan.sections.where((s) => s.isDefault).length != 1) {
    add('Exactly one section must take the items no other section claims');
  }
  return problems;
}
