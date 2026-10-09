// Branch setup: the inspector (ADM-BSU-045…071) and a slot's setup code.
import 'package:dashboard_admin/src/area_seed.dart';
import 'package:dashboard_admin/src/branch_setup/branch_setup_providers.dart';
import 'package:dashboard_admin/src/branch_setup/builder_canvas.dart';
import 'package:dashboard_admin/src/branch_setup/plan.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

BuilderCanvas canvasOf(WidgetTester t) =>
    t.widget<BuilderCanvas>(find.byType(BuilderCanvas));

BuilderPlan planOf(WidgetTester t) => canvasOf(t).plan;

Finder byKey(String k) => find.byKey(ValueKey(k));

Finder ins(String text) => inInspector(find.text(text));

Future<void> unlock(DashHarness h) => h.tap(byKey('bb-lock'));

/// Brings [f] into view (the inspector scrolls), then taps it.
Future<void> reach(DashHarness h, Finder f) async {
  await h.tester.ensureVisible(f.first);
  await h.settle();
  await h.tap(f.first);
}

Future<void> commit(DashHarness h, Finder field, String text) async {
  await h.enterText(
    find.descendant(of: field, matching: find.byType(EditableText)),
    text,
  );
  await h.tester.testTextInput.receiveAction(TextInputAction.done);
  await h.settle();
}

final String _kitchen = BranchPlanSeed.stationId('heliopolis', 'kitchen');

