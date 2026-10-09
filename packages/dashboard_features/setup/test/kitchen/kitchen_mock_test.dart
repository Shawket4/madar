// The kitchen mock handlers against the backend's rules
// (`MadarRust/src/kitchen/stations.rs`), and the routing page's pure rules
// (`KitchenRouting`), with hand-worked expectations.
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_setup/src/kitchen/kitchen_data.dart';
import 'package:dashboard_setup/src/mock/kitchen_mock.dart'
    show kitchenEffectiveMode;
import 'package:flutter_test/flutter_test.dart';

import 'kitchen_support.dart';

Future<ApiException> _refusal(Future<Object?> call) async {
  try {
    await call;
  } on ApiException catch (e) {
    return e;
  }
  fail('expected a refusal');
}

void main() {
  late MockDb db;
  late KitchenApi api;
  setUp(() {
    final m = setupMockServer();
    db = m.db;
    api = DashboardApi(m.server).kitchen;
  });

  test('stations: by sort order then name; another branch is refused for a '
      'branch manager', () async {
    final list = await api.listStations(branchId: SeedIds.zamalek);
    expect([for (final s in list) s.name], ['Bar', 'Kitchen', 'Pastry']);
    final m = setupMockServer(persona: Persona.manager);
    final e = await _refusal(
      DashboardApi(m.server).kitchen.listStations(branchId: SeedIds.heliopolis),
    );
    expect(e.status, 403);
    final l = setupMockServer(persona: Persona.limited);
    final denied = await _refusal(
      DashboardApi(l.server).kitchen.listStations(branchId: SeedIds.maadi),
    );
    expect(denied.status, 403);
  });

  test('effective mode: the override, else KDS with an active station, '
      'else the till', () async {
    expect(kitchenEffectiveMode(db, SeedIds.zamalek), 'kds');
    expect(kitchenEffectiveMode(db, SeedIds.heliopolis), 'both');
    expect(kitchenEffectiveMode(db, SeedIds.maadi), 'till');
    expect(kitchenEffectiveMode(db, SeedIds.newCairo), 'off');
    for (final s in db[KitchenSeed.stationsTable].rows) {
      if (s['branch_id'] == SeedIds.zamalek) s['is_active'] = false;
    }
    expect(kitchenEffectiveMode(db, SeedIds.zamalek), 'till');
    final bad = await _refusal(
      api.setRoutingMode(
        body: SetRoutingModeRequest(branchId: SeedIds.zamalek, mode: 'printer'),
      ),
    );
    expect(bad.status, 400);
    final ok = await api.setRoutingMode(
      body: SetRoutingModeRequest(
        branchId: SeedIds.heliopolis,
        explicitNulls: const {'mode'},
      ),
    );
    expect(ok.mode, isNull);
    expect(ok.effective, 'kds');
  });

  test('create: a blank name is 400; a new default takes the flag', () async {
    final blank = await _refusal(
      api.createStation(
        body: CreateStationRequest(branchId: SeedIds.zamalek, name: '  '),
      ),
    );
    expect(blank.status, 400);
    final s = await api.createStation(
      body: CreateStationRequest(
        branchId: SeedIds.zamalek,
        name: ' Grill ',
        isDefault: true,
        printerBrand: PrinterBrand.star,
        printerPort: 9100,
      ),
    );
    expect(s.name, 'Grill');
    expect(s.isActive, isTrue);
    expect(s.printerBrand, PrinterBrand.star);
    final defaults = [
      for (final r in db[KitchenSeed.stationsTable].rows)
        if (r['branch_id'] == SeedIds.zamalek && r['is_default'] == true)
          r['name'],
    ];
    expect(defaults, ['Grill']);
  });

  test('update: only what is sent changes; an explicit null clears the '
      'printer; a deleted station is 404', () async {
    final bar = stationId('zamalek', 'bar');
    final s = await api.updateStation(
      id: bar,
      body: const UpdateStationRequest(isActive: false),
    );
    expect(s.isActive, isFalse);
    expect(s.printerBrand, PrinterBrand.epson);
    final cleared = await api.updateStation(
      id: bar,
      body: const UpdateStationRequest(
        explicitNulls: {'printer_brand', 'printer_ip', 'printer_port'},
      ),
    );
    expect(cleared.printerBrand, isNull);
    expect(cleared.printerIp, isNull);
    await api.deleteStation(id: bar);
    final gone = await _refusal(
      api.updateStation(id: bar, body: const UpdateStationRequest(name: 'x')),
    );
    expect(gone.status, 404);
  });

  test('routes: upsert by (branch, category); another branch\'s station is '
      '400; delete removes it', () async {
    await api.putCategoryRoute(
      body: CategoryRouteInput(
        branchId: SeedIds.zamalek,
        categoryId: MockSeed.categoryId('hot'),
        stationId: stationId('zamalek', 'kitchen'),
      ),
    );
    final foreign = await _refusal(
      api.putItemRoute(
        body: ItemRouteInput(
          branchId: SeedIds.zamalek,
          menuItemId: MockSeed.menuItemId('latte'),
          stationId: stationId('heliopolis', 'bar'),
        ),
      ),
    );
    expect(foreign.status, 400);
    final routes = await api.listRoutes(branchId: SeedIds.zamalek);
    expect(
      routes.categories
          .where((r) => r.categoryId == MockSeed.categoryId('hot'))
          .single
          .stationId,
      stationId('zamalek', 'kitchen'),
    );
    expect(routes.categories, hasLength(6));
    expect(routes.items, hasLength(2));
    await api.deleteCategoryRoute(
      branchId: SeedIds.zamalek,
      categoryId: MockSeed.categoryId('hot'),
    );
    final after = await api.listRoutes(branchId: SeedIds.zamalek);
    expect(after.categories, hasLength(5));
  });

  test('catalog: by name, 50 a page by default, searched, 500 at most', () async {
    final m = setupMockServer();
    final menu = DashboardApi(m.server).menu;
    final all = await menu.listMenuCatalog(
      orgId: SeedIds.sabahOrg,
      perPage: 1000,
    );
    expect(all.perPage, 500);
    expect(all.total, 40);
    final names = [for (final i in all.data) i.name];
    expect(names, [...names]..sort());
    final first = await menu.listMenuCatalog(orgId: SeedIds.sabahOrg);
    expect(first.perPage, 50);
    final s = await menu.listMenuCatalog(
      orgId: SeedIds.sabahOrg,
      search: ' COOKIE ',
    );
    expect([for (final i in s.data) i.name], ['Chocolate Chip Cookie']);
    expect(s.totalPages, 1);
  });

  test('KitchenRouting: only active stations are named or offered', () {
    final stations = [
      for (final s in KitchenSeed.stations)
        if (s.branchId == SeedIds.zamalek) s,
    ];
    final routing = KitchenRouting(
      stations: stations,
      routes: StationRoutes(
        categories: [
          CategoryRoute(
            categoryId: 'bakery',
            stationId: stationId('zamalek', 'pastry'),
          ),
          CategoryRoute(
            categoryId: 'hot',
            stationId: stationId('zamalek', 'bar'),
          ),
        ],
        items: const [],
      ),
    );
    expect([for (final s in routing.active) s.name], ['Bar', 'Kitchen']);
    expect(routing.stationName(routing.byCategory['hot']), 'Bar');
    expect(routing.stationName(routing.byCategory['bakery']), isNull);
    expect(routing.selectValue(null), kitchenUnassigned);
    expect(routing.selectValue(routing.byCategory['bakery']), isNull);
    expect(
      routing.selectValue(routing.byCategory['hot']),
      stationId('zamalek', 'bar'),
    );
    expect(printerBrandLabel(PrinterBrand.epson), 'Epson');
    expect(printerBrandLabel(PrinterBrand.fromJson('zebra')), 'Zebra');
    expect(kitchenName('Bar', {'ar': 'البار'}, 'ar'), 'البار');
    expect(kitchenName('Bar', {'ar': 'البار'}, 'en'), 'Bar');
  });
}
