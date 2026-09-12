// The dim belongs to the stack, not to each surface — see scrim.dart. Two
// sheets used to land the page at three-quarters black and a third at seven-
// eighths, which is the point at which a teller can no longer see what they
// opened the first one from.
import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  _claimApiTests();
  handoffTests();
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

/// The dims actually visible right now: the shared scrim colour under a fade
/// that has not reached zero.
int visibleDims(WidgetTester tester) {
  var n = 0;
  for (final e in find.byType(ColoredBox).evaluate()) {
    final box = e.widget as ColoredBox;
    if (box.color != StackScrim.color) continue;
    final fade = e.findAncestorWidgetOfExactType<FadeTransition>();
    if (fade == null || fade.opacity.value > 0) n++;
  }
  return n;
}

void handoffTests() {
  Future<BuildContext> mountHost(WidgetTester tester) async {
    late BuildContext outer;
    await tester.pumpWidget(
      MaterialApp(
        theme: MadarTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (c) {
              outer = c;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    return outer;
  }

  testWidgets('a sheet that follows a sheet takes the dim over: never none, '
      'never two', (tester) async {
    debugResetScrim();
    final host = await mountHost(tester);
    final first = showMadarSheet<int>(host, builder: (_) => const Text('A'));
    await tester.pumpAndSettle();
    expect(visibleDims(tester), 1);

    // What showCharge does: await the first, push the next straight away.
    var pushed = false;
    unawaited(
      first.then((_) {
        pushed = true;
        unawaitedPush<void>(
          showMadarSheet<void>(host, builder: (_) => const Text('B')),
        );
      }),
    );
    MadarSheet.close(tester.element(find.text('A')), 1);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(visibleDims(tester), 1, reason: 'frame $i');
    }
    await tester.pumpAndSettle();
    expect(pushed, isTrue);
    expect(find.text('A'), findsNothing);
    expect(find.text('B'), findsOneWidget);
    expect(visibleDims(tester), 1);
    debugResetScrim();
  });

  testWidgets('a dialog followed by a sheet hands the dim on too', (
    tester,
  ) async {
    debugResetScrim();
    final host = await mountHost(tester);
    final dialog = showMadarDialogSurface<int>(
      host,
      pageBuilder: (_) => const Center(child: Text('D')),
    );
    await tester.pumpAndSettle();
    expect(visibleDims(tester), 1);
    unawaited(
      dialog.then(
        (_) => unawaitedPush<void>(
          showMadarSheet<void>(host, builder: (_) => const Text('S')),
        ),
      ),
    );
    Navigator.of(tester.element(find.text('D'))).pop(1);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(visibleDims(tester), 1, reason: 'frame $i');
    }
    await tester.pumpAndSettle();
    expect(find.text('S'), findsOneWidget);
    debugResetScrim();
  });

  testWidgets('MadarSheet.close animates out instead of cutting', (
    tester,
  ) async {
    debugResetScrim();
    final host = await mountHost(tester);
    final sheet = showMadarSheet<String>(host, builder: (_) => const Text('X'));
    await tester.pumpAndSettle();
    MadarSheet.close(tester.element(find.text('X')), 'done');
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('X'), findsOneWidget, reason: 'still sliding out');
    await tester.pumpAndSettle();
    expect(find.text('X'), findsNothing);
    expect(await sheet, 'done');
    debugResetScrim();
  });

  testWidgets('a drawer claims the shared dim: a sheet over it dims nothing '
      'more', (tester) async {
    debugResetScrim();
    final host = await mountHost(tester);
    unawaitedPush<void>(
      showMadarDrawer<void>(host, builder: (_) => const Text('menu')),
    );
    await tester.pumpAndSettle();
    expect(visibleDims(tester), 1);
    unawaitedPush<void>(
      showMadarSheet<void>(
        tester.element(find.text('menu')),
        builder: (_) => const Text('over'),
      ),
    );
    await tester.pumpAndSettle();
    expect(visibleDims(tester), 1);
    debugResetScrim();
  });

  testWidgets('a top card sits under the sheet it opens, one dim', (
    tester,
  ) async {
    debugResetScrim();
    final host = await mountHost(tester);
    final card = showMadarTopCard<String>(
      host,
      barrierResult: 'away',
      builder: (_) => const SizedBox(height: 120, child: Text('card')),
    );
    await tester.pumpAndSettle();
    unawaitedPush<void>(
      showMadarSheet<void>(
        tester.element(find.text('card')),
        builder: (_) => const Center(child: Text('points')),
      ),
    );
    await tester.pumpAndSettle();
    expect(visibleDims(tester), 1);
    // A tap on the sheet lands on the sheet — the card below survives it.
    await tester.tap(find.text('points'));
    await tester.pumpAndSettle();
    expect(find.text('points'), findsOneWidget);
    expect(find.text('card'), findsOneWidget);
    MadarSheet.close<void>(tester.element(find.text('points')));
    await tester.pumpAndSettle();
    expect(find.text('card'), findsOneWidget);
    expect(visibleDims(tester), 1);
    // Its own barrier puts it away.
    await tester.tapAt(const Offset(10, 590));
    await tester.pumpAndSettle();
    expect(await card, 'away');
    expect(visibleDims(tester), 0);
    debugResetScrim();
  });
}
