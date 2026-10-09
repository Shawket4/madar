// The Roles handlers against hand-computed answers: gates per persona, the
// backend's check order and refusals, state, and the policy list.
import 'package:dashboard_admin/src/mock/roles_mock.dart' show RolesSeed;
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart' show capabilityRegistry;
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

({MockServer server, AuthzApi api, MockDb db}) _api([
  Persona p = Persona.owner,
]) {
  final s = rolesServer(persona: p);
  return (server: s.server, api: DashboardApi(s.server).authz, db: s.db);
}

Future<(int, String)> _fails(Future<Object?> call) async {
  try {
    await call;
    return (200, '');
  } on ApiException catch (e) {
    return (e.status, e.message);
  }
}

Set<String> _caps(RoleView r) => {for (final g in r.grants) g.capability};

void main() {
  test('the list: built-in roles by kind, then Senior cashier; members '
      'counted from who holds each role', () async {
    final roles = await _api().api.listRoles();
    expect([for (final r in roles) (r.nameEn, r.members, r.isSystem)], [
      ('Owner', 1, true),
      ('Branch manager', 4, true),
      ('Cashier', 8, true),
      ('Waiter', 2, true),
      ('Kitchen', 1, true),
      ('Senior cashier', 0, false),
    ]);
    expect(roles.first.editable, isFalse);
    final senior = roles.last;
    expect(senior.kind, 'teller');
    expect(senior.editable, isTrue);
    // The cashier's grants plus voiding, refunds capped at EGP 1,000.
    expect(_caps(senior), containsAll(['orders.create', 'orders.void']));
    expect(
      senior.grants.firstWhere((g) => g.capability == 'refunds.create')
          .limits
          .maxAmount,
      100000,
    );
  });

  group('create', () {
    test('from the usual defaults: the kind\'s template minus what is always '
        'on, no limits, 201', () async {
      final a = _api();
      final r = await a.api.createRole(
        body: const CreateRoleRequest(
          nameEn: '  Shift lead ',
          nameAr: ' مشرف الوردية',
          kind: 'teller',
        ),
      );
      expect(a.server.calls.last.status, 201);
      expect((r.nameEn, r.nameAr, r.kind), ('Shift lead', 'مشرف الوردية', 'teller'));
      expect((r.isSystem, r.editable, r.members), (false, true, 0));
      expect(r.key, startsWith('shift_lead_'));
      final caps = _caps(r);
      expect(caps, containsAll(['orders.create', 'refunds.create', 'till.open']));
      // Core for a cashier: never stored.
      expect(caps, isNot(contains('orders.read')));
      expect(caps, isNot(contains('pos.sign_in')));
      // Not a cashier's.
      expect(caps, isNot(contains('branches.edit')));
      expect(r.grants.every((g) => g.source == 'custom'), isTrue);
      expect(r.grants.every((g) => g.limits.toJson().isEmpty), isTrue);
      // State: the next list has it, after the built-in roles.
      final list = await a.api.listRoles();
      expect([for (final x in list) x.nameEn].sublist(5), [
        'Senior cashier',
        'Shift lead',
      ]);
    });

    test('copy_from copies the capabilities, not their limits', () async {
      final a = _api();
      final r = await a.api.createRole(
        body: CreateRoleRequest(
          nameEn: 'Night cashier',
          nameAr: 'كاشير ليلي',
          kind: 'teller',
          copyFrom: RolesSeed.seniorCashier,
        ),
      );
      final senior = (await a.api.listRoles()).firstWhere(
        (x) => x.id == RolesSeed.seniorCashier,
      );
      expect(_caps(r), _caps(senior));
      expect(
        r.grants.firstWhere((g) => g.capability == 'refunds.create').limits
            .maxAmount,
        isNull,
      );
    });

    test('refusals in the backend\'s order', () async {
      final a = _api();
      Future<(int, String)> create(String en, String ar, String kind,
              [String? from]) =>
          _fails(
            a.api.createRole(
              body: CreateRoleRequest(
                nameEn: en,
                nameAr: ar,
                kind: kind,
                copyFrom: from,
              ),
            ),
          );
      expect(
        (await create('Boss', 'رئيس', 'org_admin')).$2,
        contains('kind must be branch_manager, teller, waiter or kitchen'),
      );
      expect(
        (await create(' ', 'رئيس', 'teller')).$2,
        contains('A role needs an English and an Arabic name'),
      );
      // 41 Arabic letters are 82 bytes: over the backend's 80.
      expect(
        (await create('Long', 'ع' * 41, 'teller')).$1,
        400,
      );
      expect((await create('Long', 'ع' * 40, 'teller')).$1, 200);
      expect(
        (await create('Copy', 'نسخة', 'teller', 'missing')).$1,
        404,
      );
      // No roles.manage: refused before anything is looked at.
      final m = _api(Persona.manager);
      final (status, words) = await _fails(
        m.api.createRole(
          body: const CreateRoleRequest(nameEn: '', nameAr: '', kind: 'x'),
        ),
      );
      expect(status, 403);
      expect(words, contains('staff.roles.manage'));
    });
  });

  group('rename', () {
    test('trimmed names; a missing name keeps the old one; any role, the '
        'owner\'s included', () async {
      final a = _api();
      final r = await a.api.renameRole(
        id: roleId('org_admin'),
        body: const RenameRoleRequest(nameEn: ' Founder '),
      );
      expect((r.nameEn, r.nameAr), ('Founder', 'المالك'));
      expect(
        (await _fails(
          a.api.renameRole(
            id: roleId('waiter'),
            body: const RenameRoleRequest(nameAr: '  '),
          ),
        )).$1,
        400,
      );
      expect(
        (await _fails(
          a.api.renameRole(id: 'missing', body: const RenameRoleRequest()),
        )).$1,
        404,
      );
      expect(
        (await _fails(
          _api(Persona.manager).api.renameRole(
            id: roleId('waiter'),
            body: const RenameRoleRequest(nameEn: 'x'),
          ),
        )).$1,
        403,
      );
    });
  });

  group('grants', () {
    test('on and off; limits kept to the ones the capability takes',
        () async {
      final a = _api();
      final id = roleId('waiter');
      var r = await a.api.setRoleGrant(
        id: id,
        body: const SetGrantRequest(capability: 'branches.edit', granted: true),
      );
      expect(_caps(r), contains('branches.edit'));
      r = await a.api.setRoleGrant(
        id: id,
        body: const SetGrantRequest(
          capability: 'refunds.create',
          granted: true,
          limits: LimitsView(maxAmount: 5000, maxPercent: 1000),
        ),
      );
      expect(
        r.grants.firstWhere((g) => g.capability == 'refunds.create').limits
            .toJson(),
        {'max_amount': 5000},
      );
      r = await a.api.setRoleGrant(
        id: id,
        body: const SetGrantRequest(capability: 'branches.edit', granted: false),
      );
      expect(_caps(r), isNot(contains('branches.edit')));
    });

    test('refusals: the owner role, unknown and legacy capabilities, what '
        'is always on, no roles.manage', () async {
      final a = _api();
      Future<(int, String)> set(String role, String cap, bool on) => _fails(
        a.api.setRoleGrant(
          id: role,
          body: SetGrantRequest(capability: cap, granted: on),
        ),
      );
      final owner = await set(roleId('org_admin'), 'orders.void', false);
      expect(owner.$1, 409);
      expect(
        owner.$2,
        contains('The owner role holds everything and cannot be edited'),
      );
      expect((await set(roleId('teller'), 'nope.nope', true)).$1, 400);
      final legacy = capabilityRegistry.firstWhere((c) => c.tier == 'legacy').key;
      expect(
        (await set(roleId('teller'), legacy, true)).$2,
        contains('kept for older tablets'),
      );
      final core = await set(roleId('teller'), 'orders.read', false);
      expect(core.$1, 403);
      expect(core.$2, contains('always on for this role'));
      expect(
        (await _fails(
          _api(Persona.manager).api.setRoleGrant(
            id: roleId('teller'),
            body: const SetGrantRequest(capability: 'x', granted: true),
          ),
        )).$1,
        403,
      );
      // Unknown role: after the capability check.
      expect((await set('missing', 'orders.void', true)).$1, 404);
    });
  });

  group('delete', () {
    test('built-in 409, held 409, free 204 and gone', () async {
      final a = _api();
      final system = await _fails(a.api.deleteRole(id: roleId('waiter')));
      expect(system.$1, 409);
      expect(system.$2, contains('Built-in roles cannot be deleted'));
      // Mariam takes Senior cashier (the Users unit's assignments).
      await DashboardApi(a.server).authz.setAssignments(
        id: SeedIds.user('mariam'),
        body: SetAssignmentsRequest(
          assignments: [
            AssignmentInput(
              roleId: RolesSeed.seniorCashier,
              allBranches: false,
              branchIds: [SeedIds.zamalek],
            ),
          ],
        ),
      );
      final held = await _fails(a.api.deleteRole(id: RolesSeed.seniorCashier));
      expect(held.$1, 409);
      expect(held.$2, contains('People still hold this role'));
      final roles = await a.api.listRoles();
      expect(
        roles.firstWhere((r) => r.id == RolesSeed.seniorCashier).members,
        1,
      );
      expect(roles.firstWhere((r) => r.id == roleId('teller')).members, 7);
      // Back to Cashier: free again.
      await DashboardApi(a.server).authz.setAssignments(
        id: SeedIds.user('mariam'),
        body: SetAssignmentsRequest(
          assignments: [
            AssignmentInput(
              roleId: roleId('teller'),
              allBranches: false,
              branchIds: [SeedIds.zamalek],
            ),
          ],
        ),
      );
      await a.api.deleteRole(id: RolesSeed.seniorCashier);
      expect(a.server.calls.last.status, 204);
      expect(
        [for (final r in await a.api.listRoles()) r.id],
        isNot(contains(RolesSeed.seniorCashier)),
      );
      expect(
        (await _fails(_api(Persona.manager).api.deleteRole(id: 'x'))).$1,
        403,
      );
    });
  });

  group('policy', () {
    test('every approval capability, three asked; any member may read it',
        () async {
      final list = await _api(Persona.limited).api.getPolicy();
      expect(list, hasLength(15));
      expect(
        {for (final p in list) if (p.askManager) p.capability},
        {'orders.void', 'refunds.create', 'orders.discount.manual_percent'},
      );
    });

    test('a change answers the whole list; refusals', () async {
      final a = _api();
      final list = await a.api.setPolicy(
        body: const PolicyEntry(capability: 'tickets.void', askManager: true),
      );
      expect(
        list.firstWhere((p) => p.capability == 'tickets.void').askManager,
        isTrue,
      );
      expect(
        (await a.api.getPolicy())
            .firstWhere((p) => p.capability == 'tickets.void')
            .askManager,
        isTrue,
      );
      final notApproval = await _fails(
        a.api.setPolicy(
          body: const PolicyEntry(capability: 'branches.edit', askManager: true),
        ),
      );
      expect(notApproval.$1, 400);
      expect(notApproval.$2, contains('cannot be approved by a manager'));
      expect(
        (await _fails(
          _api(Persona.manager).api.setPolicy(
            body: const PolicyEntry(capability: 'orders.void', askManager: true),
          ),
        )).$1,
        403,
      );
    });
  });
}
