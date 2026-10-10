// Every registered range deriver (madar-core `api_cache`) against the app's
// own mock server: the answer the core derives from a saved wider range
// equals the server's answer for the narrower one, on every field, over many
// sub-ranges (single days, month starts, ranges across a month end, Cairo
// midnights, empty days).
import 'dart:convert';
import 'dart:typed_data';

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madar_dashboard/areas.dart';
import 'package:rust_bridge_dashboard/rust_bridge_dashboard.dart'
    show ApiPair, CacheRequest;

/// How a path writes its range's ends: `timestamptz` instants or calendar
/// dates (the core's deriver for it reads them so).
enum _Kind { instant, date }

const _scope = CacheScope(user: 'u1');

const _zone = 'Africa/Cairo';

typedef _Days = (DateTime, DateTime);

/// Calendar days, both ends inclusive.
_Days _d(int m1, int d1, int m2, int d2) =>
    (DateTime.utc(2026, m1, d1), DateTime.utc(2026, m2, d2));

/// The seed's clock is 8 Oct 2026; the wide range is month to date and the
/// month before it.
final _Days _wide = _d(9, 1, 10, 8);

final List<_Days> _subs = [
  for (var d = 20; d <= 30; d++) _d(9, d, 9, d),
  for (var d = 1; d <= 8; d++) _d(10, d, 10, d),
  _d(9, 1, 9, 1), // the first day held, likely empty
  _d(10, 1, 10, 8), // the owner's case: 1st to 8th from month to date
  _d(10, 1, 10, 1),
  _d(9, 1, 9, 30),
  _d(9, 28, 10, 3), // across the month end
  _d(10, 5, 10, 8),
  _d(9, 1, 10, 8), // the wide range itself
];

String _ymd(DateTime d) => d.toIso8601String().substring(0, 10);

/// [days] as the request writes them: the period picker's local-day
/// boundaries for instants, calendar dates otherwise.
Map<String, List<String>> _range(_Days days, _Kind kind) {
  final (a, b) = days;
  return switch (kind) {
    _Kind.instant => {
      'from': [dayBoundaryISO(_zone, a.year, a.month - 1, a.day)],
      'to': [dayBoundaryISO(_zone, b.year, b.month - 1, b.day, endOfDay: true)],
    },
    _Kind.date => {
      'from': [_ymd(a)],
      'to': [_ymd(b)],
    },
  };
}

CacheRequest _call(String path, Map<String, List<String>> query) =>
    CacheRequest(
      method: 'GET',
      path: path,
      query: [
        for (final e in query.entries)
          for (final v in e.value) ApiPair(key: e.key, value: v),
      ],
      headers: const [],
    );

void main() {
  late MockServer server;
  late OfflineCache cache;

  setUp(() {
    final db = MockDb.seeded();
    server = MockServer(persona: Persona.owner, clock: db.clock);
    registerCoreMocks(server, db);
    for (final a in dashboardAreas) {
      a.registerMocks?.call(server, db);
    }
    cache = memoryOfflineCache()..claim(userId: _scope.user);
  });

  Future<List<int>> askRaw(String path, Map<String, List<String>> query) async {
    final r = await server.send(
      ApiRequest(
        method: 'GET',
        path: path,
        query: query,
        headers: {'X-Org-Id': SeedIds.sabahOrg},
      ),
    );
    return r.bodyBytes;
  }

  Future<Object?> ask(String path, Map<String, List<String>> query) async =>
      jsonDecode(utf8.decode(await askRaw(path, query)));

  /// Saves the server's answer to [path] over [query], as the transport does.
  Future<void> keep(String path, Map<String, List<String>> query) async =>
      cache.save(
        scope: _scope,
        request: _call(path, query),
        headers: const [
          ApiPair(key: 'content-type', value: 'application/json'),
        ],
        body: Uint8List.fromList(await askRaw(path, query)),
        atMs: 1,
      );

  /// Checks [path] over every sub-range; returns how many answers had rows.
  /// [source]: the endpoint the wider answer comes from, when not [path].
  Future<int> exact(
    String path,
    Map<String, List<String>> params, {
    required _Kind kind,
    String? source,
    bool ties = false,
  }) async {
    await keep(source ?? path, {...params, ..._range(_wide, kind)});
    var filled = 0;
    for (final sub in _subs) {
      final query = {...params, ..._range(sub, kind)};
      final saved = cache.saved(
        scope: _scope,
        request: _call(path, query),
        zone: _zone,
      );
      expect(saved, isNotNull, reason: '$path $sub');
      final derived = jsonDecode(utf8.decode(saved!.body));
      final answer = await ask(path, query);
      // Through JSON, as the transport hands it on.
      // [ties]: rows the server orders equal (attendance: same day, same
      // name) come in no set order, there as here; the same rows, though.
      expect(
        derived,
        ties ? unorderedEquals(answer! as List) : equals(answer),
        reason: '$path ${_range(sub, kind)}',
      );
      if (answer is List
          ? answer.isNotEmpty
          : (answer! as Map)['drinks'] != 0) {
        filled++;
      }
    }
    return filled;
  }

  final branch = SeedIds.heliopolis;

  test(
    'sales timeseries, daily and hourly, a branch and every branch',
    () async {
      for (final id in [branch, allBranchesId]) {
        for (final g in ['daily', 'hourly']) {
          final filled = await exact('/reports/branches/$id/sales/timeseries', {
            'granularity': [g],
          }, kind: _Kind.instant);
          expect(filled, greaterThan(5), reason: '$id $g');
        }
      }
    },
  );

  test('monthly points are never derived', () async {
    final path = '/reports/branches/$branch/sales/timeseries';
    final monthly = {
      'granularity': ['monthly'],
    };
    await keep(path, {...monthly, ..._range(_wide, _Kind.instant)});
    expect(
      cache.saved(
        scope: _scope,
        request: _call(path, {
          ...monthly,
          ..._range(_d(10, 1, 10, 8), _Kind.instant),
        }),
        zone: _zone,
      ),
      isNull,
    );
  });

  test('tills report', () async {
    expect(
      await exact('/reports/branches/$branch/tills', {}, kind: _Kind.instant),
      greaterThan(3),
    );
  });

  test('staff drinks and their summary', () async {
    for (final only in ['false', 'true']) {
      final params = {
        'branch_id': [branch],
        'overspent_only': [only],
      };
      await exact('/staff-pool/drinks', params, kind: _Kind.date);
      await exact(
        '/staff-pool/drinks/summary',
        params,
        kind: _Kind.date,
        source: '/staff-pool/drinks',
      );
    }
    expect(
      await exact('/staff-pool/drinks', {
        'branch_id': [branch],
      }, kind: _Kind.date),
      greaterThan(0),
    );
  });

  test('attendance', () async {
    expect(
      await exact('/staff/attendance', {}, kind: _Kind.date, ties: true),
      greaterThan(3),
    );
    await exact(
      '/staff/attendance',
      {
        'branch_id': [branch],
      },
      kind: _Kind.date,
      ties: true,
    );
  });
}
