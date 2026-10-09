// Intent warming on Discounts: a row (or its pencil) warms the list the
// dialog listens to, Export warms the brand it reads, so after the mouse
// rests the press asks the server nothing more.
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  Future<void> editing(DashHarness h) async =>
      expect(inDialog(find.text('Edit discount')), findsOneWidget);
  for (final (kind, target, opened) in <(
    String,
    Finder Function(),
    Future<void> Function(DashHarness),
  )>[
    (
      'a row',
      () => inTable(find.text('Staff Meal')),
      editing,
    ),
    (
      'a row\'s pencil',
      () => labelled('Edit', of: table).first,
      editing,
    ),
    (
      'Export',
      () => inPage(find.text('Export Excel')),
      (h) => h.expectToast('Exported 7 rows'),
    ),
  ]) {
    testWidgets('intent: resting on $kind warms its read; the press asks '
        'nothing more', (tester) async {
      final h = await pumpDiscounts(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      int asked() => h.server.calls.where((c) => c.method == 'GET').length;
      // Older than 30 s: a press adding a reader would refetch.
      h.db!.clock.advance(const Duration(seconds: 31));
      final f = target();
      await tester.ensureVisible(f);
      await h.settle();
      final before = asked();
      await mouse.moveTo(tester.getCenter(f));
      await tester.pump(const Duration(milliseconds: 90));
      await h.settle();
      final warmed = asked();
      if (kind != 'Export') expect(warmed, before + 1, reason: 'warmed');
      await h.tap(f);
      await opened(h);
      expect(asked(), warmed);
    });
  }
}
