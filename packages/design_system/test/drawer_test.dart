// MadarDrawer behavior — start-edge anchoring (LTR + RTL), the
// drag-dismiss contract, and the translation clamp (the panel must never
// overshoot past its resting edge).
import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _screen = Size(800, 600);
const _panelWidth = 320.0;

Finder get _panel => find.ancestor(
      of: find.text('CONTENT'),
      matching: find.byType(ClipRRect),
    );

Future<GlobalKey<NavigatorState>> _pumpHost(
  WidgetTester tester, {
  TextDirection direction = TextDirection.ltr,
}) async {
  tester.view.physicalSize = _screen;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final navKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      theme: MadarTheme.light(),
      navigatorKey: navKey,
      builder: (context, child) =>
          Directionality(textDirection: direction, child: child!),
      home: const ColoredBox(color: Color(0xFF112233)),
    ),
  );
  return navKey;
}

Future<void> _present(
  WidgetTester tester,
  GlobalKey<NavigatorState> navKey,
) async {
  unawaited(
    showMadarDrawer<void>(
      navKey.currentContext!,
      builder: (_) => const Center(child: Text('CONTENT')),
    ),
  );
  for (var i = 0; i < 120; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets('anchors to the leading edge at its width (LTR)',
      (tester) async {
    final navKey = await _pumpHost(tester);
    await _present(tester, navKey);
    final rect = tester.getRect(_panel);
    expect(rect.left, moreOrLessEquals(0, epsilon: 0.1));
    expect(rect.width, moreOrLessEquals(_panelWidth, epsilon: 0.1));
    expect(rect.top, 0);
    expect(rect.bottom, _screen.height);
  });

  testWidgets('anchors to the trailing edge under RTL', (tester) async {
    final navKey = await _pumpHost(tester, direction: TextDirection.rtl);
    await _present(tester, navKey);
    final rect = tester.getRect(_panel);
    expect(rect.right, moreOrLessEquals(_screen.width, epsilon: 0.1));
    expect(rect.width, moreOrLessEquals(_panelWidth, epsilon: 0.1));
  });

  testWidgets('released drag below threshold springs back without '
      'overshooting past rest (LTR)', (tester) async {
    final navKey = await _pumpHost(tester);
    await _present(tester, navKey);

    // Drag 60px toward the edge (< 28% of 320) and release.
    final gesture =
        await tester.startGesture(tester.getCenter(find.text('CONTENT')));
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(-10, 0));
      await tester.pump();
    }
    await gesture.up();

    // The clamp: the panel's left edge must never cross rest (0) to the
    // right on any spring-back frame.
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (_panel.evaluate().isEmpty) continue;
      expect(
        tester.getRect(_panel).left,
        lessThanOrEqualTo(0.001),
        reason: 'panel overshot its resting edge on frame $i',
      );
    }
    expect(tester.getRect(_panel).left, moreOrLessEquals(0, epsilon: 0.5));
  });

  testWidgets('drag past 28% of the width dismisses', (tester) async {
    final navKey = await _pumpHost(tester);
    await _present(tester, navKey);

    final gesture =
        await tester.startGesture(tester.getCenter(find.text('CONTENT')));
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(-20, 0)); // 160px > 28% of 320
      await tester.pump();
    }
    await gesture.up();
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('CONTENT'), findsNothing);
  });

  testWidgets('scrim tap dismisses', (tester) async {
    final navKey = await _pumpHost(tester);
    await _present(tester, navKey);
    await tester.tapAt(const Offset(700, 300)); // beside the panel
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('CONTENT'), findsNothing);
  });

  testWidgets('system back dismisses (PopScope routing)', (tester) async {
    final navKey = await _pumpHost(tester);
    await _present(tester, navKey);
    unawaited(navKey.currentState!.maybePop());
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('CONTENT'), findsNothing);
  });
}
