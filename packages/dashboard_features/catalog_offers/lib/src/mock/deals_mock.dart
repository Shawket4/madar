/// The deals page's mock backend (`/menu/deals`), over the area seed's
/// `deals` table, behaving as MadarRust's `src/deals/handlers.rs`:
///
/// - `GET /deals` (`menu.items.read`): the org's deals not deleted, by
///   `sort`, `name`, `id`; `is_active` filters;
/// - `POST /deals` / `PUT /deals/{id}` (`menu.deals.edit`): the body checked
///   as the backend does (400 `DEAL_INVALID {field}`; the windows' rules
///   with `{window_index, field}`; pool items must be live items of this org
///   and categories its own), then stored (201 / 200 with the rule); an
///   unknown or deleted deal is 404 "Deal not found";
/// - `DELETE /deals/{id}`: a soft delete (204; 404 when it is not there);
/// - `PUT|DELETE /deals/{id}/branches/{branchId}` (`menu.deals.edit` AT that
///   branch): the branch's on/off override saved or removed (204), the
///   branch must be the org's (404 "Branch not found").
///
/// Seed rows carry no `org_id` (they are Sabah's); a created row records its
/// org. Internal fields (`org_id`, `deleted_at`) never leave the handler.
library;

import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';

/// Every route this file answers, for the tests' coverage check.
const List<(String, String)> dealsMockRoutes = [
  ('GET', '/deals'),
  ('POST', '/deals'),
  ('PUT', '/deals/{id}'),
  ('DELETE', '/deals/{id}'),
  ('PUT', '/deals/{id}/branches/{branchId}'),
  ('DELETE', '/deals/{id}/branches/{branchId}'),
];

void registerDealsMocks(MockServer server, MockDb db) {
  final deals = db.table(OffersTables.deals);

  String orgOf(MockRow r) => (r['org_id'] as String?) ?? SeedIds.sabahOrg;

  bool live(MockRow r, String? org) =>
      r['deleted_at'] == null && org != null && orgOf(r) == org;

  MockRow liveDeal(MockRequest req, String id) {
    final r = deals.find(id);
    if (r == null || !live(r, req.orgId)) req.notFound('Deal not found');
    return r;
  }

  MockRow wire(MockRow r) => {
    for (final e in r.entries)
      if (e.key != 'org_id' && e.key != 'deleted_at') e.key: e.value,
  };

  server.on('GET', '/deals', (req) {
    req.requireCap('menu.items.read');
    final org = req.orgId;
    final active = req.qBool('is_active');
    final rows = [
      for (final r in deals.rows)
        if (live(r, org) && (active == null || r['is_active'] == active)) r,
    ]..sort(_byListOrder);
    return MockResponse.ok([for (final r in rows) wire(r)]);
  });

  server.on('POST', '/deals', (req) {
    req.requireCap('menu.deals.edit');
    final org = req.orgId!;
    final body = req.json;
    _validate(req, db, org, body);
    final id = db.newId(OffersTables.deals);
    final now = db.nowIso;
    final row = deals.insert({
      'id': id,
      'org_id': org,
      ..._fields(db, body),
      'branch_overrides': <Object?>[],
      'created_at': now,
      'updated_at': now,
    }, timestamps: false);
    return MockResponse.created(wire(row));
  });

  server.on('PUT', '/deals/{id}', (req) {
    req.requireCap('menu.deals.edit');
    final org = req.orgId!;
    final id = req.param('id');
    final row = liveDeal(req, id);
    final body = req.json;
    _validate(req, db, org, body);
    row
      ..addAll(_fields(db, body))
      ..['updated_at'] = db.nowIso;
    return MockResponse.ok(wire(row));
  });

  server.on('DELETE', '/deals/{id}', (req) {
    req.requireCap('menu.deals.edit');
    final row = liveDeal(req, req.param('id'));
    row
      ..['deleted_at'] = db.nowIso
      ..['updated_at'] = db.nowIso;
    return MockResponse.empty();
  });

  server.on('PUT', '/deals/{id}/branches/{branchId}', (req) {
    final branchId = req.param('branchId');
    req.requireCap('menu.deals.edit', branchId: branchId);
    final row = liveDeal(req, req.param('id'));
    final branch = db['branches'].find(branchId);
    if (branch == null ||
        branch['org_id'] != req.orgId ||
        branch['deleted_at'] != null) {
      req.notFound('Branch not found');
    }
    final on = req.json['is_active'];
    if (on is! bool) {
      req.badRequest(
        'Json deserialize error: missing field `is_active` at line 1 column 2',
      );
    }
    final overrides =
        [
          for (final o in _maps(row['branch_overrides']))
            if (o['branch_id'] != branchId) o,
          {'branch_id': branchId, 'is_active': on},
        ]..sort(
          (a, b) =>
              (a['branch_id']! as String).compareTo(b['branch_id']! as String),
        );
    row
      ..['branch_overrides'] = overrides
      ..['updated_at'] = db.nowIso;
    return MockResponse.empty();
  });

  server.on('DELETE', '/deals/{id}/branches/{branchId}', (req) {
    final branchId = req.param('branchId');
    req.requireCap('menu.deals.edit', branchId: branchId);
    final row = liveDeal(req, req.param('id'));
    row
      ..['branch_overrides'] = [
        for (final o in _maps(row['branch_overrides']))
          if (o['branch_id'] != branchId) o,
      ]
      ..['updated_at'] = db.nowIso;
    return MockResponse.empty();
  });
}

