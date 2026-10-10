// Intent on Work shifts: no press on this page makes a read. The dialog and
// the cell menu open from what the page already holds, so resting on them
// and pressing asks the server nothing.
import 'package:dashboard_team/src/shifts/shift_dialog.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shifts_support.dart';

void main() {
  testWidgets('New shift, Edit and a roster cell open from the cache: '
      'resting and pressing ask nothing', (tester) async {
    final h = await pumpShifts(tester, edit: addDemoShifts);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    final calls = h.server.calls.length;

    Future<void> restAndPress(Finder f) async {
      await tester.ensureVisible(f);
      await h.settle();
      await mouse.moveTo(tester.getCenter(f));
      await h.settle();
      expect(h.server.calls.length, calls, reason: 'nothing to warm');
      await h.tap(f);
      expect(h.server.calls.length, calls, reason: 'opened from the cache');
    }

    await restAndPress(inPage(find.byKey(const ValueKey('shifts-new'))));
    expect(find.byType(WorkShiftDialog), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();

    await restAndPress(inRow(brunch, find.bySemanticsLabel('Edit')));
    expect(surfaceText('Edit work shift'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();

    await restAndPress(cell('karim', 5));
    expect(find.text('Assign shift'), findsOneWidget);
  });
}
