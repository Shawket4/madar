// The choice-group rules as pure functions: the web's group-model.test.ts
// ported case by case (inventory §8.15), plus the list badges, the seeding
// of the editor and its validation (with the hidden-field divergence,
// MENU-GRP-049).
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_catalog_menu/src/groups/group_form.dart';
import 'package:dashboard_catalog_menu/src/groups/group_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

const _m = GroupMessages(
  required: 'req',
  maxAtLeastOne: 'max',
  swapNeedsIngredient: 'swap',
  swapNeedsCategory: 'cat',
  duplicateIngredient: 'dup',
  qtyPositive: 'qty',
  priceMin: 'min',
  notANumber: 'nan',
);

GroupOut _group({
  String selection = 'single',
  int min = 0,
  int? max = 1,
  bool required = false,
  String effect = 'adds',
  String? type = 'extra',
  String? slug,
  String? categoryId,
  List<GroupOptionOut> options = const [],
}) => GroupOut(
  id: 'g',
  orgId: 'o',
  name: 'Group',
  nameTranslations: const {'ar': 'مجموعة'},
  selectionType: selection,
  minSelections: min,
  maxSelections: max,
  isRequired: required,
  isActive: true,
  effect: effect,
  legacyAddonType: type,
  swapCategorySlug: slug,
  swapCategoryId: categoryId,
  sort: 0,
  options: options,
);

OptionDraft _opt({
  String name = 'Oat',
  String price = '55',
  String swap = '',
  List<OptionLineDraft>? lines,
}) => OptionDraft(
  key: UniqueKey(),
  name: name,
  price: price,
  swapIngredientId: swap,
  lines: lines,
);

OptionLineDraft _line(String id, String qty, [String? label]) =>
    OptionLineDraft(
      ingredientId: id,
      quantity: qty,
      unit: 'g',
      sizeLabel: label,
    );

