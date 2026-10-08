// Today's dialogs driven end to end through the real app shell: Create PO
// and Receive opened from Today, submitted against the mock backend, and
// Today refreshed afterwards (INV-TOD-013, -018, -028, -029, -033); a
// refusal from the server reads as its words in a toast with the dialog
// left open (INV-ALL-011, INV-TOD-033). And Today's in-page links keep the
// scope (INV-ALL-024, logged in docs/fdash/divergences/inventory-today.md).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:dashboard_inventory/src/purchasing/purchase_order_dialog.dart';
import 'package:dashboard_inventory/src/purchasing/receive_dialog.dart';
import 'package:dashboard_inventory/src/today/today_parts.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const String _createOrder = '/purchasing/branches/{branch_id}/orders';
const String _getOrder = '/purchasing/orders/{id}';
const String _receive = '/purchasing/orders/{id}/receive';

/// Every read Today makes with a branch picked (the four families
/// `invalidateInventory` refreshes).
const List<String> _branchReads = [
  branchValuation,
  branchLow,
  orgOrders,
  suppliersRoute,
  catalogRoute,
  stockRoute,
  stocktakesRoute,
  wasteRoute,
];

Map<String, int> _callCounts(DashHarness h) => {
  for (final r in _branchReads) r: h.server.callsTo(r).length,
};

Finder _inside<T>(Finder matching) =>
    find.descendant(of: find.byType(T), matching: matching);

