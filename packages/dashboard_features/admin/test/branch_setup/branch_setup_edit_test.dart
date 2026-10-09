// Branch setup: the header actions, the lock, the draft, the toolbar and the
// setup picker (ADM-BSU-013…033).
import 'package:dashboard_admin/src/branch_setup/builder_canvas.dart';
import 'package:dashboard_admin/src/branch_setup/plan.dart';
import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

BuilderCanvas canvasOf(WidgetTester t) =>
    t.widget<BuilderCanvas>(find.byType(BuilderCanvas));

BuilderPlan planOf(WidgetTester t) => canvasOf(t).plan;

Finder byKey(String k) => find.byKey(ValueKey(k));

bool enabled(WidgetTester t, String key) {
  final w = t.widget(byKey(key));
  return switch (w) {
    DashButton(:final onPressed) => onPressed != null,
    DashIconButton(:final onPressed) => onPressed != null,
    _ => throw StateError('$key is ${w.runtimeType}'),
  };
}

Future<void> chord(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool shift = false,
}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pump();
}

/// Renames the selected piece through the inspector's Name field.
Future<void> rename(DashHarness h, String name) async {
  final field = inInspector(find.byType(EditableText)).first;
  await h.enterText(field, name);
  await h.tester.testTextInput.receiveAction(TextInputAction.done);
  await h.settle();
}

