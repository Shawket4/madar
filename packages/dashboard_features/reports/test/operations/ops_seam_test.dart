// REP-OPS-032 through dashboard_core's cross-area seam: unwired (this package
// alone) a sitting's customer opens the local read-only panel; wired, it
// goes to the app's opener (sell's customer sheet), read-only, and its
// intent warms through the opener. The real sheet: apps/dashboard
// test/shell/openers_test.dart.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_reports/dashboard_reports.dart';
import 'package:dashboard_reports/src/operations/ops_table_sheet.dart';
import 'package:dashboard_reports/src/operations/ops_tables.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Future<DashHarness> _pump(WidgetTester tester, AreaOpeners openers) =>
    DashHarness.pump(
      tester,
      areas: const [reportsArea],
      path: opsPath,
      prefs: {
        ScopePrefKeys.branch:
            '{"org":"${SeedIds.sabahOrg}","branch":"${SeedIds.heliopolis}"}',
      },
      overrides: [areaOpenersProvider.overrideWithValue(openers)],
    );

/// Opens T1's history and returns the first sitting customer's link.
Future<Finder> _customerLink(DashHarness h) async {
  await h.tap(
    find
        .descendant(
          of: inPage(find.byKey(opsTableNameKey)),
          matching: find.text('T1'),
        )
        .first,
  );
  return find.descendant(
    of: find.byType(OpsTableSheet),
    matching: find.widgetWithText(
      DashPressable,
      MockSeed.instance.customers[0].name,
    ),
  );
}

void main() {
  testWidgets('REP-OPS-032 seam not wired: the local read-only panel', (
    tester,
  ) async {
    final h = await _pump(tester, const AreaOpeners());
    await h.tap(await _customerLink(h));
    expect(find.byType(OpsCustomerSheet), findsOneWidget);
  });

  testWidgets('REP-OPS-032 seam wired: the app\'s customer sheet, read-only; '
      'intent warms through it', (tester) async {
    final opened = <(String, bool)>[];
    final warmed = <String>[];
    final h = await _pump(
      tester,
      AreaOpeners(
        customerSheet: CustomerSheetOpener(
          open: (context, id, {readOnly = false, branchId}) async =>
              opened.add((id, readOnly)),
          warm: (ref, id, {branchId}) => warmed.add(id),
        ),
      ),
    );
    final link = await _customerLink(h);
    final id = MockSeed.instance.customers[0].id;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(link));
    await h.settle();
    expect(warmed, [id]);
    await h.tap(link);
    expect(opened, [(id, true)]);
    expect(find.byType(OpsCustomerSheet), findsNothing);
    expect(h.server.callsTo('/customers/{id}'), isEmpty);
  });
}
