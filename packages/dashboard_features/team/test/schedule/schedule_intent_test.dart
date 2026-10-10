// Intent warming on the Schedule: resting the mouse on a control warms the
// read its press makes (same provider, same key), so the press asks the
// server nothing more.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'schedule_support.dart';

/// A mouse resting on a control, as `rest(finder)`.
Future<Future<void> Function(Finder)> mouseOn(
  WidgetTester tester,
  DashHarness h,
) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  return (f) async {
    await tester.ensureVisible(f);
    await h.settle();
    // Away first: resting again on the same control is a fresh intent.
    await mouse.moveTo(Offset.zero);
    await mouse.moveTo(tester.getCenter(f));
    await h.settle();
  };
}

/// No read asked since call [from] was asked twice.
void expectNoRepeat(DashHarness h, int from) {
  final seen = <String>{};
  for (final c in h.server.calls.skip(from)) {
    if (c.method != 'GET') continue;
    final key = '${c.path} ${c.query}';
    expect(seen.add(key), isTrue, reason: 'asked twice: $key');
  }
}

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
      calls(
        h,
        suggestionsT,
      ).where((c) => c.query['week_start']!.single == wd(7)),
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
    final from = tester.getCenter(
      inGrid(pressable("Adham Reda's preferences")),
    );
    for (var i = 0; i < 6; i++) {
      await mouse.moveTo(from + Offset(0, i * 70.0));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await mouse.moveTo(Offset.zero);
    await h.settle();
    expect(calls(h, prefsLogT), hasLength(before));
  });

  testWidgets('Previous week and "Back to this week" warm their week; '
      'pressing them asks nothing more', (tester) async {
    final h = await pumpSchedule(tester);
    final rest = await mouseOn(tester, h);
    expect(weekCalls(h, wd(-7)), isEmpty);
    await rest(pressable('Previous week'));
    expect(weekCalls(h, wd(-7)), hasLength(1));
    await h.tap(pressable('Previous week'));
    expect(weekCalls(h, wd(-7)), hasLength(1), reason: 'from the cache');

    // This week's read, let go past the gc time, is swept by the next
    // read built; resting on "Back to this week" asks for it again.
    h.server.clock.advance(const Duration(minutes: 6));
    await rest(pressable('Previous week'));
    final back = inPage(
      find.widgetWithText(DashButton, h.t('dawamOps.backToThisWeek')),
    );
    final before = weekCalls(h, week).length;
    await rest(back);
    expect(weekCalls(h, week), hasLength(before + 1));
    await h.tap(back);
    expect(weekCalls(h, week), hasLength(before + 1), reason: 'from the cache');
  });

  testWidgets('TEAM-SCH-004 a branch option warms its week, the 45 days, its '
      'suggestions and, with the coverage card open, its coverage', (
    tester,
  ) async {
    final h = await pumpSchedule(tester, allBranches: true);
    final rest = await mouseOn(tester, h);
    await h.tap(inPage(find.widgetWithText(DashButton, 'Coverage needs')));
    List<MockCall> maadi(String t) => [
      for (final c in calls(h, t))
        if (c.query['branch_id']?.single == SeedIds.maadi) c,
    ];
    expect(maadi(rosterT), isEmpty);
    await h.tap(inPage(find.byKey(const Key('schedule-branch'))));
    final option = find.text('Maadi').hitTestable().last;
    await rest(option);
    expect(maadi(rosterT), hasLength(2), reason: 'the week and the 45 days');
    expect(maadi(suggestionsT), hasLength(1));
    expect(maadi(coverageT), hasLength(1));
    await h.tap(option);
    expect(maadi(rosterT), hasLength(2), reason: 'from the cache');
    expect(maadi(suggestionsT), hasLength(1));
    expect(maadi(coverageT), hasLength(1));
  });

  testWidgets('TEAM-SCH-011 the "Edit pattern" link: rest, press, Work '
      'shifts opens without asking anything twice', (tester) async {
    final h = await pumpSchedule(tester);
    final rest = await mouseOn(tester, h);
    final from = h.server.calls.length;
    await rest(pressable(h.t('dawamOps.editPattern')));
    await h.tap(pressable(h.t('dawamOps.editPattern')));
    expect(h.location.path, '/staff/shifts');
    expectNoRepeat(h, from);
  });

  testWidgets('TEAM-SCH-012 the no-blocks banner: rest, press, Work shifts '
      'opens without asking anything twice', (tester) async {
    final h = await pumpSchedule(
      tester,
      edit: (db) =>
          db['work_shifts'].removeWhere((w) => w['org_id'] == SeedIds.sabahOrg),
    );
    final rest = await mouseOn(tester, h);
    final open = inPage(find.widgetWithText(DashButton, 'Open Work shifts'));
    final from = h.server.calls.length;
    await rest(open);
    await h.tap(open);
    expect(h.location.path, '/staff/shifts');
    expectNoRepeat(h, from);
  });

  testWidgets('TEAM-SCH-015 the empty state\'s "Open Employees": rest, press, '
      'Employees opens without asking anything twice', (tester) async {
    final h = await pumpSchedule(
      tester,
      edit: (db) {
        for (final e in db['employees'].rows) {
          if ((e['branch_ids'] as List?)?.contains(SeedIds.zamalek) ?? false) {
            e['employment_status'] = 'terminated';
          }
        }
      },
    );
    final rest = await mouseOn(tester, h);
    final open = inPage(find.widgetWithText(DashButton, 'Open Employees'));
    final from = h.server.calls.length;
    await rest(open);
    await h.tap(open);
    expect(h.location.path, '/staff/employees');
    expectNoRepeat(h, from);
  });
}
