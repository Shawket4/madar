// MadarSheet behavior — presentation, the drag-dismiss contract, and the
// translation clamp (an underdamped spring must never lift the
// bottom-anchored card above rest and flash the screen behind it).
import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _screen = Size(500, 900);

Finder get _card =>
    find.ancestor(of: find.text('CONTENT'), matching: find.byType(ClipRRect));

/// Pump [frames] 16ms frames, asserting the card's top never rises above
/// [restTop] (the clamp contract) whenever the card is on stage.
Future<double> _pumpTrackingTop(
  WidgetTester tester,
  int frames, {
  required double restTop,
}) async {
  var minTop = double.infinity;
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    if (_card.evaluate().isEmpty) continue;
    final top = tester.getTopLeft(_card).dy;
    if (top < minTop) minTop = top;
    expect(
      top,
      greaterThanOrEqualTo(restTop - 0.001),
      reason: 'sheet rose above rest on frame $i — overshoot clamp broken',
    );
  }
  return minTop;
}

Future<GlobalKey<NavigatorState>> _pumpHost(WidgetTester tester) async {
  tester.view.physicalSize = _screen;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final navKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      theme: MadarTheme.light(),
      navigatorKey: navKey,
      home: const ColoredBox(color: Color(0xFF112233)),
    ),
  );
  return navKey;
}

/// The handle's drag strip — the sheet page's own GestureDetector (index 0
/// is the scrim's).
Finder get _handle => find.byType(GestureDetector).at(1);

void main() {
  testWidgets('presents to the sized rest position', (tester) async {
    final navKey = await _pumpHost(tester);
    unawaited(
      showMadarSheet<void>(
        navKey.currentContext!,
        builder: (_) => const Center(child: Text('CONTENT')),
      ),
    );
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // SheetSize.auto: 88% of the 900 container → top at 108.
    expect(tester.getTopLeft(_card).dy, moreOrLessEquals(108, epsilon: 0.1));
  });

  testWidgets('released drag below threshold springs back without rising '
      'above rest', (tester) async {
    final navKey = await _pumpHost(tester);
    unawaited(
      showMadarSheet<void>(
        navKey.currentContext!,
        builder: (_) => const Center(child: Text('CONTENT')),
      ),
    );
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final restTop = tester.getTopLeft(_card).dy;

    // Drag down 120px (< 28% of the ~792 sheet) and release.
    final gesture = await tester.startGesture(tester.getCenter(_handle));
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
    }
    await gesture.up();

    // Track the whole spring-back — the clamp must hold every frame.
    await _pumpTrackingTop(tester, 90, restTop: restTop);
    expect(
      tester.getTopLeft(_card).dy,
      moreOrLessEquals(restTop, epsilon: 0.5),
    );
  });

  testWidgets('drag past the 28% threshold dismisses and resolves the '
      'future', (tester) async {
    final navKey = await _pumpHost(tester);
    var resolved = false;
    unawaited(
      showMadarSheet<void>(
        navKey.currentContext!,
        builder: (_) => const Center(child: Text('CONTENT')),
      ).then((_) => resolved = true),
    );
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    final gesture = await tester.startGesture(tester.getCenter(_handle));
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(0, 40)); // 320px > 28% of 792
      await tester.pump();
    }
    await gesture.up();
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(resolved, isTrue);
    expect(find.text('CONTENT'), findsNothing);
  });

  testWidgets('scrim tap dismisses', (tester) async {
    final navKey = await _pumpHost(tester);
    unawaited(
      showMadarSheet<void>(
        navKey.currentContext!,
        builder: (_) => const Center(child: Text('CONTENT')),
      ),
    );
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.tapAt(const Offset(250, 30)); // above the card
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('CONTENT'), findsNothing);
  });

  testWidgets('maybePop delivers the result after the slide-out', (
    tester,
  ) async {
    final navKey = await _pumpHost(tester);
    String? result;
    unawaited(
      showMadarSheet<String>(
        navKey.currentContext!,
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).maybePop('tender'),
            child: const Text('CONTENT'),
          ),
        ),
      ).then((r) => result = r),
    );
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.tap(find.text('CONTENT'));
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(result, 'tender');
  });

  // The floor's "Take an order": close the sheet and push the next screen in
  // the same tap. The sheet's delayed pop must complete the SHEET — it used to
  // pop whatever was on top, taking the new screen down and leaving a dead
  // scrim over the app.
  for (final surface in ['sheet', 'drawer']) {
    testWidgets('a $surface closed as the next screen is pushed removes only '
        'itself', (tester) async {
      final navKey = await _pumpHost(tester);
      String? result = 'unset';
      final shown = surface == 'sheet'
          ? showMadarSheet<String>(
              navKey.currentContext!,
              builder: (_) => const Text('CONTENT'),
            )
          : showMadarDrawer<String>(
              navKey.currentContext!,
              builder: (_) => const Text('CONTENT'),
            );
      unawaited(shown.then((r) => result = r));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      MadarSheet.close(tester.element(find.text('CONTENT')), 'picked');
      navKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            body: TextButton(onPressed: () {}, child: const Text('NEXT')),
          ),
        ),
      );
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(find.text('NEXT'), findsOneWidget, reason: 'next screen stays');
      expect(find.text('CONTENT', skipOffstage: false), findsNothing);
      expect(result, 'picked');
      expect(tester.takeException(), isNull);
      navKey.currentState!.pop();
      await tester.pump(const Duration(milliseconds: 600));
      expect(navKey.currentState!.canPop(), isFalse, reason: 'nothing left');
    });
  }
}
