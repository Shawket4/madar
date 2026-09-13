// Reduced motion TONES DOWN the playful kit, it never removes it: the cart
// flight becomes a short pulse on the cart, a nudge still plays (short and
// small), and a celebration fades in on its finished frame.
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({required bool reduced, required Widget child}) => MaterialApp(
  theme: MadarTheme.light(),
  builder: (context, c) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
    child: c!,
  ),
  home: Scaffold(body: child),
);

void main() {
  const from = Offset(40, 400);
  const to = Offset(700, 60);

  Future<BuildContext> mount(
    WidgetTester tester, {
    required bool reduced,
  }) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      _host(
        reduced: reduced,
        child: Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox.expand();
          },
        ),
      ),
    );
    return ctx;
  }

  testWidgets('full motion: the dot travels from the tile to the cart', (
    tester,
  ) async {
    final ctx = await mount(tester, reduced: false);
    var arrived = 0;
    playCartFlight(ctx, from: from, to: to, onArrive: () => arrived++);
    await tester.pump();
    final dot = find.byKey(cartFlightDotKey);
    expect(dot, findsOneWidget);
    expect((tester.getCenter(dot) - from).distance, lessThan(2));
    await tester.pump(const Duration(milliseconds: 440));
    expect((tester.getCenter(dot) - to).distance, lessThan(20));
    expect(arrived, 0);
    await tester.pump(const Duration(milliseconds: 20));
    expect(dot, findsNothing);
    expect(arrived, 1);
  });

  testWidgets('reduced motion: a short pulse ON the cart, then the catch', (
    tester,
  ) async {
    final ctx = await mount(tester, reduced: true);
    var arrived = 0;
    playCartFlight(ctx, from: from, to: to, onArrive: () => arrived++);
    await tester.pump();
    final dot = find.byKey(cartFlightDotKey);
    expect(dot, findsOneWidget, reason: 'feedback is toned down, not removed');
    expect((tester.getCenter(dot) - to).distance, lessThan(1));
    await tester.pump(const Duration(milliseconds: 160));
    expect(dot, findsNothing);
    expect(arrived, 1);
  });

  testWidgets('a screen layer: the dot flies in its own clipped overlay', (
    tester,
  ) async {
    final key = GlobalKey<OverlayState>();
    late BuildContext ctx;
    await tester.pumpWidget(
      _host(
        reduced: false,
        child: Padding(
          padding: const EdgeInsets.only(left: 80, top: 56),
          child: CartFlightLayer(
            overlayKey: key,
            child: Builder(
              builder: (c) {
                ctx = c;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      ),
    );
    playCartFlight(
      ctx,
      from: const Offset(200, 400),
      to: const Offset(700, 90),
      overlay: key.currentState,
    );
    await tester.pump();
    final dot = find.byKey(cartFlightDotKey);
    expect(Overlay.of(tester.element(dot)), same(key.currentState));
    expect(
      (tester.getCenter(dot) - const Offset(200, 400)).distance,
      lessThan(2),
    );
    await tester.pump(const Duration(milliseconds: 440));
    expect(
      (tester.getCenter(dot) - const Offset(700, 90)).distance,
      lessThan(20),
    );
    await tester.pump(const Duration(milliseconds: 20));
    expect(dot, findsNothing);
  });

  for (final reduced in [false, true]) {
    testWidgets('a nudge still plays with reduced motion = $reduced', (
      tester,
    ) async {
      Widget nudge(int n) => _host(
        reduced: reduced,
        child: Center(
          child: Nudge(
            trigger: n,
            child: const SizedBox(width: 20, height: 20),
          ),
        ),
      );
      await tester.pumpWidget(nudge(0));
      await tester.pumpWidget(nudge(1));
      await tester.pump(const Duration(milliseconds: 60));
      expect(
        find.descendant(
          of: find.byType(Nudge),
          matching: find.byType(Transform),
        ),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.descendant(
          of: find.byType(Nudge),
          matching: find.byType(Transform),
        ),
        findsNothing,
      );
    });
  }

  testWidgets('reduced motion: the settle mark fades in, finished', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(reduced: true, child: const Center(child: SettleMark())),
    );
    FadeTransition fade() => tester.widget<FadeTransition>(
      find
          .descendant(
            of: find.byType(SettleMark),
            matching: find.byType(FadeTransition),
          )
          .first,
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(fade().opacity.value, inExclusiveRange(0, 1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(fade().opacity.value, 1);
  });
}