void main() {
  group('Create PO (INV-TOD-013, INV-TOD-028)', () {
    testWidgets(
      'INV-TOD-028 placed for the row\'s branch with the prefill; Today refreshes',
      (tester) async {
        final s = todayServer();
        final h = await pumpToday(
          tester,
          server: s.server,
          db: s.db,
          branch: SeedIds.zamalek,
        );
        final before = _callCounts(h);
        final ordersBefore = s.db[InvTables.purchaseOrders].length;
        final oat = InvIds.ingredient('oat');

        await h.tap(byKey('today-create-po-${SeedIds.zamalek}-$oat'));
        expect(find.byType(PurchaseOrderDialog), findsOneWidget);
        // The supplier and catalog come from what Today already read: the
        // dialog asks for nothing more before it can be sent.
        expect(h.server.callsTo(suppliersRoute).length, before[suppliersRoute]);
        expect(h.server.callsTo(catalogRoute).length, before[catalogRoute]);

        await h.tap(byKey('po-submit'));

        final post = h.server.callsTo(_createOrder).single;
        expect(post.method, 'POST');
        expect(post.path, '/purchasing/branches/${SeedIds.zamalek}/orders');
        expect(post.status, 201);
        final body = post.body! as Map<String, Object?>;
        expect(body['supplier_id'], InvIds.supplier('metro'));
        final line = (body['lines']! as List).single as Map<String, Object?>;
        expect(line['org_ingredient_id'], oat);
        // max(1, ceil(9,350 suggested)) millilitres, in the stock unit.
        expect(line['quantity_ordered'], 9350);
        expect(line['purchase_unit'], 'ml');
        // The total is the catalog estimate for the quantity (INV-PUR-036).
        final cost = ingredientRow(s.db, 'oat')['cost_per_unit']! as num;
        expect(line['line_cost'], (cost * 9350).round());

        await h.expectToast('New purchase order');
        expect(find.byType(PurchaseOrderDialog), findsNothing);
        expect(s.db[InvTables.purchaseOrders].length, ordersBefore + 1);

        // invalidateInventory: every read of the four families again.
        for (final r in [
          branchValuation,
          branchLow,
          orgOrders,
          stockRoute,
          stocktakesRoute,
          wasteRoute,
        ]) {
          expect(
            h.server.callsTo(r).length,
            greaterThan(before[r]!),
            reason: r,
          );
        }
        // A new order is a draft: not on its way yet (INV-TOD-034).
        expect(kpi(tester, 'Deliveries').value, 3);
      },
    );

    testWidgets(
      'INV-TOD-028 with all branches the order goes to the row\'s branch',
      (tester) async {
        final s = todayServer();
        final h = await pumpToday(tester, server: s.server, db: s.db);
        final sugar = InvIds.ingredient('sugar');
        await h.tap(byKey('today-create-po-${SeedIds.newCairo}-$sugar'));
        await h.tap(byKey('po-submit'));
        expect(
          h.server.callsTo(_createOrder).single.path,
          '/purchasing/branches/${SeedIds.newCairo}/orders',
        );
        await h.expectToast('New purchase order');
        expect(
          h.server.callsTo(orgLow).length,
          greaterThan(1),
          reason: 'the org roll-up refreshes too',
        );
      },
    );

    testWidgets(
      'INV-TOD-033 a refusal: the server\'s words in a toast, dialog kept',
      (tester) async {
        final s = todayServer(persona: Persona.manager);
        s.server.fail(
          'POST',
          _createOrder,
          MockResponse.denied('purchasing.orders.create'),
        );
        final h = await pumpToday(
          tester,
          persona: Persona.manager,
          server: s.server,
          db: s.db,
          branch: SeedIds.zamalek,
        );
        final ordersBefore = s.db[InvTables.purchaseOrders].length;
        final oat = InvIds.ingredient('oat');
        await h.tap(byKey('today-create-po-${SeedIds.zamalek}-$oat'));
        await h.tap(byKey('po-submit'));
        expect(h.server.callsTo(_createOrder).single.status, 403);
        await h.expectToast(
          "Forbidden: You don't have permission to do this: "
          'Create purchase orders (purchasing.orders.create)',
        );
        expect(find.byType(PurchaseOrderDialog), findsOneWidget);
        expect(s.db[InvTables.purchaseOrders].length, ordersBefore);
        // The line is still there to send again.
        expect(
          tester.widget<DashButton>(byKey('po-submit')).onPressed,
          isNotNull,
        );
      },
    );

    testWidgets('INV-TOD-033 a 403 in Arabic keeps the Arabic UI around it', (
      tester,
    ) async {
      final s = todayServer();
      s.server.fail(
        'POST',
        _createOrder,
        MockResponse.forbidden('هذا الإجراء غير مسموح لك'),
      );
      final h = await pumpToday(
        tester,
        server: s.server,
        db: s.db,
        branch: SeedIds.zamalek,
        locale: 'ar',
      );
      final oat = InvIds.ingredient('oat');
      await h.tap(byKey('today-create-po-${SeedIds.zamalek}-$oat'));
      await h.tap(byKey('po-submit'));
      await h.expectToast('Forbidden: هذا الإجراء غير مسموح لك');
      expect(find.byType(PurchaseOrderDialog), findsOneWidget);
    });
  });

  group('Receive (INV-TOD-018, INV-TOD-029)', () {
    testWidgets(
      'INV-TOD-029 receiving what is left books it; the order leaves the list',
      (tester) async {
        final s = todayServer();
        final h = await pumpToday(
          tester,
          server: s.server,
          db: s.db,
          branch: SeedIds.zamalek,
        );
        final before = _callCounts(h);
        final valueBefore = stockValue(s.db, [SeedIds.zamalek]).total;
        expect(kpi(tester, 'Stock value').value, valueBefore);
        final po = InvIds.purchaseOrder('po-1042');

        await h.tap(byKey('today-receive-$po'));
        expect(find.byType(ReceiveDialog), findsOneWidget);
        expect(h.server.callsTo(_getOrder).last.path, '/purchasing/orders/$po');

        await h.tap(byKey('receive-submit'));

        final post = h.server.callsTo(_receive).single;
        expect(post.path, '/purchasing/orders/$po/receive');
        expect(post.status, 200);
        final lines = [
          for (final l
              in (post.body! as Map<String, Object?>)['lines']! as List)
            l as Map<String, Object?>,
        ];
        final seeded = {
          for (final l in s.db[InvTables.poLines].where(
            (r) => r['purchase_order_id'] == po,
          ))
            l['id']! as String: l,
        };
        expect(lines.map((l) => l['line_id']).toSet(), seeded.keys.toSet());
        // Each line receives what was ordered (nothing came in before).
        for (final l in lines) {
          expect(
            l['quantity_received'],
            seeded[l['line_id']]!['quantity_ordered'],
          );
        }

        await h.settle();
        expect(find.byType(ReceiveDialog), findsNothing);
        expect(s.db[InvTables.purchaseOrders].find(po)!['status'], 'received');
        for (final r in [branchValuation, branchLow, orgOrders, stockRoute]) {
          expect(
            h.server.callsTo(r).length,
            greaterThan(before[r]!),
            reason: r,
          );
        }
        // Two left on their way; PO-1042 is gone from the list.
        expect(kpi(tester, 'Deliveries').value, 2);
        expect(_inside<TodayArrivingSection>(textHas('PO-1042')), findsNothing);
        // The beans are on the shelf: the stock value moved with them.
        final valueAfter = stockValue(s.db, [SeedIds.zamalek]).total;
        expect(valueAfter, greaterThan(valueBefore));
        expect(kpi(tester, 'Stock value').value, valueAfter);
        await h.flushTimers();
      },
    );

    testWidgets(
      'INV-TOD-033 a refused receipt: the server\'s words, dialog kept',
      (tester) async {
        final s = todayServer();
        s.server.fail(
          'POST',
          _receive,
          MockResponse.denied('purchasing.orders.edit'),
        );
        final h = await pumpToday(tester, server: s.server, db: s.db);
        final po = InvIds.purchaseOrder('po-1042');
        await h.tap(byKey('today-receive-$po'));
        await h.tap(byKey('receive-submit'));
        await h.expectToast(
          "Forbidden: You don't have permission to do this: "
          'Approve and receive purchase orders (purchasing.orders.edit)',
        );
        expect(find.byType(ReceiveDialog), findsOneWidget);
        expect(s.db[InvTables.purchaseOrders].find(po)!['status'], 'ordered');
        expect(kpi(tester, 'Deliveries').value, 3);
      },
    );

    testWidgets(
      'INV-TOD-029 an order received elsewhere meanwhile: the conflict words',
      (tester) async {
        final s = todayServer();
        final h = await pumpToday(tester, server: s.server, db: s.db);
        final po = InvIds.purchaseOrder('po-1044');
        await h.tap(byKey('today-receive-$po'));
        // Someone at the branch cancels it while the dialog is open.
        s.db[InvTables.purchaseOrders].update(po, {'status': 'cancelled'});
        await h.tap(byKey('receive-submit'));
        expect(h.server.callsTo(_receive).single.status, 409);
        expect(find.byType(ReceiveDialog), findsOneWidget);
        await h.expectToast(
          'Conflict: Purchase order is already received or cancelled',
        );
      },
    );
  });

  group('scope kept by in-page links (INV-ALL-024)', () {
    testWidgets('View all opens Ingredients on the same branch', (
      tester,
    ) async {
      final h = await pumpToday(tester, branch: SeedIds.zamalek);
      h.allowUnmatched = true;
      await h.tap(byKey('today-view-all'));
      expect(h.location.path, '/inventory/ingredients');
      expect(h.container.read(scopeProvider).branchId, SeedIds.zamalek);
    });

    testWidgets('the first-count button opens Counts on the same branch', (
      tester,
    ) async {
      final h = await pumpToday(tester, branch: SeedIds.heliopolis);
      h.allowUnmatched = true;
      await h.tap(byKey('today-first-count'));
      expect(h.location.path, '/inventory/counts');
      expect(h.container.read(scopeProvider).branchId, SeedIds.heliopolis);
    });
  });
}