void main() {
  group('pick rule ⇄ selection fields', () {
    test('maps each rule onto selection_type / min / max / required', () {
      expect(pickRuleToSelection(const PickRule.exactlyOne()), (
        selectionType: 'single',
        minSelections: 1,
        maxSelections: 1,
        isRequired: true,
      ));
      expect(pickRuleToSelection(const PickRule.upTo(1)), (
        selectionType: 'single',
        minSelections: 0,
        maxSelections: 1,
        isRequired: false,
      ));
      expect(pickRuleToSelection(const PickRule.upTo(3)), (
        selectionType: 'multi',
        minSelections: 0,
        maxSelections: 3,
        isRequired: false,
      ));
      expect(pickRuleToSelection(const PickRule.any()), (
        selectionType: 'multi',
        minSelections: 0,
        maxSelections: null,
        isRequired: false,
      ));
    });

    test('round-trips every rule', () {
      for (final r in const [
        PickRule.exactlyOne(),
        PickRule.upTo(1),
        PickRule.upTo(4),
        PickRule.any(),
      ]) {
        final s = pickRuleToSelection(r);
        expect(
          selectionToPickRule(
            selectionType: s.selectionType,
            minSelections: s.minSelections,
            maxSelections: s.maxSelections,
            isRequired: s.isRequired,
          ),
          r,
        );
      }
    });

    test('reads prod shapes', () {
      expect(
        selectionToPickRule(
          selectionType: 'single',
          minSelections: 1,
          maxSelections: 1,
          isRequired: true,
        ),
        const PickRule.exactlyOne(),
      );
      expect(
        selectionToPickRule(
          selectionType: 'single',
          minSelections: 0,
          maxSelections: 1,
          isRequired: true,
        ),
        const PickRule.exactlyOne(),
      );
      expect(
        selectionToPickRule(
          selectionType: 'multi',
          minSelections: 0,
          maxSelections: null,
          isRequired: false,
        ),
        const PickRule.any(),
      );
      expect(
        selectionToPickRule(
          selectionType: 'single',
          minSelections: 0,
          maxSelections: null,
          isRequired: false,
        ),
        const PickRule.upTo(1),
      );
    });

    test('swap groups always pick exactly one', () {
      expect(
        formPickRule(pick: PickKind.any, upTo: 3, effect: GroupEffect.swaps),
        const PickRule.exactlyOne(),
      );
      expect(
        formPickRule(pick: PickKind.upTo, upTo: 3, effect: GroupEffect.adds),
        const PickRule.upTo(3),
      );
    });
  });

  group('effect ⇄ legacy_addon_type', () {
    test('swaps map to the swap families', () {
      expect(
        effectToLegacyType(GroupEffect.swaps, SwapTarget.milk, 'Milk'),
        'milk_type',
      );
      expect(
        effectToLegacyType(GroupEffect.swaps, SwapTarget.beans, 'Beans'),
        'coffee_type',
      );
      expect(
        effectToLegacyType(GroupEffect.swaps, SwapTarget.beans, 'V60 Beans', [
          'coffee_type',
        ]),
        'coffee_type',
      );
    });

    test('adds / nothing derive a type from the name', () {
      expect(
        effectToLegacyType(GroupEffect.adds, null, 'Red Bull Type'),
        'red_bull_type',
      );
      expect(
        effectToLegacyType(GroupEffect.none, null, '  Bread choice '),
        'bread_choice',
      );
      expect(
        effectToLegacyType(GroupEffect.adds, null, 'Flavour', ['flavour']),
        'flavour_2',
      );
      expect(
        effectToLegacyType(GroupEffect.adds, null, 'Flavour', [
          'flavour',
          'flavour_2',
        ]),
        'flavour_3',
      );
    });

    test('never lets a name smuggle in a swap family', () {
      expect(effectToLegacyType(GroupEffect.adds, null, 'Milk type'), 'extra');
      expect(effectToLegacyType(GroupEffect.adds, null, 'Coffee'), 'extra');
      expect(effectToLegacyType(GroupEffect.none, null, 'الحليب'), 'extra');
    });

    test('reads the effect back', () {
      expect(legacyTypeToEffect('milk_type', true), (
        effect: GroupEffect.swaps,
        swapTarget: SwapTarget.milk,
      ));
      expect(legacyTypeToEffect('coffee_type', false), (
        effect: GroupEffect.swaps,
        swapTarget: SwapTarget.beans,
      ));
      expect(legacyTypeToEffect('extra', true), (
        effect: GroupEffect.adds,
        swapTarget: null,
      ));
      expect(legacyTypeToEffect(null, false), (
        effect: GroupEffect.none,
        swapTarget: null,
      ));
    });

    test('prefers the explicit effect, falls back to the legacy type', () {
      expect(
        groupEffect(
          effect: 'none',
          legacyAddonType: 'milk_type',
          anyOptionHasLines: false,
        ),
        GroupEffect.none,
      );
      expect(
        groupEffect(
          effect: null,
          legacyAddonType: 'milk_type',
          anyOptionHasLines: false,
        ),
        GroupEffect.swaps,
      );
      expect(
        groupEffect(
          effect: 'legacy',
          legacyAddonType: 'extra',
          anyOptionHasLines: true,
        ),
        GroupEffect.adds,
      );
    });
  });

  group('option recipe lines', () {
    String? unitOf(String id) => id == 'oat' ? 'g' : null;

    test("a swap writes one line of 1 in the ingredient's unit", () {
      expect(
        optionRecipeLines(
          GroupEffect.swaps,
          swapIngredientId: 'oat',
          lines: const [],
          unitOf: unitOf,
        ),
        [(ingredientId: 'oat', quantity: 1.0, unit: 'g', sizeLabel: null)],
      );
      expect(
        optionRecipeLines(
          GroupEffect.swaps,
          swapIngredientId: 'soy',
          lines: const [],
          unitOf: unitOf,
        ).single.unit,
        'pcs',
      );
    });

    test('adds writes the typed lines, labels passed through; nothing writes '
        'none', () {
      final lines = [
        _line('syrup', '15'),
        _line('syrup', '20', 'Can'),
        _line('ice', '5', ''),
      ];
      final adds = optionRecipeLines(
        GroupEffect.adds,
        swapIngredientId: '',
        lines: lines,
        unitOf: unitOf,
      );
      expect([for (final l in adds) l.sizeLabel], [null, 'Can', null]);
      expect(adds.first.quantity, 15);
      expect(
        optionRecipeLines(
          GroupEffect.none,
          swapIngredientId: '',
          lines: lines,
          unitOf: unitOf,
        ),
        isEmpty,
      );
    });
  });

  group('validation', () {
    test('a swap option needs its ingredient; a swap group its category', () {
      final d = GroupDraft(
        name: 'Milk',
        effect: GroupEffect.swaps,
        swapCategoryId: 'cat-milk',
        options: [_opt()],
      );
      expect(validateGroup(d, _m), {GroupField.optionSwap(0): 'swap'});
      d.options.first.swapIngredientId = 'oat';
      expect(validateGroup(d, _m), isEmpty);
      d.swapCategoryId = '';
      expect(validateGroup(d, _m), {GroupField.swapCategory: 'cat'});
      d.effect = GroupEffect.adds;
      expect(validateGroup(d, _m), isEmpty);
    });

    test('one line per (ingredient, size label)', () {
      final d = GroupDraft(
        name: 'Syrups',
        options: [
          _opt(
            lines: [
              _line('syrup', '15'),
              _line('syrup', '20', 'Can'),
              _line('syrup', '25', 'Can'),
            ],
          ),
        ],
      );
      // The plain list (the grid holds one cell per size by construction).
      d.options.first.perSize = false;
      expect(validateGroup(d, _m), {GroupField.lineIngredient(0, 2): 'dup'});
      d.options.first.lines = [_line('syrup', '15'), _line('syrup', '15', '')];
      expect(validateGroup(d, _m), {GroupField.lineIngredient(0, 1): 'dup'});
    });

    test('name, option name, amount, price and the "Up to" count', () {
      final d = GroupDraft(
        name: ' ',
        pick: PickKind.upTo,
        upTo: '',
        options: [
          _opt(name: '', price: '.', lines: [_line('', '0')]),
        ],
      );
      expect(validateGroup(d, _m), {
        GroupField.name: 'req',
        GroupField.upTo: 'max',
        GroupField.optionName(0): 'req',
        GroupField.optionPrice(0): 'nan',
        GroupField.lineIngredient(0, 0): 'req',
        GroupField.lineQuantity(0, 0): 'qty',
      });
    });

    test('MENU-GRP-049 (divergence) hidden fields are not checked', () {
      final d = GroupDraft(
        name: 'Extras',
        pick: PickKind.any,
        upTo: '',
        effect: GroupEffect.none,
        options: [
          _opt(lines: [_line('', '0')]),
        ],
      );
      expect(validateGroup(d, _m), isEmpty);
      d
        ..effect = GroupEffect.swaps
        ..swapCategoryId = 'milk';
      d.options.first.swapIngredientId = 'oat';
      expect(validateGroup(d, _m), isEmpty);
    });

    test('a per-size grid with a 0 cell says so under the grid', () {
      final o = _opt(lines: [_line('syrup', '0', 'Large')]);
      expect(o.perSize, isTrue);
      final d = GroupDraft(name: 'Toppings', options: [o]);
      expect(validateGroup(d, _m), {GroupField.optionGrid(0): 'qty'});
    });
  });

  group('the editor form', () {
    test('single choice keeps one default', () {
      final d = GroupDraft(
        pick: PickKind.exactlyOne,
        options: [_opt(), _opt(), _opt()],
      );
      d.setDefault(0, true);
      d.setDefault(2, true);
      expect([for (final o in d.options) o.isDefault], [false, false, true]);
      d.pick = PickKind.any;
      d.setDefault(0, true);
      expect([for (final o in d.options) o.isDefault], [true, false, true]);
    });

    test('per size off keeps the unlabelled lines; on drops blank lines', () {
      final o = _opt(
        lines: [_line('syrup', '10'), _line('syrup', '15', 'Large')],
      );
      o.togglePerSize(false, const ['Regular'], 'All sizes');
      expect([for (final l in o.lines) l.sizeLabel], [null]);
      o
        ..lines.add(_line('', '3'))
        ..togglePerSize(true, const ['Regular'], 'All sizes');
      expect(o.lines, hasLength(1));
      expect([for (final b in o.blocks!) b.label], ['All sizes', 'Regular']);
    });

    test('cost: every line costed in its own unit', () {
      ({double? costPerUnit, String unit})? costOf(String id) => switch (id) {
        'blend' => (costPerUnit: 95, unit: 'g'),
        'paste' => (costPerUnit: null, unit: 'g'),
        _ => null,
      };
      expect(optionLinesCost([_line('blend', '18')], costOf), 1710);
      expect(optionLinesCost([_line('paste', '5')], costOf), isNull);
      expect(
        optionLinesCost([
          const OptionLineDraft(
            ingredientId: 'blend',
            quantity: '1',
            unit: 'kg',
          ),
        ], costOf),
        isNull,
      );
      expect(optionLinesCost(const [], costOf), isNull);
    });

    test(
      'seeding: pick rule, effect, legacy swap category, options by sort',
      () {
        final g = _group(
          selection: 'multi',
          max: 2,
          effect: 'swaps',
          type: 'coffee_type',
          options: [
            GroupOptionOut(
              id: 'b',
              name: 'Ethiopia',
              nameTranslations: const {'ar': 'إثيوبيا'},
              price: 2500,
              isDefault: false,
              isActive: true,
              sort: 1,
              recipe: const [
                GroupOptionRecipeLine(
                  ingredientId: 'eth',
                  ingredientName: 'Ethiopia',
                  quantity: 1,
                  unit: 'g',
                ),
              ],
            ),
            const GroupOptionOut(
              id: 'a',
              name: 'House',
              nameTranslations: null,
              price: 0,
              isDefault: true,
              isActive: true,
              sort: 0,
              replacesIngredientId: 'house',
            ),
          ],
        );
        expect(seedGroupDraft(g, null), isNull);
        final d = seedGroupDraft(g, [
          IngredientCategory(
            id: 'cat-beans',
            orgId: 'o',
            name: 'Coffee beans',
            slug: 'coffee_bean',
            ingredientCount: 2,
            isPackaging: false,
            sortOrder: 0,
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
        ])!;
        expect(d.effect, GroupEffect.swaps);
        expect(d.pick, PickKind.upTo);
        expect(d.upTo, '2');
        expect(d.swapCategoryId, 'cat-beans');
        expect(d.nameAr, 'مجموعة');
        expect([for (final o in d.options) o.id], ['a', 'b']);
        expect(
          [for (final o in d.options) o.swapIngredientId],
          ['house', 'eth'],
        );
        expect(d.options[1].price, '25');
        expect(d.options[1].nameAr, 'إثيوبيا');
        expect(seedGroupDraft(null, null)!.effect, GroupEffect.adds);
        expect(seedGroupDraft(null, null)!.pick, PickKind.any);
      },
    );
  });

  group('the list', () {
    test('only shared groups, by sort then name', () {
      GroupOut g(String name, int sort, String? type) => GroupOut(
        id: name,
        orgId: 'o',
        name: name,
        nameTranslations: null,
        selectionType: 'multi',
        minSelections: 0,
        isRequired: false,
        isActive: true,
        effect: 'adds',
        legacyAddonType: type,
        sort: sort,
        options: const [],
      );
      expect(
        [
          for (final x in sharedGroups([
            g('b', 1, 'b'),
            g('Options', 0, null),
            g('a', 1, 'a'),
            g('z', 0, 'z'),
          ]))
            x.name,
        ],
        ['z', 'a', 'b'],
      );
    });

    test('badges', () {
      expect(pickBadge(_group(required: true)), (
        'menu.groups.pick.exactlyOneShort',
        null,
      ));
      expect(pickBadge(_group(selection: 'multi', max: 3)), (
        'menu.groups.pick.upToShort',
        3,
      ));
      expect(pickBadge(_group(selection: 'multi', max: null)), (
        'menu.groups.pick.anyShort',
        null,
      ));
      expect(
        effectBadgeKey(
          _group(effect: 'swaps', type: 'milk_type', slug: 'milk'),
        ),
        'menu.groups.effect.swapsMilk',
      );
      expect(
        effectBadgeKey(_group(effect: 'adds', type: 'coffee_type')),
        'menu.groups.effect.swapsBeans',
      );
      expect(
        effectBadgeKey(_group(effect: 'swaps', type: 'syrup', slug: 'syrup')),
        'menu.groups.effect.swapsOther',
      );
      expect(
        effectBadgeKey(_group(effect: 'swaps', type: 'x')),
        'menu.groups.effect.swapsMilk',
      );
      expect(effectBadgeKey(_group(effect: 'none')), 'menu.groups.effect.none');
      expect(
        effectBadgeKey(_group(effect: 'odd')),
        'menu.groups.effect.addsOrNothing',
      );
      expect(shownName('Milk', const {'ar': 'اللبن'}, 'ar'), 'اللبن');
      expect(shownName('Milk', const {'ar': ''}, 'ar'), 'Milk');
      expect(shownName('Milk', const {'ar': '  '}, 'ar'), 'Milk');
      expect(shownName('Milk', null, 'ar'), 'Milk');
      expect(shownName('Milk', const {'ar': 'اللبن'}, 'en'), 'Milk');
      expect(arrayMove([1, 2, 3, 4], 0, 2), [2, 3, 1, 4]);
      expect(arrayMove([1, 2, 3, 4], 3, 1), [1, 4, 2, 3]);
    });
  });
}
