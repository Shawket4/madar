// Intent warming on Stock counts (owner rule, SPEC 6.1): pointing at a
// control warms the read its press makes, so the press asks nothing more.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:dashboard_inventory/src/counts/counts_data.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const String _stockRoute = '/inventory/branches/{branch_id}/stock';

/// A mouse resting at [at] for longer than the intent dwell.
Future<TestGesture> restAt(DashHarness h, Offset at) async {
  final mouse = await h.tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await mouse.moveTo(at);
  await h.settle();
  return mouse;
}

int _gets(DashHarness h, String route) =>
    h.server.callsTo(route, method: 'GET').length;

/// Rests on [button], presses it and checks the start dialog opens on the
/// categories and catalog the rest warmed.
Future<void> _startFrom(DashHarness h, Finder button) async {
  expect(h.tester.widget<DashButton>(button).onIntent, isNotNull);
  final categories = _gets(h, categoriesRoute);
  await restAt(h, h.tester.getCenter(button));
  expect(_gets(h, categoriesRoute), categories + 1, reason: 'warmed');
  final warm = (_gets(h, categoriesRoute), _gets(h, catalogRoute));
  expect(warm.$2, greaterThan(0));
  await h.tap(button);
  expect(scopeDialog, findsOneWidget);
  expect((_gets(h, categoriesRoute), _gets(h, catalogRoute)), warm);
}

void main() {
  testWidgets('INV-CNT-015 (intent) View report warms the variance report; '
      'opening it asks nothing more', (tester) async {
    final h = await pumpCounts(tester, branch: SeedIds.zamalek);
    final button = inTable(byKey('counts-report-$zamalekFull'));
    expect(_gets(h, reportRoute), 0);
    await restAt(h, tester.getCenter(button));
    expect(_gets(h, reportRoute), 1, reason: 'warmed');
    await h.tap(button);
    expect(report, findsOneWidget);
    expect(_gets(h, reportRoute), 1, reason: 'opened from the cache');
  });

  testWidgets('INV-CNT-016 (intent) a finalized row warms its report; a '
      'cancelled one warms nothing', (tester) async {
    final h = await pumpCounts(tester, branch: SeedIds.zamalek);
    // The row's own band, well clear of its View report button.
    final full = tester.getCenter(inTable(byKey('counts-report-$zamalekFull')));
    final mouse = await restAt(h, full - const Offset(600, 0));
    final warmed = h.server.callsTo(reportRoute, method: 'GET');
    expect(warmed, hasLength(1));
    expect(warmed.single.path, '/stocktakes/$zamalekFull/variance-report');
    // Stale again, then a cancelled row: nothing to warm.
    h.container.invalidate(varianceReportProvider(zamalekFull));
    await h.settle();
    final cancelled = find.descendant(
      of: table,
      matching: find.text('Cancelled'),
    );
    await mouse.moveTo(tester.getCenter(cancelled.first));
    await h.settle();
    expect(_gets(h, reportRoute), 1);
  });

  testWidgets('INV-CNT-004 (intent) Start a count warms the scope dialog\'s '
      'reads', (tester) async {
    final h = await pumpCounts(tester, branch: SeedIds.zamalek);
    await _startFrom(h, inPage(byKey('counts-start')));
  });

  testWidgets('INV-CNT-006 (intent) the first-run button warms the scope '
      'dialog\'s reads', (tester) async {
    final h = await pumpCounts(tester, branch: SeedIds.heliopolis);
    await _startFrom(h, inPage(byKey('counts-first-run')));
  });

  testWidgets('INV-CNT-034 (intent) New ingredient warms Ingredients; opening '
      'it asks nothing more', (tester) async {
    final s = countsServer();
    s.db[InvTables.stocktakeItems].removeWhere(
      (i) => i['stocktake_id'] == openNewCairo,
    );
    final h = await pumpCounts(
      tester,
      server: s.server,
      db: s.db,
      branch: SeedIds.newCairo,
    );
    final button = find.ancestor(
      of: inEditor(find.text('New ingredient')),
      matching: find.byType(DashButton),
    );
    expect(tester.widget<DashButton>(button).to, '/inventory/ingredients');
    await restAt(h, tester.getCenter(button));
    final reads = (_gets(h, catalogRoute), _gets(h, _stockRoute));
    expect(reads.$2, greaterThan(0), reason: 'the branch stock is warmed');
    await h.tap(button);
    expect(h.location.path, '/inventory/ingredients');
    expect((_gets(h, catalogRoute), _gets(h, _stockRoute)), reads);
  });
}
