// The pricing unit's handlers against hand-worked figures from the seed: the
// add-on catalog (the shared groups' options, the Milk group's 6 among them) and
// the channel add-on overrides (Zamalek hides almond milk for In-mall).
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_menu/src/area_seed.dart';
import 'package:dashboard_catalog_menu/src/mock/register.dart';
import 'package:flutter_test/flutter_test.dart';

({MockServer server, MockDb db, DashboardApi api}) _server([
  Persona persona = Persona.owner,
]) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  registerCatalogMenuMocks(server, db);
  return (server: server, db: db, api: DashboardApi(server));
}

Future<int> _status(Future<Object?> call) async {
  try {
    await call;
    return 200;
  } on ApiException catch (e) {
    return e.status;
  }
}

void main() {
  final org = SeedIds.sabahOrg;

  group('GET /addon-items/catalog', () {
    test('by type then name, paged', () async {
      final s = _server();
      final api = s.api;
      final all = await api.menu.listAddonCatalog(orgId: org, perPage: 500);
      final seeded = [
        for (final a in CatalogMenuData(s.db).addonItems())
          if (a['org_id'] == org) a,
      ];
      expect(all.total, seeded.length);
      expect(all.totalPages, 1);
      final keys = [for (final a in all.data) (a.addonType, a.name.toLowerCase())];
      final sorted = [...keys]
        ..sort((a, b) {
          final c = a.$1.compareTo(b.$1);
          return c != 0 ? c : a.$2.compareTo(b.$2);
        });
      expect(keys, sorted);
      final milk = [
        for (final a in all.data)
          if (a.addonType == 'milk_type') a.name,
      ];
      expect(milk, [
        'Almond milk',
        'Coconut milk',
        'Full cream',
        'Lactose-free',
        'Oat milk',
        'Skimmed',
      ]);
      final last = (all.total / 5).ceil();
      final page = await api.menu.listAddonCatalog(
        orgId: org,
        page: last,
        perPage: 5,
      );
      expect(page.totalPages, last);
      expect(page.data.map((a) => a.name), [
        for (final a in all.data.skip((last - 1) * 5)) a.name,
      ]);
    });

    test('search is a trimmed, case-blind contains', () async {
      final api = _server().api;
      final r = await api.menu.listAddonCatalog(orgId: org, search: ' MILK ');
      expect(r.data.map((a) => a.name), [
        'Almond milk',
        'Coconut milk',
        'Oat milk',
      ]);
      final none = await api.menu.listAddonCatalog(orgId: org, search: 'qq');
      expect(none.total, 0);
      expect(none.totalPages, 0);
    });

    test('the branch filter and the overridden-first sort', () async {
      final api = _server().api;
      final r = await api.menu.listAddonCatalog(
        orgId: org,
        branchId: SeedIds.zamalek,
        sort: 'overridden',
      );
      expect(r.data.first.name, 'Oat milk');
      final only = await api.menu.listAddonCatalog(
        orgId: org,
        branchId: SeedIds.zamalek,
        overridden: true,
      );
      expect(only.data.map((a) => a.name), ['Oat milk']);
    });

    test('refusals: another org 403', () async {
      final api = _server(Persona.dawamOnly).api;
      expect(await _status(api.menu.listAddonCatalog(orgId: org)), 403);
    });
  });

  group('GET /delivery/channel-addon-overrides', () {
    test('one branch, one channel', () async {
      final api = _server().api;
      final mall = await api.delivery.listChannelAddonOverrides(
        branchId: SeedIds.zamalek,
        channel: 'in_mall',
      );
      expect(mall, hasLength(1));
      expect(mall.single.addonItemId, MenuSeedIds.option('milk', 'almond'));
      expect(mall.single.isAvailable, isFalse);
      expect(mall.single.priceOverride, isNull);
      final outside = await api.delivery.listChannelAddonOverrides(
        branchId: SeedIds.zamalek,
        channel: 'outside',
      );
      expect(outside, isEmpty);
    });

    test('refusals: bad channel 400, unknown branch 404, another branch '
        '403', () async {
      final owner = _server().api;
      expect(
        await _status(
          owner.delivery.listChannelAddonOverrides(
            branchId: SeedIds.zamalek,
            channel: 'drive_thru',
          ),
        ),
        400,
      );
      expect(
        await _status(
          owner.delivery.listChannelAddonOverrides(
            branchId: mockUuid('nowhere'),
            channel: 'outside',
          ),
        ),
        404,
      );
      final manager = _server(Persona.manager).api;
      expect(
        await _status(
          manager.delivery.listChannelAddonOverrides(
            branchId: SeedIds.maadi,
            channel: 'outside',
          ),
        ),
        403,
      );
    });

    test('a write through PUT /menu-price-overrides shows in the lists', () async {
      final api = _server().api;
      final oat = MenuSeedIds.option('milk', 'oat');
      await api.menu.putPriceOverride(
        body: PriceOverrideRequest(
          scope: 'branch_channel',
          branchId: SeedIds.zamalek,
          channel: 'pickup',
          targetType: 'modifier_option',
          targetId: oat,
          price: 3500,
        ),
      );
      final pickup = await api.delivery.listChannelAddonOverrides(
        branchId: SeedIds.zamalek,
        channel: 'pickup',
      );
      expect(pickup.single.addonItemId, oat);
      expect(pickup.single.priceOverride, 3500);
      expect(pickup.single.isAvailable, isNull);
    });
  });
}
