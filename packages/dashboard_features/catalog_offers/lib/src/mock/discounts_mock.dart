/// The discounts page's mock backend (`/discounts`): `GET /discounts`,
/// `POST /discounts`, `PATCH /discounts/{id}` and `DELETE /discounts/{id}`,
/// over the area seed's `discounts` table (answered sorted by `name`; see
/// `legacyDiscountValue` for the legacy `value`).
///
/// As MadarRust `src/discounts/handlers.rs`:
/// - list `discounts.read`, create `discounts.create`, PATCH `discounts.edit`
///   (`discounts:update`), delete `discounts.delete`; each also refuses
///   another org's discount with 403 "Forbidden: Not your org";
/// - `dtype` must be `percentage` or `fixed`, `value` ≥ 0 and a percentage a
///   fraction ≤ 1 (400 with the backend's words); a PATCH checks the value
///   only when it also sends the type;
/// - the stored value is the fraction (or piastres); the answer carries it
///   as `value_rate` and as the legacy integer `value`;
/// - names: `name_translations.en` always mirrors `name`; a PATCH that sends
///   a `name` keeps the stored translations (only `en` follows the name), a
///   PATCH with translations and no name replaces them.
library;

import 'package:collection/collection.dart';
import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';

void registerDiscountsMocks(MockServer server, MockDb db) {
  final table = db.table(OffersTables.discounts);

  Never notYourOrg() =>
      throw MockHttpError(MockResponse.forbidden('Not your org'));

  void requireOrg(MockRequest req, Object? orgId) {
    if (req.persona.isPlatform) return;
    if (orgId != req.persona.orgId) notYourOrg();
  }

  MockRow found(MockRequest req) {
    final row = table.find(req.param('id'));
    if (row == null) req.notFound('Discount not found');
    return row;
  }

  void checkType(MockRequest req, Object? dtype) {
    if (dtype != 'percentage' && dtype != 'fixed') {
      req.badRequest("type must be 'percentage' or 'fixed'");
    }
  }

  void checkValue(MockRequest req, num value, Object? dtype) {
    if (value < 0) req.badRequest('value must be >= 0');
    if (dtype == 'percentage' && value > 1) {
      req.badRequest(
        'a percentage discount is a fraction between 0 and 1 (0.14 = 14%)',
      );
    }
  }

  num readValue(MockRequest req, Object? raw) {
    if (raw is num) return raw;
    if (raw is String) {
      final n = num.tryParse(raw);
      if (n != null) return n;
    }
    req.badRequest('Json deserialize error: invalid value');
  }

  Map<String, Object?> translations(Object? raw) => raw is Map
      ? {
          for (final e in raw.entries)
            if (e.value is String) e.key.toString(): e.value,
        }
      : <String, Object?>{};

  MockRow wire(MockRow r) => {
    ...r,
    'value': legacyDiscountValue(r['value_rate']! as num),
  };

  int byName(MockRow a, MockRow b) {
    final x = compareAsciiLowerCase(a['name']! as String, b['name']! as String);
    return x != 0 ? x : (a['name']! as String).compareTo(b['name']! as String);
  }

  server.on('GET', '/discounts', (req) {
    req.requireCap('discounts.read');
    final orgId = req.q('org_id');
    if (orgId == null || orgId.isEmpty) {
      req.badRequest('Query deserialize error: missing field `org_id`');
    }
    requireOrg(req, orgId);
    final rows = table.where((r) => r['org_id'] == orgId)..sort(byName);
    return MockResponse.ok([for (final r in rows) wire(r)]);
  });

  server.on('POST', '/discounts', (req) {
    req.requireCap('discounts.create');
    final b = req.json;
    final orgId = b['org_id'];
    final name = b['name'];
    if (orgId is! String || name is! String) {
      req.badRequest('Json deserialize error: missing field');
    }
    requireOrg(req, orgId);
    checkType(req, b['dtype']);
    final value = readValue(req, b['value']);
    checkValue(req, value, b['dtype']);
    final row = table.insert({
      'org_id': orgId,
      'name': name,
      'name_translations': {
        ...translations(b['name_translations']),
        'en': name,
      },
      'dtype': b['dtype'],
      'value_rate': value,
      'is_active': b['is_active'] ?? true,
    });
    return MockResponse.created(wire(row));
  });

  server.on('PATCH', '/discounts/{id}', (req) {
    req.requireCap('discounts.edit');
    final row = found(req);
    requireOrg(req, row['org_id']);
    final b = req.json;
    final dtype = b['dtype'];
    if (dtype != null) checkType(req, dtype);
    final value = b['value'] == null ? null : readValue(req, b['value']);
    if (value != null && dtype != null) checkValue(req, value, dtype);
    final name = b['name'];
    var names = translations(row['name_translations']);
    if (name is String) {
      names = {...names, 'en': name};
    } else if (b['name_translations'] != null) {
      names = {...translations(b['name_translations']), 'en': row['name']};
    }
    row
      ..['name'] = name is String ? name : row['name']
      ..['name_translations'] = names
      ..['dtype'] = dtype ?? row['dtype']
      ..['value_rate'] = value ?? row['value_rate']
      ..['is_active'] = b['is_active'] ?? row['is_active']
      ..['updated_at'] = db.nowIso;
    return MockResponse.ok(wire(row));
  });

  server.on('DELETE', '/discounts/{id}', (req) {
    req.requireCap('discounts.delete');
    final row = found(req);
    requireOrg(req, row['org_id']);
    table.delete(row['id']! as String);
    return MockResponse.empty();
  });
}
