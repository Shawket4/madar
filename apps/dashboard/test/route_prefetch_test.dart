// The route registry's prefetch, route by route, in the ASSEMBLED app (every
// area, the mock backend with the mock app's 120 ms latency, a clock that
// moves).
//
// For every page the registry lists, from a page that reads none of it with
// the cache emptied:
// - cold: open it and record the reads it makes (and when the last one
//   landed: the tap-to-content time under the mock's latency);
// - warmed: run its `prefetch` (what a hover, focus or touch on any link to
//   it does), let the reads land, open it, and record what it still asks.
//
// The rules:
// - a page that reads anything on open has a `prefetch`, unless it is on
//   [nothingToWarm] with the reason;
// - a prefetch never writes and never exports: GETs only;
// - a read the prefetch warmed is never asked again on open (the warm and
//   the page share the provider AND its argument, so it is a cache hit);
// - once warmed, a page asks nothing at all on open (the providers warmed
//   are every one it watches on mount), unless [partialHit] says why not.
//
// `FDASH_AUDIT=1` prints the table (cold vs warmed reads and times);
// `FDASH_ROUTES=/staff,/settings` walks only the routes under those prefixes.
import 'dart:convert';
import 'dart:io';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madar_dashboard/areas.dart';
import 'package:madar_dashboard/boot/mock.dart' show mockLatency;

/// A record for each templated route, from the seed.
final Map<String, String> samples = {
  '/menu/items/:itemId': '/menu/items/${MockSeed.menuItemId('latte')}',
  '/menu/combos/:comboId':
      '/menu/combos/${mockUuid('combo:morning-croissant')}',
};

/// Pages with nothing a prefetch can warm, and why. A page listed here that
/// gains a `prefetch` must leave the list.
const Map<String, String> nothingToWarm = {
  '/settings': 'Appearance: local preferences only, no read',
  '/basira':
      'no query cache: the conversations are read fresh by its controller on '
      'every open, as on the web (REP-BAS-002/004)',
};

/// Pages that, once warmed, still ask something on open, and why. Every
/// other page asks the server NOTHING once warmed: the providers warmed are
/// every one the page watches on mount, with the same arguments.
const Map<String, String> partialHit = {
  '/menu/items/:itemId':
      'the step animations: one file per step, named by the step library '
      'answer (assets, fetched once it lands)',
  '/menu/groups':
      "each group's usage, keyed by the ids in the group list answer",
};

class _Row {
  _Row(this.path, this.location);
  final String path;
  final String location;
  bool hasPrefetch = false;
  List<String> cold = [];
  Duration coldTime = Duration.zero;
  List<String> warmed = [];
  List<String> writes = [];
  List<String> refetched = [];
  List<String> notWarmed = [];
  Duration warmTime = Duration.zero;
}

String _call(MockCall c) {
  final q = c.query.isEmpty
      ? ''
      : '?${[for (final e in c.query.entries) '${e.key}=${e.value.join(',')}'].join('&')}';
  return '${c.method} ${c.path}$q';
}

bool _isRead(MockCall c) => c.method.toUpperCase() == 'GET';

