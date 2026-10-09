// Branch setup: History, the review and the save, refusals, the leave guard
// (ADM-BSU-023…025, 072…085).
import 'package:dashboard_admin/src/area_seed.dart';
import 'package:dashboard_admin/src/branch_setup/builder_canvas.dart';
import 'package:dashboard_admin/src/branch_setup/plan.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
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

Finder review(String text) => find.descendant(
  of: find.byType(DashSurface),
  matching: find.text(text),
);

Future<void> unlock(DashHarness h) => h.tap(byKey('bb-lock'));

Future<void> reach(DashHarness h, Finder f) async {
  await h.tester.ensureVisible(f.first);
  await h.settle();
  await h.tap(f.first);
}

/// Unlocks, removes the piece titled [title] and opens the review.
Future<void> removeAndReview(DashHarness h, String title) async {
  await unlock(h);
  await h.tap(cardTitled(title));
  await reach(h, byKey('bb-remove'));
  await h.tap(byKey('bb-save'));
}

void main() {
  testWidgets('ADM-BSU-023/024 History reads the versions only while open: '
      'newest first, the current one disabled, when and who', (tester) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.heliopolis);
    expect(h.server.callsTo(BranchPlanRoutes.versions), isEmpty);
    await h.tap(byKey('bb-history'));
    final calls = h.server.callsTo(BranchPlanRoutes.versions);
    expect(calls, hasLength(1));
    expect(calls.single.query['branch_id'], [SeedIds.heliopolis]);
    expect(
      top('Load an earlier plan into the editor. Nothing changes until you save it.'),
      findsOneWidget,
    );
    final rows = [
      for (final e in find.byWidgetPredicate((w) => '${w.key}'.contains('bb-version-')).evaluate())
        '${e.widget.key}',
    ];
    expect(rows, ["[<'bb-version-2'>]", "[<'bb-version-1'>]"]);
    expect(top('Version 2 · current'), findsOneWidget);
    expect(
      find.textContaining('· Nour El-Sayed').hitTestable(),
      findsNWidgets(2),
    );
    final current = tester.widget<DashPressable>(
      find.descendant(of: byKey('bb-version-2'), matching: find.byType(DashPressable)),
    );
    expect(current.enabled, isFalse);
  });

  testWidgets('ADM-BSU-024 "Loading…" while the versions are read; a failed '
      'read shows the hint alone', (tester) async {
    final b = PlanBackend();
    final gate = b.server.hold('GET', BranchPlanRoutes.versions);
    final h = await pumpBuilder(tester, branchId: SeedIds.heliopolis, backend: b);
    await h.tap(byKey('bb-history'));
    expect(top('Loading…'), findsOneWidget);
    gate.release();
    await h.settle();
    expect(top('Loading…'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();

    final b2 = PlanBackend();
    b2.server.fail(
      'GET',
      BranchPlanRoutes.versions,
      MockResponse.error(500, 'boom'),
      times: null,
    );
    final h2 = await pumpBuilder(tester, branchId: SeedIds.heliopolis, backend: b2);
    await h2.tap(byKey('bb-history'));
    expect(
      top('Load an earlier plan into the editor. Nothing changes until you save it.'),
      findsOneWidget,
    );
    expect(find.byWidgetPredicate((w) => '${w.key}'.contains('bb-version-')), findsNothing);
  });

  testWidgets('ADM-BSU-025 loading a version: one undo step, unlocked, saved '
      'as a new version over the current one', (tester) async {
    final b = PlanBackend();
    final h = await pumpBuilder(tester, branchId: SeedIds.heliopolis, backend: b);
    await h.tap(byKey('bb-history'));
    await h.tap(byKey('bb-version-1'));
    expect(canvasOf(tester).editable, isTrue);
    expect(cardTitled('Kitchen screen'), findsNothing);
    expect(byKey('bb-unsaved'), findsOneWidget);
    await h.tap(byKey('bb-undo'));
    expect(cardTitled('Kitchen screen'), findsOneWidget);
    await h.tap(byKey('bb-redo'));
    await h.tap(byKey('bb-save'));
    await h.tap(byKey('bb-review-save'));
    final put = lastSave(h.server);
    expect(put['expected_version'], 2);
    await h.expectToast('Branch plan saved');
    expect(b.db['branches'].find(SeedIds.heliopolis)!['hardware_plan_version'], 3);
  });

  testWidgets('ADM-BSU-025 a version names a retired device and a deleted '
      'category: both let go', (tester) async {
    final b = PlanBackend();
    b.db[AdminTables.devices].find(AdminSeed.deviceId('heliopolis', 'T1'))!['retired_at'] =
        '2026-10-01T08:00:00Z';
    b.db['categories'].removeWhere((c) => c['id'] == MockSeed.categoryId('iced'));
    final h = await pumpBuilder(tester, branchId: SeedIds.heliopolis, backend: b);
    await h.tap(byKey('bb-history'));
    await h.tap(byKey('bb-version-1'));
    final plan = planOf(tester);
    expect(plan.device(BranchPlanSeed.counter)!.deviceId, isNull);
    expect(plan.sections.first.categoryIds, [MockSeed.categoryId('hot')]);
  });

  testWidgets('ADM-BSU-072/073/074/075 the review: first save, removed names '
      'in red, the kitchen routing changing', (tester) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.zamalek);
    await removeAndReview(h, 'Counter 2');
    expect(review('Save the branch plan?'), findsOneWidget);
    expect(
      review("This becomes the branch's plan. Devices and printers follow it from now on."),
      findsOneWidget,
    );
    expect(review('Removed'), findsOneWidget);
    expect(review('Counter 2'), findsOneWidget);
    // Zamalek is on auto with stations (kitchen screens); the plan has
    // sections without a screen: the till.
    expect(review('Kitchen'), findsOneWidget);
    expect(review('Kitchen screens'), findsOneWidget);
    expect(review('The POS handles the kitchen and prints its chits'), findsOneWidget);
    expect(review('Only positions on the canvas changed.'), findsNothing);
  });

  testWidgets('ADM-BSU-072/073 a later save: added and changed, or only '
      'positions', (tester) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.heliopolis);
    await unlock(h);
    await h.tap(cardTitled('Counter 1'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await h.settle();
    await h.tap(byKey('bb-save'));
    expect(
      review(
        "The branch's devices follow the new plan at once. Orders already sent to the kitchen finish where they were sent.",
      ),
      findsOneWidget,
    );
    expect(review('Only positions on the canvas changed.'), findsOneWidget);
    await h.tap(byKey('bb-review-cancel'));
    await h.tap(byKey('bb-add'));
    await h.tap(top('Waiter tablet').last);
    await h.tap(cardTitled('Bar'));
    await reach(h, ins('Bakery'));
    await h.tap(byKey('bb-save'));
    expect(review('Added'), findsOneWidget);
    expect(review('Waiter tablet 1'), findsOneWidget);
    expect(review('Changed'), findsOneWidget);
    expect(review('Bar'), findsOneWidget);
  });

  testWidgets('ADM-BSU-076 removing a section with items cooking blocks the '
      'save', (tester) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.heliopolis);
    await removeAndReview(h, 'Bar');
    expect(byKey('bb-review-busy'), findsOneWidget);
    expect(
      review(
        'Bar still has items cooking. Finish or move them on the kitchen screen first, or keep the section.',
      ),
      findsOneWidget,
    );
    expect(tester.widget<DashButton>(byKey('bb-review-save')).onPressed, isNull);
  });

  testWidgets('ADM-BSU-077/078 Save: the PUT, the spinner, then the toast, the '
      'draft adopted, versions and /kitchen refreshed, no second read', (
    tester,
  ) async {
    final b = PlanBackend();
    final h = await pumpBuilder(tester, branchId: SeedIds.zamalek, backend: b);
    final seen = watchInvalidations(h);
    await unlock(h);
    await h.tap(cardTitled('Counter 2'));
    final name = find.descendant(of: byKey('bb-name'), matching: find.byType(EditableText));
    await h.enterText(name, '  Drive-through  ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await h.settle();
    await h.tap(byKey('bb-save'));
    final gate = b.server.hold('PUT', BranchPlanRoutes.plan);
    await h.tap(byKey('bb-review-save'));
    expect(tester.widget<DashButton>(byKey('bb-review-save')).loading, isTrue);
    expect(tester.widget<DashButton>(byKey('bb-review-cancel')).onPressed, isNull);
    gate.release();
    await h.settle();
    final put = lastSave(h.server);
    expect(put['branch_id'], SeedIds.zamalek);
    expect(put['expected_version'], 0);
    final plan = (put['plan']! as Map).cast<String, Object?>();
    final names = [
      for (final d in (plan['devices']! as List).cast<Map<String, Object?>>())
        d['name'],
    ];
    expect(names, contains('Drive-through'));
    await h.expectToast('Branch plan saved');
    expect(byKey('bb-review-save'), findsNothing);
    expect(byKey('bb-unsaved'), findsNothing);
    expect(tester.widget<DashIconButton>(byKey('bb-undo')).onPressed, isNull);
    expect(seen, contains(equals(['/branch-plan/versions', '/kitchen'])));
    expect(h.server.callsTo(BranchPlanRoutes.plan, method: 'GET'), hasLength(1));
    // The slots now exist: codes can be issued.
    await h.tap(cardTitled('Drive-through'));
    expect(byKey('bb-get-code'), findsOneWidget);
    expect(tester.widget<DashButton>(byKey('bb-history')).onPressed, isNotNull);
  });

  testWidgets('ADM-BSU-080 any other failure: a toast, the dialog stays', (
    tester,
  ) async {
    final b = PlanBackend();
    final h = await pumpBuilder(tester, branchId: SeedIds.zamalek, backend: b);
    await removeAndReview(h, 'Counter 2');
    final boom = MockResponse.error(500, 'Database error: boom');
    b.server.fail('PUT', BranchPlanRoutes.plan, boom);
    await h.tap(byKey('bb-review-save'));
    await h.expectToast(refusalText(h, boom));
    expect(byKey('bb-review-save'), findsOneWidget);
    expect(byKey('bb-unsaved'), findsOneWidget);
  });

  testWidgets('ADM-BSU-081 PLAN_CHANGED: the dialog closes, a toast with '
      '"Load their version" that drops the draft and reads again', (
    tester,
  ) async {
    final b = PlanBackend();
    final h = await pumpBuilder(tester, branchId: SeedIds.heliopolis, backend: b);
    await removeAndReview(h, 'Kitchen printer');
    // Someone saved in between (no event reached this page).
    b.db['branches'].find(SeedIds.heliopolis)!['hardware_plan_version'] = 3;
    await h.tap(byKey('bb-review-save'));
    expect(byKey('bb-review-save'), findsNothing);
    expect(
      find.text(
        "Someone saved this branch's plan while you were editing. Reload to see their version.",
      ),
      findsOneWidget,
    );
    expect(cardTitled('Kitchen printer'), findsNothing, reason: 'draft kept');
    await h.tap(find.text('Load their version'));
    expect(h.server.callsTo(BranchPlanRoutes.plan, method: 'GET'), hasLength(2));
    expect(cardTitled('Kitchen printer'), findsOneWidget);
    expect(byKey('bb-unsaved'), findsNothing);
    await h.flushTimers();
  });

  testWidgets('ADM-BSU-082 SECTION_HAS_OPEN_TICKETS: the coded words, the '
      'dialog stays', (tester) async {
    final b = PlanBackend();
    final h = await pumpBuilder(tester, branchId: SeedIds.heliopolis, backend: b);
    await removeAndReview(h, 'Kitchen');
    // Cooking started after the plan was read.
    b.table(BranchPlanTables.ticketItems).insert({
      'branch_id': SeedIds.heliopolis,
      'station_id': BranchPlanSeed.stationId('heliopolis', 'kitchen'),
      'status': 'firing',
      'closed_at': null,
      'bumped_at': null,
      'voided_at': null,
    }, timestamps: false);
    await h.tap(byKey('bb-review-save'));
    await h.expectToast(
      'Items are still cooking in a section this plan removes. Finish or move them before removing it.',
    );
    expect(byKey('bb-review-save'), findsOneWidget);
  });

  testWidgets('ADM-BSU-083 a 400: the server\'s sentence in English, '
      '"Please check" in Arabic', (tester) async {
    for (final lang in ['en', 'ar']) {
      final b = PlanBackend();
      final h = await pumpBuilder(
        tester,
        branchId: SeedIds.heliopolis,
        backend: b,
        locale: lang,
      );
      await unlock(h);
      await h.tap(cardTitled('Counter 1'));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await h.settle();
      await h.tap(byKey('bb-save'));
      // The category was deleted after the plan was read.
      b.db['categories'].removeWhere((c) => c['id'] == MockSeed.categoryId('hot'));
      await h.tap(byKey('bb-review-save'));
      await h.expectToast(
        lang == 'en'
            ? BranchPlanRefusals.unknownCategory
            : h.t('errors.validation'),
      );
      expect(byKey('bb-review-save'), findsOneWidget);
    }
  });

  testWidgets('ADM-BSU-084 (divergence) a slot naming a retired device is let '
      'go as read, so the save goes through', (tester) async {
    final b = PlanBackend();
    b.db[AdminTables.devices].find(AdminSeed.deviceId('heliopolis', 'T1'))!['retired_at'] =
        '2026-10-01T08:00:00Z';
    final h = await pumpBuilder(tester, branchId: SeedIds.heliopolis, backend: b);
    expect(pieceOf(tester, cardTitled('Counter 1')).presence!.label, 'Not set up');
    expect(byKey('bb-unsaved'), findsNothing);
    await removeAndReview(h, 'Kitchen printer');
    await h.tap(byKey('bb-review-save'));
    await h.expectToast('Branch plan saved');
    final devices = ((lastSave(h.server)['plan']! as Map)['devices']! as List)
        .cast<Map<String, Object?>>();
    expect(devices.first['device_id'], isNull);
  });

  testWidgets('ADM-BSU-085 the leave guard on "Item routing": Cancel stays, '
      'Leave goes', (tester) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.zamalek);
    await unlock(h);
    await h.tap(cardTitled('Kitchen'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await h.settle();
    await reach(h, byKey('bb-item-routing'));
    expect(find.text('Leave without saving?'), findsOneWidget);
    expect(find.text("Your changes to this branch's plan will be lost."), findsOneWidget);
    await h.tap(top('Cancel'));
    expect(h.location.path, '/branch-setup');
    expect(byKey('bb-unsaved'), findsOneWidget);
    await reach(h, byKey('bb-item-routing'));
    await h.tap(top('Leave'));
    expect(h.location.path, '/settings/kitchen-routing');
  });

  testWidgets('ADM-BSU-010/011/085 a branch switch: a clean editor starts '
      'fresh; a dirty one asks, and Cancel puts the scope back', (
    tester,
  ) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.heliopolis);
    await unlock(h);
    await h.tap(cardTitled('Counter 1'));
    final scope = h.container.read(scopeProvider.notifier);
    // Clean: straight over, Locked again, nothing selected.
    await scope.setBranch(SeedIds.maadi);
    await h.settle();
    expect(find.text('Leave without saving?'), findsNothing);
    expect(canvasOf(tester).editable, isFalse);
    expect(canvasOf(tester).selection, isEmpty);
    expect(h.server.callsTo(BranchPlanRoutes.plan).last.query['branch_id'], [SeedIds.maadi]);
    // Dirty: asked.
    await unlock(h);
    await h.tap(cardTitled('Counter 1'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await h.settle();
    await scope.setBranch(SeedIds.zamalek);
    await h.settle();
    expect(find.text('Leave without saving?'), findsOneWidget);
    await h.tap(top('Cancel'));
    expect(h.container.read(currentScopeProvider).branchId, SeedIds.maadi);
    expect(byKey('bb-unsaved'), findsOneWidget);
    await scope.setBranch(SeedIds.zamalek);
    await h.settle();
    await h.tap(top('Leave'));
    expect(h.container.read(currentScopeProvider).branchId, SeedIds.zamalek);
    expect(byKey('bb-unsaved'), findsNothing);
    expect(cardTitled('Terrace tablet'), findsOneWidget);
  });
}
