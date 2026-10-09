// Intent warming on Employees (owner rule): a row warms the profile's salary
// rules, a filter option the list under it, Add employee the linkable users
// and the rules, Departments its list, so each press asks nothing more.
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_team/src/area_seed.dart';
import 'package:dashboard_team/src/employees/add_employee_dialog.dart';
import 'package:dashboard_team/src/employees/departments_dialog.dart';
import 'package:dashboard_team/src/employees/employee_dialog.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'employees_support.dart';

const String settingsT = '/staff/attendance/settings';

Future<TestGesture> mouseAt(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  return mouse;
}

Future<void> hover(DashHarness h, TestGesture mouse, Finder f) async {
  await mouse.moveTo(h.tester.getCenter(f));
  await h.settle();
}

int gets(DashHarness h, String route, [String? param, String? value]) => [
  for (final c in h.server.callsTo(route, method: 'GET'))
    if (param == null || c.query[param]?.single == value) c,
].length;

void main() {
  testWidgets('TEAM-EMP-010 (intent) a row warms the profile\'s salary '
      'rules; opening it asks nothing more', (tester) async {
    final h = await pumpEmployees(tester);
    final mouse = await mouseAt(tester);
    await hover(h, mouse, inPage(find.text('Adham Reda')));
    final warmed = gets(h, settingsT);
    expect(warmed, greaterThanOrEqualTo(1), reason: 'warmed on hover');
    await h.tap(inPage(find.text('Adham Reda')));
    expect(find.byType(EmployeeDialog), findsOneWidget);
    expect(gets(h, settingsT), warmed, reason: 'served from the cache');
  });

  testWidgets('TEAM-EMP-002/003 (intent) a filter option warms the list '
      'under it; picking it asks nothing more', (tester) async {
    final h = await pumpEmployees(tester);
    final mouse = await mouseAt(tester);
    const status = 'employment_status';
    expect(gets(h, listT, status, 'suspended'), 0);
    await h.tap(inPage(find.text('All statuses')));
    await hover(h, mouse, find.text('Suspended').hitTestable().last);
    expect(gets(h, listT, status, 'suspended'), 1, reason: 'warmed');
    await h.tap(find.text('Suspended').hitTestable().last);
    expect(gets(h, listT, status, 'suspended'), 1, reason: 'from the cache');

    final kitchen =
        '${h.db![TeamTables.departments].firstWhere((d) => d['name'] == 'Kitchen')!['id']}';
    expect(gets(h, listT, 'department_id', kitchen), 0);
    await h.tap(inPage(find.text('All departments')));
    await hover(h, mouse, find.text('Kitchen').hitTestable().last);
    expect(gets(h, listT, 'department_id', kitchen), 1, reason: 'warmed');
    await h.tap(find.text('Kitchen').hitTestable().last);
    expect(gets(h, listT, 'department_id', kitchen), 1);
  });

  testWidgets('TEAM-EMP-014/012 (intent) Add employee warms the linkable '
      'users; Departments opens on the page\'s own list', (tester) async {
    final h = await pumpEmployees(tester);
    final mouse = await mouseAt(tester);
    expect(gets(h, linkableT), 0);
    await hover(h, mouse, pageText('Add employee'));
    expect(gets(h, linkableT), 1, reason: 'warmed on hover');
    final rules = gets(h, settingsT);
    expect(rules, greaterThanOrEqualTo(1));
    await h.tap(pageText('Add employee'));
    expect(find.byType(AddEmployeeDialog), findsOneWidget);
    expect(gets(h, linkableT), 1, reason: 'served from the cache');
    expect(gets(h, settingsT), rules);
    await h.tapText('Cancel');

    final departments = gets(h, departmentsT);
    await hover(h, mouse, pageText('Departments'));
    await h.tap(pageText('Departments'));
    expect(find.byType(DepartmentsDialog), findsOneWidget);
    expect(gets(h, departmentsT), departments);
  });
}
