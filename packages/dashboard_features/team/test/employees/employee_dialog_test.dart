// The employee profile dialog (TEAM-EMP-016…029): opened from a row of the
// Employees page, driven through the real shell on the mock server.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_team/src/area_seed.dart';
import 'package:dashboard_team/src/employees/employee_dialog.dart';
import 'package:dashboard_team/src/employees/employee_fields.dart';
import 'package:dashboard_team/src/shared/staff_query.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'employees_support.dart';

Future<DashHarness> openProfile(
  WidgetTester tester,
  String name, {
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
  await h.tap(inPage(find.text(name)));
  expect(find.byType(EmployeeDialog), findsOneWidget);
  return h;
}

Finder field<T>(String label) =>
    inSurface(find.widgetWithText(T, label)).first;

Future<void> type(DashHarness h, Finder f, String text) =>
    h.enterText(f, text);

Future<void> pick(DashHarness h, String label, String option) async {
  await h.tap(field<DashSelectField<String>>(label));
  await h.tap(find.text(option).hitTestable().last);
}

Future<void> save(DashHarness h) => h.tap(surfaceText('Save'));

String boxText(WidgetTester tester, Finder f) => tester
    .widget<EditableText>(
      find.descendant(of: f, matching: find.byType(EditableText)).first,
    )
    .controller
    .text;

/// A background refetch of everything under /staff/employees landing.
Future<void> refetchList(DashHarness h) async {
  h.container.read(staffRevisionsProvider.notifier).invalidateEmployees();
  await h.settle();
}

Map<String, Object?> lastPut(DashHarness h) =>
    (h.server.callsTo(employeeT, method: 'PUT').last.body! as Map)
        .cast<String, Object?>();

void main() {
  testWidgets('TEAM-EMP-016 the profile: the name as title, linked words, '
      'the form from the row, departments and branches read', (tester) async {
    final h = await openProfile(tester, 'Mariam Fathy');
    expect(surfaceText(h.t('staff.employeeDialogLinked')), findsOneWidget);
    expect(inSurface(find.text('Barista')), findsWidgets);
    expect(inSurface(find.text('+201110001111')), findsWidgets);
    expect(inSurface(find.text('SB-006')), findsWidgets);
    expect(inSurface(find.text('Bar')), findsWidgets);
    expect(inSurface(find.text('01 Apr 2024')), findsOneWidget);
    expect(h.server.callsTo(departmentsT), isNotEmpty);
    expect(h.server.callsTo('/branches'), isNotEmpty);
    // Two columns from the web's `sm` up: name and number side by side.
    final name = tester.getTopLeft(field<DashTextField>('Name'));
    final phone = tester.getTopLeft(field<PhoneField>('WhatsApp number'));
    expect(name.dy, phone.dy);
  });

  testWidgets('TEAM-EMP-016 records-only person: "On the staff records only"; '
      'one column on a phone', (tester) async {
    final h = await openProfile(
      tester,
      'Sherif Mansour',
      persona: Persona.dawamOnly,
      size: DashSize.phone,
    );
    expect(surfaceText(h.t('staff.employeeDialogUnlinked')), findsOneWidget);
    final name = tester.getTopLeft(field<DashTextField>('Name'));
    final phone = tester.getTopLeft(field<PhoneField>('WhatsApp number'));
    expect(phone.dy, greaterThan(name.dy));
  });

  testWidgets('TEAM-EMP-017 name: required, at most 120; nothing is sent', (
    tester,
  ) async {
    final h = await openProfile(tester, 'Adham Reda');
    await type(h, field<DashTextField>('Name'), '   ');
    await save(h);
    expect(surfaceText('A name is needed'), findsOneWidget);
    await type(h, field<DashTextField>('Name'), 'x' * 121);
    expect(surfaceText('At most 120 characters'), findsOneWidget);
    expect(h.server.callsTo(employeeT, method: 'PUT'), isEmpty);
  });

  testWidgets('TEAM-EMP-018 number: optional, must be a phone, left to right', (
    tester,
  ) async {
    final h = await openProfile(
      tester,
      'Sherif Mansour',
      persona: Persona.dawamOnly,
    );
    final phone = field<PhoneField>('WhatsApp number');
    await type(h, phone, '12345');
    await save(h);
    expect(surfaceText('Not a phone number'), findsOneWidget);
    expect(h.server.callsTo(employeeT, method: 'PUT'), isEmpty);
    final input = tester.widget<DashTextInput>(
      find.descendant(of: phone, matching: find.byType(DashTextInput)),
    );
    expect(input.textDirection, TextDirection.ltr);
    // Records-only: an empty number is fine.
    await type(h, phone, '');
    await save(h);
    expect(lastPut(h)['phone'], '');
    await h.expectToast('Employee saved');
  });

  testWidgets('TEAM-EMP-019 app access: the phone signed in, or none; on with '
      'no number is refused', (tester) async {
    var h = await openProfile(tester, 'Mariam Fathy');
    expect(
      surfaceText('Signed in on Samsung Galaxy A54 since 02 Sept 2026'),
      findsOneWidget,
    );
    await h.tapText('Cancel');
    h = await openProfile(tester, 'Adham Reda');
    expect(surfaceText('No phone signed in.'), findsOneWidget);
    await type(h, field<PhoneField>('WhatsApp number'), '');
    await save(h);
    expect(
      surfaceText('The staff app needs their WhatsApp number'),
      findsOneWidget,
    );
    expect(h.server.callsTo(employeeT, method: 'PUT'), isEmpty);
    await h.tap(field<DashCheckboxField>('May sign in to the staff app'));
    expect(
      surfaceText('The staff app needs their WhatsApp number'),
      findsNothing,
    );
  });

  testWidgets('TEAM-EMP-020 branches: a tick per branch, at least one', (
    tester,
  ) async {
    final h = await openProfile(tester, 'Adham Reda');
    for (final b in ['Heliopolis', 'Maadi', 'New Cairo', 'Zamalek']) {
      expect(inSurface(find.widgetWithText(DashCheckChip, b)), findsOneWidget);
    }
    await h.tap(inSurface(find.widgetWithText(DashCheckChip, 'Zamalek')));
    await save(h);
    expect(surfaceText('Pick at least one branch'), findsOneWidget);
    await h.tap(inSurface(find.widgetWithText(DashCheckChip, 'Maadi')));
    await h.tap(inSurface(find.widgetWithText(DashCheckChip, 'Heliopolis')));
    expect(surfaceText('Pick at least one branch'), findsNothing);
    await save(h);
    expect(lastPut(h)['branch_ids'], [SeedIds.maadi, SeedIds.heliopolis]);
    await h.expectToast('Employee saved');
  });

  testWidgets('TEAM-EMP-016/028 a fresher row re-seeds the form until '
      'something is edited; the save never sends a stale copy', (
    tester,
  ) async {
    final h = await openProfile(tester, 'Adham Reda');
    expect(boxText(tester, field<DashTextField>('Job title')), 'Waiter');
    empRow(h.db!, 'adham')['job_title'] = 'Head waiter';
    await refetchList(h);
    expect(boxText(tester, field<DashTextField>('Job title')), 'Head waiter');
    await type(h, field<DashTextField>('Notes'), 'Night owl');
    empRow(h.db!, 'adham')['job_title'] = 'Floor lead';
    await refetchList(h);
    // Edited: what is on screen stays.
    expect(boxText(tester, field<DashTextField>('Job title')), 'Head waiter');
    expect(boxText(tester, field<DashTextField>('Notes')), 'Night owl');
    await save(h);
    expect(lastPut(h)['job_title'], 'Head waiter');
    expect(lastPut(h)['notes'], 'Night owl');
    await h.expectToast('Employee saved');
  });

  testWidgets('TEAM-EMP-021 job title, employee number, department, hire '
      'date', (tester) async {
    final h = await openProfile(tester, 'Adham Reda');
    await type(h, field<DashTextField>('Job title'), 'Head waiter');
    await type(h, field<DashTextField>('Employee number'), 'EMP-042');
    await pick(h, 'Department', 'No department');
    await h.tap(field<EmployeeDateField>('Hire date'));
    await h.tap(find.text('Today').hitTestable());
    await save(h);
    final body = lastPut(h);
    expect(body['job_title'], 'Head waiter');
    expect(body['employee_code'], 'EMP-042');
    expect(body.containsKey('department_id'), isTrue);
    expect(body['department_id'], isNull);
    expect(body['hire_date'], '2026-10-08');
    await h.expectToast('Employee saved');
    final row = empRow(h.db!, 'adham');
    expect(row['job_title'], 'Head waiter');
    expect(row['department_id'], isNull);
  });

  testWidgets('TEAM-EMP-021 the hire date can be emptied: Clear sends '
      'hire_date null', (tester) async {
    final h = await openProfile(tester, 'Adham Reda');
    await h.tap(field<EmployeeDateField>('Hire date'));
    // Opens on the hire date's own month.
    expect(find.text('June 2025').hitTestable(), findsOneWidget);
    await h.tap(find.text('Clear').hitTestable());
    expect(
      find.descendant(
        of: field<EmployeeDateField>('Hire date'),
        matching: find.text('Pick a date'),
      ),
      findsOneWidget,
    );
    await save(h);
    final body = lastPut(h);
    expect(body.containsKey('hire_date'), isTrue);
    expect(body['hire_date'], isNull);
    await h.expectToast('Employee saved');
    expect(empRow(h.db!, 'adham')['hire_date'], isNull);
  });

  testWidgets('TEAM-EMP-021 empty job title shows "Head chef"; too long is '
      'refused with words', (tester) async {
    final h = await openProfile(
      tester,
      'Adham Reda',
      edit: (db) => empRow(db, 'adham')['job_title'] = null,
    );
    expect(surfaceText('Head chef'), findsOneWidget);
    await type(h, field<DashTextField>('Employee number'), 'E' * 65);
    await save(h);
    expect(surfaceText('At most 64 characters'), findsOneWidget);
    await pick(h, 'Department', 'Kitchen');
    await type(h, field<DashTextField>('Employee number'), 'K-1');
    await save(h);
    final kitchen = h.db![TeamTables.departments].firstWhere(
      (d) => d['name'] == 'Kitchen',
    )!['id'];
    expect(lastPut(h)['department_id'], kitchen);
    await h.flushTimers();
  });

  testWidgets('TEAM-EMP-022 status: the hint; Terminated asks for its date', (
    tester,
  ) async {
    final h = await openProfile(tester, 'Adham Reda');
    expect(surfaceText(h.t('staff.suspendedCannotClockIn')), findsOneWidget);
    expect(surfaceText('Termination date'), findsNothing);
    await pick(h, 'Status', 'Terminated');
    expect(surfaceText('Termination date'), findsOneWidget);
    await save(h);
    expect(
      surfaceText('A terminated employee needs a termination date'),
      findsOneWidget,
    );
    expect(h.server.callsTo(employeeT, method: 'PUT'), isEmpty);
    await h.tap(field<EmployeeDateField>('Termination date'));
    await h.tap(find.text('Today').hitTestable());
    await save(h);
    final body = lastPut(h);
    expect(body['employment_status'], 'terminated');
    expect(body['termination_date'], '2026-10-08');
    await h.expectToast('Employee saved');
  });

  testWidgets('TEAM-EMP-022 suspended: no termination date sent', (
    tester,
  ) async {
    final h = await openProfile(tester, 'Adham Reda');
    await pick(h, 'Status', 'Suspended');
    await save(h);
    final body = lastPut(h);
    expect(body['employment_status'], 'suspended');
    expect(body['termination_date'], isNull);
    await h.flushTimers();
  });

  testWidgets('TEAM-EMP-023 Paid through Dawam: only for whoever sets pay, '
      'and only then sent', (tester) async {
    var h = await openProfile(tester, 'Adham Reda');
    expect(surfaceText(h.t('dawam.onPayrollHint')), findsOneWidget);
    await h.tap(field<DashCheckboxField>('Paid through Dawam'));
    await save(h);
    expect(lastPut(h)['on_payroll'], false);
    await h.flushTimers();

    h = await openProfile(tester, 'Adham Reda', persona: Persona.manager);
    expect(surfaceText('Paid through Dawam'), findsNothing);
    await save(h);
    expect(lastPut(h).containsKey('on_payroll'), isFalse);
    await h.flushTimers();
  });

  testWidgets('TEAM-EMP-024 salary: the calculator for whoever sets pay; '
      '"Not set" placeholder and hint; a bad figure is refused; empty keeps '
      'it unset', (tester) async {
    final h = await openProfile(tester, 'Nour El-Sayed');
    expect(surfaceText('Base salary (monthly)'), findsOneWidget);
    expect(surfaceText(h.t('dawam.salaryNotSetHint')), findsOneWidget);
    final box = find.descendant(
      of: field<SalaryCalculator>('Base salary (monthly)'),
      matching: find.byType(DashTextInput),
    );
    expect(tester.widget<DashTextInput>(box.first).placeholder, 'Not set');
    await save(h);
    expect(lastPut(h).containsKey('base_salary_piastres'), isFalse);
    await h.flushTimers();
    await h.tap(inPage(find.text('Nour El-Sayed')));
    await type(h, box.first, 'abc');
    await save(h);
    expect(surfaceText('Not an amount'), findsOneWidget);
    await type(h, box.first, '20000');
    await save(h);
    expect(lastPut(h)['base_salary_piastres'], 2000000);
    await h.flushTimers();
  });

  testWidgets('TEAM-EMP-024 refusal: a manager sees no salary box', (
    tester,
  ) async {
    final h = await openProfile(
      tester,
      'Adham Reda',
      persona: Persona.manager,
    );
    expect(surfaceText('Base salary (monthly)'), findsNothing);
    expect(find.byType(SalaryCalculator), findsNothing);
    await save(h);
    expect(lastPut(h).containsKey('base_salary_piastres'), isFalse);
    await h.flushTimers();
  });

  testWidgets('TEAM-EMP-025 gender: Not set / Female / Male and its hint', (
    tester,
  ) async {
    final h = await openProfile(tester, 'Adham Reda');
    expect(surfaceText(h.t('dawam.genderSuggestHint')), findsOneWidget);
    await pick(h, 'Gender', 'Not set');
    await save(h);
    final body = lastPut(h);
    expect(body.containsKey('gender'), isTrue);
    expect(body['gender'], isNull);
    await h.flushTimers();
    await h.tap(inPage(find.text('Adham Reda')));
    await pick(h, 'Gender', 'Female');
    await save(h);
    expect(lastPut(h)['gender'], 'f');
    await h.flushTimers();
  });

  testWidgets('TEAM-EMP-026 paid by: bank asks the IBAN (left to right), '
      'wallet the number; too long says so; cash sends no account', (
    tester,
  ) async {
    final h = await openProfile(tester, 'Adham Reda');
    expect(surfaceText('Account (IBAN)'), findsNothing);
    await pick(h, 'Paid by', 'Bank transfer');
    expect(surfaceText('Account (IBAN)'), findsOneWidget);
    expect(surfaceText(h.t('dawam.payAccountHint')), findsOneWidget);
    final iban = field<DashTextField>('Account (IBAN)');
    expect(tester.widget<DashTextField>(iban).textDirection, TextDirection.ltr);
    await type(h, iban, 'E' * 65);
    await save(h);
    expect(surfaceText('At most 64 characters'), findsOneWidget);
    expect(h.server.callsTo(employeeT, method: 'PUT'), isEmpty);
    await pick(h, 'Paid by', 'Mobile wallet');
    expect(surfaceText('Wallet number'), findsOneWidget);
    await type(h, field<DashTextField>('Wallet number'), '01001234567');
    await save(h);
    expect(lastPut(h)['pay_method'], 'wallet');
    expect(lastPut(h)['pay_account'], '01001234567');
    await h.flushTimers();
    await h.tap(inPage(find.text('Adham Reda')));
    await pick(h, 'Paid by', 'Cash');
    await save(h);
    expect(lastPut(h)['pay_account'], isNull);
    expect(empRow(h.db!, 'adham')['pay_account'], isNull);
    await h.flushTimers();
  });

  testWidgets('TEAM-EMP-027 national ID, emergency contact and phone, notes; '
      'numbers stay left to right in Arabic', (tester) async {
    final h = await openProfile(tester, 'Adham Reda', locale: 'ar');
    final id = field<DashTextField>(h.t('staff.nationalId'));
    expect(tester.widget<DashTextField>(id).textDirection, TextDirection.ltr);
    final ePhone = field<DashTextField>(h.t('staff.emergencyPhone'));
    expect(
      tester.widget<DashTextField>(ePhone).textDirection,
      TextDirection.ltr,
    );
    await type(h, id, '29001011234567');
    await type(h, field<DashTextField>(h.t('staff.emergencyName')), 'Reda');
    await type(h, ePhone, '01001234567');
    await type(h, field<DashTextField>(h.t('staff.notes')), 'Night owl');
    await h.tap(surfaceText(h.t('common.save')));
    final body = lastPut(h);
    expect(body['national_id'], '29001011234567');
    expect(body['emergency_contact_name'], 'Reda');
    expect(body['emergency_contact_phone'], '01001234567');
    expect(body['notes'], 'Night owl');
    await h.flushTimers();
  });

  testWidgets('TEAM-EMP-028 Save: the whole body, toast, the list refetched, '
      'the dialog closed', (tester) async {
    final h = await openProfile(tester, 'Adham Reda');
    final lists = h.server.callsTo(listT, method: 'GET').length;
    await type(h, field<DashTextField>('Name'), '  Adham Reda Hassan ');
    await save(h);
    expect(lastPut(h), {
      'name': 'Adham Reda Hassan',
      'phone': '201111110000',
      'app_access': true,
      'branch_ids': [SeedIds.zamalek],
      'department_id': empRow(h.db!, 'adham')['department_id'],
      'employee_code': 'SB-015',
      'job_title': 'Waiter',
      'hire_date': '2025-06-10',
      'employment_status': 'active',
      'termination_date': null,
      'base_salary_piastres': 750000,
      'on_payroll': true,
      'national_id': null,
      'emergency_contact_name': null,
      'emergency_contact_phone': null,
      'notes': null,
      'gender': 'm',
      'pay_method': 'cash',
      'pay_account': null,
    });
    await h.expectToast('Employee saved');
    expect(find.byType(EmployeeDialog), findsNothing);
    expect(h.server.callsTo(listT, method: 'GET').length, greaterThan(lists));
    expect(inPage(find.text('Adham Reda Hassan')), findsOneWidget);
  });

  testWidgets('TEAM-EMP-028 a new number on a signed-in phone asks first: '
      'Cancel sends nothing, "Save and sign it out" saves', (tester) async {
    final h = await openProfile(tester, 'Mariam Fathy');
    await type(h, field<PhoneField>('WhatsApp number'), '010 9876 5432');
    await save(h);
    expect(confirmText("Sign Mariam Fathy's phone out?"), findsOneWidget);
    expect(
      confirmText(
        h.t('dawam.signOutOnNewNumber', args: {'model': 'Samsung Galaxy A54'}),
      ),
      findsOneWidget,
    );
    await h.tap(confirmText('Cancel'));
    expect(h.server.callsTo(employeeT, method: 'PUT'), isEmpty);
    expect(find.byType(EmployeeDialog), findsOneWidget);
    await save(h);
    await h.tap(confirmText('Save and sign it out'));
    expect(lastPut(h)['phone'], '201098765432');
    await h.expectToast('Employee saved');
    expect(empRow(h.db!, 'mariam')['device_model'], isNull);
  });

  testWidgets('TEAM-EMP-028 app access off on a signed-in phone says the '
      'phone is signed out', (tester) async {
    final h = await openProfile(tester, 'Mariam Fathy');
    await h.tap(field<DashCheckboxField>('May sign in to the staff app'));
    await save(h);
    expect(
      confirmText(
        h.t('dawam.signOutOnAccessOff', args: {'model': 'Samsung Galaxy A54'}),
      ),
      findsOneWidget,
    );
    await h.tap(confirmText('Save and sign it out'));
    expect(lastPut(h)['app_access'], false);
    await h.flushTimers();
  });

  testWidgets('TEAM-EMP-028 a refusal toasts and keeps the dialog; Save waits '
      'while busy', (tester) async {
    final s = employeesServer();
    s.server.fail(
      'PUT',
      employeeT,
      MockResponse.error(
        409,
        'Someone here already signs in with +201110001111.',
        code: 'PHONE_TAKEN',
        vars: {'phone': '+201110001111'},
      ),
    );
    final h = await openProfile(tester, 'Adham Reda', s: s);
    await save(h);
    await h.expectToast(
      h.t('errors.codes.PHONE_TAKEN', args: {'phone': '+201110001111'}),
    );
    expect(find.byType(EmployeeDialog), findsOneWidget);
    final gate = s.server.hold('PUT', employeeT);
    await save(h);
    final button = tester.widget<DashButton>(
      inSurface(find.widgetWithText(DashButton, 'Save')),
    );
    expect(button.loading, isTrue);
    gate.release();
    await h.settle();
    await h.expectToast('Employee saved');
  });

  testWidgets('TEAM-EMP-029 Sign the phone out from the profile: confirm, '
      'DELETE, the dialog stays and follows the refreshed row (no phone, no '
      'button); Cancel closes without saving', (tester) async {
    final h = await openProfile(tester, 'Mariam Fathy');
    expect(
      surfaceText('Signed in on Samsung Galaxy A54 since 02 Sept 2026'),
      findsOneWidget,
    );
    await h.tap(surfaceText('Sign the phone out'));
    await h.tap(confirmText('Sign the phone out'));
    expect(h.server.callsTo(deviceT).single.method, 'DELETE');
    await h.expectToast('Phone signed out');
    expect(find.byType(EmployeeDialog), findsOneWidget);
    expect(textHas('Signed in on Samsung'), findsNothing);
    expect(surfaceText(h.t('dawam.noDevice')), findsOneWidget);
    expect(surfaceText('Sign the phone out'), findsNothing);
    await h.tap(surfaceText('Cancel'));
    expect(find.byType(EmployeeDialog), findsNothing);
    expect(h.server.callsTo(employeeT, method: 'PUT'), isEmpty);
  });

  testWidgets('TEAM-EMP-029 refusal: no "Sign the phone out" without '
      'hr.staff.edit, nor without a phone signed in', (tester) async {
    final s = employeesServer();
    answerAuthz(s.server, const ['hr.staff.read']);
    var h = await openProfile(tester, 'Mariam Fathy', s: s);
    expect(surfaceText('Sign the phone out'), findsNothing);
    await h.tapText('Cancel');
    h = await openProfile(tester, 'Adham Reda');
    expect(surfaceText('Sign the phone out'), findsNothing);
  });
}
