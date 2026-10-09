// Intent warming on Attendance (owner rule): Add record warms the dialog's
// reads, a person or status option the rows and cards under it, so each
// press asks nothing more. Plus the automatic retry rule (TEAM-ALL-023):
// an attempt Riverpod will retry is still the skeleton, never the error.
import 'package:dashboard_api/dashboard_api.dart' show AttendanceRecord;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart'
    show DashAsyncState, orgIdProvider, transportProvider, webRetry;
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart' show DashOptionList;
import 'package:dashboard_team/src/attendance/attendance_dialogs.dart';
import 'package:dashboard_team/src/attendance/attendance_providers.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart' show EditableText, Offset;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'attendance_support.dart';

Future<TestGesture> _mouse(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  return mouse;
}

Future<void> _hover(DashHarness h, TestGesture mouse, Finder f) async {
  await mouse.moveTo(h.tester.getCenter(f));
  await h.settle();
}

int _gets(DashHarness h, String route, [String? param, String? value]) => [
  for (final c in h.server.callsTo(route, method: 'GET'))
    if (param == null || c.query[param]?.single == value) c,
].length;

void main() {
  testWidgets('TEAM-ATT-023 (intent) Add record warms the active people, '
      'the shifts and the 40 days ahead; the dialog asks nothing more', (
    tester,
  ) async {
    final h = await pumpAttendance(tester);
    final mouse = await _mouse(tester);
    int lookAheads() =>
        h.server.callsTo(listT, method: 'GET').where(isLookAhead).length;
    expect(lookAheads(), 0);
    await _hover(h, mouse, pageText('Add record'));
    expect(lookAheads(), 1, reason: 'warmed on hover');
    final active = _gets(h, employeesT, 'employment_status', 'active');
    final shifts = _gets(h, '/staff/work-shifts');
    expect(active, greaterThanOrEqualTo(1));
    expect(shifts, greaterThanOrEqualTo(1));
    await h.tap(pageText('Add record'));
    expect(find.byType(AttendanceAddDialog), findsOneWidget);
    expect(lookAheads(), 1, reason: 'served from the cache');
    expect(_gets(h, employeesT, 'employment_status', 'active'), active);
    expect(_gets(h, '/staff/work-shifts'), shifts);
  });

  testWidgets('TEAM-ATT-004/005 (intent) a person or status option warms '
      'the rows and the cards under it; picking it asks nothing more', (
    tester,
  ) async {
    final h = await pumpAttendance(tester);
    final mouse = await _mouse(tester);
    final mariam = emp('mariam');
    expect(_gets(h, listT, 'employee_id', mariam), 0);
    await h.tap(pageText('Everyone'));
    await h.enterText(
      find.descendant(
        of: find.byType(DashOptionList<String>),
        matching: find.byType(EditableText),
      ),
      'mari',
    );
    await _hover(h, mouse, find.text('Mariam Fathy').hitTestable());
    expect(_gets(h, listT, 'employee_id', mariam), 1, reason: 'warmed');
    expect(_gets(h, summaryT, 'employee_id', mariam), 1, reason: 'warmed');
    await h.tap(find.text('Mariam Fathy').hitTestable());
    expect(_gets(h, listT, 'employee_id', mariam), 1, reason: 'cached');
    expect(_gets(h, summaryT, 'employee_id', mariam), 1, reason: 'cached');

    expect(_gets(h, listT, 'status', 'late'), 0);
    await h.tap(pageText('All statuses'));
    await _hover(h, mouse, find.text('Late').hitTestable());
    expect(_gets(h, listT, 'status', 'late'), 1, reason: 'warmed');
    expect(_gets(h, summaryT, 'status', 'late'), 1, reason: 'warmed');
    await h.tap(find.text('Late').hitTestable());
    expect(_gets(h, listT, 'status', 'late'), 1, reason: 'cached');
    expect(_gets(h, summaryT, 'status', 'late'), 1, reason: 'cached');
  });

  testWidgets('TEAM-ALL-023 TEAM-ATT-020/007 one 500 on the rows and the '
      'cards: the skeleton, then the data; never an error frame', (
    tester,
  ) async {
    final s = attendanceServer();
    final c = ProviderContainer(
      retry: webRetry,
      overrides: [
        transportProvider.overrideWithValue(s.server),
        orgIdProvider.overrideWithValue(SeedIds.sabahOrg),
      ],
    );
    addTearDown(c.dispose);
    final key = attendanceWindow(day(-6), day());

    Future<void> check<T>(String path, FutureProvider<List<T>> read) async {
      s.server.fail('GET', path, MockResponse.error(500, 'boom'));
      final seen = <AsyncValue<List<T>>>[];
      final sub = c.listen(read, (_, next) => seen.add(next));
      await tester.pump(const Duration(milliseconds: 300));
      // Failed once and waiting for the retry: still the skeleton.
      expect(sub.read().awaitingFirst, isTrue, reason: path);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(sub.read().hasValue, isTrue, reason: path);
      expect(sub.read().value, isNotEmpty, reason: path);
      // No frame showed the error state, the table's error line, or a
      // refresh toast (refresh_toast skips a retrying attempt).
      for (final v in seen) {
        expect(v.failedFirst, isFalse, reason: path);
        expect(v.hasError && !v.retrying, isFalse, reason: path);
      }
      expect(s.server.callsTo(path), hasLength(2), reason: path);
      sub.close();
    }

    await check<AttendanceRecord>(listT, attendanceListProvider(key));
    await check(summaryT, attendanceSummaryProvider(key));
  });
}