void main() {
  testWidgets('ADM-BSU-013/016/017 header actions; starts Locked: no ports, '
      'no toolbar, fields off; the lock button and ⌘E toggle Editing', (
    tester,
  ) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.heliopolis);
    for (final k in ['bb-zoom-out', 'bb-fit', 'bb-zoom-in', 'bb-history']) {
      expect(byKey(k), findsOneWidget, reason: k);
    }
    expect(byKey('bb-unsaved'), findsNothing);
    expect(byKey('bb-discard'), findsNothing);
    expect(byKey('bb-save'), findsNothing);
    expect(pageText('Locked'), findsOneWidget);
    expect(find.byKey(const ValueKey('bb-toolbar')), findsNothing);
    expect(
      find.byWidgetPredicate((w) => '${w.key}'.contains('bb-port-')),
      findsNothing,
    );
    expect(canvasOf(tester).editable, isFalse);
    // Selecting still works; the inspector's fields are off, no Remove.
    await h.tap(cardTitled('Counter 1'));
    expect(canvasOf(tester).selection, hasLength(1));
    final name = tester.widget<DashTextInput>(
      inInspector(find.byType(DashTextInput)).first,
    );
    expect(name.enabled, isFalse);
    expect(byKey('bb-remove'), findsNothing);

    await h.tap(byKey('bb-lock'));
    expect(pageText('Editing'), findsOneWidget);
    expect(byKey('bb-toolbar'), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) => '${w.key}'.contains('bb-port-')),
      findsWidgets,
    );
    expect(byKey('bb-remove'), findsOneWidget);
    await chord(tester, LogicalKeyboardKey.keyE);
    await h.settle();
    expect(pageText('Locked'), findsOneWidget);
    expect(byKey('bb-toolbar'), findsNothing);
  });

  testWidgets('ADM-BSU-014 zoom ×1.25 within 10–400 %; Fit frames the pieces; '
      'the keys + - 0', (tester) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.heliopolis);
    final v = canvasOf(tester).viewport;
    final fitted = v.zoom;
    await h.tap(byKey('bb-zoom-in'));
    expect(v.zoom, closeTo(fitted * 1.25, 1e-9));
    await h.tap(byKey('bb-zoom-out'));
    await h.tap(byKey('bb-zoom-out'));
    expect(v.zoom, closeTo(fitted / 1.25, 1e-9));
    await h.tap(byKey('bb-fit'));
    expect(v.zoom, closeTo(fitted, 1e-9));
    for (var i = 0; i < 20; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.equal);
    }
    await h.settle();
    expect(v.zoom, kZoomMax);
    for (var i = 0; i < 40; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.minus);
    }
    await h.settle();
    expect(v.zoom, kZoomMin);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await h.settle();
    expect(v.zoom, closeTo(fitted, 1e-9));
    // A plain wheel pans; ctrl + wheel zooms about the pointer.
    final at = tester.getCenter(find.byType(BuilderCanvas));
    final x0 = v.x;
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(at));
    await tester.sendEventToBinding(mouse.scroll(const Offset(40, 0)));
    await h.settle();
    expect(v.x, closeTo(x0 + 40 / v.zoom, 1e-6));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -50)));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await h.settle();
    expect(v.zoom, greaterThan(fitted));
  });

  testWidgets('ADM-BSU-015 the plan is framed when it first arrives, not on '
      'later edits', (tester) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.heliopolis);
    final v = canvasOf(tester).viewport;
    expect(v.zoom, isNot(1.0), reason: 'framed on arrival');
    await h.tap(byKey('bb-zoom-in'));
    final zoomed = v.zoom;
    await h.tap(byKey('bb-lock'));
    await h.tap(byKey('bb-add'));
    await h.tap(top('POS'));
    expect(v.zoom, zoomed);
  });

  testWidgets('ADM-BSU-018/019 an edit makes the draft dirty (a move too); '
      'Discard drops it and clears undo', (tester) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.heliopolis);
    await h.tap(byKey('bb-lock'));
    await h.tap(cardTitled('Counter 1'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await h.settle();
    expect(byKey('bb-unsaved'), findsOneWidget);
    expect(pageText('Unsaved changes'), findsOneWidget);
    expect(byKey('bb-discard'), findsOneWidget);
    expect(byKey('bb-save'), findsOneWidget);
    expect(enabled(tester, 'bb-undo'), isTrue);
    expect(h.server.callsTo(BranchPlanRoutes.plan, method: 'PUT'), isEmpty);
    await h.tap(byKey('bb-discard'));
    expect(byKey('bb-unsaved'), findsNothing);
    expect(enabled(tester, 'bb-undo'), isFalse);
    expect(planOf(tester).device(BranchPlanSeed.counter)!.x, 0);
  });

  testWidgets('ADM-BSU-020 Save… waits for the problems in red; ⌘S opens the '
      'review only when dirty and clear', (tester) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.heliopolis);
    await chord(tester, LogicalKeyboardKey.keyS);
    await h.settle();
    expect(byKey('bb-review-save'), findsNothing, reason: 'clean: nothing');
    await h.tap(byKey('bb-lock'));
    await h.tap(cardTitled('Receipt printer'));
    // A blank IP: blocking.
    final ip = find.descendant(
      of: byKey('bb-ip'),
      matching: find.byType(EditableText),
    );
    await h.enterText(ip, '');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await h.settle();
    expect(enabled(tester, 'bb-save'), isFalse);
    expect(byKey('bb-fix-first'), findsOneWidget);
    expect(
      tester.widget<Tooltip>(byKey('bb-fix-first')).message,
      'Fix the problems marked in red first',
    );
    await chord(tester, LogicalKeyboardKey.keyS);
    await h.settle();
    expect(byKey('bb-review-save'), findsNothing);
    await h.enterText(ip, '192.168.1.44');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await h.settle();
    expect(enabled(tester, 'bb-save'), isTrue);
    // Focus away from the field, then ⌘S.
    await h.tap(cardTitled('Bar'));
    await chord(tester, LogicalKeyboardKey.keyS);
    await h.settle();
    expect(byKey('bb-review-save'), findsOneWidget);
  });

  testWidgets('ADM-BSU-021/087 someone else saves while the draft is dirty: '
      'the banner, the draft kept; "Load their version" follows theirs', (
    tester,
  ) async {
    final b = PlanBackend();
    final h = await pumpBuilder(
      tester,
      branchId: SeedIds.heliopolis,
      backend: b,
    );
    await h.tap(byKey('bb-lock'));
    await h.tap(cardTitled('Counter 1'));
    await rename(h, 'Front till');
    expect(cardTitled('Front till'), findsOneWidget);
    // Their save: the bar printer renamed.
    final view = await tester.runAsync(
      () => b.api.branchPlan.getPlan(branchId: SeedIds.heliopolis),
    );
    final theirs = BranchPlan.fromJson({
      ...view!.plan.toJson(),
      'printers': [
        for (final p in view.plan.printers!)
          {
            ...p.toJson(),
            if (p.id == BranchPlanSeed.barPrinter) 'name': 'Drinks printer',
          },
      ],
    });
    await tester.runAsync(
      () => b.api.branchPlan.savePlan(
        body: SavePlanRequest(
          branchId: SeedIds.heliopolis,
          expectedVersion: 2,
          plan: theirs,
        ),
      ),
    );
    h.realtime.current!.emit(
      'branch.plan_changed',
      data: '{"branch_id":"${SeedIds.heliopolis}","version":3}',
    );
    await h.settle();
    expect(byKey('bb-overtaken'), findsOneWidget);
    expect(
      pageText(
        "Someone saved this branch's plan while you were editing. Saving now would be refused.",
      ),
      findsOneWidget,
    );
    expect(cardTitled('Front till'), findsOneWidget, reason: 'draft kept');
    expect(enabled(tester, 'bb-save'), isTrue);
    await h.tap(byKey('bb-load-theirs'));
    expect(byKey('bb-overtaken'), findsNothing);
    expect(cardTitled('Counter 1'), findsOneWidget);
    expect(cardTitled('Drinks printer'), findsOneWidget);
    expect(byKey('bb-unsaved'), findsNothing);
  });

  testWidgets('ADM-BSU-022/087 a clean draft follows a newer plan; its undo '
      'steps are dropped', (tester) async {
    final b = PlanBackend();
    final h = await pumpBuilder(
      tester,
      branchId: SeedIds.heliopolis,
      backend: b,
    );
    await h.tap(byKey('bb-lock'));
    await h.tap(cardTitled('Counter 1'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await h.settle();
    await h.tap(byKey('bb-undo'));
    expect(enabled(tester, 'bb-redo'), isTrue);
    final view = await tester.runAsync(
      () => b.api.branchPlan.getPlan(branchId: SeedIds.heliopolis),
    );
    await tester.runAsync(
      () => b.api.branchPlan.savePlan(
        body: SavePlanRequest(
          branchId: SeedIds.heliopolis,
          expectedVersion: 2,
          plan: BranchPlan.fromJson({
            ...view!.plan.toJson(),
            'till_prints_kitchen': false,
          }),
        ),
      ),
    );
    h.realtime.current!.emit('branch.plan_changed', data: '{}');
    await h.settle();
    expect(planOf(tester).tillPrintsKitchen, isFalse);
    expect(enabled(tester, 'bb-redo'), isFalse);
    expect(enabled(tester, 'bb-undo'), isFalse);
    expect(byKey('bb-overtaken'), findsNothing);
  });

  testWidgets('ADM-BSU-026/027 the toolbar and its Add menu', (tester) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.heliopolis);
    await h.tap(byKey('bb-lock'));
    for (final k in ['bb-add', 'bb-undo', 'bb-redo', 'bb-remove-tool']) {
      expect(byKey(k), findsOneWidget, reason: k);
    }
    expect(
      pageText(
        'Drag a card to move it · drag from its dot to another card to connect them · ⌘S to save',
      ),
      findsOneWidget,
    );
    expect(enabled(tester, 'bb-undo'), isFalse);
    expect(enabled(tester, 'bb-redo'), isFalse);
    expect(enabled(tester, 'bb-remove-tool'), isFalse);
    await h.tap(byKey('bb-add'));
    for (final w in [
      'Front of house',
      'POS',
      'Waiter tablet',
      'Receipt printer',
      'Kitchen',
      'Kitchen section',
      'Kitchen screen',
      'Kitchen printer',
    ]) {
      expect(top(w), findsWidgets, reason: w);
    }
  });

  testWidgets('ADM-BSU-026/088 the toolbar hint shows only from 1024 px', (
    tester,
  ) async {
    final h = await pumpBuilder(
      tester,
      branchId: SeedIds.heliopolis,
      size: DashSize.phone,
    );
    await h.tap(byKey('bb-lock'));
    expect(byKey('bb-toolbar'), findsOneWidget);
    expect(find.textContaining('⌘S to save'), findsNothing);
  });

  testWidgets('ADM-BSU-028 a new piece: "<kind> N", in the middle of the view '
      'and clear of others, selected, one undo step', (tester) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.heliopolis);
    await h.tap(byKey('bb-lock'));
    Future<void> add(String what) async {
      await h.tap(byKey('bb-add'));
      await h.tap(top(what).last);
    }

    await add('POS');
    final pos = planOf(tester).devices.last;
    expect(pos.name, 'POS 2');
    expect(pos.receiptPrinterId, isNull);
    expect(pos.deviceId, isNull);
    expect(pos.x % 10, 0);
    expect(canvasOf(tester).selection, {pieceKey(PieceKind.device, pos.id)});
    final boxes = boxesOf(planOf(tester)).where((b) => !b.key.contains(pos.id));
    expect(
      boxes.any(
        (b) =>
            pos.x < b.x + b.w &&
            pos.x + kNodeW > b.x &&
            pos.y < b.y + b.h &&
            pos.y + kNodeH > b.y,
      ),
      isFalse,
    );
    await add('Kitchen printer');
    final printer = planOf(tester).printers.last;
    expect(printer.name, 'Kitchen printer 3');
    expect(printer.connection, 'network');
    expect(printer.port, 9100);
    expect(printer.paperMm, 80);
    expect(printer.brand, isNull);
    expect(printer.ip, isNull);
    await add('Kitchen section');
    final section = planOf(tester).sections.last;
    expect(section.name, 'Kitchen section 3');
    expect(section.isDefault, isFalse);
    expect(section.categoryIds, isEmpty);
    await h.tap(byKey('bb-undo'));
    expect(planOf(tester).sections, hasLength(2));
  });

  testWidgets('ADM-BSU-029 undo and redo: buttons and ⌘Z / ⌘⇧Z / ⌘Y, '
      'Editing only', (tester) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.heliopolis);
    await h.tap(byKey('bb-lock'));
    await h.tap(cardTitled('Counter 1'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await h.settle();
    double x() => planOf(tester).device(BranchPlanSeed.counter)!.x;
    expect(x(), 20);
    await chord(tester, LogicalKeyboardKey.keyZ);
    expect(x(), 10);
    await chord(tester, LogicalKeyboardKey.keyZ, shift: true);
    expect(x(), 20);
    await h.tap(byKey('bb-undo'));
    await h.tap(byKey('bb-undo'));
    expect(x(), 0);
    await chord(tester, LogicalKeyboardKey.keyY);
    expect(x(), 10);
    await h.tap(byKey('bb-redo'));
    expect(x(), 20);
    // Locked: the keys do nothing.
    await h.tap(byKey('bb-lock'));
    await chord(tester, LogicalKeyboardKey.keyZ);
    expect(x(), 20);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await h.settle();
    expect(x(), 20);
  });

  testWidgets('ADM-BSU-030 Remove: the toolbar, Delete and the inspector; a '
      'line goes before pieces; the catch-all passes on', (tester) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.heliopolis);
    await h.tap(byKey('bb-lock'));
    await h.tap(cardTitled('Bar printer'));
    await h.tap(byKey('bb-remove-tool'));
    expect(planOf(tester).printer(BranchPlanSeed.barPrinter), isNull);
    expect(
      planOf(tester).sections.first.printerIds,
      isNot(contains(BranchPlanSeed.barPrinter)),
    );
    await h.tap(cardTitled('Kitchen screen'));
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await h.settle();
    expect(planOf(tester).device(BranchPlanSeed.screen), isNull);
    expect(planOf(tester).sections.first.screenIds, isEmpty);
    // The catch-all removed: the next section takes the role.
    await h.tap(cardTitled('Bar'));
    await h.ensureAndTap(byKey('bb-remove'));
    final left = planOf(tester).sections;
    expect(left.single.name, 'Kitchen');
    expect(left.single.isDefault, isTrue);
    expect(canvasOf(tester).selection, isEmpty);
    expect(enabled(tester, 'bb-remove-tool'), isFalse);
  });

  testWidgets('ADM-BSU-031/066 a section with items cooking can leave the '
      'draft; the inspector warns', (tester) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.heliopolis);
    await h.tap(byKey('bb-lock'));
    await h.tap(cardTitled('Bar'));
    expect(byKey('bb-cooking'), findsOneWidget);
    expect(
      inInspector(
        find.text(
          "3 items are cooking here now. The section can't be removed until they're done.",
        ),
      ),
      findsOneWidget,
    );
    await h.ensureAndTap(byKey('bb-remove'));
    expect(cardTitled('Bar'), findsNothing);
  });

  testWidgets('ADM-BSU-032/033 the setup picker; a pick replaces the draft, '
      'unlocks and frames; Undo returns to the picker', (tester) async {
    final b = PlanBackend();
    b.db['branches'].find(SeedIds.maadi)!['printer_ip'] = null;
    b.db['devices'].removeWhere((d) => d['branch_id'] == SeedIds.maadi);
    final h = await pumpBuilder(tester, branchId: SeedIds.maadi, backend: b);
    expect(pageText('How is this branch set up?'), findsOneWidget);
    expect(
      pageText(
        'Pick the closest one. Everything it places can be changed, moved or removed afterwards.',
      ),
      findsOneWidget,
    );
    for (final s in Setup.values) {
      expect(byKey('bb-setup-${s.name}'), findsOneWidget);
    }
    expect(pageText('Most common'), findsNWidgets(2));
    await h.tap(byKey('bb-setup-tillPrinter'));
    final plan = planOf(tester);
    expect(canvasOf(tester).editable, isTrue);
    expect([for (final d in plan.devices) d.name], ['POS 1']);
    expect(
      [for (final p in plan.printers) (p.name, p.connection)],
      [('Receipt printer', 'usb'), ('Kitchen printer', 'network')],
    );
    expect(plan.sections.single.name, 'Kitchen');
    expect(plan.sections.single.isDefault, isTrue);
    expect(plan.sections.single.categoryIds, hasLength(7));
    // The kitchen printer has no IP yet: Save waits.
    expect(enabled(tester, 'bb-save'), isFalse);
    expect(h.server.callsTo(BranchPlanRoutes.plan, method: 'PUT'), isEmpty);
    await h.tap(byKey('bb-undo'));
    expect(pageText('How is this branch set up?'), findsOneWidget);
    await h.tap(byKey('bb-setup-sections'));
    expect([for (final s in planOf(tester).sections) s.name], ['Hot', 'Cold']);
    expect(
      [
        for (final d in planOf(tester).devices)
          if (d.kind == 'kitchen') d.name,
      ],
      ['Hot screen', 'Cold screen'],
    );
  });
}

extension on DashHarness {
  Future<void> ensureAndTap(Finder f) async {
    await tester.ensureVisible(f);
    await settle();
    await tap(f);
  }
}
