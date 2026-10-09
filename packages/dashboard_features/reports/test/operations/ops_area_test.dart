// The reports area's nav, legacy links and the cross-page refresh contract
// (REP-ALL-001…003, 006, 028), driven from Operations.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _reportPaths = [
  '/reports/operations',
  '/reports/financial',
  '/reports/inventory',
  '/reports/legal',
  '/reports/loyalty',
  '/reports/bundles',
  '/reports/staff',
  '/reports/staff-pool',
  '/reports/tills',
];

/// The sidebar's leaves (their paths), top to bottom, every group opened.
Future<List<String>> _leaves(DashHarness h) async {
  final more = find.descendant(
    of: find.byType(DashSidebar),
    matching: find.textContaining(RegExp(r'^\d+ more$')),
  );
  while (more.evaluate().isNotEmpty) {
    await h.tap(more.first);
  }
  return [
    for (final w in h.tester.widgetList<PrefetchOnIntent>(
      find.descendant(
        of: find.byType(DashSidebar),
        matching: find.byType(PrefetchOnIntent),
      ),
    ))
      w.to,
  ];
}

/// The sidebar's words, top to bottom.
List<String> _sidebarWords() => [
  for (final e in find
      .descendant(of: find.byType(DashSidebar), matching: find.byType(Text))
      .evaluate())
    (e.widget as Text).data ?? '',
];

void main() {
  testWidgets('REP-ALL-001 the Reports group lists its nine leaves in order; '
      'Operations is the active one', (tester) async {
    final h = await pumpOps(tester);
    final leaves = await _leaves(h);
    expect([for (final p in leaves) if (p.startsWith('/reports/')) p],
        _reportPaths);
    final words = _sidebarWords();
    expect(words, contains(h.t('nav.reports')));
    for (final k in ['nav.reportsStaffPool', 'nav.reportsBundles']) {
      expect(words, contains(h.t(k)));
    }
    final active = tester.widget<DashSidebar>(find.byType(DashSidebar)).path;
    expect(active, opsPath);
    await h.shot('operations/sidebar');
  });

  testWidgets('REP-ALL-003 the Basira group: one leaf "Ask"', (tester) async {
    final h = await pumpOps(tester);
    final words = _sidebarWords();
    final basira = words.indexOf(h.t('nav.basira'));
    expect(basira, isNot(-1));
    expect(words[basira + 1], h.t('nav.basiraAsk'));
  });

  testWidgets('REP-ALL-002 / 003 leaf gates: without till.read.branch no '
      'Tills (plain till.read is not enough); without reports.read no Basira',
      (tester) async {
    final s = opsServer();
    authzWithout(s.server, Persona.owner, {
      Cap.tillReadBranch,
      Cap.reportsRead,
    });
    final h = await pumpOps(tester, server: s.server, db: s.db);
    expect(h.container.read(authzProvider).can(Cap.tillRead), isTrue);
    final leaves = await _leaves(h);
    expect(leaves, isNot(contains('/reports/tills')));
    expect(leaves, isNot(contains('/basira')));
    expect(leaves, contains('/reports/operations'));
  });

  testWidgets('REP-ALL-002 without orders.read: no Operations leaf', (
    tester,
  ) async {
    final s = opsServer();
    authzWithout(s.server, Persona.owner, {Cap.ordersRead});
    final h = await pumpOps(tester, server: s.server, db: s.db);
    final leaves = await _leaves(h);
    expect(leaves, isNot(contains('/reports/operations')));
    // Financial stays for inventory.read.
    expect(leaves, contains('/reports/financial'));
  });

  testWidgets('REP-ALL-002 / 004 a Dawam-only org: Staff and Legal, no POS '
      'reports', (tester) async {
    final h = await pumpOps(
      tester,
      persona: Persona.dawamOnly,
      path: '/reports/legal',
    );
    final leaves = await _leaves(h);
    expect(leaves, contains('/reports/staff'));
    expect(leaves, contains('/reports/legal'));
    for (final p in [
      '/reports/operations',
      '/reports/financial',
      '/reports/tills',
      '/reports/staff-pool',
      '/basira',
    ]) {
      expect(leaves, isNot(contains(p)), reason: p);
    }
  });

  testWidgets('REP-ALL-001 the group is hidden when no leaf is visible', (
    tester,
  ) async {
    final s = opsServer();
    authzWithout(s.server, Persona.limited, {
      Cap.ordersRead,
      Cap.reportsRead,
    });
    final h = await pumpOps(
      tester,
      persona: Persona.limited,
      server: s.server,
      db: s.db,
    );
    expect(_sidebarWords(), isNot(contains(h.t('nav.reports'))));
  });

  group('REP-ALL-006 legacy links land on Operations › Tables, without '
      'the scope params', () {
    for (final from in [
      '/analytics',
      '/reports/sales',
      '/reports/operations/profitability',
      '/reports/operations/tables',
      '/insights/sales',
      '/insights/profitability',
      '/insights/tables',
    ]) {
      testWidgets(from, (tester) async {
        final h = await pumpOps(tester, path: '$from?preset=7d');
        expect(h.location.path, opsPath);
        expect(h.location.queryParameters, isEmpty);
        expect(opsPage, findsOneWidget);
        expect(pageText(h.t('tablesInsights.title')), findsWidgets);
      });
    }
  });

  testWidgets('REP-ALL-028 a till action elsewhere (`/tills`, `/reports`) '
      'refreshes Operations\' reports; Tables stays (its key is not a '
      'path)', (tester) async {
    final h = await pumpOps(tester);
    await openTab(h, 'Overview');
    expect(h.server.callsTo(salesRoute), hasLength(1));
    // invalidateTills: every `/tills*` and `/reports*` key.
    h.container.read(realtimeBusProvider).invalidate(const ['/tills', '/reports']);
    await h.settle();
    expect(h.server.callsTo(salesRoute), hasLength(2));
    await openTab(h, 'Tables');
    h.container.read(realtimeBusProvider).invalidate(const ['/reports']);
    await h.settle();
    expect(h.server.callsTo(metricsRoute, method: 'POST'), hasLength(1));
  });

  testWidgets('REP-ALL-028 an inventory or customer write elsewhere does '
      'not touch the analytics; a menu write refreshes the exclude list', (
    tester,
  ) async {
    final h = await pumpOps(tester);
    await openTab(h, 'Overview');
    await h.tap(inPage(find.byKey(const ValueKey('ops-exclude-trigger'))));
    expect(h.server.callsTo(menuRoute), hasLength(1));
    h.container
        .read(realtimeBusProvider)
        .invalidate(const ['/customers', '/loyalty/', '/stocktakes']);
    await h.settle();
    expect(h.server.callsTo(salesRoute), hasLength(1));
    expect(h.server.callsTo(menuRoute), hasLength(1));
    h.container.read(realtimeBusProvider).invalidate(const ['/menu-items']);
    await h.settle();
    expect(h.server.callsTo(menuRoute), hasLength(2));
  });
}
