// The Add employee dialog (TEAM-EMP-030…040), its salary calculator
// (TEAM-EMP-070…072) and the phone field (TEAM-ALL-025), driven from the
// Employees header through the real shell on the mock server.
import 'dart:async';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_team/src/employees/add_employee_dialog.dart';
import 'package:dashboard_team/src/employees/employee_dialog.dart';
import 'package:dashboard_team/src/employees/employee_fields.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'employees_support.dart';

Future<DashHarness> openAdd(
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
  await h.tap(pageText(h.t('dawam.addEmployee')));
  expect(find.byType(AddEmployeeDialog), findsOneWidget);
  return h;
}

Finder field<T>(String label) =>
    inSurface(find.widgetWithText(T, label)).first;

Finder addButton() =>
    inSurface(find.widgetWithText(DashButton, 'Add employee'));

bool addEnabled(WidgetTester tester) =>
    tester.widget<DashButton>(addButton()).onPressed != null;

Future<void> kind(DashHarness h, String label) =>
    h.tap(inSurface(find.text(label)).hitTestable());

Future<void> branch(DashHarness h, String name) =>
    h.tap(inSurface(find.widgetWithText(DashCheckChip, name)));

Map<String, Object?> lastPost(DashHarness h) =>
    (h.server.callsTo(listT, method: 'POST').last.body! as Map)
        .cast<String, Object?>();

Finder salaryBox(String label, int i) => find
    .descendant(
      of: field<SalaryCalculator>(label),
      matching: find.byType(DashTextInput),
    )
    .at(i);

String boxText(WidgetTester tester, Finder f) =>
    tester.widget<EditableText>(
      find.descendant(of: f, matching: find.byType(EditableText)),
    ).controller.text;

