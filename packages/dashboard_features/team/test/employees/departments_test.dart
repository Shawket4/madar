// The Departments dialog (TEAM-EMP-060…063): the list for everyone; add and
// delete for whoever holds the right at every branch.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_team/src/area_seed.dart';
import 'package:dashboard_team/src/employees/departments_dialog.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'employees_support.dart';

Future<DashHarness> openDepartments(
  WidgetTester tester, {
  Persona persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  Srv? s,
  void Function(MockDb db)? edit,
}) async {
  final h = await pumpEmployees(
    tester,
    persona: persona,
    size: size,
    locale: locale,
    s: s,
    edit: edit,
  );
  await h.tap(pageText(h.t('staff.departments')));
  expect(find.byType(DepartmentsDialog), findsOneWidget);
  return h;
}

Finder card(String name) =>
    find.ancestor(of: surfaceText(name), matching: find.byType(DashCard)).first;

Finder inCard(String name, Finder f) =>
    find.descendant(of: card(name), matching: f);

String departmentId(MockDb db, String name) =>
    db[TeamTables.departments].firstWhere(
          (d) => d['org_id'] == SeedIds.sabahOrg && d['name'] == name,
        )!['id']!
        as String;

void main() {
  testWidgets('TEAM-EMP-060 Departments opens for everyone; Close closes', (
    tester,
  ) async {
    var h = await openDepartments(tester);
    expect(surfaceText('Departments'), findsOneWidget);
    await h.tap(surfaceText('Close'));
    expect(find.byType(DepartmentsDialog), findsNothing);
    h = await openDepartments(tester, persona: Persona.limited);
    // Their read is refused: the refusal with Retry (divergence: the web
    // lists nothing as "No departments yet."), no add.
    expect(surfaceText(h.t('errors.unauthorized')), findsOneWidget);
    expect(surfaceText('No departments yet.'), findsNothing);
    expect(surfaceText('New department'), findsNothing);
    expect(h.server.callsTo(departmentsT).last.status, 403);
    final calls = h.server.callsTo(departmentsT).length;
    await h.tap(surfaceText('Retry'));
    expect(h.server.callsTo(departmentsT).length, calls + 1);
  });

  testWidgets('TEAM-EMP-061 a card per department: name, "n staff", who '
      'manages it; none → "No departments yet."', (tester) async {
    var h = await openDepartments(tester);
    expect(inCard('Bar', find.text('5 staff')), findsOneWidget);
    expect(inCard('Kitchen', find.text('1 staff')), findsOneWidget);
    expect(inCard('Management', find.text('4 staff')), findsOneWidget);
    expect(
      inCard('Kitchen', find.text('Managed by Nour El-Sayed')),
      findsOneWidget,
    );
    await h.tapText('Close');
    h = await openDepartments(
      tester,
      edit: (db) => db[TeamTables.departments].removeWhere(
        (d) => d['org_id'] == SeedIds.sabahOrg,
      ),
    );
    expect(surfaceText('No departments yet.'), findsOneWidget);
  });

  testWidgets('TEAM-EMP-062 add: Enter or the + button; the box clears; the '
      'list (and the filter) updated; no toast', (tester) async {
    final h = await openDepartments(tester);
    final add = inSurface(find.bySemanticsLabel('Add department'));
    expect(
      tester
          .widget<DashIconButton>(
            find.ancestor(of: add, matching: find.byType(DashIconButton)).first,
          )
          .onPressed,
      isNull,
    );
    final box = inSurface(find.byType(DashTextInput));
    await h.enterText(box, '  Bakery ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await h.settle();
    final post = h.server.callsTo(departmentsT, method: 'POST').single;
    expect(post.body, {'name': 'Bakery'});
    expect(inCard('Bakery', find.text('0 staff')), findsOneWidget);
    expect(
      tester
          .widget<EditableText>(
            find.descendant(of: box, matching: find.byType(EditableText)),
          )
          .controller
          .text,
      '',
    );
    await h.enterText(box, 'Delivery');
    await h.tap(add);
    expect(h.server.callsTo(departmentsT, method: 'POST'), hasLength(2));
    expect(card('Delivery'), findsOneWidget);
  });

  testWidgets('TEAM-EMP-062 a refusal toasts; a branch manager has no add', (
    tester,
  ) async {
    final s = employeesServer();
    final refused = MockResponse.badRequest('Department name is required');
    s.server.fail('POST', departmentsT, refused);
    var h = await openDepartments(tester, s: s);
    await h.enterText(inSurface(find.byType(DashTextInput)), 'Bakery');
    await h.tap(inSurface(find.bySemanticsLabel('Add department')));
    await h.expectToast(refusal(h, refused));
    await h.tapText('Close');

    h = await openDepartments(tester, persona: Persona.manager);
    expect(inSurface(find.byType(DashTextInput)), findsNothing);
    expect(inSurface(find.bySemanticsLabel('Add department')), findsNothing);
    expect(inSurface(find.bySemanticsLabel('Delete')), findsNothing);
    expect(card('Bar'), findsOneWidget);
  });

  testWidgets('TEAM-EMP-063 delete: confirm, DELETE; still staffed → the '
      'server\'s count verbatim; empty → gone, no toast', (tester) async {
    final h = await openDepartments(
      tester,
      edit: (db) => db[TeamTables.departments].insert({
        'id': mockUuid('department:sabah:pastry'),
        'org_id': SeedIds.sabahOrg,
        'name': 'Pastry',
        'manager_user_id': null,
        'manager_name': null,
        'employee_count': 0,
      }),
    );
    await h.tap(inCard('Bar', find.bySemanticsLabel('Delete')));
    expect(confirmText('Delete the Bar department?'), findsOneWidget);
    expect(confirmText(h.t('staff.deleteDepartmentHint')), findsOneWidget);
    await h.tap(confirmText('Cancel'));
    expect(h.server.callsTo(departmentT, method: 'DELETE'), isEmpty);
    await h.tap(inCard('Bar', find.bySemanticsLabel('Delete')));
    await h.tap(confirmText('Delete'));
    expect(
      h.server.callsTo(departmentT, method: 'DELETE').single.path,
      '/staff/departments/${departmentId(h.db!, 'Bar')}',
    );
    // The backend's own refusal, its count included (the mock says it).
    await h.expectToast(
      refusal(
        h,
        MockResponse.badRequest(
          '5 employee(s) are still in this department — move them first',
        ),
      ),
    );
    expect(card('Bar'), findsOneWidget);
    await h.tap(inCard('Pastry', find.bySemanticsLabel('Delete')));
    await h.tap(confirmText('Delete'));
    expect(surfaceText('Pastry'), findsNothing);
    expect(
      h.db![TeamTables.departments].find(mockUuid('department:sabah:pastry')),
      isNull,
    );
  });

  testWidgets('TEAM-EMP-061 loading: skeletons, never "No departments yet." '
      'before the answer', (tester) async {
    final s = employeesServer();
    final h = await pumpEmployees(tester, s: s);
    // The page already holds the list: ask it again on the way in.
    final gate = s.server.hold('GET', departmentsT);
    await h.tap(inPage(find.bySemanticsLabel('Refresh')));
    await h.tap(pageText('Departments'));
    expect(surfaceText('Bar'), findsOneWidget, reason: 'the last answer stays');
    gate.release();
    await h.settle();

    final s2 = employeesServer();
    final gate2 = s2.server.hold('GET', departmentsT);
    final h2 = await pumpEmployees(tester, s: s2);
    await h2.tap(pageText('Departments'));
    expect(surfaceText('No departments yet.'), findsNothing);
    expect(inSurface(find.byType(DashSkeleton)), findsNWidgets(3));
    gate2.release();
    await h2.settle();
    expect(surfaceText('Bar'), findsOneWidget);
  });
}
