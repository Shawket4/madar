// Intent warming on the links page: resting on "QR code" fetches the links
// code, so the press asks the server nothing more. The page's other
// presses make no read (Copy, Open, the editor's own controls, Save).
import 'package:dashboard_core/testing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

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
  testWidgets('SET-LNK-007 QR code warms the links code; the press asks '
      'nothing more', (
    tester,
  ) async {
    final h = await pumpLinks(tester);
    expect(gets(h, LinksRoutes.qr), 0);
    final m = await _mouse(tester);
    await _rest(h, m, byKey('links-qr'));
    expect(gets(h, LinksRoutes.qr), 1);
    await m.moveTo(Offset.zero);
    await h.tap(byKey('links-qr'));
    expect(gets(h, LinksRoutes.qr), 1);
    expect(find.text('Links page code'), findsOneWidget);
  });
}