void main() {
  testWidgets('ADM-BSU-045 docked at the end side from 1280 px, under the '
      'canvas below; the panel follows the selection', (tester) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.heliopolis);
    final canvas = tester.getRect(find.byType(BuilderCanvas));
    final panel = tester.getRect(byKey('bb-inspector'));
    expect(panel.left, greaterThanOrEqualTo(canvas.right - 1));
    expect(panel.width, closeTo(340, 1));
    expect(ins('This branch'), findsOneWidget);
    await h.tap(cardTitled('Counter 1'));
    expect(ins('POS'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await h.tap(cardTitled('Bar'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(ins('Selection'), findsOneWidget);
  });

  testWidgets('ADM-BSU-045/088 below 1280 px the inspector sits under the '
      'canvas', (tester) async {
    await pumpBuilder(
      tester,
      branchId: SeedIds.heliopolis,
      size: DashSize.tablet,
    );
    final canvas = tester.getRect(find.byType(BuilderCanvas));
    final panel = tester.getRect(byKey('bb-inspector'));
    expect(panel.top, greaterThanOrEqualTo(canvas.bottom - 1));
  });

  testWidgets('ADM-BSU-046/047/048/050/051 the branch summary: the setup it '
      'reads as, kitchen chits, checks, categories in no section, the '
      'locked hint', (tester) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.heliopolis);
    expect(ins('Kitchen sections'), findsOneWidget);
    expect(
      ins(
        'The kitchen is split into sections. Each gets only its own items, on its own screens or printers.',
      ),
      findsOneWidget,
    );
    expect(ins('The till prints kitchen chits'), findsOneWidget);
    expect(ins(h.t('builder.tillPrintsKitchenHintSections')), findsOneWidget);
    expect(ins('Every order has somewhere to go.'), findsOneWidget);
    expect(ins('Categories in no section'.toUpperCase()), findsOneWidget);
    expect(
      ins(
        'These go to Bar, the section that takes whatever no other section claims.',
      ),
      findsOneWidget,
    );
    for (final c in ['Tea & More', 'Fresh Juice', 'Bakery', 'Desserts']) {
      expect(ins(c), findsOneWidget, reason: c);
    }
    expect(ins(h.t('builder.lockedHint')), findsOneWidget);
    // Locked: the switch is off-limits.
    final chits = tester.widget<DashSwitch>(byKey('bb-till-chits'));
    expect(chits.enabled, isFalse);
    await unlock(h);
    expect(ins(h.t('builder.lockedHint')), findsNothing);
    await h.tap(byKey('bb-till-chits'));
    expect(planOf(tester).tillPrintsKitchen, isFalse);
    await h.tap(byKey('bb-undo'));
    expect(planOf(tester).tillPrintsKitchen, isTrue);
  });

  testWidgets('ADM-BSU-046/047 a till-only branch: "Till only" and the chits '
      'hint for no sections', (tester) async {
    await pumpBuilder(tester, branchId: SeedIds.maadi);
    expect(ins('Till only'), findsOneWidget);
    expect(
      ins(
        "Off: orders go nowhere but the receipt. On: each order also prints a chit for the kitchen on the till's printer.",
      ),
      findsOneWidget,
    );
  });

  testWidgets('ADM-BSU-048/049 checks: blocking first, each selects its '
      'piece; the problem sentences', (tester) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.zamalek);
    // Zamalek: the kitchen screen shows no section (a warning).
    expect(
      ins('Kitchen screen shows no section yet, so it will stay empty.'),
      findsOneWidget,
    );
    await unlock(h);
    await h.tap(cardTitled('Kitchen printer'));
    await commit(h, byKey('bb-ip'), '');
    await h.tap(cardTitled('Kitchen'));
    // Untick its printer: Kitchen has nowhere to send orders, and the kitchen
    // printer prints for no section.
    await reach(h, find.widgetWithText(DashPressable, 'Kitchen printer').last);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
    final rows = [
      for (var i = 0; i < 10; i++)
        if (byKey('bb-problem-$i').evaluate().isNotEmpty) i,
    ];
    expect(rows.length, greaterThanOrEqualTo(4));
    expect(
      ins('Kitchen has no screen or printer, so its orders would go nowhere.'),
      findsOneWidget,
    );
    expect(
      ins('Kitchen printer is on the network but has no IP address.'),
      findsOneWidget,
    );
    expect(
      ins(
        'Kitchen printer is not linked to a section, so nothing prints on it.',
      ),
      findsOneWidget,
    );
    // Blocking ones come first.
    final firstText = tester
        .widget<Text>(
          find.descendant(
            of: byKey('bb-problem-0'),
            matching: find.byType(Text),
          ),
        )
        .data;
    expect(firstText, contains('has no screen or printer'));
    await h.tap(
      find.ancestor(
        of: ins('Kitchen printer is on the network but has no IP address.'),
        matching: find.byType(DashPressable),
      ),
    );
    expect(ins('Kitchen printer'), findsWidgets);
    expect(canvasOf(tester).selection, hasLength(1));
  });

  testWidgets('ADM-BSU-052 several selected: the count, the hint, Remove for '
      'all', (tester) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.heliopolis);
    await unlock(h);
    await h.tap(cardTitled('Bar printer'));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await h.tap(cardTitled('Kitchen printer'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(ins('2 pieces'), findsOneWidget);
    expect(ins(h.t('builder.manyHint')), findsOneWidget);
    await h.tap(byKey('bb-remove'));
    expect(planOf(tester).printers, hasLength(1));
  });

  testWidgets('ADM-BSU-053 the name commits on Enter or blur, one undo step '
      'each; blank is allowed in the draft', (tester) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.heliopolis);
    await unlock(h);
    await h.tap(cardTitled('Counter 1'));
    final field = find.descendant(
      of: byKey('bb-name'),
      matching: find.byType(EditableText),
    );
    await h.enterText(field, 'Front');
    expect(cardTitled('Front'), findsNothing, reason: 'not committed yet');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await h.settle();
    expect(cardTitled('Front'), findsOneWidget);
    expect(ins('Front'), findsWidgets);
    // Blur commits too.
    await h.enterText(field, '');
    await h.tap(cardTitled('Bar'));
    await h.tap(cardTitled('Unnamed'));
    expect(ins('—'), findsOneWidget);
    await h.tap(byKey('bb-undo'));
    expect(cardTitled('Front'), findsOneWidget);
    await h.tap(byKey('bb-undo'));
    expect(cardTitled('Counter 1'), findsOneWidget);
  });

  testWidgets('ADM-BSU-054/056/057 a POS slot: receipts print on, the device '
      'and its status, the registered device select', (tester) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.zamalek);
    await unlock(h);
    await h.tap(cardTitled('Counter 1'));
    expect(ins('Receipts print on'.toUpperCase()), findsOneWidget);
    expect(ins(h.t('builder.theDeviceHint')), findsOneWidget);
    expect(ins('Counter 1 · online'), findsOneWidget);
    await h.tap(cardTitled('Counter 2'));
    expect(
      find.descendant(
        of: byKey('bb-inspector'),
        matching: find.textContaining('Counter 2 · last seen '),
      ),
      findsOneWidget,
    );
    await h.tap(byKey('bb-receipt-select'));
    await h.tap(top('No printer').last);
    BuilderDevice named(String n) =>
        planOf(tester).devices.firstWhere((d) => d.name == n);
    expect(named('Counter 2').receiptPrinterId, isNull);
    // Take Counter 1's install into Counter 2's place.
    await h.tap(byKey('bb-device-select'));
    expect(top('None'), findsWidgets);
    await h.tap(top('Counter 1 · in Counter 1').last);
    expect(named('Counter 1').deviceId, isNull);
    expect(named('Counter 2').deviceId, AdminSeed.deviceId('zamalek', 'T1'));
    expect(
      pieceOf(tester, cardTitled('Counter 1')).presence!.label,
      'Not set up',
    );
    await h.tap(byKey('bb-undo'));
    expect(named('Counter 1').deviceId, AdminSeed.deviceId('zamalek', 'T1'));
  });

  testWidgets('ADM-BSU-054/055/057 empty lists: no receipt printer, no '
      'section, no matching install', (tester) async {
    final b = PlanBackend();
    b.db['branches'].find(SeedIds.maadi)!['printer_ip'] = null;
    final h = await pumpBuilder(tester, branchId: SeedIds.maadi, backend: b);
    await unlock(h);
    await h.tap(cardTitled('Counter 1'));
    expect(ins(h.t('builder.noReceiptPrinters')), findsOneWidget);
    await h.tap(byKey('bb-add'));
    await h.tap(top('Kitchen screen').last);
    expect(ins('No kitchen sections yet.'), findsOneWidget);
    expect(ins('No device set up yet'), findsOneWidget);
    expect(byKey('bb-device-select'), findsNothing, reason: 'no KDS at Maadi');
  });

  testWidgets('ADM-BSU-055 a kitchen screen ticks the sections it shows', (
    tester,
  ) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.heliopolis);
    await unlock(h);
    await h.tap(cardTitled('Kitchen screen'));
    expect(ins('Sections shown here'.toUpperCase()), findsOneWidget);
    await h.tap(ins('Kitchen'));
    expect(planOf(tester).section(_kitchen)!.screenIds, [
      BranchPlanSeed.screen,
    ]);
    await h.tap(ins('Bar'));
    expect(
      planOf(
        tester,
      ).section(BranchPlanSeed.stationId('heliopolis', 'bar'))!.screenIds,
      isEmpty,
    );
  });

  testWidgets('ADM-BSU-058 a slot not saved yet asks for a save first', (
    tester,
  ) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.zamalek);
    await h.tap(cardTitled('Counter 1'));
    expect(ins(h.t('builder.saveForCode')), findsOneWidget);
    expect(byKey('bb-get-code'), findsNothing);
  });

  testWidgets('ADM-BSU-059 a setup code for a saved slot (Locked too): the '
      'code, its expiry, /devices refreshed; gone on another selection', (
    tester,
  ) async {
    final b = PlanBackend();
    final h = await pumpBuilder(
      tester,
      branchId: SeedIds.heliopolis,
      backend: b,
    );
    final seen = watchInvalidations(h);
    await h.tap(cardTitled('Kitchen screen'));
    await reach(h, byKey('bb-get-code'));
    final call = h.server
        .callsTo(BranchPlanRoutes.codes, method: 'POST')
        .single;
    expect(call.body, {
      'branch_id': SeedIds.heliopolis,
      'slot_id': BranchPlanSeed.screen,
    });
    final row = b.codes.rows.last;
    expect(row['slot_id'], BranchPlanSeed.screen);
    expect(row['kind'], 'kds');
    expect(row['label'], 'Kitchen screen');
    expect(byKey('bb-slot-code'), findsOneWidget);
    expect(ins(row['code']! as String), findsOneWidget);
    expect(ins('On the device, enter'), findsOneWidget);
    expect(
      find.descendant(
        of: byKey('bb-inspector'),
        matching: find.textContaining('Works once, until '),
      ),
      findsOneWidget,
    );
    expect(seen, contains(equals(['/devices'])));
    await h.tap(cardTitled('Counter 1'));
    await h.tap(cardTitled('Kitchen screen'));
    expect(byKey('bb-slot-code'), findsNothing);
    expect(byKey('bb-get-code'), findsOneWidget);
  });

  testWidgets('ADM-BSU-059/086 a refused setup code toasts; the slot a save '
      'removed is 404', (tester) async {
    final b = PlanBackend();
    final h = await pumpBuilder(
      tester,
      branchId: SeedIds.heliopolis,
      backend: b,
    );
    await h.tap(cardTitled('Counter 1'));
    final denied = MockResponse.denied('branches.edit');
    b.server.fail('POST', BranchPlanRoutes.codes, denied);
    await reach(h, byKey('bb-get-code'));
    await h.expectToast(refusalText(h, denied));
    expect(byKey('bb-slot-code'), findsNothing);
    b.table(BranchPlanTables.slots).delete(BranchPlanSeed.counter);
    await reach(h, byKey('bb-get-code'));
    await h.expectToast(
      refusalText(h, MockResponse.notFound(BranchPlanRefusals.slotGone)),
    );
  });

  testWidgets('ADM-BSU-059/086 a manager saves the plan, but may not issue '
      'setup codes (branches.edit)', (tester) async {
    final h = await pumpBuilder(
      tester,
      branchId: SeedIds.zamalek,
      persona: Persona.manager,
    );
    await unlock(h);
    await h.tap(cardTitled('Terrace tablet'));
    await reach(h, byKey('bb-remove'));
    await h.tap(byKey('bb-save'));
    await h.tap(byKey('bb-review-save'));
    await h.expectToast('Branch plan saved');
    await h.tap(cardTitled('Counter 1'));
    await reach(h, byKey('bb-get-code'));
    await h.expectToast(refusalText(h, MockResponse.denied('branches.edit')));
  });

  testWidgets('ADM-BSU-060 a tablet entering a slot\'s code fills the slot; '
      'the card says so only once the plan is read again', (tester) async {
    final b = PlanBackend();
    final h = await pumpBuilder(
      tester,
      branchId: SeedIds.heliopolis,
      backend: b,
    );
    await unlock(h);
    await h.tap(cardTitled('Counter 1'));
    await reach(h, byKey('bb-device-select'));
    await h.tap(top('None').last);
    // Save the empty slot, then issue its code.
    await h.tap(byKey('bb-save'));
    await h.tap(byKey('bb-review-save'));
    await h.flushTimers();
    await h.tap(cardTitled('Counter 1'));
    await reach(h, byKey('bb-get-code'));
    final code = b.codes.rows.last['code']! as String;
    activateSlotCode(b.db, code, AdminSeed.deviceId('heliopolis', 'T1'));
    await h.settle();
    expect(
      pieceOf(tester, cardTitled('Counter 1')).presence!.label,
      'Not set up',
    );
    h.container.invalidate(branchPlanProvider(SeedIds.heliopolis));
    await h.settle();
    expect(
      pieceOf(tester, cardTitled('Counter 1')).presence!.label,
      startsWith('Seen '),
    );
  });

  testWidgets('ADM-BSU-061/062/063/064 a printer: how it connects, IP and '
      'port, plugged into, brand and paper', (tester) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.heliopolis);
    await unlock(h);
    await h.tap(cardTitled('Bar printer'));
    BuilderPrinter bar() => planOf(tester).printer(BranchPlanSeed.barPrinter)!;
    await commit(h, byKey('bb-port'), '9101');
    expect(bar().port, 9101);
    await commit(h, byKey('bb-port'), 'abc');
    expect(bar().port, 9100);
    await commit(h, byKey('bb-port'), '9102');
    await commit(h, byKey('bb-ip'), '  10.0.0.7 ');
    expect(bar().ip, '10.0.0.7');
    await h.tap(ins('USB'));
    expect(bar().connection, 'usb');
    expect(bar().port, isNull);
    expect(byKey('bb-ip'), findsNothing);
    expect(ins('Plugged into'), findsOneWidget);
    await h.tap(byKey('bb-host-select'));
    expect(top('Pick a device'), findsWidgets);
    await h.tap(top('Kitchen screen').last);
    expect(bar().hostDeviceId, BranchPlanSeed.screen);
    await h.tap(ins('Network'));
    expect(bar().port, 9100, reason: 'restored as 9100 once dropped');
    await reach(h, byKey('bb-brand'));
    await h.tap(top('Star').last);
    expect(bar().brand, 'star');
    await h.tap(byKey('bb-brand'));
    await h.tap(top('Other').last);
    expect(bar().brand, isNull);
    await reach(
      h,
      find.descendant(of: byKey('bb-paper'), matching: find.text('58 mm')),
    );
    expect(bar().paperMm, 58);
  });

  testWidgets('ADM-BSU-065 a kitchen printer ticks its sections; a receipt '
      'printer the tills it prints for', (tester) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.zamalek);
    await unlock(h);
    await h.tap(cardTitled('Bar printer'));
    await reach(h, ins('Kitchen'));
    expect(
      planOf(tester).sections.last.printerIds,
      hasLength(2),
      reason: 'Kitchen now prints on the bar printer too',
    );
    await h.tap(cardTitled('Receipt printer'));
    expect(ins('Prints receipts for'.toUpperCase()), findsOneWidget);
    await reach(h, ins('Floor tablet'));
    expect(
      planOf(
        tester,
      ).devices.firstWhere((d) => d.name == 'Floor tablet').receiptPrinterId,
      isNull,
    );
    await reach(h, ins('Floor tablet'));
    expect(
      planOf(
        tester,
      ).devices.firstWhere((d) => d.name == 'Floor tablet').receiptPrinterId,
      isNotNull,
    );
  });

  testWidgets('ADM-BSU-067/068 a section: the catch-all box, where its orders '
      'go', (tester) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.heliopolis);
    await h.tap(cardTitled('Kitchen'));
    expect(ins(h.t('builder.defaultHint')), findsOneWidget);
    expect(byKey('bb-make-default'), findsNothing, reason: 'locked');
    await unlock(h);
    await h.tap(cardTitled('Bar'));
    expect(ins('Takes everything else'), findsOneWidget);
    await h.tap(cardTitled('Kitchen'));
    await reach(h, byKey('bb-make-default'));
    expect(planOf(tester).section(_kitchen)!.isDefault, isTrue);
    expect(pieceOf(tester, cardTitled('Kitchen')).badge, 'Everything else');
    expect(pieceOf(tester, cardTitled('Bar')).badge, isNull);
    expect(ins('Where its orders go'.toUpperCase()), findsOneWidget);
    expect(ins('Kitchen screen'), findsWidgets);
    await reach(h, ins('Bar printer'));
    expect(planOf(tester).section(_kitchen)!.printerIds, hasLength(2));
  });

  testWidgets('ADM-BSU-068 no screen and no kitchen printer: the hint', (
    tester,
  ) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.maadi);
    await unlock(h);
    await h.tap(byKey('bb-add'));
    await h.tap(top('Kitchen section').last);
    expect(ins(h.t('builder.noOutputs')), findsOneWidget);
  });

  testWidgets('ADM-BSU-069 categories: select all (some → all, all → none), '
      'one at a time, "in <section>"', (tester) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.heliopolis);
    await unlock(h);
    await h.tap(cardTitled('Kitchen'));
    expect(ins(h.t('builder.categoriesHint')), findsOneWidget);
    expect(ins('1 of 7'), findsOneWidget);
    expect(ins('in Bar'), findsNWidgets(2));
    await reach(h, byKey('bb-select-all'));
    expect(planOf(tester).section(_kitchen)!.categoryIds, hasLength(7));
    expect(
      planOf(
        tester,
      ).section(BranchPlanSeed.stationId('heliopolis', 'bar'))!.categoryIds,
      isEmpty,
    );
    expect(ins('7 of 7'), findsOneWidget);
    await reach(h, byKey('bb-select-all'));
    expect(planOf(tester).section(_kitchen)!.categoryIds, isEmpty);
    await reach(h, ins('Bakery'));
    expect(planOf(tester).section(_kitchen)!.categoryIds, hasLength(1));
    await reach(h, ins('Bakery'));
    expect(planOf(tester).section(_kitchen)!.categoryIds, isEmpty);
  });

  testWidgets('ADM-BSU-069 a menu with no categories', (tester) async {
    final b = PlanBackend();
    b.db['categories'].removeWhere((c) => true);
    b.table(BranchPlanTables.categoryRoutes).removeWhere((r) => true);
    final h = await pumpBuilder(
      tester,
      branchId: SeedIds.heliopolis,
      backend: b,
    );
    await h.tap(cardTitled('Kitchen'));
    expect(ins('The menu has no categories yet.'), findsOneWidget);
  });

  testWidgets('ADM-BSU-070 items routed one by one, and the link to Item '
      'routing', (tester) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.zamalek);
    await h.tap(cardTitled('Kitchen'));
    expect(ins(h.t('builder.itemOverrides', count: 1)), findsOneWidget);
    await reach(h, byKey('bb-item-routing'));
    expect(h.location.path, '/settings/kitchen-routing');
  });

  testWidgets('ADM-BSU-071 Remove from the plan ends every piece panel '
      '(Editing)', (tester) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.heliopolis);
    for (final c in ['Counter 1', 'Receipt printer', 'Bar']) {
      await h.tap(cardTitled(c));
      expect(byKey('bb-remove'), findsNothing, reason: '$c locked');
    }
    await unlock(h);
    for (final c in ['Counter 1', 'Receipt printer', 'Bar']) {
      await h.tap(cardTitled(c));
      expect(byKey('bb-remove'), findsOneWidget, reason: c);
    }
  });
}
