// Shared set-up for the Employees unit's tests: the real app shell with the
// team area on a seeded mock server, edited per test before pumping.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_team/dashboard_team.dart';
import 'package:dashboard_team/src/employees/employees_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const String employeesPath = '/staff/employees';
const String listT = '/staff/employees';
const String employeeT = '/staff/employees/{employee_id}';
const String deviceT = '/staff/employees/{employee_id}/device';
const String linkableT = '/staff/employees/linkable';
const String departmentsT = '/staff/departments';
const String departmentT = '/staff/departments/{id}';

typedef Srv = ({MockServer server, MockDb db});

/// A seeded server with the core's and the team area's handlers.
Srv employeesServer({
  Persona persona = Persona.owner,
  void Function(MockDb db)? edit,
}) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  teamArea.registerMocks!(server, db);
  edit?.call(db);
  return (server: server, db: db);
}

/// Opens Employees as [persona] on [s] (a fresh seeded server by default).
Future<DashHarness> pumpEmployees(
  WidgetTester tester, {
  Persona persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  Srv? s,
  void Function(MockDb db)? edit,
}) {
  final srv = s ?? employeesServer(persona: persona, edit: edit);
  return DashHarness.pump(
    tester,
    areas: const [teamArea],
    path: employeesPath,
    persona: persona,
    size: size,
    locale: locale,
    dark: dark,
    server: srv.server,
    db: srv.db,
    shotArea: 'team',
  );
}

/// Answers `/authz/me` with only [caps] (held at every branch unless
/// [everywhere] says otherwise).
void answerAuthz(
  MockServer server,
  List<String> caps, {
  List<String>? everywhere,
  bool owner = false,
}) {
  server.on('GET', '/authz/me', (req) {
    final sorted = [...caps]..sort();
    return MockResponse.ok({
      'user_id': req.persona.userId,
      'branch_id': req.q('branch_id'),
      'capabilities': sorted,
      'everywhere': everywhere ?? sorted,
      'ask_manager': <String>[],
      'limits': <String, Object?>{},
      'owner': owner,
      'platform': false,
      'role_kinds': req.persona.roleKinds,
      'epoch': 1,
      'spec_version': 2,
    });
  });
}

// ── Seed helpers ───────────────────────────────────────────────────────────

String emp(String key) => SeedIds.employee(key);

MockRow empRow(MockDb db, String key) => db['employees'].find(emp(key))!;

/// Sabah's people as GET /staff/employees lists them (by name).
List<MockRow> sabahPeople(MockDb db) =>
    db['employees'].where((e) => e['org_id'] == SeedIds.sabahOrg)..sort(
      (a, b) =>
          '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase()),
    );

/// Nobody at Sabah at all.
void noPeople(MockDb db) =>
    db['employees'].removeWhere((e) => e['org_id'] == SeedIds.sabahOrg);

// ── Finders ────────────────────────────────────────────────────────────────

final Finder page = find.byType(EmployeesPage);

Finder inPage(Finder f) => find.descendant(of: page, matching: f);

Finder pageText(String s) => inPage(find.text(s));

/// The open dialog / sheet (the last `DashSurface`).
Finder surface() => find.byType(DashSurface).last;

Finder inSurface(Finder f) => find.descendant(of: surface(), matching: f);

Finder surfaceText(String s) => inSurface(find.text(s));

/// The confirm card.
Finder confirmText(String s) => find.descendant(
  of: find.byType(DashConfirmDialog).last,
  matching: find.text(s),
);

/// What a person reads for the server's refusal [r]: the app's words for it
/// (`h.refusalWords`), without the kind the server writes before its
/// sentence ("Not found: …"), as the web's `getErrorMessage` strips it.
String refusal(DashHarness h, MockResponse r) => h
    .refusalWords(r)
    .replaceFirst(
      RegExp(
        '^(?:Unauthorized|Forbidden|Not found|Bad request|Conflict|'
        'Service unavailable|Database error): ',
      ),
      '',
    );

/// Text containing [s] (rich text too).
Finder textHas(String s) => find.textContaining(s, findRichText: true);

/// Shoots the page top to bottom: `<name>-1`, `<name>-2`, …
Future<void> shootPage(DashHarness h, String name) async {
  final scroll = find
      .descendant(of: page, matching: find.byType(Scrollable))
      .evaluate()
      .map((e) => (e as StatefulElement).state as ScrollableState)
      .firstWhere((s) => s.position.axis == Axis.vertical);
  final position = scroll.position;
  var i = 1;
  var y = 0.0;
  while (true) {
    position.jumpTo(y);
    await h.settle(rounds: 2);
    await h.shot('employees/$name-$i');
    if (y >= position.maxScrollExtent) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
    i++;
  }
}
