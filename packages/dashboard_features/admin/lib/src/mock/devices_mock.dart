/// `/devices` Devices (ADM-DEV rows): the mock backend for the six calls the
/// page makes, over the area seed's tables (`AdminTables.devices`,
/// `AdminTables.activationCodes`, `AdminTables.clientVersions`):
///
/// - `GET /devices?branch_id=` (list_devices): `branches.read` + branch
///   access; ordered retired last, then by code; `code_conflict` computed
///   live (another live device at the branch with the same code).
/// - `PATCH /devices/{id}` (update_device): `branches.edit`; the code is
///   trimmed and uppercased and must be 1–6 letters or digits (400); a code
///   another live device at the branch uses is refused (409
///   `DEVICE_CODE_TAKEN`) whenever a code is sent; `label` null clears it;
///   `retired` stamps or clears `retired_at`.
/// - `GET /devices/activation-codes?branch_id=` (list_codes): branch access +
///   `branches.edit`; newest first; the state is computed from the stamps.
/// - `POST /devices/activation-codes` (create_code, 201): the same gate; a
///   fresh 8-digit code, free for 24 hours.
/// - `POST /devices/activation-codes/{id}/revoke` (revoke_code):
///   `branches.edit`; 404 for an unknown code; a used code is refused (409
///   `ACTIVATION_CODE_USED`).
/// - `GET /devices/client-versions` (list_client_versions): `branches.edit`;
///   org-wide or one branch; `legacy_only` (default true) and `days`
///   (1..365, default 14) window; newest legacy hit first.
///
/// Backend: MadarRust `src/devices/{handlers,activation}.rs`,
/// `src/client_seen/handlers.rs`, `src/authz/scope.rs`.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';

/// The routes, for tests.
abstract final class DevicesRoutes {
  static const String devices = '/devices';
  static const String device = '/devices/{id}';
  static const String codes = '/devices/activation-codes';
  static const String revoke = '/devices/activation-codes/{id}/revoke';
  static const String clients = '/devices/client-versions';
}

final RegExp _deviceCode = RegExp(r'^[A-Z0-9]{1,6}$');

const Set<String> _kinds = {'pos', 'kds', 'waiter'};

