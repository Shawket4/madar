// Branch setup: what the page reads and shows (ADM-BSU-001…012).
import 'package:dashboard_admin/src/area_seed.dart';
import 'package:dashboard_admin/src/branch_setup/builder_canvas.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  testWidgets('ADM-BSU-003 no branch in scope: the title and "Select a '
      'branch", nothing fetched', (tester) async {
    final h = await pumpBuilder(tester);
    expect(find.byKey(const ValueKey('bb-pick-branch')), findsOneWidget);
    expect(
      pageText('Select a branch in the top bar to set it up'),
      findsOneWidget,
    );
    expect(pageText('Branch setup'), findsOneWidget);
    expect(h.server.callsTo(BranchPlanRoutes.plan), isEmpty);
  });

  testWidgets('ADM-BSU-004/006 a saved branch: its plan, version and pieces, '
      'presence in words', (tester) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.heliopolis);
    final calls = h.server.callsTo(BranchPlanRoutes.plan, method: 'GET');
    expect(calls, hasLength(1));
    expect(calls.single.query['branch_id'], [SeedIds.heliopolis]);
    expect(cardTitled('Counter 1'), findsOneWidget);
    expect(cardTitled('Kitchen screen'), findsOneWidget);
    expect(cardTitled('Bar'), findsOneWidget);
    expect(cardTitled('Receipt printer'), findsOneWidget);
    // K1 reported 3 minutes ago: online; T1 12 minutes ago: seen.
    expect(
      pieceOf(tester, cardTitled('Kitchen screen')).presence!.label,
      'Online',
    );
    expect(
      pieceOf(tester, cardTitled('Counter 1')).presence!.label,
      startsWith('Seen '),
    );
    expect(inPage(find.byKey(const ValueKey('bb-counts'))), findsOneWidget);
    expect(pageText('Devices 2 · Printers 3 · Sections 2'), findsOneWidget);
    // The Bar's three cooking items, its catch-all chip.
    final bar = pieceOf(tester, cardTitled('Bar'));
    expect(bar.badge, 'Everything else');
    expect(bar.detail, '3 cooking now');
    expect(bar.subtitle, '2 categories');
    // The kitchen screen lists the sections it shows.
    expect(pieceOf(tester, cardTitled('Kitchen screen')).subtitle, 'Bar');
  });

  testWidgets('ADM-BSU-006/089 the printer names the server gives '
      'read in Arabic', (tester) async {
    final h = await pumpBuilder(
      tester,
      branchId: SeedIds.heliopolis,
      locale: 'ar',
    );
    expect(cardTitled(h.t('builder.kind.receiptPrinter')), findsOneWidget);
    expect(cardTitled('طابعة Bar'), findsOneWidget);
    expect(cardTitled('Bar printer'), findsNothing);
    // Not a change: nothing to save.
    expect(find.byKey(const ValueKey('bb-unsaved')), findsNothing);
  });

  testWidgets('ADM-BSU-005 a never-saved branch is assembled from what it '
      'has', (tester) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.zamalek);
    expect(h.server.callsTo(BranchPlanRoutes.plan), hasLength(1));
    // Zamalek: two tills, a kitchen screen, two waiter tablets, the branch
    // printer, the Bar and Kitchen stations with their printers.
    for (final name in [
      'Counter 1',
      'Counter 2',
      'Kitchen screen',
      'Floor tablet',
      'Terrace tablet',
      'Receipt printer',
      'Bar printer',
      'Kitchen printer',
      'Bar',
      'Kitchen',
    ]) {
      expect(cardTitled(name), findsOneWidget, reason: name);
    }
    expect(cardTitled('Pastry'), findsNothing, reason: 'inactive station');
    expect(pieceOf(tester, cardTitled('Bar')).badge, 'Everything else');
    // History is off until a first save.
    final history = tester.widget<DashButton>(
      find.byKey(const ValueKey('bb-history')),
    );
    expect(history.onPressed, isNull);
  });

  testWidgets('ADM-BSU-007 loading: header shown, skeleton in the canvas, no '
      'inspector, no legend', (tester) async {
    final b = PlanBackend();
    final gate = b.server.hold('GET', BranchPlanRoutes.plan);
    final h = await pumpBuilder(
      tester,
      branchId: SeedIds.heliopolis,
      backend: b,
    );
    expect(find.byKey(const ValueKey('bb-skeleton')), findsOneWidget);
    expect(pageText('Branch setup'), findsOneWidget);
    expect(find.byKey(const ValueKey('bb-inspector')), findsNothing);
    expect(find.byKey(const ValueKey('bb-counts')), findsNothing);
    gate.release();
    await h.settle();
    expect(find.byKey(const ValueKey('bb-skeleton')), findsNothing);
    expect(find.byKey(const ValueKey('bb-inspector')), findsOneWidget);
  });

  testWidgets(
    'ADM-BSU-008 (divergence: no legend over it) a failed read: "Couldn\'t load this", the error, '
    'Retry reads again',
    (tester) async {
      final b = PlanBackend();
      b.server.fail(
        'GET',
        BranchPlanRoutes.plan,
        MockResponse.error(500, 'Database error: boom'),
      );
      final h = await pumpBuilder(
        tester,
        branchId: SeedIds.heliopolis,
        backend: b,
      );
      expect(find.byKey(const ValueKey('bb-error')), findsOneWidget);
      expect(pageText("Couldn't load this"), findsOneWidget);
      expect(find.byKey(const ValueKey('bb-inspector')), findsNothing);
      expect(find.byKey(const ValueKey('bb-counts')), findsNothing);
      await h.tap(inPage(find.text('Retry')));
      expect(h.server.callsTo(BranchPlanRoutes.plan), hasLength(2));
      expect(cardTitled('Counter 1'), findsOneWidget);
    },
  );

  testWidgets('ADM-BSU-012 presence turns from Online to Seen by the clock, '
      'without a refetch', (tester) async {
    final b = PlanBackend();
    final h = await pumpBuilder(
      tester,
      branchId: SeedIds.heliopolis,
      backend: b,
    );
    expect(
      pieceOf(tester, cardTitled('Kitchen screen')).presence!.label,
      'Online',
    );
    b.db.clock.advance(const Duration(minutes: 8));
    await tester.pump(const Duration(seconds: 61));
    await h.settle();
    expect(
      pieceOf(tester, cardTitled('Kitchen screen')).presence!.tone,
      PresenceTone.offline,
    );
    expect(h.server.callsTo(BranchPlanRoutes.plan), hasLength(1));
  });

  testWidgets('ADM-BSU-009 an empty plan shows the setup picker; no toolbar, '
      'no legend; the summary says nothing is placed', (tester) async {
    final b = PlanBackend();
    // Qahwa's Smouha has no devices, printer or stations.
    b.db[AdminTables.devices].removeWhere(
      (d) => d['branch_id'] == SeedIds.newCairo,
    );
    b.db['branches'].find(SeedIds.newCairo)!['printer_ip'] = null;
    await pumpBuilder(tester, branchId: SeedIds.newCairo, backend: b);
    expect(pageText('How is this branch set up?'), findsOneWidget);
    expect(find.byKey(const ValueKey('bb-toolbar')), findsNothing);
    expect(find.byKey(const ValueKey('bb-counts')), findsNothing);
    expect(inInspector(find.text('Nothing placed yet')), findsOneWidget);
    expect(
      inInspector(find.text('Every order has somewhere to go.')),
      findsOneWidget,
    );
  });
}
