// Every registered range deriver against the app's own mock server: the
// answer derived from a wider range equals the server's answer for the
// narrower one, on every field, over many sub-ranges (single days, month
// starts, ranges across a month end, Cairo midnights, empty days).
import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madar_dashboard/areas.dart';

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
Map<String, List<String>> _range(_Days days, RangeKind kind) {
  final (a, b) = days;
  return switch (kind) {
    RangeKind.instant => {
      'from': [dayBoundaryISO(_zone, a.year, a.month - 1, a.day)],
      'to': [
        dayBoundaryISO(_zone, b.year, b.month - 1, b.day, endOfDay: true),
      ],
    },
    RangeKind.date => {
      'from': [_ymd(a)],
      'to': [_ymd(b)],
    },
  };
}

void main() {
  late MockServer server;

  setUpAll(ensureTimeZones);

  setUp(() {
    final db = MockDb.seeded();
    server = MockServer(persona: Persona.owner, clock: db.clock);
    registerCoreMocks(server, db);
    for (final a in dashboardAreas) {
      a.registerMocks?.call(server, db);
    }
  });

  Future<Object?> ask(String path, Map<String, List<String>> query) async {
    final r = await server.send(
      ApiRequest(
        method: 'GET',
        path: path,
        query: query,
        headers: {'X-Org-Id': SeedIds.sabahOrg},
      ),
    );
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  /// Checks [path] over every sub-range; returns how many answers had rows.
  Future<int> exact(
    String path,
    Map<String, List<String>> params, {
    bool ties = false,
  }) async {
    final d = deriverFor(path)!;
    final wideQuery = {...params, ..._range(_wide, d.kind)};
    final wider = await ask(d.sourceOf(path), wideQuery);
    var filled = 0;
    for (final sub in _subs) {
      final query = {...params, ..._range(sub, d.kind)};
      final r = d.rangeOf(query)!;
      final want = DeriveRequest(
        path: path,
        match: d.path.firstMatch(path)!,
        query: query,
        from: r.from,
        to: r.to,
        zoneFor: (_) => _zone,
      );
      expect(d.covers(wideQuery, want), isTrue, reason: '$path $sub');
      final derived = d.derive(wider, want);
      expect(derived, isNotNull, reason: '$path $sub');
      final answer = await ask(path, query);
      // Through JSON, as the transport hands it on.
      // [ties]: rows the server orders equal (attendance: same day, same
      // name) come in no set order, there as here; the same rows, though.
      expect(
        jsonDecode(jsonEncode(derived)),
        ties ? unorderedEquals(answer! as List) : equals(answer),
        reason: '$path ${_range(sub, d.kind)}',
      );
      if (answer is List ? answer.isNotEmpty : (answer! as Map)['drinks'] != 0) {
        filled++;
      }
    }
    return filled;
  }

  final branch = SeedIds.heliopolis;

  test('sales timeseries, daily and hourly, a branch and every branch', () async {
    for (final id in [branch, allBranchesId]) {
      for (final g in ['daily', 'hourly']) {
        final filled = await exact('/reports/branches/$id/sales/timeseries', {
          'granularity': [g],
        });
        expect(filled, greaterThan(5), reason: '$id $g');
      }
    }
  });

  test('monthly points are never derived', () {
    final d = deriverFor('/reports/branches/$branch/sales/timeseries')!;
    final query = {
      'granularity': ['monthly'],
      ..._range(_d(10, 1, 10, 8), d.kind),
    };
    final r = d.rangeOf(query)!;
    final want = DeriveRequest(
      path: '/reports/branches/$branch/sales/timeseries',
      match: d.path.firstMatch('/reports/branches/$branch/sales/timeseries')!,
      query: query,
      from: r.from,
      to: r.to,
      zoneFor: (_) => _zone,
    );
    expect(d.derive(const <Object?>[], want), isNull);
  });

  test('tills report', () async {
    expect(await exact('/reports/branches/$branch/tills', {}), greaterThan(3));
  });

  test('staff drinks and their summary', () async {
    for (final only in ['false', 'true']) {
      final params = {
        'branch_id': [branch],
        'overspent_only': [only],
      };
      await exact('/staff-pool/drinks', params);
      await exact('/staff-pool/drinks/summary', params);
    }
    expect(
      await exact('/staff-pool/drinks', {
        'branch_id': [branch],
      }),
      greaterThan(0),
    );
  });

  test('attendance', () async {
    expect(await exact('/staff/attendance', {}, ties: true), greaterThan(3));
    await exact('/staff/attendance', {
      'branch_id': [branch],
    }, ties: true);
  });
}
