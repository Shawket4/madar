// Ingredients' mock backend (`lib/src/mock/ingredients_mock.dart`) behaves
// like MadarRust's inventory handlers: capabilities, scoping, validation,
// the unit conversion, COALESCE on PATCH, paging of the ledger; and the
// page's pure rules (`ingredients_data.dart`).
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:dashboard_inventory/src/ingredients/ingredients_data.dart';
import 'package:dashboard_inventory/src/mock/ingredients_mock.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Matcher refused(int status, String words) => throwsA(
  isA<ApiException>()
      .having((e) => e.status, 'status', status)
      .having((e) => e.message, 'message', contains(words)),
);

({DashboardApi api, MockDb db}) backend([Persona p = Persona.owner]) {
  final s = ingredientsServer(persona: p);
  return (api: DashboardApi(s.server), db: s.db);
}

final String org = SeedIds.sabahOrg;

void main() {
  group('POST catalog (createCatalogItem)', () {
    test('creates in the general category when none is given; listed next',
        () async {
      final b = backend();
      final made = await b.api.inventory.createCatalogItem(
        orgId: org,
        body: const CreateCatalogItemRequest(
          name: '  Pistachio Paste ',
          unit: 'g',
          costPerUnit: 45.5,
        ),
      );
      expect(made.name, 'Pistachio Paste');
      expect(made.categoryId, InvIds.category('general'));
      expect(made.categoryName, 'General');
      expect(made.costPerUnit, 45.5);
      final list = await b.api.inventory.listCatalog(orgId: org);
      expect(list.map((i) => i.id), contains(made.id));
    });

    test('refusals: capability, unit, blank name, duplicate, foreign '
        'supplier', () async {
      final mgr = backend(Persona.manager);
      await expectLater(
        mgr.api.inventory.createCatalogItem(
          orgId: org,
          body: const CreateCatalogItemRequest(name: 'X', unit: 'g'),
        ),
        refused(403, '(inventory.items.create)'),
      );
      final b = backend();
      await expectLater(
        b.api.inventory.createCatalogItem(
          orgId: org,
          body: const CreateCatalogItemRequest(name: 'X', unit: 'oz'),
        ),
        refused(400, 'Unit must be one of: g, kg, ml, l, pcs'),
      );
      await expectLater(
        b.api.inventory.createCatalogItem(
          orgId: org,
          body: const CreateCatalogItemRequest(name: '  ', unit: 'g'),
        ),
        refused(400, 'name cannot be empty'),
      );
      await expectLater(
        b.api.inventory.createCatalogItem(
          orgId: org,
          body: const CreateCatalogItemRequest(name: 'Oat Milk', unit: 'ml'),
        ),
        refused(409, 'An ingredient with this name already exists'),
      );
      await expectLater(
        b.api.inventory.createCatalogItem(
          orgId: org,
          body: CreateCatalogItemRequest(
            name: 'Y',
            unit: 'g',
            supplierId: mockUuid('supplier:nowhere'),
          ),
        ),
        refused(400, 'Supplier does not belong to this organization'),
      );
    });
  });

  group('PATCH catalog (updateCatalogItem)', () {
    test('null keeps a value (COALESCE); a given one replaces it', () async {
      final b = backend();
      final id = InvIds.ingredient('cocoa');
      final out = await b.api.inventory.updateCatalogItem(
        orgId: org,
        id: id,
        body: const UpdateCatalogItemRequest(
          name: 'Cocoa 22%',
          explicitNulls: {'cost_per_unit', 'description'},
        ),
      );
      expect(out.name, 'Cocoa 22%');
      expect(out.costPerUnit, 25);
    });

    test('g → kg converts the cost, every branch row and the ledger',
        () async {
      final b = backend();
      final id = InvIds.ingredient('house-blend');
      final stock = stockRow(b.db, SeedIds.zamalek, 'house-blend')!;
      final onHand = (stock['on_hand']! as num).toDouble();
      final parMin = (stock['par_min']! as num).toDouble();
      final moves = b.db[InvTables.movements].where(
        (m) => m['org_ingredient_id'] == id,
      );
      final q0 = (moves.first['quantity']! as num).toDouble();
      final out = await b.api.inventory.updateCatalogItem(
        orgId: org,
        id: id,
        body: const UpdateCatalogItemRequest(unit: 'kg'),
      );
      expect(out.unit, 'kg');
      expect(out.costPerUnit, 90000);
      final after = stockRow(b.db, SeedIds.zamalek, 'house-blend')!;
      expect(after['on_hand'], closeTo(onHand / 1000, 0.0005));
      expect(after['par_min'], closeTo(parMin / 1000, 0.0005));
      expect(
        b.db[InvTables.movements].find(moves.first['id']! as String)!['quantity'],
        closeTo(q0 / 1000, 0.0005),
      );
    });

    test('refusals: unit with cost, across measures, pcs, unknown, the '
        'capability', () async {
      final b = backend();
      await expectLater(
        b.api.inventory.updateCatalogItem(
          orgId: org,
          id: InvIds.ingredient('sugar'),
          body: const UpdateCatalogItemRequest(unit: 'kg', costPerUnit: 3000),
        ),
        refused(400, 'Change the unit and the cost in separate requests'),
      );
      await expectLater(
        b.api.inventory.updateCatalogItem(
          orgId: org,
          id: InvIds.ingredient('sugar'),
          body: const UpdateCatalogItemRequest(unit: 'ml'),
        ),
        refused(400, 'A unit can only change within the same measure'),
      );
      await expectLater(
        b.api.inventory.updateCatalogItem(
          orgId: org,
          id: InvIds.ingredient('sugar'),
          body: const UpdateCatalogItemRequest(name: 'Oat Milk'),
        ),
        refused(409, 'An ingredient with this name already exists'),
      );
      await expectLater(
        b.api.inventory.updateCatalogItem(
          orgId: org,
          id: mockUuid('ingredient:none'),
          body: const UpdateCatalogItemRequest(name: 'Z'),
        ),
        refused(404, 'Ingredient not found'),
      );
      await expectLater(
        backend(Persona.limited).api.inventory.updateCatalogItem(
          orgId: org,
          id: InvIds.ingredient('sugar'),
          body: const UpdateCatalogItemRequest(name: 'Z'),
        ),
        refused(403, '(inventory.adjust)'),
      );
    });
  });

  group('PUT par (setParLevels)', () {
    test('creates the branch row at 0 on hand when there is none', () async {
      final b = backend();
      expect(stockRow(b.db, SeedIds.heliopolis, 'sugar'), isNull);
      final row = await b.api.inventory.setParLevels(
        branchId: SeedIds.heliopolis,
        orgIngredientId: InvIds.ingredient('sugar'),
        body: const SetParRequest(parMin: 2000, parMax: 5000),
      );
      expect(row.onHand, 0);
      expect(row.parMin, 2000);
      expect(row.hasActivity, isTrue);
      expect(row.belowPar, isTrue);
    });

    test('refusals: negative, max under min, another branch, the capability',
        () async {
      final b = backend();
      Future<BranchStockRow> put(Persona? p, String branch, SetParRequest r) =>
          (p == null ? b.api : backend(p).api).inventory.setParLevels(
            branchId: branch,
            orgIngredientId: InvIds.ingredient('sugar'),
            body: r,
          );
      await expectLater(
        put(null, SeedIds.zamalek, const SetParRequest(parMin: -1)),
        refused(400, 'Par levels cannot be negative'),
      );
      await expectLater(
        put(null, SeedIds.zamalek, const SetParRequest(parMin: 5, parMax: 2)),
        refused(400, 'Max par must be at least the min par'),
      );
      await expectLater(
        put(Persona.manager, SeedIds.maadi, const SetParRequest(parMin: 5)),
        refused(403, ''),
      );
      await expectLater(
        put(Persona.limited, SeedIds.zamalek, const SetParRequest(parMin: 5)),
        refused(403, '(inventory.adjust)'),
      );
    });
  });

  group('GET movements (listMovements)', () {
    test('one ingredient at one branch, newest first, per_page clamped',
        () async {
      final b = backend();
      final id = InvIds.ingredient('oat');
      final all = b.db[InvTables.movements].where(
        (m) => m['branch_id'] == SeedIds.zamalek && m['org_ingredient_id'] == id,
      );
      final rows = await b.api.inventory.listMovements(
        branchId: SeedIds.zamalek,
        orgIngredientId: id,
        perPage: 5,
      );
      expect(rows.length, all.length < 5 ? all.length : 5);
      for (var i = 1; i < rows.length; i++) {
        expect(!rows[i].createdAt.isAfter(rows[i - 1].createdAt), isTrue);
      }
      expect(rows.every((m) => m.orgIngredientId == id), isTrue);
      expect(rows.every((m) => m.ingredientName == 'Oat Milk'), isTrue);
      final big = await b.api.inventory.listMovements(
        branchId: SeedIds.zamalek,
        perPage: 9999,
      );
      expect(big.length, lessThanOrEqualTo(500));
    });

    test('inventory.read, and only the persona\'s branches', () async {
      await expectLater(
        backend(Persona.limited).api.inventory.listMovements(
          branchId: SeedIds.maadi,
        ),
        refused(403, '(inventory.read)'),
      );
      await expectLater(
        backend(Persona.manager).api.inventory.listMovements(
          branchId: SeedIds.maadi,
        ),
        refused(403, ''),
      );
    });
  });

  group('DELETE catalog (deleteCatalogItem)', () {
    test('refused while stocked somewhere; gone once not', () async {
      final b = backend();
      await expectLater(
        b.api.inventory.deleteCatalogItem(
          orgId: org,
          id: InvIds.ingredient('oat'),
        ),
        refused(409, 'Ingredient still has stock at a branch'),
      );
      final made = await b.api.inventory.createCatalogItem(
        orgId: org,
        body: const CreateCatalogItemRequest(name: 'Temp', unit: 'g'),
      );
      await b.api.inventory.deleteCatalogItem(orgId: org, id: made.id);
      final list = await b.api.inventory.listCatalog(orgId: org);
      expect(list.map((i) => i.id), isNot(contains(made.id)));
    });
  });

  group('fallbacks for the routes other units own', () {
    test('POST categories: slug, 409 on a taken key', () async {
      final b = backend();
      final c = await b.api.inventory.createIngredientCategory(
        orgId: org,
        body: const CreateIngredientCategoryRequest(name: 'Nut Pastes!'),
      );
      expect(c.slug, 'nut_pastes');
      expect(c.ingredientCount, 0);
      await expectLater(
        b.api.inventory.createIngredientCategory(
          orgId: org,
          body: const CreateIngredientCategoryRequest(name: 'Milk'),
        ),
        refused(409, "A category with the key 'milk' already exists"),
      );
    });

    test('POST stocktakes: one-item count; 409 while one is open', () async {
      final b = backend();
      final st = await b.api.stocktakes.createStocktake(
        branchId: SeedIds.zamalek,
        body: CreateStocktakeRequest(
          orgIngredientIds: [InvIds.ingredient('oat')],
        ),
      );
      expect(st.status, 'in_progress');
      expect(st.items.single.orgIngredientId, InvIds.ingredient('oat'));
      await expectLater(
        b.api.stocktakes.createStocktake(
          branchId: SeedIds.zamalek,
          body: const CreateStocktakeRequest(),
        ),
        refused(409, 'An open stocktake already exists for this branch'),
      );
    });

    test('ingredientCategorySlug follows the backend', () {
      expect(ingredientCategorySlug('  Coffee  Beans '), 'coffee_beans');
      expect(ingredientCategorySlug('حليب'), isNull);
      expect(ingredientCategorySlug('a-b--c'), 'a_b_c');
    });
  });

  group('pure rules', () {
    test('costInputToPiastres keeps a hundredth of a piastre', () {
      expect(costInputToPiastres(''), isNull);
      expect(costInputToPiastres('  '), isNull);
      expect(costInputToPiastres('0.9'), 90);
      expect(costInputToPiastres('0.045'), 4.5);
      expect(costInputToPiastres('0.001'), 0.1);
      expect(costInputToPiastres('١٫٥'), 150);
      expect(costInputToPiastres('abc'), isNull);
    });

    test('field texts read like String(n)', () {
      expect(costFieldText(90), '0.9');
      expect(costFieldText(4.5), '0.045');
      expect(costFieldText(null), '');
      expect(numberFieldText(1000.0), '1000');
      expect(numberFieldText(1.03), '1.03');
    });
  });
}
