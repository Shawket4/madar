// Reconfigure is a fresh install the core gates: the sheet shows every
// blocker the core names, and "Reconfigure" stays disabled until the core
// says the device is allowed.

import 'package:app_core/app_core.dart';
import 'package:app_core/testing.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_auth/feature_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

const _blocked = ReconfigureReadinessView(
  allowed: false,
  outboxTotal: 4,
  blockers: [
    ReconfigureBlockerView(
      kind: 'pending',
      count: 3,
      label: '3 sales still uploading',
    ),
    ReconfigureBlockerView(
      kind: 'dead',
      count: 1,
      label: '1 failed refund — retry or discard',
    ),
    ReconfigureBlockerView(
      kind: 'till_open',
      count: 1,
      label: "Close Sara's till first",
      tillId: 't1',
      ownerName: 'Sara',
    ),
    ReconfigureBlockerView(
      kind: 'offline',
      count: 1,
      label: 'This device is offline',
    ),
  ],
);

const _allowed = ReconfigureReadinessView(
  allowed: true,
  outboxTotal: 0,
  blockers: [],
);

class _Bridge implements MadarBridge {
  _Bridge(this.readiness);

  ReconfigureReadinessView readiness;
  ReconfigureReadinessView? afterPush;
  int pushes = 0;
  int wipes = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final can = fakeCanInvocation(invocation, () => currentSession()?.role);
    if (can != null) return can;
    final name = invocation.memberName;
    if (name == #tr) return invocation.namedArguments[#key];
    if (name == #appRoute) return const AppRoute.deviceSetup();
    if (name == #reconfigureReadiness) return readiness;
    if (name == #reconfigurePushNow) {
      pushes++;
      readiness = afterPush ?? readiness;
      return Future<ReconfigureReadinessView>.value(readiness);
    }
    if (name == #startReconfigure) {
      wipes++;
      return Future<void>.value();
    }
    return null;
  }
}

Future<void> _pump(WidgetTester tester, _Bridge bridge) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1024, 1366);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [bridgeProvider.overrideWithValue(bridge)],
      child: MaterialApp(
        theme: MadarTheme.light(),
        home: const Scaffold(
          body: SingleChildScrollView(child: ReconfigurePanel()),
        ),
      ),
    ),
  );
  await tester.pump();
}

MadarButton _button(WidgetTester tester, String key) =>
    tester.widget<MadarButton>(find.byKey(ValueKey(key)));

void main() {
  testWidgets('every blocker the core names is shown, reconfigure disabled', (
    tester,
  ) async {
    final bridge = _Bridge(_blocked);
    await _pump(tester, bridge);
    expect(find.text('3 sales still uploading'), findsOneWidget);
    expect(find.text('1 failed refund — retry or discard'), findsOneWidget);
    expect(find.text("Close Sara's till first"), findsOneWidget);
    expect(find.text('This device is offline'), findsOneWidget);
    expect(find.byKey(const ValueKey('reconfigure-ready')), findsNothing);
    expect(_button(tester, 'reconfigure-confirm').enabled, isFalse);
    expect(_button(tester, 'reconfigure-push').enabled, isTrue);

    await tester.tap(find.byKey(const ValueKey('reconfigure-confirm')));
    await tester.pump();
    expect(bridge.wipes, 0, reason: 'a disabled Reconfigure never wipes');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('live counts follow the core on the tick', (tester) async {
    final bridge = _Bridge(_blocked);
    await _pump(tester, bridge);
    bridge.readiness = const ReconfigureReadinessView(
      allowed: false,
      outboxTotal: 1,
      blockers: [
        ReconfigureBlockerView(
          kind: 'pending',
          count: 1,
          label: '1 sale still uploading',
        ),
      ],
    );
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('1 sale still uploading'), findsOneWidget);
    expect(find.text('3 sales still uploading'), findsNothing);
    expect(_button(tester, 'reconfigure-confirm').enabled, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('push now that clears everything enables reconfigure', (
    tester,
  ) async {
    final bridge = _Bridge(_blocked)..afterPush = _allowed;
    await _pump(tester, bridge);
    await tester.tap(find.byKey(const ValueKey('reconfigure-push')));
    await tester.pump();
    await tester.pump();
    expect(bridge.pushes, 1);
    expect(find.byKey(const ValueKey('reconfigure-ready')), findsOneWidget);
    expect(find.text('3 sales still uploading'), findsNothing);
    expect(_button(tester, 'reconfigure-confirm').enabled, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an allowed device asks, then wipes', (tester) async {
    final bridge = _Bridge(_allowed);
    await _pump(tester, bridge);
    var resets = 0;
    ProviderScope.containerOf(
      tester.element(find.byType(ReconfigurePanel)),
    ).read(deviceResetProvider.notifier).register(() => resets++);
    expect(_button(tester, 'reconfigure-confirm').enabled, isTrue);
    await tester.tap(find.byKey(const ValueKey('reconfigure-confirm')));
    await tester.pumpAndSettle();
    expect(bridge.wipes, 0, reason: 'asked first');
    expect(find.text('reconfigure.confirm_title'), findsOneWidget);
    await tester.tap(find.text('reconfigure.confirm').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(bridge.wipes, 1);
    expect(resets, 1, reason: 'the app starts a fresh container');
    await tester.pumpWidget(const SizedBox());
  });
}
