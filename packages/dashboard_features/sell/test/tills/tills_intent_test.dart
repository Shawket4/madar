// Intent warming on Tills: resting the pointer on a control warms the read
// its press makes, so the press asks the server nothing more.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tills_support.dart';

/// Calls to [route] for till [id].
int _for(DashHarness h, String route, String id) =>
    h.server.callsTo(route).where((c) => c.path.contains(id)).length;

/// List reads whose [param] is [value].
int _lists(DashHarness h, String param, String value) => h.server
    .callsTo(tillsList)
    .where((c) => c.query[param]?.single == value)
    .length;

Future<TestGesture> _mouse(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  return mouse;
}

Future<void> _rest(DashHarness h, TestGesture mouse, Finder f) async {
  await h.tester.ensureVisible(f);
  await h.settle();
  await mouse.moveTo(h.tester.getCenter(f));
  await h.settle();
}

void main() {
  testWidgets('a table row warms its whole report; opening it asks nothing '
      'more', (tester) async {
    final h = await pumpTills(tester);
    final mouse = await _mouse(tester);
    final id = TillIds.seeded('heliopolis', 1, 'evening');
    final row = find.byKey(ValueKey('till-badges-$id'));
    final reads = [tillReport, tillSummary, tillDeductions, tillSpotViews];
    expect([for (final r in reads) _for(h, r, id)], [0, 0, 0, 0]);

    await _rest(h, mouse, row);
    expect([for (final r in reads) _for(h, r, id)], [1, 1, 1, 1]);
    await h.tap(row);
    expect(h.location.queryParameters['report'], id);
    expect([for (final r in reads) _for(h, r, id)], [1, 1, 1, 1]);
  });

  testWidgets('an "Open now" row and "See the other till" warm their '
      'report', (tester) async {
    final h = await pumpTills(tester);
    final mouse = await _mouse(tester);
    final open = find.byKey(ValueKey('open-now-${TillIds.helioMorning}'));
    await _rest(h, mouse, open);
    expect(_for(h, tillReport, TillIds.helioMorning), 1);
    await h.tap(open);
    expect(_for(h, tillReport, TillIds.helioMorning), 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();

    // The table's link on the second till opens the first one's report.
    // A fresh tree: the second app must not reuse the first one's scope.
    await tester.pumpWidget(const SizedBox());
    final h2 = await pumpTills(tester);
    final link = find.descendant(
      of: find.byKey(ValueKey('till-badges-${TillIds.helioSecond}')),
      matching: find.text('See the other till'),
    );
    await _rest(h2, mouse, link);
    expect(_for(h2, tillReport, TillIds.helioMorning), 1);
    await h2.tap(link);
    expect(h2.location.queryParameters['report'], TillIds.helioMorning);
    expect(_for(h2, tillReport, TillIds.helioMorning), 1);
  });

  testWidgets('menu items warm the report and the close preview', (
    tester,
  ) async {
    final s = tillsServer();
    // The owner's own open till: only then are Close till and Cash movement
    // offered.
    s.db['tills'].get(TillIds.helioMorning)
      ..['teller_id'] = SeedIds.owner
      ..['teller_name'] = 'Nour El-Sayed';
    final h = await pumpTills(tester, server: s.server, db: s.db);
    final mouse = await _mouse(tester);
    final id = TillIds.helioMorning;

    await openRowMenu(h, id);
    expect(_for(h, tillClosePreview, id), 0);
    await _rest(h, mouse, find.text('Close till').last);
    expect(_for(h, tillClosePreview, id), 1);
    await pickMenu(h, 'Close till');
    expect(find.byKey(const ValueKey('close-till-submit')), findsOneWidget);
    expect(_for(h, tillClosePreview, id), 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();

    await openRowMenu(h, id);
    await _rest(h, mouse, find.text('View report').last);
    expect(_for(h, tillReport, id), 1);
    await pickMenu(h, 'View report');
    expect(h.location.queryParameters['report'], id);
    expect(_for(h, tillReport, id), 1);
  });

  testWidgets('a filter option and a filter toggle warm the list under '
      'them', (tester) async {
    final h = await pumpTills(tester);
    final mouse = await _mouse(tester);

    await h.tap(inKey('filter-status', find.byType(DashSelectTrigger)));
    final option = find.descendant(
      of: find.byWidgetPredicate((w) => w is DashOptionList),
      matching: find.text('Closed'),
    );
    expect(_lists(h, 'status', 'closed'), 0);
    await _rest(h, mouse, option.last);
    expect(_lists(h, 'status', 'closed'), 1);
    await h.tap(option.last);
    expect(h.location.queryParameters['status'], 'closed');
    expect(_lists(h, 'status', 'closed'), 1);

    final flagged = find.byKey(const ValueKey('filter-flagged'));
    expect(_lists(h, 'flagged', 'true'), 0);
    await _rest(h, mouse, flagged);
    expect(_lists(h, 'flagged', 'true'), 1);
    await h.tap(flagged);
    expect(h.location.queryParameters['flagged'], 'true');
    expect(_lists(h, 'flagged', 'true'), 1);
  });
}
