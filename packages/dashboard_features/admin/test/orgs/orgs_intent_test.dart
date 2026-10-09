// Organizations: the sidebar prefetch (the web's `prefetchRoute('/orgs')`)
// and intent warming (a row warms the editor's reads, New the wizard's), so
// each press asks the server nothing more.
import 'package:dashboard_admin/src/area_seed.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/shell.dart';
import 'package:dashboard_kit/dashboard_kit.dart' show DashExportButton;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  testWidgets('ADM-ORG-003 pointing at Organizations warms the list; opening '
      'it refetches nothing', (tester) async {
    final h = await pumpOrgs(tester, path: '/branches');
    List<MockCall> lists() => h.server.callsTo('/orgs', method: 'GET');
    final before = lists().length;
    final row = find.descendant(
      of: find.byType(DashSidebar),
      matching: find.text(h.t('nav.orgs')),
    );
    await tester.scrollUntilVisible(
      row,
      200,
      scrollable: find
          .descendant(
            of: find.byType(DashSidebar),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await h.settle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(row));
    await h.settle();
    // The shell's org picker already holds the one shared /orgs entry, so a
    // fresh entry needs no request on hover; a cold one asks once.
    final warmed = lists().length;
    expect(
      warmed,
      inInclusiveRange(before, before + 1),
      reason: 'warmed on hover',
    );

    await h.tap(row);
    expect(h.location.path, '/orgs');
    expect(lists().length, warmed, reason: 'served from the cache');
    expect(find.text('Layali Bistro'), findsOneWidget);
  });

  testWidgets('ADM-ORG-018 / 023 a row warms the editor\'s timezones, New the '
      'wizard\'s templates; the presses ask nothing more', (tester) async {
    final h = await pumpOrgs(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    List<MockCall> zones() => h.server.callsTo('/timezones', method: 'GET');
    List<MockCall> templates() =>
        h.server.callsTo('/orgs/templates', method: 'GET');
    expect(zones(), isEmpty);
    expect(templates(), isEmpty);

    await mouse.moveTo(tester.getCenter(find.text('Qahwa Corner')));
    await h.settle();
    expect(zones(), hasLength(1), reason: 'the editor read is warmed');
    await h.tapText('Qahwa Corner');
    expect(h.location.queryParameters['edit'], AdminSeed.qahwaOrg);
    expect(find.text('Edit Organization'), findsOneWidget);
    expect(zones(), hasLength(1), reason: 'the editor opened from the cache');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();

    final newButton = find.byKey(const ValueKey('orgs-new'));
    await mouse.moveTo(tester.getCenter(newButton));
    await h.settle();
    expect(templates(), hasLength(1), reason: 'the wizard read is warmed');
    await h.tap(newButton);
    expect(find.text('New Organization'), findsOneWidget);
    expect(templates(), hasLength(1), reason: 'the wizard opened from cache');
    expect(zones(), hasLength(1));
  });

  testWidgets('ADM-ORG-019 / 022 the Edit pencil warms the editor\'s '
      'timezones, Export the brand it reads; the presses ask nothing more', (
    tester,
  ) async {
    final h = await pumpOrgs(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    List<MockCall> zones() => h.server.callsTo('/timezones', method: 'GET');
    List<MockCall> brand() =>
        h.server.callsTo('/public/orgs/brand', method: 'GET');

    final pencil = find.bySemanticsLabel('Edit').first;
    await mouse.moveTo(tester.getCenter(pencil));
    await h.settle();
    expect(zones(), hasLength(1), reason: 'the editor read is warmed');
    await h.tap(pencil);
    expect(find.text('Edit Organization'), findsOneWidget);
    expect(zones(), hasLength(1), reason: 'the editor opened from the cache');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();

    final export = find.byType(DashExportButton);
    await mouse.moveTo(tester.getCenter(export));
    await h.settle();
    expect(
      h.container.read(publicBrandProvider),
      isA<AsyncData<Object?>>(),
      reason: 'the export read is warmed',
    );
    final warmed = brand().length;
    await h.tap(export);
    await h.expectToast(h.t('excel.done', count: 4));
    expect(brand(), hasLength(warmed), reason: 'the export read the cache');
  });
}
