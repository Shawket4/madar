// Intent warming on Reports (owner rule): a tab warms the report it shows,
// with the page's dates and branch, so pressing it asks nothing more. Plus
// the automatic retry rule (TEAM-ALL-023): an attempt Riverpod will retry is
// still the skeleton, never the report's error.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart'
    show DashAsyncState, orgIdProvider, transportProvider, webRetry;
import 'package:dashboard_kit/dashboard_kit.dart' show DashPageTabs;
import 'package:dashboard_team/src/team_reports/team_reports_providers.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'reports_support.dart';

Future<TestGesture> _mouse(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  return mouse;
}

Finder _tab(String label) => find.descendant(
  of: find.byType(DashPageTabs<String>),
  matching: find.text(label),
);

void main() {
  testWidgets('TEAM-RPT-005 (intent) resting on a tab warms its report with '
      'the page\'s params; opening it asks nothing more', (tester) async {
    final h = await pumpReports(tester);
    final mouse = await _mouse(tester);
    for (final (label, path) in [
      ('Labour vs sales', labourT),
      ('Overtime & payroll', historyT),
      ('Salary advances', advancesT),
    ]) {
      expect(gets(h, path), isEmpty, reason: label);
      await mouse.moveTo(tester.getCenter(_tab(label)));
      await h.settle();
      expect(gets(h, path), hasLength(1), reason: '$label warmed');
      expect(gets(h, path).single.query, {
        'from': [thisPeriod.from],
        'to': [thisPeriod.to],
      }, reason: label);
      await h.tap(_tab(label));
      expect(gets(h, path), hasLength(1), reason: '$label from the cache');
    }
    // Back to the first tab: the summary it opened on.
    await h.tap(_tab('Attendance & discipline'));
    expect(gets(h, summaryT), hasLength(1));
  });

  testWidgets('TEAM-ALL-023 one 500 on a report: the skeleton, then the '
      'data; never the report\'s error', (tester) async {
    final s = reportsServer();
    final c = ProviderContainer(
      retry: webRetry,
      overrides: [
        transportProvider.overrideWithValue(s.server),
        orgIdProvider.overrideWithValue(SeedIds.sabahOrg),
      ],
    );
    addTearDown(c.dispose);
    const ReportQuery k = (
      from: '2026-07-01',
      to: '2026-10-31',
      branchId: null,
    );

    Future<void> check(String path, FutureProvider<Object?> read) async {
      s.server.fail('GET', path, MockResponse.error(500, 'boom'));
      final seen = <AsyncValue<Object?>>[];
      final sub = c.listen(read, (_, next) => seen.add(next));
      await tester.pump(const Duration(milliseconds: 300));
      expect(sub.read().awaitingFirst, isTrue, reason: path);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(sub.read().hasValue, isTrue, reason: path);
      for (final v in seen) {
        expect(v.hasError && !v.retrying, isFalse, reason: path);
      }
      expect(s.server.callsTo(path), hasLength(2), reason: path);
      sub.close();
    }

    await check(labourT, labourVsSalesProvider(k));
    await check(historyT, payrollHistoryProvider(k));
    await check(advancesT, advancesReportProvider(k));
  });

  testWidgets('TEAM-ALL-023 a 403 is not retried: the error at once', (
    tester,
  ) async {
    final s = reportsServer();
    final c = ProviderContainer(
      retry: webRetry,
      overrides: [
        transportProvider.overrideWithValue(s.server),
        orgIdProvider.overrideWithValue(SeedIds.sabahOrg),
      ],
    );
    addTearDown(c.dispose);
    s.server.fail('GET', historyT, MockResponse.denied('hr.payroll.read'));
    final sub = c.listen(
      payrollHistoryProvider((
        from: thisPeriod.from,
        to: thisPeriod.to,
        branchId: null,
      )),
      (_, _) {},
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(sub.read().failedFirst, isTrue);
    expect(s.server.callsTo(historyT), hasLength(1));
    sub.close();
  });
}
