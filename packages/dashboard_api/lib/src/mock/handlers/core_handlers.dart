/// The handlers the app shell needs at start (read from the web's
/// `auth.store.ts`, `lib/auth-guard.ts`, `data/scope/**`, `data/authz`,
/// `hooks/use-org-modules.ts`, `components/layout/**` and the `/_app` route):
/// sign-in, the current user, `/authz/me`, the org with its modules and
/// onboarding status, the org list for platform admins, branches, the public
/// brand, timezones, the realtime stream, and the Dawam set-up progress reads
/// (employees, work shifts, attendance settings) the sidebar asks for.
///
/// Register these first; an area that needs richer behaviour for one of these
/// routes registers it again (the later registration wins).
library;

import '../../generated/models.dart';
import '../mock_db.dart';
import '../mock_server.dart';
import '../personas.dart';
import '../seed.dart';

/// The `/timezones` list.
const List<String> mockTimezones = [
  'Africa/Cairo',
  'Asia/Dubai',
  'Asia/Kuwait',
  'Asia/Qatar',
  'Asia/Riyadh',
  'Europe/Istanbul',
  'Europe/London',
  'UTC',
];

/// The realtime channel a branch's stream listens on: publish a frame with
/// `server.publish(realtimeChannel(branchId), jsonEncode({...}))`.
String realtimeChannel(String? branchId) => 'realtime:${branchId ?? 'org'}';

