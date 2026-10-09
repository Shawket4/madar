// Intent warming on Requests (owner rule): a status segment, a kind option,
// New request and a mission's Approve warm exactly the read their press
// makes, so the press asks nothing more.
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_team/src/approvals/approvals_dialogs.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'requests_support.dart';

Future<TestGesture> _mouse(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  return mouse;
}

Finder _option(String label) => find
    .descendant(
      of: find.byWidgetPredicate(
        (w) => w.runtimeType.toString().startsWith('DashOptionList'),
      ),
      matching: find.text(label),
    )
    .last;

int _lists(DashHarness h, String param, String value) => [
  for (final c in h.server.callsTo(listT, method: 'GET'))
    if (c.query[param]?.single == value) c,
].length;

void main() {
  testWidgets('intent: a status segment and a kind option warm their list; '
      'pressing asks nothing more', (tester) async {
    final h = await pumpRequests(tester);
    final mouse = await _mouse(tester);
    expect(_lists(h, 'status', 'approved'), 0);
    await mouse.moveTo(tester.getCenter(pageText('Approved')));
    await h.settle();
    expect(_lists(h, 'status', 'approved'), 1);
    await h.tap(pageText('Approved'));
    expect(_lists(h, 'status', 'approved'), 1);

    await h.tap(pageText('All kinds'));
    final leave = find
        .descendant(
          of: find.byWidgetPredicate(
            (w) => w.runtimeType.toString().startsWith('DashOptionList'),
          ),
          matching: find.text('Leave'),
        )
        .last;
    await mouse.moveTo(tester.getCenter(leave));
    await h.settle();
    expect(_lists(h, 'kind', 'leave'), 1);
    await h.tap(leave);
    expect(_lists(h, 'kind', 'leave'), 1);
  });

  testWidgets('intent: "Show what\'s pending" warms the pending list; '
      'pressing asks nothing more', (tester) async {
    final h = await pumpRequests(tester);
    await h.tap(pageText('Rejected'));
    await h.tap(pageText('All kinds'));
    await h.tap(_option('Correction'));
    final show = pageText(h.t('dawamOps.showPending'));
    expect(show, findsOneWidget);
    final mouse = await _mouse(tester);
    await mouse.moveTo(tester.getCenter(show));
    await h.settle();
    final warmed = _lists(h, 'status', 'pending');
    await h.tap(show);
    expect(_lists(h, 'status', 'pending'), warmed);
    expect(pageText('All kinds'), findsOneWidget);
  });

  testWidgets('intent: a pay kind\'s Approve on another filter asks nothing; '
      'the dialog reads the page\'s own list', (tester) async {
    final h = await pumpRequests(tester);
    await h.tap(pageText('All kinds'));
    await h.tap(_option('Leave'));
    final before = gets(h);
    final mouse = await _mouse(tester);
    await mouse.moveTo(tester.getCenter(approveIn("My sister's wedding")));
    await h.settle();
    expect(gets(h), before, reason: 'no GET status=pending');
    await h.tap(approveIn("My sister's wedding"));
    expect(find.byType(ApproveWithPayDialog), findsOneWidget);
    expect(gets(h), before);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
  });

  testWidgets('intent: New request warms the active people; the dialog asks '
      'nothing more', (tester) async {
    final h = await pumpRequests(tester);
    final mouse = await _mouse(tester);
    int active() => h.server
        .callsTo(employeesT, method: 'GET')
        .where((c) => c.query['employment_status']?.single == 'active')
        .length;
    await mouse.moveTo(tester.getCenter(pageText('New request')));
    await h.settle();
    final warmed = active();
    expect(warmed, 1);
    await h.tap(pageText('New request'));
    expect(active(), warmed);
  });

  testWidgets('intent: pointing at a mission\'s Approve warms its worked '
      'days; pressing asks nothing more', (tester) async {
    final h = await pumpRequests(tester);
    final mission = requestOf(tester, 'Choosing next month');
    int days() => h.server
        .callsTo(attendanceT, method: 'GET')
        .where((c) => c.query['employee_id']?.single == mission.employeeId)
        .length;
    expect(days(), 0);
    final mouse = await _mouse(tester);
    await mouse.moveTo(tester.getCenter(approveIn('Choosing next month')));
    await h.settle();
    expect(days(), 1);
    await h.tap(approveIn('Choosing next month'));
    expect(days(), 1);
    if (confirmCard().evaluate().isNotEmpty) {
      await h.tap(inConfirm(find.text('Approve')));
    }
    await h.flushTimers();
  });
}