/// `ORDER BY sort, name, id`.
int _byListOrder(MockRow a, MockRow b) {
  final s = ((a['sort'] as num?) ?? 0).compareTo((b['sort'] as num?) ?? 0);
  if (s != 0) return s;
  final n = (a['name']! as String).compareTo(b['name']! as String);
  if (n != 0) return n;
  return (a['id']! as String).compareTo(b['id']! as String);
}

List<Map<String, Object?>> _maps(Object? list) => [
  for (final e in (list as List<Object?>? ?? const []))
    if (e is Map<String, Object?>) e,
];

/// The `DealWrite` fields as the rule stores them (the serde defaults
/// applied: no translations = `{}`, no sort = 0, no `is_active` = on, no
/// reward list or windows = `[]`).
MockRow _fields(MockDb db, Map<String, Object?> b) => {
  'name': (b['name']! as String).trim(),
  'name_translations': b['name_translations'] ?? const <String, Object?>{},
  'kind': b['kind'],
  'qty': b['qty'],
  'price': b['price'],
  'get_qty': b['get_qty'],
  'get_percent': b['get_percent'],
  'max_per_order': b['max_per_order'],
  'sort': b['sort'] ?? 0,
  'is_active': b['is_active'] ?? true,
  'pool': [for (final e in _maps(b['pool'])) _entry(e)],
  'reward_pool': [for (final e in _maps(b['reward_pool'])) _entry(e)],
  'windows': [
    for (final w in _maps(b['windows']))
      {
        'id': db.newId('sale_windows'),
        'branch_id': w['branch_id'],
        'weekdays': w['weekdays'] ?? 127,
        'starts_at': _hhmm(w['starts_at']),
        'ends_at': _hhmm(w['ends_at']),
        'valid_from': w['valid_from'],
        'valid_to': w['valid_to'],
      },
  ],
};

MockRow _entry(Map<String, Object?> e) => {
  'menu_item_id': e['menu_item_id'],
  'category_id': e['category_id'],
  'size_label': e['size_label'],
};

/// The database keeps `HH:MM` (`to_char(…, 'HH24:MI')`).
String? _hhmm(Object? v) =>
    v is String && v.length >= 5 ? v.substring(0, 5) : null;

Never _invalid(MockRequest req, String field) => req.fail(
  MockResponse.error(
    400,
    'Check the deal\'s "$field".',
    code: 'DEAL_INVALID',
    vars: {'field': field},
  ),
);

Never _windowInvalid(MockRequest req, int index, String field) => req.fail(
  MockResponse.error(
    400,
    'Check window ${index + 1} ($field).',
    code: 'DEAL_INVALID',
    vars: {'window_index': index, 'field': field},
  ),
);

/// A body the JSON extractor refuses before the handler runs.
Never _badJson(MockRequest req, String detail) =>
    req.badRequest('Json deserialize error: $detail');

int? _int(
  MockRequest req,
  Map<String, Object?> b,
  String key, {
  bool required = false,
}) {
  final v = b[key];
  if (v == null) {
    if (required) _badJson(req, 'missing field `$key`');
    return null;
  }
  if (v is int) return v;
  if (v is num && v == v.truncate()) return v.toInt();
  _badJson(req, 'invalid type: floating point `$v`, expected i16');
}

