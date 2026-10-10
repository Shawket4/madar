// The combo form's rules and mappings, as the web's `form-schema.test.ts`
// pins them: the refusals the server would 400 on, EGP text ↔ piastres,
// blank size extras meaning "the usual difference", a window's hours and
// dates, and the tolerant body the price check asks with.
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_catalog_offers/src/combo_editor/combo_form.dart';
import 'package:dashboard_catalog_offers/src/shared/menu_options.dart';
import 'package:dashboard_catalog_offers/src/shared/sale_window_form.dart';
import 'package:flutter_test/flutter_test.dart';

const _burger = 'item-burger';
const _fries = 'item-fries';
const _drinks = 'cat-drinks';

ComboDraft _lunch() => ComboDraft(
  name: 'Lunch deal',
  nameAr: 'وجبة الغداء',
  price: '150',
  slots: [
    SlotDraft.empty().copyWith(
      name: 'Main',
      defaultItemId: _burger,
      choices: [ChoiceDraft.empty().copyWith(menuItemId: _burger)],
    ),
    SlotDraft.empty().copyWith(
      name: 'Side',
      choices: [ChoiceDraft.empty().copyWith(menuItemId: _fries)],
    ),
    SlotDraft.empty().copyWith(
      name: 'Drink',
      nameAr: 'مشروب',
      choices: [
        ChoiceDraft.empty(ChoiceTarget.category).copyWith(
          categoryId: _drinks,
          includedSizeLabel: 'Regular',
          sizeSurcharges: const [
            (label: 'Large', surcharge: '8'),
            (label: 'XL', surcharge: ''),
          ],
        ),
      ],
    ),
  ],
);

ComboDraft _withSlot(ComboDraft v, int i, SlotDraft Function(SlotDraft) f) =>
    v.copyWith(
      slots: [
        for (var j = 0; j < v.slots.length; j++)
          j == i ? f(v.slots[j]) : v.slots[j],
      ],
    );

