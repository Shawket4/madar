// The rules the wizard computes in the browser and the mock's checklist
// against hand-computed figures (ADM-ONB-004, 008, 016, 019, 021, 027; the
// backend's `load_status`).
import 'package:dashboard_admin/src/mock/onboarding_mock.dart';
import 'package:dashboard_admin/src/onboarding/dialogs/addon_dialog.dart';
import 'package:dashboard_admin/src/onboarding/dialogs/menu_item_dialog.dart';
import 'package:dashboard_admin/src/onboarding/dialogs/payment_method_dialog.dart';
import 'package:dashboard_admin/src/onboarding/onboarding_config.dart';
import 'package:dashboard_admin/src/onboarding/onboarding_data.dart';
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

OnboardingStep _step(String key, int n, {bool required = false}) =>
    OnboardingStep(key: key, done: n > 0, count: n, required_: required);

OnboardingStatus _status(List<OnboardingStep> steps) => OnboardingStatus(
  orgId: 'org',
  completed: false,
  canComplete: false,
  recipeCoverage: 0,
  steps: steps,
);

final _t = Translator(Strings.empty(), 'en');

void main() {
  group('ADM-ONB-004 progress', () {
    test('round(done required ÷ required × 100); 0 with none', () {
      expect(readyPercent(null), 0);
      expect(readyPercent(_status([_step('team', 3)])), 0);
      expect(
        readyPercent(
          _status([
            _step('branch', 1, required: true),
            _step('payment_methods', 0, required: true),
            _step('categories', 0, required: true),
          ]),
        ),
        33,
      );
      expect(
        readyPercent(
          _status([
            _step('branch', 1, required: true),
            _step('payment_methods', 2, required: true),
            _step('categories', 0, required: true),
          ]),
        ),
        67,
      );
    });

    test('the cheer thresholds', () {
      expect(cheerKey(100), 'onboarding.cheer.done');
      expect(cheerKey(75), 'onboarding.cheer.most');
      expect(cheerKey(74), 'onboarding.cheer.half');
      expect(cheerKey(50), 'onboarding.cheer.half');
      expect(cheerKey(49), 'onboarding.cheer.start');
      expect(cheerKey(1), 'onboarding.cheer.start');
      expect(cheerKey(0), 'onboarding.cheer.go');
    });
  });

  group('ADM-ONB-008 the opening step', () {
    test('the first step whose status is not done, in wizard order', () {
      expect(firstIncomplete(const {}), OnbStep.orgProfile);
      final byKey = stepsByKey(
        _status([
          _step('org_profile', 1),
          _step('branch', 1, required: true),
          _step('payment_methods', 0, required: true),
          _step('ingredients', 0),
        ]),
      );
      expect(firstIncomplete(byKey), OnbStep.paymentMethods);
    });

    test('everything done: the finale', () {
      final byKey = stepsByKey(
        _status([
          for (final s in OnbStep.values)
            if (s.statusKey case final k?) _step(k, 1),
        ]),
      );
      expect(firstIncomplete(byKey), OnbStep.goLive);
    });

    test('the steps and stages, in order', () {
      expect(
        [for (final s in OnbStep.values) s.key],
        [
          'org_profile',
          'branch',
          'payment_methods',
          'ingredients',
          'categories',
          'menu_items',
          'addons',
          'recipes',
          'team',
          'go_live',
        ],
      );
      expect(OnbStage.menu.steps, [
        OnbStep.ingredients,
        OnbStep.categories,
        OnbStep.menuItems,
        OnbStep.addons,
        OnbStep.recipes,
      ]);
    });
  });

  group('the mock checklist (load_status)', () {
    test('a fresh café: nothing done, completion refused', () {
      final db = MockDb.seeded();
      loadSeedFor(db);
      freshCafe(db);
      final s = onboardingStatus(db, sabah);
      expect(s['completed'], isFalse);
      expect(s['can_complete'], isFalse);
      expect(s['recipe_coverage'], 0.0);
      expect(
        [
          for (final step in (s['steps']! as List).cast<Map<String, Object?>>())
            (step['key'], step['count'], step['required']),
        ],
        [
          ('org_profile', 0, false),
          ('branch', 0, true),
          ('payment_methods', 0, true),
          ('categories', 0, true),
          ('menu_items', 0, true),
          ('ingredients', 0, false),
          ('recipes', 0, false),
          ('addons', 0, false),
          ('team', 0, false),
          ('first_order', 0, false),
        ],
      );
    });

    test('ADM-ONB-027 coverage = items with a recipe ÷ live active items; '
        'inactive payment methods and items are not counted', () {
      final db = MockDb.seeded();
      loadSeedFor(db);
      everythingDone(db);
      final cat = db[OnbTables.categories].rows.firstWhere(
        (c) => c['org_id'] == sabah,
      );
      addItem(db, cat, name: 'Mocha', ar: 'موكا');
      addItem(db, cat, name: 'Old', ar: 'قديم')['is_active'] = false;
      addPaymentMethod(db, name: 'old')['is_active'] = false;
      final s = onboardingStatus(db, sabah);
      final by = {
        for (final step in (s['steps']! as List).cast<Map<String, Object?>>())
          step['key']: step['count'],
      };
      expect(by['menu_items'], 2);
      expect(by['recipes'], 1);
      expect(by['payment_methods'], 1);
      expect(by['addons'], 1);
      expect(by['team'], 1);
      expect(by['org_profile'], 1);
      expect(s['recipe_coverage'], 0.5);
      expect(s['can_complete'], isTrue);
    });

    test('Sabah as seeded finished its checklist long ago', () {
      final db = MockDb.seeded();
      loadSeedFor(db);
      final s = onboardingStatus(db, sabah);
      expect(s['completed'], isTrue);
      expect(s['completed_at'], isNotNull);
    });
  });

  group('editors', () {
    test('ADM-ONB-016 the identifier and its words', () {
      expect(pmIdentifier('Visa Card!'), 'visa_card_');
      expect(pmIdentifier('INSTAPAY'), 'instapay');
      expect(validatePaymentMethod(name: '', labelEn: '', t: _t), {
        'name': 'common.requiredField',
        'labelEn': 'common.requiredField',
      });
      expect(validatePaymentMethod(name: 'a-b', labelEn: 'A', t: _t), {
        'name': 'settings.pm.idError',
      });
      expect(
        validatePaymentMethod(name: 'visa', labelEn: 'Visa', t: _t),
        isEmpty,
      );
    });

    test('ADM-ONB-019 add-on words: name, group, a price of 0 or more', () {
      expect(validateAddon(name: '', groupId: '', price: '0', t: _t).keys, [
        'name',
        'group_id',
      ]);
      expect(
        validateAddon(name: 'Oat', groupId: 'g', price: '', t: _t),
        isEmpty,
      );
      expect(validateAddon(name: 'Oat', groupId: 'g', price: '.', t: _t), {
        'default_price': 'onboarding.form.notANumber',
      });
    });

    test('ADM-ONB-021 item words and the add-on groups an item offers', () {
      expect(
        validateMenuItem(
          name: '',
          categoryId: '',
          sizes: [SizeDraft(key: 0, label: '')],
          t: _t,
        ).keys,
        ['name', 'category_id', 'sizes.0.label'],
      );
      final addons = [
        for (final (id, type) in [
          ('oat', 'milk_type'),
          ('shot', 'extras'),
          ('soy', 'milk_type'),
          ('lost', 'gone'),
        ])
          AddonItem(
            id: id,
            orgId: 'o',
            name: id,
            nameTranslations: const {},
            addonType: type,
            defaultPrice: 0,
            isActive: true,
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
      ];
      GroupOut group(String id, String? type, String name) => GroupOut(
        id: id,
        orgId: 'o',
        name: name,
        nameTranslations: const {},
        selectionType: 'multi',
        minSelections: 0,
        isRequired: false,
        isActive: true,
        sort: 0,
        effect: 'none',
        legacyAddonType: type,
        options: const [],
      );
      final groups = [
        group('g-milk', 'milk_type', 'Milk'),
        group('g-x', null, 'extras'),
      ];
      final out = addonAttachments(
        ['shot', 'oat', 'lost', 'soy'],
        addons,
        groups,
      );
      expect(
        [for (final a in out) a.toJson()],
        [
          {
            'group_id': 'g-x',
            'included_option_ids': ['shot'],
            'sort': 0,
          },
          {
            'group_id': 'g-milk',
            'included_option_ids': ['oat', 'soy'],
            'sort': 1,
          },
        ],
      );
      expect(selectionKey({'b', 'a'}), selectionKey(['a', 'b']));
    });
  });
}

/// The admin seed on top of the core seed (as the area registers it).
void loadSeedFor(MockDb db) =>
    registerOnboardingArea(MockServer(clock: db.clock), db);