void main() {
  testWidgets('TEAM-EMP-030 Add employee: title and the kind\'s hint', (
    tester,
  ) async {
    final h = await openAdd(tester);
    expect(surfaceText('Add employee'), findsWidgets);
    expect(surfaceText(h.t('dawam.kindHint_app')), findsOneWidget);
  });

  testWidgets('TEAM-EMP-030/032 Make employee: a preset Madar user, no kind '
      'choice, the user fixed', (tester) async {
    final h = await pumpEmployees(tester);
    final mostafa = mockUuid('user:mostafa-kamal');
    showAddEmployeeDialog(tester.element(page), userId: mostafa);
    await h.settle();
    expect(surfaceText('Make employee'), findsWidgets);
    expect(surfaceText('Kind'), findsNothing);
    expect(surfaceText('Mostafa Kamal · Teller'), findsOneWidget);
    final select = tester.widget<DashSelectField<String>>(
      field<DashSelectField<String>>('Madar user'),
    );
    expect(select.enabled, isFalse);
    await branch(h, 'Heliopolis');
    await h.tap(inSurface(find.widgetWithText(DashButton, 'Make employee')));
    expect(lastPost(h)['user_id'], mostafa);
    await h.expectToast('Employee added.');
  });

  testWidgets('TEAM-EMP-031 kinds: Staff app (default), Records only, Madar '
      'user, each with its hint', (tester) async {
    final h = await openAdd(tester);
    for (final (label, hint) in [
      ('Records only', 'dawam.kindHint_manual'),
      ('Madar user', 'dawam.kindHint_linked'),
      ('Staff app', 'dawam.kindHint_app'),
    ]) {
      await kind(h, label);
      expect(surfaceText(h.t(hint)), findsOneWidget, reason: label);
    }
  });

  testWidgets('TEAM-EMP-032 Madar user: "name · role" from the linkable '
      'users; picking fills the number; required', (tester) async {
    final h = await openAdd(tester);
    await kind(h, 'Madar user');
    expect(h.server.callsTo(linkableT), hasLength(1));
    expect(surfaceText('Name'), findsNothing);
    expect(surfaceText('May sign in to the staff app'), findsOneWidget);
    await h.tap(field<DashSelectField<String>>('Madar user'));
    expect(find.text('Mostafa Kamal · Teller').hitTestable(), findsOneWidget);
    expect(find.text('Nadia Farouk · Waiter').hitTestable(), findsOneWidget);
    await h.tap(find.text('Mostafa Kamal · Teller').hitTestable());
    expect(inSurface(find.text('+201110010101')), findsWidgets);
    await branch(h, 'Heliopolis');
    await h.tap(field<DashCheckboxField>('May sign in to the staff app'));
    await h.tap(addButton());
    final body = lastPost(h);
    expect(body['user_id'], mockUuid('user:mostafa-kamal'));
    expect(body.containsKey('name'), isFalse);
    expect(body['phone'], '201110010101');
    expect(body['app_access'], true);
    await h.expectToast(h.t('dawam.employeeAdded'));
    final row = h.db!['employees'].firstWhere(
      (e) => e['user_id'] == mockUuid('user:mostafa-kamal'),
    )!;
    expect(row['name'], 'Mostafa Kamal');
    expect(row['phone'], '+201110010101');
  });

  testWidgets('TEAM-EMP-032 nobody left to link: "Everyone with a Madar '
      'account is already an employee."; Add waits for a person', (
    tester,
  ) async {
    final h = await openAdd(tester, persona: Persona.dawamOnly);
    await kind(h, 'Madar user');
    expect(surfaceText(h.t('dawam.noLinkable')), findsOneWidget);
    expect(addEnabled(tester), isFalse);
    expect(textHas('pick a person'), findsOneWidget);
  });

  testWidgets('TEAM-EMP-032 while the users load nothing says "Everyone '
      'is already an employee"', (tester) async {
    final s = employeesServer();
    final gate = s.server.hold('GET', linkableT);
    final h = await openAdd(tester, s: s);
    await kind(h, 'Madar user');
    expect(surfaceText(h.t('dawam.noLinkable')), findsNothing);
    gate.release();
    await h.settle();
    expect(surfaceText(h.t('dawam.noLinkable')), findsNothing);
  });

  testWidgets('TEAM-EMP-033 name: required, at most 120', (tester) async {
    final h = await openAdd(tester);
    await h.enterText(field<DashTextField>('Name'), 'x');
    await h.enterText(field<DashTextField>('Name'), ' ');
    expect(surfaceText('A name is needed'), findsOneWidget);
    await h.enterText(field<DashTextField>('Name'), 'x' * 121);
    expect(surfaceText('At most 120 characters'), findsOneWidget);
    expect(addEnabled(tester), isFalse);
  });

  testWidgets('TEAM-EMP-034 number: required for the staff app, optional for '
      'records only; a non-phone is named', (tester) async {
    final h = await openAdd(tester);
    final phone = field<PhoneField>('WhatsApp number');
    await h.enterText(phone, '12');
    expect(surfaceText('"12" isn\'t a phone number'), findsOneWidget);
    await h.enterText(phone, '');
    expect(
      surfaceText('The staff app needs their WhatsApp number'),
      findsOneWidget,
    );
    await kind(h, 'Records only');
    expect(surfaceText('Optional. Only for reaching them.'), findsOneWidget);
    expect(
      surfaceText('The staff app needs their WhatsApp number'),
      findsNothing,
    );
  });

  testWidgets('TEAM-EMP-035 branches: at least one; the only branch ticks '
      'itself', (tester) async {
    var h = await openAdd(tester);
    await branch(h, 'Maadi');
    await branch(h, 'Maadi');
    expect(surfaceText('Pick at least one branch'), findsOneWidget);
    await h.tapText('Cancel');

    h = await openAdd(
      tester,
      edit: (db) => db['branches'].removeWhere(
        (b) => b['org_id'] == SeedIds.sabahOrg && b['id'] != SeedIds.maadi,
      ),
    );
    final chip = tester.widget<DashCheckChip>(
      inSurface(find.widgetWithText(DashCheckChip, 'Maadi')),
    );
    expect(chip.value, isTrue);
    expect(textHas('at least one branch'), findsNothing);
  });

  testWidgets('TEAM-EMP-036 job title, hire date, gender ("Not set" until '
      'picked)', (tester) async {
    final h = await openAdd(tester);
    expect(surfaceText('Not set'), findsOneWidget);
    await h.enterText(field<DashTextField>('Name'), 'Rania Adel');
    await h.enterText(field<PhoneField>('WhatsApp number'), '01001234567');
    await branch(h, 'Zamalek');
    await h.enterText(field<DashTextField>('Job title'), 'Pastry chef');
    await h.tap(field<EmployeeDateField>('Hire date'));
    await h.tap(find.text('20').hitTestable().last);
    await h.tap(field<DashSelectField<String>>('Gender'));
    await h.tap(find.text('Female').hitTestable().last);
    await h.tap(addButton());
    final body = lastPost(h);
    expect(body['job_title'], 'Pastry chef');
    expect(body['hire_date'], '2026-10-20');
    expect(body['gender'], 'f');
    await h.flushTimers();
  });

  testWidgets('TEAM-EMP-037 salary: the calculator for whoever sets pay, its '
      'empty hint; a bad figure is refused', (tester) async {
    final h = await openAdd(tester);
    expect(surfaceText('Monthly salary (EGP)'), findsOneWidget);
    expect(surfaceText(h.t('dawam.salaryEmptyHint')), findsOneWidget);
    await h.enterText(salaryBox('Monthly salary (EGP)', 0), 'abc');
    expect(surfaceText('Not an amount'), findsOneWidget);
    expect(surfaceText(h.t('dawam.salaryEmptyHint')), findsNothing);
  });

  testWidgets('TEAM-EMP-037 refusal: a manager reads the "Not set" note and '
      'sends no salary', (tester) async {
    final h = await openAdd(tester, persona: Persona.manager);
    expect(surfaceText('Monthly salary (EGP)'), findsNothing);
    expect(surfaceText(h.t('dawam.salaryNoAccessHint')), findsOneWidget);
    await h.enterText(field<DashTextField>('Name'), 'Rania Adel');
    await h.enterText(field<PhoneField>('WhatsApp number'), '01001234567');
    await branch(h, 'Zamalek');
    await h.tap(addButton());
    expect(lastPost(h).containsKey('base_salary_piastres'), isFalse);
    await h.flushTimers();
  });

  testWidgets('TEAM-EMP-038 what is missing, in the form\'s words; Add '
      'disabled until valid', (tester) async {
    final h = await openAdd(tester);
    expect(
      surfaceText(
        'To add them: a name, their WhatsApp number, at least one branch.',
      ),
      findsOneWidget,
    );
    expect(addEnabled(tester), isFalse);
    await h.enterText(field<DashTextField>('Name'), 'Rania Adel');
    await h.enterText(field<PhoneField>('WhatsApp number'), '0100');
    expect(
      textHas('a phone number that works, at least one branch'),
      findsOneWidget,
    );
    await h.enterText(field<PhoneField>('WhatsApp number'), '01001234567');
    await branch(h, 'Zamalek');
    expect(textHas('To add them'), findsNothing);
    expect(addEnabled(tester), isTrue);
  });

  testWidgets('TEAM-EMP-039 Add: the body, the staff-app toast, everything '
      'under /staff refetched, closed', (tester) async {
    final h = await openAdd(tester);
    final lists = h.server.callsTo(listT, method: 'GET').length;
    final departments = h.server.callsTo(departmentsT).length;
    await h.enterText(field<DashTextField>('Name'), '  Rania Adel ');
    await h.enterText(field<PhoneField>('WhatsApp number'), '010 0123 4567');
    await branch(h, 'Zamalek');
    await branch(h, 'Maadi');
    await h.enterText(salaryBox('Monthly salary (EGP)', 0), '9,000');
    await h.tap(addButton());
    expect(lastPost(h), {
      'name': 'Rania Adel',
      'phone': '201001234567',
      'app_access': true,
      'branch_ids': [SeedIds.zamalek, SeedIds.maadi],
      'job_title': null,
      'hire_date': null,
      'gender': null,
      'base_salary_piastres': 900000,
    });
    await h.expectToast(h.t('dawam.employeeAdded'));
    expect(find.byType(AddEmployeeDialog), findsNothing);
    expect(h.server.callsTo(listT, method: 'GET').length, greaterThan(lists));
    expect(h.server.callsTo(departmentsT).length, greaterThan(departments));
    final row = h.db!['employees'].firstWhere((e) => e['name'] == 'Rania Adel')!;
    expect(row['hire_date'], '2026-10-08');
    expect(row['base_salary_piastres'], 900000);
  });

  testWidgets('TEAM-ALL-026 an add invalidates every key under "/staff" by '
      'plain prefix (staff-drinks reads under /staff-pool too)', (
    tester,
  ) async {
    final h = await openAdd(tester);
    final seen = <String>[];
    final sub = h.container
        .read(realtimeBusProvider)
        .invalidations
        .listen((l) => seen.add(l.join()));
    await h.enterText(field<DashTextField>('Name'), 'Rania Adel');
    await h.enterText(field<PhoneField>('WhatsApp number'), '01001234567');
    await branch(h, 'Zamalek');
    await h.tap(addButton());
    await h.expectToast(h.t('dawam.employeeAdded'));
    unawaited(sub.cancel());
    expect(seen, contains('/staff'));
    expect(pathInvalidatedBy('/staff-pool/drinks', '/staff'), isTrue);
  });

  testWidgets('TEAM-EMP-039 records only: no app, "Employee added."', (
    tester,
  ) async {
    final h = await openAdd(tester);
    await kind(h, 'Records only');
    await h.enterText(field<DashTextField>('Name'), 'Saeed Hamdy');
    await branch(h, 'Maadi');
    await h.tap(addButton());
    expect(lastPost(h)['app_access'], false);
    expect(lastPost(h)['phone'], isNull);
    await h.expectToast('Employee added.');
  });

  testWidgets('TEAM-EMP-039/TEAM-ALL-014 a number already in use: the '
      'refusal in the person\'s language, the dialog stays', (tester) async {
    final h = await openAdd(tester, locale: 'ar');
    await h.enterText(field<DashTextField>(h.t('staff.name')), 'رانيا عادل');
    await h.enterText(
      field<PhoneField>(h.t('dawam.whatsapp')),
      '01110001111',
    );
    await branch(h, 'Zamalek');
    await h.tap(inSurface(find.widgetWithText(DashButton, h.t('dawam.addEmployee'))));
    expect(h.server.callsTo(listT, method: 'POST').last.status, 409);
    await h.expectToast(
      h.t('errors.codes.PHONE_TAKEN', args: {'phone': '+201110001111'}),
    );
    expect(find.byType(AddEmployeeDialog), findsOneWidget);
  });

  testWidgets('TEAM-EMP-040 Cancel closes, nothing sent', (tester) async {
    final h = await openAdd(tester);
    await h.enterText(field<DashTextField>('Name'), 'Rania Adel');
    await h.tap(surfaceText('Cancel'));
    expect(find.byType(AddEmployeeDialog), findsNothing);
    expect(h.server.callsTo(listT, method: 'POST'), isEmpty);
  });

  testWidgets('TEAM-EMP-070/071 calculator: monthly fills the day and hour '
      'rates from the rules; a day rate fills the monthly; Arabic digits', (
    tester,
  ) async {
    final h = await openAdd(tester);
    const label = 'Monthly salary (EGP)';
    expect(
      surfaceText('From the rules: 26 working days of 12 h a month.'),
      findsOneWidget,
    );
    await h.enterText(salaryBox(label, 0), '9000');
    expect(boxText(tester, salaryBox(label, 1)), '346.15');
    expect(boxText(tester, salaryBox(label, 2)), '28.85');
    await h.enterText(salaryBox(label, 1), '400');
    expect(boxText(tester, salaryBox(label, 0)), '10400');
    expect(boxText(tester, salaryBox(label, 2)), '33.33');
    await h.enterText(salaryBox(label, 2), '50');
    expect(boxText(tester, salaryBox(label, 0)), '15600');
    await h.enterText(salaryBox(label, 0), '٩٬٠٠٠٫٥٠');
    expect(boxText(tester, salaryBox(label, 1)), '346.17');
    await h.enterText(field<DashTextField>('Name'), 'Rania Adel');
    await h.enterText(field<PhoneField>('WhatsApp number'), '01001234567');
    await branch(h, 'Zamalek');
    await h.tap(addButton());
    expect(lastPost(h)['base_salary_piastres'], 900050);
    await h.flushTimers();
  });

  testWidgets('TEAM-EMP-072/TEAM-ALL-012 first pay: pro rata from today (the '
      'zone\'s), then from the hire date', (tester) async {
    final h = await openAdd(tester);
    const label = 'Monthly salary (EGP)';
    await h.enterText(salaryBox(label, 0), '3100');
    expect(
      surfaceText('First pay (from 08 Oct 2026 to 31 Oct 2026): EGP 2,400.00'),
      findsOneWidget,
    );
    await h.tap(field<EmployeeDateField>('Hire date'));
    await h.tap(find.text('16').hitTestable().last);
    expect(
      surfaceText('First pay (from 16 Oct 2026 to 31 Oct 2026): EGP 1,600.00'),
      findsOneWidget,
    );
  });

  testWidgets('TEAM-EMP-072 the profile names the first pay only while that '
      'period is open', (tester) async {
    var h = await pumpEmployees(
      tester,
      edit: (db) => empRow(db, 'adham')['hire_date'] = '2026-10-01',
    );
    await h.tap(inPage(find.text('Adham Reda')));
    expect(find.byType(EmployeeDialog), findsOneWidget);
    expect(
      surfaceText('First pay (from 01 Oct 2026 to 31 Oct 2026): EGP 7,500.00'),
      findsOneWidget,
    );
    await h.tapText('Cancel');
    h = await pumpEmployees(tester);
    await h.tap(inPage(find.text('Adham Reda')));
    expect(textHas('First pay'), findsNothing);
  });

  testWidgets('TEAM-ALL-025 phone field: a problem only after leaving the '
      'field; a good number reads back with a check', (tester) async {
    final h = await openAdd(tester);
    final phone = field<PhoneField>('WhatsApp number');
    final input = tester.widget<DashTextInput>(
      find.descendant(of: phone, matching: find.byType(DashTextInput)),
    );
    expect(input.placeholder, ltr('010 1234 5678'));
    await h.enterText(phone, '01001234567');
    expect(inSurface(find.text('+20 100 123 4567')), findsOneWidget);
    expect(
      find.descendant(of: phone, matching: find.byType(DashIcon)),
      findsOneWidget,
    );
  });

  testWidgets('TEAM-ALL-025 phone field words: too short, too long, a '
      'prefix, not a phone, only after the field is left; the form\'s error '
      'wins', (tester) async {
    final h = await pumpEmployees(tester);
    await h.tap(inPage(find.text('Adham Reda')));
    final phone = field<PhoneField>('WhatsApp number');
    final name = field<DashTextField>('Name');
    for (final (typed, key) in [
      ('0100123', 'inputs.phoneShort'),
      ('010012345678', 'inputs.phoneLong'),
      ('013001', 'inputs.phonePrefix'),
      ('call me', 'inputs.phoneBad'),
    ]) {
      // A good number first: it clears what the field said.
      await h.enterText(phone, '01001234567');
      await h.enterText(phone, typed);
      expect(surfaceText(h.t(key)), findsNothing, reason: 'while typing');
      await h.tap(name); // leave the field
      expect(surfaceText(h.t(key)), findsOneWidget, reason: typed);
    }
    await h.tap(surfaceText('Save'));
    expect(surfaceText('Not a phone number'), findsOneWidget);
    expect(surfaceText(h.t('inputs.phoneBad')), findsNothing);
  });
}
