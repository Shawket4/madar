/// `/branches` Branches (ADM-BRA rows): `POST /branches`, `PATCH` / `PUT` /
/// `DELETE /branches/{id}` (the core already answers `GET /branches`,
/// `GET /branches/{id}` and `GET /timezones`).
///
/// Each handler follows MadarRust `src/branches/handlers.rs`:
///
/// - capability first (`branches.create` / `.edit` / `.delete`, the 403
///   envelope), then the org (`require_same_org`), then not-found;
/// - create: `printer_port` defaults to 9100, `old_bill_hours` to 3, the
///   branch code is derived from the name the way the `set_branch_code`
///   trigger does, and the till settings and tax overrides are NOT taken
///   (the client PATCHes them on afterwards);
/// - update: `name`, `address`, `phone`, `timezone`, `is_active`,
///   `geo_radius_meters` and `old_bill_hours` are `COALESCE`d (null or
///   absent keeps the stored value); the printer, location, tax and float
///   fields take an explicit null (absent keeps, null clears); rates are
///   fractions 0..1, `old_bill_hours` 1..168, `standard_float` >= 0 (400 with
///   the backend's sentence); a changed `old_bill_hours` / `standard_float`
///   publishes `branch.settings_changed` on the branch's stream;
/// - `printer_ip` is a Postgres `inet` and `timezone` the `timezone_name`
///   enum: a bad value is the database's own 400;
/// - names are unique per org (`uq_branches_org_name`): a clash is the
///   database's 409;
/// - delete refuses (409) while the branch still has an open till, an
///   unsettled ticket, a table in use or an upcoming booking, naming all of
///   them in one sentence; otherwise the branch is gone from every list.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart'
    show TransportRealtimeGateway;

/// The fields `UPDATE branches` merges with `COALESCE` (null keeps).
const List<String> _coalesced = [
  'name',
  'address',
  'phone',
  'timezone',
  'is_active',
  'geo_radius_meters',
  'old_bill_hours',
];

/// The double-option fields (absent keeps, an explicit null clears).
const List<String> _clearable = [
  'printer_brand',
  'printer_ip',
  'printer_port',
  'latitude',
  'longitude',
  'tax_rate',
  'tax_inclusive',
  'service_charge_rate',
  'service_charge_taxable',
  'require_table_for_orders',
  'standard_float',
];

void registerBranchesMocks(MockServer server, MockDb db) {
  server.on('POST', '/branches', (req) {
    req.requireCap('branches.create');
    final body = req.bodyAs(CreateBranchRequest.fromJson);
    req.requireSameOrg(body.orgId);
    final org = db['orgs'].get(body.orgId, what: 'Organization not found');
    final tz = body.timezone;
    if (tz != null && tz.isNotEmpty) _checkTimezone(req, tz);
    final ip = body.printerIp;
    if (ip != null) _checkInet(req, ip);
    _checkUniqueName(req, db, body.orgId, body.name);
    final id = db.newId('branches');
    final now = db.nowIso;
    final row = <String, Object?>{
      'id': id,
      'org_id': body.orgId,
      'code': _branchCode(db, body.orgId, id, body.name),
      'name': body.name,
      'address': body.address,
      'phone': body.phone,
      'timezone': (tz == null || tz.isEmpty)
          ? (org['timezone'] as String? ?? 'Africa/Cairo')
          : tz,
      'printer_brand': body.printerBrand?.toJson(),
      'printer_ip': ip,
      'printer_port': body.printerPort ?? 9100,
      'is_active': true,
      'latitude': body.latitude,
      'longitude': body.longitude,
      'geo_radius_meters': body.geoRadiusMeters,
      'old_bill_hours': 3,
      'created_at': now,
      'updated_at': now,
    };
    db['branches'].insert(row, timestamps: false);
    return MockResponse.created(_answer(db, row));
  });

  MockResponse update(MockRequest req) {
    req.requireCap('branches.edit');
    final row = db['branches'].get(req.param('id'), what: 'Branch not found');
    req.requireSameOrg(row['org_id'] as String?);
    // Decoding first answers a wrongly typed field as actix does (400).
    req.bodyAs(UpdateBranchRequest.fromJson);
    final body = req.json;
    final tz = body['timezone'];
    if (tz is String && tz.isNotEmpty) _checkTimezone(req, tz);
    for (final name in const ['tax_rate', 'service_charge_rate']) {
      final r = body[name];
      if (r is num && (r < 0 || r > 1)) {
        req.badRequest(
          '$name is a fraction between 0 and 1, not a percentage — '
          '0.14 means 14%',
        );
      }
    }
    final hours = body['old_bill_hours'];
    if (hours is num && (hours < 1 || hours > 168)) {
      req.badRequest('old_bill_hours must be between 1 and 168');
    }
    final float = body['standard_float'];
    if (float is num && float < 0) {
      req.badRequest('standard_float must be zero or more (minor units)');
    }
    final ip = body['printer_ip'];
    if (ip is String) _checkInet(req, ip);
    final name = body['name'];
    if (name is String && name != row['name']) {
      _checkUniqueName(req, db, row['org_id']! as String, name, except: row);
    }

    final before = (row['old_bill_hours'], row['standard_float']);
    for (final key in _coalesced) {
      final v = body[key];
      if (v == null) continue;
      if (key == 'timezone' && v == '') continue;
      row[key] = v;
    }
    for (final key in _clearable) {
      if (body.containsKey(key)) row[key] = body[key];
    }
    row['updated_at'] = db.nowIso;
    if ((row['old_bill_hours'], row['standard_float']) != before) {
      final id = row['id']! as String;
      server.publish(
        realtimeChannel(id),
        TransportRealtimeGateway.encode(
          'branch.settings_changed',
          data: {'branch_id': id, 'old_bill_hours': row['old_bill_hours']},
        ),
      );
    }
    return MockResponse.ok(_answer(db, row));
  }

  server.on('PATCH', '/branches/{id}', update);
  server.on('PUT', '/branches/{id}', update);

  server.on('DELETE', '/branches/{id}', (req) {
    req.requireCap('branches.delete');
    final id = req.param('id');
    final row = db['branches'].get(id, what: 'Branch not found');
    req.requireSameOrg(row['org_id'] as String?);
    final blockers = liveAtBranch(db, id, req.now);
    if (blockers.isNotEmpty) {
      req.conflict(
        'This branch still has ${joinWithAnd(blockers)}. Close or clear them '
        'first — or switch the branch off instead, which keeps its history '
        'and stops it being used.',
      );
    }
    db['branches'].delete(id);
    return MockResponse.empty();
  });
}

