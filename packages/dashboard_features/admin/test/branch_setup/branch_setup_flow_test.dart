// Branch setup: the nav leaf and module gate, refusals, realtime and the
// phone layout (ADM-BSU-001, 002, 086, 087, 088).
import 'package:dashboard_admin/src/branch_setup/branch_setup_page.dart';
import 'package:dashboard_admin/src/branch_setup/builder_canvas.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/shell.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

BuilderCanvas canvasOf(WidgetTester t) =>
    t.widget<BuilderCanvas>(find.byType(BuilderCanvas));

Finder byKey(String k) => find.byKey(ValueKey(k));

Finder navRow(DashHarness h) => find.descendant(
  of: find.byType(DashSidebar),
  matching: find.text('Branch setup'),
);

void main() {
  testWidgets('ADM-BSU-001 the Setup group lists "Branch setup" for '
      'kitchen.stations.edit; not for the limited persona', (tester) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.heliopolis);
    expect(navRow(h), findsOneWidget);
    final l = await pumpBuilder(
      tester,
      branchId: SeedIds.maadi,
      persona: Persona.limited,
    );
    expect(navRow(l), findsNothing);
  });

  testWidgets('ADM-BSU-002 a Dawam-only org never reaches the page', (
    tester,
  ) async {
    final h = await pumpBuilder(tester, persona: Persona.dawamOnly);
    expect(find.byType(BranchSetupPage), findsNothing);
    expect(h.server.callsTo(BranchPlanRoutes.plan), isEmpty);
  });

  testWidgets('ADM-BSU-086 without kitchen.stations.read (a deep link): the '
      'error panel says so, with Retry', (tester) async {
    final h = await pumpBuilder(
      tester,
      branchId: SeedIds.maadi,
      persona: Persona.limited,
    );
    expect(byKey('bb-error'), findsOneWidget);
    expect(
      pageText(refusalText(h, MockResponse.denied('kitchen.stations.read'))),
      findsOneWidget,
    );
    expect(pageText('Retry'), findsOneWidget);
  });

  testWidgets('ADM-BSU-086 a save the server refuses for the right: the '
      'toast, the dialog stays', (tester) async {
    final b = PlanBackend();
    final h = await pumpBuilder(tester, branchId: SeedIds.heliopolis, backend: b);
    await h.tap(byKey('bb-lock'));
    await h.tap(cardTitled('Kitchen screen'));
    await tester.ensureVisible(byKey('bb-remove'));
    await h.settle();
    await h.tap(byKey('bb-remove'));
    await h.tap(byKey('bb-save'));
    final denied = MockResponse.denied('kitchen.stations.edit');
    b.server.fail('PUT', BranchPlanRoutes.plan, denied);
    await h.tap(byKey('bb-review-save'));
    await h.expectToast(refusalText(h, denied));
    expect(byKey('bb-review-save'), findsOneWidget);
  });

  testWidgets('ADM-BSU-087 branch.plan_changed reads the plan (and the open '
      'History) again; kitchen.* events leave the plan alone', (tester) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.heliopolis);
    int reads() => h.server.callsTo(BranchPlanRoutes.plan, method: 'GET').length;
    expect(reads(), 1);
    h.realtime.current!.emit('kitchen.ticket_bumped', data: '{}');
    await h.settle();
    expect(reads(), 1);
    await h.tap(byKey('bb-history'));
    final versions = h.server.callsTo(BranchPlanRoutes.versions).length;
    h.realtime.current!.emit('branch.plan_changed', data: '{}');
    await h.settle();
    expect(reads(), 2);
    expect(h.server.callsTo(BranchPlanRoutes.versions).length, versions + 1);
    expect(h.realtime.current!.topics, contains('kitchen'));
  });

  testWidgets('ADM-BSU-087 this person\'s own save comes back and changes '
      'nothing', (tester) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.heliopolis);
    await h.tap(byKey('bb-lock'));
    await h.tap(cardTitled('Kitchen screen'));
    await tester.ensureVisible(byKey('bb-remove'));
    await h.settle();
    await h.tap(byKey('bb-remove'));
    await h.tap(byKey('bb-save'));
    await h.tap(byKey('bb-review-save'));
    await h.expectToast('Branch plan saved');
    h.realtime.current!.emit('branch.plan_changed', data: '{"version":3}');
    await h.settle();
    expect(byKey('bb-overtaken'), findsNothing);
    expect(byKey('bb-unsaved'), findsNothing);
    expect(cardTitled('Kitchen screen'), findsNothing);
  });

  testWidgets('ADM-BSU-088 a phone: History is an icon, the inspector under '
      'the canvas, the canvas at least 45 % of the screen; one finger on a '
      'card drags it, two pinch', (tester) async {
    final h = await pumpBuilder(
      tester,
      branchId: SeedIds.heliopolis,
      size: DashSize.phone,
    );
    expect(tester.widget(byKey('bb-history')), isA<DashIconButton>());
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final canvas = tester.getRect(find.byType(BuilderCanvas));
    expect(canvas.height, greaterThanOrEqualTo(screen.height * 0.45 - 1));
    await tester.ensureVisible(byKey('bb-inspector'));
    await h.settle();
    expect(
      tester.getRect(byKey('bb-inspector')).top,
      greaterThanOrEqualTo(tester.getRect(find.byType(BuilderCanvas)).bottom - 1),
    );
    await tester.ensureVisible(find.byType(BuilderCanvas));
    await h.settle();
    await h.tap(byKey('bb-lock'));
    final v = canvasOf(tester).viewport;
    final before = canvasOf(tester).plan.device(BranchPlanSeed.counter)!.x;
    await tester.dragFrom(
      tester.getCenter(cardTitled('Counter 1')),
      Offset(30 * v.zoom, 0),
    );
    await h.settle();
    expect(
      canvasOf(tester).plan.device(BranchPlanSeed.counter)!.x,
      before + 30,
    );
    // Two fingers spread: zoom in.
    final z = v.zoom;
    final c = tester.getCenter(find.byType(BuilderCanvas));
    final a = await tester.startGesture(c - const Offset(20, 0));
    final b = await tester.startGesture(c + const Offset(20, 0));
    await a.moveTo(c - const Offset(60, 0));
    await b.moveTo(c + const Offset(60, 0));
    await tester.pump();
    await a.up();
    await b.up();
    await h.settle();
    expect(v.zoom, greaterThan(z));
  });

  testWidgets('ADM-BSU-088 the setup picker is one column below 640 px', (
    tester,
  ) async {
    final b = PlanBackend();
    b.db['branches'].find(SeedIds.maadi)!['printer_ip'] = null;
    b.db['devices'].removeWhere((d) => d['branch_id'] == SeedIds.maadi);
    await pumpBuilder(
      tester,
      branchId: SeedIds.maadi,
      size: DashSize.phone,
      backend: b,
    );
    final a = tester.getRect(byKey('bb-setup-till'));
    final c = tester.getRect(byKey('bb-setup-tillPrinter'));
    expect(c.top, greaterThan(a.bottom - 1));
    expect((c.left - a.left).abs(), lessThan(1));
  });

  testWidgets('intent: a mouse rests on History: the versions are warmed; '
      'opening it reads nothing more', (tester) async {
    final h = await pumpBuilder(tester, branchId: SeedIds.heliopolis);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(byKey('bb-history')));
    await h.settle();
    expect(h.server.callsTo(BranchPlanRoutes.versions), hasLength(1));
    await h.tap(byKey('bb-history'));
    expect(h.server.callsTo(BranchPlanRoutes.versions), hasLength(1));
    expect(byKey('bb-version-2'), findsOneWidget);
  });
}
