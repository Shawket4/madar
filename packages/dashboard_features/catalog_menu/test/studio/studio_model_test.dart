// The studio's pure rules: dirty signatures, seeding, validation, the save
// payloads (explicit nulls as the web's JSON keeps them), the grid's cost
// footer, the base picker's value, the allowlist toggle, the preview's
// selection and price line, and "Make it a meal"'s delta, against
// hand-computed figures.
import 'package:dashboard_api/dashboard_api.dart'
    show
        Combo,
        ComboChoice,
        ComboSlot,
        OrgIngredient,
        PreviewOptionPrice,
        PreviewPrice,
        StudioAggregate;
import 'package:dashboard_catalog_menu/src/shared/grid_model.dart';
import 'package:dashboard_catalog_menu/src/studio/meal_model.dart';
import 'package:dashboard_catalog_menu/src/studio/preview_model.dart';
import 'package:dashboard_catalog_menu/src/studio/studio_model.dart';
import 'package:flutter_test/flutter_test.dart';

StudioAggregate agg(Map<String, Object?> over) => StudioAggregate.fromJson({
  'id': 'm1',
  'org_id': 'o1',
  'name': 'Latte',
  'name_translations': {'ar': 'لاتيه'},
  'description': null,
  'category_id': null,
  'is_active': true,
  'availability': {'org_active': true, 'branches': <Object?>[]},
  'catalog_revision': 1,
  'modifier_groups': <Object?>[],
  'options': <Object?>[],
  'recipe_steps': <Object?>[],
  'sizes': <Object?>[],
  ...over,
});

Map<String, Object?> size(
  String id,
  String label,
  int price, {
  int sort = 0,
  bool active = true,
  List<Map<String, Object?>> recipe = const [],
}) => {
  'id': id,
  'label': label,
  'price': price,
  'sort': sort,
  'is_active': active,
  'base_id': null,
  'cost_piastres': 2706,
  'cost_incomplete': false,
  'recipe': recipe,
};

Map<String, Object?> line(String ing, String qty, {String? source}) => {
  'id': 'l-$ing',
  'ingredient_id': ing,
  'ingredient_name': ing,
  'quantity': qty,
  'unit': 'ml',
  'source': source,
};

OrgIngredient ing(String id, double? cost) => OrgIngredient.fromJson({
  'id': id,
  'org_id': 'o1',
  'name': id,
  'category_id': 'c',
  'category_name': 'Milk',
  'category_slug': 'milk',
  'unit': 'ml',
  'cost_per_unit': cost,
  'is_active': true,
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
});

