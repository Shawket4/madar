// The Employees page (`/staff/employees`) driven through the real shell on
// the mock server: one test per inventory row (TEAM-EMP-001…015, 073, 074
// and the area-wide TEAM-ALL rows this page carries), with its refusal,
// loading, empty and error states.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/shell.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart' show MadarClippedText;
import 'package:dashboard_team/src/area_seed.dart';
import 'package:dashboard_team/src/employees/add_employee_dialog.dart';
import 'package:dashboard_team/src/employees/employee_dialog.dart';
import 'package:dashboard_team/src/employees/import_people_dialog.dart';
import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'employees_support.dart';

/// The page's own list calls (the sidebar's set-up check asks for the
/// active people too).
List<MockCall> listCalls(DashHarness h) =>
    h.server.callsTo(listT, method: 'GET');

Finder row(String name) => inPage(find.text(name));

void main() {
  testWidgets('TEAM-EMP-001 header: title, words, Refresh, Departments, '
      'Import and Add for hr.staff.create', (tester) async {
    final h = await pumpEmployees(tester);
    expect(pageText('Employees'), findsOneWidget);
    expect(pageText(h.t('staff.employeesSubtitle2')), findsOneWidget);
    expect(inPage(find.bySemanticsLabel('Refresh')), findsOneWidget);
    expect(pageText('Departments'), findsOneWidget);
    expect(pageText('Import from a spreadsheet'), findsOneWidget);
    expect(pageText('Add employee'), findsOneWidget);
  });

  testWidgets('TEAM-EMP-001 refusal: without hr.staff.create no Import and '
      'no Add; Departments stays', (tester) async {
    final s = employeesServer();
    answerAuthz(s.server, const ['hr.staff.read', 'hr.staff.edit']);
    final h = await pumpEmployees(tester, s: s);
    expect(pageText('Departments'), findsOneWidget);
    expect(pageText('Import from a spreadsheet'), findsNothing);
    expect(pageText('Add employee'), findsNothing);
    expect(h.server.callsTo(listT, method: 'GET'), isNotEmpty);
  });

  testWidgets('TEAM-EMP-002 status filter: All / Active / Suspended / '
      'Terminated refetch with employment_status', (tester) async {
    final h = await pumpEmployees(
      tester,
      edit: (db) {
        empRow(db, 'omar')['employment_status'] = 'suspended';
        empRow(db, 'ziad')['employment_status'] = 'terminated';
      },
    );
    // All statuses: no filter sent.
    expect(listCalls(h).where((c) => c.query.isEmpty), hasLength(1));
    await h.tap(inPage(find.text('All statuses')));
    for (final w in ['Active', 'Suspended', 'Terminated']) {
      expect(find.text(w), findsWidgets);
    }
    await h.tapText('Suspended');
    expect(listCalls(h).last.query, {
      'employment_status': ['suspended'],
    });
    expect(row('Omar Khaled'), findsOneWidget);
    expect(row('Ziad Amr'), findsNothing);
    expect(row('Adham Reda'), findsNothing);

    await h.tap(inPage(find.text('Suspended')));
    await h.tapText('Terminated');
    expect(listCalls(h).last.query, {
      'employment_status': ['terminated'],
    });
    expect(row('Ziad Amr'), findsOneWidget);
    expect(row('Omar Khaled'), findsNothing);
  });

  testWidgets('TEAM-EMP-002 "Active" is the set-up check\'s own request: no '
      'second call for the same key', (tester) async {
    final h = await pumpEmployees(tester);
    final before = listCalls(
      h,
    ).where((c) => c.query['employment_status']?.first == 'active').length;
    expect(before, 1, reason: 'the sidebar asked once');
    await h.tap(inPage(find.text('All statuses')));
    await h.tapText('Active');
    final after = listCalls(
      h,
    ).where((c) => c.query['employment_status']?.first == 'active').length;
    expect(after, before);
    expect(row('Adham Reda'), findsOneWidget);
  });

  testWidgets('TEAM-EMP-003 department filter: every department, sends '
      'department_id', (tester) async {
    final h = await pumpEmployees(tester);
    expect(h.server.callsTo(departmentsT, method: 'GET'), hasLength(1));
    await h.tap(inPage(find.text('All departments')));
    for (final d in ['Management', 'Bar', 'Front of house', 'Kitchen']) {
      expect(find.text(d), findsWidgets);
    }
    await h.tap(find.text('Kitchen').hitTestable());
    final kitchen = h.db![TeamTables.departments].firstWhere(
      (d) => d['name'] == 'Kitchen',
    )!['id'];
    expect(listCalls(h).last.query, {
      'department_id': [kitchen],
    });
    expect(row('Hassan Ibrahim'), findsOneWidget);
    expect(row('Adham Reda'), findsNothing);
  });

  testWidgets('TEAM-EMP-004/074 search: names, kind/role/status keys, phone '
      'digits and department, case-insensitive; job title is not searched; '
      'no hits shows the page\'s own empty state', (tester) async {
    final h = await pumpEmployees(tester);
    final box = inPage(find.byType(DashSearchInput));
    Future<void> search(String q) async {
      await h.enterText(box, q);
      await h.settle();
    }

    await search('mariam');
    expect(row('Mariam Fathy'), findsOneWidget);
    expect(row('Adham Reda'), findsNothing);
    await search('201110001111');
    expect(row('Mariam Fathy'), findsOneWidget);
    await search('WAITER'); // role key
    expect(row('Laila Ehab'), findsOneWidget);
    expect(row('Adham Reda'), findsOneWidget);
    expect(row('Mariam Fathy'), findsNothing);
    await search('kitchen'); // department name (and role key)
    expect(row('Hassan Ibrahim'), findsOneWidget);
    await search('Barista'); // a job title: not searched
    expect(row('Mariam Fathy'), findsNothing);
    expect(pageText('No employees yet'), findsOneWidget);
    expect(pageText(h.t('common.noResults')), findsNothing);
    await search('linked'); // the kind key, not its word
    expect(row('Adham Reda'), findsOneWidget);
    await search('Madar user');
    expect(row('Adham Reda'), findsNothing);
  });

  testWidgets('TEAM-EMP-005 columns: name + job title, kind, branches, '
      'number, staff app, role, phone, department, status', (tester) async {
    await pumpEmployees(tester);
    for (final head in [
      'Name',
      'Kind',
      'Branches',
      'WhatsApp number',
      'Staff app',
      'Madar role',
      'Phone',
      'Department',
      'Status',
      'Base salary (monthly)',
    ]) {
      expect(
        inPage(find.text(head.toUpperCase())),
        findsOneWidget,
        reason: head,
      );
    }
    expect(pageText('Barista'), findsWidgets);
    expect(pageText('Madar user'), findsWidgets);
    expect(pageText('+201110001111'), findsOneWidget);
    expect(pageText('Teller'), findsWidgets);
    expect(pageText('Samsung Galaxy A54'), findsOneWidget);
    expect(pageText('since 02 Sept 2026'), findsOneWidget);
    expect(pageText('Front of house'), findsWidgets);
    expect(pageText('Active'), findsWidgets);
    // The owner (10th by name) works every branch: names joined.
    expect(pageText('Heliopolis, Maadi, New Cairo, Zamalek'), findsOneWidget);
  });

  testWidgets('TEAM-EMP-005 kinds and statuses: Staff app, Records only, '
      'No job title, Terminated, no phone "—"', (tester) async {
    final h = await pumpEmployees(
      tester,
      persona: Persona.dawamOnly,
      edit: (db) {
        empRow(db, 'hamza')
          ..['employment_status'] = 'terminated'
          ..['job_title'] = null
          ..['phone'] = null;
      },
    );
    expect(pageText('Staff app'), findsWidgets);
    expect(pageText('Records only'), findsWidgets);
    expect(pageText('No job title'), findsOneWidget);
    expect(pageText('Terminated'), findsOneWidget);
    expect(h.t('staff.kind_app'), 'Staff app');
  });

  testWidgets('TEAM-EMP-006 salary: the owner sees it, "Not set" with its '
      'hint for nobody-set; a manager sees no column', (tester) async {
    var h = await pumpEmployees(tester);
    expect(inPage(find.text('BASE SALARY (MONTHLY)')), findsOneWidget);
    expect(pageText('EGP 7,500.00'), findsWidgets); // Adham
    // Nour (the owner) has no salary on file.
    expect(pageText('Not set'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is Tooltip && w.message == h.t('dawam.salaryNotSetHint'),
      ),
      findsOneWidget,
    );

    h = await pumpEmployees(tester, persona: Persona.manager);
    expect(inPage(find.text('BASE SALARY (MONTHLY)')), findsNothing);
    expect(pageText('EGP 7,500.00'), findsNothing);
  });

  testWidgets('TEAM-EMP-006 salary hidden from this caller reads "—" while '
      'the column shows for whoever sets pay', (tester) async {
    final s = employeesServer(persona: Persona.manager);
    answerAuthz(s.server, const [
      'hr.staff.read',
      'hr.staff.edit',
      'hr.payroll.edit',
    ]);
    final h = await pumpEmployees(tester, persona: Persona.manager, s: s);
    expect(inPage(find.text('BASE SALARY (MONTHLY)')), findsOneWidget);
    expect(pageText('EGP 7,500.00'), findsNothing);
    expect(h.server.callsTo(listT).last.status, 200);
  });

  testWidgets('TEAM-EMP-007 loading: skeleton rows until the list answers', (
    tester,
  ) async {
    final s = employeesServer();
    final gate = s.server.hold('GET', listT);
    final h = await pumpEmployees(tester, s: s);
    expect(inPage(find.byType(DashSkeleton)), findsWidgets);
    expect(row('Adham Reda'), findsNothing);
    gate.release();
    await h.settle();
    expect(inPage(find.byType(DashSkeleton)), findsNothing);
    expect(row('Adham Reda'), findsOneWidget);
  });

  testWidgets('TEAM-EMP-008 error: words + Retry refetches only the list', (
    tester,
  ) async {
    final s = employeesServer();
    final boom = MockResponse.error(500, 'Database error: boom');
    s.server.fail('GET', listT, boom, times: null);
    final h = await pumpEmployees(tester, s: s);
    expect(pageText(h.t('common.loadFailed')), findsOneWidget);
    expect(pageText(refusal(h, boom)), findsOneWidget);
    final departments = h.server.callsTo(departmentsT).length;
    final before = listCalls(h).length;
    s.server.clearFailures();
    // While the retry runs the error stays: no skeleton, no empty words.
    final gate = s.server.hold('GET', listT);
    await h.tap(inPage(find.text('Retry')));
    expect(pageText(h.t('common.loadFailed')), findsOneWidget);
    expect(inPage(find.byType(DashSkeleton)), findsNothing);
    expect(pageText('No employees yet'), findsNothing);
    gate.release();
    await h.settle();
    expect(listCalls(h).length, before + 1);
    expect(h.server.callsTo(departmentsT).length, departments);
    expect(row('Adham Reda'), findsOneWidget);
  });

  testWidgets('TEAM-EMP-009 empty: "No employees yet" with Add for a '
      'creator, no button without hr.staff.create', (tester) async {
    var h = await pumpEmployees(tester, edit: noPeople);
    expect(pageText('No employees yet'), findsOneWidget);
    expect(pageText(h.t('staff.noEmployeesHint2')), findsOneWidget);
    expect(pageText('Add employee'), findsNWidgets(2));
    await h.tap(pageText('Add employee').last);
    expect(find.byType(AddEmployeeDialog), findsOneWidget);
    await h.tapText('Cancel');

    final s = employeesServer(edit: noPeople);
    answerAuthz(s.server, const ['hr.staff.read']);
    h = await pumpEmployees(tester, s: s);
    expect(pageText('No employees yet'), findsOneWidget);
    expect(pageText('Add employee'), findsNothing);
  });

  testWidgets('TEAM-EMP-010 a row opens the profile; not gated in the UI', (
    tester,
  ) async {
    final s = employeesServer();
    answerAuthz(s.server, const ['hr.staff.read']);
    final h = await pumpEmployees(tester, s: s);
    await h.tap(row('Mariam Fathy'));
    expect(find.byType(EmployeeDialog), findsOneWidget);
    expect(surfaceText('Mariam Fathy'), findsWidgets);
  });

  testWidgets('TEAM-EMP-011 Sign the phone out: only on rows with a phone; '
      'confirm, DELETE, toast, the list refetched', (tester) async {
    final h = await pumpEmployees(tester);
    // Mariam and Ali have a phone signed in on the first page.
    expect(
      inPage(find.bySemanticsLabel('Sign the phone out')),
      findsNWidgets(2),
    );
    final before = listCalls(h).length;
    await h.tap(inPage(find.bySemanticsLabel('Sign the phone out')).at(1));
    expect(confirmText("Sign Mariam Fathy's phone out?"), findsOneWidget);
    expect(confirmText(h.t('dawam.revokeHint')), findsOneWidget);
    await h.tap(confirmText('Sign the phone out'));
    final call = h.server.callsTo(deviceT).single;
    expect(call.method, 'DELETE');
    expect(call.path, '/staff/employees/${emp('mariam')}/device');
    await h.expectToast('Phone signed out');
    expect(listCalls(h).length, greaterThan(before));
    expect(pageText('Samsung Galaxy A54'), findsNothing);
    expect(empRow(h.db!, 'mariam')['device_model'], isNull);
  });

  testWidgets('TEAM-EMP-011 Cancel sends nothing; a refusal toasts', (
    tester,
  ) async {
    final h = await pumpEmployees(tester);
    await h.tap(inPage(find.bySemanticsLabel('Sign the phone out')).first);
    await h.tap(confirmText('Cancel'));
    expect(h.server.callsTo(deviceT), isEmpty);
    h.server.fail('DELETE', deviceT, MockResponse.denied('hr.staff.edit'));
    await h.tap(inPage(find.bySemanticsLabel('Sign the phone out')).first);
    await h.tap(confirmText('Sign the phone out'));
    await h.expectToast(h.t('errors.unauthorized'));
  });

  testWidgets('TEAM-EMP-012 End employment: confirm, DELETE, toast, the row '
      'reads Terminated and loses the action', (tester) async {
    final h = await pumpEmployees(tester);
    final ends = inPage(find.bySemanticsLabel('End employment'));
    expect(ends, findsNWidgets(10));
    await h.tap(ends.first); // Adham Reda
    expect(confirmText("End Adham Reda's employment?"), findsOneWidget);
    expect(confirmText(h.t('staff.endEmploymentHint')), findsOneWidget);
    await h.tap(confirmText('End employment'));
    final call = h.server.callsTo(employeeT, method: 'DELETE').single;
    expect(call.path, '/staff/employees/${emp('adham')}');
    await h.expectToast('Employment ended');
    expect(empRow(h.db!, 'adham')['employment_status'], 'terminated');
    expect(empRow(h.db!, 'adham')['termination_date'], '2026-10-08');
    expect(pageText('Terminated'), findsOneWidget);
    expect(inPage(find.bySemanticsLabel('End employment')), findsNWidgets(9));
  });

  testWidgets('TEAM-EMP-012 a refusal toasts the server\'s words', (
    tester,
  ) async {
    final s = employeesServer();
    final gone = MockResponse.notFound('Employee not found');
    s.server.fail('DELETE', employeeT, gone);
    final h = await pumpEmployees(tester, s: s);
    await h.tap(inPage(find.bySemanticsLabel('End employment')).first);
    await h.tap(confirmText('End employment'));
    await h.expectToast(refusal(h, gone));
  });

  testWidgets('TEAM-EMP-013 no row actions without hr.staff.edit and '
      'hr.staff.delete; a manager (no delete) only signs phones out', (
    tester,
  ) async {
    final s = employeesServer();
    answerAuthz(s.server, const ['hr.staff.read', 'hr.staff.create']);
    var h = await pumpEmployees(tester, s: s);
    expect(inPage(find.bySemanticsLabel('End employment')), findsNothing);
    expect(inPage(find.bySemanticsLabel('Sign the phone out')), findsNothing);

    h = await pumpEmployees(tester, persona: Persona.manager);
    expect(inPage(find.bySemanticsLabel('End employment')), findsNothing);
    expect(inPage(find.bySemanticsLabel('Sign the phone out')), findsOneWidget);
    expect(h.location.path, employeesPath);
  });

  testWidgets('TEAM-EMP-014 Add employee opens the add dialog', (tester) async {
    final h = await pumpEmployees(tester);
    await h.tap(pageText('Add employee'));
    expect(find.byType(AddEmployeeDialog), findsOneWidget);
  });

  testWidgets('TEAM-EMP-015 Import from a spreadsheet opens the import '
      'dialog', (tester) async {
    final h = await pumpEmployees(tester);
    await h.tap(pageText('Import from a spreadsheet'));
    expect(find.byType(ImportPeopleDialog), findsOneWidget);
  });

  testWidgets('TEAM-EMP-073 phone: each person a card titled by name and job '
      'title, actions on the card; the profile a centred card', (tester) async {
    final h = await pumpEmployees(tester, size: DashSize.phone);
    expect(inPage(find.byType(DashCard)), findsNWidgets(10));
    expect(row('Mariam Fathy'), findsOneWidget);
    expect(inPage(find.bySemanticsLabel('End employment')), findsNWidgets(10));
    expect(inPage(find.text('Columns')), findsNothing);
    await h.tap(row('Adham Reda'));
    expect(find.byType(EmployeeDialog), findsOneWidget);
    expectPhoneDialog(tester, primary: 'Save', secondary: 'Cancel');
  });

  // ── area-wide rows on this page ─────────────────────────────────────────

  testWidgets('TEAM-ALL-001/002 the Employees leaf shows with hr.staff.read, '
      'hidden without', (tester) async {
    var h = await pumpEmployees(tester);
    expect(
      find.descendant(
        of: find.byType(DashSidebar),
        matching: find.text('Employees'),
      ),
      findsOneWidget,
    );
    h = await pumpEmployees(tester, persona: Persona.limited);
    expect(
      find.descendant(
        of: find.byType(DashSidebar),
        matching: find.text('Employees'),
      ),
      findsNothing,
    );
    expect(h.location.path, employeesPath);
  });

  testWidgets('TEAM-ALL-005 module off: the module refusal, nothing asked', (
    tester,
  ) async {
    final s = employeesServer(
      edit: (db) => db['orgs'].update(SeedIds.sabahOrg, {
        'modules': ['pos'],
      }),
    );
    final h = await pumpEmployees(tester, s: s);
    expect(find.text(h.t('dawam.moduleOffTitle')), findsOneWidget);
    expect(find.text(h.t('dawam.moduleDawamOff')), findsOneWidget);
    expect(page, findsNothing);
    expect(listCalls(h).where((c) => c.query.isEmpty), isEmpty);
  });

  testWidgets('TEAM-ALL-007 no in-page guard: a person without hr.staff.read '
      'reaches the page and the list says the refusal', (tester) async {
    final h = await pumpEmployees(tester, persona: Persona.limited);
    expect(pageText('Employees'), findsOneWidget);
    expect(pageText(h.t('errors.unauthorized')), findsOneWidget);
    expect(listCalls(h).last.status, 403);
    expect(pageText('Add employee'), findsNothing);
  });

  testWidgets('TEAM-ALL-008 Refresh refetches the page\'s reads and spins '
      'while they are in flight', (tester) async {
    final h = await pumpEmployees(tester);
    final lists = listCalls(h).length;
    final departments = h.server.callsTo(departmentsT).length;
    final gate = h.server.hold('GET', departmentsT);
    await h.tap(inPage(find.bySemanticsLabel('Refresh')));
    expect(inPage(find.bySemanticsLabel('Refreshing…')), findsOneWidget);
    gate.release();
    await h.settle();
    expect(inPage(find.bySemanticsLabel('Refresh')), findsOneWidget);
    expect(listCalls(h).length, greaterThan(lists));
    expect(h.server.callsTo(departmentsT).length, departments + 1);
  });

  testWidgets('TEAM-ALL-009 back to the app after 30 s refetches the list; '
      'sooner does nothing', (tester) async {
    final h = await pumpEmployees(tester);
    final before = listCalls(h).length;
    h.server.clock.advance(const Duration(seconds: 10));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await h.settle();
    expect(listCalls(h).length, before);
    h.server.clock.advance(const Duration(seconds: 30));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await h.settle();
    expect(listCalls(h).length, before + 1);
  });

  testWidgets('TEAM-ALL-010/022 a failed refresh replaces the rows with the '
      'error (the web\'s Employees table) and toasts once', (tester) async {
    final h = await pumpEmployees(tester);
    expect(row('Adham Reda'), findsOneWidget);
    h.server.fail(
      'GET',
      listT,
      MockResponse.error(429, 'Too many requests'),
      times: null,
    );
    await h.tap(inPage(find.bySemanticsLabel('Refresh')));
    expect(row('Adham Reda'), findsNothing);
    expect(pageText(h.t('common.loadFailed')), findsOneWidget);
    await h.expectToast(h.t('errors.tooManyRequests'));
  });

  testWidgets('TEAM-ALL-013 numbers read left to right in Arabic', (
    tester,
  ) async {
    await pumpEmployees(tester, locale: 'ar');
    final phone = tester.widget<Text>(pageText('+201110001111'));
    expect(phone.textDirection, TextDirection.ltr);
    expect(
      tester
          .widget<MadarClippedText>(
            find.ancestor(
              of: pageText('+201110001111'),
              matching: find.byType(MadarClippedText),
            ),
          )
          .textDirection,
      TextDirection.ltr,
    );
  });

  testWidgets('TEAM-ALL-018 the scope bar\'s branch is not sent', (
    tester,
  ) async {
    final h = await pumpEmployees(tester, s: employeesServer());
    await h.tap(find.text('All branches'));
    await h.tap(find.text('Zamalek').hitTestable());
    await h.tap(inPage(find.bySemanticsLabel('Refresh')));
    expect(
      listCalls(h).every((c) => !c.query.containsKey('branch_id')),
      isTrue,
    );
  });

  testWidgets('TEAM-ALL-020 pages of 10: "Page 1 of 2", Next/Previous; the '
      'Columns menu lists every column', (tester) async {
    final h = await pumpEmployees(tester);
    expect(pageText('Page 1 of 2'), findsOneWidget);
    expect(row('Omar Khaled'), findsNothing);
    await h.tap(inPage(find.bySemanticsLabel('Next')));
    expect(pageText('Page 2 of 2'), findsOneWidget);
    expect(row('Omar Khaled'), findsOneWidget);
    await h.tap(inPage(find.bySemanticsLabel('Previous')));
    expect(pageText('Page 1 of 2'), findsOneWidget);
    await h.tap(inPage(find.text('Columns')));
    for (final c in [
      'Name',
      'Kind',
      'Branches',
      'WhatsApp number',
      'Staff app',
      'Madar role',
      'Phone',
      'Department',
      'Status',
      'Base salary (monthly)',
    ]) {
      expect(find.text(c), findsWidgets, reason: c);
    }
    // Hide the Kind column.
    await h.tap(find.text('Kind').last);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
    expect(inPage(find.text('KIND')), findsNothing);
  });

  testWidgets('TEAM-ALL-021 filters live in the page, not the URL, and reset '
      'when it is left', (tester) async {
    final h = await pumpEmployees(tester);
    await h.tap(inPage(find.text('All statuses')));
    await h.tapText('Suspended');
    expect(h.location.query, isEmpty);
    h.allowUnmatched = true;
    await h.go('/staff/attendance');
    await h.go(employeesPath);
    expect(pageText('All statuses'), findsOneWidget);
  });

  testWidgets('TEAM-ALL-021 a dialog closes on Escape sending nothing', (
    tester,
  ) async {
    final h = await pumpEmployees(tester);
    await h.tap(row('Mariam Fathy'));
    expect(find.byType(EmployeeDialog), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
    expect(find.byType(EmployeeDialog), findsNothing);
    expect(h.server.callsTo(employeeT), isEmpty);
  });
}
