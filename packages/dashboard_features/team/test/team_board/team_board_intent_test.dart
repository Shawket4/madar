// Intent warming on the Team board: resting on a flag row warms the read its
// dialog makes (everyone, for the own-flag check), resting on the pay-line
// and Add employee buttons warms their dialogs' reads, so the press asks the
// server nothing more.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'team_board_support.dart';

int _everyone(MockServer s) => [
  for (final c in s.callsTo(employeesT, method: 'GET'))
    if (c.query.isEmpty) c,
].length;

Future<void> _rest(WidgetTester tester, TestGesture mouse, Finder f) async {
  await mouse.moveTo(tester.getCenter(f));
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  testWidgets('a flag row warms its dialog\'s read; pressing it asks '
      'nothing more', (tester) async {
    final h = await pumpTeam(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    final row = rowOf('Karim Adel · ${h.t('dawam.flag_left_mid_shift')}');
    expect(_everyone(h.server), 0);
    await _rest(tester, mouse, row);
    await h.settle();
    expect(_everyone(h.server), 1, reason: 'the dialog read is warmed');
    await h.tap(row);
    expect(surfaceText(h.t('dawam.excusePaid')), findsOneWidget);
    expect(_everyone(h.server), 1, reason: 'the dialog opened from the cache');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
  });

  testWidgets('the pay-line and Add employee buttons warm their dialogs\' '
      'reads', (tester) async {
    final h = await pumpTeam(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    const current = '/staff/payroll/current';
    expect(h.server.callsTo(current), isEmpty);
    final payLine = boardButton(h.t('dawam.addPayLineHere'));
    await _rest(tester, mouse, payLine);
    await h.settle();
    expect(h.server.callsTo(current), hasLength(1));
    await h.tap(payLine);
    expect(surfaceText(h.t('dawam.addPayLine')), findsOneWidget);
    expect(h.server.callsTo(current), hasLength(1));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();

    const linkable = '/staff/employees/linkable';
    expect(h.server.callsTo(linkable), isEmpty);
    final add = boardButton(h.t('dawam.addEmployee'));
    await _rest(tester, mouse, add);
    await h.settle();
    expect(h.server.callsTo(linkable), hasLength(1));
    await h.tap(add);
    expect(h.server.callsTo(linkable), hasLength(1));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
  });
}
