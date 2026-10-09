/// The mock backend for Payment methods (`/settings/payment-methods`,
/// SET-PAY rows), as MadarRust `src/payment_methods/{handlers,availability}.rs`
/// answers:
///
/// - `GET /payment-methods`: `payment_methods.read`; the org's methods,
///   oldest first (the org comes from `X-Org-Id` for a platform admin).
/// - `POST /payment-methods` (201): `payment_methods.create`; a name the org
///   already has is refused (409); `is_active` and `visible_in_integrations`
///   default to true.
/// - `PUT /payment-methods/{id}`: `payment_methods.edit`; 404 outside the
///   org; a rename onto another method's name is refused (409); only the
///   fields sent change.
/// - `POST /payment-methods/{id}/activate|deactivate`: `payment_methods.edit`.
/// - `GET /payment-methods/availability?branch_id=`: `payment_methods.read`;
///   404 for a branch outside the org; the branch's list, every teller's list
///   in the org and the lists of the devices at the branch.
/// - `PUT /payment-methods/availability/{branches|users|devices}/{id}`:
///   `payment_methods.edit`; a restricted empty list is refused (400
///   `EMPTY_ALLOW_LIST`), an owner outside the org is 404, an unknown method
///   id 400; the list is replaced and the stored one returned.
/// - `GET /users`, `GET /devices`: only when no other area answers them (in
///   the app the admin area does, over the same records).
///
/// Data: the core seed's six methods plus two of Sabah's own ([extraMethods],
/// with real identity colours), and a few allow-lists at Zamalek
/// ([availabilityRows]).
library;

import 'package:collection/collection.dart';
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';

import 'support.dart';

/// The routes, for tests.
abstract final class PmRoutes {
  static const String list = '/payment-methods';
  static const String method = '/payment-methods/{id}';
  static const String activate = '/payment-methods/{id}/activate';
  static const String deactivate = '/payment-methods/{id}/deactivate';
  static const String availability = '/payment-methods/availability';
  static const String branch = '/payment-methods/availability/branches/{id}';
  static const String user = '/payment-methods/availability/users/{id}';
  static const String device = '/payment-methods/availability/devices/{id}';
  static const String users = '/users';
  static const String devices = '/devices';
}

/// The backend's refusal sentences (tests build the same responses).
abstract final class PmRefusals {
  static const String nameTakenInOrg =
      'A payment method with this name already exists for the organization';
  static const String nameTaken =
      'A payment method with this name already exists';
}

abstract final class PmSeed {
  static const String methodsTable = 'payment_methods';
  static const String availabilityTable = 'payment_method_availability';

  /// The admin area's devices table (`AdminTables.devices`); this unit
  /// keeps its own copy of the same rows when that area is not loaded.
  static const String devicesTable = 'devices';
  static const String ownDevicesTable = 'pm_devices';

  /// A method's id by its name (the core seed's rule).
  static String methodId(String name) => mockUuid('payment-method:$name');

  /// A device's id by branch key and code (the admin seed's rule).
  static String deviceId(String branchKey, String code) =>
      mockUuid('device:$branchKey:$code');

  /// Sabah's own methods, added in June 2026: InstaPay at the counters and
  /// the gift card it stopped selling (and keeps out of partner reports).
  static final List<OrgPaymentMethod> extraMethods = [
    OrgPaymentMethod(
      id: methodId('instapay'),
      orgId: SeedIds.sabahOrg,
      name: 'instapay',
      labelTranslations: const {'en': 'InstaPay', 'ar': 'إنستاباي'},
      color: '#7C3AED',
      icon: 'smartphone',
      isCash: false,
      isActive: true,
      visibleInIntegrations: true,
      createdAt: DateTime.utc(2026, 6, 14, 9),
      updatedAt: DateTime.utc(2026, 6, 14, 9),
    ),
    OrgPaymentMethod(
      id: methodId('gift_card'),
      orgId: SeedIds.sabahOrg,
      name: 'gift_card',
      labelTranslations: const {'en': 'Gift card', 'ar': 'بطاقة هدايا'},
      color: '#DB2777',
      icon: 'gift_card',
      isCash: false,
      isActive: false,
      visibleInIntegrations: false,
      createdAt: DateTime.utc(2026, 6, 20, 9),
      updatedAt: DateTime.utc(2026, 8, 2, 9),
    ),
  ];