void registerDevicesMocks(MockServer server, MockDb db) {
  MockTable devices() => db[AdminTables.devices];
  MockTable codes() => db[AdminTables.activationCodes];
  MockTable clients() => db[AdminTables.clientVersions];

  /// `require_branch_access`: 404 for an unknown branch, 403 for another
  /// org's, 403 for a branch the person is not assigned to.
  void branchAccess(MockRequest req, String branchId) {
    if (req.persona.isPlatform) return;
    final b = db['branches'].find(branchId);
    if (b == null || b['deleted_at'] != null) req.notFound('Branch not found');
    if (b['org_id'] != req.orgId) {
      req.fail(MockResponse.forbidden('Branch belongs to a different org'));
    }
    req.requireBranch(branchId);
  }

  String uuidParam(MockRequest req, String value, String field) {
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(value)) {
      req.badRequest(
        'Query deserialize error: $field: UUID parsing failed: invalid character',
      );
    }
    return value;
  }

  /// The device as the server reads it (`DEVICE_SELECT`).
  MockRow deviceOut(MockRow d) => {
    ...d,
    'code_conflict': devices().rows.any(
      (o) =>
          o['id'] != d['id'] &&
          o['branch_id'] == d['branch_id'] &&
          o['code'] == d['code'] &&
          o['retired_at'] == null,
    ),
  };

  /// The code as the server reads it (`to_code`): the state from the stamps.
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

  // ── devices ──────────────────────────────────────────────────────────

  server.on('GET', DevicesRoutes.devices, (req) {
    final raw = req.q('branch_id');
    if (raw == null) {
      req.badRequest('Query deserialize error: missing field `branch_id`');
    }
    final branchId = uuidParam(req, raw, 'branch_id');
    req.requireCap('branches.read');
    branchAccess(req, branchId);
    final rows = [
      for (final d in devices().rows)
        if (d['branch_id'] == branchId) deviceOut(d),
    ];
    // ORDER BY d.retired_at NULLS FIRST, d.code
    rows.sort((a, b) {
      final ra = a['retired_at'] as String?;
      final rb = b['retired_at'] as String?;
      if (ra == null && rb != null) return -1;
      if (ra != null && rb == null) return 1;
      if (ra != null && rb != null) {
        final byRetired = DateTime.parse(ra).compareTo(DateTime.parse(rb));
        if (byRetired != 0) return byRetired;
      }
      return (a['code']! as String).compareTo(b['code']! as String);
    });
    return MockResponse.ok(rows);
  });

  server.on('PATCH', DevicesRoutes.device, (req) {
    req.requireCap('branches.edit');
    final id = req.param('id');
    final current = devices().find(id);
    if (current == null) req.notFound('Device not found');
    final body = req.json;
    final branch = (body['branch_id'] as String?) ?? current['branch_id'];
    if (branch is String) branchAccess(req, branch);
    var code = current['code']! as String;
    if (body['code'] is String) {
      code = (body['code']! as String).trim().toUpperCase();
      if (!_deviceCode.hasMatch(code)) {
        req.badRequest('Device code must be 1-6 letters or digits');
      }
    }
    if (body['code'] != null || body['branch_id'] != null) {
      final taken = devices().rows.any(
        (o) =>
            o['branch_id'] == branch &&
            o['code'] == code &&
            o['id'] != id &&
            o['retired_at'] == null,
      );
      if (taken) {
        req.conflict(
          'Another device at this branch uses that code',
          code: 'DEVICE_CODE_TAKEN',
        );
      }
    }
    final patch = <String, Object?>{'code': code, 'branch_id': branch};
    if (body.containsKey('label')) {
      final l = (body['label'] as String?)?.trim();
      patch['label'] = l == null || l.isEmpty
          ? null
          : String.fromCharCodes(l.runes.take(120));
    }
    final retired = body['retired'];
    if (retired == true) {
      patch['retired_at'] = current['retired_at'] ?? req.now.toIso8601String();
    } else if (retired == false) {
      patch['retired_at'] = null;
    }
    final saved = devices().update(id, patch);
    return MockResponse.ok(deviceOut(saved));
  });

  // ── activation codes ─────────────────────────────────────────────────

  /// `gate`: branch access, then `branches.edit` at that branch.
  void codesGate(MockRequest req, String branchId) {
    branchAccess(req, branchId);
    req.requireCap('branches.edit', branchId: branchId);
  }

  server.on('GET', DevicesRoutes.codes, (req) {
    final raw = req.q('branch_id');
    if (raw == null) {
      req.badRequest('Query deserialize error: missing field `branch_id`');
    }
    final branchId = uuidParam(req, raw, 'branch_id');
    codesGate(req, branchId);
    final rows = [
      for (final c in codes().rows)
        if (c['branch_id'] == branchId) codeOut(c, req.now),
    ];
    rows.sort(
      (a, b) => DateTime.parse(
        b['created_at']! as String,
      ).compareTo(DateTime.parse(a['created_at']! as String)),
    );
    return MockResponse.ok(rows.take(200).toList());
  });

  server.on('POST', DevicesRoutes.codes, (req) {
    final body = req.bodyAs(CreateActivationCodeRequest.fromJson);
    codesGate(req, body.branchId);
    final kind = body.kind?.value ?? 'pos';
    if (!_kinds.contains(kind)) {
      req.badRequest('kind must be pos, kds or waiter');
    }
    final l = body.label?.trim();
    final label = l == null || l.isEmpty
        ? null
        : String.fromCharCodes(l.runes.take(120));
    final now = req.now;
    // Eight digits, unique among the codes still free (the partial unique
    // index), deterministic per run.
    final live = {
      for (final c in codes().rows)
        if (codeOut(c, now)['state'] == 'free') c['code'],
    };
    var n = codes().length;
    String code;
    do {
      n++;
      final h = mockUuid('activation-code#$n').replaceAll('-', '');
      code = (int.parse(h.substring(0, 12), radix: 16) % 100000000)
          .toString()
          .padLeft(8, '0');
    } while (live.contains(code));
    final row = codes().insert({
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
    }, timestamps: false);
    return MockResponse.created(codeOut(row, now));
  });

  server.on('POST', DevicesRoutes.revoke, (req) {
    // Route guard first: someone who may edit no branch at all.
    req.requireCap('branches.edit');
    final id = req.param('id');
    final row = codes().find(id);
    if (row == null) req.notFound('No such activation code');
    codesGate(req, row['branch_id']! as String);
    if (row['used_at'] != null) {
      req.conflict(
        'This code was already used; deactivate the device instead',
        code: 'ACTIVATION_CODE_USED',
      );
    }
    row['revoked_at'] ??= req.now.toIso8601String();
    return MockResponse.ok(codeOut(row, req.now));
  });

  // ── client versions ──────────────────────────────────────────────────

  /// The org a client row belongs to: its branch's, else its device's; the
  /// seed's device-less, branch-less clients are Sabah's.
  String? orgOf(MockRow c) {
    if (c['org_id'] is String) return c['org_id']! as String;
    final b = c['branch_id'];
    if (b is String) return db['branches'].find(b)?['org_id'] as String?;
    final d = c['device_id'];
    if (d is String) return devices().find(d)?['org_id'] as String?;
    return SeedIds.sabahOrg;
  }

  server.on('GET', DevicesRoutes.clients, (req) {
    req.requireCap('branches.edit');
    final org = req.orgId;
    if (org == null) {
      req.badRequest('A token with an organization is required');
    }
    final days = req.qInt('days') ?? 14;
    if (days < 1 || days > 365) {
      req.badRequest('days must be between 1 and 365');
    }
    final legacyOnly = req.qBool('legacy_only') ?? true;
    final rawBranch = req.q('branch_id');
    final branchId = rawBranch == null
        ? null
        : uuidParam(req, rawBranch, 'branch_id');
    final since = req.now.subtract(Duration(days: days));
    DateTime? at(Object? v) => v is String ? DateTime.parse(v) : null;
    final rows = <MockRow>[];
    for (final c in clients().rows) {
      if (orgOf(c) != org) continue;
      if (branchId != null && c['branch_id'] != branchId) continue;
      final stamp = legacyOnly
          ? at(c['last_legacy_at'])
          : at(c['last_seen_at']);
      if (stamp == null || stamp.isBefore(since)) continue;
      final b = c['branch_id'];
      final d = c['device_id'];
      final device = d is String ? devices().find(d) : null;
      rows.add(
        {
          ...c,
          'branch_name': b is String ? (db['branches'].find(b)?['name']) : null,
          'device_code': device != null && device['org_id'] == org
              ? device['code']
              : null,
        }..remove('org_id'),
      );
    }
    // ORDER BY last_legacy_at DESC NULLS LAST, last_seen_at DESC
    rows.sort((a, b) {
      final la = at(a['last_legacy_at']);
      final lb = at(b['last_legacy_at']);
      if (la != null && lb == null) return -1;
      if (la == null && lb != null) return 1;
      if (la != null && lb != null && la != lb) return lb.compareTo(la);
      return at(b['last_seen_at'])!.compareTo(at(a['last_seen_at'])!);
    });
    return MockResponse.ok(rows);
  });
}
