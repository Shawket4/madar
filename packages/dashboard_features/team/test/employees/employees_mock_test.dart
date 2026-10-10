// The Employees unit's mock handlers against the backend's rules
// (MadarRust `src/staff/directory.rs`, `dawam/presence.rs`): gates, scope,
// salary redaction, pay written only with the right everywhere, the
// refusals and the phone sign-out rules, with hand-computed figures.
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_team/src/area_seed.dart';
import 'package:flutter_test/flutter_test.dart';

import 'employees_support.dart';

Future<ApiException> refused(Future<Object?> f) async {
  try {
    await f;
  } on ApiException catch (e) {
    return e;
  }
  fail('expected a refusal');
}

void main() {
  late MockServer server;
  late MockDb db;
  late StaffApi api;

  setUp(() {
    final s = employeesServer();
    server = s.server;
    db = s.db;
    api = DashboardApi(server).staff;
  });

  test('the list: the org, sorted by name, kind derived, filters', () async {
    final all = await api.listEmployees();
    expect(all, hasLength(16));
    expect(all.first.name, 'Adham Reda');
    expect(all.every((e) => e.kind == 'linked'), isTrue);
    final kitchen =
        db[TeamTables.departments].firstWhere(
              (d) => d['org_id'] == SeedIds.sabahOrg && d['name'] == 'Kitchen',
            )!['id']!
            as String;
    final k = await api.listEmployees(departmentId: kitchen);
    expect([for (final e in k) e.name], ['Hassan Ibrahim']);
    final e = await refused(api.listEmployees(employmentStatus: 'gone'));
    expect(e.status, 400);
    server.persona = Persona.dawamOnly;
    final nakhla = await api.listEmployees();
    expect({for (final e in nakhla) e.kind}, {'linked', 'app', 'manual'});
  });

  test('salary redaction: the owner reads pay; a manager reads only their '
      'branch\'s people, salaries hidden, "salary set" kept', () async {
    final owner = await api.listEmployees();
    expect(
      owner.firstWhere((e) => e.name == 'Adham Reda').baseSalaryPiastres,
      750000,
    );
    final nour = owner.firstWhere((e) => e.name == 'Nour El-Sayed');
    expect((nour.baseSalaryPiastres, nour.salarySet), (null, false));
    server.persona = Persona.manager;
    final mine = await api.listEmployees();
    expect(
      [for (final e in mine) e.name],
      [
        'Adham Reda',
        'Hassan Ibrahim',
        'Karim Adel',
        'Laila Ehab',
        'Mariam Fathy',
        'Nour El-Sayed',
        'Youssef Samir',
      ],
    );
    final adham = mine.first;
    expect((adham.baseSalaryPiastres, adham.salarySet), (null, true));
    server.persona = Persona.limited;
    expect((await refused(api.listEmployees())).status, 403);
  });

  test('create: needs a branch, a name, a number for the app; 409 for a '
      'number in use; pay only from the owner; hire date today', () async {
    Future<Employee> add(Map<String, Object?> b) =>
        api.createEmployee(body: CreateEmployeeRequest.fromJson(b));
    expect(
      (await refused(add({'name': 'A', 'branch_ids': <String>[]}))).message,
      'Bad request: Pick the branch they work at',
    );
    expect(
      (await refused(
        add({
          'branch_ids': [SeedIds.maadi],
        }),
      )).message,
      'Bad request: name is required',
    );
    expect(
      (await refused(
        add({
          'name': 'A',
          'app_access': true,
          'branch_ids': [SeedIds.maadi],
        }),
      )).message,
      'Bad request: The staff app needs their WhatsApp number.',
    );
    final taken = await refused(
      add({
        'name': 'A',
        'phone': '01110001111',
        'branch_ids': [SeedIds.maadi],
      }),
    );
    expect((taken.status, taken.code), (409, 'PHONE_TAKEN'));
    final e = await add({
      'name': 'Rania Adel',
      'phone': '01001234567',
      'branch_ids': [SeedIds.maadi],
      'base_salary_piastres': 900000,
    });
    expect(e.kind, 'app');
    expect(e.phone, '+201001234567');
    expect(e.hireDate, '2026-10-08');
    expect(e.baseSalaryPiastres, 900000);

    server.persona = Persona.manager;
    final away = await refused(
      add({
        'name': 'B',
        'branch_ids': [SeedIds.maadi],
      }),
    );
    expect(away.status, 403);
    final m = await add({
      'name': 'Sameh Fouad',
      'branch_ids': [SeedIds.zamalek],
      'base_salary_piastres': 900000,
    });
    expect(m.kind, 'manual');
    expect(db['employees'].find(m.id)!['base_salary_piastres'], isNull);
    expect(m.salarySet, isFalse);
  });

  test('linking a user: the account\'s name and number; twice is a 409; '
      'the linkable list shrinks', () async {
    final before = await api.linkableUsers();
    expect([for (final u in before) u.name], ['Mostafa Kamal', 'Nadia Farouk']);
    final id = mockUuid('user:mostafa-kamal');
    final e = await api.createEmployee(
      body: CreateEmployeeRequest(userId: id, branchIds: [SeedIds.heliopolis]),
    );
    expect(
      (e.name, e.phone, e.kind, e.role, e.appAccess),
      ('Mostafa Kamal', '+201110010101', 'linked', 'teller', true),
    );
    final again = await refused(
      api.createEmployee(
        body: CreateEmployeeRequest(
          userId: id,
          branchIds: [SeedIds.heliopolis],
        ),
      ),
    );
    expect((again.status, again.code), (409, 'ALREADY_EMPLOYEE'));
    expect(
      [for (final u in await api.linkableUsers()) u.name],
      ['Nadia Farouk'],
    );
    server.persona = Persona.manager; // Zamalek's users only
    expect(
      [for (final u in await api.linkableUsers()) u.name],
      ['Nadia Farouk'],
    );
  });

  test('put: termination date rules; a new number or app off signs the '
      'phone out; a manager\'s salary is ignored', () async {
    final mariam = emp('mariam');
    Future<Employee> put(Map<String, Object?> b) => api.putEmployee(
      employeeId: mariam,
      body: PutEmployeeRequest.fromJson(b),
    );
    expect(
      (await refused(put({'employment_status': 'terminated'}))).message,
      'Bad request: A terminated employee needs a termination date',
    );
    expect(
      (await refused(put({'termination_date': '2026-10-08'}))).status,
      400,
    );
    var e = await put({'name': 'Mariam Fathy', 'job_title': 'Head barista'});
    expect(e.deviceModel, 'Samsung Galaxy A54', reason: 'nothing changed');
    expect(e.jobTitle, 'Head barista');
    e = await put({'phone': '01009876543'});
    expect(e.phone, '+201009876543');
    expect(e.deviceModel, isNull);
    e = await put({
      'base_salary_piastres': 1000000,
      'pay_method': 'bank',
      'pay_account': 'EG12',
    });
    expect((e.baseSalaryPiastres, e.payAccount), (1000000, 'EG12'));
    e = await put({'pay_method': 'cash', 'pay_account': 'EG12'});
    expect(e.payAccount, isNull);

    server.persona = Persona.manager;
    e = await put({'base_salary_piastres': 5, 'on_payroll': false});
    expect(db['employees'].find(mariam)!['base_salary_piastres'], 1000000);
    expect(db['employees'].find(mariam)!['on_payroll'], isTrue);
    expect(
      (await refused(
        api.putEmployee(
          employeeId: emp('hana'), // Maadi: not theirs
          body: const PutEmployeeRequest(name: 'Hana'),
        ),
      )).status,
      403,
    );
  });

  test('end employment and sign a phone out: records kept, today, the '
      'phone gone; a manager may not end', () async {
    await api.deleteEmployee(employeeId: emp('ali'));
    final ali = db['employees'].find(emp('ali'))!;
    expect(ali['employment_status'], 'terminated');
    expect(ali['termination_date'], '2026-10-08');
    expect((ali['app_access'], ali['device_model']), (false, null));
    await api.revokeDevice(employeeId: emp('mariam'));
    expect(db['employees'].find(emp('mariam'))!['device_model'], isNull);
    server.persona = Persona.manager;
    expect(
      (await refused(api.deleteEmployee(employeeId: emp('adham')))).status,
      403,
    );
    expect(
      (await refused(api.revokeDevice(employeeId: emp('nobody')))).status,
      404,
    );
  });

  test('departments: live counts (not terminated), org-wide add and delete, '
      'a staffed one refused with its count', () async {
    final list = await api.listDepartments();
    expect(
      {for (final d in list) d.name: d.employeeCount},
      {'Bar': 5, 'Front of house': 5, 'Kitchen': 1, 'Management': 4},
    );
    final bar = list.firstWhere((d) => d.name == 'Bar');
    final e = await refused(api.deleteDepartment(id: bar.id));
    expect(
      e.message,
      'Bad request: 5 employee(s) are still in this department — move them '
      'first',
    );
    final made = await api.createDepartment(
      body: const UpsertDepartmentRequest(name: '  Bakery '),
    );
    expect((made.name, made.employeeCount), ('Bakery', 0));
    await api.deleteDepartment(id: made.id);
    expect(
      (await api.listDepartments()).map((d) => d.name),
      isNot(contains('Bakery')),
    );
    expect(
      (await refused(
        api.createDepartment(body: const UpsertDepartmentRequest(name: ' ')),
      )).status,
      400,
    );
    server.persona = Persona.manager;
    expect(
      (await refused(
        api.createDepartment(body: const UpsertDepartmentRequest(name: 'X')),
      )).status,
      403,
    );
  });
}
