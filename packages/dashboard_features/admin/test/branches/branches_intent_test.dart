// Intent warming on Branches: pointing at a row, its Edit action or a New
// button warms the dialog's timezone list, so the press asks nothing more.
import 'package:dashboard_admin/src/branches/branch_dialog.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  for (final (what, target) in [
    ('a row', () => rowOf('Zamalek')),
    ('its Edit action', () => labelled('Edit', within: rowOf('Maadi')).first),
    ('New', () => find.byKey(const ValueKey('branches-new'))),
    (
      'New warehouse',
      () => find.byKey(const ValueKey('branches-new-warehouse')),
    ),
  ]) {
    testWidgets('$what warms the dialog\'s timezones; the press asks nothing '
        'more', (tester) async {
      final h = await pumpBranches(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      expect(h.server.callsTo(timezonesRoute), isEmpty);

      await mouse.moveTo(tester.getCenter(target()));
      await h.settle();
      expect(h.server.callsTo(timezonesRoute), hasLength(1), reason: 'warmed');

      await h.tap(target());
      expect(find.byType(BranchDialog), findsOneWidget);
      expect(
        h.server.callsTo(timezonesRoute),
        hasLength(1),
        reason: 'the dialog opened from the cache',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();
    });
  }
}
