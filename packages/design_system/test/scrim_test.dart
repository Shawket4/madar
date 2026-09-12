// The dim belongs to the stack, not to each surface — see scrim.dart. Two
// sheets used to land the page at three-quarters black and a third at seven-
// eighths, which is the point at which a teller can no longer see what they
// opened the first one from.
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
