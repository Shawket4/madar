// The command palette: Ctrl/Cmd+K, the pages this person sees, ranked
// matching, the keyboard, the phone's search action.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart';
import 'package:dashboard_kit/dashboard_kit.dart' show DashPressable;
import 'package:flutter/material.dart';
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

  testWidgets('ADM-APP-070 ADM-APP-071 ADM-APP-072: Ctrl+K opens it, typing '
      'narrows, a pick navigates', (tester) async {
    final h = await pumpShell(tester);
    await ctrlK(tester);
    await h.settle();
    // The title and the hint are for screen readers only, as on the web.
    expect(text('Jump to any page'), findsNothing);
    expect(
      tester.getSemantics(find.byType(DashCommandPalette)),
      containsSemantics(label: 'Search', hint: 'Jump to any page'),
    );
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

  testWidgets('ADM-APP-070: Ctrl+K again closes it', (tester) async {
    final h = await pumpShell(tester);
    await ctrlK(tester);
    await h.settle();
    expect(find.byType(DashCommandPalette), findsOneWidget);
    await ctrlK(tester);
    await h.settle();
    expect(find.byType(DashCommandPalette), findsNothing);
  });

  testWidgets('ADM-APP-071: arrows move, Enter opens', (tester) async {
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

  testWidgets('ADM-APP-072: no match says so', (tester) async {
    final h = await pumpShell(tester);
    await h.tap(labelled('Search').first);
    await h.enterText(find.byType(DashCommandPalette), 'zzzzqq');
    expect(text('No results found'), findsOneWidget);
  });

  testWidgets('ADM-APP-031 ADM-APP-072: only the pages this person sees', (
    tester,
  ) async {
    final h = await pumpShell(tester, persona: Persona.limited);
    await h.tap(labelled('Search').first);
    final p = find.byType(DashCommandPalette);
    expect(find.descendant(of: p, matching: text('Tills')), findsOneWidget);
    expect(find.descendant(of: p, matching: text('Floor')), findsNothing);
    expect(find.descendant(of: p, matching: text('Discounts')), findsNothing);
  });

  testWidgets('ADM-APP-070: the Search button, then Ctrl+K: one palette, and '
      'Ctrl+K closes it', (tester) async {
    final h = await pumpShell(tester);
    await h.tap(labelled('Search').first);
    expect(find.byType(DashCommandPalette), findsOneWidget);
    await ctrlK(tester);
    await h.settle();
    expect(find.byType(DashCommandPalette), findsNothing);
    await ctrlK(tester);
    await h.settle();
    expect(find.byType(DashCommandPalette), findsOneWidget);
    // The button while it is open opens no second one.
    await showDashCommandPalette(tester.element(find.byType(PaletteButton)));
    await h.settle();
    expect(find.byType(DashCommandPalette), findsOneWidget);
  });

  testWidgets('ADM-APP-071: the highlight never leaves the list\'s view', (
    tester,
  ) async {
    final h = await pumpShell(tester);
    await ctrlK(tester);
    await h.settle();
    // ignore: avoid_print
    print('DBG0 ${FocusManager.instance.primaryFocus?.context?.widget.runtimeType} ${FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<DashCommandPalette>() != null} ${FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>() != null}');
    for (var i = 0; i < 20; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await h.settle(rounds: 1);
    }
    final palette = find.byType(DashCommandPalette);
    final list = find.descendant(of: palette, matching: find.byType(ListView));
    final row = find.descendant(
      of: palette,
      matching: find.byWidgetPredicate(
        (w) => w is DashPressable && w.selected == true,
      ),
    );
    // ignore: avoid_print
    print('DBG ${find.descendant(of: palette, matching: find.byType(DashPressable)).evaluate().length} ${tester.state<ScrollableState>(find.descendant(of: list, matching: find.byType(Scrollable)).first).position.pixels} focus=${FocusManager.instance.primaryFocus}');
    final view = tester.getRect(list);
    final r = tester.getRect(row);
    expect(r.top, greaterThanOrEqualTo(view.top - 0.5));
    expect(r.bottom, lessThanOrEqualTo(view.bottom + 0.5));
  });

  testWidgets('ADM-APP-073: a pick keeps the branch and the period', (
    tester,
  ) async {
    final h = await pumpShell(
      tester,
      path: '/?branchId=${SeedIds.zamalek}&preset=7d',
    );
    await ctrlK(tester);
    await h.settle();
    await h.enterText(find.byType(DashCommandPalette), 'tills');
    await h.tap(
      find.descendant(
        of: find.byType(DashCommandPalette),
        matching: text('Tills'),
      ),
    );
    expect(h.location.path, '/tills');
    expect(h.container.read(scopeProvider).branchId, SeedIds.zamalek);
    expect(h.container.read(scopeProvider).preset, ScopePreset.last7Days);
  });
}
