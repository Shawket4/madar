// REP-SPL-019 through dashboard_core's cross-area seam: unwired (this package
// alone) "View order" opens the local port of the order sheet; wired, it goes
// to the app's opener (sell's order sheet) and its intent warms through it.
// The real sheet: apps/dashboard test/shell/openers_test.dart.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_reports/src/mock/staff_pool_bundles_mock.dart';
import 'package:dashboard_reports/src/staff_pool_bundles/staff_drink_order_sheet.dart';
import 'package:dashboard_reports/src/staff_pool_bundles/staff_drinks_table.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Future<DashHarness> _pump(WidgetTester tester, AreaOpeners openers) =>
    DashHarness.pump(
      tester,
      areas: const [unitArea],
      path: '$staffPoolPath?branchId=${SeedIds.heliopolis}&preset=today',
      overrides: [areaOpenersProvider.overrideWithValue(openers)],
    );

Finder get _viewOrder => find
    .descendant(
      of: find.byType(StaffDrinksTable),
      matching: find.text('View order'),
    )
    .first;

void main() {
  testWidgets('REP-SPL-019 seam not wired: the local order sheet', (
    tester,
  ) async {
    final h = await _pump(tester, const AreaOpeners());
    await h.tap(_viewOrder);
    expect(find.byType(StaffDrinkOrderSheet), findsOneWidget);
  });

  testWidgets('REP-SPL-019 seam wired: the app\'s order sheet; intent warms '
      'through it', (tester) async {
    final opened = <String>[];
    final warmed = <String>[];
    final h = await _pump(
      tester,
      AreaOpeners(
        orderSheet: OrderSheetOpener(
          open: (context, id) async => opened.add(id),
          warm: (ref, id) => warmed.add(id),
        ),
      ),
    );
    final id = StaffPoolMock.drinksIn(
      h.db!,
      SeedIds.heliopolis,
      defaultTo,
      defaultTo,
    ).first['order_id']! as String;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(_viewOrder));
    await h.settle();
    expect(warmed, [id]);
    await h.tap(_viewOrder);
    expect(opened, [id]);
    expect(find.byType(StaffDrinkOrderSheet), findsNothing);
    expect(h.server.callsTo(orderTpl), isEmpty);
  });
}