/// `validate` + `validate_pool` + `validate_windows`.
void _validate(MockRequest req, MockDb db, String org, Map<String, Object?> b) {
  final name = b['name'];
  if (name is! String) _badJson(req, 'missing field `name`');
  final kind = b['kind'];
  if (kind is! String) _badJson(req, 'missing field `kind`');
  if (b['pool'] is! List) _badJson(req, 'missing field `pool`');
  final qty = _int(req, b, 'qty', required: true)!;
  final price = _int(req, b, 'price');
  final getQty = _int(req, b, 'get_qty');
  final getPercent = _int(req, b, 'get_percent');
  final max = _int(req, b, 'max_per_order');
  final pool = _maps(b['pool']);
  final reward = _maps(b['reward_pool']);

  if (name.trim().isEmpty) _invalid(req, 'name');
  switch (kind) {
    case 'n_for_price':
      if (qty < 2 || qty > 20) _invalid(req, 'qty');
      if (price == null || price < 0) _invalid(req, 'price');
      if (getQty != null) _invalid(req, 'get_qty');
      if (getPercent != null) _invalid(req, 'get_percent');
      if (reward.isNotEmpty) _invalid(req, 'reward_pool');
    case 'buy_get':
      if (qty < 1 || qty > 20) _invalid(req, 'qty');
      if (price != null) _invalid(req, 'price');
      if (getQty == null || getQty < 1 || getQty > 20) {
        _invalid(req, 'get_qty');
      }
      if (getPercent == null || getPercent < 1 || getPercent > 100) {
        _invalid(req, 'get_percent');
      }
    default:
      _invalid(req, 'kind');
  }
  if (max != null && max < 1) _invalid(req, 'max_per_order');
  if (pool.isEmpty) _invalid(req, 'pool');
  _validatePool(req, db, org, pool, 'pool');
  _validatePool(req, db, org, reward, 'reward_pool');
  _validateWindows(req, db, org, _maps(b['windows']));
}

void _validatePool(
  MockRequest req,
  MockDb db,
  String org,
  List<Map<String, Object?>> pool,
  String field,
) {
  final items = db.table(OffersTables.menuItems);
  final cats = db.table(OffersTables.categories);
  for (final e in pool) {
    final item = e['menu_item_id'];
    final cat = e['category_id'];
    if ((item == null) == (cat == null)) _invalid(req, field);
    final size = e['size_label'];
    if (size is String && size.trim().isEmpty) _invalid(req, field);
    if (item is String) {
      final r = items.find(item);
      if (r == null ||
          r['org_id'] != org ||
          r['deleted_at'] != null ||
          (r['kind'] ?? 'item') != 'item') {
        _invalid(req, field);
      }
    }
    if (cat is String) {
      final r = cats.find(cat);
      if (r == null || r['org_id'] != org || r['deleted_at'] != null) {
        _invalid(req, field);
      }
    }
  }
}

final RegExp _time = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)(:([0-5]\d))?$');
final RegExp _date = RegExp(r'^\d{4}-\d{2}-\d{2}$');

void _validateWindows(
  MockRequest req,
  MockDb db,
  String org,
  List<Map<String, Object?>> windows,
) {
  for (final (i, w) in windows.indexed) {
    final from = w['valid_from'];
    final to = w['valid_to'];
    for (final d in [from, to]) {
      if (d != null && (d is! String || !_date.hasMatch(d))) {
        _badJson(req, 'input contains invalid characters');
      }
    }
    final days = (w['weekdays'] as num?)?.toInt() ?? 127;
    if (days < 1 || days > 127) _windowInvalid(req, i, 'weekdays');
    final s = w['starts_at'];
    final e = w['ends_at'];
    if (s != null && (s is! String || !_time.hasMatch(s))) {
      _windowInvalid(req, i, 'starts_at');
    }
    if (e != null && (e is! String || !_time.hasMatch(e))) {
      _windowInvalid(req, i, 'ends_at');
    }
    if (s != null && e == null) _windowInvalid(req, i, 'ends_at');
    if (s == null && e != null) _windowInvalid(req, i, 'starts_at');
    if (s != null && e != null && _hhmm(s) == _hhmm(e)) {
      _windowInvalid(req, i, 'ends_at');
    }
    if (from is String && to is String && from.compareTo(to) > 0) {
      _windowInvalid(req, i, 'valid_to');
    }
    final branch = w['branch_id'];
    if (branch != null) {
      final r = branch is String ? db['branches'].find(branch) : null;
      if (r == null || r['org_id'] != org || r['deleted_at'] != null) {
        _windowInvalid(req, i, 'branch_id');
      }
    }
  }
}
