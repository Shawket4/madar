// Purchasing: the page, its three tabs, their tables, filters, row actions
// and exports, driven through the real shell (INV-PUR-001…027, -058, -060…
// -062, -064, -072 and the INV-ALL rows that live on this page). The
// dialogs are in purchasing_dialogs_test.dart.
import 'dart:async';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:dashboard_inventory/src/purchasing/purchasing_data.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

final String _po1044 = PurIds.po('po-1044'); // Zamalek, ordered, no ref
final String _po1042 = PurIds.po('po-1042'); // Zamalek, ordered
final String _po1041 = PurIds.po('po-1041'); // Maadi, partially received
final String _po1040 = PurIds.po('po-1040'); // New Cairo, draft
final String _po1039 = PurIds.po('po-1039'); // Zamalek, received
final String _po1038 = PurIds.po('po-1038'); // Heliopolis, cancelled

/// `#` and the first 8 characters of the id (an order with no reference).
String shortRef(String id) => '#${id.substring(0, 8)}';

/// The references the orders table shows, top to bottom.
List<String> shownRefs(WidgetTester tester, MockDb db) {
  final all = [
    for (final po in db[InvTables.purchaseOrders].rows)
      (po['reference'] as String?) ?? shortRef(po['id']! as String),
  ];
  final shown = <(double, String)>[
    for (final r in all)
      if (exactText(ordersTable, r).evaluate().isNotEmpty)
        (tester.getTopLeft(exactText(ordersTable, r)).dy, r),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final s in shown) s.$2];
}

Future<void> openPalette(DashHarness h, String query) async {
  await h.tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await h.tester.sendKeyEvent(LogicalKeyboardKey.keyK);
  await h.tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await h.settle();
  await h.enterText(find.byType(DashCommandPalette), query);
}

DashStatusPill pillOf(WidgetTester tester, Finder row, String label) =>
    tester.widget<DashStatusPill>(
      find.ancestor(of: row, matching: find.byType(DashStatusPill)).first,
    );

