// Intent warming on Devices: pointing at a view tab, a window option or the
// legacy switch warms the read that press makes, so the press asks nothing
// more.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Finder _tab(String label) => find.descendant(
  of: find.byKey(const ValueKey('devices-view')),
  matching: find.text(label),
);

List<MockCall> _clients(DashHarness h) =>
    h.server.callsTo(DevicesRoutes.clients);

void main() {
  testWidgets('the Client versions tab warms its read; pressing it asks '
      'nothing more', (tester) async {
    final h = await pumpDevices(tester, query: atBranch(SeedIds.zamalek));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    expect(_clients(h), isEmpty);

    await mouse.moveTo(tester.getCenter(_tab('Client versions')));
    await h.settle();
    expect(_clients(h), hasLength(1), reason: 'warmed');
    expect(_clients(h).single.query, {
      'branch_id': [SeedIds.zamalek],
      'legacy_only': ['true'],
      'days': ['14'],
    });
    await h.tap(_tab('Client versions'));
    expect(find.text('Clients seen'), findsOneWidget);
    expect(_clients(h), hasLength(1), reason: 'opened from the cache');
  });

  testWidgets('a window option, the legacy switch and the Devices tab warm '
      'their reads; pressing them asks nothing more', (tester) async {
    final h = await pumpDevices(
      tester,
      query: '${atBranch(SeedIds.zamalek)}&view=clients',
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    expect(_clients(h), hasLength(1));

    await h.tap(find.byKey(const ValueKey('clients-window')));
    final thirty = find.text('Last 30 days').hitTestable().last;
    await mouse.moveTo(tester.getCenter(thirty));
    await h.settle();
    expect(_clients(h), hasLength(2), reason: 'the 30-day window warmed');
    expect(_clients(h).last.query['days'], ['30']);
    await h.tap(thirty);
    expect(h.location.queryParameters['days'], '30');
    expect(_clients(h), hasLength(2), reason: 'from the cache');

    final legacy = find.byKey(const ValueKey('clients-legacy-only'));
    await mouse.moveTo(tester.getCenter(legacy));
    await h.settle();
    expect(_clients(h), hasLength(3), reason: 'every client warmed');
    expect(_clients(h).last.query['legacy_only'], ['false']);
    expect(_clients(h).last.query['days'], ['30']);
    await h.tap(legacy);
    expect(h.location.queryParameters['all'], 'true');
    expect(_clients(h), hasLength(3), reason: 'from the cache');

    expect(h.server.callsTo(DevicesRoutes.devices), isEmpty);
    await mouse.moveTo(tester.getCenter(_tab('Devices')));
    await h.settle();
    expect(h.server.callsTo(DevicesRoutes.devices), hasLength(1));
    expect(h.server.callsTo(DevicesRoutes.codes, method: 'GET'), hasLength(1));
    await h.tap(_tab('Devices'));
    expect(deviceRows(), findsNWidgets(5));
    expect(h.server.callsTo(DevicesRoutes.devices), hasLength(1));
    expect(h.server.callsTo(DevicesRoutes.codes, method: 'GET'), hasLength(1));
  });

  testWidgets('without branches.edit the Devices tab warms no codes', (
    tester,
  ) async {
    final h = await pumpDevices(
      tester,
      query: '${atBranch(SeedIds.zamalek)}&view=clients',
      persona: Persona.manager,
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(_tab('Devices')));
    await h.settle();
    expect(h.server.callsTo(DevicesRoutes.devices), hasLength(1));
    expect(h.server.callsTo(DevicesRoutes.codes), isEmpty);
  });
}
