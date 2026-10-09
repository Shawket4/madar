// Intent on the Rules page: the only press that makes a read is picking a
// scope, and resting on its option warms that scope's rules. Every other
// control works on what the page holds (or writes).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_team/src/rules/rules_cards.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'rules_support.dart';

void main() {
  testWidgets('resting on a scope option warms its rules; picking it asks '
      'nothing more', (tester) async {
    final h = await pumpRules(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await h.tap(find.byKey(RulesKeys.scope));
    final option = find.text('Maadi').hitTestable().last;
    final before = settingsGets(h);
    await mouse.moveTo(tester.getCenter(option));
    await tester.pump(kDashIntentDwell + const Duration(milliseconds: 20));
    await h.settle();
    expect(settingsGets(h), before + 1);
    expect(h.server.callsTo(settingsT).last.query, {
      'branch_id': [SeedIds.maadi],
    });
    await h.tap(option);
    expect(settingsGets(h), before + 1);
    expect(pageText("This branch's own rules"), findsOneWidget);
  });

  testWidgets('Add a rung and a rung\'s kind ask nothing', (tester) async {
    final h = await pumpRules(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    final calls = h.server.calls.length;
    await tapKey(h, RulesKeys.tierRemove(2));
    await mouse.moveTo(tester.getCenter(find.byKey(RulesKeys.addTier)));
    await tester.pump(kDashIntentDwell + const Duration(milliseconds: 20));
    await tapKey(h, RulesKeys.addTier);
    await pickIn(h, RulesKeys.tierKind(0), 'Fixed amount');
    expect(h.server.calls.length, calls);
  });
}
