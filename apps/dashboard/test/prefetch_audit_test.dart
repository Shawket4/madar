// The intent-prefetch audit in the ASSEMBLED app: every area, the mock
// backend with the mock app's 120 ms latency (`--dart-define=MADAR_MOCK=1`),
// a clock that MOVES (as the real app's does: the mock app's stands still),
// animations on, and a mouse. For each page the web's `prefetchRoute` warms
// (MadarDashboard `src/lib/route-prefetch.ts`), it rests the mouse on the
// page's sidebar row, lets the warm reads land, clicks, and records every
// request the page then makes.
//
// The rule is the web's: a read warmed on hover (and, with a branch picked,
// any read the web warms for that path) is never asked again on open.
// `FDASH_AUDIT=1` prints the audit table.
import 'dart:convert';
import 'dart:io';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madar_dashboard/areas.dart';
import 'package:madar_dashboard/boot/mock.dart' show mockLatency;

/// What the web's `prefetchRoute` warms for each path with a branch picked
/// (API path templates).
const Map<String, List<String>> webWarmBranch = {
  '/': [
    '/reports/branches/{branch_id}/sales',
    '/reports/branches/{branch_id}/sales/timeseries',
    '/reports/orgs/{org_id}/comparison',
  ],
  '/orders': ['/orders'],
  '/tills': ['/tills/branches/{branch_id}/open'],
  '/menu/items': ['/costing/catalog', '/categories', '/addon-items'],
  // The web's nav says /menu/pricing; its prefetch case is the retired
  // /menu/overrides, so the web warms nothing here.
  '/menu/pricing': [],
  '/discounts': ['/discounts'],
  '/branches': ['/branches'],
  '/orgs': ['/orgs'],
  '/access/users': ['/users'],
  '/access/roles': ['/users'],
  '/settings/payment-methods': ['/payment-methods'],
  '/reports/operations': ['/reports/branches/{branch_id}/sales'],
  '/reports/financial': ['/insights/branches/{branch_id}/menu-margin'],
  '/reports/inventory': ['/reports/branches/{branch_id}/consumption'],
  '/inventory/today': [
    '/reports/branches/{branch_id}/inventory-valuation',
    '/reports/branches/{branch_id}/low-stock',
    '/inventory/branches/{branch_id}/stock',
    '/inventory/branches/{branch_id}/waste',
    '/purchasing/orgs/{org_id}/suppliers',
    '/inventory/orgs/{org_id}/catalog',
  ],
  '/inventory/ingredients': [
    '/inventory/orgs/{org_id}/catalog',
    '/branches',
    '/inventory/branches/{branch_id}/stock',
  ],
  '/inventory/purchasing': [
    '/purchasing/orgs/{org_id}/suppliers',
    '/inventory/orgs/{org_id}/catalog',
    '/purchasing/branches/{branch_id}/orders',
  ],
  '/inventory/counts': ['/stocktakes/branches/{branch_id}'],
  '/inventory/waste': [
    '/inventory/branches/{branch_id}/waste',
    '/reports/branches/{branch_id}/waste-report',
  ],
  '/inventory/transfers': [
    '/branches',
    '/inventory/branches/{branch_id}/transfers',
  ],
  '/inventory/settings': ['/inventory/orgs/{org_id}/settings'],
};

/// Sidebar parents the web warms through their base path (they open their
/// children; they do not navigate).
const Map<String, String> parentsWarming = {
  '/menu': '/menu/items',
  '/inventory': '/inventory/today',
};

/// One page's audit line.
class AuditRow {
  AuditRow(this.path);
  final String path;
  bool inSidebar = false;
  String landed = '';
  List<String> warmed = [];
  List<String> refetched = [];
  List<String> other = [];
}

String _call(MockCall c) {
  final q = c.query.isEmpty
      ? ''
      : '?${[for (final e in c.query.entries) '${e.key}=${e.value.join(',')}'].join('&')}';
  return '${c.method} ${c.path}$q';
}

