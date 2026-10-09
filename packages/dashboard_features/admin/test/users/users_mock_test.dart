// The Users handlers against hand-computed answers: scoping, gates per
// persona, validation order, state, and the access resolver.
import 'package:dashboard_admin/src/users/users_data.dart';
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart' show Strings, Translator;
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

({MockServer server, DashboardApi api, MockDb db}) _api([
  Persona p = Persona.owner,
]) {
  final s = usersServer(persona: p);
  return (server: s.server, api: DashboardApi(s.server), db: s.db);
}

Future<int> _status(Future<Object?> call) async {
  try {
    await call;
    return 200;
  } on ApiException catch (e) {
    return e.status;
  }
}

Future<String> _error(Future<Object?> call) async {
  try {
    await call;
    return '';
  } on ApiException catch (e) {
    return e.message;
  }
}

void main() {
  group('list', () {
    test('owner: every Sabah account by name; manager: their branch', () async {
      final o = _api();
      final all = await o.api.users.listUsers(orgId: SeedIds.sabahOrg);
      expect(all, hasLength(16));
      expect(all.first.name, 'Adham Reda');
      expect(all.last.name, 'Ziad Amr');
      final m = _api(Persona.manager);
      final mine = await m.api.users.listUsers(orgId: SeedIds.sabahOrg);
      expect([for (final u in mine) u.name], [
        'Adham Reda',
        'Hassan Ibrahim',
        'Karim Adel',
        'Laila Ehab',
        'Mariam Fathy',
        'Youssef Samir',
      ]);
      expect(
        await _status(_api(Persona.limited).api.users.listUsers()),
        403,
      );
    });
  });

  group('create', () {
    test('validation in the backend\'s order', () async {
      final o = _api();
      CreateUserRequest req(UserRole role, {String? pin, String? email, String? password, String name = 'Sara Lotfy'}) =>
          CreateUserRequest(
            name: name,
            role: role,
            orgId: SeedIds.sabahOrg,
            pin: pin,
            email: email,
            password: password,
          );
      expect(
        await _error(o.api.users.createUser(body: req(UserRole.teller))),
        'Bad request: Tellers, waiters and kitchen users require a PIN',
      );
      expect(
        await _error(o.api.users.createUser(body: req(UserRole.teller, pin: '1234'))),
        'Bad request: A new PIN must be 6 digits',
      );
      expect(
        await _error(o.api.users.createUser(body: req(UserRole.teller, pin: '482915'))),
        'Conflict: Someone in this organization already uses that PIN',
      );
      expect(
        await _error(o.api.users.createUser(body: req(UserRole.branchManager, email: 'x@y.z'))),
        'Bad request: Admins and managers require a password',
      );
      expect(
        await _error(o.api.users.createUser(body: req(UserRole.branchManager, password: 'p'))),
        'Bad request: Admins and managers require an email',
      );
      expect(
        await _error(
          o.api.users.createUser(
            body: req(UserRole.waiter, pin: '111222', name: 'laila ehab'),
          ),
        ),
        startsWith('Conflict: A teller, waiter or kitchen user with this name'),
      );
      final made = await o.api.users.createUser(
        body: req(UserRole.teller, pin: '111222'),
      );
      expect(made.user.isActive, isTrue);
      expect(
        await o.api.users.listUsers(orgId: SeedIds.sabahOrg),
        hasLength(17),
      );
      // The PIN is now taken.
      expect(
        await _status(o.api.users.createUser(body: req(UserRole.teller, pin: '111222', name: 'Other'))),
        409,
      );
    });

    test('a manager creates till roles only; nobody but the platform a super '
        'admin', () async {
      final m = _api(Persona.manager);
      expect(
        await _status(
          m.api.users.createUser(
            body: CreateUserRequest(
              name: 'New Manager',
              role: UserRole.branchManager,
              orgId: SeedIds.sabahOrg,
              email: 'nm@sabah.test',
              password: 'p',
            ),
          ),
        ),
        403,
      );
      expect(
        await _status(
          _api().api.users.createUser(
            body: CreateUserRequest(
              name: 'Root',
              role: UserRole.superAdmin,
              orgId: SeedIds.sabahOrg,
              email: 'root@sabah.test',
              password: 'p',
            ),
          ),
        ),
        403,
      );
    });

    test('the PIN suggestion is six digits nobody in the org holds', () async {
      final pin = (await _api().api.users.suggestPin()).pin;
      expect(pin, matches(RegExp(r'^\d{6}$')));
      expect(sabahStaff.map((p) => p.pin), isNot(contains(pin)));
      expect(await _status(_api(Persona.limited).api.users.suggestPin()), 403);
    });
  });

  group('edit and delete', () {
    test('null keeps; self cannot demote or deactivate; last owner kept', () async {
      final o = _api();
      final u = await o.api.users.updateUser(
        id: uid('mariam'),
        body: const UpdateUserRequest(name: 'Mariam F.', explicitNulls: {'email'}),
      );
      expect(u.name, 'Mariam F.');
      expect(u.phone, '+201110001111');
      expect(
        await _error(
          o.api.users.updateUser(
            id: SeedIds.owner,
            body: const UpdateUserRequest(isActive: false),
          ),
        ),
        'Forbidden: You cannot change your own role or deactivate yourself',
      );
      expect(
        await _error(
          o.api.users.updateUser(
            id: uid('karim'),
            body: const UpdateUserRequest(email: 'nour@sabah.test'),
          ),
        ),
        'Conflict: Email already in use',
      );
      final m = _api(Persona.manager);
      expect(
        await _error(
          m.api.users.updateUser(
            id: uid('dina'),
            body: const UpdateUserRequest(name: 'D'),
          ),
        ),
        'Forbidden: You cannot manage a user with this role',
      );
    });

    test('delete: gone from the list; yourself refused; manager refused', () async {
      final o = _api();
      await o.api.users.deleteUser(id: uid('ziad'));
      expect(
        (await o.api.users.listUsers(orgId: SeedIds.sabahOrg)).map((u) => u.name),
        isNot(contains('Ziad Amr')),
      );
      expect(
        await _error(o.api.users.deleteUser(id: SeedIds.owner)),
        'Forbidden: You cannot delete yourself',
      );
      expect(await _status(o.api.users.deleteUser(id: 'missing')), 404);
      expect(
        await _status(_api(Persona.manager).api.users.deleteUser(id: uid('mariam'))),
        403,
      );
    });
  });

  group('branches', () {
    test('assignments read, assign and unassign', () async {
      final o = _api();
      final before = await o.api.users.listUserBranches(id: uid('dina'));
      expect([for (final b in before) b.branchName], ['New Cairo', 'Maadi']);
      await o.api.users.assignBranch(
        id: uid('dina'),
        body: AssignBranchRequest(branchId: SeedIds.zamalek),
      );
      await o.api.users.unassignBranch(id: uid('dina'), branchId: SeedIds.maadi);
      final after = await o.api.users.listUserBranches(id: uid('dina'));
      expect([for (final b in after) b.branchName], ['New Cairo', 'Zamalek']);
      expect(
        await _status(
          _api(Persona.manager).api.users.assignBranch(
            id: uid('mariam'),
            body: AssignBranchRequest(branchId: SeedIds.zamalek),
          ),
        ),
        403,
      );
    });
  });

  group('access', () {
    test('a teller\'s access: core, role, the person\'s own, at a branch', () async {
      final o = _api();
      final a = await o.api.authz.userAccess(id: uid('youssef'));
      CapabilityAccess row(UserAccess x, String k) =>
          x.capabilities.firstWhere((c) => c.capability == k);
      expect(a.canEdit, isTrue);
      expect(a.assignments.single.roleNameEn, 'Cashier');
      expect(row(a, 'branches.read').source, 'core');
      expect(row(a, 'orders.void').source, 'role');
      expect(row(a, 'orders.void').fromRoles, ['Cashier']);
      expect(effectAt(row(a, 'orders.void'), null), 'inherit');
      final z = await o.api.authz.userAccess(
        id: uid('youssef'),
        branchId: SeedIds.zamalek,
      );
      expect(row(z, 'orders.void').source, 'deny');
      expect(row(z, 'orders.void').effective, isFalse);
      expect(effectAt(row(z, 'orders.void'), SeedIds.zamalek), 'deny');
      expect(
        a.capabilities.any((c) => c.capability.startsWith('legacy.')),
        isFalse,
      );
    });

    test('locked reasons by who is looking', () async {
      expect(
        (await _api().api.authz.userAccess(id: SeedIds.owner)).lockedReason,
        'self',
      );
      expect(
        await _error(_api(Persona.platform).api.authz.userAccess(id: SeedIds.owner)),
        'Forbidden: No organization selected',
        reason: 'no org picked: the platform admin acts in none',
      );
      final o = _api();
      expect(
        (await o.api.authz.userAccess(id: uid('karim'))).canEdit,
        isTrue,
      );
      expect(
        (await _api(Persona.manager).api.authz.userAccess(id: SeedIds.manager))
            .lockedReason,
        'self',
        reason: 'anyone may read their own access',
      );
    });

    test('overrides: allow with limits restricted to the capability\'s, '
        'inherit removes', () async {
      final o = _api();
      final after = await o.api.authz.setOverride(
        id: uid('mariam'),
        body: const SetOverrideRequest(
          capability: 'refunds.create',
          effect: 'allow',
          limits: LimitsView(maxAmount: 30000, maxPercent: 500),
        ),
      );
      final r = after.capabilities.firstWhere((c) => c.capability == 'refunds.create');
      expect(r.source, 'allow');
      expect(r.limits?.maxAmount, 30000);
      expect(r.limits?.maxPercent, isNull);
      final back = await o.api.authz.setOverride(
        id: uid('mariam'),
        body: const SetOverrideRequest(capability: 'refunds.create', effect: 'inherit'),
      );
      expect(
        back.capabilities.firstWhere((c) => c.capability == 'refunds.create').source,
        'role',
      );
      expect(
        await _error(
          o.api.authz.setOverride(
            id: uid('mariam'),
            body: const SetOverrideRequest(capability: 'nope', effect: 'allow'),
          ),
        ),
        'Bad request: Unknown capability nope',
      );
      expect(
        await _status(
          o.api.authz.setOverride(
            id: SeedIds.owner,
            body: const SetOverrideRequest(capability: 'orders.void', effect: 'deny'),
          ),
        ),
        403,
      );
      expect(
        await _status(
          _api(Persona.manager).api.authz.setOverride(
            id: uid('mariam'),
            body: const SetOverrideRequest(capability: 'orders.void', effect: 'deny'),
          ),
        ),
        403,
      );
    });

    test('assignments replace the roles; at least one; branches or all', () async {
      final o = _api();
      final teller = mockUuid('role:sabah:teller');
      expect(
        await _error(
          o.api.authz.setAssignments(
            id: uid('mariam'),
            body: const SetAssignmentsRequest(assignments: []),
          ),
        ),
        'Bad request: A person needs at least one role',
      );
      expect(
        await _error(
          o.api.authz.setAssignments(
            id: uid('mariam'),
            body: SetAssignmentsRequest(
              assignments: [AssignmentInput(roleId: teller, allBranches: false)],
            ),
          ),
        ),
        'Bad request: Choose the branches, or all branches',
      );
      final a = await o.api.authz.setAssignments(
        id: uid('mariam'),
        body: SetAssignmentsRequest(
          assignments: [AssignmentInput(roleId: teller, allBranches: true)],
        ),
      );
      expect(a.assignments.single.allBranches, isTrue);
    });

    test('explain: the steps the backend writes', () async {
      final e = await _api().api.authz.explain(
        userId: uid('omar'),
        capability: 'refunds.create',
      );
      expect(e.effective, isTrue);
      expect([for (final s in e.steps) s.kind], [
        'assignment',
        'override_allow',
        'limit',
      ]);
      final n = await _api().api.authz.explain(
        userId: uid('youssef'),
        capability: 'orders.void',
        branchId: SeedIds.zamalek,
      );
      expect(n.effective, isFalse);
      expect([for (final s in n.steps) s.kind], [
        'assignment',
        'override_deny',
        'ask_manager',
        'not_held',
      ]);
      expect(
        await _status(
          _api(Persona.manager).api.authz.explain(
            userId: uid('mariam'),
            capability: 'orders.void',
          ),
        ),
        403,
      );
    });
  });

  group('rules', () {
    test('role options, till roles, assignable rows', () {
      expect(roleOptionsFor('super_admin'), hasLength(6));
      expect(roleOptionsFor('branch_manager'), [
        UserRole.teller,
        UserRole.waiter,
        UserRole.kitchen,
      ]);
      expect(roleOptionsFor('org_admin'), isNot(contains(UserRole.superAdmin)));
      expect(assignableRole(UserRole.orgAdmin), isFalse);
      expect(assignableRole(UserRole.kitchen), isTrue);
      expect(isTillRole(UserRole.branchManager), isFalse);
    });

    test('locked reasons in words; an unknown code reads the generic', () {
      final t = Translator(
        Strings({
          'en': {
            'access.locked': 'Generic',
            'access.lockedReasons.self': 'Yourself',
          },
        }),
        'en',
      );
      expect(lockedReasonText('self', t), 'Yourself');
      expect(lockedReasonText('weird', t), 'Generic');
      expect(lockedReasonText(null, t), 'Generic');
    });
  });
}
