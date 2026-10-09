// The Transfers page (INV-TRF-001…012, INV-TRF-041, INV-ALL-027/028), driven
// through the real shell on the seeded mock server. Zamalek's transfers:
// TR-6 (requested), TR-5 (received), TR-8 (cancelled), TR-3 and TR-2
// (received).
import 'dart:async';

import 'package:dashboard_api/dashboard_api.dart'
    show CreateTransferRequest, DashboardApi, StockTransfer, TransferLineInput;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:dashboard_inventory/src/transfers/transfers_page.dart'
    show TransferRoute;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _zamalek = ['TR-6', 'TR-5', 'TR-8', 'TR-3', 'TR-2'];

/// The references the table shows, top to bottom.
List<String> _refs(WidgetTester tester) {
  final found = <(double, String)>[];
  for (final e in inTable(
    find.textContaining(RegExp(r'^TR-\d+$')),
  ).evaluate()) {
    final w = e.widget as Text;
    found.add((tester.getTopLeft(find.byWidget(w)).dy, w.data!));
  }
  found.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final f in found) f.$2];
}

void main() {
  testWidgets('INV-TRF-001 header: Transfers, Export then New transfer; the '
      'status tabs and the direction control below', (tester) async {
    final h = await pumpTransfers(tester, branch: SeedIds.zamalek);
    expect(inPage(find.text('Transfers')), findsWidgets);
    expect(inPage(byKey('transfers-export')), findsOneWidget);
    expect(inPage(byKey('transfers-new')), findsOneWidget);
    expect(inPage(find.text('New transfer')), findsOneWidget);
    expect(inPage(byKey('transfers-replenish')), findsNothing);
    final exportX = tester.getCenter(inPage(byKey('transfers-export'))).dx;
    final newX = tester.getCenter(inPage(byKey('transfers-new'))).dx;
    expect(exportX, lessThan(newX));
    for (final w in [
      'All transfers',
      'Requested',
      'Draft',
      'In transit',
      'Received',
      'Cancelled',
      'Differences',
      'Both ways',
      'Incoming',
      'Outgoing',
    ]) {
      expect(
        find
                .descendant(
                  of: find.byType(DashSegmentedControl<String>).first,
                  matching: find.text(w),
                )
                .evaluate()
                .isNotEmpty ||
            find
                .descendant(
                  of: find.byType(DashSegmentedControl<String?>),
                  matching: find.text(w),
                )
                .evaluate()
                .isNotEmpty,
        isTrue,
        reason: w,
      );
    }
    expect(h.location.path, transfersPath);
  });

  testWidgets('INV-TRF-002 reads: the org\'s locations (with create), the '
      'scoped list with no direction or status, newest first', (tester) async {
    final h = await pumpTransfers(tester, branch: SeedIds.zamalek);
    final list = h.server.callsTo(listRoute).single;
    expect(list.path, '/inventory/branches/${SeedIds.zamalek}/transfers');
    expect(list.query, isEmpty);
    expect(
      h.server.callsTo(locationsRoute).single.path,
      '/inventory/orgs/${SeedIds.sabahOrg}/transfer-locations',
    );
    expect(_refs(tester), _zamalek);
  });

  testWidgets('INV-TRF-008 columns: Ref, Date (received, else sent, else '
      'created), Direction, Items, Status pill', (tester) async {
    final h = await pumpTransfers(tester, branch: SeedIds.zamalek);
    final f = h.container.read(formatProvider);
    for (final c in ['REF', 'DATE', 'DIRECTION', 'ITEMS', 'STATUS']) {
      expect(inTable(find.text(c)), findsWidgets, reason: c);
    }
    // TR-5: received 06 Oct; one line.
    expect(
      inTable(find.text(f.fmtDateTime(DateTime.utc(2026, 10, 6, 8, 30)))),
      findsOneWidget,
    );
    expect(inTable(find.text('Oat Milk · 2,000 ml')), findsOneWidget);
    // TR-6: requested, so its created stamp; two lines → the names.
    expect(
      inTable(find.text(f.fmtDateTime(DateTime.utc(2026, 10, 7, 9, 10)))),
      findsOneWidget,
    );
    expect(inTable(find.text('House Blend Beans, Oat Milk')), findsOneWidget);
    DashStatusPill pill(String label) => tester.widget<DashStatusPill>(
      inTable(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(DashStatusPill),
        ),
      ).first,
    );
    expect(pill('Requested').tone, DashTone.info);
    expect(pill('Received').tone, DashTone.success);
    expect(pill('Cancelled').tone, DashTone.danger);
    // No row menu (Edit note / Reverse are gone).
    expect(
      tester.widget<DashDataTable<StockTransfer>>(table).rowActions,
      isNull,
    );
  });

  for (final locale in ['en', 'ar']) {
    testWidgets('INV-TRF-008 tablet ($locale): Direction stays on one line', (
      tester,
    ) async {
      final h = await pumpTransfers(
        tester,
        size: DashSize.tablet,
        locale: locale,
        branch: SeedIds.zamalek,
      );
      final routes = inTable(find.byType(TransferRoute)).evaluate().toList();
      expect(routes, hasLength(5));
      final heights = {
        for (final e in routes) tester.getSize(find.byWidget(e.widget)).height,
      };
      expect(heights, hasLength(1), reason: '$heights');
      expect(h.locale, locale);
    });
  }

  testWidgets('INV-TRF-008 / INV-ALL-028 a warehouse side wears the '
      'Warehouse glyph; the arrow is mirrored in Arabic', (tester) async {
    final s = transfersServer();
    withWarehouse(s.db);
    // A draft from the store to Zamalek.
    await DashboardApi(s.server).inventory.createTransfer(
      body: CreateTransferRequest(
        sourceBranchId: centralStore,
        destinationBranchId: SeedIds.zamalek,
        lines: [
          TransferLineInput(
            orgIngredientId: InvIds.ingredient('oat'),
            quantity: 3000,
          ),
        ],
      ),
    );
    final h = await pumpTransfers(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.zamalek,
      locale: 'ar',
    );
    final row = find.ancestor(
      of: inTable(find.text('Central Store')),
      matching: find.byType(Wrap),
    );
    expect(
      find.descendant(
        of: row.first,
        matching: find.byWidgetPredicate(
          (w) => w is DashIcon && w.name == 'warehouse',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: row.first,
        matching: find.byWidgetPredicate(
          (w) => w is DashIcon && w.name == 'arrow-left',
        ),
      ),
      findsOneWidget,
    );
    expect(h.locale, 'ar');
  });

  testWidgets('INV-TRF-005 a status tab re-reads with status=; Differences '
      'hides the direction control', (tester) async {
    final h = await pumpTransfers(tester, branch: SeedIds.zamalek);
    await h.tap(inPage(find.text('Requested')));
    expect(h.server.callsTo(listRoute).last.query, {
      'status': ['requested'],
    });
    expect(_refs(tester), ['TR-6']);
    await h.tap(inPage(find.text('All transfers')));
    expect(_refs(tester), _zamalek);
    await h.tap(inPage(find.text('Differences')));
    expect(inPage(byKey('transfers-direction')), findsNothing);
    expect(diffTable, findsOneWidget);
  });

  testWidgets('INV-TRF-006 Incoming / Outgoing re-read with direction=; the '
      'direction is kept across status tabs', (tester) async {
    final h = await pumpTransfers(tester, branch: SeedIds.zamalek);
    await h.tap(inPage(find.text('Outgoing')));
    expect(h.server.callsTo(listRoute).last.query, {
      'direction': ['outgoing'],
    });
    expect(_refs(tester), ['TR-3']);
    await h.tap(inPage(find.text('Received')));
    expect(h.server.callsTo(listRoute).last.query, {
      'direction': ['outgoing'],
      'status': ['received'],
    });
    await h.tap(inPage(find.text('Both ways')));
    expect(h.server.callsTo(listRoute).last.query, {
      'status': ['received'],
    });
    expect(_refs(tester), ['TR-5', 'TR-3', 'TR-2']);
  });

  testWidgets('INV-TRF-007 Export walks the list with direction AND status, '
      'as an export; one row per line', (tester) async {
    final h = await pumpTransfers(tester, branch: SeedIds.zamalek);
    await h.tap(inPage(find.text('Incoming')));
    await h.tap(inPage(find.text('Requested')));
    final before = h.server.callsTo(listRoute).length;
    await h.tap(inPage(byKey('transfers-export')));
    final walk = h.server.callsTo(listRoute).skip(before).toList();
    expect(walk, isNotEmpty);
    expect(walk.first.query['offset'], ['0']);
    for (final c in walk) {
      expect(c.query['limit'], ['500']);
      expect(c.query['direction'], ['incoming']);
      expect(c.query['status'], ['requested']);
      expect(c.headers['X-Madar-Export'], '1');
    }
    await h.expectToast('Exported 2 rows');
    final sheet = h.exports.built.single.sheets.single;
    expect(sheet.name, 'Transfers');
    expect(
      [for (final c in sheet.columns) c.header],
      [
        'Ref',
        'Date',
        'Status',
        'From',
        'To',
        'Ingredient',
        'Sent',
        'Received',
        'Unit',
        'Note',
      ],
    );
    expect(sheet.rows.first.sublist(2), [
      'Requested',
      'Maadi',
      'Zamalek',
      'House Blend Beans',
      1000,
      null,
      'g',
      'Weekend rush: please send before Friday',
    ]);
    expect(sheet.rows.first.first, 'TR-6');
    expect(sheet.rows[1][5], 'Oat Milk');
    expect(h.files.saved.single.filename, 'Madar-Transfers-2026-10-08.xlsx');
  });

  testWidgets('INV-TRF-007 Export is off on Differences and on an empty '
      'list; a failing walk toasts the server\'s words', (tester) async {
    final s = transfersServer();
    final h = await pumpTransfers(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.zamalek,
    );
    DashExportButton exportButton() =>
        tester.widget(inPage(byKey('transfers-export')));
    await h.tap(inPage(find.text('Draft')));
    expect(exportButton().enabled, isFalse, reason: 'no drafts at Zamalek');
    await h.tap(inPage(find.text('Differences')));
    expect(exportButton().enabled, isFalse);
    await h.tap(inPage(find.text('All transfers')));
    expect(exportButton().enabled, isTrue);
    final boom = MockResponse.error(500, 'Export throttled');
    s.server.fail('GET', listRoute, boom);
    final hold = Completer<void>();
    h.exports.hold = hold.future;
    await h.tap(inPage(byKey('transfers-export')));
    await h.expectToast(h.refusalWords(boom));
    expect(h.exports.built, isEmpty);
    expect(exportButton().loading, isFalse);
    hold.complete();
  });

  testWidgets('INV-TRF-009 a row opens the drawer on that transfer', (
    tester,
  ) async {
    final h = await pumpTransfers(tester, branch: SeedIds.zamalek);
    await openRow(h, 'TR-5');
    expect(drawer, findsOneWidget);
    expect(inDrawer(find.text('TR-5')), findsOneWidget);
    expect(inDrawer(find.text('Oat Milk')), findsOneWidget);
  });

  testWidgets('INV-TRF-010 loading: skeleton rows, never "No transfers '
      'found"; Export off', (tester) async {
    final s = transfersServer();
    final gate = s.server.hold('GET', listRoute);
    final h = await pumpTransfers(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.zamalek,
    );
    expect(inTable(find.byType(DashSkeleton)), findsWidgets);
    expect(inPage(find.text('No transfers found')), findsNothing);
    expect(
      tester
          .widget<DashExportButton>(inPage(byKey('transfers-export')))
          .enabled,
      isFalse,
    );
    gate.release();
    await h.settle();
    expect(_refs(tester), _zamalek);
  });

  testWidgets('INV-TRF-010 error: "Couldn\'t load this" + the server\'s '
      'words; Retry re-reads only the list', (tester) async {
    final s = transfersServer();
    final boom = MockResponse.error(500, 'Database unavailable');
    s.server.fail('GET', listRoute, boom);
    final h = await pumpTransfers(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.zamalek,
    );
    expect(inTable(find.text('Couldn\'t load this')), findsOneWidget);
    expect(inTable(find.text(h.refusalWords(boom))), findsOneWidget);
    expect(inPage(find.text('No transfers found')), findsNothing);
    final locations = h.server.callsTo(locationsRoute).length;
    await h.tap(inTable(find.text('Retry')));
    expect(h.server.callsTo(listRoute), hasLength(2));
    expect(h.server.callsTo(locationsRoute), hasLength(locations));
    expect(_refs(tester), _zamalek);
  });

  testWidgets('INV-TRF-010 Retry while the list is out: the failure stays '
      'up and its Retry spins', (tester) async {
    final s = transfersServer();
    s.server.fail('GET', listRoute, MockResponse.error(500, 'Down'));
    final h = await pumpTransfers(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.zamalek,
    );
    s.server.clearFailures();
    final gate = s.server.hold('GET', listRoute);
    await tester.tap(inTable(find.text('Retry')));
    await tester.pump();
    expect(inTable(find.text('Couldn\'t load this')), findsOneWidget);
    expect(
      tester
          .widget<DashErrorState>(inTable(find.byType(DashErrorState)))
          .retrying,
      isTrue,
    );
    gate.release();
    await h.settle();
    expect(_refs(tester), _zamalek);
  });

  testWidgets('INV-TRF-010 empty: "No transfers found"', (tester) async {
    final h = await pumpTransfers(tester, branch: SeedIds.heliopolis);
    await h.tap(inPage(find.text('Cancelled')));
    expect(inTable(find.text('No transfers found')), findsOneWidget);
  });

  testWidgets('INV-TRF-010 ten rows a page, no search box', (tester) async {
    final s = transfersServer();
    final base = doc(s.db, 't1');
    for (var i = 0; i < 6; i++) {
      s.db[InvTables.transfers].insert({
        ...base,
        'id': 'extra-$i',
        'number': 20 + i,
        'reference': 'TR-${20 + i}',
      }, timestamps: false);
    }
    final h = await pumpTransfers(tester, server: s.server, db: s.db);
    expect(inTable(find.text('Page 1 of 2')), findsOneWidget);
    expect(inTable(find.byType(DashSearchInput)), findsNothing);
    expect(h.server.callsTo(listRoute), hasLength(1));
  });

  testWidgets('INV-TRF-011 Differences: the org\'s received lines that '
      'differ, in the scope period; signed difference and value', (
    tester,
  ) async {
    final s = transfersServer();
    final t = receiveShort(s.db);
    final cost =
        ((t['lines']! as List).cast<MockRow>().firstWhere(
                  (l) => l['ingredient_name'] == 'Croissant Dough',
                )['unit_cost']!
                as num)
            .toDouble();
    final h = await pumpTransfers(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.zamalek,
    );
    await h.tap(inPage(find.text('Differences')));
    final call = h.server.callsTo(diffsRoute).single;
    final scope = h.container.read(currentScopeProvider);
    expect(
      call.path,
      '/inventory/orgs/${SeedIds.sabahOrg}/transfer-differences',
    );
    expect(
      DateTime.parse(call.query['from']!.single),
      DateTime.parse(scope.from),
    );
    expect(DateTime.parse(call.query['to']!.single), DateTime.parse(scope.to));
    final f = h.container.read(formatProvider);
    for (final c in [
      'REF',
      'RECEIVED',
      'DIRECTION',
      'INGREDIENT',
      'DIFFERENCE',
      'VALUE',
      'NOTE',
    ]) {
      expect(inDiffs(find.text(c)), findsWidgets, reason: c);
    }
    expect(inDiffs(find.text('TR-7')), findsOneWidget);
    expect(inDiffs(find.text('Croissant Dough')), findsOneWidget);
    expect(inDiffs(find.text('${f.fmtNumber(-2)} pcs')), findsOneWidget);
    expect(
      inDiffs(find.text(f.fmtMoney((-2 * cost).round(), signed: true))),
      findsOneWidget,
    );
    expect(inDiffs(find.text('Two crushed in the van')), findsOneWidget);
    // No row click.
    await h.tap(inDiffs(find.text('TR-7')));
    expect(drawer, findsNothing);
  });

  testWidgets('INV-TRF-011 Differences: empty, error + Retry, loading', (
    tester,
  ) async {
    final s = transfersServer();
    final h = await pumpTransfers(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.zamalek,
    );
    final gate = s.server.hold('GET', diffsRoute);
    await h.tap(inPage(find.text('Differences')));
    expect(inDiffs(find.byType(DashSkeleton)), findsWidgets);
    expect(inPage(find.text('Everything arrived as sent')), findsNothing);
    gate.release();
    await h.settle();
    expect(inDiffs(find.text('Everything arrived as sent')), findsOneWidget);
    expect(
      inDiffs(
        find.text(
          'Received transfers whose quantities differ from what was sent '
          'show up here.',
        ),
      ),
      findsOneWidget,
    );
    final s2 = transfersServer();
    final boom = MockResponse.error(500, 'Report timed out');
    s2.server.fail('GET', diffsRoute, boom, times: null);
    final h2 = await pumpTransfers(
      tester,
      server: s2.server,
      db: s2.db,
      branch: SeedIds.zamalek,
    );
    await h2.tap(inPage(find.text('Differences')));
    expect(inDiffs(find.text(h2.refusalWords(boom))), findsOneWidget);
    expect(inPage(find.text('Everything arrived as sent')), findsNothing);
    final calls = h2.server.callsTo(diffsRoute).length;
    final lists = h2.server.callsTo(listRoute).length;
    s2.server.clearFailures();
    await h2.tap(inDiffs(find.text('Retry')));
    expect(h2.server.callsTo(diffsRoute), hasLength(calls + 1));
    expect(h2.server.callsTo(listRoute), hasLength(lists));
    expect(inDiffs(find.text('Everything arrived as sent')), findsOneWidget);
  });

  testWidgets('INV-TRF-012 phone: cards led by the reference; a tap opens '
      'the drawer full screen', (tester) async {
    final h = await pumpTransfers(
      tester,
      size: DashSize.phone,
      branch: SeedIds.zamalek,
    );
    for (final r in _zamalek) {
      expect(inTable(find.text(r)), findsOneWidget, reason: r);
    }
    expect(inTable(find.text('Columns')), findsNothing);
    await h.tap(inTable(find.text('TR-6')));
    expect(drawer, findsOneWidget);
    expect(tester.getSize(drawer).width, closeTo(DashSize.phone.size.width, 1));
  });

  testWidgets('INV-TRF-012 the Columns menu lists the five columns', (
    tester,
  ) async {
    final h = await pumpTransfers(tester, branch: SeedIds.zamalek);
    await h.tap(inTable(find.text('Columns')));
    for (final c in ['Ref', 'Date', 'Direction', 'Items', 'Status']) {
      expect(find.text(c).hitTestable(), findsWidgets, reason: c);
    }
  });

  testWidgets('INV-TRF-003 New transfer opens the dialog in send mode from '
      'the scoped branch, To empty, one empty line', (tester) async {
    final h = await pumpTransfers(tester, branch: SeedIds.zamalek);
    await h.tap(inPage(byKey('transfers-new')));
    expect(dialog, findsOneWidget);
    expect(inDialog(find.text('New transfer')), findsOneWidget);
    expect(
      find.descendant(
        of: triggerIn(dialog, 'transfer-source'),
        matching: find.text('Zamalek'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: triggerIn(dialog, 'transfer-destination'),
        matching: find.text('—'),
      ),
      findsOneWidget,
    );
    expect(inDialog(byKey('transfer-ingredient-0')), findsOneWidget);
    expect(inDialog(byKey('transfer-ingredient-1')), findsNothing);
  });

  testWidgets('INV-TRF-003 / INV-ALL-027 All branches: New transfer is '
      'shown; From starts empty', (tester) async {
    final h = await pumpTransfers(tester);
    expect(
      h.server.callsTo(listRoute).single.path,
      '/inventory/branches/$allBranches/transfers',
    );
    await h.tap(inPage(byKey('transfers-new')));
    expect(
      find.descendant(
        of: triggerIn(dialog, 'transfer-source'),
        matching: find.text('—'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('INV-TRF-004 / INV-ALL-028 Replenish a branch: at a warehouse '
      'scope where the person can create, reads the list at the warehouse', (
    tester,
  ) async {
    final s = transfersServer();
    withWarehouse(s.db);
    final h = await pumpTransfers(
      tester,
      server: s.server,
      db: s.db,
      branch: centralStore,
    );
    expect(
      h.server.callsTo(listRoute).single.path,
      '/inventory/branches/$centralStore/transfers',
    );
    expect(
      h.server
          .callsTo(authzRoute)
          .where((c) => c.query['branch_id']?.single == centralStore),
      isNotEmpty,
    );
    expect(inPage(byKey('transfers-replenish')), findsOneWidget);
    expect(inPage(find.text('Replenish a branch')), findsOneWidget);
    final replenishX = tester
        .getCenter(inPage(byKey('transfers-replenish')))
        .dx;
    final newX = tester.getCenter(inPage(byKey('transfers-new'))).dx;
    expect(replenishX, lessThan(newX));
  });

  testWidgets('INV-TRF-004 / INV-TRF-041 no Replenish at a selling branch, '
      'nor without create AT the warehouse', (tester) async {
    final s = transfersServer();
    withWarehouse(s.db);
    holdAt(s.server, centralStore, {Cap.inventoryTransfersCreate});
    await pumpTransfers(
      tester,
      server: s.server,
      db: s.db,
      branch: centralStore,
    );
    expect(inPage(byKey('transfers-replenish')), findsNothing);
    expect(inPage(byKey('transfers-new')), findsOneWidget);
  });

  testWidgets('INV-TRF-041 without inventory.transfers.create: no New '
      'transfer, no Replenish, no transfer-locations read', (tester) async {
    final s = transfersServer();
    withWarehouse(s.db);
    holdAt(s.server, null, {Cap.inventoryTransfersCreate});
    final h = await pumpTransfers(
      tester,
      server: s.server,
      db: s.db,
      branch: centralStore,
    );
    expect(inPage(byKey('transfers-new')), findsNothing);
    expect(inPage(byKey('transfers-replenish')), findsNothing);
    expect(h.server.callsTo(locationsRoute), isEmpty);
    expect(_refs(tester), isEmpty);
  });

  testWidgets('INV-TRF-041 manager: works at Zamalek; the list and New '
      'transfer as the owner', (tester) async {
    final h = await pumpTransfers(
      tester,
      persona: Persona.manager,
      branch: SeedIds.zamalek,
    );
    expect(_refs(tester), _zamalek);
    expect(inPage(byKey('transfers-new')), findsOneWidget);
    expect(h.server.callsTo(locationsRoute), hasLength(1));
  });

  testWidgets('INV-TRF-001 (divergence) limited persona: the shell\'s route '
      'gate shows Restricted and reads nothing', (tester) async {
    final h = await pumpTransfers(
      tester,
      persona: Persona.limited,
      branch: SeedIds.maadi,
    );
    expect(page, findsNothing);
    expect(find.text('Not available on this account'), findsOneWidget);
    expect(h.server.callsTo(listRoute), isEmpty);
  });

  testWidgets('INV-TRF-010 a 403 on the list shows the server\'s words in '
      'the table', (tester) async {
    final s = transfersServer();
    final denied = MockResponse.denied('inventory.transfers.read');
    s.server.fail('GET', listRoute, denied, times: null);
    final h = await pumpTransfers(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.zamalek,
    );
    expect(inTable(find.text(h.refusalWords(denied))), findsOneWidget);
  });

  testWidgets('INV-ALL-027 no organization: the list reads the all-branches '
      'id; branches and locations are not read; Differences never loads', (
    tester,
  ) async {
    final h = await pumpTransfers(tester, persona: Persona.platform);
    expect(h.container.read(currentScopeProvider).orgId, isNull);
    expect(
      h.server.callsTo(listRoute).single.path,
      '/inventory/branches/$allBranches/transfers',
    );
    expect(h.server.callsTo(locationsRoute), isEmpty);
    expect(
      inTable(
        find.text(
          h.refusalWords(MockResponse.forbidden('No organization in scope')),
        ),
      ),
      findsOneWidget,
    );
    // New transfer still follows the capability.
    expect(inPage(byKey('transfers-new')), findsOneWidget);
    await h.tap(inPage(find.text('Differences')));
    expect(h.server.callsTo(diffsRoute), isEmpty);
  });
}
