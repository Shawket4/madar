// A till the Free plan switched off shows "This till isn't active" instead
// of the sell screen, and "Check again" is a person's pull (the owner may
// just have chosen this till in the dashboard).

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madar/app/inactive_till.dart';
import 'package:rust_bridge/rust_bridge.dart';

class _Bridge implements MadarBridge {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #tr) return invocation.namedArguments[#key];
    return super.noSuchMethod(invocation);
  }
}

void main() {
  testWidgets('says the till is not active and pulls on Check again', (
    tester,
  ) async {
    var pulls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bridgeProvider.overrideWithValue(_Bridge()),
          pullFromServerProvider.overrideWithValue(() async => pulls++),
        ],
        child: MaterialApp(
          theme: MadarTheme.light(),
          home: const InactiveTillScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('plan.inactive_title'), findsOneWidget);
    expect(find.text('plan.inactive_body'), findsOneWidget);
    await tester.tap(find.text('plan.inactive_check'));
    await tester.pump();
    expect(pulls, 1);
  });
}
