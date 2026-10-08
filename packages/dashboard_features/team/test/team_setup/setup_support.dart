// Shared set-up for the Set-up page's tests: the real app shell with the
// team area on a seeded mock server, the checklist's data shaped per test,
// and the few backend answers another unit owns (registered only while that
// unit has not landed its own handler).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_team/dashboard_team.dart';
import 'package:dashboard_team/src/team_setup/geo.dart';
import 'package:dashboard_team/src/team_setup/setup_location.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const String setupPath = '/staff/setup';

/// Sabah's branches by name (GET /branches sorts by name).
const String heliopolis = SeedIds.heliopolis;
const String maadi = SeedIds.maadi;
const String newCairo = SeedIds.newCairo;
const String zamalek = SeedIds.zamalek;

/// A seeded server with the core's and the team area's handlers.
({MockServer server, MockDb db}) setupServer({
  Persona persona = Persona.owner,
  void Function(MockDb db)? edit,
}) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  teamArea.registerMocks!(server, db);
  registerSetupFallbacks(server, db);
  edit?.call(db);
  return (server: server, db: db);
}

/// Opens Set-up as [persona] on [server] (a fresh seeded one by default).
Future<DashHarness> pumpSetup(
  WidgetTester tester, {
  Persona persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  ({MockServer server, MockDb db})? s,
  void Function(MockDb db)? edit,
  String path = setupPath,
}) {
  final srv = s ?? setupServer(persona: persona, edit: edit);
  return DashHarness.pump(
    tester,
    areas: const [teamArea],
    path: path,
    persona: persona,
    size: size,
    locale: locale,
    dark: dark,
    server: srv.server,
    db: srv.db,
    shotArea: 'team',
  );
}

// ── Data shapes ────────────────────────────────────────────────────────────

/// Takes the pin off [ids] the way the web's test does: no radius (Maadi),
/// or no coordinates at all.
void unpin(MockDb db, String id, {bool keepCoordinates = false}) {
  db['branches'].update(id, {
    if (!keepCoordinates) ...{'latitude': null, 'longitude': null},
    'geo_radius_meters': null,
  });
}

/// Sabah's active people (ordered by name).
List<MockRow> activeStaff(MockDb db) => db['employees'].query(
  filters: {'org_id': SeedIds.sabahOrg, 'employment_status': 'active'},
  sort: 'name',
);

/// Nobody active at Sabah.
void noActivePeople(MockDb db) {
  for (final e in activeStaff(db)) {
    e['employment_status'] = 'terminated';
  }
}

/// No active work shift at Sabah.
void noActiveShifts(MockDb db) {
  for (final s in db['work_shifts'].where(
    (r) => r['org_id'] == SeedIds.sabahOrg,
  )) {
    s['is_active'] = false;
  }
}

/// Sabah never saved its rules and stores no ladder: the step starts from
/// the server's suggested one.
void rulesNeverSaved(MockDb db) {
  final row = db['attendance_settings'].firstWhere(
    (r) => r['org_id'] == SeedIds.sabahOrg,
  )!;
  row['rules_saved_at'] = null;
  row['late_deduction_tiers'] = <Object?>[];
  row['overtime_mode'] = 'off';
}

// ── Permissions ────────────────────────────────────────────────────────────

