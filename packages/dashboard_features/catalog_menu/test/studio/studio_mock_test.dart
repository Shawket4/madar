// The studio's mock handlers against the backend's rules and hand-computed
// figures: gates per capability, validation refusals, state across calls,
// the aggregate's costs agreeing with the area seed, the preview's numbers.
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_menu/src/area_seed.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

String _ing(String k) => MenuSeedIds.ingredient(k);

Future<ApiException> refused(Future<Object?> f) async {
  try {
    await f;
  } on ApiException catch (e) {
    return e;
  }
  fail('expected a refusal');
}

void main() {
  late ({MockServer server, MockDb db}) s;
  late DashboardApi api;
  final latte = item('latte');

  setUp(() {
    s = studioServer();
    api = DashboardApi(s.server);
  });

  test('GET studio: sizes with their lines and costs, by sort', () async {
    final a = await api.menu.getStudio(id: latte);
    expect(a.sizes.map((z) => z.label), ['Regular', 'Large']);
    expect(a.sizes.map((z) => z.price), [11500, 13500]);
    final regular = a.sizes.first;
    // 180 ml × 4.2 + 18 g × 95 + a 12oz cup 180 + a lid 60 = 2,706.
    expect(regular.costPiastres, 2706);
    expect(regular.costIncomplete, isFalse);
    expect(
      regular.recipe.map((l) => '${l.source}:${l.ingredientName}:${l.quantity}'),
      [
        'own:Full cream milk:180.000',
        'base:House espresso blend:18.000',
        'rule:12oz paper cup:1.000',
        'rule:Hot cup lid:1.000',
      ],
    );
    expect(a.modifierGroups.map((g) => g.name), containsAll(['Milk', 'Extras']));
    expect(a.recipeSteps.map((st) => st.presetSlug), [
      'pull-espresso',
      'steam-milk',
      'pour-latte-art',
    ]);
    expect(a.options, isEmpty);
  });

  test('GET studio: 404, the org guard, menu.items.read', () async {
    expect(
      (await refused(api.menu.getStudio(id: mockUuid('nope')))).status,
      404,
    );
    s.server.persona = Persona.dawamOnly;
    expect((await refused(api.menu.getStudio(id: latte))).status, 403);
  });

  test('writes need menu.items.edit (manager refused)', () async {
    s.server.persona = Persona.manager;
    final e = await refused(
      api.menu.putSizes(
        id: latte,
        body: const PutSizesRequest(
          sizes: [SizeInput(label: 'Regular', price: 100, isActive: true)],
        ),
      ),
    );
    expect(e.status, 403);
    expect(e.message, contains('menu.items.edit'));
    expect(
      (await refused(
        api.recipes.putRecipeSteps(
          menuItemId: latte,
          body: const PutRecipeStepsRequest(steps: []),
        ),
      )).message,
      contains('recipes.edit'),
    );
  });

  test('PUT sizes: refusals, then the replace-set persists', () async {
    expect(
      (await refused(
        api.menu.putSizes(
          id: latte,
          body: const PutSizesRequest(
            sizes: [SizeInput(label: 'A', price: 1, isActive: false)],
          ),
        ),
      )).status,
      400,
    );
    expect(
      (await refused(
        api.menu.putSizes(
          id: latte,
          body: const PutSizesRequest(
            sizes: [
              SizeInput(label: 'A', price: 1, isActive: true),
              SizeInput(label: 'A', price: 2, isActive: true),
            ],
          ),
        ),
      )).message,
      contains("Duplicate size label 'A'"),
    );
    final agg = await api.menu.putSizes(
      id: latte,
      body: const PutSizesRequest(
        sizes: [
          SizeInput(label: 'Large', price: 14000, sort: 0, isActive: true),
          SizeInput(label: 'Double', price: 16000, sort: 1, isActive: true),
        ],
      ),
    );
    expect(agg.sizes.map((z) => z.label), ['Large', 'Double']);
    // Regular is gone with its lines; Double picked up the base and rules.
    final again = await api.menu.getStudio(id: latte);
    expect(again.sizes.map((z) => z.price), [14000, 16000]);
    final double = again.sizes.last;
    // A new size has no base yet; the packaging rule applies.
    expect(double.recipe.map((l) => l.source).toSet(), {'rule'});
    expect(
      s.db[MenuTables.recipeLines].where(
        (l) => l['size_id'] == MenuSeedIds.size('latte', 'Regular'),
      ),
      isEmpty,
    );
  });

  test('PUT size recipe: own lines replaced, base and rules re-expanded', () async {
    final sizeId = MenuSeedIds.size('latte', 'Regular');
    expect(
      (await refused(
        api.menu.putSizeRecipe(
          sizeId: sizeId,
          body: PutRecipeRequest(
            lines: [
              RecipeLineInput(ingredientId: _ing('oat_milk'), quantity: 1, unit: 'ml'),
              RecipeLineInput(ingredientId: _ing('oat_milk'), quantity: 2, unit: 'ml'),
            ],
          ),
        ),
      )).message,
      contains('Duplicate ingredient'),
    );
    final r = await api.menu.putSizeRecipe(
      sizeId: sizeId,
      body: PutRecipeRequest(
        lines: [
          RecipeLineInput(ingredientId: _ing('oat_milk'), quantity: 200, unit: 'ml'),
          // An own line of the base's ingredient wins over the base.
          RecipeLineInput(ingredientId: _ing('house_blend'), quantity: 20, unit: 'g'),
        ],
      ),
    );
    expect(r.recipe.map((l) => '${l.source}:${l.ingredientName}'), [
      'own:Oat milk',
      'own:House espresso blend',
      'rule:12oz paper cup',
      'rule:Hot cup lid',
    ]);
    // 200 × 14 + 20 × 95 + 180 + 60 = 4,940.
    expect(r.costPiastres, 4940);
  });

  test('a linked copy: recipe 409, link info, unlink keeps the lines', () async {
    linkCopy(s.db, 'iced_spanish', 'spanish');
    final copy = item('iced_spanish');
    final e = await refused(
      api.menu.putSizeRecipe(
        sizeId: MenuSeedIds.size('iced_spanish', 'Regular'),
        body: const PutRecipeRequest(lines: []),
      ),
    );
    expect(e.status, 409);
    final info = await api.menu.getRecipeLink(id: copy);
    expect(info.recipeSourceItemName, 'Spanish Latte');
    expect(info.inSync, isTrue);
    final source = await api.menu.getRecipeLink(id: item('spanish'));
    expect(source.linkedCopyIds, [copy]);
    expect(source.inSync, isNull);
    await api.menu.deleteRecipeLink(id: copy);
    final a = await api.menu.getStudio(id: copy);
    expect(a.recipeSourceItemId, isNull);
    expect(a.sizes.first.recipe.map((l) => l.source).toSet(), {'own'});
  });

  test('PUT size base: an unknown base is refused; None removes base lines', () async {
    final sizeId = MenuSeedIds.size('latte', 'Regular');
    expect(
      (await refused(
        api.menu.putSizeBase(
          sizeId: sizeId,
          body: PutSizeBaseRequest(baseId: mockUuid('nope')),
        ),
      )).status,
      400,
    );
    final r = await api.menu.putSizeBase(
      sizeId: sizeId,
      body: const PutSizeBaseRequest(explicitNulls: {'base_id'}),
    );
    expect(r.baseId, isNull);
    expect(r.sizesChanged, 1);
    final a = await api.menu.getStudio(id: latte);
    expect(a.sizes.first.recipe.any((l) => l.source == 'base'), isFalse);
  });

  test('PUT modifier-groups: refusals; [] detaches; the overrides read back', () async {
    expect(
      (await refused(
        api.menu.putModifierGroups(
          id: latte,
          body: PutModifierGroupsRequest(
            groups: [GroupAttachInput(groupId: mockUuid('nope'))],
          ),
        ),
      )).status,
      400,
    );
    final a = await api.menu.putModifierGroups(
      id: latte,
      body: PutModifierGroupsRequest(
        groups: [
          GroupAttachInput(
            groupId: MenuSeedIds.group('milk'),
            sort: 0,
            minOverride: 1,
            isRequiredOverride: true,
            includedOptionIds: [MenuSeedIds.option('milk', 'full')],
          ),
        ],
      ),
    );
    final milk = a.modifierGroups.single;
    expect(milk.min, 1);
    expect(milk.isRequired, isTrue);
    expect(milk.options.where((o) => o.included).map((o) => o.id), [
      MenuSeedIds.option('milk', 'full'),
    ]);
    final none = await api.menu.putModifierGroups(
      id: latte,
      body: const PutModifierGroupsRequest(groups: []),
    );
    expect(none.modifierGroups, isEmpty);
  });

  test('PUT options: an item-private group; ids kept; [] clears a recipe', () async {
    final out = await api.menu.putItemOptions(
      id: latte,
      body: PutItemOptionsRequest(
        options: [
          ItemOptionInput(
            name: 'Extra foam',
            price: 500,
            isActive: true,
            recipe: [
              OptionRecipeLineInput(
                ingredientId: _ing('full_milk'),
                quantity: 30,
                unit: 'ml',
              ),
            ],
          ),
        ],
      ),
    );
    final id = out.single.id;
    // 30 ml × 4.2 = 126.
    expect(out.single.costPiastres, 126);
    final a = await api.menu.getStudio(id: latte);
    expect(a.options.single.id, id);
    // Not among the reusable groups.
    expect(a.modifierGroups.map((g) => g.name), isNot(contains('Options')));
    final cleared = await api.menu.putItemOptions(
      id: latte,
      body: PutItemOptionsRequest(
        options: [
          ItemOptionInput(id: id, name: 'Extra foam', price: 500, recipe: const []),
        ],
      ),
    );
    expect(cleared.single.id, id);
    expect(cleared.single.recipe, isEmpty);
  });

  test('PUT steps: validated before anything is written', () async {
    Future<ApiException> bad(List<RecipeStepInput> steps) =>
        refused(api.recipes.putRecipeSteps(
          menuItemId: latte,
          body: PutRecipeStepsRequest(steps: steps),
        ));
    expect(
      (await bad(const [RecipeStepInput(kind: 'preset', presetSlug: 'nope')]))
          .message,
      contains("Step 1: no such step 'nope'"),
    );
    expect(
      (await bad(const [RecipeStepInput(kind: 'custom')])).message,
      contains('Step 1 needs a name'),
    );
    expect(
      (await bad([RecipeStepInput(kind: 'custom', title: 'x', note: 'n' * 281)]))
          .message,
      contains("Step 1's note is too long"),
    );
    final out = await api.recipes.putRecipeSteps(
      menuItemId: latte,
      body: const PutRecipeStepsRequest(
        steps: [
          RecipeStepInput(kind: 'custom', titleAr: 'قلّب'),
          RecipeStepInput(kind: 'preset', presetSlug: 'blend'),
        ],
      ),
    );
    expect(out.map((st) => (st.name, st.nameAr)), [
      ('قلّب', 'قلّب'),
      ('Blend until smooth', 'اخلط حتى يصبح ناعمًا'),
    ]);
    expect(out.last.note, '30 seconds');
  });

  test('preview: price, deductions, cost, defaults', () async {
    final p = await api.menu.previewMenuItem(
      id: latte,
      body: PreviewRequest(
        sizeLabel: 'Large',
        optionIds: [MenuSeedIds.option('milk', 'oat')],
        quantity: 2,
        serviceMode: 'dine_in',
      ),
    );
    expect(p.sizeLabel, 'Large');
    expect(p.price.base, 13500);
    expect(p.price.options.single.priceDelta, 2500);
    expect(p.price.total, 32000);
    expect(p.defaults[MenuSeedIds.group('milk')], MenuSeedIds.option('milk', 'full'));
    final oat = p.deductions.firstWhere((d) => d.source == 'swap');
    expect(oat.name, 'Oat milk');
    expect(oat.quantity, 480);
    expect(oat.note, 'swapped from Full cream milk');
    final cups = p.deductions.where((d) => d.source == 'packaging');
    expect(cups.every((d) => d.skipped), isTrue);
    // 480 × 14 + 54 × 95 = 11,850 (dine-in: no packaging).
    expect(p.cost.total, 11850);
    expect(p.cost.costMissing, isFalse);
    expect(p.cost.marginPct, closeTo((32000 - 11850) / 32000, 1e-9));
  });

  test('preview: an option not offered here is refused', () async {
    final e = await refused(
      api.menu.previewMenuItem(
        id: item('v60'),
        body: PreviewRequest(optionIds: [MenuSeedIds.option('milk', 'oat')]),
      ),
    );
    expect(e.status, 400);
  });

  test('meal: both or neither; a slot must take the item', () async {
    seedBreakfastCombo(s.db);
    final e = await refused(
      api.menu.putMeal(
        id: latte,
        body: MealLinkWrite(comboId: comboId('breakfast')),
      ),
    );
    expect(e.code, 'MEAL_TARGET_INVALID');
    final wrong = await refused(
      api.menu.putMeal(
        id: latte,
        body: MealLinkWrite(
          comboId: comboId('breakfast'),
          slotId: slotId('breakfast', 'pastry'),
        ),
      ),
    );
    expect(wrong.message, 'That combo has no slot for this item.');
    await api.menu.putMeal(
      id: latte,
      body: MealLinkWrite(
        comboId: comboId('breakfast'),
        slotId: slotId('breakfast', 'drink'),
      ),
    );
    final full = await api.menu.getMenuItem(id: latte);
    expect(full.meal?.slotId, slotId('breakfast', 'drink'));
    s.server.persona = Persona.manager;
    expect(
      (await refused(
        api.menu.putMeal(
          id: latte,
          body: const MealLinkWrite(explicitNulls: {'combo_id', 'slot_id'}),
        ),
      )).status,
      403,
    );
  });

  test('combos: the list pages; a combo carries its slots', () async {
    seedBreakfastCombo(s.db);
    final page = await api.menu.listCombos(perPage: 200);
    expect(page.data.map((c) => c.name), ['Breakfast Combo']);
    expect(page.total, 1);
    final c = await api.menu.getCombo(id: comboId('breakfast'));
    expect(c.slots.map((sl) => sl.name), ['Hot drink', 'Pastry']);
    expect(c.price, 15000);
  });

  test('duplicate: a deep copy named "… (Copy)"', () async {
    final copy = await api.menu.duplicateItem(id: latte);
    expect(copy.name, 'Caffè Latte (Copy)');
    expect(copy.id, isNot(latte));
    expect(copy.sizes.map((z) => z.label), ['Regular', 'Large']);
    expect(copy.sizes.first.costPiastres, 2706);
    // The steps are not copied (the backend's duplicate leaves them).
    expect(copy.recipeSteps, isEmpty);
  });
}