void main() {
  group('header and reads', () {
    testWidgets('INV-PUR-001 header: title, Export Excel, New purchase '
        'order, the tab bar', (tester) async {
      final h = await pumpPurchasing(tester);
      expect(h.location.path, purchasingPath);
      expect(inPage(find.text('Purchasing')), findsOneWidget);
      expect(inPage(find.text('Export Excel')), findsOneWidget);
      expect(inPage(find.text('New purchase order')), findsOneWidget);
      for (final tab in ['Purchase orders', 'Suppliers', 'Reorder']) {
        expect(
          find.descendant(of: tabStrip, matching: find.text(tab)),
          findsOneWidget,
          reason: tab,
        );
      }
    });

    testWidgets('INV-PUR-002 / INV-ALL-009 no organization in scope: the '
        'title and "Select an organization to manage inventory" only', (
      tester,
    ) async {
      final h = await pumpPurchasing(tester, persona: Persona.platform);
      expect(
        inPage(find.text('Select an organization to manage inventory')),
        findsOneWidget,
      );
      expect(inPage(find.text('Purchasing')), findsOneWidget);
      expect(tabStrip, findsNothing);
      expect(inPage(find.text('Export Excel')), findsNothing);
      expect(h.server.callsTo(PurT.suppliers), isEmpty);
      expect(h.server.callsTo(PurT.orders), isEmpty);
      expect(h.server.callsTo(PurT.catalog), isEmpty);
    });

    testWidgets('INV-PUR-003 / INV-ALL-008 reads with All branches: the '
        'org\'s suppliers and catalog, the orders with the all-branches id '
        'and no status', (tester) async {
      final h = await pumpPurchasing(tester);
      expect(
        h.server.callsTo(PurT.suppliers).single.path,
        '/purchasing/orgs/${SeedIds.sabahOrg}/suppliers',
      );
      expect(
        h.server.callsTo(PurT.catalog).single.path,
        '/inventory/orgs/${SeedIds.sabahOrg}/catalog',
      );
      final orders = h.server.callsTo(PurT.orders).single;
      expect(orders.path, '/purchasing/branches/$allBranchesId/orders');
      expect(orders.query.containsKey('status'), isFalse);
      // The Reorder read waits for its tab.
      expect(h.server.callsTo(PurT.reorder), isEmpty);
    });

    testWidgets('INV-PUR-003 / INV-ALL-008 a ?branchId= deep link reads '
        'that branch\'s orders', (tester) async {
      final h = await pumpPurchasing(
        tester,
        path: purchasingAt(SeedIds.zamalek),
      );
      expect(
        h.server.callsTo(PurT.orders).single.path,
        '/purchasing/branches/${SeedIds.zamalek}/orders',
      );
      expect(inOrders(find.text('PO-1042')), findsOneWidget);
      expect(inOrders(find.text('PO-1043')), findsNothing); // New Cairo's
    });
  });

  group('tabs (INV-PUR-004, -005, -022, -072)', () {
    testWidgets('INV-PUR-004 Purchase orders is the default; Suppliers and '
        'Reorder switch the table; the tab is not kept in the URL', (
      tester,
    ) async {
      final h = await pumpPurchasing(
        tester,
        path: purchasingAt(SeedIds.zamalek),
      );
      expect(ordersTable, findsOneWidget);
      await openTab(h, 'Suppliers');
      expect(suppliersTable, findsOneWidget);
      expect(ordersTable, findsNothing);
      expect(h.location.queryParameters.keys, isNot(contains('tab')));
      await openTab(h, 'Reorder');
      expect(suppliersTable, findsNothing);
      expect(inPage(find.text('Create draft PO')), findsWidgets);
      expect(h.location.path, purchasingPath);
      await openTab(h, 'Purchase orders');
      expect(ordersTable, findsOneWidget);
    });

    testWidgets('INV-PUR-004 the tab bar scrolls sideways when narrow', (
      tester,
    ) async {
      await pumpPurchasing(tester, size: DashSize.phone);
      expect(
        find.descendant(
          of: tabStrip,
          matching: find.byWidgetPredicate(
            (w) =>
                w is SingleChildScrollView &&
                w.scrollDirection == Axis.horizontal,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('INV-PUR-005 the header button follows the tab: New '
        'purchase order, New supplier, none on Reorder', (tester) async {
      final h = await pumpPurchasing(
        tester,
        path: purchasingAt(SeedIds.zamalek),
      );
      expect(button(tester, 'purchasing-new-order').onPressed, isNotNull);
      expect(byKey('purchasing-new-supplier'), findsNothing);
      await h.tap(byKey('purchasing-new-order'));
      expect(poDialog, findsOneWidget);
      await h.tap(inPo(find.text('Cancel')));

      await openTab(h, 'Suppliers');
      expect(byKey('purchasing-new-order'), findsNothing);
      await h.tap(byKey('purchasing-new-supplier'));
      expect(supplierDialog, findsOneWidget);
      expect(inSupplier(find.text('New supplier')), findsOneWidget);
      await h.tap(inSupplier(find.text('Cancel')));

      await openTab(h, 'Reorder');
      expect(byKey('purchasing-new-order'), findsNothing);
      expect(byKey('purchasing-new-supplier'), findsNothing);
      expect(inPage(find.text('Export Excel')), findsOneWidget);
    });

    testWidgets('INV-PUR-022 / INV-PUR-058 Reorder is off with All branches; '
        'its read runs only while the tab is open', (tester) async {
      final h = await pumpPurchasing(tester);
      final reorder = find.ancestor(
        of: find.descendant(of: tabStrip, matching: find.text('Reorder')),
        matching: find.byType(DashPressable),
      );
      expect(tester.widget<DashPressable>(reorder.first).enabled, isFalse);
      await tester.tap(
        find.descendant(of: tabStrip, matching: find.text('Reorder')),
        warnIfMissed: false,
      );
      await h.settle();
      expect(ordersTable, findsOneWidget);
      expect(h.server.callsTo(PurT.reorder), isEmpty);
    });

    testWidgets('INV-PUR-022 with a branch, the suggestions are read when '
        'the tab opens, for that branch', (tester) async {
      final h = await pumpPurchasing(
        tester,
        path: purchasingAt(SeedIds.zamalek),
      );
      expect(h.server.callsTo(PurT.reorder), isEmpty);
      await openTab(h, 'Reorder');
      expect(
        h.server.callsTo(PurT.reorder).single.path,
        '/purchasing/branches/${SeedIds.zamalek}/reorder-suggestions',
      );
    });

    testWidgets('INV-PUR-072 (divergence) Reorder open, then All branches: '
        'the orders show (the web shows a false "No items to reorder"); '
        'picking the branch again returns to Reorder; tab and status filter '
        'are kept', (tester) async {
      final h = await pumpPurchasing(
        tester,
        path: purchasingAt(SeedIds.zamalek),
      );
      await h.tap(inPage(byKey('po-status-filter')));
      await pick(h, 'Ordered');
      await openTab(h, 'Reorder');
      final reads = h.server.callsTo(PurT.reorder).length;

      await h.container.read(scopeProvider.notifier).setBranch(null);
      await h.settle();
      expect(ordersTable, findsOneWidget);
      expect(inPage(find.text('No items to reorder')), findsNothing);
      expect(button(tester, 'purchasing-new-order').onPressed, isNull);
      // The status filter was kept: the all-branches read asks for it.
      expect(
        h.server.callsTo(PurT.orders).last.path,
        '/purchasing/branches/$allBranchesId/orders',
      );
      expect(h.server.callsTo(PurT.orders).last.query['status'], ['ordered']);
      expect(h.server.callsTo(PurT.reorder).length, reads);

      await h.container.read(scopeProvider.notifier).setBranch(SeedIds.zamalek);
      await h.settle();
      expect(inPage(find.text('Create draft PO')), findsWidgets);
    });
  });

  group('orders table (INV-PUR-008…016, -058, -060, -064)', () {
    testWidgets('INV-PUR-009 / INV-PUR-058 / INV-PUR-064 columns with All '
        'branches: Reference, Branch, Supplier, Status, Expected, Created; '
        'newest first', (tester) async {
      final s = purchasingServer();
      final h = await pumpPurchasing(tester, server: s.server, db: s.db);
      for (final head in [
        'REFERENCE',
        'BRANCH',
        'SUPPLIER',
        'STATUS',
        'EXPECTED',
        'CREATED',
      ]) {
        expect(inOrders(find.text(head)), findsOneWidget, reason: head);
      }
      expect(shownRefs(tester, s.db), [
        'PO-1040',
        'PO-1043',
        shortRef(_po1044),
        'PO-1042',
        'PO-1041',
        'PO-1036',
        'PO-1039',
        'PO-1038',
        'PO-1037',
      ]);
      // PO-1044 has no reference: "#" + the first 8 of its id, left to right.
      final ref = tester.widget<MadarClippedText>(
        find.ancestor(
          of: exactText(ordersTable, shortRef(_po1044)),
          matching: find.byType(MadarClippedText),
        ),
      );
      expect(ref.textDirection, TextDirection.ltr);
      expect(inOrders(find.text('Zamalek')), findsNWidgets(3));
      final f = h.container.read(formatProvider);
      // Expected and created as dates; PO-1040 has no expected date.
      expect(inOrders(textHas(f.fmtDate('2026-10-07T15:10:00Z'))), findsWidgets);
      expect(inOrders(textHas('—')), findsWidgets);
    });

    testWidgets('INV-PUR-009 / INV-PUR-064 status pills: Open neutral, '
        'Ordered accent, Partially received warning, Received success, '
        'Cancelled danger', (tester) async {
      await pumpPurchasing(tester);
      final tones = <String, DashTone>{
        for (final p in tester.widgetList<DashStatusPill>(
          inOrders(find.byType(DashStatusPill)),
        ))
          p.label: p.tone,
      };
      expect(tones, {
        'Open': DashTone.neutral,
        'Ordered': DashTone.accent,
        'Partially received': DashTone.warning,
        'Received': DashTone.success,
        'Cancelled': DashTone.danger,
      });
    });

    testWidgets('INV-PUR-009 with a branch: no Branch column; an order with '
        'no supplier reads a muted "—"', (tester) async {
      final s = purchasingServer();
      s.db[InvTables.purchaseOrders].update(_po1042, {
        'supplier_id': null,
        'supplier_name': null,
      });
      await pumpPurchasing(
        tester,
        server: s.server,
        db: s.db,
        path: purchasingAt(SeedIds.zamalek),
      );
      expect(inOrders(find.text('BRANCH')), findsNothing);
      expect(inOrders(find.text('Zamalek')), findsNothing);
      expect(inOrders(find.text('Nile Roasters')), findsNothing);
      expect(inOrders(find.text('—')), findsWidgets);
    });

    testWidgets('INV-PUR-008 the status filter: All statuses + the five; a '
        'status re-reads with status=, All statuses omits it', (tester) async {
      final s = purchasingServer();
      final h = await pumpPurchasing(tester, server: s.server, db: s.db);
      expect(inPage(find.text('All statuses')), findsOneWidget);
      await h.tap(inPage(byKey('po-status-filter')));
      for (final label in [
        'Open',
        'Ordered',
        'Partially received',
        'Received',
        'Cancelled',
      ]) {
        expect(find.text(label).hitTestable(), findsWidgets, reason: label);
      }
      await pick(h, 'Received');
      final call = h.server.callsTo(PurT.orders).last;
      expect(call.query['status'], ['received']);
      expect(shownRefs(tester, s.db), ['PO-1036', 'PO-1039', 'PO-1037']);

      await h.tap(inPage(byKey('po-status-filter')));
      await pick(h, 'All statuses');
      // The all-statuses answer is still cached (under 30 s): served as it
      // is, as React Query would.
      final calls = h.server.callsTo(PurT.orders);
      expect(calls, hasLength(2));
      expect(calls.first.query.containsKey('status'), isFalse);
      expect(shownRefs(tester, s.db), hasLength(9));
    });

    testWidgets('INV-PUR-016 / INV-ALL-017 Columns lists the six columns '
        'and hides one', (tester) async {
      final h = await pumpPurchasing(tester);
      await h.tap(inPage(find.text('Columns')));
      for (final c in [
        'Reference',
        'Branch',
        'Supplier',
        'Status',
        'Expected',
        'Created',
      ]) {
        expect(find.text(c).hitTestable(), findsWidgets, reason: c);
      }
      await h.tap(find.text('Expected').hitTestable().last);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();
      expect(inOrders(find.text('EXPECTED')), findsNothing);
      expect(inOrders(find.text('CREATED')), findsOneWidget);
      // The actions stay.
      expect(inPage(byKey('po-menu-$_po1042')), findsOneWidget);
    });

    testWidgets('INV-PUR-025 (ALL-025) the orders table has no search box', (
      tester,
    ) async {
      await pumpPurchasing(tester);
      expect(inOrders(find.byType(DashSearchInput)), findsNothing);
    });

    testWidgets('INV-PUR-010 Place order on a draft: the submit, Order '
        'placed, the list re-read; the order is Ordered', (tester) async {
      final s = purchasingServer();
      final h = await pumpPurchasing(tester, server: s.server, db: s.db);
      // Only the draft offers it.
      expect(inPage(byKey('po-place-$_po1040')), findsOneWidget);
      for (final id in [_po1042, _po1041, _po1039, _po1038]) {
        expect(inPage(byKey('po-place-$id')), findsNothing);
      }
      final reads = h.server.callsTo(PurT.orders).length;
      await h.tap(inPage(byKey('po-place-$_po1040')));
      final post = h.server.callsTo(PurT.submit).single;
      expect(post.method, 'POST');
      expect(post.path, '/purchasing/orders/$_po1040/submit');
      await h.expectToast('Order placed');
      expect(s.db[InvTables.purchaseOrders].find(_po1040)!['status'], 'ordered');
      expect(h.server.callsTo(PurT.orders).length, greaterThan(reads));
      expect(inPage(byKey('po-place-$_po1040')), findsNothing);
      expect(receiveDialog, findsNothing, reason: 'the row did not open');
    });

    testWidgets('INV-PUR-010 the spinner shows on that row while placing', (
      tester,
    ) async {
      final s = purchasingServer();
      final gate = s.server.hold('POST', PurT.submit);
      final h = await pumpPurchasing(tester, server: s.server, db: s.db);
      await h.tap(inPage(byKey('po-place-$_po1040')));
      expect(button(tester, 'po-place-$_po1040').loading, isTrue);
      gate.release();
      await h.settle();
      await h.expectToast('Order placed');
    });

    testWidgets('INV-PUR-010 placing an order no longer a draft: the '
        'conflict\'s words', (tester) async {
      final s = purchasingServer();
      final h = await pumpPurchasing(tester, server: s.server, db: s.db);
      // Placed meanwhile on another screen.
      s.db[InvTables.purchaseOrders].update(_po1040, {'status': 'ordered'});
      await h.tap(inPage(byKey('po-place-$_po1040')));
      expect(h.server.callsTo(PurT.submit).single.status, 409);
      await h.expectToast(
        h.refusalWords(
          MockResponse.conflict(
            'Only a draft purchase order can be placed (submitted).',
          ),
        ),
      );
    });

    testWidgets('INV-PUR-011 / INV-PUR-065 Receive on draft and ordered, '
        'Receive remaining on partially received; none on received or '
        'cancelled', (tester) async {
      final h = await pumpPurchasing(tester);
      final draft = tester.widget<DashButton>(
        inPage(byKey('po-receive-$_po1040')),
      );
      expect(draft.label, 'Receive');
      expect(
        tester.widget<DashButton>(inPage(byKey('po-receive-$_po1042'))).label,
        'Receive',
      );
      expect(
        tester.widget<DashButton>(inPage(byKey('po-receive-$_po1041'))).label,
        'Receive remaining',
      );
      expect(inPage(byKey('po-receive-$_po1039')), findsNothing);
      expect(inPage(byKey('po-receive-$_po1038')), findsNothing);
      await h.tap(inPage(byKey('po-receive-$_po1041')));
      expect(receiveDialog, findsOneWidget);
      expect(
        h.server.callsTo(PurT.order).last.path,
        '/purchasing/orders/$_po1041',
      );
    });

    testWidgets('INV-PUR-012 More actions → View order opens the order; a '
        'received one is read-only', (tester) async {
      final h = await pumpPurchasing(tester);
      expect(
        tester
            .widget<DashIconButton>(
              find.descendant(
                of: inPage(byKey('po-menu-$_po1039')),
                matching: find.byType(DashIconButton),
              ),
            )
            .semanticLabel,
        'More actions',
      );
      await orderMenu(h, _po1039, 'View order');
      expect(receiveDialog, findsOneWidget);
      expect(inReceive(find.text('Receive order · PackRight Egypt')),
          findsOneWidget);
      expect(byKey('receive-submit'), findsNothing);
    });

    testWidgets('INV-PUR-013 Cancel order only on draft and ordered; the '
        'destructive confirm, then the cancel, Done, the list re-read', (
      tester,
    ) async {
      final s = purchasingServer();
      final h = await pumpPurchasing(tester, server: s.server, db: s.db);
      // Partially received: View order only.
      await h.tap(inPage(byKey('po-menu-$_po1041')));
      expect(find.text('View order').hitTestable(), findsOneWidget);
      expect(find.text('Cancel order').hitTestable(), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();

      await orderMenu(h, _po1042, 'Cancel order');
      expect(find.text('Cancel purchase order PO-1042?'), findsOneWidget);
      expect(
        find.text(
          'The supplier order is voided and nothing more can be received '
          'against it.',
        ),
        findsOneWidget,
      );
      // "Cancel" keeps the order.
      await h.tap(find.text('Cancel').hitTestable());
      expect(h.server.callsTo(PurT.cancel), isEmpty);

      final reads = h.server.callsTo(PurT.orders).length;
      await orderMenu(h, _po1042, 'Cancel order');
      await h.tap(find.text('Cancel order').hitTestable().last);
      expect(
        h.server.callsTo(PurT.cancel).single.path,
        '/purchasing/orders/$_po1042/cancel',
      );
      await h.expectToast('Done');
      expect(
        s.db[InvTables.purchaseOrders].find(_po1042)!['status'],
        'cancelled',
      );
      expect(h.server.callsTo(PurT.orders).length, greaterThan(reads));
      expect(receiveDialog, findsNothing);
    });

    testWidgets('INV-PUR-013 the title names an order with no reference by '
        'its short id; a 409 (stock already received) is a toast', (
      tester,
    ) async {
      final s = purchasingServer();
      final h = await pumpPurchasing(tester, server: s.server, db: s.db);
      // Received meanwhile.
      s.db[InvTables.purchaseOrders].update(_po1044, {
        'status': 'partially_received',
      });
      await orderMenu(h, _po1044, 'Cancel order');
      expect(
        find.text('Cancel purchase order ${shortRef(_po1044)}?'),
        findsOneWidget,
      );
      await h.tap(find.text('Cancel order').hitTestable().last);
      expect(h.server.callsTo(PurT.cancel).single.status, 409);
      await h.expectToast(
        h.refusalWords(
          MockResponse.conflict(
            'Cannot cancel a purchase order that has already received '
            'stock. Reverse the received goods (return to supplier / stock '
            'adjustment) first.',
          ),
        ),
      );
    });

    testWidgets('INV-PUR-014 / INV-ALL-020 a row click opens the order; Tab '
        'reaches a row and Enter opens it', (tester) async {
      final h = await pumpPurchasing(tester);
      await h.tap(exactText(ordersTable, 'PO-1043'));
      expect(receiveDialog, findsOneWidget);
      expect(
        h.server.callsTo(PurT.order).last.path,
        '/purchasing/orders/${PurIds.po('po-1043')}',
      );
      await h.tap(inReceive(find.text('Cancel')));
      expect(receiveDialog, findsNothing);

      await h.tap(inPage(byKey('po-status-filter')));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();
      final cell = tester.getCenter(exactText(ordersTable, 'PO-1040'));
      var reached = false;
      for (var i = 0; i < 20 && !reached; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await h.settle(rounds: 1);
        final focus = FocusManager.instance.primaryFocus;
        reached = focus != null && focus.rect.contains(cell);
      }
      expect(reached, isTrue, reason: 'Tab reaches the PO-1040 row');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await h.settle();
      expect(receiveDialog, findsOneWidget);
      expect(
        h.server.callsTo(PurT.order).last.path,
        '/purchasing/orders/$_po1040',
      );
    });

    testWidgets('INV-PUR-060 Place order, Receive and ⋯ never open the row', (
      tester,
    ) async {
      final h = await pumpPurchasing(tester);
      await h.tap(inPage(byKey('po-receive-$_po1042')));
      expect(receiveDialog, findsOneWidget);
      expect(h.server.callsTo(PurT.order), hasLength(1));
      await h.tap(inReceive(find.text('Cancel')));
      await h.tap(inPage(byKey('po-menu-$_po1042')));
      expect(receiveDialog, findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();
      await h.tap(inPage(byKey('po-place-$_po1040')));
      expect(receiveDialog, findsNothing);
      await h.expectToast('Order placed');
    });

    testWidgets('INV-PUR-015 / INV-ALL-018 loading: skeleton rows, then the '
        'orders', (tester) async {
      final s = purchasingServer();
      final gate = s.server.hold('GET', PurT.orders);
      final h = await pumpPurchasing(tester, server: s.server, db: s.db);
      expect(inOrders(find.byType(DashSkeleton)), findsWidgets);
      expect(inPage(find.text('No purchase orders yet')), findsNothing);
      gate.release();
      await h.settle();
      expect(inOrders(find.byType(DashSkeleton)), findsNothing);
      expect(inOrders(find.text('PO-1042')), findsOneWidget);
    });

    testWidgets('INV-PUR-015 / INV-ALL-018 error: "Couldn\'t load this", '
        'the server\'s words, Retry re-reads the orders only', (tester) async {
      final s = purchasingServer();
      final boom = MockResponse.error(500, 'The ledger is resting');
      s.server.fail('GET', PurT.orders, boom, times: null);
      final h = await pumpPurchasing(tester, server: s.server, db: s.db);
      expect(inPage(find.text("Couldn't load this")), findsOneWidget);
      expect(inPage(find.text(h.refusalWords(boom))), findsOneWidget);
      expect(inPage(find.text('No purchase orders yet')), findsNothing);
      expect(
        tester
            .widget<DashExportButton>(inPage(find.byType(DashExportButton)))
            .enabled,
        isFalse,
      );
      final sup = h.server.callsTo(PurT.suppliers).length;
      final cat = h.server.callsTo(PurT.catalog).length;
      s.server.clearFailures();
      await h.tap(inPage(find.text('Retry')));
      expect(inOrders(find.text('PO-1042')), findsOneWidget);
      expect(h.server.callsTo(PurT.suppliers).length, sup);
      expect(h.server.callsTo(PurT.catalog).length, cat);
    });

    testWidgets('INV-PUR-015 / INV-ALL-018 empty: "No purchase orders yet", '
        'Export off; a status with no orders shows the same words', (
      tester,
    ) async {
      final s = purchasingServer();
      s.db[InvTables.purchaseOrders].removeWhere(
        (po) => po['branch_id'] == SeedIds.zamalek && po['status'] != 'ordered',
      );
      final h = await pumpPurchasing(
        tester,
        server: s.server,
        db: s.db,
        path: purchasingAt(SeedIds.zamalek),
      );
      expect(inOrders(find.text('PO-1042')), findsOneWidget);
      await h.tap(inPage(byKey('po-status-filter')));
      await pick(h, 'Received');
      expect(inPage(find.text('No purchase orders yet')), findsOneWidget);
      expect(inPage(find.text('No results found')), findsNothing);
      expect(
        tester
            .widget<DashExportButton>(inPage(find.byType(DashExportButton)))
            .enabled,
        isFalse,
      );
    });

    testWidgets('INV-PUR-058 All branches: Branch column, New purchase order '
        'off, Reorder off; Place order, Receive and Cancel still work', (
      tester,
    ) async {
      final s = purchasingServer();
      final h = await pumpPurchasing(tester, server: s.server, db: s.db);
      expect(inOrders(find.text('BRANCH')), findsOneWidget);
      expect(button(tester, 'purchasing-new-order').onPressed, isNull);
      await h.tap(inPage(byKey('po-place-$_po1040')));
      await h.expectToast('Order placed');
      await h.tap(inPage(byKey('po-receive-$_po1041')));
      expect(receiveDialog, findsOneWidget);
      await h.tap(inReceive(find.text('Cancel')));
      await orderMenu(h, _po1042, 'Cancel order');
      await h.tap(find.text('Cancel order').hitTestable().last);
      await h.expectToast('Done');
    });
  });

  group('suppliers tab (INV-PUR-017…021, -059)', () {
    testWidgets('INV-PUR-018 / INV-PUR-059 columns, every supplier (the '
        'inactive one too), Active / Inactive pills', (tester) async {
      final s = purchasingServer();
      final h = await pumpPurchasing(tester, server: s.server, db: s.db);
      await openTab(h, 'Suppliers');
      for (final head in [
        'SUPPLIER',
        'CONTACT NAME',
        'EMAIL',
        'PHONE',
        'STATUS',
      ]) {
        expect(inSuppliers(find.text(head)), findsOneWidget, reason: head);
      }
      for (final sup in sabahSuppliers(s.db)) {
        expect(
          inSuppliers(find.text(sup['name']! as String)),
          findsOneWidget,
          reason: sup['name']! as String,
        );
      }
      expect(inSuppliers(find.text('omar@nileroasters.example')), findsNothing);
      expect(
        inSuppliers(find.text('orders@nileroasters.example')),
        findsOneWidget,
      );
      expect(inSuppliers(find.text('+20 100 111 2233')), findsOneWidget);
      final inactive = tester.widget<DashStatusPill>(
        inSuppliers(find.widgetWithText(DashStatusPill, 'Inactive')),
      );
      expect(inactive.tone, DashTone.neutral);
      expect(inactive.icon, 'minus-circle');
      final active = tester.widgetList<DashStatusPill>(
        inSuppliers(find.widgetWithText(DashStatusPill, 'Active')),
      );
      expect(active.length, sabahSuppliers(s.db).length - 1);
      expect(active.first.tone, DashTone.success);
    });

    testWidgets('INV-PUR-018 a supplier with no contact, email or phone '
        'reads "—"', (tester) async {
      final s = purchasingServer();
      s.db[InvTables.suppliers].update(PurIds.supplier('packright'), {
        'contact_name': null,
        'email': null,
        'phone': null,
      });
      final h = await pumpPurchasing(tester, server: s.server, db: s.db);
      await openTab(h, 'Suppliers');
      expect(inSuppliers(find.text('—')), findsNWidgets(3));
    });

    testWidgets('INV-PUR-017 / INV-ALL-021 search: name, contact, email, '
        'phone; no match shows "No suppliers yet"', (tester) async {
      final h = await pumpPurchasing(tester);
      await openTab(h, 'Suppliers');
      expect(
        inPage(find.widgetWithText(DashSearchInput, 'Search')),
        findsOneWidget,
      );
      Future<void> search(String q) =>
          h.enterText(inPage(find.byType(DashSearchInput)), q);
      List<String> names() => [
        for (final n in [
          'Cairo Fresh Produce',
          'Delta Dairy',
          'Golden Bakery Supply',
          'Metro Wholesale',
          'Nile Roasters',
          'PackRight Egypt',
        ])
          if (inSuppliers(find.text(n)).evaluate().isNotEmpty) n,
      ];
      await search('dairy');
      expect(names(), ['Delta Dairy']);
      await search('laila'); // Metro's contact
      expect(names(), ['Metro Wholesale']);
      await search('goldenbakery.example');
      expect(names(), ['Golden Bakery Supply']);
      await search('333 4455');
      expect(names(), ['Cairo Fresh Produce']);
      await search('nobody');
      expect(inPage(find.text('No suppliers yet')), findsOneWidget);
      expect(inPage(find.text('No results found')), findsNothing);
    });

    testWidgets('INV-PUR-019 ⋯ → Edit opens the supplier in edit mode', (
      tester,
    ) async {
      final h = await pumpPurchasing(tester);
      await openTab(h, 'Suppliers');
      await supplierMenu(h, PurIds.supplier('metro'), 'Edit');
      expect(inSupplier(find.text('Edit supplier')), findsOneWidget);
      expect(inputText(tester, 'supplier-name'), 'Metro Wholesale');
    });

    testWidgets('INV-PUR-020 ⋯ → Delete: the destructive confirm, then the '
        'delete, Done, the list re-read; past orders keep the name', (
      tester,
    ) async {
      final s = purchasingServer();
      final h = await pumpPurchasing(tester, server: s.server, db: s.db);
      await openTab(h, 'Suppliers');
      final id = PurIds.supplier('golden-bakery');
      await supplierMenu(h, id, 'Delete');
      expect(
        find.text('Delete supplier "Golden Bakery Supply"?'),
        findsOneWidget,
      );
      expect(
        find.text(
          'The supplier is removed from your list. Past purchase orders '
          'keep their records.',
        ),
        findsOneWidget,
      );
      await h.tap(find.text('Cancel').hitTestable());
      expect(h.server.callsTo(PurT.supplier, method: 'DELETE'), isEmpty);

      final reads = h.server.callsTo(PurT.suppliers).length;
      await supplierMenu(h, id, 'Delete');
      await h.tap(find.text('Delete').hitTestable().last);
      expect(
        h.server.callsTo(PurT.supplier, method: 'DELETE').single.path,
        '/purchasing/suppliers/$id',
      );
      await h.expectToast('Done');
      expect(h.server.callsTo(PurT.suppliers).length, greaterThan(reads));
      expect(inSuppliers(find.text('Golden Bakery Supply')), findsNothing);
      await openTab(h, 'Purchase orders');
      expect(inOrders(find.text('Golden Bakery Supply')), findsNWidgets(2));
    });

    testWidgets('INV-PUR-021 suppliers loading, then rows; no row click', (
      tester,
    ) async {
      final s = purchasingServer();
      final gate = s.server.hold('GET', PurT.suppliers);
      final h = await pumpPurchasing(tester, server: s.server, db: s.db);
      await openTab(h, 'Suppliers');
      expect(inSuppliers(find.byType(DashSkeleton)), findsWidgets);
      expect(inPage(find.text('No suppliers yet')), findsNothing);
      gate.release();
      await h.settle();
      await h.tap(inSuppliers(find.text('Delta Dairy')));
      expect(supplierDialog, findsNothing);
      expect(receiveDialog, findsNothing);
    });

    testWidgets('INV-PUR-021 suppliers error with Retry; empty "No '
        'suppliers yet"', (tester) async {
      final s = purchasingServer();
      final boom = MockResponse.error(500, 'Suppliers are resting');
      s.server.fail('GET', PurT.suppliers, boom, times: null);
      final h = await pumpPurchasing(tester, server: s.server, db: s.db);
      await openTab(h, 'Suppliers');
      expect(inPage(find.text("Couldn't load this")), findsOneWidget);
      expect(inPage(find.text(h.refusalWords(boom))), findsOneWidget);
      expect(
        tester
            .widget<DashExportButton>(inPage(find.byType(DashExportButton)))
            .enabled,
        isFalse,
      );
      s.server.clearFailures();
      s.db[InvTables.suppliers].removeWhere(
        (r) => r['org_id'] == SeedIds.sabahOrg,
      );
      await h.tap(inPage(find.text('Retry')));
      expect(inPage(find.text('No suppliers yet')), findsOneWidget);
    });
  });

  group('reorder tab (INV-PUR-023…027)', () {
    Future<DashHarness> openReorder(
      WidgetTester tester, {
      MockServer? server,
      MockDb? db,
    }) async {
      final h = await pumpPurchasing(
        tester,
        path: purchasingAt(SeedIds.zamalek),
        server: server,
        db: db,
      );
      await openTab(h, 'Reorder');
      return h;
    }

    testWidgets('INV-PUR-026 one group per supplier in the server\'s order: '
        'the name or "No supplier", the count, Name / On hand / Suggested '
        'qty', (tester) async {
      final s = purchasingServer();
      // Croissant Dough has no default supplier here: its own group.
      s.db[InvTables.ingredients].update(PurIds.ingredient('croissant'), {
        'supplier_id': null,
      });
      final croissant = s.db[InvTables.branchStock].firstWhere(
        (r) =>
            r['branch_id'] == SeedIds.zamalek &&
            r['org_ingredient_id'] == PurIds.ingredient('croissant'),
      )!;
      s.db[InvTables.branchStock].update(croissant['id']! as String, {
        'on_hand': 4.0,
        'par_min': 12.0,
        'par_max': 30.0,
      });
      final h = await openReorder(tester, server: s.server, db: s.db);
      final groups = h.container
          .read(reorderSuggestionsProvider(SeedIds.zamalek))
          .requireValue;
      expect(groups.length, greaterThan(1));
      expect(groups.last.supplierId, isNull, reason: 'NULLS LAST');
      final sections = tester
          .widgetList<DashSectionHeader>(
            inPage(find.byType(DashSectionHeader)),
          )
          .toList();
      expect([for (final x in sections) x.title], [
        for (final g in groups) g.supplierName ?? 'No supplier',
      ]);
      expect([for (final x in sections) x.count], [
        for (final g in groups) g.lines.length,
      ]);
      for (final head in ['NAME', 'ON HAND', 'SUGGESTED QTY']) {
        expect(
          inPage(find.text(head)),
          findsNWidgets(groups.length),
          reason: head,
        );
      }
      expect(inPage(find.text('Columns')), findsNothing);
      // 4 pcs on hand, 26 to reach 30.
      expect(inPage(find.text('Croissant Dough')), findsOneWidget);
      expect(inPage(textHas('26 pcs')), findsOneWidget);
      final onHand = tester.widget<Text>(
        inPage(
          find.byWidgetPredicate(
            (w) => w is Text && RegExp(r'(^|\D)4 pcs').hasMatch(w.data ?? ''),
          ),
        ),
      );
      final suggested = tester.widget<Text>(
        inPage(find.textContaining('26 pcs')),
      );
      expect(onHand.style?.color, isNot(suggested.style?.color));
    });

    testWidgets('INV-PUR-023 error: "Couldn\'t load reorder suggestions" + '
        'Retry, no server line', (tester) async {
      final s = purchasingServer();
      final boom = MockResponse.error(500, 'Suggestions are resting');
      s.server.fail('GET', PurT.reorder, boom, times: null);
      final h = await openReorder(tester, server: s.server, db: s.db);
      expect(
        inPage(find.text("Couldn't load reorder suggestions")),
        findsOneWidget,
      );
      expect(inPage(find.text(h.refusalWords(boom))), findsNothing);
      s.server.clearFailures();
      final reads = h.server.callsTo(PurT.orders).length;
      await h.tap(inPage(find.text('Retry')));
      expect(inPage(find.text('Create draft PO')), findsWidgets);
      expect(h.server.callsTo(PurT.orders).length, reads);
    });

    testWidgets('INV-PUR-024 loading: a heading bar and a skeleton table', (
      tester,
    ) async {
      final s = purchasingServer();
      final gate = s.server.hold('GET', PurT.reorder);
      final h = await openReorder(tester, server: s.server, db: s.db);
      expect(inPage(find.byType(DashSkeleton)), findsWidgets);
      expect(inPage(find.text('No items to reorder')), findsNothing);
      gate.release();
      await h.settle();
      expect(inPage(find.text('Create draft PO')), findsWidgets);
    });

    testWidgets('INV-PUR-025 empty: "No items to reorder" and the hint', (
      tester,
    ) async {
      final s = purchasingServer();
      for (final r in s.db[InvTables.branchStock].where(
        (r) => r['branch_id'] == SeedIds.zamalek,
      )) {
        s.db[InvTables.branchStock].update(r['id']! as String, {
          'par_min': null,
        });
      }
      await openReorder(tester, server: s.server, db: s.db);
      expect(inPage(find.text('No items to reorder')), findsOneWidget);
      expect(
        inPage(find.text('All stocked items are above their reorder point.')),
        findsOneWidget,
      );
    });
  });

  group('exports (INV-PUR-006, -007, INV-ALL-012, -013)', () {
    testWidgets('INV-PUR-006 orders: the filtered list, five columns, the '
        'file name and the toasts', (tester) async {
      final s = purchasingServer();
      final h = await pumpPurchasing(tester, server: s.server, db: s.db);
      await h.tap(inPage(byKey('po-status-filter')));
      await pick(h, 'Ordered');
      await h.tap(inPage(byKey('purchasing-export')));
      await h.expectToast('Exported 3 rows');
      final sheet = h.exports.built.single.sheets.single;
      expect(sheet.name, 'Purchase orders');
      expect(sheet.title, 'Purchase orders');
      expect([for (final c in sheet.columns) c.header], [
        'Reference',
        'Supplier',
        'Status',
        'Expected',
        'Created',
      ]);
      expect(sheet.columns.first.width, 20);
      expect([for (final r in sheet.rows) r.first], [
        'PO-1043',
        shortRef(_po1044),
        'PO-1042',
      ]);
      expect([for (final r in sheet.rows) r[2]], everyElement('Ordered'));
      expect(sheet.rows.first[1], 'Nile Roasters');
      expect(
        h.files.saved.single.filename,
        'Madar-PurchaseOrders-2026-10-08.xlsx',
      );
    });

    testWidgets('INV-PUR-006 an order with no supplier exports "—", with no '
        'expected date a blank cell', (tester) async {
      final s = purchasingServer();
      s.db[InvTables.purchaseOrders].update(_po1040, {
        'supplier_id': null,
        'supplier_name': null,
      });
      final h = await pumpPurchasing(tester, server: s.server, db: s.db);
      await h.tap(inPage(byKey('purchasing-export')));
      await h.expectToast('Exported 9 rows');
      final row = h.exports.built.single.sheets.single.rows.first;
      expect(row[0], 'PO-1040');
      expect(row[1], '—');
      expect(row[2], 'Open');
      expect(row[3], anyOf(isNull, ''));
      expect(row[4], isNotNull);
    });

    testWidgets('INV-PUR-007 suppliers (from Suppliers and from Reorder): '
        'five columns, Active / Inactive', (tester) async {
      final s = purchasingServer();
      final h = await pumpPurchasing(
        tester,
        server: s.server,
        db: s.db,
        path: purchasingAt(SeedIds.zamalek),
      );
      await openTab(h, 'Suppliers');
      await h.tap(inPage(byKey('purchasing-export')));
      final n = sabahSuppliers(s.db).length;
      await h.expectToast('Exported $n rows');
      var sheet = h.exports.built.last.sheets.single;
      expect(sheet.name, 'Suppliers');
      expect([for (final c in sheet.columns) c.header], [
        'Supplier',
        'Contact name',
        'Email',
        'Phone',
        'Status',
      ]);
      expect(sheet.columns.first.width, 26);
      final cairo = sheet.rows.firstWhere(
        (r) => r.first == 'Cairo Fresh Produce',
      );
      expect(cairo.last, 'Inactive');
      expect(
        sheet.rows.firstWhere((r) => r.first == 'Delta Dairy'),
        [
          'Delta Dairy',
          'Mona Adel',
          'sales@deltadairy.example',
          '+20 100 222 3344',
          'Active',
        ],
      );
      expect(h.files.saved.last.filename, 'Madar-Suppliers-2026-10-08.xlsx');

      await openTab(h, 'Reorder');
      await h.tap(inPage(byKey('purchasing-export')));
      await h.expectToast('Exported $n rows');
      sheet = h.exports.built.last.sheets.single;
      expect(sheet.name, 'Suppliers');
    });

    testWidgets('INV-PUR-007 a supplier with no contact exports "—"', (
      tester,
    ) async {
      final s = purchasingServer();
      s.db[InvTables.suppliers].update(PurIds.supplier('metro'), {
        'contact_name': null,
        'email': null,
        'phone': null,
      });
      final h = await pumpPurchasing(tester, server: s.server, db: s.db);
      await openTab(h, 'Suppliers');
      await h.tap(inPage(byKey('purchasing-export')));
      await h.flushTimers();
      final metro = h.exports.built.single.sheets.single.rows.firstWhere(
        (r) => r.first == 'Metro Wholesale',
      );
      expect(metro.sublist(1, 4), ['—', '—', '—']);
    });

    testWidgets('INV-ALL-012 / INV-ALL-013 spinner while exporting; '
        '"Export failed" on a failure', (tester) async {
      final h = await pumpPurchasing(tester);
      final hold = Completer<void>();
      h.exports.hold = hold.future;
      await h.tap(inPage(byKey('purchasing-export')));
      expect(find.text('Gathering data…'), findsOneWidget);
      expect(
        tester
            .widget<DashExportButton>(inPage(find.byType(DashExportButton)))
            .loading,
        isTrue,
      );
      hold.complete();
      h.exports.hold = null;
      await h.settle();
      await h.flushTimers();
      h.exports.failNext = StateError('disk full');
      await h.tap(inPage(byKey('purchasing-export')));
      await h.expectToast('Export failed');
    });
  });

  group('phone (INV-PUR-061, INV-ALL-019)', () {
    testWidgets('INV-PUR-061 orders are cards: the reference leads, the '
        'labelled grid, the buttons and ⋯ inside; no Columns menu', (
      tester,
    ) async {
      final h = await pumpPurchasing(tester, size: DashSize.phone);
      expect(inPage(find.text('Columns')), findsNothing);
      final card = byKey('po-card-$_po1041');
      await h.scrollUntilVisible(card);
      for (final label in [
        'Branch',
        'Supplier',
        'Status',
        'Expected',
        'Created',
      ]) {
        expect(
          find.descendant(of: card, matching: find.text(label)),
          findsOneWidget,
          reason: label,
        );
      }
      expect(
        find.descendant(of: card, matching: find.text('Receive remaining')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: byKey('po-menu-$_po1041')),
        findsOneWidget,
      );
      expect(find.text('actions'), findsNothing);
      await h.tap(find.descendant(of: card, matching: find.text('PO-1041')));
      expect(receiveDialog, findsOneWidget);
    });

    testWidgets('INV-PUR-061 suppliers are cards with the name as title', (
      tester,
    ) async {
      final h = await pumpPurchasing(tester, size: DashSize.phone);
      await openTab(h, 'Suppliers');
      expect(inSuppliers(find.text('Delta Dairy')), findsOneWidget);
      expect(inSuppliers(find.text('Contact name')), findsWidgets);
      expect(inPage(find.text('Columns')), findsNothing);
      await h.tap(inPage(byKey('supplier-menu-${PurIds.supplier('metro')}')));
      expect(find.text('Edit').hitTestable(), findsOneWidget);
    });
  });

  group('gating (INV-PUR-062, INV-ALL-002…006)', () {
    testWidgets('INV-PUR-062 no control is hidden by capability: a manager '
        'sees New supplier, Edit and Delete; the server refuses them', (
      tester,
    ) async {
      final s = purchasingServer(persona: Persona.manager);
      final h = await pumpPurchasing(
        tester,
        persona: Persona.manager,
        server: s.server,
        db: s.db,
      );
      await openTab(h, 'Suppliers');
      final id = PurIds.supplier('metro');
      await supplierMenu(h, id, 'Delete');
      await h.tap(find.text('Delete').hitTestable().last);
      expect(
        h.server.callsTo(PurT.supplier, method: 'DELETE').single.status,
        403,
      );
      await h.expectToast(
        h.refusalWords(MockResponse.denied('purchasing.suppliers.delete')),
      );
      expect(inSuppliers(find.text('Metro Wholesale')), findsOneWidget);
    });

    testWidgets('INV-PUR-062 only purchasing.suppliers.read: the Orders tab '
        'still shows, its read refused into the table\'s error', (
      tester,
    ) async {
      final s = purchasingServer();
      final denied = MockResponse.denied('purchasing.orders.read');
      s.server.fail('GET', PurT.orders, denied, times: null);
      final h = await pumpPurchasing(tester, server: s.server, db: s.db);
      expect(inPage(find.text("Couldn't load this")), findsOneWidget);
      expect(inPage(find.text(h.refusalWords(denied))), findsOneWidget);
      await openTab(h, 'Suppliers');
      expect(inSuppliers(find.text('Delta Dairy')), findsOneWidget);
    });

    testWidgets('INV-ALL-002 a manager (orders and suppliers read) sees the '
        'Purchasing leaf; Zamalek\'s orders only', (tester) async {
      await pumpPurchasing(tester, persona: Persona.manager);
      expect(
        find.descendant(
          of: find.byType(DashSidebar),
          matching: find.text('Purchasing'),
        ),
        findsOneWidget,
      );
      expect(inOrders(find.text('PO-1042')), findsOneWidget);
      expect(inOrders(find.text('PO-1043')), findsNothing);
    });

    testWidgets('INV-ALL-002 / INV-ALL-006 (divergence) without either read '
        'capability: no leaf, no palette entry, the shell\'s Restricted and '
        'nothing read', (tester) async {
      final h = await pumpPurchasing(tester, persona: Persona.limited);
      expect(
        find.descendant(
          of: find.byType(DashSidebar),
          matching: find.text('Purchasing'),
        ),
        findsNothing,
      );
      expect(find.byType(Restricted), findsOneWidget);
      expect(page, findsNothing);
      expect(h.server.callsTo(PurT.orders), isEmpty);
      await openPalette(h, 'Purchas');
      expect(
        find.descendant(
          of: find.byType(DashCommandPalette),
          matching: find.text('Purchasing'),
        ),
        findsNothing,
      );
    });

    testWidgets('INV-ALL-004 the palette lists Purchasing', (tester) async {
      final h = await pumpPurchasing(tester, persona: Persona.manager);
      await openPalette(h, 'Purchas');
      expect(
        find.descendant(
          of: find.byType(DashCommandPalette),
          matching: find.text('Purchasing'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('INV-ALL-005 module gate: a Dawam-only business sees "Not '
        'part of this business\'s plan"', (tester) async {
      final h = await pumpPurchasing(tester, persona: Persona.dawamOnly);
      expect(page, findsNothing);
      expect(find.text(h.t('dawam.moduleOffTitle')), findsOneWidget);
      expect(h.server.callsTo(PurT.orders), isEmpty);
    });

    testWidgets('INV-ALL-015 a realtime resync re-reads the orders and the '
        'suppliers', (tester) async {
      final h = await pumpPurchasing(
        tester,
        path: purchasingAt(SeedIds.zamalek),
      );
      final o = h.server.callsTo(PurT.orders).length;
      final sup = h.server.callsTo(PurT.suppliers).length;
      h.realtime.current!.emit('resync');
      await h.settle();
      expect(h.server.callsTo(PurT.orders).length, o + 1);
      expect(h.server.callsTo(PurT.suppliers).length, sup + 1);
    });
  });
}