  /// Zamalek takes cash, card, wallets and InstaPay (no Talabat at the
  /// counter); Youssef may only take cash; the second counter has no drawer.
  static List<MockRow> get availabilityRows => [
    for (final m in ['cash', 'card', 'digital_wallet', 'instapay'])
      _allow('branch', SeedIds.zamalek, m),
    _allow('user', SeedIds.user('youssef'), 'cash'),
    for (final m in ['card', 'digital_wallet', 'instapay'])
      _allow('device', deviceId('zamalek', 'T2'), m),
  ];

  static MockRow _allow(String owner, String ownerId, String method) => {
    'id': mockUuid('pm-allow:$owner:$ownerId:$method'),
    'owner': owner,
    'owner_id': ownerId,
    'payment_method_id': methodId(method),
    'org_id': SeedIds.sabahOrg,
  };

  static Device _device(
    String branchKey,
    String code,
    DeviceKind kind,
    String label, {
    DateTime? retiredAt,
    bool conflict = false,
    String? id,
  }) => Device(
    id: id ?? deviceId(branchKey, code),
    orgId: SeedIds.sabahOrg,
    branchId: MockSeed.branchIdOf(branchKey),
    code: code,
    codeConflict: conflict,
    kind: kind,
    label: label,
    firstSeenAt: DateTime.utc(2026, 3, 1, 8),
    lastSeenAt: DateTime.utc(2026, 10, 8, 6, 30),
    retiredAt: retiredAt,
  );

  /// The admin seed's devices (same ids, codes and names).
  static List<Device> get devices => [
    _device('heliopolis', 'T1', DeviceKind.pos, 'Counter 1'),
    _device('heliopolis', 'K1', DeviceKind.kds, 'Kitchen screen'),
    _device('maadi', 'T1', DeviceKind.pos, 'Counter 1'),
    _device(
      'maadi',
      'T9',
      DeviceKind.pos,
      'Old counter iPad',
      retiredAt: DateTime.utc(2026, 8, 20, 6, 55),
    ),
    _device('new-cairo', 'T1', DeviceKind.pos, 'Counter 1'),
    _device(
      'new-cairo',
      'T2',
      DeviceKind.pos,
      'Drive-through',
      conflict: true,
    ),
    _device(
      'new-cairo',
      'T2',
      DeviceKind.pos,
      'Counter 2',
      conflict: true,
      id: deviceId('new-cairo', 'T2-b'),
    ),
    _device('zamalek', 'T1', DeviceKind.pos, 'Counter 1'),
    _device('zamalek', 'T2', DeviceKind.pos, 'Counter 2'),
    _device('zamalek', 'K1', DeviceKind.kds, 'Kitchen screen'),
    _device('zamalek', 'W1', DeviceKind.waiter, 'Floor tablet'),
    _device('zamalek', 'W2', DeviceKind.waiter, 'Terrace tablet'),
  ];
}

