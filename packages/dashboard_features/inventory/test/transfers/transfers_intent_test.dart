// Prefetch and intent warming on Transfers: the sidebar row warms what the
// web's `prefetchRoute('/inventory/transfers')` warms (the branches, and the
// list only with a location picked); a status tab, a direction segment, a
// row, New transfer, a From option, Replenish and a replenish branch each
// warm the read their press makes, so the press asks nothing more.
import 'package:dashboard_api/mock.dart' show SeedIds;
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

int _gets(DashHarness h, String route) =>
    h.server.callsTo(route, method: 'GET').length;

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

  testWidgets('INV-TRF-002 (prefetch) with a location picked, hovering '
      'Transfers warms its list (no filters); opening reads nothing again', (
    tester,
  ) async {
    final h = await pumpTransfers(
      tester,
      path: '/inventory/counts',
      branch: SeedIds.zamalek,
    );
    expect(_gets(h, listRoute), 0);
    final branches = _gets(h, branchesRoute);
    final mouse = await _mouse(tester);
    await hoverSidebar(h, mouse);
    final warmed = h.server.callsTo(listRoute).single;
    expect(warmed.path, '/inventory/branches/${SeedIds.zamalek}/transfers');
    expect(warmed.query, isEmpty);
    await h.tap(row);
    expect(h.location.path, transfersPath);
    expect(_gets(h, listRoute), 1, reason: 'served from the cache');
    expect(_gets(h, branchesRoute), branches, reason: 'the shell\'s, kept');
    expect(inTable(find.text('TR-6')), findsOneWidget);
  });

  testWidgets('INV-TRF-002 (prefetch) All branches warms no list, as the '
      'web; the page reads it once', (tester) async {
    final h = await pumpTransfers(tester, path: '/inventory/counts');
    final mouse = await _mouse(tester);
    await hoverSidebar(h, mouse);
    expect(_gets(h, listRoute), 0);
    await h.tap(row);
    expect(_gets(h, listRoute), 1);
    expect(
      h.server.callsTo(listRoute).single.path,
      '/inventory/branches/$allBranches/transfers',
    );
  });

  testWidgets('INV-TRF-005 (intent) resting on a status tab warms its list; '
      'the press reads nothing again', (tester) async {
    final h = await pumpTransfers(tester, branch: SeedIds.zamalek);
    final mouse = await _mouse(tester);
    final tab = find.descendant(
      of: inPage(byKey('transfers-status')),
      matching: find.text('Requested'),
    );
    await _hover(h, mouse, tab);
    expect(_gets(h, listRoute), 2);
    expect(h.server.callsTo(listRoute).last.query, {
      'status': ['requested'],
    });
    await h.tap(tab);
    expect(_gets(h, listRoute), 2);
    expect(inTable(find.text('TR-5')), findsNothing);
  });

  testWidgets('INV-TRF-011 (intent) resting on Differences warms the '
      'report', (tester) async {
    final h = await pumpTransfers(tester, branch: SeedIds.zamalek);
    final mouse = await _mouse(tester);
    final tab = inPage(find.text('Differences'));
    await _hover(h, mouse, tab);
    expect(_gets(h, diffsRoute), 1);
    await h.tap(tab);
    expect(_gets(h, diffsRoute), 1);
  });

  testWidgets('INV-TRF-006 (intent) resting on Incoming warms its list; the '
      'press reads nothing again', (tester) async {
    final h = await pumpTransfers(tester, branch: SeedIds.zamalek);
    final mouse = await _mouse(tester);
    final seg = inPage(find.text('Incoming'));
    await _hover(h, mouse, seg);
    expect(_gets(h, listRoute), 2);
    expect(h.server.callsTo(listRoute).last.query['direction'], ['incoming']);
    await h.tap(seg);
    expect(_gets(h, listRoute), 2);
    expect(inTable(find.text('TR-3')), findsNothing);
  });

  testWidgets('INV-TRF-009 (intent) resting on a row warms what each side '
      'holds; the drawer opens on it', (tester) async {
    final h = await pumpTransfers(tester, branch: SeedIds.zamalek);
    final mouse = await _mouse(tester);
    List<String?> at() => [
      for (final c in h.server.callsTo(authzRoute))
        if (c.query['branch_id'] != null) c.query['branch_id']!.single,
    ];
    final before = at().length;
    await _hover(h, mouse, inTable(find.text('TR-6')));
    // Zamalek's is the page's own (here); Maadi's is new.
    expect(at().skip(before), [SeedIds.maadi]);
    expect(at(), contains(SeedIds.zamalek));
    final warmed = at().length;
    await h.tap(inTable(find.text('TR-6')));
    expect(drawer, findsOneWidget);
    expect(at(), hasLength(warmed));
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
    expect(h.server.callsTo(stockRoute), hasLength(1));
  });

  testWidgets('INV-TRF-027 (intent) resting on a From option warms that '
      'location\'s stock; picking it reads nothing again', (tester) async {
    final h = await pumpTransfers(tester);
    await h.tap(inPage(byKey('transfers-new')));
    await h.tap(triggerIn(dialog, 'transfer-source'));
    final mouse = await _mouse(tester);
    await _hover(h, mouse, option('Maadi').last);
    final maadi = '/inventory/branches/${SeedIds.maadi}/stock';
    expect([
      for (final c in h.server.callsTo(stockRoute)) c.path,
    ], contains(maadi));
    final n = _gets(h, stockRoute);
    await h.tap(option('Maadi').last);
    expect(_gets(h, stockRoute), n);
  });

  testWidgets('INV-TRF-039 (intent) resting on a branch in the replenish '
      'dialog warms its rows', (tester) async {
    final s = transfersServer();
    withWarehouse(s.db);
    final h = await pumpTransfers(
      tester,
      server: s.server,
      db: s.db,
      branch: centralStore,
    );
    await h.tap(inPage(byKey('transfers-replenish')));
    await h.tap(triggerIn(replenishDialog, 'replenish-branch'));
    final mouse = await _mouse(tester);
    await _hover(h, mouse, option('Zamalek').last);
    expect(_gets(h, replenishRoute), 1);
    await h.tap(option('Zamalek').last);
    expect(_gets(h, replenishRoute), 1);
    expect(inReplenish(find.text('Oat Milk')), findsOneWidget);
  });

  testWidgets('INV-TRF-004 (intent) with one selling branch, resting on '
      'Replenish warms its rows', (tester) async {
    final s = transfersServer();
    withWarehouse(s.db);
    for (final id in [SeedIds.heliopolis, SeedIds.maadi, SeedIds.newCairo]) {
      s.db['branches'].get(id)['is_active'] = false;
    }
    final h = await pumpTransfers(
      tester,
      server: s.server,
      db: s.db,
      branch: centralStore,
    );
    final mouse = await _mouse(tester);
    await _hover(h, mouse, inPage(byKey('transfers-replenish')));
    expect(_gets(h, replenishRoute), 1);
    await h.tap(inPage(byKey('transfers-replenish')));
    expect(_gets(h, replenishRoute), 1);
  });

  testWidgets('INV-TRF-020 / INV-TRF-035 (intent) resting on Edit of a draft '
      'warms the source\'s stock; the dialog opens on it', (tester) async {
    final h = await pumpTransfers(tester);
    await openRow(h, 'TR-7');
    final maadi = '/inventory/branches/${SeedIds.maadi}/stock';
    final n = _gets(h, stockRoute);
    final mouse = await _mouse(tester);
    await _hover(h, mouse, inDrawer(byKey('transfer-step-edit')));
    expect(_gets(h, stockRoute), n + 1);
    expect(h.server.callsTo(stockRoute).last.path, maadi);
    await h.tap(inDrawer(byKey('transfer-step-edit')));
    expect(dialog, findsOneWidget);
    expect(_gets(h, stockRoute), n + 1);
  });

  testWidgets('INV-TRF-020 / INV-TRF-035 (intent) resting on Edit of a '
      'request warms the catalogue, not stock', (tester) async {
    final h = await pumpTransfers(tester);
    await openRow(h, 'TR-6');
    final stock = _gets(h, stockRoute), catalog = _gets(h, catalogRoute);
    final mouse = await _mouse(tester);
    await _hover(h, mouse, inDrawer(byKey('transfer-step-edit')));
    expect(_gets(h, catalogRoute), catalog + 1);
    expect(_gets(h, stockRoute), stock);
    await h.tap(inDrawer(byKey('transfer-step-edit')));
    expect(dialog, findsOneWidget);
    expect(_gets(h, catalogRoute), catalog + 1);
  });

  testWidgets('INV-TRF-020 / INV-TRF-036 (intent) resting on Accept warms '
      'the source\'s stock; the dialog opens on it', (tester) async {
    final h = await pumpTransfers(tester);
    await openRow(h, 'TR-6');
    final n = _gets(h, stockRoute);
    final mouse = await _mouse(tester);
    await _hover(h, mouse, inDrawer(byKey('transfer-step-accept')));
    expect(_gets(h, stockRoute), n + 1);
    expect(
      h.server.callsTo(stockRoute).last.path,
      '/inventory/branches/${SeedIds.maadi}/stock',
    );
    await h.tap(inDrawer(byKey('transfer-step-accept')));
    expect(dialog, findsOneWidget);
    expect(_gets(h, stockRoute), n + 1);
  });

  testWidgets('INV-TRF-026 (intent) resting on Request stock warms the '
      'catalogue; resting on Send stock warms the new source\'s stock', (
    tester,
  ) async {
    final h = await pumpTransfers(tester, branch: SeedIds.zamalek);
    await h.tap(inPage(byKey('transfers-new')));
    await pick(h, 'transfer-destination', 'Maadi');
    final mouse = await _mouse(tester);
    await _hover(h, mouse, inDialog(find.text('Request stock')));
    expect(_gets(h, catalogRoute), 1);
    await h.tap(inDialog(find.text('Request stock')).last);
    expect(_gets(h, catalogRoute), 1);
    // Asking for Heliopolis: sending back makes it the source.
    await pick(h, 'transfer-destination', 'Heliopolis');
    final n = _gets(h, stockRoute);
    await _hover(h, mouse, inDialog(find.text('Send stock')));
    expect(_gets(h, stockRoute), n + 1);
    expect(
      h.server.callsTo(stockRoute).last.path,
      '/inventory/branches/${SeedIds.heliopolis}/stock',
    );
    await h.tap(inDialog(find.text('Send stock')));
    expect(_gets(h, stockRoute), n + 1);
  });

  testWidgets('INV-TRF-040 (intent) resting on Review transfer warms the '
      'store\'s stock; the transfer dialog opens on it', (tester) async {
    final s = transfersServer();
    withWarehouse(s.db);
    final h = await pumpTransfers(
      tester,
      server: s.server,
      db: s.db,
      branch: centralStore,
    );
    await h.tap(inPage(byKey('transfers-replenish')));
    await pick(h, 'replenish-branch', 'Zamalek', scope: replenishDialog);
    final n = _gets(h, stockRoute);
    final mouse = await _mouse(tester);
    await _hover(h, mouse, inReplenish(byKey('replenish-review')));
    expect(_gets(h, stockRoute), n + 1);
    expect(
      h.server.callsTo(stockRoute).last.path,
      '/inventory/branches/$centralStore/stock',
    );
    await h.tap(inReplenish(byKey('replenish-review')));
    expect(dialog, findsOneWidget);
    expect(_gets(h, stockRoute), n + 1);
  });
}
