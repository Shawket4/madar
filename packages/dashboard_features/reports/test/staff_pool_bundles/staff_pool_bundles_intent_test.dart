// Intent warming on Bundles and Staff drinks: a resting mouse warms the read
// the press makes, so the press asks the server nothing more.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_reports/src/staff_pool_bundles/bundles_report_page.dart';
import 'package:dashboard_reports/src/staff_pool_bundles/staff_drink_order_sheet.dart';
import 'package:dashboard_reports/src/staff_pool_bundles/staff_drinks_table.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Future<TestGesture> _mouse(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  return mouse;
}

int _kindCalls(DashHarness h, String kind) => [
  for (final c in h.server.callsTo(bundlesTpl))
    if (c.query['kind']?.single == kind) c,
].length;

void main() {
  testWidgets('REP-BUN-011 pointing at Deals warms the deals; the switch '
      'asks nothing more', (tester) async {
    final h = await pumpReports(tester, path: bundlesPath);
    final mouse = await _mouse(tester);
    final deals = find.descendant(
      of: find.byType(DashSegmentedControl<BundleKind>),
      matching: find.text('Deals'),
    );
    expect(_kindCalls(h, 'deal'), 0);
    await mouse.moveTo(tester.getCenter(deals));
    await h.settle();
    expect(_kindCalls(h, 'deal'), 1, reason: 'the deals are warmed');
    await h.tap(deals);
    expect(_kindCalls(h, 'deal'), 1, reason: 'the deals came from the cache');
    expect(find.text('Brunch for Two'), findsNothing);
  });

  for (final size in [DashSize.desktop, DashSize.phone]) {
    testWidgets('REP-BUN-012 ${size.name}: pointing at a combo warms its mix; '
        'the dialog asks nothing more', (tester) async {
      final h = await pumpReports(
        tester,
        path: '$bundlesPath?branchId=${SeedIds.heliopolis}',
        size: size,
      );
      final mouse = await _mouse(tester);
      final row = find.text('Coffee & Cookie');
      await tester.ensureVisible(row);
      await h.settle();
      expect(h.server.callsTo(mixTpl), isEmpty);
      await mouse.moveTo(tester.getCenter(row));
      await h.settle();
      expect(h.server.callsTo(mixTpl), hasLength(1), reason: 'mix warmed');
      await h.tap(row);
      expect(find.text('What went into Coffee & Cookie'), findsOneWidget);
      expect(h.server.callsTo(mixTpl), hasLength(1), reason: 'from the cache');
    });
  }

  testWidgets('REP-SPL-019 pointing at View order warms the sale; the sheet '
      'asks nothing more', (tester) async {
    final h = await pumpReports(
      tester,
      path: '$staffPoolPath?branchId=${SeedIds.heliopolis}&preset=today',
    );
    final mouse = await _mouse(tester);
    final link = find
        .descendant(
          of: find.byType(StaffDrinksTable),
          matching: find.text('View order'),
        )
        .first;
    expect(h.server.callsTo(orderTpl), isEmpty);
    await mouse.moveTo(tester.getCenter(link));
    await h.settle();
    expect(h.server.callsTo(orderTpl), hasLength(1), reason: 'sale warmed');
    await h.tap(link);
    expect(find.byType(StaffDrinkOrderSheet), findsOneWidget);
    expect(h.server.callsTo(orderTpl), hasLength(1), reason: 'from the cache');
  });
}
