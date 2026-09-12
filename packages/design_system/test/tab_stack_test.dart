// Pages go on the tab's own stack; surfaces (sheets, drawers, the top card)
// go on the ROOT navigator over the whole window — and a surface closed in
// the same tap that pushes a page removes only itself.

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _root = GlobalKey<NavigatorState>();
final _tab = GlobalKey<NavigatorState>();

/// A shell stand-in: a CHROME strip that must stay, the tab stack beside it.
Future<void> _pumpShell(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: MadarTheme.light(),
      navigatorKey: _root,
      home: Row(
        children: [
          const SizedBox(width: 80, child: Text('CHROME')),
          Expanded(
            child: MadarTabStack(
              navigatorKey: _tab,
              active: true,
              child: const ColoredBox(
                color: Color(0xFF112233),
                child: Text('TAB ROOT'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets('a page pushed from inside the tab lands on the tab stack', (
    tester,
  ) async {
    await _pumpShell(tester);
    MadarPages.push<void>(
      tester.element(find.text('TAB ROOT')),
      (_) => const Text('PAGE'),
    ).ignore();
    await _frames(tester);
    expect(find.text('PAGE'), findsOneWidget);
    expect(find.text('CHROME'), findsOneWidget);
    expect(_root.currentState!.canPop(), isFalse);
    expect(_tab.currentState!.canPop(), isTrue);
    expect(tester.getTopLeft(find.text('PAGE')).dx, greaterThanOrEqualTo(80));
  });

  testWidgets('a sheet opened from a page overlays the window on the root', (
    tester,
  ) async {
    await _pumpShell(tester);
    MadarPages.push<void>(
      tester.element(find.text('TAB ROOT')),
      (_) => const Text('PAGE'),
    ).ignore();
    await _frames(tester);
    showMadarSheet<void>(
      tester.element(find.text('PAGE')),
      builder: (_) => const Text('SHEET'),
    ).ignore();
    await _frames(tester);
    expect(_root.currentState!.canPop(), isTrue, reason: 'sheet on the root');
    // The card is centred on the WINDOW, not on the content area.
    final sheetBox = tester.getRect(
      find
          .ancestor(of: find.text('SHEET'), matching: find.byType(Material))
          .first,
    );
    expect(sheetBox.center.dx, closeTo(500, 1));
  });

  // The floor's "Take an order", inside the shell: the sheet (root) closes
  // and the table's Sell (tab stack) is pushed in the same tap.
  testWidgets('a sheet closed as a page is pushed from it leaves the page', (
    tester,
  ) async {
    await _pumpShell(tester);
    String? result = 'unset';
    final floor = tester.element(find.text('TAB ROOT'));
    showMadarSheet<String>(
      floor,
      builder: (_) => const Text('SEATED'),
    ).then((r) => result = r).ignore();
    await _frames(tester);

    MadarSheet.close(tester.element(find.text('SEATED')), 'take');
    // Pushed from the SHEET's context: navigatorOf still finds the tab.
    MadarPages.push<void>(
      tester.element(find.text('SEATED')),
      (_) => TextButton(onPressed: () {}, child: const Text('SELL')),
    ).ignore();
    await _frames(tester);

    expect(find.text('SELL'), findsOneWidget);
    expect(find.text('SEATED', skipOffstage: false), findsNothing);
    expect(result, 'take');
    expect(_root.currentState!.canPop(), isFalse, reason: 'no dead scrim');
    expect(_tab.currentState!.canPop(), isTrue, reason: 'Sell on the tab');
    await tester.tap(find.text('SELL'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a top card opens its sheet above it, both on the root', (
    tester,
  ) async {
    debugResetScrim();
    await _pumpShell(tester);
    final card = showMadarTopCard<String>(
      tester.element(find.text('TAB ROOT')),
      barrierResult: 'away',
      builder: (_) => const SizedBox(height: 120, child: Text('DONE')),
    );
    await _frames(tester);
    showMadarSheet<void>(
      tester.element(find.text('DONE')),
      builder: (_) => const Center(child: Text('POINTS')),
    ).ignore();
    await _frames(tester);
    await tester.tap(find.text('POINTS'));
    await _frames(tester);
    expect(find.text('POINTS'), findsOneWidget);
    expect(find.text('DONE'), findsOneWidget);
    MadarSheet.close<void>(tester.element(find.text('POINTS')));
    await _frames(tester);
    expect(find.text('DONE'), findsOneWidget);
    MadarSheet.close(tester.element(find.text('DONE')), 'done');
    await _frames(tester);
    expect(await card, 'done');
    expect(_root.currentState!.canPop(), isFalse);
    debugResetScrim();
  });
}
