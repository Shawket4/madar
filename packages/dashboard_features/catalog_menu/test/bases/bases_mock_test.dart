// The `bases` unit's mock backend against the backend's rules
// (`MadarRust/src/menu/bases.rs`, `packaging.rs`): the capability gates, the
// validation refusals, unit conversion, and the counts a write reports.
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_menu/src/area_seed.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Future<ApiException> refusal(Future<Object?> Function() call) async {
  try {
    await call();
  } on ApiException catch (e) {
    return e;
  }
  fail('expected a refusal');
}

final String _ice = MenuSeedIds.ingredient('ice');
final String _straw = MenuSeedIds.ingredient('straw');

void main() {
  test('reads need menu.items.read, writes menu.items.edit, apply its own '
      'cap', () async {
    final manager = DashboardApi(menuServer(persona: Persona.manager).server);
    expect(await manager.menu.listBases(), hasLength(3));
    expect(await manager.menu.listRules(), hasLength(6));
    for (final call in <Future<Object?> Function()>[
      () => manager.menu.deleteBase(id: MenuSeedIds.base('iced_build')),
      () => manager.menu.deleteRule(id: MenuSeedIds.rule('iced')),
      manager.menu.applyRules,
    ]) {
      expect((await refusal(call)).status, 403);
    }
    // A limited cashier reads, as the nav shows the page to them.
    final limited = DashboardApi(menuServer(persona: Persona.limited).server);
    expect(await limited.menu.listRules(), hasLength(6));
  });

  test('GET /recipe-bases: the session\'s org only; deleted items\' sizes '
      'do not count', () async {
    final platform = DashboardApi(menuServer(persona: Persona.platform).server);
    expect((await refusal(platform.menu.listBases)).status, 403);
    final s = menuServer();
    final api = DashboardApi(s.server);
    final espresso = MenuSeedIds.base('espresso');
    final americano = MenuSeedIds.item('americano');
    final gone = s.db[MenuTables.sizes]
        .where(
          (z) => z['menu_item_id'] == americano && z['base_id'] == espresso,
        )
        .length;
    expect(gone, greaterThan(0));
    final before = (await api.menu.listBases()).firstWhere(
      (b) => b.id == espresso,
    );
    s.db[MenuTables.menuItems].find(americano)!['deleted_at'] = s.db.nowIso;
    final after = (await api.menu.listBases()).firstWhere(
      (b) => b.id == espresso,
    );
    expect(after.itemCount, before.itemCount - 1);
    expect(after.sizeCount, before.sizeCount - gone);
  });

  test('base lines: converted to the ingredient unit, no duplicate per size, '
      'no negative quantity', () async {
    final api = DashboardApi(menuServer().server);
    final base = await api.menu.createBase(
      body: CreateRecipeBaseRequest(
        name: '  Ice cup ',
        isActive: true,
        lines: [
          RecipeBaseLineInput(ingredientId: _ice, quantity: 0.2, unit: 'kg'),
        ],
      ),
    );
    expect(base.name, 'Ice cup');
    expect(base.lines.single.unit, 'g');
    expect(jsonNum(base.lines.single.quantity), 200);
    final dup = await refusal(
      () => api.menu.putBaseLines(
        id: base.id,
        body: PutRecipeBaseLinesRequest(
          lines: [
            RecipeBaseLineInput(ingredientId: _ice, quantity: 1, unit: 'g'),
            RecipeBaseLineInput(ingredientId: _ice, quantity: 2, unit: 'g'),
          ],
        ),
      ),
    );
    expect(dup.status, 400);
    expect(dup.message, contains('Duplicate ingredient for the same size'));
    final neg = await refusal(
      () => api.menu.putBaseLines(
        id: base.id,
        body: PutRecipeBaseLinesRequest(
          lines: [
            RecipeBaseLineInput(ingredientId: _ice, quantity: -1, unit: 'g'),
          ],
        ),
      ),
    );
    expect(neg.message, contains('quantity must be >= 0'));
    final family = await refusal(
      () => api.menu.putBaseLines(
        id: base.id,
        body: PutRecipeBaseLinesRequest(
          lines: [
            RecipeBaseLineInput(ingredientId: _ice, quantity: 1, unit: 'pcs'),
          ],
        ),
      ),
    );
    expect(family.message, contains('incompatible unit families'));
  });

  test('a rule must match something; a duplicate ingredient is refused; a '
      'create lists next', () async {
    final api = DashboardApi(menuServer().server);
    final none = await refusal(
      () => api.menu.createRule(
        body: CreatePackagingRuleRequest(name: 'All', lines: const []),
      ),
    );
    expect(none.status, 400);
    final dup = await refusal(
      () => api.menu.createRule(
        body: CreatePackagingRuleRequest(
          name: 'Straws',
          matchSizeLabel: 'Cup',
          lines: [
            PackagingRuleLineInput(
              ingredientId: _straw,
              quantity: 1,
              unit: 'pcs',
            ),
            PackagingRuleLineInput(
              ingredientId: _straw,
              quantity: 2,
              unit: 'pcs',
            ),
          ],
        ),
      ),
    );
    expect(dup.message, contains('Duplicate ingredient in rule'));
    final made = await api.menu.createRule(
      body: CreatePackagingRuleRequest(
        name: 'Straws',
        matchSizeLabel: ' Cup ',
        lines: [
          PackagingRuleLineInput(
            ingredientId: _straw,
            quantity: 1,
            unit: 'pcs',
          ),
        ],
      ),
    );
    expect(made.matchSizeLabel, 'Cup');
    expect((await api.menu.listRules()).map((r) => r.id), contains(made.id));
  });

  test('a base write reports the sizes it re-expanded', () async {
    final s = menuServer();
    final api = DashboardApi(s.server);
    final iced = MenuSeedIds.base('iced_build');
    // Hand count: Iced build feeds 4 sizes (Cold Brew and Iced Matcha,
    // Regular and Large); turning it off takes its ice out of all four.
    expect(sizesUsing(s.db, iced), 4);
    final r = await api.menu.patchBase(
      id: iced,
      body: PatchRecipeBaseRequest(isActive: false),
    );
    expect(r.sizesChanged, 4);
    expect(r.base.isActive, isFalse);
    // Nothing left to change on a second identical write.
    final again = await api.menu.patchBase(
      id: iced,
      body: PatchRecipeBaseRequest(isActive: false),
    );
    expect(again.sizesChanged, 0);
  });
}

/// A decimal-text or numeric quantity as a number.
num jsonNum(Object? v) => v is num ? v : num.parse('$v');