/// Registers the shell's routes on [server] over [db] (a [MockDb.seeded]).
void registerCoreMocks(MockServer server, MockDb db) {
  // ── auth ──────────────────────────────────────────────────────────────
  server.on('POST', '/auth/login', (req) {
    final body = req.bodyAs(LoginRequest.fromJson);
    final persona = body.email == null ? null : Persona.byEmail(body.email!);
    if (persona == null || body.password != Persona.password) {
      return MockResponse.unauthorized('Invalid credentials');
    }
    server.persona = persona;
    final user = _user(db, persona);
    return MockResponse.ok(
      LoginResponse(
        token: persona.token,
        user: user,
        currencyCode: 'EGP',
        taxRate: MockSeed.taxRate,
        taxPolicy: _taxPolicy,
        requireTableForOrders: false,
      ),
    );
  });

  server.on(
    'GET',
    '/auth/me',
    (req) => MockResponse.ok(
      MeResponse(
        user: _user(db, req.persona),
        currencyCode: 'EGP',
        taxRate: MockSeed.taxRate,
        taxPolicy: _taxPolicy,
        requireTableForOrders: false,
      ),
    ),
  );

  server.on('GET', '/authz/me', (req) {
    final p = req.persona;
    final caps = p.capabilities.toList()..sort();
    return MockResponse.ok(
      MyAuthz(
        userId: p.userId,
        branchId: req.q('branch_id'),
        capabilities: caps,
        everywhere: p.branchIds == null ? caps : const [],
        askManager: const [],
        limits: const {},
        owner: p.isOwner,
        platform: p.isPlatform,
        roleKinds: p.roleKinds,
        epoch: 1,
        specVersion: 2,
      ),
    );
  });

  // ── orgs ──────────────────────────────────────────────────────────────
  server.on('GET', '/orgs', (req) {
    req.requireCap('org.settings.read');
    req.requirePlatform();
    return MockResponse.ok(db['orgs'].query(sort: 'name'));
  });

  server.on('GET', '/orgs/{id}', (req) {
    req.requireCap('org.settings.read');
    final id = req.param('id');
    req.requireSameOrg(id);
    return MockResponse.ok(db['orgs'].get(id, what: 'Organization not found'));
  });

  server.on('GET', '/orgs/{id}/modules', (req) {
    final id = req.param('id');
    req.requireSameOrg(id);
    final org = db['orgs'].get(id, what: 'Organization not found');
    return MockResponse.ok(
      OrgModules(
        orgId: id,
        modules: [
          for (final m in (org['modules'] as List? ?? const [])) m as String,
        ],
      ),
    );
  });

  server.on('GET', '/orgs/{id}/onboarding', (req) {
    req.requireCap('org.settings.read');
    final id = req.param('id');
    req.requireSameOrg(id);
    db['orgs'].get(id, what: 'Organization not found');
    return MockResponse.ok(MockSeed.instance.onboarding(id));
  });

  server.on('GET', '/public/orgs/brand', (req) {
    final id = req.q('org_id');
    final slug = req.q('slug');
    final org = db['orgs'].firstWhere(
      (o) =>
          (id != null && o['id'] == id) || (slug != null && o['slug'] == slug),
    );
    if (org == null) return MockResponse.notFound('Organization not found');
    final o = Org.fromJson(org);
    return MockResponse.ok(
      PublicBrand(
        orgId: o.id,
        name: o.name,
        slug: o.slug,
        customBranding: o.customBranding,
        accentColor: o.brandAccent ?? '#0F766E',
        backgroundColor: o.brandBackground ?? '#FFFFFF',
        foregroundColor: o.brandForeground ?? '#0F172A',
        logoIsMark: o.brandLogoIsMark ?? false,
        logoUrl: o.logoUrl,
        cardImageUrl: o.brandCardImage,
      ),
    );
  });

  // ── branches ──────────────────────────────────────────────────────────
  server.on('GET', '/branches', (req) {
    req.requireCap('branches.read');
    final orgId = req.q('org_id');
    if (orgId == null) {
      req.badRequest('Query deserialize error: missing field `org_id`');
    }
    req.requireSameOrg(orgId);
    return MockResponse.ok(
      db['branches'].query(
        filters: {'org_id': orgId},
        where: (b) => req.persona.seesBranch(b['id']! as String),
        sort: 'name',
      ),
    );
  });

  server.on('GET', '/branches/{id}', (req) {
    req.requireCap('branches.read');
    final b = db['branches'].get(req.param('id'), what: 'Branch not found');
    req.requireSameOrg(b['org_id'] as String?);
    req.requireBranch(b['id']! as String);
    return MockResponse.ok(b);
  });

  server.on('GET', '/timezones', (req) => MockResponse.ok(mockTimezones));

  // ── realtime ──────────────────────────────────────────────────────────
  server.onStream('GET', '/realtime/stream', (req) {
    final branchId = req.q('branch_id');
    if (branchId != null) req.requireBranch(branchId);
    return server.channel(realtimeChannel(branchId));
  });

  // ── Dawam set-up progress (sidebar, command palette) ─────────────────
  server.on('GET', '/staff/employees', (req) {
    final branchId = req.q('branch_id');
    req.requireCap('hr.staff.read', branchId: branchId);
    final rows = db['employees'].query(
      filters: {
        'org_id': req.orgId,
        'employment_status': req.q('employment_status'),
        'kind': req.q('kind'),
        'department_id': req.q('department_id'),
      },
      where: (e) {
        final ids = (e['branch_ids'] as List?)?.cast<String>() ?? const [];
        if (branchId != null && !ids.contains(branchId)) return false;
        final scoped = req.persona.branchIds;
        return scoped == null || ids.any(scoped.contains);
      },
      search: req.q('search'),
      searchFields: const ['name', 'phone', 'employee_code', 'job_title'],
      sort: 'name',
    );
    return MockResponse.ok(rows);
  });

  server.on('GET', '/staff/work-shifts', (req) {
    req.requireCap('hr.schedule.read');
    return MockResponse.ok([
      for (final r in db['work_shifts'].query(
        filters: {'org_id': req.orgId},
        sort: 'start_time',
      ))
        _shiftAsRead(r),
    ]);
  });

  server.on('GET', '/staff/attendance/settings', (req) {
    final branchId = req.q('branch_id');
    req.requireAnyCap(const [
      'hr.rules.view',
      'hr.rules.edit',
    ], branchId: branchId);
    final row = db['attendance_settings'].firstWhere(
      (s) => s['org_id'] == req.orgId,
    );
    if (row == null) {
      return MockResponse.notFound('Attendance settings not found');
    }
    return MockResponse.ok(row);
  });
}

final TaxPolicyPublic _taxPolicy = TaxPolicyPublic(
  taxRate: MockSeed.taxRate,
  taxInclusive: true,
  serviceChargeRate: 0,
  serviceChargeTaxable: true,
);

UserPublic _user(MockDb db, Persona p) {
  final row = db['users'].find(p.userId);
  if (row != null) return UserPublic.fromJson(row);
  return UserPublic(
    id: p.userId,
    name: p.displayName,
    email: p.email,
    role: UserRole.fromJson(p.role),
    orgId: p.orgId,
    branchId: p.homeBranchId,
    isActive: true,
  );
}

/// A `work_shifts` row as the server reads it: the columns' defaults (the
/// staff_schedules and shift_blocks migrations) where a bare insert left one
/// out, and `crosses_midnight`, a generated column.
MockRow _shiftAsRead(MockRow r) => {
  'grace_minutes': 15,
  'break_minutes': 0,
  'paid_break': true,
  'overtime_threshold_minutes': 15,
  'overtime_multiplier': 1.5,
  'checkin_window_minutes': 120,
  'is_active': true,
  'valid_days': const [0, 1, 2, 3, 4, 5, 6],
  ...r,
  'crosses_midnight': '${r['end_time']}'.compareTo('${r['start_time']}') <= 0,
};
