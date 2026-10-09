// Operations: the gate, the header, the tabs, the export's place, the read
// cache between tabs and the sidebar warm-up (REP-OPS-001…005, 062;
// REP-ALL-004, 005, 007, 008, 021, 022, 029, 030).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

List<String> _tabLabels() => [
  for (final e
      in find
          .descendant(
            of: find.byType(DashPageTabs<String>),
            matching: find.byType(Text),
          )
          .evaluate())
    (e.widget as Text).data ?? '',
];

Finder get _export => inPage(find.byType(DashExportButton));

int _reads(DashHarness h) =>
    [for (final r in opsReads) ...h.server.callsTo(r)].length;

void main() {
  testWidgets('REP-OPS-001 / REP-ALL-005 without orders.read: Restricted '
      '"Operations" with the reports\' words, nothing asked', (tester) async {
    final s = opsServer(persona: Persona.manager);
    authzWithout(s.server, Persona.manager, {Cap.ordersRead});
    final h = await pumpOps(
      tester,
      persona: Persona.manager,
      server: s.server,
      db: s.db,
    );
    expect(find.text(h.t('reports.operations.title')), findsWidgets);
    expect(find.text(h.t('common.restrictedTitle')), findsOneWidget);
    expect(find.text(h.t('reports.noAccess')), findsOneWidget);
    expect(find.byType(DashPageTabs<String>), findsNothing);
    expect(_reads(h), 0);
    await h.shot('operations/restricted');
  });

  testWidgets('REP-OPS-001 Restricted in Arabic, phone', (tester) async {
    final s = opsServer(persona: Persona.manager);
    authzWithout(s.server, Persona.manager, {Cap.ordersRead});
    final h = await pumpOps(
      tester,
      persona: Persona.manager,
      server: s.server,
      db: s.db,
      locale: 'ar',
      size: DashSize.phone,
    );
    expect(find.text('العمليات'), findsWidgets);
    expect(find.text(h.t('reports.noAccess')), findsOneWidget);
    await h.shot('operations/restricted');
  });

  testWidgets('REP-OPS-001 with orders.read only (no reports.read) the page '
      'opens; its Tables read is refused by the server (REP-OPS-006)', (
    tester,
  ) async {
    final s = opsServer(persona: Persona.manager);
    authzWithout(s.server, Persona.manager, {Cap.reportsRead});
    // The server's gate on the metrics layer is `reports.read`.
    s.server.fail(
      'POST',
      metricsRoute,
      MockResponse.denied('reports.read'),
      times: null,
    );
    final h = await pumpOps(
      tester,
      persona: Persona.manager,
      server: s.server,
      db: s.db,
    );
    expect(find.text(h.t('reports.noAccess')), findsNothing);
    expect(opsPage, findsOneWidget);
    expect(h.server.callsTo(metricsRoute, method: 'POST'), hasLength(1));
    expect(pageText(h.t('tablesInsights.loadFailed')), findsOneWidget);
  });

  testWidgets('REP-ALL-030 (divergence SH-10) nothing renders and nothing is '
      'asked while the person\'s rights load; then the page and its reads', (
    tester,
  ) async {
    final s = opsServer();
    final gate = s.server.hold('GET', '/authz/me');
    final h = await pumpOps(tester, server: s.server, db: s.db);
    expect(opsPage, findsOneWidget);
    expect(find.byType(DashPageTabs<String>), findsNothing);
    expect(_reads(h), 0);
    gate.release();
    await h.settle();
    expect(find.byType(DashPageTabs<String>), findsOneWidget);
    expect(h.server.callsTo(metricsRoute, method: 'POST'), hasLength(1));
  });

  testWidgets('REP-ALL-004 the module gate: a Dawam-only org sees "Not part '
      'of this business\'s plan" and nothing is asked', (tester) async {
    final h = await pumpOps(tester, persona: Persona.dawamOnly);
    expect(find.text(h.t('dawam.moduleOffTitle')), findsOneWidget);
    expect(find.text(h.t('dawam.modulePosOff')), findsOneWidget);
    expect(opsPage, findsNothing);
    expect(_reads(h), 0);
  });

  testWidgets('REP-OPS-002 / REP-ALL-008 header: "Operations" and the '
      'period\'s words; a preset change rewords it', (tester) async {
    final h = await pumpOps(tester);
    expect(pageText(h.t('reports.operations.title')), findsOneWidget);
    // The page's subtitle and the Tables sub-heading's (REP-ALL-021).
    expect(pageText('Last 30 days'), findsNWidgets(2));
    await h.container
        .read(scopeProvider.notifier)
        .setPreset(ScopePreset.last7Days);
    await h.settle();
    expect(pageText('Last 7 days'), findsNWidgets(2));
    expect(pageText('Last 30 days'), findsNothing);
  });

  testWidgets('REP-ALL-008 every preset\'s words; "Custom", not the inline '
      '"Custom range"', (tester) async {
    final h = await pumpOps(tester);
    final scope = h.container.read(scopeProvider.notifier);
    for (final (p, words) in [
      (ScopePreset.today, 'Today'),
      (ScopePreset.yesterday, 'Yesterday'),
      (ScopePreset.monthToDate, 'Month to date'),
    ]) {
      await scope.setPreset(p);
      await h.settle();
      expect(pageText(words), findsWidgets, reason: p.wire);
    }
    await scope.setCustomRange(
      '2026-09-01T00:00:00.000Z',
      '2026-09-10T00:00:00.000Z',
    );
    await h.settle();
    expect(pageText('Custom'), findsWidgets);
    expect(pageText('Custom range'), findsNothing);
  });

  testWidgets('REP-ALL-007 a scope change asks again with the new period '
      'and branch', (tester) async {
    final h = await pumpOps(tester);
    final first = h.server.callsTo(metricsRoute, method: 'POST');
    expect(first, hasLength(1));
    await h.container
        .read(scopeProvider.notifier)
        .setPreset(ScopePreset.last7Days);
    await h.settle();
    final calls = h.server.callsTo(metricsRoute, method: 'POST');
    expect(calls, hasLength(2));
    final p0 = (first.first.body! as Map)['period'] as Map;
    final p1 = (calls.last.body! as Map)['period'] as Map;
    expect(p1['from'], isNot(p0['from']));
    expect(p1['to'], p0['to']);
    await h.container.read(scopeProvider.notifier).setBranch(SeedIds.maadi);
    await h.settle();
    final last = h.server.callsTo(metricsRoute, method: 'POST');
    expect(last, hasLength(3));
    expect(last.last.headers['X-Branch-Id'], SeedIds.maadi);
  });

  testWidgets('REP-OPS-003 / REP-ALL-022 the six tabs in the web\'s order, '
      'Tables first; the tab is page state, not the address', (tester) async {
    final h = await pumpOps(tester);
    expect(_tabLabels(), [
      'Tables',
      'Overview',
      'Items',
      'Tellers',
      'Waiters',
      'Branches',
    ]);
    expect(pageText(h.t('tablesInsights.title')), findsWidgets);
    await openTab(h, 'Tellers');
    expect(h.location.path, opsPath);
    expect(h.location.queryParameters, isEmpty);
    expect(pageText(h.t('analytics.revenueByTeller')), findsOneWidget);
    // Opening the address again starts on Tables.
    await h.go('/reports/financial');
    await h.go(opsPath);
    expect(chartCard(h.t('tablesInsights.busiestHours')), findsOneWidget);
  });

  testWidgets('REP-OPS-003 the tab strip in Arabic', (tester) async {
    final h = await pumpOps(tester, locale: 'ar', size: DashSize.phone);
    expect(_tabLabels(), [
      for (final k in [
        'tables',
        'overview',
        'items',
        'tellers',
        'waiters',
        'branches',
      ])
        h.t('reports.operations.tabs.$k'),
    ]);
  });

  testWidgets('REP-OPS-003 a manager sees all six tabs', (tester) async {
    await pumpOps(tester, persona: Persona.manager);
    expect(_tabLabels(), hasLength(6));
  });

  testWidgets('REP-OPS-004 Export only on Items, Tellers, Waiters and '
      'Branches', (tester) async {
    final h = await pumpOps(tester);
    expect(_export, findsNothing);
    for (final (tab, shown) in [
      ('Overview', false),
      ('Items', true),
      ('Tellers', true),
      ('Waiters', true),
      ('Branches', true),
      ('Tables', false),
    ]) {
      await openTab(h, tab);
      expect(_export, shown ? findsOneWidget : findsNothing, reason: tab);
    }
  });

  testWidgets('REP-OPS-005 Export is enabled with a scope; on Branches it is '
      'disabled with no org in scope', (tester) async {
    final h = await pumpOps(tester);
    await openTab(h, 'Items');
    DashButton button() => tester.widget<DashButton>(
      find.descendant(of: _export, matching: find.byType(DashButton)),
    );
    expect(button().onPressed, isNotNull);
    await openTab(h, 'Branches');
    expect(button().onPressed, isNotNull);
  });

  testWidgets('REP-OPS-005 a platform admin with no org picked: Branches '
      'asks nothing and its Export is disabled', (tester) async {
    final h = await pumpOps(tester, persona: Persona.platform);
    expect(h.container.read(orgIdProvider), isNull);
    await openTab(h, 'Branches');
    final button = tester.widget<DashButton>(
      find.descendant(of: _export, matching: find.byType(DashButton)),
    );
    expect(button.onPressed, isNull);
    expect(h.server.callsTo(comparisonRoute), isEmpty);
    expect(pageText(h.t('analytics.noData')), findsWidgets);
  });

  testWidgets('REP-OPS-062 back on a tab within 30 s: its figures at once, '
      'nothing asked again', (tester) async {
    final s = opsServer();
    final h = await pumpOps(tester, server: s.server, db: s.db);
    await openTab(h, 'Overview');
    expect(h.server.callsTo(salesRoute), hasLength(1));
    await openTab(h, 'Tables');
    await openTab(h, 'Overview');
    expect(h.server.callsTo(salesRoute), hasLength(1));
    expect(h.server.callsTo(metricsRoute, method: 'POST'), hasLength(1));
  });

  testWidgets('REP-OPS-062 back on a tab after 30 s: the cached figures stay '
      'on screen while they are read again in the background', (tester) async {
    final s = opsServer();
    final h = await pumpOps(tester, server: s.server, db: s.db);
    await openTab(h, 'Tellers');
    expect(h.server.callsTo(tellersRoute), hasLength(1));
    await openTab(h, 'Tables');
    s.db.clock.advance(const Duration(seconds: 31));
    final gate = s.server.hold('GET', tellersRoute);
    await openTab(h, 'Tellers');
    // No skeleton: the old rows are shown while the refetch runs.
    expect(inPage(find.byType(DashSkeleton)), findsNothing);
    expect(
      inPage(find.byKey(const ValueKey('ops-tellers-table'))),
      findsOneWidget,
    );
    expect(h.server.callsTo(tellersRoute), hasLength(2));
    gate.release();
    await h.settle();
  });

  testWidgets('REP-OPS-062 a tab\'s own state (the section filter) is lost '
      'when the tab is left', (tester) async {
    final h = await pumpOps(tester, branchId: SeedIds.heliopolis);
    final select = inPage(find.byKey(const ValueKey('ops-section-filter')));
    expect(select, findsOneWidget);
    await pickOption(h, select, 'Terrace');
    expect(tester.widget<DashSelect<String>>(select).value, 'Terrace');
    await openTab(h, 'Overview');
    await openTab(h, 'Tables');
    expect(
      tester
          .widget<DashSelect<String>>(
            inPage(find.byKey(const ValueKey('ops-section-filter'))),
          )
          .value,
      isNot('Terrace'),
    );
  });

  group('REP-ALL-029 sidebar warm-up', () {
    Future<void> hoverOperations(DashHarness h, WidgetTester tester) async {
      final row = find.descendant(
        of: find.byType(DashSidebar),
        matching: find.text(h.t('nav.reportsOperations')),
      );
      await tester.scrollUntilVisible(
        row,
        200,
        scrollable: find
            .descendant(
              of: find.byType(DashSidebar),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await h.settle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(row));
      await h.settle();
    }

    testWidgets('with a branch picked, pointing at Operations warms the '
        'branch\'s sales with the page\'s exact key; the Overview then asks '
        'nothing', (tester) async {
      final h = await pumpOps(
        tester,
        path: '/reports/legal',
        branchId: SeedIds.zamalek,
      );
      expect(h.server.callsTo(salesRoute), isEmpty);
      await hoverOperations(h, tester);
      final warmed = h.server.callsTo(salesRoute);
      expect(warmed, hasLength(1), reason: 'warmed on hover');
      expect(warmed.single.path, '/reports/branches/${SeedIds.zamalek}/sales');
      expect(warmed.single.query.keys.toSet(), {'from', 'to'});

      final row = find.descendant(
        of: find.byType(DashSidebar),
        matching: find.text(h.t('nav.reportsOperations')),
      );
      await h.tap(row);
      expect(h.location.path, opsPath);
      // The default tab is Tables (not prefetched).
      expect(h.server.callsTo(metricsRoute, method: 'POST'), hasLength(1));
      await openTab(h, 'Overview');
      expect(h.server.callsTo(salesRoute), hasLength(1));
    });

    testWidgets('with items excluded the Overview\'s key differs from the '
        'warmed one, so it reads again (as the web)', (tester) async {
      final h = await pumpOps(
        tester,
        path: '/reports/legal',
        branchId: SeedIds.zamalek,
        prefs: {
          'madar.excluded-line-items.${SeedIds.sabahOrg}':
              '["${MockSeed.menuItemId('latte')}"]',
        },
      );
      await hoverOperations(h, tester);
      expect(h.server.callsTo(salesRoute), hasLength(1));
      await h.go(opsPath);
      await openTab(h, 'Overview');
      final calls = h.server.callsTo(salesRoute);
      expect(calls, hasLength(2));
      expect(calls.last.query['exclude_items'], [MockSeed.menuItemId('latte')]);
    });

    testWidgets('with All branches nothing is warmed', (tester) async {
      final h = await pumpOps(tester, path: '/reports/legal');
      await hoverOperations(h, tester);
      expect(h.server.callsTo(salesRoute), isEmpty);
      expect(h.server.callsTo(metricsRoute, method: 'POST'), isEmpty);
    });
  });
}
