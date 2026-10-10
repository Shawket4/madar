// Prefetch and intent warming on the Waste log: the sidebar's Waste row
// warms the page's first reads (the web's `prefetchRoute('/inventory/waste')`),
// Record waste warms the dialog's branch stock, and "Count it first" warms
// Stock counts, so each press asks the server nothing more.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Future<TestGesture> mouseAt(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  return mouse;
}

Future<void> hover(DashHarness h, TestGesture mouse, Finder f) async {
  await h.tester.ensureVisible(f);
  await h.settle();
  await mouse.moveTo(h.tester.getCenter(f));
  await h.settle();
}

void main() {
  final row = find.descendant(
    of: find.byType(DashSidebar),
    matching: find.text('Waste'),
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
    await hover(h, mouse, row);
  }

  testWidgets('INV-WST-002 (prefetch) hovering Waste warms the branch\'s log '
      'and the period\'s report; opening it reads nothing again', (
    tester,
  ) async {
    final h = await pumpWaste(
      tester,
      path: '/inventory/settings',
      branch: SeedIds.zamalek,
    );
    int n(String r) => h.server.callsTo(r, method: 'GET').length;
    final logs = n(logRoute);
    expect(n(reportRoute), 0);
    final mouse = await mouseAt(tester);
    await hoverSidebar(h, mouse);
    expect(n(reportRoute), 1, reason: 'warmed on hover');
    expect(
      h.server.callsTo(reportRoute).single.path,
      '/reports/branches/${SeedIds.zamalek}/waste-report',
    );
    final warmedLogs = n(logRoute);
    expect(warmedLogs, logs + 1);
    await h.tap(row);
    expect(h.location.path, wastePath);
    expect(n(reportRoute), 1, reason: 'served from the cache');
    expect(n(logRoute), warmedLogs, reason: 'served from the cache');
    expect(inTable(find.text('Cocoa Powder')), findsOneWidget);
  });

  testWidgets('INV-WST-002 (prefetch) All branches: nothing is warmed', (
    tester,
  ) async {
    final h = await pumpWaste(tester, path: '/inventory/settings');
    final mouse = await mouseAt(tester);
    await hoverSidebar(h, mouse);
    expect(h.server.callsTo(reportRoute), isEmpty);
    expect(h.container.read(currentScopeProvider).branchId, isNull);
  });

  testWidgets('INV-WST-003 (intent) pointing at Record waste warms the '
      'branch stock; the dialog opens on it', (tester) async {
    final h = await pumpWaste(tester, branch: SeedIds.zamalek);
    expect(h.server.callsTo(stockRoute), isEmpty);
    final mouse = await mouseAt(tester);
    final button = inPage(byKey('waste-record'));
    await hover(h, mouse, button);
    expect(h.server.callsTo(stockRoute), hasLength(1));
    await h.tap(button);
    expect(dialog, findsOneWidget);
    expect(h.server.callsTo(stockRoute), hasLength(1));
    await pickSearch(
      h,
      inDialog(
        find.descendant(
          of: byKey('waste-ingredient'),
          matching: find.byType(DashSelectTrigger),
        ),
      ),
      'Matcha Powder',
    );
    expect(inDialog(find.text('80 g on hand')), findsOneWidget);
  });

  testWidgets('INV-WST-015 (intent) pointing at "Count it first" warms Stock '
      'counts; it opens without asking again', (tester) async {
    final h = await pumpWaste(tester, branch: SeedIds.heliopolis);
    await h.tap(inPage(byKey('waste-record')));
    const counts = '/stocktakes/branches/{branch_id}';
    expect(h.server.callsTo(counts), isEmpty);
    final mouse = await mouseAt(tester);
    final link = inDialog(byKey('waste-count-first'));
    await hover(h, mouse, link);
    expect(h.server.callsTo(counts), hasLength(1));
    await h.tap(link);
    expect(h.location.path, '/inventory/counts');
    expect(h.server.callsTo(counts), hasLength(1));
  });
}
