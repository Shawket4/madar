// Intent warming on the Schedule: resting the mouse on a control warms the
// read its press makes (same provider, same key), so the press asks the
// server nothing more.
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'schedule_support.dart';

void main() {
  testWidgets('the next-week arrow, the coverage toggle and a preferences '
      'button warm their reads; pressing them asks nothing more', (
    tester,
  ) async {
    final h = await pumpSchedule(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    Future<void> rest(Finder f) async {
      await tester.ensureVisible(f);
      await h.settle();
      await mouse.moveTo(tester.getCenter(f));
      await h.settle();
    }

    // The next week: its roster and suggestions; the fairness month stays.
    expect(weekCalls(h, wd(7)), isEmpty);
    await rest(pressable('Next week'));
    expect(weekCalls(h, wd(7)), hasLength(1));
    final sg = [
      for (final c in calls(h, suggestionsT))
        if (c.query['week_start']!.single == wd(7)) c,
    ];
    expect(sg, hasLength(1));
    await h.tap(pressable('Next week'));
    expect(weekCalls(h, wd(7)), hasLength(1), reason: 'from the cache');
    expect(
      calls(h, suggestionsT).where((c) => c.query['week_start']!.single == wd(7)),
      hasLength(1),
    );

    // The coverage card's read.
    final toggle = inPage(find.widgetWithText(DashButton, 'Coverage needs'));
    await rest(toggle);
    expect(calls(h, coverageT), hasLength(1));
    await h.tap(toggle);
    expect(calls(h, coverageT), hasLength(1), reason: 'from the cache');

    // The preferences dialog's change log.
    final prefs = inGrid(pressable("Hassan Ibrahim's preferences"));
    await rest(prefs);
    expect(calls(h, prefsLogT), hasLength(1));
    await h.tap(prefs);
    expect(surfaceText("Hassan Ibrahim's preferences"), findsOneWidget);
    expect(calls(h, prefsLogT), hasLength(1), reason: 'from the cache');
  });

  testWidgets('a sweep across the grid warms nothing', (tester) async {
    final h = await pumpSchedule(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    final before = calls(h, prefsLogT).length;
    final from = tester.getCenter(inGrid(pressable("Adham Reda's preferences")));
    for (var i = 0; i < 6; i++) {
      await mouse.moveTo(from + Offset(0, i * 70.0));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await mouse.moveTo(Offset.zero);
    await h.settle();
    expect(calls(h, prefsLogT), hasLength(before));
  });
}