/// The branch as the backend answers it: the org's logo and receipt footer
/// alongside, the zone resolved branch → org.
Map<String, Object?> _answer(MockDb db, Map<String, Object?> row) {
  final org = db['orgs'].find(row['org_id']! as String);
  return {
    ...row,
    'timezone':
        row['timezone'] ?? org?['timezone'] ?? MockClock.timezone,
    'org_logo_url': org?['logo_url'],
    'org_receipt_footer': org?['receipt_footer'],
  };
}

/// Everything still live at branch [id], phrased for a person
/// (`live_at_branch`): open tills, unsettled tickets, tables in use,
/// upcoming bookings. Tables another area has not loaded count as empty.
List<String> liveAtBranch(MockDb db, String id, DateTime now) {
  String plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';
  int count(String table, bool Function(Map<String, Object?> r) test) =>
      db.hasTable(table)
      ? db[table].where((r) => r['branch_id'] == id && test(r)).length
      : 0;
  final tills = count('tills', (r) => r['closed_at'] == null);
  final tickets = count(
    'open_tickets',
    (r) => r['status'] != 'settled' && r['status'] != 'voided',
  );
  final tables =
      count('floor_tables', (r) => (r['status'] ?? 'free') != 'free') +
      count('branch_tables', (r) => (r['status'] ?? 'free') != 'free');
  final bookings = count('bookings', (r) {
    final at = DateTime.tryParse('${r['starts_at']}');
    return (r['status'] == 'confirmed' || r['status'] == 'seated') &&
        at != null &&
        at.isAfter(now);
  });
  return [
    if (tills > 0) plural(tills, 'open shift', 'open shifts'),
    if (tickets > 0) plural(tickets, 'unsettled ticket', 'unsettled tickets'),
    if (tables > 0) plural(tables, 'table in use', 'tables in use'),
    if (bookings > 0) plural(bookings, 'upcoming booking', 'upcoming bookings'),
  ];
}

/// "a, b and c" (`join_with_and`).
String joinWithAnd(List<String> items) => switch (items.length) {
  0 => '',
  1 => items.single,
  _ =>
    '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}',
};

/// `set_branch_code`: the name upper-cased and stripped to A-Z0-9, first six
/// characters; when that is empty or already taken in the org, `B` and the
/// first five hex digits of the id.
String _branchCode(MockDb db, String orgId, String id, String name) {
  final stripped = name.replaceAll(RegExp('[^A-Za-z0-9]'), '').toUpperCase();
  final preferred = stripped.length > 6 ? stripped.substring(0, 6) : stripped;
  final taken =
      preferred.isEmpty ||
      db['branches'].rows.any(
        (b) => b['org_id'] == orgId && b['code'] == preferred,
      );
  if (!taken) return preferred;
  return 'B${id.replaceAll('-', '').substring(0, 5).toUpperCase()}';
}

void _checkTimezone(MockRequest req, String tz) {
  if (!mockTimezones.contains(tz)) req.badRequest("Unknown timezone '$tz'");
}

final RegExp _ipv4 = RegExp(
  r'^((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(/\d{1,2})?$',
);

/// A Postgres `inet` cast: IPv4 (with an optional mask) or anything IPv6
/// looking; else the database's own 400.
void _checkInet(MockRequest req, String ip) {
  final v6 = ip.contains(':') && RegExp(r'^[0-9A-Fa-f:.]+(/\d{1,3})?$').hasMatch(ip);
  if (_ipv4.hasMatch(ip) || v6) return;
  req.fail(
    MockResponse.error(
      400,
      'Database error: error returned from database: invalid input syntax '
      'for type inet: "$ip"',
    ),
  );
}

/// `uq_branches_org_name`: one live branch per name in an org.
void _checkUniqueName(
  MockRequest req,
  MockDb db,
  String orgId,
  String name, {
  Map<String, Object?>? except,
}) {
  final clash = db['branches'].rows.any(
    (b) => b['org_id'] == orgId && b['name'] == name && !identical(b, except),
  );
  if (!clash) return;
  req.fail(
    MockResponse.error(
      409,
      'Database error: error returned from database: duplicate key value '
      'violates unique constraint "uq_branches_org_name"',
    ),
  );
}
