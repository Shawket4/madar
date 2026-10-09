// Intent warming on the QR page: resting on Generate warms that code, on
// "Make codes" every table's code (one at a time), so the press asks the
// server nothing more. An in-mall form that would not submit warms nothing.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'qr_support.dart';

Future<TestGesture> _mouse(WidgetTester tester) async {
  final m = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await m.addPointer(location: Offset.zero);
  addTearDown(m.removePointer);
  return m;
}

Future<void> _rest(DashHarness h, TestGesture m, Finder f) async {
  await h.tester.ensureVisible(f);
  await h.settle();
  await m.moveTo(h.tester.getCenter(f));
  await h.settle();
}

void main() {
  testWidgets('Generate warms its code; the press asks nothing more', (
    tester,
  ) async {
    final h = await pumpQr(tester);
    final m = await _mouse(tester);
    await _rest(h, m, generateOf(QrKind.orgOrder));
    expect(h.server.callsTo(QrRoutes.orgQr), hasLength(1));
    await m.moveTo(Offset.zero);
    await h.tap(generateOf(QrKind.orgOrder));
    expect(h.server.callsTo(QrRoutes.orgQr), hasLength(1));
    expect(resultOf(QrKind.orgOrder), findsOneWidget);
  });

  testWidgets('the in-mall Generate warms only a form that would submit', (
    tester,
  ) async {
    final h = await pumpQr(tester, query: atBranch(SeedIds.heliopolis));
    final m = await _mouse(tester);
    final button = generateOf(QrKind.branchOrderInMall);
    await _rest(h, m, button);
    expect(h.server.callsTo(QrRoutes.branchQr), isEmpty);
    await m.moveTo(Offset.zero);

    Finder field(String key) => find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byType(EditableText),
    );
    await h.enterText(field('qr-place'), 'Sabah Kiosk 3');
    await h.enterText(field('qr-floor'), 'Ground Floor');
    await h.enterText(field('qr-unit'), 'Unit 42');
    await _rest(h, m, button);
    expect(h.server.callsTo(QrRoutes.branchQr), hasLength(1));
    await m.moveTo(Offset.zero);
    await h.tap(button);
    expect(h.server.callsTo(QrRoutes.branchQr), hasLength(1));
    expect(resultOf(QrKind.branchOrderInMall), findsOneWidget);
  });

  testWidgets('"Make codes" warms every table\'s code in turn; the press '
      'asks nothing more', (tester) async {
    final h = await pumpQr(tester, query: atBranch(SeedIds.zamalek));
    final m = await _mouse(tester);
    final make = find.byKey(const ValueKey('qr-tables-make'));
    await _rest(h, m, make);
    expect(h.server.callsTo(QrRoutes.tableQr), hasLength(10));
    await m.moveTo(Offset.zero);
    await h.tap(make);
    expect(h.server.callsTo(QrRoutes.tableQr), hasLength(10));
    expect(find.byKey(const ValueKey('qr-tables-sheet')), findsOneWidget);
  });
}
