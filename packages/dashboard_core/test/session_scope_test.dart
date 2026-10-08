// Session, authz, modules, onboarding, set-up and scope against the mock
// backend (package:dashboard_api/mock.dart) and its personas.
import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/mock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> settle() async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class Rig {
  Rig({Persona? as, Map<String, String>? prefs, SessionGateway? gateway})
    : db = MockDb.seeded() {
    server = MockServer(persona: as ?? Persona.owner, clock: db.clock);
    registerCoreMocks(server, db);
    gw = MockSessionGateway(server, signedInAs: as);
    this.prefs = MemoryPreferences(prefs);
    c = ProviderContainer(
      overrides: [
        transportProvider.overrideWithValue(gw.transport),
        sessionGatewayProvider.overrideWithValue(gateway ?? gw),
        preferencesProvider.overrideWithValue(this.prefs),
        clockProvider.overrideWithValue(() => db.clock.now),
        initialLocaleProvider.overrideWithValue('en'),
      ],
    );
    c
      ..listen(sessionProvider, (_, _) {})
      ..listen(authzStateProvider, (_, _) {})
      ..listen(currentScopeProvider, (_, _) {})
      ..listen(activeBranchesProvider, (_, _) {});
  }

  final MockDb db;
  late final MockServer server;
  late final MockSessionGateway gw;
  late final MemoryPreferences prefs;
  late final ProviderContainer c;

  Future<void> ready() async {
    await c.read(sessionProvider.future);
    await settle();
  }

  void dispose() => c.dispose();
}

