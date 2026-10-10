// The phone frame: the app bar, the bottom bar (Home, Orders, Reports, More,
// as the person's permissions and modules allow) and the drawer.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/shell.dart'
    show DashBottomBar, DashCommandPalette, sidebarCollapsedProvider;
import 'package:flutter/services.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:madar_dashboard/areas.dart';

import 'support.dart';

void main() {
  testWidgets(
    'ADM-APP-037: owner: Home, Orders, Reports, More; each goes where it '
    'says',
    (tester) async {
      final h = await pumpShell(tester, size: DashSize.phone);
      for (final l in ['Home', 'Orders', 'Reports', 'More']) {
        expect(labelled(l), findsWidgets, reason: l);
      }
      await h.tap(labelled('Orders').last);
      expect(h.location.path, '/orders');
      await h.tap(labelled('Reports').last);
      expect(h.location.path, '/reports/operations');
      await h.tap(labelled('Home').last);
      expect(h.location.path, '/');
    },
  );

  testWidgets(
    'ADM-APP-028 ADM-APP-037 ADM-APP-038: More opens the whole sidebar as '
    'a drawer; a pick closes it',
    (tester) async {
      final h = await pumpShell(tester, size: DashSize.phone);
      expect(text('Floor'), findsNothing);
      await h.tap(labelled('More').last);
      await h.settle(rounds: 12);
      expect(text('Floor'), findsOneWidget);
      expect(text('Privacy Policy'), findsOneWidget);
      // The foot: the shop is on its own branding (the wide frame's footer).
      expect(text('Powered by Madar'), findsOneWidget);
      // Named for screen readers as the web's mobile sidebar sheet.
      expect(labelled('Sidebar'), findsOneWidget);
      await h.shot('frame/drawer');
      await h.tapText('Floor');
      await h.settle(rounds: 12);
      expect(h.location.path, '/floor');
      final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold).first);
      expect(scaffold.isDrawerOpen, isFalse);
    },
  );

  testWidgets('Dawam-only: no Orders; Reports opens the first report it sees', (
    tester,
  ) async {
    final h = await pumpShell(
      tester,
      size: DashSize.phone,
      persona: Persona.dawamOnly,
    );
    expect(labelled('Orders'), findsNothing);
    await h.tap(labelled('Reports').last);
    // Sidebar order: Legal (no module) comes before Staff (Dawam).
    expect(h.location.path, '/reports/legal');
  });

  testWidgets('a person with no report sees no Reports shortcut', (
    tester,
  ) async {
    final db = MockDb.seeded();
    final server = MockServer(persona: Persona.limited, clock: db.clock);
    registerAppMocks(server, db);
    server.on(
      'GET',
      '/authz/me',
      (req) => MockResponse.ok({
        'user_id': Persona.limited.userId,
        'capabilities': ['branches.read', 'customers.view'],
        'ask_manager': <String>[],
        'limits': <String, Object>{},
        'owner': false,
        'platform': false,
        'role_kinds': ['teller'],
        'epoch': 1,
        'spec_version': 2,
      }),
    );
    await DashHarness.pump(
      tester,
      areas: dashboardAreas,
      server: server,
      db: db,
      persona: Persona.limited,
      size: DashSize.phone,
      shotArea: 'shell',
    );
    expect(labelled('Reports'), findsNothing);
    // In the bar (the home page has an Orders figure of its own).
    expect(
      find.descendant(
        of: find.byType(DashBottomBar),
        matching: labelled('Orders'),
      ),
      findsNothing,
    );
    expect(labelled('Home'), findsWidgets);
    expect(labelled('More'), findsWidgets);
  });

  testWidgets('ADM-APP-050 ADM-APP-069: the app bar: search opens the palette, '
      'filters the scope', (tester) async {
    final h = await pumpShell(tester, size: DashSize.phone);
    await h.tap(labelled('Search').first);
    expect(find.byType(DashCommandPalette), findsOneWidget);
    await h.shot('frame/palette');
    await h.tap(labelled('Close').last);
    await h.tap(labelled('Filters'));
    expect(text('All branches'), findsOneWidget);
    expect(text('Last 30 days'), findsOneWidget);
    await h.shot('frame/filters');
  });

  testWidgets('ADM-APP-027: Ctrl/Cmd+B opens and closes the drawer', (
    tester,
  ) async {
    final h = await pumpShell(tester, size: DashSize.phone);
    Future<void> ctrlB() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await h.settle(rounds: 12);
    }

    final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold).first);
    await ctrlB();
    expect(scaffold.isDrawerOpen, isTrue);
    await ctrlB();
    expect(scaffold.isDrawerOpen, isFalse);
    // The wide rail's preference is not the phone's to change.
    expect(h.container.read(sidebarCollapsedProvider), isFalse);
  });
}