/// Runs the audit as [persona] with [prefs] (the scope) and returns its rows;
/// [webWarm] (with a branch picked) adds the web's own list to the rule.
Future<List<AuditRow>> _audit(
  WidgetTester tester, {
  required Persona persona,
  required Map<String, String> prefs,
  Map<String, List<String>>? webWarm,
}) async {
  final db = MockDb.seeded();
  final server = MockServer(
    persona: persona,
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
    persona: persona,
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

  await wait();
  final sidebar = find.byType(DashSidebar);
  Finder rowFor(String to) => find.descendant(
    of: sidebar,
    matching: find.byWidgetPredicate(
      (w) => w is PrefetchOnIntent && w.to == to,
    ),
  );

  // Every row shown: the groups' "N more" and every parent opened.
  Future<void> expandAll() async {
    for (var guard = 0; guard < 10; guard++) {
      final more = find.descendant(
        of: sidebar,
        matching: find.textContaining(RegExp(r'^\d+ more$')),
      );
      if (more.evaluate().isEmpty) break;
      await tester.ensureVisible(more.first);
      await tester.tap(more.first);
      await wait(rounds: 2);
    }
    for (final g in dashNav) {
      for (final e in g.entries) {
        if (e is! NavParent) continue;
        final children = e.children.map((c) => c.to).toSet();
        final shown = tester
            .widgetList<PrefetchOnIntent>(
              find.descendant(
                of: sidebar,
                matching: find.byType(PrefetchOnIntent),
              ),
            )
            .any((w) => children.contains(w.to));
        final row = rowFor(e.basePath);
        if (shown || row.evaluate().isEmpty) continue;
        await tester.ensureVisible(row);
        await tester.tap(row, warnIfMissed: false);
        await wait(rounds: 2);
      }
    }
  }

  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: const Offset(1, 1));
  addTearDown(mouse.removePointer);

  /// A cold start: a page that reads none of it, the cache emptied.
  Future<Offset?> coldRow(String to) async {
    await mouse.moveTo(const Offset(1, 1));
    await h.go('/settings');
    await wait();
    h.container.read(queryCacheProvider).clear();
    await wait();
    await expandAll();
    final target = rowFor(to);
    if (target.evaluate().isEmpty) return null;
    await tester.ensureVisible(target);
    await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
    await wait(rounds: 2);
    return tester.getCenter(target);
  }

  final rows = <AuditRow>[];
  for (final path in webWarmBranch.keys) {
    final row = AuditRow(path);
    rows.add(row);
    final at = await coldRow(path);
    if (at == null) continue;
    row.inSidebar = true;

    var mark = h.server.calls.length;
    await mouse.moveTo(at);
    await wait();
    final warmed = h.server.calls.skip(mark).map(_call).toSet();
    row.warmed = [...warmed];

    mark = h.server.calls.length;
    await mouse.down(at);
    await mouse.up();
    await wait(rounds: 30);
    row.landed = h.location.path;
    for (final c in h.server.calls.skip(mark)) {
      final line = _call(c);
      final webRead =
          c.method == 'GET' &&
          (webWarm?[path]?.contains(c.template) ?? false);
      if (warmed.contains(line) || webRead) {
        row.refetched.add(line);
      } else {
        row.other.add(line);
      }
    }
  }
  // A parent row warms the page its base path lands on.
  for (final MapEntry(key: parent, value: page) in parentsWarming.entries) {
    final row = AuditRow('$parent (parent row, warms $page)');
    rows.add(row);
    final at = await coldRow(parent);
    if (at == null) continue;
    row
      ..inSidebar = true
      ..landed = parent;
    final mark = h.server.calls.length;
    await mouse.moveTo(at);
    await wait();
    row.warmed = h.server.calls.skip(mark).map(_call).toSet().toList();
  }
  return rows;
}

String _table(List<AuditRow> rows, Map<String, List<String>>? webWarm) {
  final b = StringBuffer()
    ..writeln(
      '| path | web-warmed reads | warmed on hover | refetched on open | '
      'other reads on open |',
    )
    ..writeln('|---|---|---|---|---|');
  for (final r in rows) {
    final listed = webWarm?[r.path];
    final web = listed == null
        ? ''
        : listed.isEmpty
        ? '(none)'
        : listed.join('<br>');
    if (!r.inSidebar) {
      b.writeln('| ${r.path} | $web | not in the sidebar | | |');
      continue;
    }
    final moved = r.landed == r.path || r.path.contains(' ')
        ? ''
        : ' → ${r.landed}';
    b.writeln(
      '| ${r.path}$moved | $web | '
      '${r.warmed.isEmpty ? '(nothing)' : r.warmed.join('<br>')} | '
      '${r.refetched.isEmpty ? 'no' : 'YES: ${r.refetched.join('<br>')}'} | '
      '${r.other.toSet().join('<br>')} |',
    );
  }
  return b.toString();
}

void _check(String name, List<AuditRow> rows, Map<String, List<String>>? web) {
  final table = _table(rows, web);
  if (Platform.environment['FDASH_AUDIT'] != null) {
    debugPrint('## $name\n$table', wrapWidth: null);
  }
  expect(
    [
      for (final r in rows)
        if (r.refetched.isNotEmpty) '${r.path}: ${r.refetched.join(', ')}',
    ],
    isEmpty,
    reason: table,
  );
  for (final p in parentsWarming.keys) {
    final r = rows.firstWhere((r) => r.path.startsWith('$p '));
    if (r.inSidebar) {
      expect(r.warmed, isNotEmpty, reason: '$p warms ${parentsWarming[p]}');
    }
  }
}

void main() {
  testWidgets('owner, a branch picked: every warmed page opens from the cache', (
    tester,
  ) async {
    final rows = await _audit(
      tester,
      persona: Persona.owner,
      prefs: {
        ScopePrefKeys.branch: jsonEncode({
          'org': SeedIds.sabahOrg,
          'branch': SeedIds.heliopolis,
        }),
      },
      webWarm: webWarmBranch,
    );
    _check('owner, Heliopolis', rows, webWarmBranch);
  });

  testWidgets('owner, all branches: what is warmed is not asked again', (
    tester,
  ) async {
    final rows = await _audit(tester, persona: Persona.owner, prefs: const {});
    _check('owner, all branches', rows, null);
  });

  testWidgets('platform admin, an org picked: the same', (tester) async {
    final rows = await _audit(
      tester,
      persona: Persona.platform,
      prefs: {
        ScopePrefKeys.org: jsonEncode({'id': SeedIds.sabahOrg}),
        ScopePrefKeys.branch: jsonEncode({
          'org': SeedIds.sabahOrg,
          'branch': SeedIds.heliopolis,
        }),
      },
    );
    _check('platform, Sabah, Heliopolis', rows, null);
  });
}
