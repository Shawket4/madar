// The owner's rule (2026-10-11): a filter carries through navigation. An
// inventory page left for another and opened again shows the same filter,
// tab and status (`DashRememberedState`).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ingredients/support.dart' as ing;
import '../purchasing/support.dart' as pur;
import '../transfers/support.dart' as trf;

/// The ingredient names the table shows.
Set<String> _shown(MockDb db) => {
  for (final r in db[InvTables.ingredients].rows)
    if (ing.inTable(find.text(r['name']! as String)).evaluate().isNotEmpty)
      r['name']! as String,
};

void main() {
  testWidgets('Ingredients: the stock filter comes back', (tester) async {
    final s = ing.ingredientsServer();
    final h = await ing.pumpIngredients(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.zamalek,
    );
    await h.tap(ing.inPage(find.text('Never counted')));
    final never = _shown(s.db);
    expect(never, contains('Chai Spice Mix'));
    expect(find.text('Page 1 of 3'), findsNothing);
    await h.go('/inventory/settings');
    await h.go(ing.ingredientsPath);
    expect(_shown(s.db), never);
    expect(find.text('Page 1 of 3'), findsNothing);
  });

  testWidgets('Purchasing: the tab and the status filter come back', (
    tester,
  ) async {
    final s = pur.purchasingServer();
    final h = await pur.pumpPurchasing(tester, server: s.server, db: s.db);
    await h.tap(pur.inPage(pur.byKey('po-status-filter')));
    await pur.pick(h, 'Received');
    expect(h.server.callsTo(pur.PurT.orders).last.query['status'], [
      'received',
    ]);
    await h.go('/inventory/settings');
    await h.go(pur.purchasingPath);
    expect(h.server.callsTo(pur.PurT.orders).last.query['status'], [
      'received',
    ]);
    expect(pur.inPage(find.text('All statuses')), findsNothing);

    await pur.openTab(h, 'Suppliers');
    expect(pur.suppliersTable, findsOneWidget);
    await h.go('/inventory/settings');
    await h.go(pur.purchasingPath);
    expect(pur.suppliersTable, findsOneWidget);
    expect(pur.ordersTable, findsNothing);
  });

  testWidgets('Transfers: the direction and the status tab come back', (
    tester,
  ) async {
    final h = await trf.pumpTransfers(tester, branch: SeedIds.zamalek);
    await h.tap(trf.inPage(find.text('Outgoing')));
    await h.tap(trf.inPage(find.text('Received')));
    expect(h.server.callsTo(trf.listRoute).last.query, {
      'direction': ['outgoing'],
      'status': ['received'],
    });
    await h.go('/inventory/settings');
    await h.go(trf.transfersPath);
    expect(h.server.callsTo(trf.listRoute).last.query, {
      'direction': ['outgoing'],
      'status': ['received'],
    });
  });
}