/// Answers `/authz/me` with only [caps] (held at every branch unless
/// [everywhere] says otherwise): a person the personas do not cover, e.g. an
/// owner who gave the branch right away.
void answerAuthz(
  MockServer server,
  List<String> caps, {
  List<String>? everywhere,
  bool owner = true,
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

// ── Other units' endpoints, until they land ────────────────────────────────

/// Registers a backend-shaped answer for each route the page's dialogs call
/// that no unit answers yet (a unit's own handler always wins).
void registerSetupFallbacks(MockServer server, MockDb db) {
  if (!server.handles('POST', '/staff/employees')) {
    server.on('POST', '/staff/employees', (req) {
      req.requireCap('hr.staff.create');
      final b = req.json;
      final name = (b['name'] as String?)?.trim() ?? '';
      if (b['user_id'] == null && name.isEmpty) {
        req.unprocessable('A name is needed', code: 'NAME_REQUIRED');
      }
      final phone = b['phone'] as String?;
      if (phone != null &&
          db['employees'].firstWhere(
                (e) => e['org_id'] == req.orgId && e['phone'] == phone,
              ) !=
              null) {
        req.conflict(
          'That phone number is already used by another employee',
          code: 'PHONE_TAKEN',
        );
      }
      final row = db['employees'].insert({
        'org_id': req.orgId,
        'name': name,
        'phone': phone,
        'app_access': b['app_access'] ?? false,
        'branch_ids': b['branch_ids'] ?? <String>[],
        'job_title': b['job_title'],
        'hire_date': b['hire_date'],
        'gender': b['gender'],
        'employment_status': 'active',
        'kind': b['user_id'] != null
            ? 'linked'
            : (b['app_access'] == true ? 'app' : 'manual'),
        'salary_set': b['base_salary_piastres'] != null,
        'base_salary_piastres': b['base_salary_piastres'],
        'on_payroll': true,
        'pay_method': 'cash',
        'advance_within_cap': true,
        'cant_work_days': <int>[],
      });
      return MockResponse.created(row);
    });
  }
  if (!server.handles('GET', '/staff/employees/linkable')) {
    server.on('GET', '/staff/employees/linkable', (req) {
      req.requireCap('hr.staff.create');
      return MockResponse.ok(<Object?>[]);
    });
  }
  if (!server.handles('POST', '/staff/work-shifts')) {
    server.on('POST', '/staff/work-shifts', (req) {
      req.requireCap('hr.schedule.create');
      final b = req.json;
      final row = db['work_shifts'].insert({
        'org_id': req.orgId,
        'branch_id': b['branch_id'],
        'name': b['name'],
        'start_time': b['start_time'],
        'end_time': b['end_time'],
        'crosses_midnight': false,
        'break_minutes': b['break_minutes'] ?? 0,
        'paid_break': b['paid_break'] ?? true,
        'grace_minutes': b['grace_minutes'] ?? 15,
        'checkin_window_minutes': b['checkin_window_minutes'] ?? 120,
        'overtime_threshold_minutes': b['overtime_threshold_minutes'] ?? 15,
        'overtime_multiplier': b['overtime_multiplier'] ?? 1.5,
        'valid_days': b['valid_days'] ?? [0, 1, 2, 3, 4, 5, 6],
        'is_active': b['is_active'] ?? true,
      });
      return MockResponse.created(row);
    });
  }
}

// ── Location ───────────────────────────────────────────────────────────────

/// A device location that answers what the test says.
class FakeLocator implements SetupLocator {
  FakeLocator(this.answer);

  LocationResult answer;
  int calls = 0;
  Duration? lastTimeout;

  @override
  Future<LocationResult> locate({Duration timeout = locateTimeout}) async {
    calls++;
    lastTimeout = timeout;
    return answer;
  }
}

/// Installs [locator] as the device's location reader.
void useLocator(DashHarness h, SetupLocator locator) =>
    h.container.read(setupLocatorProvider.notifier).use(locator);

/// A good fix at [at] with [accuracy] metres.
LocationResult fixAt(double lat, double lng, double accuracy) =>
    LocationResult.fix(LatLng(lat, lng), accuracy);

// ── Finders ────────────────────────────────────────────────────────────────

Finder byKey(String key) => find.byKey(ValueKey(key));

/// Text inside the widget keyed [key].
Finder textIn(String key, String text) =>
    find.descendant(of: byKey(key), matching: find.text(text));

/// Text containing [s] (rich text too).
Finder textHas(String s) => find.textContaining(s, findRichText: true);
