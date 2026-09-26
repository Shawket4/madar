// The panel host: sheets opened under it land in the panel's navigator, in
// place of what the panel shows, and hand back their result the way a sheet
// does. Without a host a sheet is still the window-wide surface.

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _panelNav = GlobalKey<NavigatorState>();
final GlobalKey _besideKey = GlobalKey();

/// A cart-like column beside a panel whose rest page is the "menu".
Widget _hosted() => MaterialApp(
  theme: MadarTheme.light(),
  home: MadarPanelHost(
    navigatorKey: _panelNav,
    child: Row(
      children: [
        SizedBox(width: 200, child: Container(key: _besideKey)),
        Expanded(
          child: Navigator(
            key: _panelNav,
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => const Center(child: Text('menu')),
            ),
          ),
        ),
      ],
    ),
  ),
);

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('a sheet from beside the panel opens IN the panel', (
    tester,
  ) async {
    await tester.pumpWidget(_hosted());
    final beside = _besideKey.currentContext!;
    final result = showMadarSheet<String>(
      beside,
      builder: (context) => TextButton(
        onPressed: () => Navigator.of(context).maybePop('picked'),
        child: const Text('choices'),
      ),
    );
    await _settle(tester);

    expect(find.text('choices'), findsOneWidget);
    expect(
      ModalRoute.of(tester.element(find.text('choices'))),
      isA<MadarPanelRoute<String>>(),
    );
    // It sits inside the panel, to the end of the 200px column.
    expect(tester.getTopLeft(find.text('choices')).dx, greaterThan(200));
    expect(
      MadarPanelHost.isPanelPage(tester.element(find.text('choices'))),
      isTrue,
    );

    await tester.tap(find.text('choices'));
    await _settle(tester);
    expect(await result, 'picked');
    expect(find.text('menu'), findsOneWidget);
    expect(find.text('choices'), findsNothing);
  });

  testWidgets('a second sheet from beside REPLACES the first', (tester) async {
    await tester.pumpWidget(_hosted());
    final beside = _besideKey.currentContext!;
    final first = showMadarSheet<String>(
      beside,
      builder: (_) => const Text('latte'),
    );
    await _settle(tester);
    final second = showMadarSheet<String>(
      beside,
      builder: (context) => TextButton(
        onPressed: () => MadarSheet.close(context, 'done'),
        child: const Text('mocha'),
      ),
    );
    await _settle(tester);

    // The first resolved as closed; only the second is up.
    expect(await first, isNull);
    expect(find.text('latte'), findsNothing);
    expect(find.text('mocha'), findsOneWidget);

    await tester.tap(find.text('mocha'));
    await _settle(tester);
    expect(await second, 'done');
    expect(find.text('menu'), findsOneWidget);
  });

  testWidgets('a sheet from a panel page STACKS and returns to it', (
    tester,
  ) async {
    await tester.pumpWidget(_hosted());
    String? inner;
    showMadarSheet<void>(
      _besideKey.currentContext!,
      builder: (context) => TextButton(
        onPressed: () async {
          inner = await showMadarSheet<String>(
            context,
            builder: (c) => TextButton(
              onPressed: () => Navigator.of(c).maybePop('customised'),
              child: const Text('customise'),
            ),
          );
        },
        child: const Text('combo'),
      ),
    ).ignore();
    await _settle(tester);
    await tester.tap(find.text('combo'));
    await _settle(tester);
    expect(find.text('customise'), findsOneWidget);

    await tester.tap(find.text('customise'));
    await _settle(tester);
    expect(inner, 'customised');
    // Back on the combo, not the menu.
    expect(find.text('combo'), findsOneWidget);
    expect(find.text('menu'), findsNothing);
  });

  testWidgets('without a host a sheet is still the window-wide surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: MadarTheme.light(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showMadarSheet<void>(
              context,
              builder: (_) => const Text('sheet'),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await _settle(tester);
    final route = ModalRoute.of(tester.element(find.text('sheet')));
    expect(route, isA<MadarSheetRoute<void>>());
    expect(
      MadarPanelHost.isPanelPage(tester.element(find.text('sheet'))),
      isFalse,
    );
  });

  testWidgets('reduced motion swaps the page without a transition', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: _hosted(),
      ),
    );
    showMadarSheet<void>(
      _besideKey.currentContext!,
      builder: (_) => const Text('choices'),
    ).ignore();
    await tester.pump();
    await tester.pump();
    final route = ModalRoute.of(tester.element(find.text('choices')))!;
    expect(route.transitionDuration, Duration.zero);
  });
}
