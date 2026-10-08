/// The mock backend of the Set-up (`/staff/setup`, TEAM-SET rows) unit: the
/// endpoints this unit OWNS (register them here and nowhere else):
///
/// - `PATCH /branches/{id}` (the pin; the admin area registers it too, and in the app the later area wins)
///
/// Read and extend the area seed's tables (`TeamTables`, `TeamSeed`); behave
/// like the backend (capability refusals, validation, state).
///
/// The page's other calls are owned elsewhere: the four checklist reads
/// (`GET /branches` by the core; `GET /staff/employees`,
/// `GET /staff/work-shifts` and `GET /staff/attendance/settings` by the
/// Employees, Work shifts and Rules units over the core's), the rules save
/// (`PUT /staff/attendance/settings`, Rules), and the dialogs' creates
/// (`POST /staff/employees` + `GET /staff/employees/linkable`, Employees;
/// `POST /staff/work-shifts`, Work shifts).
library;

import 'package:dashboard_api/mock.dart';

void registerTeamSetupMocks(MockServer server, MockDb db) {
  // `branches::update_branch` (PATCH = PUT): `check_permission(branches,
  // update)` → `branches.edit`; same org; a partial update where an absent
  // field keeps its value, `latitude` / `longitude` may be cleared with an
  // explicit null, and `geo_radius_meters` only ever changes to a value.
  server.on('PATCH', '/branches/{id}', (req) {
    req.requireCap('branches.edit');
    final id = req.param('id');
    final row = db['branches'].get(id, what: 'Branch not found');
    req.requireSameOrg(row['org_id'] as String?);
    final body = req.json;

    final tz = body['timezone'];
    if (tz is String && tz.isNotEmpty && !mockTimezones.contains(tz)) {
      req.badRequest('Unknown timezone: $tz');
    }
    for (final name in ['tax_rate', 'service_charge_rate']) {
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
    // Wire types as actix's JSON extractor reads them.
    for (final name in ['latitude', 'longitude']) {
      final v = body[name];
      if (v != null && v is! num) {
        req.badRequest(
          'Json deserialize error: invalid type: ${v.runtimeType}, '
          'expected f64',
        );
      }
    }
    final radius = body['geo_radius_meters'];
    if (radius != null && (radius is! num || radius != radius.roundToDouble())) {
      req.badRequest(
        'Json deserialize error: invalid type: $radius, expected i32',
      );
    }

    final patch = <String, Object?>{};
    // COALESCE fields: a value replaces, an absent or null field keeps.
    for (final name in [
      'name',
      'address',
      'phone',
      'timezone',
      'is_active',
      'geo_radius_meters',
      'old_bill_hours',
    ]) {
      final v = body[name];
      if (v != null && !(name == 'timezone' && v == '')) patch[name] = v;
    }
    // Clearable fields: present (even null) replaces.
    for (final name in [
      'latitude',
      'longitude',
      'printer_brand',
      'printer_ip',
      'printer_port',
      'tax_rate',
      'tax_inclusive',
      'service_charge_rate',
      'service_charge_taxable',
      'require_table_for_orders',
      'standard_float',
    ]) {
      if (body.containsKey(name)) patch[name] = body[name];
    }
    if (patch['geo_radius_meters'] is num) {
      patch['geo_radius_meters'] = (patch['geo_radius_meters']! as num)
          .toInt();
    }
    final updated = db['branches'].update(id, patch, what: 'Branch not found');
    return MockResponse.ok(updated);
  });
}
