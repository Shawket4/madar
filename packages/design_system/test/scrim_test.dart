// The dim belongs to the stack, not to each surface — see scrim.dart. Two
// sheets used to land the page at three-quarters black and a third at seven-
// eighths, which is the point at which a teller can no longer see what they
// opened the first one from.
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  _claimApiTests();
  setUp(debugResetScrim);
  tearDown(debugResetScrim);

  Widget host(Widget child) => MaterialApp(
    theme: MadarTheme.light(),
    home: Scaffold(body: child),
  );

  testWidgets('the second sheet down does not dim again', (tester) async {
    late BuildContext outer;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (c) {
            outer = c;
            return const SizedBox.expand();
          },
        ),
      ),
    );

    ColoredBox? scrimOf(WidgetTester t) => t
        .widgetList<ColoredBox>(find.byType(ColoredBox))
        .where((b) => b.color.a > 0 && b.color.r == 0 && b.color.g == 0)
        .firstOrNull;

    unawaitedPush<void>(
      showMadarSheet<void>(outer, builder: (_) => const Text('first')),
    );
    await tester.pumpAndSettle();
    expect(find.text('first'), findsOneWidget);
    final first = scrimOf(tester);
    expect(first, isNotNull, reason: 'the first sheet paints the dim');

    final inner = tester.element(find.text('first'));
    unawaitedPush<void>(
      showMadarSheet<void>(inner, builder: (_) => const Text('second')),
    );
    await tester.pumpAndSettle();
    expect(find.text('second'), findsOneWidget);

    // Exactly one black layer on screen, not two.
    final blacks = tester
        .widgetList<ColoredBox>(find.byType(ColoredBox))
        .where((b) => b.color.a > 0 && b.color.r == 0 && b.color.g == 0)
        .length;
    expect(blacks, 1);
  });

  testWidgets('the dim comes back for the next, unstacked sheet', (
    tester,
  ) async {
    late BuildContext outer;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (c) {
            outer = c;
            return const SizedBox.expand();
          },
        ),
      ),
    );

    for (var i = 0; i < 2; i++) {
      unawaitedPush<void>(
        showMadarSheet<void>(outer, builder: (_) => Text('sheet $i')),
      );
      await tester.pumpAndSettle();
      final blacks = tester
          .widgetList<ColoredBox>(find.byType(ColoredBox))
          .where((b) => b.color.a > 0 && b.color.r == 0 && b.color.g == 0)
          .length;
      expect(blacks, 1, reason: 'pass $i still dims exactly once');
      Navigator.of(tester.element(find.text('sheet $i'))).pop();
      await tester.pumpAndSettle();
    }
  });
}

/// A pushed route whose future we deliberately do not await inside a test.
void unawaitedPush<T>(Future<T?> route) {
  route.ignore();
}

// A dialog that builds its own barrier still has to tell the kit it is
// dimming, or a sheet raised from inside it dims a second time. That was the
// Charge drawer: the loyalty scan sheet opened over it and the drawer behind
// went nearly black, so the sheet looked like it had landed on nothing.
void _claimApiTests() {
  test('a surface that claims makes the next one stand down', () {
    debugResetScrim();
    expect(scrimIsDown, isFalse);
    final first = claimScrim();
    expect(first, isTrue, reason: 'nothing below it');
    expect(scrimIsDown, isTrue);

    final second = claimScrim();
    expect(second, isFalse, reason: 'something below is already dimming');

    releaseScrim(painting: second); // a no-op, by contract
    expect(scrimIsDown, isTrue, reason: "the claim is still the first one's");

    releaseScrim(painting: first);
    expect(scrimIsDown, isFalse);
    expect(claimScrim(), isTrue, reason: 'the next surface dims again');
    debugResetScrim();
  });
}