String _jwt(DateTime exp) {
  String part(Object o) =>
      base64Url.encode(utf8.encode(json.encode(o))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.${part({'exp': exp.millisecondsSinceEpoch ~/ 1000})}.sig';
}

class _ExpiredGateway implements SessionGateway {
  _ExpiredGateway(this.token);

  final String token;
  int signOuts = 0;

  @override
  Future<SessionInfo?> restore() async => SessionInfo(
    user: const SessionUser(id: 'u', name: 'U', role: 'org_admin'),
    token: token,
  );

  @override
  Future<SessionInfo> signIn({
    required String email,
    required String password,
    String? orgId,
  }) => throw UnimplementedError();

  @override
  Future<void> signOut() async => signOuts++;

  @override
  Future<void> applyScope({
    required String? orgId,
    required String? branchId,
  }) async {}
}

void main() {
  setUpAll(ensureTimeZones);

  group('session', () {
    test('restores the signed-in persona through /auth/me', () async {
      final r = Rig(as: Persona.owner);
      addTearDown(r.dispose);
      await r.ready();
      final s = r.c.read(currentSessionProvider)!;
      expect(s.user.name, 'Nour El-Sayed');
      expect(s.user.role, 'org_admin');
      expect(s.user.orgId, SeedIds.sabahOrg);
      expect(s.currencyCode, 'EGP');
      expect(s.isPlatform, isFalse);
    });

    test('signs in with email and password; a wrong one is refused', () async {
      final r = Rig();
      addTearDown(r.dispose);
      await r.ready();
      expect(r.c.read(currentSessionProvider), isNull);
      final n = r.c.read(sessionProvider.notifier);
      await expectLater(
        n.signIn(email: Persona.manager.email, password: 'nope'),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)),
      );
      expect(r.c.read(currentSessionProvider), isNull);
      final s = await n.signIn(
        email: Persona.manager.email,
        password: Persona.password,
      );
      expect(s.user.role, 'branch_manager');
      expect(r.c.read(currentSessionProvider)!.user.name, 'Karim Adel');
      expect(r.gw.signedIn, isTrue);
      // The token travels on every request, like the core adds it.
      await settle();
      expect(
        r.server.calls.last.headers['Authorization'],
        'Bearer ${Persona.manager.token}',
      );
    });

    test('signing out forgets the session and the scope', () async {
      final r = Rig(
        as: Persona.owner,
        prefs: {
          ScopePrefKeys.branch: json.encode({
            'org': SeedIds.sabahOrg,
            'branch': SeedIds.maadi,
          }),
        },
      );
      addTearDown(r.dispose);
      await r.ready();
      expect(r.c.read(scopeProvider).branchId, SeedIds.maadi);
      await r.c.read(sessionProvider.notifier).signOut();
      expect(r.c.read(currentSessionProvider), isNull);
      expect(r.prefs.values.containsKey(ScopePrefKeys.branch), isFalse);
      expect(
        r.c.read(sessionProvider.notifier).lastSignOutReason,
        SignOutReason.requested,
      );
      expect(r.c.read(authzProvider).ready, isFalse);
    });

    test('a 401 storm signs out exactly once', () async {
      final r = Rig(as: Persona.owner);
      addTearDown(r.dispose);
      await r.ready();
      final n = r.c.read(sessionProvider.notifier);
      await Future.wait([
        n.handleUnauthorized(),
        n.handleUnauthorized(),
        n.handleUnauthorized(),
      ]);
      expect(r.gw.signOutCount, 1);
      expect(n.lastSignOutReason, SignOutReason.unauthorized);
    });

    test(
      'an expired token signs out before anything asks (requireAuth)',
      () async {
        final now = DateTime.utc(2026, 10, 8, 7);
        final expired = _jwt(now.subtract(const Duration(minutes: 5)));
        final skewed = _jwt(now.subtract(const Duration(seconds: 10)));
        expect(jwtExpiry(expired), isNotNull);
        expect(tokenExpired(expired, now), isTrue);
        expect(
          tokenExpired(skewed, now),
          isFalse,
          reason: '30 s of clock skew allowed',
        );
        expect(tokenExpired('not.a.jwt', now), isFalse);
        final gw = _ExpiredGateway(expired);
        final r = Rig(gateway: gw);
        addTearDown(r.dispose);
        await r.ready();
        expect(r.c.read(currentSessionProvider), isNull);
        expect(gw.signOuts, 1);
        expect(
          r.c.read(sessionProvider.notifier).lastSignOutReason,
          SignOutReason.expired,
        );
      },
    );
  });

  group('authz', () {
    test('the owner: /authz/me, remembered for next time', () async {
      final r = Rig(as: Persona.owner);
      addTearDown(r.dispose);
      await r.ready();
      final a = r.c.read(authzProvider);
      expect(a.ready, isTrue);
      expect(a.owner, isTrue);
      expect(a.can(Cap.ordersVoid), isTrue);
      expect(a.can(Cap.platformOrgsCreate), isFalse);
      expect(r.prefs.values[authzPrefKey(SeedIds.owner)], isNotNull);
    });

    test(
      'a manager holds the registry manager defaults, not the owner ones',
      () async {
        final r = Rig(as: Persona.manager);
        addTearDown(r.dispose);
        await r.ready();
        final a = r.c.read(authzProvider);
        expect(a.can(Cap.ordersRead), isTrue);
        expect(a.can(Cap.orgSettingsEdit), isFalse);
        expect(a.owner, isFalse);
        expect(r.c.read(canPickBranchProvider), isFalse);
      },
    );

    test('a platform admin holds everything and asks nothing', () async {
      final r = Rig(as: Persona.platform);
      addTearDown(r.dispose);
      await r.ready();
      final a = r.c.read(authzProvider);
      expect(a.platform, isTrue);
      expect(a.can('anything.at.all'), isTrue);
      expect(r.server.callsTo('/authz/me'), isEmpty);
      expect(r.c.read(canPickBranchProvider), isTrue);
    });

    test('the remembered answer stands in while the server answers', () async {
      final remembered = MyAuthz(
        userId: SeedIds.owner,
        epoch: 0,
        specVersion: 2,
        owner: true,
        platform: false,
        roleKinds: const ['org_admin'],
        capabilities: const [Cap.ordersRead],
        askManager: const [],
        limits: const {},
      );
      final r = Rig(
        as: Persona.owner,
        prefs: {authzPrefKey(SeedIds.owner): json.encode(remembered.toJson())},
      );
      addTearDown(r.dispose);
      final gate = r.server.hold('GET', '/authz/me');
      await r.c.read(sessionProvider.future);
      await settle();
      final before = r.c.read(authzProvider);
      expect(before.ready, isTrue);
      expect(before.can(Cap.ordersRead), isTrue);
      expect(before.can(Cap.ordersVoid), isFalse);
      gate.release();
      await settle();
      expect(r.c.read(authzProvider).can(Cap.ordersVoid), isTrue);
    });

    test('a backend without /authz/me: the role defaults', () async {
      final r = Rig(as: Persona.manager);
      addTearDown(r.dispose);
      r.server.fail(
        'GET',
        '/authz/me',
        MockResponse.notFound('Not found'),
        times: null,
      );
      await r.ready();
      final a = r.c.read(authzProvider);
      expect(a.ready, isTrue);
      expect(a.can(Cap.ordersRead), isTrue);
      expect(a.roleKinds, ['branch_manager']);
    });

    test('any other failure holds nothing, with the error', () async {
      final r = Rig(as: Persona.owner);
      addTearDown(r.dispose);
      r.server.fail('GET', '/authz/me', MockResponse.error(500, 'Boom'));
      await r.ready();
      final a = r.c.read(authzProvider);
      expect(a.ready, isFalse);
      expect(a.can(Cap.ordersRead), isFalse);
      expect(a.error, isA<ApiException>());
      await r.c.read(authzProvider.notifier).refresh();
      expect(r.c.read(authzProvider).can(Cap.ordersRead), isTrue);
    });
  });

  group('modules, onboarding, set-up', () {
    test('a two-module org; a Dawam-only org; no org = every module', () async {
      final owner = Rig(as: Persona.owner);
      addTearDown(owner.dispose);
      await owner.ready();
      expect(owner.c.read(orgModulesProvider).known, isTrue);
      expect(owner.c.read(orgModulesProvider).modules, ['pos', 'dawam']);

      final dawam = Rig(as: Persona.dawamOnly);
      addTearDown(dawam.dispose);
      await dawam.ready();
      expect(dawam.c.read(orgModulesProvider).modules, ['dawam']);

      final platform = Rig(as: Persona.platform);
      addTearDown(platform.dispose);
      await platform.ready();
      final m = platform.c.read(orgModulesProvider);
      expect(m.known, isTrue);
      expect(m.modules, OrgModule.all);
    });

    test('modules that cannot be read are not guessed', () async {
      final r = Rig(as: Persona.owner);
      addTearDown(r.dispose);
      r.server.fail(
        'GET',
        '/orgs/{id}/modules',
        MockResponse.error(500, 'Boom'),
      );
      await r.ready();
      final m = r.c.read(orgModulesProvider);
      expect(m.known, isFalse);
      expect(m.modules, isEmpty);
      expect(m.error, isA<ApiException>());
      r.c.invalidate(orgModulesQueryProvider);
      await settle();
      expect(r.c.read(orgModulesProvider).known, isTrue);
    });

    test('the onboarding gate (gate.ts)', () async {
      expect(
        sendsToOnboarding(
          role: 'org_admin',
          skipped: false,
          modules: ['pos'],
          modulesKnown: true,
          completed: false,
        ),
        isTrue,
      );
      for (final s in [
        sendsToOnboarding(
          role: 'branch_manager',
          skipped: false,
          modules: ['pos'],
          modulesKnown: true,
          completed: false,
        ),
        sendsToOnboarding(
          role: 'org_admin',
          skipped: true,
          modules: ['pos'],
          modulesKnown: true,
          completed: false,
        ),
        sendsToOnboarding(
          role: 'org_admin',
          skipped: false,
          modules: ['dawam'],
          modulesKnown: true,
          completed: false,
        ),
        sendsToOnboarding(
          role: 'org_admin',
          skipped: false,
          modules: ['pos'],
          modulesKnown: false,
          completed: false,
        ),
        sendsToOnboarding(
          role: 'org_admin',
          skipped: false,
          modules: ['pos'],
          modulesKnown: true,
          completed: true,
        ),
        sendsToOnboarding(
          role: 'org_admin',
          skipped: false,
          modules: ['pos'],
          modulesKnown: true,
          completed: null,
        ),
      ]) {
        expect(s, isFalse);
      }
      // Sabah's checklist is complete in the seed: no wizard.
      final r = Rig(as: Persona.owner);
      addTearDown(r.dispose);
      await r.ready();
      expect(r.c.read(onboardingCompletedProvider).value, isTrue);
      expect(r.c.read(sendsToOnboardingProvider), isFalse);
      // A Dawam-only owner is never asked.
      final d = Rig(as: Persona.dawamOnly);
      addTearDown(d.dispose);
      await d.ready();
      expect(d.server.callsTo('/orgs/{id}/onboarding'), isEmpty);
    });

    test(
      'an unfinished checklist sends the owner to the wizard until skipped',
      () async {
        final r = Rig(as: Persona.owner);
        addTearDown(r.dispose);
        r.server.on('GET', '/orgs/{id}/onboarding', (req) {
          return MockResponse.ok(
            OnboardingStatus(
              orgId: req.param('id'),
              completed: false,
              canComplete: false,
              recipeCoverage: 0,
              steps: const [],
            ),
          );
        });
        await r.ready();
        expect(r.c.read(sendsToOnboardingProvider), isTrue);
        r.c.read(onboardingSkippedProvider.notifier).skip();
        await settle();
        expect(r.c.read(sendsToOnboardingProvider), isFalse);
      },
    );

    test(
      'the Dawam set-up checklist is read from real data (setup.ts)',
      () async {
        final r = Rig(as: Persona.dawamOnly);
        addTearDown(r.dispose);
        await r.ready();
        expect(r.c.read(setupEnabledProvider), isTrue);
        final p = r.c.read(setupProgressProvider);
        expect(p.ready, isTrue);
        final api = DashboardApi(r.gw.transport);
        final branches = await api.branches.listBranches(
          orgId: SeedIds.nakhlaOrg,
        );
        final employees = await api.staff.listEmployees(
          employmentStatus: 'active',
        );
        final shifts = await api.staff.listWorkShifts();
        final rules = await api.staff.getAttendanceSettings();
        expect(
          p.done[SetupStep.branches],
          branches.isNotEmpty && branches.every(branchPinned),
        );
        expect(
          p.done[SetupStep.employees],
          employees.any((e) => e.employmentStatus == 'active'),
        );
        expect(p.done[SetupStep.shifts], shifts.any((s) => s.isActive));
        expect(p.done[SetupStep.rules], rules.rulesSavedAt != null);
        expect(p.complete, p.count == 4);
        expect(r.c.read(authzStateProvider).setupIncomplete, !p.complete);
        // A manager without hr.rules.edit is never asked.
        final m = Rig(as: Persona.manager);
        addTearDown(m.dispose);
        await m.ready();
        expect(m.c.read(setupEnabledProvider), isFalse);
        expect(m.c.read(setupProgressProvider).ready, isFalse);
        expect(m.server.callsTo('/staff/work-shifts'), isEmpty);
      },
    );

    test('setupProgress counts real data only', () {
      Branch b(String id, {double? lat, double? lng, int? r}) =>
          Branch.fromJson({
            'id': id,
            'org_id': 'o',
            'name': id,
            'timezone': 'Africa/Cairo',
            'is_active': true, //
            'old_bill_hours': 3,
            'created_at': '2026-01-01T00:00:00Z',
            'updated_at': '2026-01-01T00:00:00Z',
            'latitude': lat, 'longitude': lng, 'geo_radius_meters': r,
          });
      final none = setupProgress(const SetupData());
      expect(none.ready, isFalse);
      expect(none.count, 0);
      final all = setupProgress(
        SetupData(
          branches: [b('a', lat: 30, lng: 31, r: 200)],
          activeEmployeeStatuses: const ['active'],
          shiftsActive: const [false, true],
          rulesKnown: true,
          rulesSavedAt: DateTime.utc(2026),
        ),
      );
      expect(all.ready, isTrue);
      expect(all.complete, isTrue);
      final unpinned = setupProgress(
        SetupData(
          branches: [b('a', lat: 30, lng: 31, r: 200), b('b')],
          activeEmployeeStatuses: const [],
          shiftsActive: const [],
          rulesKnown: true,
        ),
      );
      expect(unpinned.done.values.every((v) => !v), isTrue);
      expect(unpinned.ready, isTrue);
    });
  });

  group('scope', () {
    String stored(String? org, String? branch) =>
        json.encode({'org': org, 'branch': branch});

    test(
      "a branch stored for another org is dropped (the 'Branch not found' bug)",
      () async {
        final r = Rig(
          as: Persona.owner,
          prefs: {
            ScopePrefKeys.branch: stored(SeedIds.nakhlaOrg, SeedIds.dokki),
          },
        );
        addTearDown(r.dispose);
        await r.ready();
        expect(r.c.read(scopeProvider).branchId, isNull);
        expect(json.decode(r.prefs.values[ScopePrefKeys.branch]!), {
          'org': SeedIds.sabahOrg,
          'branch': null,
        });
        expect(r.gw.branchId, isNull);
        expect(r.gw.orgId, SeedIds.sabahOrg);
        expect(r.c.read(currentScopeProvider).scopeBranchId, allBranchesId);
      },
    );

    test("a stored branch the org's list no longer has is dropped", () async {
      final r = Rig(
        as: Persona.owner,
        prefs: {
          ScopePrefKeys.branch: stored(SeedIds.sabahOrg, 'deleted-branch'),
        },
      );
      addTearDown(r.dispose);
      await r.ready();
      expect(r.c.read(activeBranchesProvider), isNotNull);
      expect(r.c.read(scopeProvider).branchId, isNull);
      expect(
        json.decode(r.prefs.values[ScopePrefKeys.branch]!)['branch'],
        isNull,
      );
    });

    test('a valid stored branch is kept and sent', () async {
      final r = Rig(
        as: Persona.owner,
        prefs: {ScopePrefKeys.branch: stored(SeedIds.sabahOrg, SeedIds.maadi)},
      );
      addTearDown(r.dispose);
      await r.ready();
      expect(r.c.read(scopeProvider).branchId, SeedIds.maadi);
      expect(r.gw.branchId, SeedIds.maadi);
      final scope = r.c.read(currentScopeProvider);
      expect(scope.isAllBranches, isFalse);
      expect(scope.scopeBranchId, SeedIds.maadi);
      expect(
        r.c.read(activeBranchesProvider)!.map((b) => b.id),
        SeedIds.sabahBranches,
      );
    });

    test('picking a branch persists it with its org', () async {
      final r = Rig(as: Persona.owner);
      addTearDown(r.dispose);
      await r.ready();
      await r.c.read(scopeProvider.notifier).setBranch(SeedIds.zamalek);
      expect(r.c.read(scopeProvider).branchId, SeedIds.zamalek);
      expect(json.decode(r.prefs.values[ScopePrefKeys.branch]!), {
        'org': SeedIds.sabahOrg,
        'branch': SeedIds.zamalek,
      });
      expect(r.gw.scopeCalls.last, (
        orgId: SeedIds.sabahOrg,
        branchId: SeedIds.zamalek,
      ));
      await r.c.read(scopeProvider.notifier).setBranch(null);
      expect(r.c.read(currentScopeProvider).isAllBranches, isTrue);
    });

    test(
      'a platform admin picks the org; a new org resets the branch',
      () async {
        final r = Rig(as: Persona.platform);
        addTearDown(r.dispose);
        await r.ready();
        expect(r.c.read(orgIdProvider), isNull);
        final orgs = await r.c.read(orgsProvider.future);
        expect(orgs.map((o) => o.name), ['Nakhla Bakery', 'Sabah Coffee']);
        await r.c.read(selectedOrgProvider.notifier).select(SeedIds.sabahOrg);
        await settle();
        expect(r.c.read(orgIdProvider), SeedIds.sabahOrg);
        expect(r.server.platformOrgId, SeedIds.sabahOrg);
        await r.c.read(scopeProvider.notifier).setBranch(SeedIds.maadi);
        expect(r.c.read(scopeProvider).branchId, SeedIds.maadi);
        await r.c.read(selectedOrgProvider.notifier).select(SeedIds.nakhlaOrg);
        await settle();
        expect(r.c.read(orgIdProvider), SeedIds.nakhlaOrg);
        expect(r.c.read(scopeProvider).branchId, isNull);
        expect(r.gw.branchId, isNull);
        expect(
          r.c.read(activeBranchesProvider)!.map((b) => b.id),
          SeedIds.nakhlaBranches,
        );
        expect(r.c.read(orgModulesProvider).modules, ['dawam']);
        // Remembered for next launch.
        expect(
          json.decode(r.prefs.values[ScopePrefKeys.org]!)['id'],
          SeedIds.nakhlaOrg,
        );
      },
    );

    test("a branch manager's requests carry their own branch", () async {
      final r = Rig(as: Persona.manager);
      addTearDown(r.dispose);
      await r.ready();
      expect(r.c.read(scopeProvider).branchId, isNull);
      expect(r.gw.branchId, SeedIds.zamalek);
    });

    test('period: the last preset is remembered, custom never is', () async {
      final r = Rig(as: Persona.owner);
      addTearDown(r.dispose);
      await r.ready();
      expect(r.c.read(currentScopeProvider).preset, ScopePreset.last30Days);
      await r.c.read(scopeProvider.notifier).setPreset(ScopePreset.last7Days);
      expect(r.prefs.values[ScopePrefKeys.preset], '7d');
      final again = Rig(as: Persona.owner, prefs: Map.of(r.prefs.values));
      addTearDown(again.dispose);
      await again.ready();
      expect(again.c.read(currentScopeProvider).preset, ScopePreset.last7Days);
      final custom = Rig(
        as: Persona.owner,
        prefs: {ScopePrefKeys.preset: 'custom'},
      );
      addTearDown(custom.dispose);
      await custom.ready();
      expect(
        custom.c.read(currentScopeProvider).preset,
        ScopePreset.last30Days,
      );
    });

    test(
      'period: presets in the branch zone, custom days, granularity',
      () async {
        final r = Rig(as: Persona.owner);
        addTearDown(r.dispose);
        await r.ready();
        // MockClock: 2026-10-08 10:00 Cairo (UTC+3).
        final n = r.c.read(scopeProvider.notifier);
        await n.setPreset(ScopePreset.today);
        var s = r.c.read(currentScopeProvider);
        expect(s.from, '2026-10-07T21:00:00.000Z');
        expect(s.to, '2026-10-08T20:59:59.999Z');
        expect(s.granularity, 'hourly');
        expect(s.timezone, 'Africa/Cairo');
        await n.setCustomDays(DateTime(2026, 9, 1), DateTime(2026, 9, 30));
        s = r.c.read(currentScopeProvider);
        expect(s.preset, ScopePreset.custom);
        expect(s.from, '2026-08-31T21:00:00.000Z');
        expect(s.to, '2026-09-30T20:59:59.999Z');
        expect(s.granularity, 'daily');
        await n.setPreset(ScopePreset.monthToDate);
        expect(r.c.read(currentScopeProvider).from, '2026-09-30T21:00:00.000Z');
        expect(r.c.read(scopeProvider).custom, isNull);
      },
    );

    test("the zone: the branch's, remembered for the next launch", () async {
      final r = Rig(
        as: Persona.owner,
        prefs: {ScopePrefKeys.timezone: 'Asia/Dubai'},
      );
      addTearDown(r.dispose);
      // Before anything answers, the remembered zone.
      expect(r.c.read(activeTimezoneProvider), 'Asia/Dubai');
      await r.ready();
      expect(r.c.read(activeTimezoneProvider), 'Africa/Cairo');
      expect(r.prefs.values[ScopePrefKeys.timezone], 'Africa/Cairo');
      expect(r.c.read(formatProvider).timezone, 'Africa/Cairo');
    });

    test('resolveTimezone: branch, org, the first branch zone, Cairo', () {
      expect(
        resolveTimezone(branchTz: 'Asia/Dubai', orgTz: 'UTC'),
        'Asia/Dubai',
      );
      expect(resolveTimezone(orgTz: 'UTC'), 'UTC');
      expect(
        resolveTimezone(branchZones: [null, '', 'Asia/Riyadh']),
        'Asia/Riyadh',
      );
      expect(resolveTimezone(), appTimezone);
    });
  });
}
