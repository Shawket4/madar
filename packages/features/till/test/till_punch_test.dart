// CL-13: a dead or forgotten phone clocks in at the till with the person's
// PIN. The sheet sends the PIN to the core and hands back its worded answer;
// offline it says a connection is needed, never queues a PIN.

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_till/feature_till.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

class _Bridge implements MadarBridge {
  _Bridge({this.offline = false});
  final bool offline;
  final List<String> pins = [];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final args = invocation.namedArguments;
    if (invocation.memberName == #tr) return args[#key];
    if (invocation.memberName == #tillPunch) {
      pins.add(args[#pin] as String);
      if (offline) {
        return Future<TillPunchView>.error(
          const MadarError.offline(detail: 'no network'),
        );
      }
      return Future<TillPunchView>.value(
        const TillPunchView(
          name: 'Amal',
          punched: 'in',
          message: 'Amal clocked in at 09:02',
        ),
      );
    }
    return null;
  }
}

Future<TillPunchView?> _run(WidgetTester tester, _Bridge bridge) async {
  TillPunchView? result;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [bridgeProvider.overrideWithValue(bridge)],
      child: MaterialApp(
        theme: MadarTheme.light(),
        home: Builder(
          builder: (context) => Center(
            child: GestureDetector(
              onTap: () async => result = await showTillPunch(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(EditableText), '4321');
  await tester.tap(find.text('staff.till_punch').last);
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('the PIN goes to the core and its answer comes back', (
    tester,
  ) async {
    final bridge = _Bridge();
    final res = await _run(tester, bridge);
    expect(bridge.pins, ['4321']);
    expect(res?.message, 'Amal clocked in at 09:02');
  });

  testWidgets('offline says a connection is needed and stays open', (
    tester,
  ) async {
    final bridge = _Bridge(offline: true);
    final res = await _run(tester, bridge);
    expect(res, isNull);
    expect(find.text('staff.till_punch_needs_connection'), findsOneWidget);
  });
}