void registerPaymentMethodsMocks(MockServer server, MockDb db) {
  final methods = db[PmSeed.methodsTable];
  for (final m in PmSeed.extraMethods) {
    if (methods.firstWhere((r) => r['name'] == m.name) == null) {
      methods.insert(m.toJson(), timestamps: false);
    }
  }
  seedTableIfAbsent(
    db,
    PmSeed.availabilityTable,
    () => PmSeed.availabilityRows,
  );
  seedTableIfAbsent(
    db,
    PmSeed.ownDevicesTable,
    () => [for (final d in PmSeed.devices) d.toJson()],
  );
  MockTable allow() => db[PmSeed.availabilityTable];
  // The admin area's table when it is loaded (it answers GET /devices then).
  List<MockRow> deviceRows() => db.hasTable(PmSeed.devicesTable)
      ? db[PmSeed.devicesTable].rows
      : db[PmSeed.ownDevicesTable].rows;

  String orgOf(MockRequest req) =>
      req.orgId ?? req.fail(MockResponse.forbidden('No org id'));

  /// `ORDER BY created_at` (ties keep insertion order).
  List<MockRow> orgMethods(String orgId) {
    final rows = methods.where((r) => r['org_id'] == orgId);
    mergeSort(
      rows,
      compare: (a, b) =>
          '${a['created_at']}'.compareTo('${b['created_at']}'),
    );
    return rows;
  }

  MockRow methodIn(MockRequest req, String orgId) {
    final row = methods.find(req.param('id'));
    if (row == null || row['org_id'] != orgId) {
      req.notFound('Payment method not found');
    }
    return row;
  }

  bool nameTaken(String orgId, String name, {String? except}) => methods.rows
      .any((r) => r['org_id'] == orgId && r['name'] == name && r['id'] != except);

  /// The owner's ticked ids in the methods' order (`ids_for`).
  List<String> idsFor(String owner, String ownerId) {
    final ids = {
      for (final r in allow().rows)
        if (r['owner'] == owner && r['owner_id'] == ownerId)
          r['payment_method_id']! as String,
    };
    final order = [for (final m in methods.rows) m['id']! as String];
    return [
      for (final id in order)
        if (ids.contains(id)) id,
    ];
  }

  // ── methods ────────────────────────────────────────────────────────────

  server.on('GET', PmRoutes.list, (req) {
    req.requireCap('payment_methods.read');
    return MockResponse.ok(orgMethods(orgOf(req)));
  });

  server.on('POST', PmRoutes.list, (req) {
    req.requireCap('payment_methods.create');
    final orgId = orgOf(req);
    final body = req.bodyAs(CreatePaymentMethodRequest.fromJson);
    if (nameTaken(orgId, body.name)) {
      req.conflict(PmRefusals.nameTakenInOrg);
    }
    final row = methods.insert({
      'org_id': orgId,
      'name': body.name,
      'label_translations': body.labelTranslations,
      'color': body.color,
      'icon': body.icon,
      'is_cash': body.isCash,
      'is_active': body.isActive ?? true,
      'visible_in_integrations': body.visibleInIntegrations ?? true,
    });
    return MockResponse.created(row);
  });

  server.on('PUT', PmRoutes.method, (req) {
    req.requireCap('payment_methods.edit');
    final orgId = orgOf(req);
    final row = methodIn(req, orgId);
    final body = req.bodyAs(UpdatePaymentMethodRequest.fromJson);
    if (body.name != null &&
        nameTaken(orgId, body.name!, except: row['id']! as String)) {
      req.conflict(PmRefusals.nameTaken);
    }
    // ponytail: a rename does not carry the orders' history along (the
    // backend rewrites `order_payments.method`); no page here reads it back.
    return MockResponse.ok(
      methods.update(row['id']! as String, {
        'name': ?body.name,
        'label_translations': ?body.labelTranslations,
        'color': ?body.color,
        'icon': ?body.icon,
        'is_cash': ?body.isCash,
        'is_active': ?body.isActive,
        'visible_in_integrations': ?body.visibleInIntegrations,
      }),
    );
  });

  for (final (template, on) in [
    (PmRoutes.activate, true),
    (PmRoutes.deactivate, false),
  ]) {
    server.on('POST', template, (req) {
      req.requireCap('payment_methods.edit');
      final row = methodIn(req, orgOf(req));
      return MockResponse.ok(
        methods.update(row['id']! as String, {'is_active': on}),
      );
    });
  }

  // ── availability ───────────────────────────────────────────────────────

  bool ownerExists(String owner, String id, String orgId) {
    final MockRow? row = switch (owner) {
      'branch' => db['branches'].find(id),
      'user' => db['users'].find(id),
      _ => deviceRows().where((d) => d['id'] == id).firstOrNull,
    };
    return row != null && row['org_id'] == orgId && row['deleted_at'] == null;
  }

  server.on('GET', PmRoutes.availability, (req) {
    req.requireCap('payment_methods.read');
    final orgId = orgOf(req);
    final branchId = req.q('branch_id');
    if (branchId == null) {
      req.badRequest('Query deserialize error: missing field `branch_id`');
    }
    if (!ownerExists('branch', branchId, orgId)) {
      req.notFound('Branch not found');
    }
    final branchIds = idsFor('branch', branchId);
    Iterable<String> owners(String kind) => {
      for (final r in allow().rows)
        if (r['owner'] == kind && r['org_id'] == orgId)
          r['owner_id']! as String,
    }.toList()..sort();
    final atBranch = {
      for (final d in deviceRows())
        if (d['branch_id'] == branchId) d['id'],
    };
    return MockResponse.ok(
      PaymentMethodAvailability(
        branchId: branchId,
        branch: AllowList(
          restricted: branchIds.isNotEmpty,
          paymentMethodIds: branchIds,
        ),
        users: [
          for (final u in owners('user'))
            UserAllowList(userId: u, paymentMethodIds: idsFor('user', u)),
        ],
        devices: [
          for (final d in owners('device'))
            if (atBranch.contains(d))
              DeviceAllowList(
                deviceId: d,
                paymentMethodIds: idsFor('device', d),
              ),
        ],
      ).toJson(),
    );
  });

  for (final (template, owner) in [
    (PmRoutes.branch, 'branch'),
    (PmRoutes.user, 'user'),
    (PmRoutes.device, 'device'),
  ]) {
    server.on('PUT', template, (req) {
      req.requireCap('payment_methods.edit');
      final orgId = orgOf(req);
      final body = req.bodyAs(AllowList.fromJson);
      if (body.restricted && body.paymentMethodIds.isEmpty) {
        req.badRequest(
          'EMPTY_ALLOW_LIST: a restricted list needs at least one payment method',
          code: 'EMPTY_ALLOW_LIST',
        );
      }
      final ownerId = req.param('id');
      if (!ownerExists(owner, ownerId, orgId)) req.notFound('Not found');
      final ids = body.paymentMethodIds.toSet();
      if (body.restricted &&
          ids.any((id) => methods.find(id)?['org_id'] != orgId)) {
        req.badRequest('Unknown payment method id');
      }
      allow().removeWhere(
        (r) => r['owner'] == owner && r['owner_id'] == ownerId,
      );
      if (body.restricted) {
        for (final id in ids) {
          allow().insert({
            'owner': owner,
            'owner_id': ownerId,
            'payment_method_id': id,
            'org_id': orgId,
          }, timestamps: false);
        }
      }
      final stored = idsFor(owner, ownerId);
      return MockResponse.ok(
        AllowList(
          restricted: stored.isNotEmpty,
          paymentMethodIds: stored,
        ).toJson(),
      );
    });
  }

  // ── people and devices (owned by other areas in the app) ───────────────

  onIfAbsent(server, 'GET', PmRoutes.users, (req) {
    req.requireCap('staff.users.read');
    final orgId = req.persona.isPlatform ? req.q('org_id') : req.persona.orgId;
    final scoped = req.persona.branchIds;
    final rows = db['users'].where(
      (u) =>
          u['deleted_at'] == null &&
          (orgId == null || u['org_id'] == orgId) &&
          (scoped == null ||
              u['id'] == req.persona.userId ||
              scoped.contains(u['branch_id'])),
    )..sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
    return MockResponse.ok(rows);
  });

  onIfAbsent(server, 'GET', PmRoutes.devices, (req) {
    final branchId = req.q('branch_id');
    if (branchId == null) {
      req.badRequest('Query deserialize error: missing field `branch_id`');
    }
    req.requireCap('branches.read');
    if (!req.persona.isPlatform) {
      final b = db['branches'].find(branchId);
      if (b == null || b['deleted_at'] != null) req.notFound('Branch not found');
      if (b['org_id'] != req.orgId) {
        req.fail(MockResponse.forbidden('Branch belongs to a different org'));
      }
      req.requireBranch(branchId);
    }
    final rows = deviceRows().where((d) => d['branch_id'] == branchId).toList()
      // ORDER BY retired_at NULLS FIRST, code
      ..sort((a, b) {
        final ra = a['retired_at'] as String?, rb = b['retired_at'] as String?;
        if ((ra == null) != (rb == null)) return ra == null ? -1 : 1;
        final byRetired = (ra ?? '').compareTo(rb ?? '');
        return byRetired != 0
            ? byRetired
            : '${a['code']}'.compareTo('${b['code']}');
      });
    return MockResponse.ok(rows);
  });
}
