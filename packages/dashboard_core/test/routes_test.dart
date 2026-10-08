import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/mock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

AuthzState _state(
  Authz authz, {
  List<String> modules = OrgModule.all,
  bool setupIncomplete = false,
}) => AuthzState(
  authz: authz,
  modules: OrgModulesState(modules: modules, known: true),
  setup: setupIncomplete
      ? const SetupProgress(ready: true, done: {}, count: 1, complete: false)
      : SetupProgress.unknown,
  sendsToOnboarding: false,
);

Authz _holding(List<String> caps) => Authz.from(
  MyAuthz(
    userId: 'u',
    epoch: 0,
    specVersion: 0,
    owner: false,
    platform: false,
    roleKinds: const [],
    capabilities: caps,
    askManager: const [],
    limits: const {},
  ),
);

Widget _page(BuildContext context, Object state) => const SizedBox();

void main() {
  group('DashRoute', () {
    test('any-of capabilities, platform-only, setup-only', () {
      const orders = DashRoute(
        path: '/orders',
        caps: [Cap.ordersRead],
        module: 'pos',
        titleKey: 'nav.orders',
      );
      expect(orders.allows(_state(_holding([Cap.ordersRead]))), isTrue);
      expect(orders.allows(_state(_holding([Cap.tillRead]))), isFalse);
      expect(orders.allows(_state(Authz.platformAdmin())), isTrue);

      const anyone = DashRoute(path: '/settings');
      expect(anyone.allows(_state(_holding([]))), isTrue);

      const orgs = DashRoute(path: '/orgs', platformOnly: true);
      expect(orgs.allows(_state(_holding(Cap.all))), isFalse);
      expect(orgs.allows(_state(Authz.platformAdmin())), isTrue);

      const setup = DashRoute(
        path: '/staff/setup',
        caps: [Cap.hrRulesEdit],
        setupOnly: true,
      );
      expect(setup.allows(_state(_holding([Cap.hrRulesEdit]))), isFalse);
      expect(
        setup.allows(
          _state(_holding([Cap.hrRulesEdit]), setupIncomplete: true),
        ),
        isTrue,
      );
      expect(
        setup.allows(_state(_holding([]), setupIncomplete: true)),
        isFalse,
      );
    });

    test('tabs hide what the person cannot read or the org has off', () {
      const r = DashRoute(
        path: '/reports/operations',
        tabs: [
          DashRouteTab(id: 'overview', labelKey: 'reports.tabs.overview'),
          DashRouteTab(
            id: 'tables',
            labelKey: 'reports.tabs.tables',
            caps: [Cap.floorLayoutRead],
          ),
          DashRouteTab(
            id: 'staff',
            labelKey: 'reports.tabs.staff',
            module: 'dawam',
          ),
        ],
      );
      expect(
        r
            .visibleTabs(_state(_holding([Cap.ordersRead]), modules: ['pos']))
            .map((t) => t.id),
        ['overview'],
      );
      expect(
        r.visibleTabs(_state(_holding([Cap.floorLayoutRead]))).map((t) => t.id),
        ['overview', 'tables', 'staff'],
      );
    });
  });

  group('DashArea', () {
    test('supplement asset keys follow the package', () {
      expect(DashArea.supplementAssets('sell'), [
        'packages/dashboard_sell/assets/i18n/en.json',
        'packages/dashboard_sell/assets/i18n/ar.json',
      ]);
      expect(languageOfAsset(DashArea.supplementAssets('sell').last), 'ar');
    });

    test(
      'routes flatten with full paths; mocks register on the server',
      () async {
        var registered = false;
        final area = DashArea(
          key: 'catalog_menu',
          routes: [
            DashRoute(
              path: '/menu/items',
              builder: _page,
              children: [DashRoute(path: ':itemId', builder: _page)],
            ),
            const DashRoute(path: '/menu/groups'),
          ],
          registerMocks: (server, db) {
            registered = true;
            server.on(
              'GET',
              '/menu-items',
              (req) => MockResponse.json(200, const <Object>[]),
            );
          },
          i18nSupplements: DashArea.supplementAssets('catalog_menu'),
        );
        expect(flattenRoutes([area]).map((e) => e.$1), [
          '/menu/items',
          '/menu/items/:itemId',
          '/menu/groups',
        ]);
        final db = MockDb.seeded();
        final server = MockServer(clock: db.clock);
        area.registerMocks!(server, db);
        expect(registered, isTrue);
        expect(server.handles('GET', '/menu-items'), isTrue);
      },
    );
  });

  test('apiProvider is the generated client over the transport', () async {
    final db = MockDb.seeded();
    final server = MockServer(clock: db.clock);
    registerCoreMocks(server, db);
    final gw = MockSessionGateway(server, signedInAs: Persona.owner);
    final c = ProviderContainer(
      overrides: [transportProvider.overrideWithValue(gw.transport)],
    );
    addTearDown(c.dispose);
    final api = c.read(apiProvider);
    expect(api.transport, same(gw.transport));
    final modules = await api.orgs.getOrgModules(id: SeedIds.sabahOrg);
    expect(modules.modules, ['pos', 'dawam']);
  });
}
