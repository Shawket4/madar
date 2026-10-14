// First run: "No account? Sign up free" sits under Activate and opens the
// web sign-up (`<dashboard origin>/signup`) outside the app. A device already
// bound to a branch (reconfiguring) does not show it.

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_auth/src/device_setup_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

class _Bridge implements MadarBridge {
  _Bridge({required this.bound});

  final bool bound;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    if (name == #tr) return invocation.namedArguments[#key];
    if (name == #deviceConfig) {
      return DeviceConfigView(
        reconfiguring: false,
        configured: bound,
        branchId: bound ? 'br-1' : null,
      );
    }
    return super.noSuchMethod(invocation);
  }
}

Future<List<Uri>> _pump(WidgetTester tester, {required bool bound}) async {
  final opened = <Uri>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bridgeProvider.overrideWithValue(_Bridge(bound: bound)),
        externalLinkOpenerProvider.overrideWithValue((uri) async {
          opened.add(uri);
        }),
      ],
      child: MaterialApp(
        theme: MadarTheme.light(),
        home: const Scaffold(
          body: SingleChildScrollView(child: DeviceSetupForm(showLogo: false)),
        ),
      ),
    ),
  );
  await tester.pump();
  return opened;
}

void main() {
  testWidgets('first run points a shop with no account at the free sign-up', (
    tester,
  ) async {
    final opened = await _pump(tester, bound: false);
    expect(find.text('setup.no_account'), findsOneWidget);
    await tester.tap(find.text('setup.sign_up_free'));
    await tester.pump();
    expect(opened, [kSignupUri]);
    expect(kSignupUri.path, '/signup');
    expect(kSignupUri.scheme, 'https');
  });

  testWidgets('a device that already has a branch does not offer it', (
    tester,
  ) async {
    await _pump(tester, bound: true);
    expect(find.text('setup.sign_up_free'), findsNothing);
  });
}
