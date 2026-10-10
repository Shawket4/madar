// The sidebar: what each person sees (capabilities, modules, platform-only,
// set-up-only), which leaf is active, folding past four, parents, the rail.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
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
    test('ADM-APP-036: home only on home', () {
      expect(navActive('/', '/'), isTrue);
      expect(navActive('/', '/orders'), isFalse);
    });
    test('ADM-APP-036: a page below a leaf keeps it active', () {
      expect(navActive('/menu/items', '/menu/items/abc'), isTrue);
      expect(navActive('/orders', '/orders/'), isTrue);
    });
    test('ADM-APP-036: the most specific leaf wins', () {
      expect(navActive('/reports/staff', '/reports/staff-pool'), isFalse);
      expect(navActive('/reports/staff-pool', '/reports/staff-pool'), isTrue);
      expect(navActive('/settings', '/settings/loyalty'), isFalse);
      expect(navActive('/settings/loyalty', '/settings/loyalty'), isTrue);
      expect(navActive('/settings', '/settings/brand'), isTrue);
    });
  });

  group('who sees what', () {
    testWidgets('ADM-APP-031 ADM-APP-032: owner: everything but '
        'platform-only and a finished set-up', (tester) async {
      final h = await pumpShell(tester);
      expect(visibleLeaves(h), allLeaves.difference({'/orgs', '/staff/setup'}));
      expect(navText('Organizations'), findsNothing);
      expect(navText('Orders'), findsOneWidget);
    });

    testWidgets(
      'ADM-APP-032: platform admin with no shop picked: every module, '
      'Organizations',
      (tester) async {
        final h = await pumpShell(tester, persona: Persona.platform);
        expect(visibleLeaves(h), allLeaves.difference({'/staff/setup'}));
      },
    );

    testWidgets('ADM-APP-031: limited: only the pages its capabilities open', (
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

    testWidgets('ADM-APP-031: manager: the registry defaults, nothing '
        'platform-only', (tester) async {
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

    testWidgets('ADM-APP-083: Dawam-only org: no POS page, the team pages', (
      tester,
    ) async {
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

    testWidgets('ADM-APP-083: modules not known yet: nothing module-tagged '
        'shows', (tester) async {
      final db = MockDb.seeded();
      final server = MockServer(clock: db.clock);
      registerAppMocks(server, db);
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
      'ADM-APP-031: an unfinished Dawam set-up shows Set-up to whoever sets '
      'rules',
      (tester) async {
        final db = MockDb.seeded();
        final server = MockServer(clock: db.clock);
        registerAppMocks(server, db);
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
    testWidgets('ADM-APP-034: a group past four folds the rest behind "N '
        'more"', (tester) async {
      final h = await pumpShell(tester);
      expect(text('Customers'), findsNothing);
      expect(text('1 more'), findsOneWidget);
      await h.tapText('1 more');
      expect(text('Customers'), findsOneWidget);
      expect(text('Show less'), findsWidgets);
      await h.tapText('Show less');
      expect(text('Customers'), findsNothing);
    });

    testWidgets('ADM-APP-034: the page in a folded entry keeps its group '
        'open', (tester) async {
      await pumpShell(tester, path: '/customers');
      expect(text('Customers'), findsWidgets);
    });

    testWidgets('ADM-APP-035: a parent opens to its children; open at '
        'first on its page', (tester) async {
      var h = await pumpShell(tester);
      expect(text('Choice groups'), findsNothing);
      await h.tapText('Menu');
      expect(text('Choice groups'), findsOneWidget);
      h = await pumpShell(tester, path: '/menu/groups');
      expect(text('Choice groups'), findsWidgets);
      await h.tapText('Items');
      expect(h.location.path, '/menu/items');
    });

    testWidgets('ADM-APP-037: a leaf navigates', (tester) async {
      final h = await pumpShell(tester);
      await h.tapText('Tills');
      expect(h.location.path, '/tills');
    });

    testWidgets('ADM-APP-027 ADM-APP-038: the rail: folds to icons, '
        'remembered, a parent unfolds it', (tester) async {
      final h = await pumpShell(tester);
      await h.tap(labelled('Toggle Sidebar'));
      expect(h.prefs.values[sidebarPrefKey], 'true');
      expect(navText('Orders'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(DashSidebar),
          matching: labelled('Orders'),
        ),
        findsOneWidget,
      );
      // On the rail the fold's row says what it does (its words are hidden).
      expect(find.byTooltip('Show more'), findsWidgets);
      await h.shot('frame/rail');
      await h.tap(labelled('Menu'));
      expect(h.container.read(sidebarCollapsedProvider), isFalse);
      expect(text('Choice groups'), findsOneWidget);
    });

    testWidgets('ADM-APP-036: a deep link brings its row into sight', (
      tester,
    ) async {
      ScrollPosition sidebarScroll() => tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(DashSidebar),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      await pumpShell(tester, path: '/settings/staff-pool');
      final box = tester.getRect(find.byType(DashSidebar));
      expect(sidebarScroll().pixels, greaterThan(0));
      final row = tester.getRect(navText('Staff drinks').first);
      expect(row.bottom, lessThanOrEqualTo(box.bottom));
      expect(row.top, greaterThanOrEqualTo(box.top));
    });

    testWidgets('ADM-APP-037: a row in view stays put when it is opened', (
      tester,
    ) async {
      ScrollPosition sidebarScroll() => tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(DashSidebar),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      final h = await pumpShell(tester);
      expect(sidebarScroll().pixels, 0);
      // A leaf drawn whole in the lower half: centring it would scroll.
      final box = tester.getRect(find.byType(DashSidebar));
      final leaf = navLeaves().firstWhere((l) {
        final f = navText(l.fallback);
        if (f.evaluate().length != 1) return false;
        final r = tester.getRect(f);
        return r.center.dy > box.center.dy && r.bottom < box.bottom;
      });
      // A real tap (the harness's tap scrolls its target to the top first).
      await tester.tap(navText(leaf.fallback));
      await h.settle();
      expect(h.location.path, leaf.to);
      expect(sidebarScroll().pixels, 0);
    });

    testWidgets('ADM-APP-027: the rail is restored from preferences', (
      tester,
    ) async {
      final h = await pumpShell(tester, prefs: {sidebarPrefKey: 'true'});
      expect(h.container.read(sidebarCollapsedProvider), isTrue);
      expect(navText('Orders'), findsNothing);
    });

    testWidgets('ADM-APP-027: Ctrl/Cmd+B and the thin edge fold and unfold '
        'it, remembered', (tester) async {
      final h = await pumpShell(tester);
      Future<void> ctrlB() async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await h.settle();
      }

      await ctrlB();
      expect(h.container.read(sidebarCollapsedProvider), isTrue);
      expect(h.prefs.values[sidebarPrefKey], 'true');
      await ctrlB();
      expect(h.container.read(sidebarCollapsedProvider), isFalse);
      expect(h.prefs.values[sidebarPrefKey], 'false');
      // The edge along the sidebar (the header's button comes first).
      await h.tap(labelled('Toggle Sidebar').last);
      expect(h.container.read(sidebarCollapsedProvider), isTrue);
      await h.tap(labelled('Toggle Sidebar').last);
      expect(h.container.read(sidebarCollapsedProvider), isFalse);
    });

    testWidgets('ADM-APP-033: a shop on its own branding wears its logo', (
      tester,
    ) async {
      const logo = 'https://cdn.madar.test/sabah-logo.png';
      final h = await pumpShell(tester);
      h.db!['orgs'].update(SeedIds.sabahOrg, {'logo_url': logo});
      h.container.invalidate(publicBrandProvider);
      await h.settle();
      final image = find.descendant(
        of: find.byType(DashSidebar),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Image &&
              w.image is NetworkImage &&
              (w.image as NetworkImage).url == logo,
        ),
      );
      expect(image, findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DashSidebar),
          matching: labelled('Sabah Coffee'),
        ),
        findsOneWidget,
      );
      // Off the branding tier: Madar's own mark.
      h.db!['orgs'].update(SeedIds.sabahOrg, {'custom_branding': false});
      h.container.invalidate(publicBrandProvider);
      await h.settle();
      expect(image, findsNothing);
    });
  });
}
