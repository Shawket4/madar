// The settings and category handlers against the backend's rules
// (`MadarRust src/inventory/handlers.rs`): gates, validation, the reassign on
// delete, and the tolerance the next count read carries (INV-SET-024).
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Matcher refused(int status, String words) => throwsA(
  isA<ApiException>()
      .having((e) => e.status, 'status', status)
      .having((e) => e.message, 'message', contains(words)),
);

({InventoryApi api, MockDb db}) backend([Persona p = Persona.owner]) {
  final s = settingsServer(persona: p);
  return (api: DashboardApi(s.server).inventory, db: s.db);
}

void main() {
  test(
    'INV-SET-024 a saved tolerance is the next count read\'s threshold',
    () async {
      final s = settingsServer();
      final api = DashboardApi(s.server);
      final open = InvIds.stocktake('new-cairo-1008');
      expect(
        (await api.stocktakes.getStocktake(id: open)).varianceThresholdPct,
        invVarianceThresholdPct,
      );
      final saved = await api.inventory.updateInventorySettings(
        orgId: org,
        body: const UpdateInventorySettingsRequest(
          stocktakeVarianceThresholdPct: 12.5,
        ),
      );
      expect(saved.stocktakeVarianceThresholdPct, 12.5);
      expect(
        (await api.inventory.getInventorySettings(
          orgId: org,
        )).stocktakeVarianceThresholdPct,
        12.5,
      );
      expect(
        (await api.stocktakes.getStocktake(id: open)).varianceThresholdPct,
        12.5,
      );
    },
  );

  test('PUT settings: 0..100 only; inventory.adjust', () async {
    final b = backend();
    for (final v in [-0.5, 100.5]) {
      await expectLater(
        b.api.updateInventorySettings(
          orgId: org,
          body: UpdateInventorySettingsRequest(
            stocktakeVarianceThresholdPct: v,
          ),
        ),
        refused(400, 'between 0 and 100'),
      );
    }
    await expectLater(
      backend(Persona.limited).api.updateInventorySettings(
        orgId: org,
        body: const UpdateInventorySettingsRequest(
          stocktakeVarianceThresholdPct: 3,
        ),
      ),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 403)),
    );
  });

  test(
    'POST: slug from the name, sort 10, packaging by slug; 400 / 409',
    () async {
      final b = backend();
      final made = await b.api.createIngredientCategory(
        orgId: org,
        body: const CreateIngredientCategoryRequest(name: ' Cold Brew Kits '),
      );
      expect(made.slug, 'cold_brew_kits');
      expect(made.name, 'Cold Brew Kits');
      expect(made.sortOrder, 10);
      expect(made.isPackaging, isFalse);
      expect(made.ingredientCount, 0);
      await expectLater(
        b.api.createIngredientCategory(
          orgId: org,
          body: const CreateIngredientCategoryRequest(name: 'حليب'),
        ),
        refused(400, 'must contain a letter or digit'),
      );
      await expectLater(
        b.api.createIngredientCategory(
          orgId: org,
          body: const CreateIngredientCategoryRequest(name: 'Dry goods'),
        ),
        refused(409, "'dry_goods' already exists"),
      );
      await expectLater(
        backend(Persona.manager).api.createIngredientCategory(
          orgId: org,
          body: const CreateIngredientCategoryRequest(name: 'Tea'),
        ),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 403)),
      );
    },
  );

  test('PATCH: name and packaging; 400 blank; 404 unknown', () async {
    final b = backend();
    final c = await b.api.updateIngredientCategory(
      orgId: org,
      id: cat('milk'),
      body: const UpdateIngredientCategoryRequest(
        name: 'Fresh milk',
        isPackaging: true,
      ),
    );
    expect(c.name, 'Fresh milk');
    expect(c.slug, 'milk');
    expect(c.isPackaging, isTrue);
    expect(c.ingredientCount, usersOf(b.db, 'milk'));
    await expectLater(
      b.api.updateIngredientCategory(
        orgId: org,
        id: cat('milk'),
        body: const UpdateIngredientCategoryRequest(name: '  '),
      ),
      refused(400, '1–80 characters'),
    );
    await expectLater(
      b.api.updateIngredientCategory(
        orgId: org,
        id: InvIds.category('nope'),
        body: const UpdateIngredientCategoryRequest(name: 'X'),
      ),
      refused(404, 'Category not found'),
    );
  });

  test('DELETE: general refused; in use needs reassign_to; the ingredients '
      'move', () async {
    final b = backend();
    await expectLater(
      b.api.deleteIngredientCategory(orgId: org, id: cat('general')),
      refused(400, 'cannot be deleted'),
    );
    final users = usersOf(b.db, 'syrup');
    expect(users, greaterThan(0));
    await expectLater(
      b.api.deleteIngredientCategory(orgId: org, id: cat('syrup')),
      refused(409, '$users ingredient(s) use this category'),
    );
    await expectLater(
      b.api.deleteIngredientCategory(
        orgId: org,
        id: cat('syrup'),
        reassignTo: cat('syrup'),
      ),
      refused(400, 'must be a different category'),
    );
    final general = usersOf(b.db, 'general');
    await b.api.deleteIngredientCategory(
      orgId: org,
      id: cat('syrup'),
      reassignTo: cat('general'),
    );
    expect(usersOf(b.db, 'syrup'), 0);
    expect(usersOf(b.db, 'general'), general + users);
    final list = await b.api.listIngredientCategories(orgId: org);
    expect(list.map((c) => c.slug), isNot(contains('syrup')));
    expect(
      list.firstWhere((c) => c.slug == 'general').ingredientCount,
      general + users,
    );
  });
}
