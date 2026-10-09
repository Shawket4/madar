// Transfers (`/inventory/transfers`): one driven test per INV-TRF page row
// through the real shell on the seeded mock server, plus the loading,
// error, empty and refusal states. The New transfer dialog is in
// transfers_dialog_test.dart.
import 'dart:async';

import 'package:dashboard_api/dashboard_api.dart' show StockTransfer;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Zamalek's transfers, latest first (t1 in, t3 out, t4 in).
const _zamalek = ['Oat Milk', 'Paper Cup 12oz', 'Vanilla Syrup'];

/// The ingredient cells, top to bottom.
List<String> _ingredients(WidgetTester tester) {
  final texts = inTable(find.byType(Text)).evaluate().map(
    (e) => (e.widget as Text).data,
  );
  const names = [
    'Oat Milk',
    'House Blend Beans',
    'Paper Cup 12oz',
    'Vanilla Syrup',
    'Croissant Dough',
  ];
  return [
    for (final t in texts)
      if (names.contains(t)) t!,
  ];
}

void main() {
  testWidgets('INV-TRF-001 header: Transfers, Export + New transfer, the '
      'direction filter below', (tester) async {
    final h = await pumpTransfers(tester, branch: SeedIds.zamalek);
    expect(inPage(find.text('Transfers')), findsWidgets);
    expect(inPage(byKey('transfers-export')), findsOneWidget);
    expect(inPage(find.text('Export Excel')), findsOneWidget);
    expect(inPage(find.text('New transfer')), findsOneWidget);
    final seg = tester.widget<DashSegmentedControl<String?>>(
      inPage(byKey('transfers-direction')),
    );
    expect(seg.value, isNull);
    expect([for (final o in seg.options) o.label], [
      'All transfers',
      'Incoming',
      'Outgoing',
    ]);
  });

  testWidgets('INV-TRF-002 reads the org\'s branches and the branch\'s '
      'transfers (no direction)', (tester) async {
    final h = await pumpTransfers(tester, branch: SeedIds.zamalek);
    final call = h.server.callsTo(listRoute).single;
    expect(call.path, '/inventory/branches/${SeedIds.zamalek}/transfers');
    expect(call.query, isEmpty);
    expect(h.server.callsTo(branchesRoute), isNotEmpty);
    expect(_ingredients(tester), _zamalek);
  });

  testWidgets('INV-TRF-006 columns: Date, Ingredient, Quantity, Direction '
      '"source → destination", By; no Branch column', (tester) async {
    await pumpTransfers(tester, branch: SeedIds.zamalek);
    final t = tester.widget<DashDataTable<StockTransfer>>(table);
    expect([for (final c in t.columns) c.label], [
      'Date',
      'Ingredient',
      'Quantity',
      'Direction',
      'By',
    ]);
    // 08:30 UTC is 11:30 in Cairo (summer time).
    expect(inTable(find.text('06 Oct, 11:30 AM')), findsOneWidget);
    expect(inTable(find.text('2,000 ml')), findsOneWidget);
    expect(inTable(find.text('Maadi')), findsOneWidget);
    expect(inTable(find.text('Zamalek')), findsNWidgets(3));
    expect(inTable(find.text('Tarek Saber')), findsOneWidget);
    expect(inTable(find.text('100 pcs')), findsOneWidget);
    // The arrow points toward the end of the line.
    final arrows = tester.widgetList<DashIcon>(
      inTable(find.byWidgetPredicate((w) => w is DashIcon && w.name == 'arrow-right')),
    );
    expect(arrows, hasLength(3));
  });

  testWidgets('INV-TRF-006 Arabic: the route arrow is mirrored', (
    tester,
  ) async {
    await pumpTransfers(tester, branch: SeedIds.zamalek, locale: 'ar');
    expect(
      inTable(
        find.byWidgetPredicate((w) => w is DashIcon && w.name == 'arrow-left'),
      ),
      findsNWidgets(3),
    );
  });

  testWidgets('INV-TRF-004 Incoming / Outgoing re-read with direction=; All '
      'omits it again (from the cache)', (tester) async {
    final h = await pumpTransfers(tester, branch: SeedIds.zamalek);
    await h.tap(inPage(find.text('Incoming')));
    expect(h.server.callsTo(listRoute).last.query['direction'], ['incoming']);
    expect(_ingredients(tester), ['Oat Milk', 'Vanilla Syrup']);
    await h.tap(inPage(find.text('Outgoing')));
    expect(h.server.callsTo(listRoute).last.query['direction'], ['outgoing']);
    expect(_ingredients(tester), ['Paper Cup 12oz']);
    final n = h.server.callsTo(listRoute).length;
    await h.tap(inPage(find.text('All transfers')));
    expect(h.server.callsTo(listRoute), hasLength(n));
    expect(_ingredients(tester), _zamalek);
  });

  testWidgets('INV-TRF-023 All branches: the org rolled up, New transfer '
      'hidden, the row menu still offered', (tester) async {
    final h = await pumpTransfers(tester);
    expect(
      h.server.callsTo(listRoute).single.path,
      '/inventory/branches/$allBranches/transfers',
    );
    expect(_ingredients(tester), [
      'Oat Milk',
      'House Blend Beans',
      'Paper Cup 12oz',
      'Vanilla Syrup',
      'Croissant Dough',
    ]);
    expect(inPage(byKey('transfers-new')), findsNothing);
    expect(menuOf('t2'), findsOneWidget);
  });

  testWidgets('INV-TRF-003 / INV-TRF-026 New transfer is off with fewer than '
      'two ACTIVE branches', (tester) async {
    final s = transfersServer();
    for (final id in [SeedIds.heliopolis, SeedIds.maadi, SeedIds.newCairo]) {
      s.db['branches'].find(id)!['is_active'] = false;
    }
    final h = await pumpTransfers(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.zamalek,
    );
    final b = tester.widget<DashButton>(inPage(byKey('transfers-new')));
    expect(b.onPressed, isNull);
    expect(h.server.callsTo(listRoute), hasLength(1));
  });

  testWidgets('INV-TRF-003 with two active branches it opens the dialog', (
    tester,
  ) async {
    final s = transfersServer();
    for (final id in [SeedIds.heliopolis, SeedIds.newCairo]) {
      s.db['branches'].find(id)!['is_active'] = false;
    }
    final h = await pumpTransfers(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.zamalek,
    );
    await h.tap(inPage(byKey('transfers-new')));
    expect(dialog, findsOneWidget);
  });

  testWidgets('INV-TRF-007 the row menu: Edit note, Reverse transfer', (
    tester,
  ) async {
    final h = await pumpTransfers(tester, branch: SeedIds.zamalek);
    expect(
      tester.widget<DashIconButton>(menuOf('t1')).semanticLabel,
      'More actions',
    );
    await h.tap(menuOf('t1'));
    expect(menuItem('Edit note'), findsOneWidget);
    expect(menuItem('Reverse transfer'), findsOneWidget);
    final items = tester
        .widget<DashMenu>(byKey('transfer-menu-${InvIds.transfer('t1')}'))
        .items;
    expect([for (final i in items) i.label], ['Edit note', 'Reverse transfer']);
    final reverse = items.last;
    expect(reverse.destructive, isTrue);
    expect(reverse.icon, 'rotate-ccw');
  });

  testWidgets('INV-TRF-008 / INV-TRF-027 Edit note: prefilled, saved trimmed, '
      'inventory invalidated, "Changes saved"', (tester) async {
    final h = await pumpTransfers(tester, branch: SeedIds.zamalek);
    await h.tap(menuOf('t1'));
    await h.tap(menuItem('Edit note'));
    expect(noteDialog, findsOneWidget);
    expect(inNote(find.text('Edit note')), findsOneWidget);
    expect(inNote(find.text('Zamalek ran short over the weekend')), findsOneWidget);
    await h.enterText(
      inNote(byKey('transfer-note-draft')),
      '  Weekend rush, sent Monday  ',
    );
    final lists = h.server.callsTo(listRoute).length;
    await h.tap(inNote(byKey('transfer-note-save')));
    final call = h.server.callsTo(itemRoute, method: 'PATCH').single;
    expect(call.path, '/inventory/transfers/${InvIds.transfer('t1')}');
    expect(call.body, {'note': 'Weekend rush, sent Monday'});
    await h.expectToast('Changes saved');
    expect(noteDialog, findsNothing);
    expect(h.server.callsTo(listRoute).length, lists + 1, reason: 'refetched');
  });

  testWidgets('INV-TRF-008 a blank note is sent as null', (tester) async {
    final h = await pumpTransfers(tester, branch: SeedIds.zamalek);
    await h.tap(menuOf('t1'));
    await h.tap(menuItem('Edit note'));
    await h.enterText(inNote(byKey('transfer-note-draft')), '   ');
    await h.tap(inNote(byKey('transfer-note-save')));
    expect(h.server.callsTo(itemRoute, method: 'PATCH').single.body, {
      'note': null,
    });
    await h.expectToast('Changes saved');
  });

  testWidgets('INV-TRF-008 a refused save toasts the server\'s words and '
      'stays open; Cancel discards the draft (INV-TRF-027)', (tester) async {
    final s = transfersServer();
    final boom = MockResponse.denied('inventory.transfers.edit');
    s.server.fail('PATCH', itemRoute, boom);
    final h = await pumpTransfers(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.zamalek,
    );
    await h.tap(menuOf('t1'));
    await h.tap(menuItem('Edit note'));
    await h.enterText(inNote(byKey('transfer-note-draft')), 'Changed');
    await h.tap(inNote(byKey('transfer-note-save')));
    await h.expectToast(h.refusalWords(boom));
    expect(noteDialog, findsOneWidget);
    expect(inNote(find.text('Changed')), findsOneWidget);
    await h.tap(inNote(byKey('transfer-note-cancel')));
    expect(noteDialog, findsNothing);
    await h.tap(menuOf('t1'));
    await h.tap(menuItem('Edit note'));
    expect(inNote(find.text('Zamalek ran short over the weekend')), findsOneWidget);
  });

  testWidgets('INV-TRF-009 / INV-TRF-029 Reverse: confirm, DELETE, the row '
      'is gone, two "Transfer reversal" movements, "Done"', (tester) async {
    final s = transfersServer();
    final h = await pumpTransfers(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.newCairo,
    );
    final zamalekCups = stockRow(s.db, SeedIds.zamalek, 'paper-cup-12');
    final before = (zamalekCups!['on_hand']! as num).toDouble();
    await h.tap(menuOf('t3'));
    await h.tap(menuItem('Reverse transfer'));
    expect(find.text('Reverse the Paper Cup 12oz transfer?'), findsOneWidget);
    expect(
      find.text(
        'A compensating entry moves the stock back to the source branch. '
        'The original transfer stays in the history.',
      ),
      findsOneWidget,
    );
    await h.tap(find.widgetWithText(DashButton, 'Reverse transfer').last);
    final call = h.server.callsTo(itemRoute, method: 'DELETE').single;
    expect(call.path, '/inventory/transfers/${InvIds.transfer('t3')}');
    await h.expectToast('Done');
    expect(inTable(find.text('Paper Cup 12oz')), findsNothing);
    expect(s.db[InvTables.transfers].find(InvIds.transfer('t3')), isNull);
    final reversal = s.db[InvTables.movements].where(
      (m) => m['note'] == 'Transfer reversal',
    );
    expect({for (final m in reversal) m['movement_type']}, {
      'transfer_out',
      'transfer_in',
    });
    expect((zamalekCups['on_hand']! as num).toDouble(), before + 100);
  });

  testWidgets('INV-TRF-009 Cancel reverses nothing', (tester) async {
    final h = await pumpTransfers(tester, branch: SeedIds.zamalek);
    await h.tap(menuOf('t3'));
    await h.tap(menuItem('Reverse transfer'));
    await h.tap(find.widgetWithText(DashButton, 'Cancel').last);
    expect(h.server.callsTo(itemRoute, method: 'DELETE'), isEmpty);
    expect(inTable(find.text('Paper Cup 12oz')), findsOneWidget);
  });

  testWidgets('INV-TRF-009 the destination holds less than was sent: 409 '
      'toasted, the row stays', (tester) async {
    // Zamalek holds −350 ml of oat milk; 2,000 ml came from Maadi.
    final h = await pumpTransfers(tester, branch: SeedIds.zamalek);
    await h.tap(menuOf('t1'));
    await h.tap(menuItem('Reverse transfer'));
    await h.tap(find.widgetWithText(DashButton, 'Reverse transfer').last);
    await h.expectToast(
      h.refusalWords(
        MockResponse.conflict(
          'Cannot reverse transfer: the destination branch only has '
          '-350.000 left of the 2000.000 transferred.',
        ),
      ),
    );
    expect(inTable(find.text('Oat Milk')), findsOneWidget);
  });

  testWidgets('INV-TRF-025 manager: same controls; the server refuses the '
      'reverse (inventory.transfers.delete)', (tester) async {
    final h = await pumpTransfers(
      tester,
      persona: Persona.manager,
      branch: SeedIds.zamalek,
    );
    expect(inPage(byKey('transfers-new')), findsOneWidget);
    await h.tap(menuOf('t3'));
    expect(menuItem('Reverse transfer'), findsOneWidget);
    await h.tap(menuItem('Reverse transfer'));
    await h.tap(find.widgetWithText(DashButton, 'Reverse transfer').last);
    await h.expectToast(
      h.refusalWords(MockResponse.denied('inventory.transfers.delete')),
    );
    expect(inTable(find.text('Paper Cup 12oz')), findsOneWidget);
  });

  testWidgets('INV-TRF-010 loading: skeleton rows, never "No transfers '
      'found"', (tester) async {
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
      tester.widget<DashExportButton>(inPage(byKey('transfers-export'))).enabled,
      isFalse,
    );
    gate.release();
    await h.settle();
    expect(_ingredients(tester), _zamalek);
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
    final branches = h.server.callsTo(branchesRoute).length;
    await h.tap(inTable(find.text('Retry')));
    expect(h.server.callsTo(listRoute), hasLength(2));
    expect(h.server.callsTo(branchesRoute), hasLength(branches));
    expect(_ingredients(tester), _zamalek);
  });

  testWidgets('INV-TRF-010 empty: "No transfers found"; Export off', (
    tester,
  ) async {
    final h = await pumpTransfers(tester, branch: SeedIds.heliopolis);
    expect(inTable(find.text('No transfers found')), findsOneWidget);
    expect(
      tester.widget<DashExportButton>(inPage(byKey('transfers-export'))).enabled,
      isFalse,
    );
    expect(h.server.callsTo(listRoute).single.path, contains(SeedIds.heliopolis));
  });

  testWidgets('INV-TRF-010 refusal: a persona without inventory.transfers.read '
      'sees the server\'s words in the table', (tester) async {
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

  testWidgets('INV-TRF-010 ten rows a page (no search box)', (tester) async {
    final s = transfersServer();
    for (var i = 0; i < 9; i++) {
      s.db[InvTables.transfers].insert({
        ...s.db[InvTables.transfers].find(InvIds.transfer('t1'))!,
        'id': 'extra-$i',
        'initiated_at': '2026-10-0${i % 5 + 1}T06:00:00Z',
      }, timestamps: false);
    }
    final h = await pumpTransfers(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.zamalek,
    );
    expect(inTable(find.text('Page 1 of 2')), findsOneWidget);
    expect(inTable(find.byType(DashSearchInput)), findsNothing);
    expect(h.server.callsTo(listRoute), hasLength(1));
  });

  testWidgets('INV-TRF-011 the Columns menu lists the five columns', (
    tester,
  ) async {
    final h = await pumpTransfers(tester, branch: SeedIds.zamalek);
    await h.tap(inTable(find.text('Columns')));
    for (final c in ['Date', 'Ingredient', 'Quantity', 'Direction', 'By']) {
      expect(find.text(c).hitTestable(), findsWidgets, reason: c);
    }
  });

  testWidgets('INV-TRF-024 phone: cards led by the ingredient, ⋯ on each', (
    tester,
  ) async {
    final h = await pumpTransfers(
      tester,
      size: DashSize.phone,
      branch: SeedIds.zamalek,
    );
    for (final name in _zamalek) {
      expect(inTable(find.text(name)), findsOneWidget);
    }
    expect(inTable(find.text('Columns')), findsNothing);
    await h.tap(menuOf('t3'));
    expect(menuItem('Edit note'), findsOneWidget);
  });

  testWidgets('INV-TRF-005 Export walks the list with the direction, as an '
      'export, into Madar-Transfers', (tester) async {
    final h = await pumpTransfers(tester, branch: SeedIds.zamalek);
    await h.tap(inPage(find.text('Incoming')));
    final before = h.server.callsTo(listRoute).length;
    await h.tap(inPage(byKey('transfers-export')));
    final walk = h.server.callsTo(listRoute).skip(before).toList();
    expect([for (final c in walk) c.query['offset']!.single], ['0', '2']);
    for (final c in walk) {
      expect(c.query['limit'], ['500']);
      expect(c.query['direction'], ['incoming']);
      expect(c.headers['X-Madar-Export'], '1');
    }
    await h.expectToast('Exported 2 rows');
    final sheet = h.exports.built.single.sheets.single;
    expect(sheet.name, 'Transfers');
    expect(sheet.title, 'Transfers');
    expect([for (final c in sheet.columns) c.header], [
      'Date',
      'Ingredient',
      'Quantity',
      'Unit',
      'From',
      'To',
      'By',
      'Note',
    ]);
    final oat = sheet.rows.first;
    expect(oat.sublist(1), [
      'Oat Milk',
      2000,
      'ml',
      'Maadi',
      'Zamalek',
      'Tarek Saber',
      'Zamalek ran short over the weekend',
    ]);
    expect(sheet.rows.last[7], '');
    expect(h.files.saved.single.filename, 'Madar-Transfers-2026-10-08.xlsx');
  });

  testWidgets('INV-TRF-005 a failing walk toasts the server\'s words; the '
      'spinner stops', (tester) async {
    final s = transfersServer();
    final h = await pumpTransfers(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.zamalek,
    );
    final boom = MockResponse.error(500, 'Export throttled');
    s.server.fail('GET', listRoute, boom);
    final hold = Completer<void>();
    h.exports.hold = hold.future;
    await h.tap(inPage(byKey('transfers-export')));
    await h.expectToast(h.refusalWords(boom));
    expect(h.exports.built, isEmpty);
    expect(
      tester.widget<DashExportButton>(inPage(byKey('transfers-export'))).loading,
      isFalse,
    );
    hold.complete();
  });

  testWidgets('INV-ALL-027 no organization: the list reads the all-branches '
      'id, branches are not read, New transfer hidden', (tester) async {
    final h = await pumpTransfers(tester, persona: Persona.platform);
    expect(h.container.read(currentScopeProvider).orgId, isNull);
    expect(inPage(byKey('transfers-new')), findsNothing);
    final call = h.server.callsTo(listRoute).single;
    expect(call.path, '/inventory/branches/$allBranches/transfers');
    expect(
      inTable(
        find.text(
          h.refusalWords(MockResponse.forbidden('No organization in scope')),
        ),
      ),
      findsOneWidget,
    );
  });
}
