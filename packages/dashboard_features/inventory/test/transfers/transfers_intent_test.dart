// Prefetch and intent warming on Transfers: the sidebar's Transfers row
// warms the page's first reads (the web's `prefetchRoute('/inventory/
// transfers')`), a direction segment warms its list, New transfer warms the
// source's stock and a From option warms that branch's stock, so each press
// asks the server nothing more.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Future<TestGesture> _mouse(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  return mouse;
}

Future<void> _hover(DashHarness h, TestGesture mouse, Finder f) async {
  await h.tester.ensureVisible(f);
  await h.settle();
  await mouse.moveTo(h.tester.getCenter(f));
  await h.settle();
}

void main() {
  final row = find.descendant(
    of: find.byType(DashSidebar),
    matching: find.text('Transfers'),
  );

  Future<void> hoverSidebar(DashHarness h, TestGesture mouse) async {
    await h.tester.scrollUntilVisible(
      row,
      200,
      scrollable: find
          .descendant(
            of: find.byType(DashSidebar),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await _hover(h, mouse, row);
  }

  int gets(DashHarness h, String route) =>
      h.server.callsTo(route, method: 'GET').length;

  testWidgets('INV-TRF-002 (prefetch) hovering Transfers warms the branch\'s '
      'list (every direction) and the branches; opening it reads nothing '
      'again', (tester) async {
    final h = await pumpTransfers(
      tester,
      path: '/inventory/counts',
      branch: SeedIds.zamalek,
    );
    expect(gets(h, listRoute), 0);
    final branches = gets(h, branchesRoute);
    final mouse = await _mouse(tester);
    await hoverSidebar(h, mouse);
    final warmed = h.server.callsTo(listRoute).single;
    expect(warmed.path, '/inventory/branches/${SeedIds.zamalek}/transfers');
    expect(warmed.query, isEmpty);
    await h.tap(row);
    expect(h.location.path, transfersPath);
    expect(gets(h, listRoute), 1, reason: 'served from the cache');
    expect(gets(h, branchesRoute), branches, reason: 'the shell\'s, kept');
    expect(inTable(find.text('Oat Milk')), findsOneWidget);
  });

  testWidgets('INV-TRF-023 (prefetch, divergence) All branches warms the '
      'all-branches list the page asks for', (tester) async {
    final h = await pumpTransfers(tester, path: '/inventory/counts');
    final mouse = await _mouse(tester);
    await hoverSidebar(h, mouse);
    expect(
      h.server.callsTo(listRoute).single.path,
      '/inventory/branches/$allBranches/transfers',
    );
    await h.tap(row);
    expect(gets(h, listRoute), 1);
    expect(inTable(find.text('Croissant Dough')), findsOneWidget);
  });

  testWidgets('INV-TRF-004 (intent) resting on Incoming warms its list; the '
      'press reads nothing again', (tester) async {
    final h = await pumpTransfers(tester, branch: SeedIds.zamalek);
    final mouse = await _mouse(tester);
    final seg = inPage(find.text('Incoming'));
    await _hover(h, mouse, seg);
    expect(gets(h, listRoute), 2);
    expect(h.server.callsTo(listRoute).last.query['direction'], ['incoming']);
    await h.tap(seg);
    expect(gets(h, listRoute), 2);
    expect(inTable(find.text('Paper Cup 12oz')), findsNothing);
  });

  testWidgets('INV-TRF-003 (intent) resting on New transfer warms the '
      'source\'s stock; the dialog opens on it', (tester) async {
    final h = await pumpTransfers(tester, branch: SeedIds.zamalek);
    expect(h.server.callsTo(stockRoute), isEmpty);
    final mouse = await _mouse(tester);
    final button = inPage(byKey('transfers-new'));
    await _hover(h, mouse, button);
    expect(h.server.callsTo(stockRoute), hasLength(1));
    await h.tap(button);
    expect(dialog, findsOneWidget);
    await pickIngredient(h, 'Vanilla Syrup');
    expect(h.server.callsTo(stockRoute), hasLength(1));
    expect(inDialog(find.text('Zamalek on hand: 600 ml')), findsOneWidget);
  });

  testWidgets('INV-TRF-013 (intent) resting on a From option warms that '
      'branch\'s stock; picking it reads nothing again', (tester) async {
    final h = await pumpTransfers(tester, branch: SeedIds.zamalek);
    await h.tap(inPage(byKey('transfers-new')));
    await h.tap(trigger('transfer-source'));
    final mouse = await _mouse(tester);
    await _hover(h, mouse, option('Maadi').last);
    final maadi = '/inventory/branches/${SeedIds.maadi}/stock';
    expect([for (final c in h.server.callsTo(stockRoute)) c.path], contains(maadi));
    final n = gets(h, stockRoute);
    await h.tap(option('Maadi').last);
    expect(gets(h, stockRoute), n);
  });
}
