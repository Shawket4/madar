// Branch setup: the canvas (ADM-BSU-034…044): cards, lines, selecting,
// moving, linking and the keyboard.
import 'package:dashboard_admin/src/branch_setup/builder_canvas.dart';
import 'package:dashboard_admin/src/branch_setup/plan.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

BuilderCanvas canvasOf(WidgetTester t) =>
    t.widget<BuilderCanvas>(find.byType(BuilderCanvas));

BuilderPlan planOf(WidgetTester t) => canvasOf(t).plan;

Finder byKey(String k) => find.byKey(ValueKey(k));

/// The global point of a world point on the canvas.
Offset screenOf(WidgetTester t, Offset world) {
  final c = canvasOf(t);
  return t.getTopLeft(find.byType(BuilderCanvas)) +
      c.viewport.toScreen(world.dx, world.dy);
}

/// The middle of [link] on screen.
Offset lineMid(WidgetTester t, PlanLink link) {
  final boxes = {for (final b in boxesOf(planOf(t))) b.key: b};
  final mid = routeBetween(boxes[link.from.key]!, boxes[link.to.key]!).mid;
  return screenOf(t, mid);
}

Future<void> unlock(DashHarness h) => h.tap(byKey('bb-lock'));

void main() {
  testWidgets('ADM-BSU-034/036/037 cards: icon per kind, "Unnamed", the '
      'problem triangle, printer and section lines', (tester) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.heliopolis);
    expect(pieceOf(tester, cardTitled('Counter 1')).icon, 'monitor');
    expect(pieceOf(tester, cardTitled('Kitchen screen')).icon, 'layout-grid');
    expect(pieceOf(tester, cardTitled('Receipt printer')).icon, 'receipt-text');
    expect(pieceOf(tester, cardTitled('Bar printer')).icon, 'printer');
    expect(pieceOf(tester, cardTitled('Bar')).icon, 'chef-hat');
    expect(pieceOf(tester, cardTitled('Bar printer')).detail, '192.168.1.60');
    expect(pieceOf(tester, cardTitled('Kitchen')).subtitle, '1 category');
    expect(pieceOf(tester, cardTitled('Kitchen')).badge, isNull);
    expect(pieceOf(tester, cardTitled('Kitchen')).detail, isNull);
    await unlock(h);
    // A printer goes USB: plugged into nothing → blocking; then into the till.
    await h.tap(cardTitled('Receipt printer'));
    await h.tap(inInspector(find.text('USB')));
    var p = pieceOf(tester, cardTitled('Receipt printer'));
    expect(p.detail, 'USB');
    expect(p.problem, PieceProblem.blocking);
    await h.tap(byKey('bb-host-select'));
    await h.tap(top('Counter 1').last);
    p = pieceOf(tester, cardTitled('Receipt printer'));
    expect(p.detail, 'USB · Counter 1');
    expect(p.problem, isNull);
    // Bluetooth, no host: just the word.
    await h.tap(inInspector(find.text('Bluetooth')));
    expect(
      pieceOf(tester, cardTitled('Receipt printer')).detail,
      'Bluetooth · Counter 1',
    );
    // Network with no IP.
    await h.tap(inInspector(find.text('Network')));
    expect(
      pieceOf(tester, cardTitled('Receipt printer')).detail,
      '192.168.1.40',
    );
    // A blank name: "Unnamed", blocking.
    await h.tap(cardTitled('Bar printer'));
    await h.enterText(inInspector(find.byType(EditableText)).first, '');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await h.settle();
    expect(
      pieceOf(tester, cardTitled('Unnamed')).problem,
      PieceProblem.blocking,
    );
    // A warning only: the kitchen screen showing no section.
    await h.tap(cardTitled('Bar'));
    await h.tap(inInspector(find.text('Kitchen screen')));
    expect(
      pieceOf(tester, cardTitled('Kitchen screen')).problem,
      PieceProblem.warning,
    );
  });

  testWidgets('ADM-BSU-035 device cards: the kind or the sections shown, and '
      'presence in words; an empty slot is dashed "Not set up"', (
    tester,
  ) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.heliopolis);
    expect(pieceOf(tester, cardTitled('Counter 1')).subtitle, 'POS');
    expect(pieceOf(tester, cardTitled('Counter 1')).placeholder, isFalse);
    await unlock(h);
    await h.tap(byKey('bb-add'));
    await h.tap(top('Waiter tablet').last);
    final slot = pieceOf(tester, cardTitled('Waiter tablet 1'));
    expect(slot.subtitle, 'Waiter tablet');
    expect(slot.placeholder, isTrue);
    expect(slot.presence!.label, 'Not set up');
    expect(slot.presence!.tone, PresenceTone.unclaimed);
    // The screen shows two sections: their names joined.
    await h.tap(cardTitled('Kitchen'));
    await h.tap(inInspector(find.text('Kitchen screen')));
    expect(
      pieceOf(tester, cardTitled('Kitchen screen')).subtitle,
      'Bar · Kitchen',
    );
  });

  testWidgets('ADM-BSU-034 the canvas is never mirrored in Arabic', (
    tester,
  ) async {
    await pumpBuilder(tester, branchId: SeedIds.heliopolis, locale: 'ar');
    final till = tester.getCenter(cardTitled('Counter 1'));
    final bar = tester.getCenter(cardTitled('Bar'));
    expect(till.dx, lessThan(bar.dx), reason: 'x 0 stays left of x 340');
  });

  testWidgets('ADM-BSU-038 the lines the plan draws, the legend and the '
      'counts', (tester) async {
    await pumpBuilder(tester, branchId: SeedIds.heliopolis);
    final links = linksOf(planOf(tester));
    expect([for (final l in links) l.kind]..sort((a, b) => a.index - b.index), [
      LinkKind.shows,
      LinkKind.prints,
      LinkKind.prints,
      LinkKind.receipt,
    ]);
    for (final w in ['Shows on', 'Prints on', 'Receipts', 'Plugged into']) {
      expect(pageText(w), findsOneWidget, reason: w);
    }
    expect(pageText('Devices 2 · Printers 3 · Sections 2'), findsOneWidget);
    expect(linkStyle(LinkKind.prints).dash, isNotNull);
    expect(linkStyle(LinkKind.host).dash, isNotNull);
    expect(linkStyle(LinkKind.shows).dash, isNull);
  });

  testWidgets(
    'ADM-BSU-039 (divergence) selecting: a tap selects only that card, Shift adds '
    'and removes, empty canvas clears (Shift keeps), Escape clears',
    (tester) async {
      final h = await pumpBuilder(tester, branchId: SeedIds.heliopolis);
      final till = pieceKey(PieceKind.device, BranchPlanSeed.counter);
      final screen = pieceKey(PieceKind.device, BranchPlanSeed.screen);
      await h.tap(cardTitled('Counter 1'));
      expect(canvasOf(tester).selection, {till});
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await h.tap(cardTitled('Kitchen screen'));
      expect(canvasOf(tester).selection, {till, screen});
      expect(inInspector(find.text('2 pieces')), findsOneWidget);
      await h.tap(cardTitled('Counter 1'));
      expect(canvasOf(tester).selection, {screen});
      // Shift on empty canvas keeps the selection.
      final empty = screenOf(tester, const Offset(200, -200));
      await tester.tapAt(empty);
      await h.settle();
      expect(canvasOf(tester).selection, {screen});
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tapAt(empty);
      await h.settle();
      expect(canvasOf(tester).selection, isEmpty);
      await h.tap(cardTitled('Bar'));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();
      expect(canvasOf(tester).selection, isEmpty);
    },
  );

  testWidgets('ADM-BSU-039 Tab reaches the cards and focusing one selects it', (
    tester,
  ) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.heliopolis);
    for (var i = 0; i < 30 && canvasOf(tester).selection.isEmpty; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    await h.settle();
    expect(canvasOf(tester).selection, hasLength(1));
    final first = canvasOf(tester).selection.single;
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await h.settle();
    expect(canvasOf(tester).selection.single, isNot(first));
  });

  testWidgets('ADM-BSU-040 moving: a drag moves the selection on the grid, one '
      'undo step; arrows nudge 10 (Shift 1); Locked a drag pans', (
    tester,
  ) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.heliopolis);
    final v = canvasOf(tester).viewport;
    // Locked: the drag pans, nothing moves.
    final x0 = v.x;
    await tester.dragFrom(
      tester.getCenter(cardTitled('Counter 1')),
      const Offset(-60, 0),
    );
    await h.settle();
    expect(planOf(tester).device(BranchPlanSeed.counter)!.x, 0);
    expect(v.x, greaterThan(x0));
    expect(byKey('bb-unsaved'), findsNothing);

    await unlock(h);
    await h.tap(cardTitled('Counter 1'));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await h.tap(cardTitled('Receipt printer'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    final step = 37 * v.zoom; // 37 world units: snaps to 40
    await tester.dragFrom(
      tester.getCenter(cardTitled('Counter 1')),
      Offset(step, 0),
    );
    await h.settle();
    final plan = planOf(tester);
    expect(plan.device(BranchPlanSeed.counter)!.x, 40);
    expect(plan.printer(BranchPlanSeed.receipt)!.x, 40);
    await h.tap(byKey('bb-undo'));
    expect(planOf(tester).device(BranchPlanSeed.counter)!.x, 0);
    expect(planOf(tester).printer(BranchPlanSeed.receipt)!.x, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await h.settle();
    final d = planOf(tester).device(BranchPlanSeed.counter)!;
    expect((d.x, d.y), (-1.0, 10.0));
  });

  testWidgets('ADM-BSU-041/042 linking from a port: onto a card that takes '
      'it, onto one that can\'t (toast), onto nothing', (tester) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.heliopolis);
    await unlock(h);
    final kitchen = pieceKey(
      PieceKind.section,
      BranchPlanSeed.stationId('heliopolis', 'kitchen'),
    );
    Future<void> drawFrom(String key, Offset to) async {
      final start = tester.getCenter(byKey('bb-port-$key'));
      final g = await tester.startGesture(start);
      await g.moveTo(start + const Offset(20, 0));
      await tester.pump();
      await g.moveTo(to);
      await tester.pump();
      await g.up();
      await h.settle();
    }

    // Kitchen section → the kitchen screen: "shows".
    await drawFrom(kitchen, tester.getCenter(cardTitled('Kitchen screen')));
    expect(
      planOf(
        tester,
      ).section(BranchPlanSeed.stationId('heliopolis', 'kitchen'))!.screenIds,
      [BranchPlanSeed.screen],
    );
    // Kitchen section → the till: refused with a toast, nothing changes.
    final before = planOf(tester);
    await drawFrom(kitchen, tester.getCenter(cardTitled('Counter 1')));
    await h.expectToast("Those two can't be connected that way.");
    expect(identical(planOf(tester), before), isTrue);
    // Onto empty canvas: nothing.
    await drawFrom(kitchen, screenOf(tester, const Offset(-300, -300)));
    expect(identical(planOf(tester), before), isTrue);
    // A new receipt printer drawn from the till replaces its receipt printer.
    await h.tap(byKey('bb-add'));
    await h.tap(top('Receipt printer').last);
    final r2 = planOf(tester).printers.last.id;
    await drawFrom(
      pieceKey(PieceKind.device, BranchPlanSeed.counter),
      tester.getCenter(cardTitled('Receipt printer 2')),
    );
    expect(planOf(tester).device(BranchPlanSeed.counter)!.receiptPrinterId, r2);
  });

  testWidgets('ADM-BSU-043 a line: hover names it; a press selects it with '
      'its pill; ✕ or Delete removes it', (tester) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.heliopolis);
    final shows = linksOf(
      planOf(tester),
    ).firstWhere((l) => l.kind == LinkKind.shows);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(lineMid(tester, shows));
    await h.settle();
    expect(
      find.descendant(
        of: find.byType(BuilderCanvas),
        matching: find.text('Shows on'),
      ),
      findsOneWidget,
    );
    await mouse.moveTo(Offset.zero);
    await h.settle();

    await h.tap(cardTitled('Counter 1'));
    await tester.tapAt(lineMid(tester, shows));
    await h.settle();
    expect(canvasOf(tester).selectedLink, shows);
    expect(canvasOf(tester).selection, isEmpty);
    expect(byKey('bb-link-pill'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Remove this line'),
      findsNothing,
      reason: 'locked',
    );
    await unlock(h);
    await h.tap(find.bySemanticsLabel('Remove this line'));
    expect(
      linksOf(planOf(tester)).where((l) => l.kind == LinkKind.shows),
      isEmpty,
    );
    expect(canvasOf(tester).selectedLink, isNull);
    // Delete removes a selected line before any piece.
    final receipt = linksOf(
      planOf(tester),
    ).firstWhere((l) => l.kind == LinkKind.receipt);
    await tester.tapAt(lineMid(tester, receipt));
    await h.settle();
    expect(canvasOf(tester).selectedLink, receipt);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await h.settle();
    expect(
      linksOf(planOf(tester)).where((l) => l.kind == LinkKind.receipt),
      isEmpty,
    );
    expect(planOf(tester).devices, hasLength(2));
  });

  testWidgets('ADM-BSU-044 keys typed in the inspector never reach the '
      'canvas', (tester) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.heliopolis);
    await unlock(h);
    await h.tap(cardTitled('Bar'));
    final name = inInspector(find.byType(EditableText)).first;
    await h.tap(name);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyEvent(LogicalKeyboardKey.equal);
    await h.settle();
    expect(
      planOf(tester).sections,
      hasLength(2),
      reason: 'Backspace edits text',
    );
    expect(cardTitled('Bar'), findsOneWidget);
    expect(canvasOf(tester).selection, hasLength(1));
  });
}
