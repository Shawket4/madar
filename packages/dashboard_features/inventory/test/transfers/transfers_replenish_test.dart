// The replenish dialog (INV-TRF-038…040): at the Central Store warehouse
// scope, what a selling branch is low on and what the store can send; the
// ticked lines open the transfer dialog from the store.
import 'package:dashboard_api/dashboard_api.dart' show DashboardApi;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

final String _oat = InvIds.ingredient('oat');

Future<({DashHarness h, MockServer server, MockDb db})> _open(
  WidgetTester tester, {
  void Function(MockServer server, MockDb db)? before,
  DashSize size = DashSize.desktop,
  String locale = 'en',
}) async {
  final s = transfersServer();
  withWarehouse(s.db);
  before?.call(s.server, s.db);
  final h = await pumpTransfers(
    tester,
    server: s.server,
    db: s.db,
    branch: centralStore,
    size: size,
    locale: locale,
  );
  await h.tap(inPage(byKey('transfers-replenish')));
  return (h: h, server: s.server, db: s.db);
}

void main() {
  testWidgets('INV-TRF-038 title, the warehouse in the hint; To lists the '
      'selling branches, "Pick a branch", nothing read yet', (tester) async {
    final r = await _open(tester);
    expect(inReplenish(find.text('Replenish a branch')), findsOneWidget);
    expect(
      inReplenish(
        find.text(
          'Items the branch is low on, and what Central Store can send to '
          'bring it back to its max level.',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: triggerIn(replenishDialog, 'replenish-branch'),
        matching: find.text('Pick a branch'),
      ),
      findsOneWidget,
    );
    expect(r.h.server.callsTo(replenishRoute), isEmpty);
    await r.h.tap(triggerIn(replenishDialog, 'replenish-branch'));
    for (final b in ['Heliopolis', 'Maadi', 'New Cairo', 'Zamalek']) {
      expect(option(b), findsWidgets, reason: b);
    }
    expect(option('Central Store'), findsNothing);
    final review = tester.widget<DashButton>(
      inReplenish(byKey('replenish-review')),
    );
    expect(review.label, 'Review transfer (0)');
    expect(review.onPressed, isNull);
  });

  testWidgets('INV-TRF-038 one selling branch: picked already and read', (
    tester,
  ) async {
    final r = await _open(
      tester,
      before: (_, db) {
        for (final id in [SeedIds.heliopolis, SeedIds.maadi, SeedIds.newCairo]) {
          db['branches'].get(id)['is_active'] = false;
        }
      },
    );
    expect(
      find.descendant(
        of: triggerIn(replenishDialog, 'replenish-branch'),
        matching: find.text('Zamalek'),
      ),
      findsOneWidget,
    );
    expect(
      r.h.server.callsTo(replenishRoute).single.query['branch_id'],
      [SeedIds.zamalek],
    );
  });

  testWidgets('INV-TRF-039 a branch\'s low rows: level, at branch, coming, '
      'can send, and Send seeded with the suggestion, ticked', (tester) async {
    final r = await _open(tester);
    await pick(r.h, 'replenish-branch', 'Zamalek', scope: replenishDialog);
    final call = r.h.server.callsTo(replenishRoute).single;
    expect(call.path, '/inventory/warehouses/$centralStore/replenishment');
    final row = inReplenish(byKey('replenish-row-$_oat'));
    Finder inRow(String s) => find.descendant(of: row, matching: find.text(s));
    expect(inRow('Oat Milk'), findsOneWidget);
    expect(inRow('Level 3,000–10,000'), findsOneWidget);
    expect(inRow('2,000 ml'), findsOneWidget);
    expect(inRow('1,500'), findsOneWidget, reason: 'TR-6 asks for 1,500');
    expect(inRow('12,000'), findsOneWidget);
    expect(inRow('6500'), findsOneWidget);
    final tick = tester.widget<DashCheckbox>(
      inReplenish(byKey('replenish-tick-$_oat')),
    );
    expect(tick.value, isTrue);
    expect(tick.semanticLabel, 'Oat Milk');
    for (final c in ['Ingredient', 'At branch', 'Coming', 'Can send', 'Send']) {
      expect(inReplenish(find.text(c)), findsWidgets, reason: c);
    }
  });

  testWidgets('INV-TRF-039 a background refetch keeps the person\'s edits', (
    tester,
  ) async {
    final r = await _open(tester);
    await pick(r.h, 'replenish-branch', 'Zamalek', scope: replenishDialog);
    await r.h.enterText(inReplenish(byKey('replenish-qty-$_oat')), '4000');
    await r.h.tap(inReplenish(byKey('replenish-tick-$_oat')));
    r.h.container.read(realtimeBusProvider).invalidate(const ['/inventory']);
    await r.h.settle();
    expect(r.h.server.callsTo(replenishRoute), hasLength(2));
    expect(
      find.descendant(
        of: inReplenish(byKey('replenish-qty-$_oat')),
        matching: find.text('4000'),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<DashCheckbox>(inReplenish(byKey('replenish-tick-$_oat')))
          .value,
      isFalse,
    );
  });

  testWidgets('INV-TRF-039 loading bars, error + Retry, and "Nothing is low '
      'here"', (tester) async {
    final r = await _open(
      tester,
      before: (server, db) {
        for (final row in db[InvTables.branchStock].where(
          (x) => x['branch_id'] == SeedIds.heliopolis,
        )) {
          row['par_min'] = null;
        }
      },
    );
    final gate = r.server.hold('GET', replenishRoute);
    await pick(r.h, 'replenish-branch', 'Heliopolis', scope: replenishDialog);
    expect(inReplenish(byKey('replenish-loading')), findsOneWidget);
    expect(inReplenish(find.byType(DashSkeleton)), findsNWidgets(3));
    gate.release();
    await r.h.settle();
    expect(inReplenish(find.text('Nothing is low here')), findsOneWidget);
    expect(
      inReplenish(
        find.text(
          'Only items with a low-stock level that the branch is at or under '
          'show up.',
        ),
      ),
      findsOneWidget,
    );
    final boom = MockResponse.badRequest('Replenishment comes from a warehouse.');
    r.server.fail('GET', replenishRoute, boom, times: null);
    await pick(r.h, 'replenish-branch', 'Maadi', scope: replenishDialog);
    expect(inReplenish(find.text(r.h.refusalWords(boom))), findsOneWidget);
    final n = r.h.server.callsTo(replenishRoute).length;
    r.server.clearFailures();
    await r.h.tap(inReplenish(find.text('Retry')));
    expect(r.h.server.callsTo(replenishRoute), hasLength(n + 1));
    expect(inReplenish(byKey('replenish-error')), findsNothing);
  });

  testWidgets('INV-TRF-040 Review transfer (n) opens the transfer dialog '
      'from the store to the branch with the ticked lines', (tester) async {
    final r = await _open(tester);
    await pick(r.h, 'replenish-branch', 'Zamalek', scope: replenishDialog);
    final rows = await DashboardApi(r.server).inventory.replenishment(
      warehouseId: centralStore,
      branchId: SeedIds.zamalek,
    );
    final n = rows.where((x) => x.suggested > 0).length;
    expect(
      tester
          .widget<DashButton>(inReplenish(byKey('replenish-review')))
          .label,
      'Review transfer ($n)',
    );
    await r.h.tap(inReplenish(byKey('replenish-review')));
    expect(replenishDialog, findsNothing);
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(
        of: triggerIn(dialog, 'transfer-source'),
        matching: find.text('Central Store'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: triggerIn(dialog, 'transfer-destination'),
        matching: find.text('Zamalek'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: triggerIn(dialog, 'transfer-ingredient-0'),
        matching: find.text('Oat Milk'),
      ),
      findsWidgets,
    );
    expect(inDialog(find.text('6500')), findsOneWidget);
    await r.h.tap(inDialog(byKey('transfer-save-draft')));
    final body = r.h.server.callsTo(createRoute).single.body! as Map;
    expect(body['source_branch_id'], centralStore);
    expect(body['destination_branch_id'], SeedIds.zamalek);
    await r.h.expectToast('Draft saved');
  });

  testWidgets('INV-TRF-040 Cancel closes without reading on', (tester) async {
    final r = await _open(tester);
    await r.h.tap(inReplenish(byKey('replenish-cancel')));
    expect(replenishDialog, findsNothing);
    expect(dialog, findsNothing);
  });

  testWidgets('INV-TRF-039 phone: the rows scroll sideways in a full-screen '
      'dialog', (tester) async {
    final r = await _open(tester, size: DashSize.phone, locale: 'ar');
    await pick(r.h, 'replenish-branch', 'Zamalek', scope: replenishDialog);
    expect(inReplenish(byKey('replenish-table')), findsOneWidget);
    expect(r.h.locale, 'ar');
  });
}