Future<List<_Row>> _walk(
  WidgetTester tester, {
  required Map<String, String> prefs,
}) async {
  final db = MockDb.seeded();
  final server = MockServer(
    persona: Persona.owner,
    clock: db.clock,
    latency: mockLatency,
  );
  registerCoreMocks(server, db);
  for (final a in dashboardAreas) {
    a.registerMocks?.call(server, db);
  }
  final h = await DashHarness.pump(
    tester,
    areas: dashboardAreas,
    path: '/settings',
    server: server,
    db: db,
    reducedMotion: false,
    prefs: prefs,
  );
  h
    ..allowUnmatched = true
    ..allowMissingKeys = true;

  // The clock moves with the frames, the server's with it.
  Future<void> wait({int rounds = 12}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(() async {
        for (var j = 0; j < 5; j++) {
          await Future<void>.delayed(Duration.zero);
        }
      });
      db.clock.advance(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> cold() async {
    h.router.go('/settings');
    await wait();
    h.container.read(queryCacheProvider).clear();
    await wait();
  }

  /// When the last read [calls] made landed, from [start].
  Duration landed(Iterable<MockCall> calls, DateTime start) {
    var last = Duration.zero;
    for (final c in calls.where(_isRead)) {
      final d = c.at.difference(start) + mockLatency;
      if (d > last) last = d;
    }
    return last;
  }

  // `FDASH_ROUTES=/staff,/settings`: only the routes under these prefixes.
  final only = Platform.environment['FDASH_ROUTES']?.split(',');
  final rows = <_Row>[];
  for (final (path, route) in flattenRoutes(dashboardAreas)) {
    if (route.builder == null) continue;
    if (only != null && !only.any(path.startsWith)) continue;
    final location = samples[path] ?? path;
    final row = _Row(path, location)..hasPrefetch = route.prefetch != null;
    rows.add(row);
    if (path.contains(':') && !samples.containsKey(path)) continue;

    // Cold.
    await cold();
    var mark = h.server.calls.length;
    var start = db.clock.now;
    h.router.go(location);
    await wait(rounds: 30);
    final coldCalls = h.server.calls.skip(mark).toList();
    row
      ..cold = coldCalls.where(_isRead).map(_call).toSet().toList()
      ..coldTime = landed(coldCalls, start);

    // Warmed, then opened.
    await cold();
    mark = h.server.calls.length;
    prefetchRouteIn(h.container, location);
    await wait();
    final warmCalls = h.server.calls.skip(mark).toList();
    final warmed = warmCalls.where(_isRead).map(_call).toSet();
    row
      ..warmed = [...warmed]
      ..writes = [
        for (final c in warmCalls)
          if (!_isRead(c) || c.path.contains('export')) _call(c),
      ];
    mark = h.server.calls.length;
    start = db.clock.now;
    h.router.go(location);
    await wait(rounds: 30);
    final openCalls = h.server.calls.skip(mark).toList();
    row.warmTime = landed(openCalls, start);
    for (final c in openCalls.where(_isRead)) {
      final line = _call(c);
      (warmed.contains(line) ? row.refetched : row.notWarmed).add(line);
    }
  }
  return rows;
}

String _ms(Duration d) => '${d.inMilliseconds} ms';

String _table(List<_Row> rows) {
  final b = StringBuffer()
    ..writeln(
      '| path | prefetch | cold reads | cold content | warmed reads | '
      'refetched | still read on open | warmed content |',
    )
    ..writeln('|---|---|---|---|---|---|---|---|');
  for (final r in rows) {
    b.writeln(
      '| ${r.location == r.path ? r.path : '${r.path} (${r.location})'} | '
      '${r.hasPrefetch ? 'yes' : 'NO'} | ${r.cold.length} | '
      '${_ms(r.coldTime)} | ${r.warmed.length} | '
      '${r.refetched.isEmpty ? '' : r.refetched.join('<br>')} | '
      '${r.notWarmed.toSet().join('<br>')} | ${_ms(r.warmTime)} |',
    );
  }
  return b.toString();
}

void main() {
  testWidgets('every data-loading route warms its page from the registry, '
      'as a cache hit', (tester) async {
    final rows = await _walk(
      tester,
      prefs: {
        ScopePrefKeys.branch: jsonEncode({
          'org': SeedIds.sabahOrg,
          'branch': SeedIds.heliopolis,
        }),
      },
    );
    final table = _table(rows);
    if (Platform.environment['FDASH_AUDIT'] != null) {
      debugPrint('## route prefetch\n$table', wrapWidth: null);
    }
    final templatedWithoutSample = [
      for (final r in rows)
        if (r.path.contains(':') && !samples.containsKey(r.path)) r.path,
    ];
    expect(
      templatedWithoutSample,
      isEmpty,
      reason: 'a detail route needs a sample record in `samples`',
    );
    expect(
      [
        for (final r in rows)
          if (!r.hasPrefetch &&
              r.cold.isNotEmpty &&
              !nothingToWarm.containsKey(r.path))
            '${r.path}: ${r.cold.join(', ')}',
      ],
      isEmpty,
      reason: 'a page that reads on open needs a `prefetch`\n$table',
    );
    expect(
      [
        for (final p in nothingToWarm.keys)
          if (rows.where((r) => r.path == p).firstOrNull case final r?)
            if (r.hasPrefetch) p,
      ],
      isEmpty,
      reason: 'off the allow-list: it has a prefetch now',
    );
    expect(
      [
        for (final r in rows)
          if (r.writes.isNotEmpty) '${r.path}: ${r.writes.join(', ')}',
      ],
      isEmpty,
      reason: 'a prefetch never writes or exports',
    );
    expect(
      [
        for (final r in rows)
          if (r.refetched.isNotEmpty) '${r.path}: ${r.refetched.join(', ')}',
      ],
      isEmpty,
      reason: 'a warmed read asked again = a different key\n$table',
    );
    expect(
      [
        for (final r in rows)
          if (!partialHit.containsKey(r.path) &&
              !nothingToWarm.containsKey(r.path) &&
              r.notWarmed.isNotEmpty)
            '${r.path}: ${r.notWarmed.join(', ')}',
      ],
      isEmpty,
      reason: 'a warmed page still asks on open\n$table',
    );
  });

  testWidgets('all branches: a warmed read is never asked again, and a '
      'prefetch never writes', (tester) async {
    final rows = await _walk(tester, prefs: const {});
    final table = _table(rows);
    if (Platform.environment['FDASH_AUDIT'] != null) {
      debugPrint('## route prefetch, all branches\n$table', wrapWidth: null);
    }
    expect(
      [
        for (final r in rows)
          if (r.writes.isNotEmpty || r.refetched.isNotEmpty)
            '${r.path}: ${[...r.writes, ...r.refetched].join(', ')}',
      ],
      isEmpty,
      reason: table,
    );
  });
}
