// The owner's rule (2026-10-11): a filter carries through navigation. The
// team pages' filters come back after another page (`DashRememberedState`;
// payroll's view through `DashListMemory`).
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_team/src/payroll/payroll_data.dart';
import 'package:flutter_test/flutter_test.dart';

import 'attendance/attendance_support.dart';

Finder _option(String label) => find
    .descendant(
      of: find.byWidgetPredicate(
        (w) => w.runtimeType.toString().startsWith('DashOptionList'),
      ),
      matching: find.text(label),
    )
    .last;

void main() {
  testWidgets('attendance: the status filter comes back after another page', (
    tester,
  ) async {
    final h = await pumpAttendance(tester);
    await h.tap(pageText('All statuses'));
    await h.tap(find.text('Late').hitTestable());
    expect(pageListCalls(h).last.query['status'], ['late']);
    final from = pageListCalls(h).last.query['from'];

    await h.go('/staff/requests');
    await h.go(attendancePath);
    expect(pageText('All statuses'), findsNothing);
    expect(pageListCalls(h).last.query['status'], ['late']);
    expect(pageListCalls(h).last.query['from'], from);
  });

  testWidgets('requests: the kind and status come back after another page', (
    tester,
  ) async {
    final h = await pumpAttendance(tester);
    await h.go('/staff/requests');
    await h.tap(find.text('All kinds'));
    await h.tap(_option('Mission'));
    MockCallQuery last() =>
        h.server.callsTo('/staff/requests', method: 'GET').last.query;
    expect(last()['kind'], ['mission']);

    await h.go(attendancePath);
    await h.go('/staff/requests');
    expect(last(), {
      'kind': ['mission'],
      'status': ['pending'],
    });
    expect(find.text('All kinds'), findsNothing);
  });

  testWidgets('payroll: the tab comes back after another page', (tester) async {
    final h = await pumpAttendance(tester);
    await h.go('/staff/payroll');
    await h.tap(find.text(h.t('dawam.payLines')).first);
    expect(h.container.read(payrollViewProvider).tab, PayrollTab.lines);
    await h.go(attendancePath);
    await h.go('/staff/payroll');
    expect(h.container.read(payrollViewProvider).tab, PayrollTab.lines);
    expect(
      h.container
          .read(dashListMemoryProvider)
          .recall(PayrollViewNotifier.memoryKey)
          .string('tab'),
      'lines',
    );
  });
}

typedef MockCallQuery = Map<String, List<String>>;