void main() {
  group('seeding', () {
    test('sizes: active only, by sort; EGP text; plain quantities', () {
      final blocks = toSizeBlocks(
        agg({
          'sizes': [
            size('b', 'Large', 13500, sort: 1, recipe: [line('milk', '240.000')]),
            size('a', 'Regular', 11550, recipe: [line('milk', '180.500')]),
            size('c', 'Kids', 9000, sort: -1, active: false),
          ],
        }),
      );
      expect(blocks.map((b) => b.label), ['Regular', 'Large']);
      expect(blocks.map((b) => b.price), ['115.5', '135']);
      expect(blocks.first.lines.single.quantity, '180.5');
      expect(blocks.first.lines.single.source, LineSource.own);
      expect(blocks.first.serverCost?.piastres, 2706);
    });

    test('item: Arabic from the translations, description Arabic empty', () {
      final d = toItemDraft(agg({'category_id': 'c1'}));
      expect(d.nameAr, 'لاتيه');
      expect(d.descriptionAr, '');
      expect(d.categoryId, 'c1');
    });

    test('steps: a name typed in one language leaves Arabic empty', () {
      final steps = toStepDrafts(
        agg({
          'recipe_steps': [
            {
              'position': 1,
              'kind': 'custom',
              'name': 'Stir',
              'name_ar': 'Stir',
              'note': null,
              'note_ar': null,
              'animation_is_global': true,
            },
            {
              'position': 2,
              'kind': 'preset',
              'preset_slug': 'blend',
              'name': 'Blend',
              'name_ar': 'اخلط',
              'note': '30 seconds',
              'note_ar': null,
              'animation_is_global': true,
            },
          ],
        }),
      );
      expect(steps[0].title, 'Stir');
      expect(steps[0].titleAr, '');
      expect(steps[1].isPreset, isTrue);
      expect(steps[1].note, '30 seconds');
    });

    test('attachments: every option included collapses to null', () {
      final g = {
        'attachment_id': 'x',
        'group_id': 'g1',
        'name': 'Milk',
        'selection_type': 'single',
        'is_required': false,
        'min': 0,
        'max': 1,
        'sort': 0,
        'options': [
          for (final (id, inc) in [('o1', true), ('o2', true)])
            {
              'id': id,
              'name': id,
              'price': 0,
              'is_active': true,
              'is_default': false,
              'included': inc,
              'cost_incomplete': false,
              'recipe': <Object?>[],
            },
        ],
      };
      final all = toAttachDrafts(agg({'modifier_groups': [g]})).single;
      expect(all.includedOptionIds, isNull);
      final off = all.toggle('o2');
      expect(off.includedOptionIds, ['o1']);
      expect(off.toggle('o2').includedOptionIds, isNull);
    });
  });

  group('signatures', () {
    test('a blank or non-numeric quantity never dirties a recipe', () {
      const a = [GridLine(ingredientId: 'i', quantity: '', unit: 'g')];
      expect(ownRecipeSig(a), ownRecipeSig(const []));
      const b = [GridLine(ingredientId: 'i', quantity: '1.0', unit: 'g')];
      const c = [GridLine(ingredientId: 'i', quantity: '1', unit: 'g')];
      expect(ownRecipeSig(b), ownRecipeSig(c));
      const based = [
        GridLine(
          ingredientId: 'i',
          quantity: '9',
          unit: 'g',
          source: LineSource.base,
        ),
      ];
      expect(ownRecipeSig(based), ownRecipeSig(const []));
    });

    test('modifiers: the allowlist is compared sorted', () {
      AttachDraft d(List<String>? ids) => AttachDraft(
        groupId: 'g',
        name: 'G',
        selectionType: 'multi',
        min: 0,
        isRequired: false,
        allOptions: const [],
        includedOptionIds: ids,
      );
      expect(modifiersSig([d(['b', 'a'])]), modifiersSig([d(['a', 'b'])]));
      expect(modifiersSig([d(null)]), isNot(modifiersSig([d(const [])])));
    });

    test('steps: trimmed', () {
      expect(
        stepsSig(const [StepDraft(kind: 'custom', title: ' Stir ')]),
        stepsSig(const [StepDraft(kind: 'custom', title: 'Stir')]),
      );
    });
  });

  group('validation (MENU-STUDIO-014)', () {
    const item = ItemDraft(name: 'Latte');
    SizeBlock b(String label, String price) =>
        SizeBlock(key: label, label: label, price: price);

    test('in the web\'s order, first failure only', () {
      expect(
        validateStudio(
          item: const ItemDraft(name: ' '),
          blocks: [b('', 'x')],
          steps: const [],
          rows: const [],
        )?.key,
        'menu.studio.validate.nameRequired',
      );
      expect(
        validateStudio(item: item, blocks: [b(' ', '1')], steps: const [], rows: const [])
            ?.key,
        'menu.studio.validate.sizeLabel',
      );
      final dup = validateStudio(
        item: item,
        blocks: [b('Cup', '1'), b(' Cup ', '2')],
        steps: const [],
        rows: const [],
      );
      expect(dup?.key, 'menu.studio.validate.sizeLabelDup');
      expect(dup?.args, {'label': 'Cup'});
      expect(
        validateStudio(item: item, blocks: [b('Cup', '-1')], steps: const [], rows: const [])
            ?.args,
        {'name': 'Cup'},
      );
      // parseFloat: "12abc" is 12, a valid price.
      expect(
        validateStudio(item: item, blocks: [b('Cup', '12abc')], steps: const [], rows: const []),
        isNull,
      );
      expect(
        validateStudio(
          item: item,
          blocks: const [],
          steps: const [StepDraft(kind: 'custom', titleAr: ' ')],
          rows: const [],
        )?.key,
        'menu.studio.validate.stepName',
      );
      expect(
        validateStudio(
          item: item,
          blocks: const [],
          steps: const [StepDraft.preset('blend')],
          rows: const [OptionRow(name: 'Foam', price: '')],
        )?.args,
        {'name': 'Foam'},
      );
    });
  });

  group('payloads', () {
    test('item: {} for an empty Arabic name; nulls kept', () {
      final j = itemPayload(
        const ItemDraft(name: 'Latte'),
        imageRemoved: true,
      ).toJson();
      expect(j, {
        'name': 'Latte',
        'name_translations': <String, Object?>{},
        'description': null,
        'description_translations': <String, Object?>{},
        'category_id': null,
        'is_active': true,
        'image_url': null,
      });
      expect(
        itemPayload(
          const ItemDraft(name: 'L', categoryId: 'c'),
          imageRemoved: false,
        ).toJson().containsKey('image_url'),
        isFalse,
      );
    });

    test('sizes: piastres, trimmed labels, column order', () {
      final j = sizesPayload([
        const SizeBlock(key: 'a', label: ' Cup ', price: '12.345'),
      ]).toJson();
      expect(j, {
        'sizes': [
          {'is_active': true, 'label': 'Cup', 'price': 1235, 'sort': 0},
        ],
      });
    });

    test('steps: a preset sends its slug and notes; a written one its names',
        () {
      final j = stepsPayload(const [
        StepDraft(kind: 'preset', presetSlug: 'blend', note: ' 30 s '),
        StepDraft(kind: 'custom', titleAr: 'قلّب'),
      ]).toJson();
      expect(j['steps'], [
        {'kind': 'preset', 'note': '30 s', 'note_ar': null, 'preset_slug': 'blend'},
        {
          'kind': 'custom',
          'note': null,
          'note_ar': null,
          'title': null,
          'title_ar': 'قلّب',
        },
      ]);
    });

    test('modifiers: max and the allowlist are sent even when null', () {
      final j = modifiersPayload(const [
        AttachDraft(
          groupId: 'g',
          name: 'G',
          selectionType: 'multi',
          min: 1,
          isRequired: true,
          allOptions: [],
        ),
      ]).toJson();
      expect(j, {
        'groups': [
          {
            'group_id': 'g',
            'included_option_ids': null,
            'is_required_override': true,
            'max_override': null,
            'min_override': 1,
            'sort': 0,
          },
        ],
      });
      expect(modifiersPayload(const []).toJson(), {'groups': <Object?>[]});
    });

    test('options: deduction, cleared deduction, no usable quantity', () {
      final j = optionsPayload(const [
        OptionRow(name: ' Foam ', price: '5', ingredientId: 'i', quantity: '20', unit: 'ml'),
        OptionRow(id: 'o2', name: 'Plain', price: '0'),
        OptionRow(name: 'Half', price: '1', ingredientId: 'i', quantity: ''),
      ]).toJson();
      final opts = (j['options']! as List).cast<Map<String, Object?>>();
      expect(opts[0], {
        'is_active': true,
        'name': 'Foam',
        'price': 500,
        'recipe': [
          {'ingredient_id': 'i', 'quantity': 20.0, 'unit': 'ml'},
        ],
      });
      expect(opts[1]['id'], 'o2');
      expect(opts[1]['recipe'], <Object?>[]);
      expect(opts[2].containsKey('recipe'), isTrue);
      expect(opts[2]['recipe'], isNull);
    });
  });

  group('grid', () {
    final catalog = {'milk': ing('milk', 4.2), 'syrup': ing('syrup', null)};
    SizeBlock col(List<GridLine> lines, {String price = '115', bool isNew = false}) =>
        SizeBlock(
          key: 'a',
          id: isNew ? null : 'a',
          label: 'R',
          price: price,
          seededPrice: '115',
          serverCost: (piastres: 2706, incomplete: false),
          lines: lines,
        );

    test('the server cost unless edited; the estimate then', () {
      final lines = [const GridLine(ingredientId: 'milk', quantity: '180', unit: 'ml')];
      final server = columnCost(col(lines), catalog, recipeDirty: false);
      expect(server, isA<CostKnown>());
      expect((server as CostKnown).piastres, 2706);
      expect(server.estimated, isFalse);
      expect(server.margin, closeTo((11500 - 2706) / 11500, 1e-9));
      final est = columnCost(col(lines), catalog, recipeDirty: true) as CostKnown;
      expect(est.piastres, closeTo(756, 1e-9));
      expect(est.estimated, isTrue);
      expect(
        columnCost(col(lines, price: '116'), catalog, recipeDirty: false),
        isA<CostKnown>().having((c) => c.estimated, 'estimated', isTrue),
      );
    });

    test('an uncosted line: incomplete; no line: "—"; price 0: no margin', () {
      expect(
        columnCost(
          col([const GridLine(ingredientId: 'syrup', quantity: '5', unit: 'g')]),
          catalog,
          recipeDirty: true,
        ),
        isA<CostIncomplete>(),
      );
      expect(columnCost(col(const []), catalog, recipeDirty: true), isA<NoLines>());
      final free = columnCost(
        col([const GridLine(ingredientId: 'milk', quantity: '10', unit: 'ml')], price: '0'),
        catalog,
        recipeDirty: true,
      ) as CostKnown;
      expect(free.margin, isNull);
    });

    test('adding a size to a one-price item blanks the sentinel', () {
      final next = addSizeBlock([
        const SizeBlock(
          key: 'a',
          id: 'a',
          label: 'one_size',
          price: '95',
          lines: [GridLine(ingredientId: 'milk', quantity: '60', unit: 'ml')],
        ),
      ]);
      expect(next.map((b) => b.label), ['', '']);
      expect(next.last.price, '0');
      expect(next.last.isNew, isTrue);
      expect(next.last.lines.single.quantity, '');
    });

    test('moving out of range changes nothing', () {
      final blocks = [
        const SizeBlock(key: 'a', label: 'A', price: '1'),
        const SizeBlock(key: 'b', label: 'B', price: '1'),
      ];
      expect(moveSizeBlock(blocks, 'a', -1), same(blocks));
      expect(moveSizeBlock(blocks, 'a', 1).map((b) => b.key), ['b', 'a']);
    });

    test('the base value', () {
      expect(baseValueOf(const []), isA<BaseNone>());
      expect(baseValueOf(const [(id: 'a', baseId: null)]), isA<BaseNone>());
      expect(
        baseValueOf(const [(id: 'a', baseId: 'x'), (id: 'b', baseId: 'x')]),
        isA<BaseOne>().having((b) => b.id, 'id', 'x'),
      );
      expect(
        baseValueOf(const [(id: 'a', baseId: 'x'), (id: 'b', baseId: null)]),
        isA<BaseMixed>(),
      );
    });
  });

  group('preview model', () {
    const single = PreviewGroup(
      id: 'milk',
      name: 'Milk',
      single: true,
      required: false,
      options: [(id: 'full', name: 'Full', price: 0), (id: 'oat', name: 'Oat', price: 2500)],
    );
    const multi = PreviewGroup(
      id: 'extras',
      name: 'Extras',
      single: false,
      required: false,
      max: 2,
      options: [
        (id: 'shot', name: 'Shot', price: 3000),
        (id: 'van', name: 'Vanilla', price: 2000),
        (id: 'car', name: 'Caramel', price: 2000),
      ],
    );
    const defaults = {'milk': 'full'};

    test('single: replaces; clears unless required', () {
      var sel = const PreviewSelection();
      expect(pickedIn(sel, 'milk', defaults), ['full']);
      sel = togglePick(sel, single, 'oat', defaults);
      expect(pickedIn(sel, 'milk', defaults), ['oat']);
      sel = togglePick(sel, single, 'oat', defaults);
      expect(pickedIn(sel, 'milk', defaults), isEmpty);
      const req = PreviewGroup(
        id: 'milk',
        name: 'Milk',
        single: true,
        required: true,
        options: [],
      );
      final kept = togglePick(const PreviewSelection(), req, 'full', defaults);
      expect(pickedIn(kept, 'milk', defaults), ['full']);
    });

    test('multi: toggles up to max', () {
      var sel = const PreviewSelection();
      for (final id in ['shot', 'van', 'car']) {
        sel = togglePick(sel, multi, id, defaults);
      }
      expect(pickedIn(sel, 'extras', defaults), ['shot', 'van']);
      sel = togglePick(sel, multi, 'shot', defaults);
      expect(pickedIn(sel, 'extras', defaults), ['van']);
    });

    test('the body: defaults for untouched groups, quantity ≥ 1', () {
      final body = toPreviewBody(
        const PreviewSelection(quantity: 0, optionals: ['opt']),
        [single, multi],
        defaults,
      ).toJson();
      expect(body, {
        'option_ids': ['full', 'opt'],
        'quantity': 1,
        'service_mode': 'takeaway',
      });
    });

    test('the price line', () {
      String plain(num p) => '${p ~/ 100}';
      final p = PreviewPrice.fromJson({
        'base': 15000,
        'options': [
          {'option_id': 'a', 'name': 'a', 'price_delta': 5500, 'reason': 'adds'},
          {'option_id': 'b', 'name': 'b', 'price_delta': 0, 'reason': 'none'},
          {'option_id': 'c', 'name': 'c', 'price_delta': 3000, 'reason': 'adds'},
        ],
        'total': 23500,
      });
      expect(priceLine(p, 1, plain), '150 + 55 + 30 = 235');
      expect(priceLine(p, 2, plain), '(150 + 55 + 30) × 2 = 235');
      expect(PreviewOptionPrice, isNotNull);
    });
  });

  group('make it a meal (meal.ts)', () {
    ComboChoice choice(
      String? item,
      String? cat, {
      int surcharge = 0,
      String? included,
      List<(String, int)> extras = const [],
    }) => ComboChoice.fromJson({
      'id': 'c-${item ?? cat}',
      'menu_item_id': item,
      'category_id': cat,
      'surcharge': surcharge,
      'included_size_label': included,
      'size_surcharges': [
        for (final (l, s) in extras) {'size_label': l, 'surcharge': s},
      ],
      'sort': 0,
    });
    ComboSlot slot(String id, List<ComboChoice> choices, {int min = 1, String? def, String? defSize}) =>
        ComboSlot.fromJson({
          'id': id,
          'name': id,
          'name_translations': <String, Object?>{},
          'sort': 0,
          'min': min,
          'max': 1,
          'default_item_id': def,
          'default_size_label': defSize,
          'choices': [for (final c in choices) c.toJson()],
        });
    Combo combo(List<ComboSlot> slots) => Combo.fromJson({
      'id': 'k',
      'kind': 'combo',
      'name': 'K',
      'name_translations': <String, Object?>{},
      'description_translations': <String, Object?>{},
      'price': 15000,
      'is_active': true,
      'is_fixed': false,
      'available_now': true,
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
      'windows': <Object?>[],
      'slots': [for (final s in slots) s.toJson()],
      'economics': {
        'price': 15000,
        'list_default': 15000,
        'list_min': 15000,
        'list_max': 15000,
        'saving_default': 0,
        'warnings': <Object?>[],
      },
    });
    const latte = MealItem(
      id: 'latte',
      categoryId: 'hot',
      sizes: [(label: 'Regular', price: 11500), (label: 'Large', price: 13500)],
    );
    const croissant = MealItem(
      id: 'croissant',
      categoryId: 'bakery',
      sizes: [(label: 'one_size', price: 6500)],
    );
    const juice = MealItem(
      id: 'juice',
      categoryId: 'juice',
      sizes: [(label: 'Small', price: 6000), (label: 'Big', price: 8000)],
    );
    MealItem? lookup(String id) =>
        {'latte': latte, 'croissant': croissant, 'juice': juice}[id];

    test('the item\'s own choice wins over its category', () {
      final s = slot('d', [choice(null, 'hot'), choice('latte', null, surcharge: 500)]);
      expect(choiceFor(s, 'latte', 'hot')?.surcharge, 500);
      expect(slotsAdmitting(combo([s]), 'tea', 'tea'), isEmpty);
    });

    test('+X: the combo with defaults minus the item alone', () {
      final k = combo([
        slot('drink', [choice(null, 'hot', included: 'Regular')]),
        slot('pastry', [choice('croissant', null)], def: 'croissant'),
      ]);
      // 150 + 0 (own) + 0 (croissant) − 115 = 35.
      expect(mealDelta(k, 'drink', latte, lookup), 3500);
    });

    test('a default at another size pays the owner\'s surcharge, else the '
        'difference', () {
      final k = combo([
        slot('drink', [choice(null, 'hot', included: 'Regular')]),
        slot(
          'side',
          [choice('juice', null, included: 'Small')],
          def: 'juice',
          defSize: 'Big',
        ),
        slot(
          'big',
          [choice('juice', null, included: 'Small', extras: [('Big', 1500)])],
          def: 'juice',
          defSize: 'Big',
          min: 2,
        ),
      ]);
      // 150 + (80 − 60) + 2 × 15 − 115 = 85.
      expect(mealDelta(k, 'drink', latte, lookup), 8500);
    });

    test('unknown slot or price: null', () {
      final k = combo([slot('drink', [choice(null, 'hot', included: 'Kids')])]);
      expect(mealDelta(k, 'nope', latte, lookup), isNull);
      expect(mealDelta(k, 'drink', latte, lookup), isNull);
    });
  });
}
