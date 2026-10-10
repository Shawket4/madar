// The area-wide rows as the items page meets them (MENU-AREA-001..012):
// the nav and palette, the module gate, the legacy redirects, no route
// guard, no realtime, the confirm dialog; and the route's prefetch.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_menu/src/items/items_page.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Finder sideText(String text) =>
    find.descendant(of: find.byType(DashSidebar), matching: find.text(text));

/// A server whose `/authz/me` grants [caps] to [persona] in the app.
({MockServer server, MockDb db}) serverWithCaps(
  List<String> caps, {
  Persona persona = Persona.limited,
}) {
  final s = itemsServer(persona: persona);
  s.server.on(
    'GET',
    '/authz/me',
    (req) => MockResponse.ok({
      'user_id': persona.userId,
      'capabilities': caps,
      'ask_manager': <String>[],
      'limits': <String, Object>{},
      'owner': false,
      'platform': false,
      'role_kinds': persona.roleKinds,
      'epoch': 1,
      'spec_version': 2,
    }),
  );
  return s;
}

void main() {
  testWidgets('MENU-AREA-001 / 003 Catalog ▸ Menu with its leaves in order; '
      'the palette lists them', (tester) async {
    final h = await pumpItems(tester);
    final order = [
      'Catalog',
      'Menu',
      'Items',
      'Choice groups',
      'Pricing & Availability',
      'Recipe bases',
      'Packaging rules',
    ];
    final ys = [for (final t in order) tester.getTopLeft(sideText(t)).dy];
    expect(ys, orderedEquals([...ys]..sort()), reason: '$order');
    final items = dashNav
        .expand((g) => g.entries)
        .whereType<NavParent>()
        .expand((p) => p.children)
        .firstWhere((l) => l.to == itemsPath);
    expect(items.caps, ['menu.items.read']);
    expect(items.module, 'pos');

    await h.tap(
      find.descendant(
        of: find.byType(DashHeader),
        matching: find.text('Search'),
      ),
    );
    final palette = find.byType(DashCommandPalette);
    for (final (q, t) in [
      ('items', 'Items'),
      ('pricing', 'Pricing & Availability'),
      ('packaging', 'Packaging rules'),
    ]) {
      await h.enterText(palette, q);
      expect(
        find.descendant(of: palette, matching: find.text(t)),
        findsWidgets,
        reason: t,
      );
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
  });

  testWidgets('MENU-AREA-002 Pricing needs menu.items.edit; the others '
      'menu.items.read', (tester) async {
    await pumpItems(
      tester,
      persona: Persona.limited,
      seeded: serverWithCaps(['menu.items.read', 'orders.read']),
    );
    expect(sideText('Items'), findsOneWidget);
    expect(sideText('Choice groups'), findsOneWidget);
    expect(sideText('Pricing & Availability'), findsNothing);
  });

  testWidgets('MENU-AREA-002 without menu.items.read: no Menu leaves', (
    tester,
  ) async {
    await pumpItems(
      tester,
      persona: Persona.limited,
      seeded: serverWithCaps(['orders.read']),
    );
    expect(sideText('Items'), findsNothing);
    expect(sideText('Recipe bases'), findsNothing);
  });

  testWidgets('MENU-AREA-004 POS switched off: the plan words, nothing read', (
    tester,
  ) async {
    final s = itemsServer();
    s.db['orgs'].find(sabahOrg)!['modules'] = ['dawam'];
    final h = await pumpItems(tester, seeded: s);
    expect(find.text("Not part of this business's plan"), findsOneWidget);
    expect(
      find.text(
        'Madar POS is switched off for this business. Ask Madar to '
        'switch it on.',
      ),
      findsOneWidget,
    );
    expect(find.byType(MenuItemsPage), findsNothing);
    expect(sideText('Items'), findsNothing);
    expect(callsOf(h, 'GET', catalogPath), isEmpty);
  });

  testWidgets('MENU-AREA-004 the modules read failing: words and Retry', (
    tester,
  ) async {
    final s = itemsServer();
    s.server.fail(
      'GET',
      '/orgs/{id}/modules',
      MockResponse.error(500, 'Database error: timed out'),
    );
    final h = await pumpItems(tester, seeded: s);
    expect(
      find.textContaining("Couldn't check what this business has switched on"),
      findsOneWidget,
    );
    expect(callsOf(h, 'GET', catalogPath), isEmpty);
    await h.tapText('Retry');
    expect(find.byType(MenuItemsPage), findsOneWidget);
  });

  testWidgets('MENU-AREA-005 / 006 / 007 the retired paths', (tester) async {
    final h = await pumpItems(tester);
    await h.go('/menu');
    expect(h.location.path, itemsPath);
    await h.go('/menu/recipes?item=${item('latte')}');
    expect(h.location.toString(), itemsPath, reason: 'search dropped');
    h.allowUnmatched = true;
    await h.go('/menu/overrides');
    expect(h.location.path, '/menu/pricing');
  });

  testWidgets('MENU-AREA-008 no route guard: a read-only person sees the page '
      'and the server answers', (tester) async {
    final h = await pumpItems(tester, persona: Persona.limited);
    expect(find.byType(MenuItemsPage), findsOneWidget);
    expect(inPage(find.text('Cortado')), findsOneWidget);
    expect(
      inPage(find.text('New item')),
      findsOneWidget,
      reason: 'not hidden: the server refuses the write',
    );
    await openCardMenu(h, 'Cortado');
    await pickMenu(h, 'Delete');
    await h.tap(
      find.descendant(
        of: find.byType(DashConfirmDialog),
        matching: find.text('Delete'),
      ),
    );
    await h.expectToast(
      h.refusalWords(MockResponse.denied('menu.items.delete')),
    );
  });

  testWidgets('MENU-AREA-009 no realtime: a branch event refetches nothing '
      'here', (tester) async {
    final h = await pumpItems(tester, branchId: SeedIds.zamalek);
    final before = callsOf(h, 'GET', catalogPath).length;
    h.realtime.current!.emit('order.created', data: '{}');
    await h.settle();
    expect(callsOf(h, 'GET', catalogPath), hasLength(before));
  });

  testWidgets('MENU-AREA-011 the confirm: destructive; outside click '
      'cancels', (tester) async {
    final h = await pumpItems(tester);
    await openCardMenu(h, 'Cortado');
    await pickMenu(h, 'Delete');
    final dialog = tester.widget<DashConfirmDialog>(
      find.byType(DashConfirmDialog),
    );
    expect(dialog.destructive, isTrue);
    expect(
      find.descendant(
        of: find.byType(DashConfirmDialog),
        matching: find.text('Cancel'),
      ),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(4, 4));
    await h.settle();
    expect(find.byType(DashConfirmDialog), findsNothing);
    expect(callsOf(h, 'DELETE', '/menu-items/{id}'), isEmpty);
  });

  testWidgets('MENU-AREA-011 Esc closes the confirm; nothing is deleted', (
    tester,
  ) async {
    final h = await pumpItems(tester);
    await openCardMenu(h, 'Cortado');
    await pickMenu(h, 'Delete');
    expect(find.byType(DashConfirmDialog), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
    expect(find.byType(DashConfirmDialog), findsNothing);
    expect(callsOf(h, 'DELETE', '/menu-items/{id}'), isEmpty);
  });

  testWidgets('MENU-AREA-012 toggles need ONE branch in scope', (tester) async {
    final h = await pumpItems(tester);
    expect(inPage(find.text('Available at this branch')), findsNothing);
    await h.container.read(scopeProvider.notifier).setBranch(SeedIds.maadi);
    await h.settle();
    expect(inPage(find.text('Available at this branch')), findsWidgets);
  });

  testWidgets('prefetch: pointing at Items warms its first page, categories '
      'and add-ons; opening it asks nothing more', (tester) async {
    final h = await pumpItems(tester, path: '/menu/bases');
    List<MockCall> reads() => [
      ...callsOf(h, 'GET', catalogPath),
      ...callsOf(h, 'GET', '/categories'),
      ...callsOf(h, 'GET', '/addon-items'),
    ];
    expect(callsOf(h, 'GET', catalogPath), isEmpty);
    final before = reads().length;
    final row = sideText('Items');
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(row));
    await h.settle();
    final warmed = reads().length;
    expect(warmed, greaterThan(before), reason: 'warmed on hover');
    expect(callsOf(h, 'GET', '/addon-items'), isNotEmpty);
    expect(callsOf(h, 'GET', catalogPath).last.query, {
      'org_id': [sabahOrg],
      'page': ['1'],
      'per_page': ['24'],
    });
    await h.tap(row);
    expect(h.location.path, itemsPath);
    expect(reads().length, warmed, reason: 'served from the cache');
  });
}
