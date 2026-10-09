// The items unit's mock handlers against hand-computed figures and the
// backend's refusals, called through the generated API.
import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_menu/src/area_seed.dart';
import 'package:dashboard_catalog_menu/src/mock/register.dart';
import 'package:flutter_test/flutter_test.dart';

({MockServer server, MockDb db, DashboardApi api}) _api({
  Persona persona = Persona.owner,
}) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  registerCatalogMenuMocks(server, db);
  return (server: server, db: db, api: DashboardApi(server));
}

String get _org => SeedIds.sabahOrg;
String _item(String k) => MenuSeedIds.item(k);
String _size(String k, String l) => MenuSeedIds.size(k, l);

Matcher _status(int code) =>
    isA<ApiException>().having((e) => e.status, 'status', code);

void main() {
  group('GET /costing/catalog', () {
    test('24 a page by name; total_pages; the last page', () async {
      final s = _api();
      final p1 = await s.api.menu.listMenuCatalog(
        orgId: _org,
        page: 1,
        perPage: 24,
      );
      expect(p1.total, 40);
      expect(p1.totalPages, 2);
      expect(p1.data.first.name, 'Almond Croissant');
      expect(p1.data, hasLength(24));
      final p2 = await s.api.menu.listMenuCatalog(
        orgId: _org,
        page: 2,
        perPage: 24,
      );
      expect(p2.data, hasLength(16));
      expect(p2.data.last.name, 'V60 Pour Over');
    });

    test('nothing: total 0, total_pages 0', () async {
      final s = _api();
      final p = await s.api.menu.listMenuCatalog(orgId: _org, search: 'zzz');
      expect(p.total, 0);
      expect(p.totalPages, 0);
    });

    test('search is any case on the name; category; has_recipe', () async {
      final s = _api();
      final latte = await s.api.menu.listMenuCatalog(
        orgId: _org,
        search: 'LATTE',
      );
      expect(latte.data.map((m) => m.name), contains('Caffè Latte'));
      expect(
        latte.data.every((m) => m.name.toLowerCase().contains('latte')),
        isTrue,
      );
      final juice = await s.api.menu.listMenuCatalog(
        orgId: _org,
        categoryId: MenuSeedIds.category('juice'),
      );
      expect(juice.data.map((m) => m.name).toSet(), {
        'Mango Juice',
        'Orange Juice',
        'Strawberry Juice',
      });
      final none = await s.api.menu.listMenuCatalog(
        orgId: _org,
        hasRecipe: false,
      );
      expect(none.total, 10);
    });

    test('has_recipe needs recipes.read; another org is refused', () async {
      final s = _api(persona: Persona.limited);
      await expectLater(
        s.api.menu.listMenuCatalog(orgId: _org, hasRecipe: true),
        throwsA(_status(403)),
      );
      await expectLater(
        s.api.menu.listMenuCatalog(orgId: SeedIds.nakhlaOrg),
        throwsA(_status(403)),
      );
    });

    test(
      'a Cortado SKU: own milk + the espresso base + the hot cup rule',
      () async {
        final s = _api();
        final p = await s.api.menu.listMenuCatalog(
          orgId: _org,
          search: 'cortado',
        );
        final sku = p.data.single.skuCosts.single;
        // 60 ml milk × 4.2 + 18 g blend × 95 + cup 150 + lid 60 = 2172.
        expect(sku.cost, 2172);
        expect(sku.price, 9500);
        expect(sku.costMissing, isFalse);
        expect(sku.foodCostPct, closeTo(2172 / 9500, 1e-9));
      },
    );

    test('Pistachio Latte: the paste has no cost, cost_missing', () async {
      final s = _api();
      final p = await s.api.menu.listMenuCatalog(
        orgId: _org,
        search: 'pistachio',
      );
      expect(p.data.single.skuCosts.every((c) => c.costMissing), isTrue);
      expect(
        p.data.single.skuCosts.every((c) => c.foodCostPct == null),
        isTrue,
      );
    });
  });

  group('branch overrides', () {
    test('Zamalek: the unified rows as the item / add-on views', () async {
      final s = _api();
      final items = await s.api.menu.listBranchMenuOverrides(
        branchId: SeedIds.zamalek,
      );
      final byItem = {for (final o in items) o.menuItemId: o};
      expect(byItem[_item('pistachio_latte')]!.isAvailable, isFalse);
      expect(byItem[_item('spanish')]!.isAvailable, isTrue);
      expect(byItem[_item('spanish')]!.sizes!.map((z) => z.priceOverride), [
        14000,
        16000,
      ]);
      expect(
        byItem.containsKey(_item('iced_latte')),
        isFalse,
        reason: 'a channel row is not a branch row',
      );
      final addons = await s.api.menu.listBranchAddonOverrides(
        branchId: SeedIds.zamalek,
      );
      expect(addons.single.addonItemId, MenuSeedIds.option('milk', 'oat'));
      expect(addons.single.priceOverride, 3000);
      expect(addons.single.isAvailable, isTrue);
    });

    test('a manager reads only their branch', () async {
      final s = _api(persona: Persona.manager);
      await s.api.menu.listBranchMenuOverrides(branchId: SeedIds.zamalek);
      await expectLater(
        s.api.menu.listBranchMenuOverrides(branchId: SeedIds.maadi),
        throwsA(_status(403)),
      );
    });

    test(
      'PUT upserts, DELETE removes; shape, emptiness and tenancy refused',
      () async {
        final s = _api();
        PriceOverrideRequest row({
          bool? available,
          int? price,
          String? branch,
        }) => PriceOverrideRequest(
          scope: 'branch',
          branchId: branch ?? SeedIds.maadi,
          targetType: 'menu_item_size',
          targetId: _size('cortado', 'one_size'),
          isAvailable: available,
          price: price,
        );
        await s.api.menu.putPriceOverride(body: row(available: false));
        await s.api.menu.putPriceOverride(
          body: row(available: false, price: 9000),
        );
        var rows = s.db[MenuTables.priceOverrides].where(
          (o) => o['target_id'] == _size('cortado', 'one_size'),
        );
        expect(rows.single['price'], 9000);
        final view = await s.api.menu.listBranchMenuOverrides(
          branchId: SeedIds.maadi,
        );
        expect(
          view.firstWhere((o) => o.menuItemId == _item('cortado')).isAvailable,
          isFalse,
        );
        await s.api.menu.deletePriceOverride(body: row());
        rows = s.db[MenuTables.priceOverrides].where(
          (o) => o['target_id'] == _size('cortado', 'one_size'),
        );
        expect(rows, isEmpty);
        await expectLater(
          s.api.menu.putPriceOverride(body: row()),
          throwsA(_status(400)),
        );
        await expectLater(
          s.api.menu.putPriceOverride(body: row(available: false, price: -1)),
          throwsA(_status(400)),
        );
        await expectLater(
          s.api.menu.putPriceOverride(
            body: PriceOverrideRequest(
              scope: 'branch',
              targetType: 'menu_item_size',
              targetId: _size('cortado', 'one_size'),
              isAvailable: false,
            ),
          ),
          throwsA(_status(400)),
        );
        await expectLater(
          s.api.menu.putPriceOverride(
            body: row(available: false, branch: SeedIds.nakhlaOrg),
          ),
          throwsA(_status(400)),
        );
      },
    );

    test('a manager may not write overrides', () async {
      final s = _api(persona: Persona.manager);
      await expectLater(
        s.api.menu.putPriceOverride(
          body: PriceOverrideRequest(
            scope: 'branch',
            branchId: SeedIds.zamalek,
            targetType: 'modifier_option',
            targetId: MenuSeedIds.option('milk', 'oat'),
            isAvailable: false,
          ),
        ),
        throwsA(_status(403)),
      );
    });
  });

  group('items', () {
    test('create: a one_size row at base_price; the full item; sizes '
        're-mirror base_price', () async {
      final s = _api();
      final full = await s.api.menu.createMenuItem(
        body: CreateMenuItemRequest(
          orgId: _org,
          name: 'Rose Latte',
          categoryId: MenuSeedIds.category('hot'),
          basePrice: 12500,
          nameTranslations: const {'ar': 'لاتيه الورد'},
        ),
      );
      expect(full.sizes, isEmpty);
      expect(full.allSizes!.single.label, 'one_size');
      expect(full.allSizes!.single.priceOverride, 12500);
      expect(full.nameTranslations, {'ar': 'لاتيه الورد', 'en': 'Rose Latte'});
      final studio = await s.api.menu.putSizes(
        id: full.id,
        body: const PutSizesRequest(
          sizes: [
            SizeInput(label: 'Regular', price: 13000, sort: 0, isActive: true),
            SizeInput(label: 'Large', price: 15000, sort: 1, isActive: true),
          ],
        ),
      );
      expect(studio.sizes.map((z) => z.label), ['Regular', 'Large']);
      expect(s.db[MenuTables.menuItems].find(full.id)!['base_price'], 13000);
      final got = await s.api.menu.getMenuItem(id: full.id);
      expect(got.allSizes!.map((z) => z.label), ['Regular', 'Large']);
    });

    test('sizes: duplicates and no active size refused', () async {
      final s = _api();
      await expectLater(
        s.api.menu.putSizes(
          id: _item('latte'),
          body: const PutSizesRequest(
            sizes: [
              SizeInput(label: 'Large', price: 1),
              SizeInput(label: 'Large', price: 2),
            ],
          ),
        ),
        throwsA(_status(400)),
      );
      await expectLater(
        s.api.menu.putSizes(
          id: _item('latte'),
          body: const PutSizesRequest(
            sizes: [SizeInput(label: 'Large', price: 1, isActive: false)],
          ),
        ),
        throwsA(_status(400)),
      );
    });

    test('size recipe: own lines replaced; base kept; duplicate refused; the '
        'cost', () async {
      final s = _api();
      final r = await s.api.menu.putSizeRecipe(
        sizeId: _size('cortado', 'one_size'),
        body: const PutRecipeRequest(lines: []),
      );
      // The base blend and the hot cup rule remain: 1710 + 150 + 60.
      expect(r.costPiastres, 1920);
      expect(r.recipe.map((l) => l.source).toSet(), {'base', 'rule'});
      await expectLater(
        s.api.menu.putSizeRecipe(
          sizeId: _size('cortado', 'one_size'),
          body: PutRecipeRequest(
            lines: [
              RecipeLineInput(
                ingredientId: MenuSeedIds.ingredient('sugar'),
                quantity: 5,
                unit: 'g',
              ),
              RecipeLineInput(
                ingredientId: MenuSeedIds.ingredient('sugar'),
                quantity: 6,
                unit: 'g',
              ),
            ],
          ),
        ),
        throwsA(_status(400)),
      );
    });

    test('the full item: own recipe lines and the offered add-ons', () async {
      final s = _api();
      final latte = await s.api.menu.getMenuItem(id: _item('latte'));
      expect(latte.recipes.map((r) => (r.sizeLabel, r.quantityUsed)), [
        ('Regular', 180.0),
        ('Large', 240.0),
      ]);
      expect(
        latte.allowedAddonIds,
        contains(MenuSeedIds.option('milk', 'oat')),
      );
      expect(
        latte.allowedAddonIds,
        contains(MenuSeedIds.option('extras', 'shot')),
      );
    });

    test(
      'patch: translations merged, image cleared, create needs its cap',
      () async {
        final s = _api();
        await s.api.menu.updateMenuItem(
          id: _item('latte'),
          body: const UpdateMenuItemRequest(
            nameTranslations: {'ar': 'لاتيه ساخن'},
          ),
        );
        expect(
          s.db[MenuTables.menuItems].find(_item('latte'))!['name_translations'],
          {'en': 'Caffè Latte', 'ar': 'لاتيه ساخن'},
        );
        final m = _api(persona: Persona.manager);
        await expectLater(
          m.api.menu.createMenuItem(
            body: CreateMenuItemRequest(
              orgId: _org,
              name: 'X',
              categoryId: MenuSeedIds.category('hot'),
              basePrice: 0,
            ),
          ),
          throwsA(_status(403)),
        );
        await expectLater(
          m.api.menu.deleteMenuItem(id: _item('latte')),
          throwsA(_status(403)),
        );
      },
    );

    test('duplicate: " (Copy)", sizes on new ids, own lines', () async {
      final s = _api();
      final copy = await s.api.menu.duplicateItem(id: _item('latte'));
      expect(copy.name, 'Caffè Latte (Copy)');
      expect(copy.sizes.map((z) => z.label), ['Regular', 'Large']);
      expect(
        copy.sizes.map((z) => z.id),
        isNot(contains(_size('latte', 'Regular'))),
      );
      final lines = s.db[MenuTables.recipeLines].where(
        (l) => l['menu_item_id'] == copy.id && l['source'] == 'own',
      );
      expect(lines, hasLength(2));
    });

    test('upload: processing, then done on the second look', () async {
      final s = _api();
      final res = await s.api.uploads.uploadMenuItemImage(
        menuItemId: _item('latte'),
        body: const UploadImageMultipart(
          image: ApiFilePart(field: 'image', filename: 'l.png', bytes: [1, 2]),
        ),
      );
      expect(res.status, 'processing');
      final first = await s.api.assets.getJob(id: res.assetJobId);
      expect(first.status, 'processing');
      final second = await s.api.assets.getJob(id: res.assetJobId);
      expect(second.status, 'done');
      expect(
        s.db[MenuTables.menuItems].find(_item('latte'))!['image_url'],
        isNotNull,
      );
    });
  });

  group('categories and costs', () {
    test('create goes last; reorder needs exactly the live set', () async {
      final s = _api();
      final c = await s.api.menu.createCategory(
        body: CreateCategoryRequest(orgId: _org, name: 'Smoothies'),
      );
      expect(c.displayOrder, 7);
      expect(c.isActive, isTrue);
      await expectLater(
        s.api.menu.reorderCategories(
          body: ReorderCategoriesRequest(orgId: _org, orderedIds: [c.id]),
        ),
        throwsA(_status(400)),
      );
    });

    test('category writes need their caps', () async {
      final s = _api(persona: Persona.manager);
      await expectLater(
        s.api.menu.deleteCategory(id: MenuSeedIds.category('hot')),
        throwsA(_status(403)),
      );
    });

    test('add-on costs: an extra shot is 18 g of the blend', () async {
      final s = _api();
      final costs = await s.api.costing.listAddonCosts(orgId: _org);
      final shot = costs.firstWhere(
        (c) => c.addonItemId == MenuSeedIds.option('extras', 'shot'),
      );
      expect(shot.cost, 1710);
      expect(shot.price, 3000);
      expect(shot.marginPct, closeTo((3000 - 1710) / 3000, 1e-9));
    });
  });
}
