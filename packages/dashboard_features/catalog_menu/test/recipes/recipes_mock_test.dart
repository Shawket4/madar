// The recipes unit's mock handlers behave like the backend
// (`inventory::create_catalog_item`, `recipes::list_addon_ingredients`):
// refusals in the backend's order and words, state that persists.
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_menu/dashboard_catalog_menu.dart';
import 'package:dashboard_catalog_menu/src/area_seed.dart';
import 'package:flutter_test/flutter_test.dart';

({MockServer server, MockDb db, DashboardApi api}) _boot([
  Persona persona = Persona.owner,
]) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  registerCatalogMenuMocks(server, db);
  return (server: server, db: db, api: DashboardApi(server));
}

Future<ApiException> _refusal(Future<Object?> call) async {
  try {
    await call;
  } on ApiException catch (e) {
    return e;
  }
  fail('expected a refusal');
}

String get _org => SeedIds.sabahOrg;

void main() {
  group('POST /inventory/orgs/{org_id}/catalog', () {
    test(
      'creates the ingredient in the general category and lists it',
      () async {
        final b = _boot();
        final created = await b.api.inventory.createCatalogItem(
          orgId: _org,
          body: const CreateCatalogItemRequest(
            name: '  Rose syrup ',
            unit: 'ml',
            costPerUnit: 9,
            explicitNulls: {'category_id'},
          ),
        );
        expect(created.name, 'Rose syrup');
        expect(created.categorySlug, 'general');
        expect(created.categoryName, 'General');
        expect(created.costPerUnit, 9);
        expect(created.isActive, isTrue);
        expect(b.server.calls.last.status, 201);
        final list = await b.api.inventory.listCatalog(orgId: _org);
        expect(list.where((i) => i.id == created.id), hasLength(1));
        final cats = await b.api.inventory.listIngredientCategories(
          orgId: _org,
        );
        final general = cats.firstWhere((c) => c.slug == 'general');
        expect(
          general.ingredientCount,
          list.where((i) => i.categoryId == general.id).length,
        );
      },
    );

    test('a chosen category and a null cost (unknown, never 0)', () async {
      final b = _boot();
      final created = await b.api.inventory.createCatalogItem(
        orgId: _org,
        body: CreateCatalogItemRequest(
          name: 'Saffron',
          unit: 'g',
          categoryId: MenuSeedIds.ingredientCategory('syrup'),
          explicitNulls: const {'cost_per_unit'},
        ),
      );
      expect(created.categorySlug, 'syrup');
      expect(created.costPerUnit, isNull);
    });

    test('refuses a blank name, a bad unit, a foreign category and a '
        'duplicate', () async {
      final b = _boot();
      Future<ApiException> post(Map<String, Object?> body) => _refusal(
        b.api.inventory.createCatalogItem(
          orgId: _org,
          body: CreateCatalogItemRequest.fromJson(body),
        ),
      );
      var e = await post({'name': '   ', 'unit': 'g'});
      expect((e.status, e.message), (400, 'Bad request: name cannot be empty'));
      e = await post({'name': 'Rose', 'unit': 'cup'});
      expect(
        (e.status, e.message),
        (400, 'Bad request: Unit must be one of: g, kg, ml, l, pcs'),
      );
      e = await post({
        'name': 'Rose',
        'unit': 'g',
        'category_id': mockUuid('somebody-else'),
      });
      expect(
        (e.status, e.message),
        (400, 'Bad request: Category does not belong to this organization'),
      );
      e = await post({'name': 'Oat milk', 'unit': 'ml'});
      expect(
        (e.status, e.message),
        (
          409,
          'Conflict: An ingredient with this name already exists in the catalog',
        ),
      );
    });

    for (final p in [Persona.manager, Persona.limited]) {
      test('${p.name}: refused without inventory.items.create', () async {
        final b = _boot(p);
        final e = await _refusal(
          b.api.inventory.createCatalogItem(
            orgId: _org,
            body: const CreateCatalogItemRequest(name: 'Rose', unit: 'g'),
          ),
        );
        expect(e.status, 403);
        expect(e.message, contains('inventory.items.create'));
        final list = await b.api.inventory.listCatalog(orgId: _org);
        expect(list.where((i) => i.name == 'Rose'), isEmpty);
      });
    }

    test('another org is refused', () async {
      final b = _boot();
      final e = await _refusal(
        b.api.inventory.createCatalogItem(
          orgId: SeedIds.nakhlaOrg,
          body: const CreateCatalogItemRequest(name: 'Rose', unit: 'g'),
        ),
      );
      expect(e.status, 403);
    });
  });

  group('GET /recipes/addons/{addon_item_id}', () {
    test("an add-on's all-sizes lines, named by the catalog", () async {
      final b = _boot();
      final lines = await b.api.recipes.listAddonIngredients(
        addonItemId: MenuSeedIds.option('extras', 'shot'),
      );
      expect(lines, hasLength(1));
      final l = lines.single;
      expect(l.ingredientName, 'House espresso blend');
      expect(l.orgIngredientId, MenuSeedIds.ingredient('house_blend'));
      expect(l.unit, 'g');
      expect(l.quantityUsed, 18);
      expect(l.addonItemId, MenuSeedIds.option('extras', 'shot'));
    });

    test('an unknown add-on is not found', () async {
      final b = _boot();
      final e = await _refusal(
        b.api.recipes.listAddonIngredients(addonItemId: mockUuid('nothing')),
      );
      expect((e.status, e.message), (404, 'Not found: Addon item not found'));
    });

    test('limited: refused without recipes.read', () async {
      final b = _boot(Persona.limited);
      final e = await _refusal(
        b.api.recipes.listAddonIngredients(
          addonItemId: MenuSeedIds.option('extras', 'shot'),
        ),
      );
      expect(e.status, 403);
      expect(e.message, contains('recipes.read'));
    });

    test("another org's add-on is refused", () async {
      final b = _boot(Persona.dawamOnly);
      final e = await _refusal(
        b.api.recipes.listAddonIngredients(
          addonItemId: MenuSeedIds.option('extras', 'shot'),
        ),
      );
      expect(e.status, 403);
    });
  });

  // recipes::book::get_recipe_book: the Items page's filters, menu order, a
  // column per size and a row per (source, ingredient, unit), the Studio's
  // own figures.
  group('GET /recipes/book', () {
    test('every live non-combo item in menu order, its categories in '
        'display order', () async {
      final b = _boot();
      final book = await b.api.recipes.getRecipeBook(orgId: _org);
      final live = b.db[MenuTables.menuItems].where(
        (m) =>
            m['org_id'] == _org &&
            m['deleted_at'] == null &&
            m['kind'] != 'combo',
      );
      expect(book.items, hasLength(live.length));
      final cats = b.db[MenuTables.categories].query(
        filters: {'org_id': _org},
        where: (c) => c['deleted_at'] == null,
        sort: 'display_order',
      );
      final used = {for (final m in live) m['category_id']};
      expect(book.categories.map((c) => c.id), [
        for (final c in cats)
          if (used.contains(c['id'])) c['id'],
      ]);
      // Grouped by category in that order, by name within one.
      final order = [for (final c in book.categories) c.id];
      for (var i = 1; i < book.items.length; i++) {
        final a = book.items[i - 1];
        final z = book.items[i];
        final ai = order.indexOf(a.categoryId ?? '');
        final zi = order.indexOf(z.categoryId ?? '');
        if (ai == zi) {
          expect(a.name.compareTo(z.name), lessThanOrEqualTo(0));
        } else {
          expect(zi == -1 || (ai != -1 && ai < zi), isTrue);
        }
      }
    });

    test("a drink's table: the Studio's sizes, usable amounts, costs and "
        'steps', () async {
      final b = _boot();
      final book = await b.api.recipes.getRecipeBook(orgId: _org);
      final latte = book.items.firstWhere((c) => c.name == 'Caffè Latte');
      final studio = await b.api.menu.getStudio(id: latte.menuItemId);
      expect(latte.sizes.map((s) => s.label), [
        for (final s in studio.sizes) s.label,
      ]);
      expect(latte.rows, isNotEmpty);
      for (final row in latte.rows) {
        expect(row.cells, hasLength(latte.sizes.length));
      }
      for (final (col, size) in studio.sizes.indexed) {
        final card = latte.sizes[col];
        expect(card.price, size.price);
        expect(card.costPiastres, size.costPiastres);
        expect(card.costIncomplete, size.costIncomplete);
        expect(
          card.foodCostPct,
          size.costPiastres != null && !size.costIncomplete && size.price > 0
              ? size.costPiastres! / size.price
              : null,
        );
        for (final line in size.recipe) {
          final row = latte.rows.singleWhere(
            (r) =>
                r.ingredientId == line.ingredientId &&
                r.unit == line.unit &&
                r.source == (line.source ?? 'own'),
          );
          expect(row.cells[col].quantity, double.parse(line.usableQuantity));
          expect(row.cells[col].lineCostPiastres, line.lineCostPiastres);
        }
      }
      // The Studio grid's order: own lines, then a base's, then a rule's.
      int rank(String s) => switch (s) {
        'base' => 1,
        'rule' => 2,
        _ => 0,
      };
      final ranks = [for (final r in latte.rows) rank(r.source)];
      expect(ranks, [...ranks]..sort());
      expect(latte.steps.map((s) => s.name), [
        for (final s in studio.recipeSteps) s.name,
      ]);
      expect(latte.steps, isNotEmpty);
    });

    test('follows the Items page filters', () async {
      final b = _boot();
      final all = await b.api.recipes.getRecipeBook(orgId: _org);
      final cat = all.categories.first.id;
      final inCat = await b.api.recipes.getRecipeBook(
        orgId: _org,
        categoryId: cat,
      );
      expect(inCat.items, isNotEmpty);
      expect(inCat.items.every((c) => c.categoryId == cat), isTrue);
      expect(inCat.categories.map((c) => c.id), [cat]);
      final latte = await b.api.recipes.getRecipeBook(
        orgId: _org,
        search: '  LATTE ',
      );
      expect(latte.items, isNotEmpty);
      expect(
        latte.items.every((c) => c.name.toLowerCase().contains('latte')),
        isTrue,
      );
      final has = await b.api.recipes.getRecipeBook(
        orgId: _org,
        hasRecipe: true,
      );
      final none = await b.api.recipes.getRecipeBook(
        orgId: _org,
        hasRecipe: false,
      );
      expect(has.items.every((c) => c.rows.isNotEmpty), isTrue);
      expect(none.items.every((c) => c.rows.isEmpty), isTrue);
      expect(has.items.length + none.items.length, all.items.length);
    });

    test('recipes.read, and the caller\'s own org', () async {
      final limited = _boot(Persona.limited);
      final e = await _refusal(limited.api.recipes.getRecipeBook(orgId: _org));
      expect(e.status, 403);
      final other = await _refusal(
        _boot().api.recipes.getRecipeBook(orgId: SeedIds.nakhlaOrg),
      );
      expect(other.status, 403);
    });
  });
}
