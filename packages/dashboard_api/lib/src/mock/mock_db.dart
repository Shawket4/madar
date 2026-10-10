/// An in-memory store of JSON rows, with the backend's two list conventions:
/// `page`/`per_page` → `{data, total, page, per_page, total_pages}` and
/// `limit`/`offset` → a plain array.
library;

import 'mock_clock.dart';
import 'mock_ids.dart';
import 'mock_server.dart';
import 'seed.dart';

typedef MockRow = Map<String, Object?>;

/// Generic tables keyed by `id`. Rows are plain JSON maps (a model's
/// `toJson()`), so whatever a handler answers has the spec's exact shape.
class MockDb {
  MockDb({MockClock? clock}) : clock = clock ?? MockClock();

  /// A database holding the seed (see [MockSeed.loadInto] for the tables).
  factory MockDb.seeded({MockClock? clock}) {
    final db = MockDb(clock: clock);
    MockSeed.instance.loadInto(db);
    return db;
  }

  final MockClock clock;

  final Map<String, MockTable> _tables = {};
  final Map<String, int> _seq = {};

  /// The table [name], created empty on first use.
  MockTable table(String name) => _tables[name] ??= MockTable._(this, name);

  MockTable operator [](String name) => table(name);

  bool hasTable(String name) => _tables.containsKey(name);

  Iterable<String> get tableNames => _tables.keys;

  /// A table whose rows are produced by [loader] the first time it is read.
  MockTable lazyTable(String name, Iterable<MockRow> Function() loader) {
    final t = table(name);
    t._loader = loader;
    return t;
  }

  /// A new deterministic id for a row of [table]: the n-th create in a run is
  /// always the same uuid.
  String newId(String table) {
    final n = (_seq[table] ?? 0) + 1;
    _seq[table] = n;
    return mockUuid('$table#$n');
  }

  /// Now as the backend writes timestamps (UTC ISO-8601).
  String get nowIso => clock.now.toIso8601String();
}

/// One table of JSON rows, indexed by `id`.
class MockTable {
  MockTable._(this.db, this.name);

  final MockDb db;
  final String name;
  final List<MockRow> _rows = [];
  final Map<String, int> _index = {};
  Iterable<MockRow> Function()? _loader;

  void _load() {
    final loader = _loader;
    if (loader == null) return;
    _loader = null;
    for (final r in loader()) {
      _put(r);
    }
  }

  void _put(MockRow row) {
    final id = row['id'];
    if (id is String) {
      final at = _index[id];
      if (at != null) {
        _rows[at] = row;
        return;
      }
      _index[id] = _rows.length;
    }
    _rows.add(row);
  }

  void _reindex() {
    _index.clear();
    for (var i = 0; i < _rows.length; i++) {
      final id = _rows[i]['id'];
      if (id is String) _index[id] = i;
    }
  }

  /// Every row, in insertion order (live list: do not mutate).
  List<MockRow> get rows {
    _load();
    return _rows;
  }

  int get length => rows.length;

  bool get isEmpty => rows.isEmpty;

  MockRow? find(String id) {
    _load();
    final at = _index[id];
    return at == null ? null : _rows[at];
  }

  /// The row [id], or a 404 in the backend's envelope ([what] names it).
  MockRow get(String id, {String? what}) =>
      find(id) ??
      (throw MockHttpError(MockResponse.notFound(what ?? _singular)));

  String get _singular {
    final words = name.replaceAll('_', ' ');
    final one = words.endsWith('s')
        ? words.substring(0, words.length - 1)
        : words;
    return one.isEmpty ? 'Resource' : one[0].toUpperCase() + one.substring(1);
  }

  List<MockRow> where(bool Function(MockRow row) test) =>
      rows.where(test).toList();

  MockRow? firstWhere(bool Function(MockRow row) test) {
    for (final r in rows) {
      if (test(r)) return r;
    }
    return null;
  }

  /// Adds [row]: assigns an `id` when it has none and, with [timestamps],
  /// `created_at`/`updated_at` when missing. Returns the stored row.
  MockRow insert(MockRow row, {bool timestamps = true}) {
    _load();
    final r = MockRow.of(row);
    r['id'] ??= db.newId(name);
    if (timestamps) {
      r['created_at'] ??= db.nowIso;
      r['updated_at'] ??= r['created_at'];
    }
    _put(r);
    return r;
  }

  void insertAll(Iterable<MockRow> rows, {bool timestamps = false}) {
    for (final r in rows) {
      insert(r, timestamps: timestamps);
    }
  }

  /// Merges [patch] into row [id] (404 when absent) and bumps `updated_at`
  /// when the row has one.
  MockRow update(String id, MockRow patch, {String? what}) {
    final row = get(id, what: what);
    row.addAll(patch);
    if (row.containsKey('updated_at')) row['updated_at'] = db.nowIso;
    return row;
  }

  /// Replaces row [id] (or adds it).
  MockRow put(MockRow row) {
    _load();
    final r = MockRow.of(row);
    _put(r);
    return r;
  }

  /// Removes row [id]; false when it was not there.
  bool delete(String id) {
    _load();
    final at = _index.remove(id);
    if (at == null) return false;
    _rows.removeAt(at);
    _reindex();
    return true;
  }

  void removeWhere(bool Function(MockRow row) test) {
    rows.removeWhere(test);
    _reindex();
  }

