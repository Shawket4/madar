// What the app shell calls at start, through the typed client, for every
// persona: sign-in, me, authz, org + modules + onboarding, orgs, branches,
// brand, realtime and the Dawam set-up reads.
import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:flutter_test/flutter_test.dart';

({MockServer server, DashboardApi api, MockDb db}) _boot([
  Persona persona = Persona.owner,
]) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  return (server: server, api: DashboardApi(server), db: db);
}

Matcher _status(int status, [String? message]) => isA<ApiException>()
    .having((e) => e.status, 'status', status)
    .having((e) => e.message, 'message', message ?? anything);

void main() {
  group('sign-in', () {
    test(
      'a persona signs in with email and password and becomes the session',
      () async {
        final b = _boot(Persona.platform);
        final res = await b.api.auth.login(
          body: const LoginRequest(
            email: 'karim@sabah.test',
            password: Persona.password,
          ),
        );
        expect(res.token, Persona.manager.token);
        expect(res.user.name, 'Karim Adel');
        expect(res.user.role, UserRole.branchManager);
        expect(res.user.branchId, SeedIds.zamalek);
        expect(res.currencyCode, 'EGP');
        expect(res.taxPolicy.taxInclusive, isTrue);
        expect(b.server.persona, Persona.manager);
      },
    );

    test('a wrong password is the backend 401', () async {
      final b = _boot();
      await expectLater(
        b.api.auth.login(
          body: const LoginRequest(email: 'nour@sabah.test', password: 'nope'),
        ),
        throwsA(_status(401, 'Unauthorized: Invalid credentials')),
      );
      await expectLater(
        b.api.auth.login(
          body: const LoginRequest(
            email: 'nobody@sabah.test',
            password: Persona.password,
          ),
        ),
        throwsA(_status(401)),
      );
    });

    test('me answers the signed-in person', () async {
      final b = _boot(Persona.dawamOnly);
      final me = await b.api.auth.me();
      expect(me.user.name, 'Yasmin Ghali');
      expect(me.user.orgId, SeedIds.nakhlaOrg);
    });
  });

  group('authz', () {
    test('owner, manager, limited, platform', () async {
      for (final p in Persona.values) {
        final a = await _boot(p).api.authz.getMyAuthz();
        expect(a.userId, p.userId, reason: p.name);
        expect(a.capabilities.toSet(), p.capabilities, reason: p.name);
        expect(a.platform, p == Persona.platform, reason: p.name);
        expect(a.owner, p.isOwner, reason: p.name);
        expect(a.roleKinds, p.roleKinds, reason: p.name);
      }
      final m = await _boot(
        Persona.manager,
      ).api.authz.getMyAuthz(branchId: SeedIds.zamalek);
      expect(m.branchId, SeedIds.zamalek);
      expect(m.everywhere, isEmpty);
    });
  });

  group('org', () {
    test('the owner reads the org, its modules and its onboarding', () async {
      final api = _boot().api;
      final org = await api.orgs.getOrg(id: SeedIds.sabahOrg);
      expect(org.name, 'Sabah Coffee');
      expect(org.currencyCode, 'EGP');
      expect((await api.orgs.getOrgModules(id: SeedIds.sabahOrg)).modules, [
        'pos',
        'dawam',
      ]);
      final onboarding = await api.orgs.getOnboarding(id: SeedIds.sabahOrg);
      expect(onboarding.completed, isTrue);
      expect(onboarding.steps, isNotEmpty);
    });

    test(
      'a manager reads the modules but not the org (the web never asks)',
      () async {
        final api = _boot(Persona.manager).api;
        expect((await api.orgs.getOrgModules(id: SeedIds.sabahOrg)).modules, [
          'pos',
          'dawam',
        ]);
        await expectLater(
          api.orgs.getOrg(id: SeedIds.sabahOrg),
          throwsA(
            _status(
              403,
              "Forbidden: You don't have permission to do this: See business settings (org.settings.read)",
            ),
          ),
        );
      },
    );

    test(
      'the Dawam-only org has only the dawam module and an incomplete POS checklist',
      () async {
        final api = _boot(Persona.dawamOnly).api;
        expect((await api.orgs.getOrgModules(id: SeedIds.nakhlaOrg)).modules, [
          'dawam',
        ]);
        expect(
          (await api.orgs.getOnboarding(id: SeedIds.nakhlaOrg)).completed,
          isFalse,
        );
        await expectLater(
          api.orgs.getOrg(id: SeedIds.sabahOrg),
          throwsA(_status(403)),
        );
      },
    );

    test('only a platform admin lists orgs', () async {
      final orgs = await _boot(Persona.platform).api.orgs.listOrgs();
      expect(orgs.map((o) => o.name), ['Nakhla Bakery', 'Sabah Coffee']);
      await expectLater(
        _boot().api.orgs.listOrgs(),
        throwsA(_status(403, 'Forbidden: Super admin access required')),
      );
    });

    test('a platform admin acts in the org it pins', () async {
      final b = _boot(Persona.platform);
      b.server.platformOrgId = SeedIds.nakhlaOrg;
      final employees = await b.api.staff.listEmployees();
      expect(employees.every((e) => e.orgId == SeedIds.nakhlaOrg), isTrue);
      expect(employees, isNotEmpty);
    });

    test('the public brand needs no capability', () async {
      final brand = await _boot(
        Persona.limited,
      ).api.orgs.publicOrgBrand(orgId: SeedIds.sabahOrg);
      expect(brand.name, 'Sabah Coffee');
      expect(brand.customBranding, isTrue);
      final bySlug = await _boot().api.orgs.publicOrgBrand(
        slug: 'nakhla-bakery',
      );
      expect(bySlug.orgId, SeedIds.nakhlaOrg);
      await expectLater(
        _boot().api.orgs.publicOrgBrand(slug: 'nope'),
        throwsA(_status(404)),
      );
    });
  });

  group('branches', () {
    test('the owner sees four, by name; the manager sees his one', () async {
      final all = await _boot().api.branches.listBranches(
        orgId: SeedIds.sabahOrg,
      );
      expect(all.map((b) => b.name), [
        'Heliopolis',
        'Maadi',
        'New Cairo',
        'Zamalek',
      ]);
      expect(all.every((b) => b.timezone == 'Africa/Cairo'), isTrue);
      final mine = await _boot(
        Persona.manager,
      ).api.branches.listBranches(orgId: SeedIds.sabahOrg);
      expect(mine.map((b) => b.name), ['Zamalek']);
    });

    test(
      'another org\'s branches are refused; one branch reads by id',
      () async {
        final api = _boot().api;
        await expectLater(
          api.branches.listBranches(orgId: SeedIds.nakhlaOrg),
          throwsA(_status(403, 'Forbidden: Access to this org is not allowed')),
        );
        expect((await api.branches.getBranch(id: SeedIds.maadi)).name, 'Maadi');
        await expectLater(
          _boot(Persona.manager).api.branches.getBranch(id: SeedIds.maadi),
          throwsA(_status(403, 'Forbidden: Not assigned to this branch')),
        );
        await expectLater(
          api.branches.getBranch(id: 'missing'),
          throwsA(_status(404)),
        );
      },
    );

    test('timezones', () async {
      expect(
        await _boot().api.branches.listTimezones(),
        contains('Africa/Cairo'),
      );
    });
  });

  group('Dawam set-up reads', () {
    test(
      'employees, work shifts and attendance settings decode into models',
      () async {
        final api = _boot().api;
        final employees = await api.staff.listEmployees(
          employmentStatus: 'active',
        );
        expect(employees.length, 16);
        expect(employees.first.name, 'Adham Reda');
        final zamalek = await api.staff.listEmployees(
          branchId: SeedIds.zamalek,
        );
        expect(
          zamalek.every((e) => e.branchIds.contains(SeedIds.zamalek)),
          isTrue,
        );
        expect(
          (await api.staff.listEmployees(search: 'karim')).single.name,
          'Karim Adel',
        );
        final shifts = await api.staff.listWorkShifts();
        expect(shifts.map((s) => s.name), ['Morning', 'Evening']);
        final settings = await api.staff.getAttendanceSettings();
        expect(settings.orgId, SeedIds.sabahOrg);
      },
    );

    test(
      'a manager sees the people of his branch; the limited persona is refused',
      () async {
        final mine = await _boot(Persona.manager).api.staff.listEmployees();
        expect(mine, isNotEmpty);
        expect(
          mine.every((e) => e.branchIds.contains(SeedIds.zamalek)),
          isTrue,
        );
        await expectLater(
          _boot(Persona.limited).api.staff.listEmployees(),
          throwsA(
            _status(
              403,
              "Forbidden: You don't have permission to do this: ${_label('hr.staff.read')} (hr.staff.read)",
            ),
          ),
        );
        await expectLater(
          _boot(Persona.limited).api.staff.getAttendanceSettings(),
          throwsA(_status(403)),
        );
      },
    );
  });

  test(
    'the realtime stream carries frames published on the branch channel',
    () async {
      final b = _boot();
      final frames = <String>[];
      final sub = b.api.realtime
          .stream(branchId: SeedIds.zamalek)
          .listen(frames.add);
      b.server.publish(
        realtimeChannel(SeedIds.zamalek),
        jsonEncode({'type': 'floor.changed'}),
      );
      b.server.publish(
        realtimeChannel(SeedIds.maadi),
        jsonEncode({'type': 'floor.changed'}),
      );
      await Future<void>.delayed(Duration.zero);
      expect(frames, ['{"type":"floor.changed"}']);
      await sub.cancel();
      await b.server.close();
    },
  );

  test('the shell start-up sequence hits no unmatched route', () async {
    for (final p in Persona.values) {
      final b = _boot(p);
      final orgId = p.orgId ?? SeedIds.sabahOrg;
      b.server.platformOrgId = orgId;
      await b.api.auth.me();
      if (!p.isPlatform) await b.api.authz.getMyAuthz();
      await b.api.orgs.getOrgModules(id: orgId);
      await b.api.orgs.publicOrgBrand(orgId: orgId);
      await b.api.branches.listBranches(orgId: orgId);
      if (p.can('org.settings.read')) {
        await b.api.orgs.getOrg(id: orgId);
        await b.api.orgs.getOnboarding(id: orgId);
      }
      if (p.can('hr.rules.edit')) {
        await b.api.staff.listEmployees(employmentStatus: 'active');
        await b.api.staff.listWorkShifts();
        await b.api.staff.getAttendanceSettings();
      }
      if (p.isPlatform) await b.api.orgs.listOrgs();
      expect(b.server.unmatched, isEmpty, reason: p.name);
      expect(b.server.handlerErrors, isEmpty, reason: p.name);
      expect(
        b.server.calls.every((c) => (c.status ?? 0) < 300),
        isTrue,
        reason: '${p.name}: ${b.server.calls}',
      );
    }
  });
}

String _label(String key) =>
    mockCapabilities.firstWhere((c) => c.key == key).en;
