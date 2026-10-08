// The sidebar: what each person sees (capabilities, modules, platform-only,
// set-up-only), which leaf is active, folding past four, parents, the rail.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:madar_dashboard/areas.dart';

import 'support.dart';

Set<String> visibleLeaves(DashHarness h) {
  final v = h.container.read(navLeafVisibleProvider);
  return {
    for (final l in navLeaves())
      if (v(l)) l.to,
  };
}

final Set<String> allLeaves = {for (final l in navLeaves()) l.to};

void main() {
  group('navActive (useIsActive)', () {
    test('home only on home', () {
      expect(navActive('/', '/'), isTrue);
      expect(navActive('/', '/orders'), isFalse);
    });
    test('a page below a leaf keeps it active', () {
      expect(navActive('/menu/items', '/menu/items/abc'), isTrue);
      expect(navActive('/orders', '/orders/'), isTrue);
    });
    test('the most specific leaf wins', () {
      expect(navActive('/reports/staff', '/reports/staff-pool'), isFalse);
      expect(navActive('/reports/staff-pool', '/reports/staff-pool'), isTrue);
      expect(navActive('/settings', '/settings/loyalty'), isFalse);
      expect(navActive('/settings/loyalty', '/settings/loyalty'), isTrue);
      expect(navActive('/settings', '/settings/brand'), isTrue);
    });
  });

  group('who sees what', () {
    testWidgets('owner: everything but platform-only and a finished set-up', (
      tester,
    ) async {
      final h = await pumpShell(tester);
      expect(visibleLeaves(h), allLeaves.difference({'/orgs', '/staff/setup'}));
      expect(text('Organizations'), findsNothing);
      expect(text('Orders'), findsOneWidget);
    });

    testWidgets(
      'platform admin with no shop picked: every module, Organizations',
      (tester) async {
        final h = await pumpShell(tester, persona: Persona.platform);
        expect(visibleLeaves(h), allLeaves.difference({'/staff/setup'}));
      },
    );

    testWidgets('limited: only the pages its capabilities open', (
      tester,
    ) async {
      final h = await pumpShell(tester, persona: Persona.limited);
      expect(visibleLeaves(h), {
        '/',
        '/orders',
        '/tills',
        '/customers',
        '/menu/items',
        '/menu/groups',
        '/menu/combos',
        '/menu/deals',
        '/menu/bases',
        '/menu/packaging',
        '/basira',
        '/reports/operations',
        '/reports/financial',
        '/settings',
        '/branches',
      });
      expect(text('Floor'), findsNothing);
    });

    testWidgets('manager: the registry defaults, nothing platform-only', (
      tester,
    ) async {
      final h = await pumpShell(tester, persona: Persona.manager);
      final v = visibleLeaves(h);
      expect(v, containsAll(['/', '/orders', '/floor', '/tills']));
      expect(v, isNot(contains('/orgs')));
      for (final l in navLeaves()) {
        final caps = l.caps;
        if (caps != null && !l.setup && !l.superAdminOnly) {
          expect(v.contains(l.to), caps.any(Persona.manager.can), reason: l.to);
        }
      }
    });

    testWidgets('Dawam-only org: no POS page, the team pages', (tester) async {
      final h = await pumpShell(tester, persona: Persona.dawamOnly);
      final v = visibleLeaves(h);
      for (final l in navLeaves()) {
        if (l.module == 'pos') expect(v, isNot(contains(l.to)), reason: l.to);
      }
      expect(
        v,
        containsAll(['/staff/employees', '/staff/team', '/reports/staff']),
      );
      expect(v, containsAll(['/reports/legal', '/settings', '/branches']));
      expect(text('Orders'), findsNothing);
    });

    testWidgets('modules not known yet: nothing module-tagged shows', (
      tester,
    ) async {
      final db = MockDb.seeded();
      final server = MockServer(clock: db.clock);
      registerCoreMocks(server, db);
      final gate = server.hold('GET', '/orgs/{id}/modules');
      final h = await DashHarness.pump(
        tester,
        areas: dashboardAreas,
        server: server,
        db: db,
        shotArea: 'shell',
      );
      final v = visibleLeaves(h);
      for (final l in navLeaves()) {
        if (l.module != null) expect(v, isNot(contains(l.to)), reason: l.to);
      }
      gate.release();
      await h.settle();
      expect(visibleLeaves(h), contains('/orders'));
    });

    testWidgets(
      'an unfinished Dawam set-up shows Set-up to whoever sets rules',
      (tester) async {
        final db = MockDb.seeded();
        final server = MockServer(clock: db.clock);
        registerCoreMocks(server, db);
        server.on(
          'GET',
          '/staff/work-shifts',
          (req) => MockResponse.ok(const []),
        );
        final h = await DashHarness.pump(
          tester,
          areas: dashboardAreas,
          server: server,
          db: db,
          shotArea: 'shell',
        );
        expect(visibleLeaves(h), contains('/staff/setup'));
      },
    );
  });

  group('the sidebar', () {
    testWidgets('a group past four folds the rest behind "N more"', (
      tester,
    ) async {
      final h = await pumpShell(tester);
      expect(text('Customers'), findsNothing);
      expect(text('1 more'), findsOneWidget);
      await h.tapText('1 more');
      expect(text('Customers'), findsOneWidget);
      expect(text('Show less'), findsWidgets);
      await h.tapText('Show less');
      expect(text('Customers'), findsNothing);
    });

    testWidgets('the page in a folded entry keeps its group open', (
      tester,
    ) async {
      await pumpShell(tester, path: '/customers');
      expect(text('Customers'), findsWidgets);
    });

    testWidgets('a parent opens to its children; open at first on its page', (
      tester,
    ) async {
      var h = await pumpShell(tester);
      expect(text('Choice groups'), findsNothing);
      await h.tapText('Menu');
      expect(text('Choice groups'), findsOneWidget);
      h = await pumpShell(tester, path: '/menu/groups');
      expect(text('Choice groups'), findsWidgets);
      await h.tapText('Items');
      expect(h.location.path, '/menu/items');
    });

    testWidgets('a leaf navigates', (tester) async {
      final h = await pumpShell(tester);
      await h.tapText('Tills');
      expect(h.location.path, '/tills');
    });

    testWidgets('the rail: folds to icons, remembered, a parent unfolds it', (
      tester,
    ) async {
      final h = await pumpShell(tester);
      await h.tap(labelled('Toggle Sidebar'));
      expect(h.prefs.values[sidebarPrefKey], 'true');
      expect(text('Orders'), findsNothing);
      expect(labelled('Orders'), findsOneWidget);
      await h.shot('frame/rail');
      await h.tap(labelled('Menu'));
      expect(h.container.read(sidebarCollapsedProvider), isFalse);
      expect(text('Choice groups'), findsOneWidget);
    });

    testWidgets('the rail is restored from preferences', (tester) async {
      final h = await pumpShell(tester, prefs: {sidebarPrefKey: 'true'});
      expect(h.container.read(sidebarCollapsedProvider), isTrue);
      expect(text('Orders'), findsNothing);
    });
  });
}