  void clear() {
    _loader = null;
    _rows.clear();
    _index.clear();
  }

  /// Filters and sorts the rows:
  /// - [filters]: `{field: value}`, equality on the row's field (null values
  ///   are skipped, so query params can be passed straight through);
  /// - [search] matched case-insensitively against [searchFields];
  /// - [from]/[to] bound [dateField] (ISO strings compare as instants);
  /// - [sort] by a field, `-field` for descending; ties keep insertion order.
  List<MockRow> query({
    Map<String, Object?> filters = const {},
    bool Function(MockRow row)? where,
    String? search,
    List<String> searchFields = const ['name'],
    DateTime? from,
    DateTime? to,
    String dateField = 'created_at',
    String? sort,
  }) => queryRows(
    rows,
    filters: filters,
    where: where,
    search: search,
    searchFields: searchFields,
    from: from,
    to: to,
    dateField: dateField,
    sort: sort,
  );
}

/// [MockTable.query] over any list of rows.
List<MockRow> queryRows(
  Iterable<MockRow> rows, {
  Map<String, Object?> filters = const {},
  bool Function(MockRow row)? where,
  String? search,
  List<String> searchFields = const ['name'],
  DateTime? from,
  DateTime? to,
  String dateField = 'created_at',
  String? sort,
}) {
  final active = {
    for (final e in filters.entries)
      if (e.value != null) e.key: e.value,
  };
  final needle = search?.trim().toLowerCase();
  final fromMs = from?.toUtc().millisecondsSinceEpoch;
  final toMs = to?.toUtc().millisecondsSinceEpoch;
  final out = <MockRow>[];
  for (final r in rows) {
    var ok = true;
    for (final e in active.entries) {
      if (!_matches(r[e.key], e.value)) {
        ok = false;
        break;
      }
    }
    if (!ok) continue;
    if (where != null && !where(r)) continue;
    if (needle != null && needle.isNotEmpty) {
      final hit = searchFields.any(
        (f) => (r[f]?.toString().toLowerCase() ?? '').contains(needle),
      );
      if (!hit) continue;
    }
    if (fromMs != null || toMs != null) {
      final v = r[dateField];
      final at = v is String
          ? DateTime.tryParse(v)?.millisecondsSinceEpoch
          : null;
      if (at == null) continue;
      if (fromMs != null && at < fromMs) continue;
      if (toMs != null && at >= toMs) continue;
    }
    out.add(r);
  }
  if (sort != null && sort.isNotEmpty) {
    final desc = sort.startsWith('-');
    final field = desc ? sort.substring(1) : sort;
    final indexed = [for (var i = 0; i < out.length; i++) (i, out[i])];
    indexed.sort((a, b) {
      final c = compareJson(a.$2[field], b.$2[field]);
      if (c != 0) return desc ? -c : c;
      return a.$1 - b.$1;
    });
    return [for (final e in indexed) e.$2];
  }
  return out;
}

bool _matches(Object? actual, Object? wanted) {
  if (wanted is Iterable) return wanted.any((w) => _matches(actual, w));
  if (actual is num && wanted is String) return actual.toString() == wanted;
  if (actual is bool && wanted is String) return actual.toString() == wanted;
  return actual == wanted;
}

/// Orders JSON values: nulls last, numbers numerically, strings
/// case-insensitively, booleans false < true.
int compareJson(Object? a, Object? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  if (a is num && b is num) return a.compareTo(b);
  if (a is bool && b is bool) return (a ? 1 : 0) - (b ? 1 : 0);
  return a.toString().toLowerCase().compareTo(b.toString().toLowerCase());
}

/// One page in the backend's `page`/`per_page` envelope (`PaginatedOrders`,
/// `PaginatedTills`, …): `{data, total, page, per_page, total_pages}` plus
/// [extra] fields (e.g. `summary`). `page` is 1-based and clamped to ≥ 1;
/// `per_page` defaults to [defaultPerPage] and is clamped to 1..[maxPerPage].
Map<String, Object?> pageOf(
  List<Object?> items,
  MockRequest req, {
  int defaultPerPage = 50,
  int maxPerPage = 200,
  Map<String, Object?> extra = const {},
}) {
  final page = (req.qInt('page') ?? 1) < 1 ? 1 : (req.qInt('page') ?? 1);
  final perPage = (req.qInt('per_page') ?? defaultPerPage).clamp(1, maxPerPage);
  final total = items.length;
  final start = ((page - 1) * perPage).clamp(0, total);
  final end = (start + perPage).clamp(0, total);
  return {
    'data': items.sublist(start, end),
    'total': total,
    'page': page,
    'per_page': perPage,
    'total_pages': (total / perPage).ceil(),
    ...extra,
  };
}

/// One window in the backend's `limit`/`offset` convention: a plain array.
/// `limit` defaults to [defaultLimit] and is clamped to 1..[maxLimit].
List<T> sliceOf<T>(
  List<T> items,
  MockRequest req, {
  int defaultLimit = 100,
  int maxLimit = 500,
}) {
  final limit = (req.qInt('limit') ?? defaultLimit).clamp(1, maxLimit);
  final offset = (req.qInt('offset') ?? 0).clamp(0, items.length);
  final end = (offset + limit).clamp(0, items.length);
  return items.sublist(offset, end);
}