void main() {
  group('combo form rules', () {
    test('accepts a meal deal with a category slot', () {
      expect(validateCombo(_lunch()).isEmpty, isTrue);
    });

    test('OFFR-CED-031 refuses min above max on the min field', () {
      final v = _withSlot(_lunch(), 1, (s) => s.copyWith(min: '3', max: '2'));
      expect(validateCombo(v).slot(1).min, ComboErrorKeys.minOverMax);
    });

    test('OFFR-CED-034 refuses a slot with no choices', () {
      final v = _withSlot(
        _lunch(),
        0,
        (s) => s.copyWith(choices: const [], defaultItemId: ''),
      );
      expect(validateCombo(v).slot(0).choices, ComboErrorKeys.noChoices);
    });

    test('OFFR-CED-031/039/043/036 max = 0, no slots, a blank choice, a '
        'duplicate and a stray default', () {
      final zero = _withSlot(
        _lunch(),
        0,
        (s) => s.copyWith(min: '0', max: '0'),
      );
      expect(validateCombo(zero).slot(0).max, ComboErrorKeys.maxZero);

      final none = _lunch().copyWith(slots: const []);
      expect(validateCombo(none).slots, ComboErrorKeys.slotsRequired);

      final blank = _withSlot(
        _lunch(),
        1,
        (s) => s.copyWith(choices: [...s.choices, ChoiceDraft.empty()]),
      );
      expect(
        validateCombo(blank).slot(1).choiceErrors[1].target,
        ComboErrorKeys.choiceTarget,
      );

      final dup = _withSlot(
        _lunch(),
        1,
        (s) => s.copyWith(
          choices: [
            ...s.choices,
            ChoiceDraft.empty().copyWith(menuItemId: _fries),
          ],
        ),
      );
      expect(
        validateCombo(dup).slot(1).choiceErrors[1].target,
        ComboErrorKeys.choiceDuplicate,
      );

      final stray = _withSlot(
        _lunch(),
        1,
        (s) => s.copyWith(defaultItemId: _burger),
      );
      expect(
        validateCombo(stray).slot(1).defaultItem,
        ComboErrorKeys.defaultNotChoice,
      );
      // A category choice admits items the form cannot list: no error.
      final viaCategory = _withSlot(
        _lunch(),
        2,
        (s) => s.copyWith(defaultItemId: _burger),
      );
      expect(validateCombo(viaCategory).slot(2).defaultItem, isNull);
    });

    test('OFFR-CED-082 a blank "At least" is 0; a blank "At most" is 0 (max '
        'must be 1 or more); 1.5 or 11 is out of range', () {
      final blankMin = _withSlot(_lunch(), 0, (s) => s.copyWith(min: ''));
      expect(validateCombo(blankMin).isEmpty, isTrue);
      expect(blankMin.toWire().slots[0].min, 0);

      final blankMax = _withSlot(_lunch(), 0, (s) => s.copyWith(max: ''));
      expect(validateCombo(blankMax).slot(0).max, ComboErrorKeys.maxZero);

      final half = _withSlot(_lunch(), 0, (s) => s.copyWith(min: '1.5'));
      expect(validateCombo(half).slot(0).min, ComboErrorKeys.pickRange);

      final big = _withSlot(_lunch(), 0, (s) => s.copyWith(max: '11'));
      expect(validateCombo(big).slot(0).max, ComboErrorKeys.pickRange);
    });

    test(
      'OFFR-CED-055/056/057 a window\'s days, hours pair and date order',
      () {
        final v = _lunch().copyWith(
          windows: [
            WindowDraft.empty().copyWith(weekdays: 0),
            WindowDraft.empty().copyWith(startsAt: '12:00'),
            WindowDraft.empty().copyWith(startsAt: '12:00', endsAt: '12:00'),
            WindowDraft.empty().copyWith(
              validFrom: '2026-10-10',
              validTo: '2026-10-01',
            ),
          ],
        );
        final w = validateCombo(v).windows;
        expect(w[0]!.weekdays, 'combos.errors.noDays');
        expect(w[1]!.endsAt, 'combos.errors.hoursPair');
        expect(w[2]!.endsAt, 'combos.errors.hoursSame');
        expect(w[3]!.validTo, 'combos.errors.datesOrder');
      },
    );

    test('OFFR-CED-021 refuses a blank or negative price but never looks at '
        'margins', () {
      expect(
        validateCombo(_lunch().copyWith(price: '')).price,
        ComboErrorKeys.money,
      );
      expect(
        validateCombo(_lunch().copyWith(price: '-5')).price,
        ComboErrorKeys.money,
      );
      expect(validateCombo(_lunch().copyWith(price: '99999')).isEmpty, isTrue);
    });

    test('OFFR-CED-083 money boxes read like JavaScript\'s Number()', () {
      String? priceError(String text) =>
          validateCombo(_lunch().copyWith(price: text)).price;
      expect(priceError(' 150 '), isNull);
      expect(priceError('1,000'), ComboErrorKeys.money);
      expect(priceError('١٥٠'), ComboErrorKeys.money);
      expect(_lunch().copyWith(price: '.5').toWire().price, 50);
      expect(_lunch().copyWith(price: '1e2').toWire().price, 10000);
      expect(_lunch().copyWith(price: '19.99').toWire().price, 1999);
    });

    test('OFFR-CED-046/049 a negative extra or size extra is refused; a '
        'blank one is not', () {
      final v = _withSlot(
        _lunch(),
        2,
        (s) => s.copyWith(
          choices: [
            s.choices.single.copyWith(
              surcharge: '-1',
              sizeSurcharges: const [(label: 'Large', surcharge: '-2')],
            ),
          ],
        ),
      );
      final e = validateCombo(v).slot(2).choiceErrors.single;
      expect(e.surcharge, ComboErrorKeys.money);
      expect(e.badSizes, {'Large'});
    });
  });

  group('combo form ↔ wire', () {
    test('OFFR-CED-077 writes piastres, translations, and drops blank size '
        'surcharges', () {
      final v = _lunch().copyWith(
        windows: [
          WindowDraft.empty().copyWith(
            weekdays: 62,
            startsAt: '12:00:00',
            endsAt: '16:00',
            validFrom: '2026-10-01',
          ),
        ],
      );
      final w = v.toWire().toJson();
      expect(w['price'], 15000);
      expect(w['name_translations'], {'ar': 'وجبة الغداء'});
      final slots = (w['slots']! as List).cast<Map<String, Object?>>();
      expect(slots.map((s) => s['sort']), [0, 1, 2]);
      expect(slots[0]['min'], 1);
      expect(slots[0]['default_item_id'], _burger);
      expect(slots[0]['name_translations'], <String, Object?>{});
      final drink = (slots[2]['choices']! as List).single as Map;
      expect(drink['menu_item_id'], isNull);
      expect(drink.containsKey('menu_item_id'), isTrue);
      expect(drink['category_id'], _drinks);
      expect(drink['surcharge'], 0);
      expect(drink['included_size_label'], 'Regular');
      expect(drink['size_surcharges'], [
        {'size_label': 'Large', 'surcharge': 800},
      ]);
      expect(w['windows'], [
        {
          'branch_id': null,
          'weekdays': 62,
          'starts_at': '12:00',
          'ends_at': '16:00',
          'valid_from': '2026-10-01',
          'valid_to': null,
        },
      ]);
    });

    test('OFFR-CED-020/023/073 reads a saved combo back into the same form '
        '(ids kept for the in-place diff)', () {
      final w = _lunch()
          .copyWith(description: '  ', descriptionAr: ' وصف ')
          .toWire()
          .toJson();
      expect(w['description'], isNull);
      expect(w['description_translations'], {'ar': 'وصف'});
      final slots = (w['slots']! as List).cast<Map<String, Object?>>();
      final saved = Combo.fromJson({
        ...w,
        'id': 'combo-1',
        'kind': 'combo',
        'image_url': null,
        'is_active': true,
        'is_fixed': false,
        'available_now': true,
        'created_at': '2026-10-01T09:00:00Z',
        'updated_at': '2026-10-01T09:00:00Z',
        'slots': [
          for (final (i, s) in slots.indexed)
            {
              ...s,
              'id': 'slot-$i',
              'choices': [
                for (final (j, c)
                    in (s['choices']! as List)
                        .cast<Map<String, Object?>>()
                        .indexed)
                  {...c, 'id': 'ch-$i-$j'},
              ],
            },
        ],
        'economics': {
          'price': 15000,
          'list_default': 21000,
          'list_min': 19000,
          'list_max': 26000,
          'saving_default': 6000,
          'warnings': <Object?>[],
        },
      });
      final back = ComboDraft.fromWire(saved);
      expect(back.price, '150');
      expect(back.slots[2].id, 'slot-2');
      expect(back.slots[2].nameAr, 'مشروب');
      final ch = back.slots[2].choices.single;
      expect(ch.id, 'ch-2-0');
      expect(ch.target, ChoiceTarget.category);
      expect(ch.sizeSurcharges, [(label: 'Large', surcharge: '8')]);
      expect(ch.surcharge, '');
      final again = back.toWire();
      expect(again.slots[2].id, 'slot-2');
      expect(again.slots[2].choices.single.id, 'ch-2-0');
      expect(back.fingerprint(), ComboDraft.fromWire(saved).fingerprint());
    });

    test('OFFR-CED-061/062 asks the price check only once a price and a real '
        'slot exist', () {
      expect(_lunch().copyWith(price: '').economicsBody(), isNull);
      expect(
        _lunch().copyWith(slots: [SlotDraft.empty()]).economicsBody(),
        isNull,
      );
      final half = _withSlot(
        _lunch(),
        1,
        (s) => s.copyWith(choices: [...s.choices, ChoiceDraft.empty()]),
      );
      final body = half.economicsBody()!;
      expect(body['price'], 15000);
      final slots = (body['slots']! as List).cast<Map<String, Object?>>();
      expect(slots[1]['choices'], hasLength(1));
      expect(body['windows'], isEmpty);
      expect(body['description'], isNull);
    });

    test('OFFR-CED-008 the fixed-bundle rule', () {
      expect(isFixedDraft(_lunch().slots), isFalse);
      expect(isFixedDraft(_lunch().slots.take(2).toList()), isTrue);
      expect(isFixedDraft(const []), isFalse);
      final ranged = _withSlot(_lunch(), 0, (s) => s.copyWith(max: '2'));
      expect(isFixedDraft(ranged.slots.take(2).toList()), isFalse);
    });
  });

  test('OFFR-CED-041 pick lists sort like localeCompare: case, accents and '
      'the Arabic alef forms folded', () {
    List<String> sorted(List<String> names) => [...names]..sort(compareNames);
    expect(sorted(['banana Bread', 'Americano', 'Éclair', 'Caffè Latte']), [
      'Americano',
      'banana Bread',
      'Caffè Latte',
      'Éclair',
    ]);
    expect(sorted(['تارت', 'إسبريسو', 'آيس لاتيه', 'أمريكانو']), [
      'إسبريسو',
      'أمريكانو',
      'آيس لاتيه',
      'تارت',
    ]);
    expect(compareNames('Latte', 'latte'), isNot(0));
  });
}
