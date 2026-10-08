// The command palette: Ctrl/Cmd+K, the pages this person sees, ranked
// matching, the keyboard, the phone's search action.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/shell.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Future<void> ctrlK(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
}

void main() {
  test(
    'paletteScore: substring beats scattered letters; word starts first',
    () {
      expect(
        paletteScore('Tills /tills', 'till'),
        greaterThan(paletteScore('Staff drinks /reports/staff-pool', 'till')),
      );
      expect(paletteScore('Orders /orders', 'xyz'), 0);
      expect(paletteScore('Choice groups /menu/groups', 'cg'), greaterThan(0));
      expect(paletteScore('Tills', ''), 1);
    },
  );

  testWidgets('Ctrl+K opens it, typing narrows, a pick navigates', (
    tester,
  ) async {
    final h = await pumpShell(tester);
    await ctrlK(tester);
    await h.settle();
    expect(text('Jump to any page'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(DashCommandPalette),
        matching: text('Orders'),
      ),
      findsOneWidget,
    );
    await h.shot('palette/open');
    await h.enterText(find.byType(DashCommandPalette), 'tills');
    final inPalette = find.descendant(
      of: find.byType(DashCommandPalette),
      matching: text('Tills'),
    );
    expect(inPalette, findsWidgets);
    expect(
      find.descendant(
        of: find.byType(DashCommandPalette),
        matching: text('Orders'),
      ),
      findsNothing,
    );
    await h.shot('palette/filtered');
    await h.tap(inPalette.first);
    expect(h.location.path, '/tills');
    expect(find.byType(DashCommandPalette), findsNothing);
  });

  testWidgets('Ctrl+K again closes it', (tester) async {
    final h = await pumpShell(tester);
    await ctrlK(tester);
    await h.settle();
    expect(find.byType(DashCommandPalette), findsOneWidget);
    await ctrlK(tester);
    await h.settle();
    expect(find.byType(DashCommandPalette), findsNothing);
  });

  testWidgets('arrows move, Enter opens', (tester) async {
    final h = await pumpShell(tester);
    await h.tap(labelled('Search').first);
    await h.enterText(find.byType(DashCommandPalette), 'reports');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await h.settle(rounds: 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await h.settle();
    expect(find.byType(DashCommandPalette), findsNothing);
    expect(h.location.path, startsWith('/'));
    expect(h.location.path, isNot('/'));
  });

  testWidgets('no match says so', (tester) async {
    final h = await pumpShell(tester);
    await h.tap(labelled('Search').first);
    await h.enterText(find.byType(DashCommandPalette), 'zzzzqq');
    expect(text('No results found'), findsOneWidget);
  });

  testWidgets('only the pages this person sees', (tester) async {
    final h = await pumpShell(tester, persona: Persona.limited);
    await h.tap(labelled('Search').first);
    final p = find.byType(DashCommandPalette);
    expect(find.descendant(of: p, matching: text('Tills')), findsOneWidget);
    expect(find.descendant(of: p, matching: text('Floor')), findsNothing);
    expect(find.descendant(of: p, matching: text('Discounts')), findsNothing);
  });
}
