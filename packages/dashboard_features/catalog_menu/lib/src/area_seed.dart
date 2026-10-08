/// The menu area's own domain data, on top of the core seed
/// (`package:dashboard_api/mock.dart`: Sabah Coffee's 7 categories, 40 items
/// with their sizes, the Milk and Extras groups and their options), shared by
/// every unit so their numbers agree:
///
/// - the org ingredient catalog and its categories (unit costs in piastres);
/// - a COMPLETE size table: the core seed only stores sizes for items with
///   more than one; a simple item gets its `one_size` row here, as the backend
///   always has one (`sort` and `base_id` added to every row);
/// - each size's recipe lines (`own`, plus the `base` and `rule` lines the
///   backend expands at write time), two recipe bases and five packaging
///   rules, the option recipes of the shared groups, branch and channel
///   price overrides, the step library and a few items' steps.
///
/// [CatalogMenuData] answers what several handlers compute the backend's way:
/// a size's lines and cost, an item's `sku_costs`, the add-on view over the
/// groups' options, the expansion of bases / rules / linked copies, and
/// `POST /packaging-rules/apply`. Units add page-only data in their own mock
/// files, through these tables.
library;

import 'package:dashboard_api/mock.dart';

import 'shared/menu_text.dart';

/// The [MockDb] tables this area keeps (rows are the wire JSON).
abstract final class MenuTables {
  static const String ingredientCategories = 'ingredient_categories';

  /// `OrgIngredient` rows.
  static const String ingredients = 'org_ingredients';

  /// The core seed's size table, completed: `{id, menu_item_id, label,
  /// price_override, is_active, sort, base_id}`.
  static const String sizes = 'item_sizes';

  /// One row per stored size recipe line: `{id, size_id, menu_item_id,
  /// ingredient_id, quantity (decimal text), unit, source, sort}`.
  static const String recipeLines = 'size_recipe_lines';

  /// `RecipeBaseOut`-shaped rows without the computed counts:
  /// `{id, org_id, name, name_ar, is_active, lines: [{id, ingredient_id,
  /// quantity, unit, size_label, sort}], created_at, updated_at}`.
  static const String bases = 'recipe_bases';

  /// `PackagingRuleOut`-shaped rows (lines without names).
  static const String rules = 'packaging_rules';

  /// `RecipeStepPreset` rows.
  static const String stepPresets = 'recipe_step_presets';

  /// `{id, menu_item_id, position, kind, preset_slug, name, name_ar, note,
  /// note_ar}`.
  static const String steps = 'recipe_steps';

  /// The unified override table: `{id, scope (branch | branch_channel),
  /// branch_id, channel, target_type (menu_item_size | modifier_option),
  /// target_id, price, is_available}`.
  static const String priceOverrides = 'menu_price_overrides';

  /// The core seed's groups (`GroupOut` rows); this area adds the options'
  /// `recipe` and `replaces_ingredient_id` and the swap category.
  static const String groups = 'modifier_groups';

  /// The core seed's item↔group attachments (`{id, menu_item_id, group_id,
  /// sort}`; units may add the per-item override fields).
  static const String groupLinks = 'item_group_links';
  static const String categories = 'categories';
  static const String menuItems = 'menu_items';
}

/// Stable ids of this area's seed rows.
abstract final class MenuSeedIds {
  static String ingredientCategory(String key) =>
      mockUuid('ingredient-category:$key');
  static String ingredient(String key) => mockUuid('ingredient:$key');
  static String base(String key) => mockUuid('recipe-base:$key');
  static String rule(String key) => mockUuid('packaging-rule:$key');

  /// A size of a core-seed item (`one_size` for a simple item).
  static String size(String itemKey, String label) =>
      MockSeed.sizeId(itemKey, label);
  static String item(String key) => MockSeed.menuItemId(key);
  static String category(String key) => MockSeed.categoryId(key);
  static String group(String key) => MockSeed.groupId(key);
  static String option(String group, String key) =>
      MockSeed.optionId(group, key);
}

/// The org's channels besides in-store (`branch` scope).
const List<String> menuChannels = ['in_mall', 'outside', 'umbrella', 'pickup'];

// ── data ──────────────────────────────────────────────────────────────────

const List<(String, String, bool)> _ingredientCategories = [
  ('general', 'General', false),
  ('coffee_bean', 'Coffee beans', false),
  ('milk', 'Milk', false),
  ('dairy', 'Dairy', false),
  ('syrup', 'Syrups & sauces', false),
  ('tea', 'Tea & botanicals', false),
  ('fruit', 'Fruit', false),
  ('bakery', 'Bakery stock', false),
  ('packaging', 'Packaging', true),
];

/// (key, name, category, unit, piastres per unit or null, active).
const List<(String, String, String, String, double?, bool)> _ingredients = [
  ('house_blend', 'House espresso blend', 'coffee_bean', 'g', 95, true),
  ('ethiopia', 'Ethiopia Yirgacheffe', 'coffee_bean', 'g', 180, true),
  (
    'turkish_coffee',
    'Turkish coffee with cardamom',
    'coffee_bean',
    'g',
    90,
    true,
  ),
  ('full_milk', 'Full cream milk', 'milk', 'ml', 4.2, true),
  ('skimmed_milk', 'Skimmed milk', 'milk', 'ml', 4, true),
  ('oat_milk', 'Oat milk', 'milk', 'ml', 14, true),
  ('almond_milk', 'Almond milk', 'milk', 'ml', 16, true),
  ('coconut_milk', 'Coconut milk', 'milk', 'ml', 15, true),
  ('lactose_free_milk', 'Lactose-free milk', 'milk', 'ml', 6, true),
  ('condensed_milk', 'Condensed milk', 'dairy', 'g', 9, true),
  ('whipped_cream', 'Whipped cream', 'dairy', 'g', 12, true),
  ('vanilla_syrup', 'Vanilla syrup', 'syrup', 'ml', 8, true),
  ('caramel_syrup', 'Caramel syrup', 'syrup', 'ml', 8, true),
  ('hazelnut_syrup', 'Hazelnut syrup', 'syrup', 'ml', 8.5, true),
  ('chocolate_sauce', 'Chocolate sauce', 'syrup', 'g', 10, true),
  // No unit cost yet: Pistachio Latte reads "cost incomplete" / "Set cost".
  ('pistachio_paste', 'Pistachio paste', 'syrup', 'g', null, true),
  ('vanilla_powder', 'Vanilla powder', 'syrup', 'g', 40, false),
  ('matcha', 'Matcha powder', 'tea', 'g', 250, true),
  ('chai', 'Chai concentrate', 'tea', 'ml', 10, true),
  ('hibiscus', 'Dried hibiscus', 'tea', 'g', 30, true),
  ('green_tea', 'Green tea leaves', 'tea', 'g', 60, true),
  ('mint', 'Fresh mint', 'tea', 'g', 20, true),
  ('cocoa', 'Cocoa powder', 'general', 'g', 30, true),
  ('sugar', 'Sugar', 'general', 'g', 3, true),
  ('ice', 'Ice', 'general', 'g', 0.2, true),
  ('oranges', 'Oranges', 'fruit', 'g', 3, true),
  ('mangoes', 'Mangoes', 'fruit', 'g', 6, true),
  ('strawberries', 'Strawberries', 'fruit', 'g', 8, true),
  ('lemons', 'Lemons', 'fruit', 'g', 4, true),
  ('croissant_dough', 'Butter croissant (frozen)', 'bakery', 'pcs', 1800, true),
  ('pain_choc_dough', 'Pain au chocolat (frozen)', 'bakery', 'pcs', 2200, true),
  ('almond_cream', 'Almond cream', 'bakery', 'g', 35, true),
  ('cup_8oz', '8oz paper cup', 'packaging', 'pcs', 150, true),
  ('cup_12oz', '12oz paper cup', 'packaging', 'pcs', 180, true),
  ('cup_16oz', '16oz paper cup', 'packaging', 'pcs', 210, true),
  ('hot_lid', 'Hot cup lid', 'packaging', 'pcs', 60, true),
  ('sleeve', 'Cup sleeve', 'packaging', 'pcs', 50, true),
  ('cup_16oz_clear', '16oz clear cup', 'packaging', 'pcs', 220, true),
  ('dome_lid', 'Dome lid', 'packaging', 'pcs', 90, true),
  ('straw', 'Paper straw', 'packaging', 'pcs', 40, true),
];

/// The items whose sizes follow a base, by base key.
const Map<String, List<String>> _baseItems = {
  'espresso': [
    'espresso',
    'americano',
    'cortado',
    'flatwhite',
    'cappuccino',
    'latte',
    'spanish',
    'mocha',
    'pistachio_latte',
    'iced_americano',
    'iced_latte',
    'iced_spanish',
    'iced_mocha',
    'frappe',
  ],
  'iced_build': ['cold_brew', 'iced_matcha'],
};

/// (key, name, Arabic name, active, lines: (size label or null, ingredient,
/// quantity)).
const List<(String, String, String?, bool, List<(String?, String, num)>)>
_bases = [
  (
    'espresso',
    'Espresso shot',
    'شوت إسبريسو',
    true,
    [
      (null, 'house_blend', 18),
      ('Large', 'house_blend', 27),
      ('Double', 'house_blend', 36),
    ],
  ),
  (
    'iced_build',
    'Iced build',
    'تجهيز المشروبات المثلجة',
    true,
    [(null, 'ice', 150), ('Large', 'ice', 200)],
  ),
  (
    'mocha_old',
    'Mocha base (old)',
    null,
    false,
    [(null, 'chocolate_sauce', 25)],
  ),
];

/// (key, name, match category key, match size label, match item key, active,
/// lines: (ingredient, quantity)).
const List<
  (String, String, String?, String?, String?, bool, List<(String, num)>)
>
_rules = [
  (
    'hot_any',
    'Hot cup',
    'hot',
    null,
    null,
    true,
    [('cup_8oz', 1), ('hot_lid', 1)],
  ),
  (
    'hot_regular',
    'Hot cup · Regular',
    'hot',
    'Regular',
    null,
    true,
    [('cup_12oz', 1), ('hot_lid', 1)],
  ),
  (
    'hot_large',
    'Hot cup · Large',
    'hot',
    'Large',
    null,
    true,
    [('cup_16oz', 1), ('hot_lid', 1), ('sleeve', 1)],
  ),
  (
    'iced',
    'Iced cup',
    'iced',
    null,
    null,
    true,
    [('cup_16oz_clear', 1), ('dome_lid', 1), ('straw', 1)],
  ),
  (
    'juice',
    'Juice cup',
    'juice',
    null,
    null,
    true,
    [('cup_16oz_clear', 1), ('straw', 1)],
  ),
  (
    'espresso_cup',
    'Espresso to go (paused)',
    null,
    null,
    'espresso',
    false,
    [('cup_8oz', 1)],
  ),
];

/// Own recipe lines: item key -> size label -> (ingredient, quantity).
const Map<String, Map<String, List<(String, num)>>> _ownLines = {
  'cortado': {
    oneSize: [('full_milk', 60)],
  },
  'flatwhite': {
    oneSize: [('full_milk', 120)],
  },
  'cappuccino': {
    'Regular': [('full_milk', 150)],
    'Large': [('full_milk', 210)],
  },
  'latte': {
    'Regular': [('full_milk', 180)],
    'Large': [('full_milk', 240)],
  },
  'spanish': {
    'Regular': [('full_milk', 160), ('condensed_milk', 25)],
    'Large': [('full_milk', 220), ('condensed_milk', 35)],
  },
  'mocha': {
    'Regular': [('full_milk', 170), ('chocolate_sauce', 25)],
    'Large': [('full_milk', 230), ('chocolate_sauce', 35)],
  },
  'pistachio_latte': {
    'Regular': [('full_milk', 170), ('pistachio_paste', 15)],
    'Large': [('full_milk', 230), ('pistachio_paste', 20)],
  },
  'v60': {
    oneSize: [('ethiopia', 20)],
  },
  'turkish': {
    'Single': [('turkish_coffee', 8), ('sugar', 5)],
    'Double': [('turkish_coffee', 16), ('sugar', 10)],
  },
  'iced_americano': {
    'Regular': [('ice', 150)],
    'Large': [('ice', 200)],
  },
  'iced_latte': {
    'Regular': [('full_milk', 200), ('ice', 150)],
    'Large': [('full_milk', 260), ('ice', 200)],
  },
  'iced_spanish': {
    'Regular': [('full_milk', 180), ('condensed_milk', 30), ('ice', 150)],
    'Large': [('full_milk', 240), ('condensed_milk', 40), ('ice', 200)],
  },
  'iced_mocha': {
    'Regular': [('full_milk', 180), ('chocolate_sauce', 30), ('ice', 150)],
    'Large': [('full_milk', 240), ('chocolate_sauce', 40), ('ice', 200)],
  },
  'cold_brew': {
    'Regular': [('ethiopia', 30)],
    'Large': [('ethiopia', 40)],
  },
  'frappe': {
    'Regular': [('full_milk', 150), ('caramel_syrup', 20), ('ice', 200)],
    'Large': [('full_milk', 200), ('caramel_syrup', 30), ('ice', 260)],
  },
  'iced_matcha': {
    'Regular': [('matcha', 4), ('full_milk', 220)],
    'Large': [('matcha', 6), ('full_milk', 280)],
  },
  'matcha': {
    'Regular': [('matcha', 4), ('full_milk', 200)],
    'Large': [('matcha', 6), ('full_milk', 260)],
  },
  'chai': {
    'Regular': [('chai', 60), ('full_milk', 160)],
    'Large': [('chai', 80), ('full_milk', 220)],
  },
  'hot_choc': {
    oneSize: [('cocoa', 25), ('full_milk', 220), ('sugar', 10)],
  },
  'mint_lemonade': {
    oneSize: [('lemons', 120), ('mint', 5), ('sugar', 25), ('ice', 150)],
  },
  'hibiscus': {
    oneSize: [('hibiscus', 10), ('sugar', 15)],
  },
  // Hand-entered packaging (counted by "keep hand-entered packaging").
  'green_tea': {
    oneSize: [('green_tea', 3), ('cup_8oz', 1)],
  },
  'orange': {
    oneSize: [('oranges', 450)],
  },
  'mango': {
    oneSize: [('mangoes', 300), ('sugar', 10)],
  },
  'strawberry': {
    oneSize: [('strawberries', 250), ('sugar', 15)],
  },
  'croissant': {
    oneSize: [('croissant_dough', 1)],
  },
  'almond_croissant': {
    oneSize: [('croissant_dough', 1), ('almond_cream', 30)],
  },
  'pain_choc': {
    oneSize: [('pain_choc_dough', 1)],
  },
};

/// What each shared option deducts: group -> option -> (ingredient, quantity).
/// A Milk (swap) option pours its milk instead of the drink's own.
const Map<String, Map<String, (String, num)>> _optionRecipes = {
  'milk': {
    'full': ('full_milk', 1),
    'skimmed': ('skimmed_milk', 1),
    'oat': ('oat_milk', 1),
    'almond': ('almond_milk', 1),
    'coconut': ('coconut_milk', 1),
    'lactose_free': ('lactose_free_milk', 1),
  },
  'extras': {
    'shot': ('house_blend', 18),
    'vanilla': ('vanilla_syrup', 15),
    'caramel': ('caramel_syrup', 15),
    'hazelnut': ('hazelnut_syrup', 15),
    'cream': ('whipped_cream', 30),
  },
};

/// (branch, channel or null, item key, size label, price piastres or null,
/// available false or null).
final List<(String, String?, String, String, int?, bool?)> _sizeOverrides = [
  (SeedIds.zamalek, null, 'spanish', 'Regular', 14000, null),
  (SeedIds.zamalek, null, 'spanish', 'Large', 16000, null),
  (SeedIds.zamalek, null, 'pistachio_latte', 'Regular', null, false),
  (SeedIds.zamalek, null, 'pistachio_latte', 'Large', null, false),
  (SeedIds.zamalek, 'outside', 'iced_latte', 'Regular', 14500, null),
  (SeedIds.maadi, null, 'turkish', 'Single', null, false),
  (SeedIds.maadi, null, 'turkish', 'Double', null, false),
  (SeedIds.heliopolis, 'umbrella', 'croissant', oneSize, 8500, null),
];

/// (branch, channel or null, group, option, price or null, available or null).
final List<(String, String?, String, String, int?, bool?)> _optionOverrides = [
  (SeedIds.zamalek, null, 'milk', 'oat', 3000, null),
  (SeedIds.zamalek, 'in_mall', 'milk', 'almond', null, false),
];

/// (slug, name, Arabic, note, Arabic note).
const List<(String, String, String, String?, String?)> _presets = [
  (
    'pull-espresso',
    'Pull the espresso',
    'استخلص الإسبريسو',
    '18 g in, 36 g out in 25 to 30 seconds',
    '18 جم بن تعطي 36 جم في 25 إلى 30 ثانية',
  ),
  (
    'steam-milk',
    'Steam the milk',
    'بخّر الحليب',
    'Stop at 60 °C',
    'توقّف عند 60 درجة',
  ),
  ('pour-latte-art', 'Pour and finish', 'اسكب وزيّن', null, null),
  ('add-ice', 'Fill the cup with ice', 'املأ الكوب بالثلج', null, null),
  ('add-syrup', 'Add the syrup', 'أضف السيروب', null, null),
  (
    'blend',
    'Blend until smooth',
    'اخلط حتى يصبح ناعمًا',
    '30 seconds',
    '30 ثانية',
  ),
  ('steep-tea', 'Steep the tea', 'انقع الشاي', '3 minutes', '3 دقائق'),
  ('press-juice', 'Press the fruit', 'اعصر الفاكهة', null, null),
];

/// Item key -> steps: a preset slug, or (English, Arabic) for a written one.
const Map<String, List<Object>> _steps = {
  'latte': ['pull-espresso', 'steam-milk', 'pour-latte-art'],
  'spanish': [
    'pull-espresso',
    ('Stir in the condensed milk', 'قلّب الحليب المكثّف'),
    'steam-milk',
    'pour-latte-art',
  ],
  'iced_latte': [
    'add-ice',
    'pull-espresso',
    ('Pour the cold milk over the ice', 'اسكب الحليب البارد فوق الثلج'),
  ],
  'frappe': ['add-ice', 'pull-espresso', 'add-syrup', 'blend'],
  'green_tea': ['steep-tea'],
};

// ── loading ───────────────────────────────────────────────────────────────

/// Loads the area's data into a seeded [MockDb] (idempotent: the second call
/// for the same db does nothing).
abstract final class CatalogMenuSeed {
  static final DateTime _created = DateTime.utc(2026, 1, 10, 9);
  static final DateTime _updated = DateTime.utc(2026, 9, 1, 9);

  static void loadInto(MockDb db) {
    if (db.hasTable(MenuTables.ingredients) &&
        db[MenuTables.ingredients].length > 0) {
      return;
    }
    final created = _created.toIso8601String();
    final updated = _updated.toIso8601String();
    final org = SeedIds.sabahOrg;

    // Ingredient categories and the catalog.
    final catCount = <String, int>{};
    for (final i in _ingredients) {
      catCount[i.$3] = (catCount[i.$3] ?? 0) + 1;
    }
    for (final (n, (key, name, packaging)) in _ingredientCategories.indexed) {
      db[MenuTables.ingredientCategories].insert({
        'id': MenuSeedIds.ingredientCategory(key),
        'org_id': org,
        'name': name,
        'slug': key,
        'sort_order': n,
        'is_packaging': packaging,
        'ingredient_count': catCount[key] ?? 0,
        'created_at': created,
        'updated_at': updated,
      }, timestamps: false);
    }
    final catName = {for (final c in _ingredientCategories) c.$1: c.$2};
    for (final (key, name, cat, unit, cost, active) in _ingredients) {
      db[MenuTables.ingredients].insert({
        'id': MenuSeedIds.ingredient(key),
        'org_id': org,
        'name': name,
        'category_id': MenuSeedIds.ingredientCategory(cat),
        'category_name': catName[cat],
        'category_slug': cat,
        'unit': unit,
        'cost_per_unit': cost?.toDouble(),
        'is_active': active,
        'created_at': created,
        'updated_at': updated,
      }, timestamps: false);
    }

    // Complete sizes (one_size for simple items), with sort and base.
    final baseOf = {
      for (final e in _baseItems.entries)
        for (final item in e.value) item: MenuSeedIds.base(e.key),
    };
    final sizes = db[MenuTables.sizes];
    for (final m in seedMenu) {
      final itemId = MenuSeedIds.item(m.key);
      if (m.sizes.length == 1) {
        sizes.insert({
          'id': MenuSeedIds.size(m.key, oneSize),
          'menu_item_id': itemId,
          'label': oneSize,
          'price_override': m.sizes.first.$2 * 100,
          'is_active': true,
        }, timestamps: false);
      }
      final labels = m.sizes.length == 1
          ? [oneSize]
          : [for (final s in m.sizes) s.$1];
      for (final (n, label) in labels.indexed) {
        sizes.update(MenuSeedIds.size(m.key, label), {
          'sort': n,
          'base_id': baseOf[m.key],
        });
      }
    }

    // Own recipe lines.
    final lines = db[MenuTables.recipeLines];
    for (final e in _ownLines.entries) {
      for (final s in e.value.entries) {
        for (final (n, (ing, qty)) in s.value.indexed) {
          lines.insert({
            'size_id': MenuSeedIds.size(e.key, s.key),
            'menu_item_id': MenuSeedIds.item(e.key),
            'ingredient_id': MenuSeedIds.ingredient(ing),
            'quantity': fmtQty(qty),
            'unit': _unitOf(ing),
            'source': 'own',
            'sort': n,
          }, timestamps: false);
        }
      }
    }

    // Bases and packaging rules.
    for (final (key, name, ar, active, baseLines) in _bases) {
      db[MenuTables.bases].insert({
        'id': MenuSeedIds.base(key),
        'org_id': org,
        'name': name,
        'name_ar': ar,
        'is_active': active,
        'lines': [
          for (final (n, (label, ing, qty)) in baseLines.indexed)
            {
              'id': mockUuid('recipe-base-line:$key:$n'),
              'ingredient_id': MenuSeedIds.ingredient(ing),
              'quantity': fmtQty(qty),
              'unit': _unitOf(ing),
              'size_label': label,
              'sort': n,
            },
        ],
        'created_at': created,
        'updated_at': updated,
      }, timestamps: false);
    }
    for (final (n, (key, name, cat, size, item, active, ruleLines))
        in _rules.indexed) {
      db[MenuTables.rules].insert({
        'id': MenuSeedIds.rule(key),
        'org_id': org,
        'name': name,
        'match_category_id': cat == null ? null : MenuSeedIds.category(cat),
        'match_size_label': size,
        'match_item_id': item == null ? null : MenuSeedIds.item(item),
        'is_active': active,
        'sort': n,
        'lines': [
          for (final (s, (ing, qty)) in ruleLines.indexed)
            {
              'ingredient_id': MenuSeedIds.ingredient(ing),
              'quantity': fmtQty(qty),
              'unit': _unitOf(ing),
              'sort': s,
            },
        ],
        'created_at': created,
        'updated_at': updated,
      }, timestamps: false);
    }

    // Option recipes on the shared groups.
    final data = CatalogMenuData(db);
    for (final g in db[MenuTables.groups].rows) {
      final key = seedGroups
          .where((s) => MenuSeedIds.group(s.key) == g['id'])
          .firstOrNull
          ?.key;
      final recipes = _optionRecipes[key];
      if (key == null || recipes == null) continue;
      final swaps = g['effect'] == 'swaps';
      if (swaps) {
        g['swap_category_id'] = MenuSeedIds.ingredientCategory('milk');
        g['swap_category_slug'] = 'milk';
      }
      g['is_item_options'] = false;
      for (final o in (g['options'] as List).cast<Map<String, Object?>>()) {
        final optKey = recipes.keys
            .where((k) => MenuSeedIds.option(key, k) == o['id'])
            .firstOrNull;
        final r = optKey == null ? null : recipes[optKey];
        if (r == null) continue;
        final ingId = MenuSeedIds.ingredient(r.$1);
        o['replaces_ingredient_id'] = swaps ? ingId : null;
        o['recipe'] = [
          {
            'ingredient_id': ingId,
            'ingredient_name': data.ingredientName(ingId),
            'quantity': r.$2.toDouble(),
            'unit': _unitOf(r.$1),
            'size_label': null,
          },
        ];
      }
    }

    // Price overrides.
    final overrides = db[MenuTables.priceOverrides];
    for (final (branch, channel, item, label, price, available)
        in _sizeOverrides) {
      overrides.insert({
        'scope': channel == null ? 'branch' : 'branch_channel',
        'branch_id': branch,
        'channel': channel,
        'target_type': 'menu_item_size',
        'target_id': MenuSeedIds.size(item, label),
        'price': price,
        'is_available': available,
      }, timestamps: false);
    }
    for (final (branch, channel, group, option, price, available)
        in _optionOverrides) {
      overrides.insert({
        'scope': channel == null ? 'branch' : 'branch_channel',
        'branch_id': branch,
        'channel': channel,
        'target_type': 'modifier_option',
        'target_id': MenuSeedIds.option(group, option),
        'price': price,
        'is_available': available,
      }, timestamps: false);
    }

    // The step library and a few items' steps.
    for (final (n, (slug, name, ar, note, noteAr)) in _presets.indexed) {
      db[MenuTables.stepPresets].insert({
        'id': slug,
        'slug': slug,
        'name': name,
        'name_ar': ar,
        'note': note,
        'note_ar': noteAr,
        'sort_order': n,
        'animation_url': '/recipes/step-presets/$slug/animation',
        'animation_sha256': mockUuid('animation:$slug').replaceAll('-', ''),
        'animation_hash': mockUuid('animation:$slug').substring(0, 8),
        'bytes': 18000 + 1000 * n,
      }, timestamps: false);
    }
    final presetBySlug = {for (final p in _presets) p.$1: p};
    for (final e in _steps.entries) {
      for (final (n, s) in e.value.indexed) {
        final preset = s is String ? presetBySlug[s] : null;
        final written = s is (String, String) ? s : null;
        db[MenuTables.steps].insert({
          'menu_item_id': MenuSeedIds.item(e.key),
          'position': n + 1,
          'kind': preset != null ? 'preset' : 'custom',
          'preset_slug': preset?.$1,
          'name': preset?.$2 ?? written!.$1,
          'name_ar': preset?.$3 ?? written!.$2,
          'note': null,
          'note_ar': null,
        }, timestamps: false);
      }
    }

    // Base and rule lines, as the backend materialises them.
    for (final m in seedMenu) {
      data.rebuildItem(MenuSeedIds.item(m.key));
    }
  }

  static String _unitOf(String ingredientKey) =>
      _ingredients.firstWhere((i) => i.$1 == ingredientKey).$4;
}

// ── computations ──────────────────────────────────────────────────────────

/// A cost rollup the backend's way: the sum over the PRICED lines (rounded to
/// piastres), null when no line is priced; incomplete when any line has no
/// ingredient or no unit cost.
typedef CostRollup = ({int? cost, bool incomplete});

/// The backend's menu computations over the area's tables.
class CatalogMenuData {
  CatalogMenuData(this.db);

  final MockDb db;

  MockTable get _sizes => db[MenuTables.sizes];
  MockTable get _lines => db[MenuTables.recipeLines];

  MockRow? ingredient(String id) => db[MenuTables.ingredients].find(id);

  String ingredientName(String id) =>
      (ingredient(id)?['name'] as String?) ?? '';

  /// The item's sizes (active and inactive) by `sort`.
  List<MockRow> sizesOf(String itemId) =>
      _sizes.query(filters: {'menu_item_id': itemId}, sort: 'sort');

  /// Every stored line of one size (own, base, rule, linked), own first.
  List<MockRow> linesOf(String sizeId) {
    final rows = _lines.where((l) => l['size_id'] == sizeId);
    int rank(MockRow l) => switch (l['source']) {
      'base' => 1,
      'rule' => 2,
      _ => 0,
    };
    final indexed = rows.indexed.toList()
      ..sort((a, b) {
        final c = rank(a.$2) - rank(b.$2);
        if (c != 0) return c;
        final s = ((a.$2['sort'] as int?) ?? 0) - ((b.$2['sort'] as int?) ?? 0);
        return s != 0 ? s : a.$1 - b.$1;
      });
    return [for (final e in indexed) e.$2];
  }

  /// One line's cost in piastres (unit cost × quantity), null when unknown.
  int? lineCost(MockRow line) {
    final cpu = ingredient(
      line['ingredient_id'] as String? ?? '',
    )?['cost_per_unit'];
    final q = jsNumber('${line['quantity']}');
    if (cpu is! num || !q.isFinite) return null;
    return jsRound(cpu * q);
  }

  /// The cost of [lines].
  CostRollup costOf(Iterable<Map<String, Object?>> lines) {
    double? sum;
    var incomplete = false;
    for (final l in lines) {
      final id = l['ingredient_id'] as String?;
      final cpu = id == null ? null : ingredient(id)?['cost_per_unit'];
      final q = jsNumber('${l['quantity']}');
      if (cpu is! num || !q.isFinite) {
        incomplete = true;
        continue;
      }
      sum = (sum ?? 0) + cpu * q;
    }
    return (cost: sum == null ? null : jsRound(sum), incomplete: incomplete);
  }

  /// A size's price: its own price, else the item's `base_price`.
  int priceOf(MockRow size, MockRow item) =>
      (size['price_override'] as int?) ?? (item['base_price'] as int? ?? 0);

  /// `SkuCost` rows of one item: its ACTIVE sizes, only while the item is
  /// active (the backend skips inactive items).
  List<Map<String, Object?>> skuCosts(MockRow item) {
    if (item['is_active'] != true) return const [];
    return [
      for (final s in sizesOf(item['id'] as String))
        if (s['is_active'] == true) _skuCost(item, s),
    ];
  }

  Map<String, Object?> _skuCost(MockRow item, MockRow size) {
    final price = priceOf(size, item);
    final r = costOf(linesOf(size['id'] as String));
    final graded = r.cost != null && !r.incomplete && price > 0;
    return {
      'menu_item_id': item['id'],
      'size_label': size['label'],
      'item_name': item['name'],
      'category_id': item['category_id'],
      'price': price,
      'cost': r.cost,
      'cost_missing': r.incomplete,
      'margin_pct': graded ? (price - r.cost!) / price : null,
      'food_cost_pct': graded ? r.cost! / price : null,
    };
  }

  /// Whether the item has any recipe line (`has_recipe`).
  bool hasRecipe(String itemId) =>
      _lines.rows.any((l) => l['menu_item_id'] == itemId);

  /// The most specific ACTIVE packaging rule for one size (`best_rule_for`):
  /// item beats category beats label, then `sort`.
  MockRow? bestRuleFor(MockRow item, String sizeLabel) {
    final matches = db[MenuTables.rules].where(
      (r) =>
          r['is_active'] == true &&
          (r['match_item_id'] == null || r['match_item_id'] == item['id']) &&
          (r['match_category_id'] == null ||
              r['match_category_id'] == item['category_id']) &&
          (r['match_size_label'] == null || r['match_size_label'] == sizeLabel),
    );
    int score(MockRow r) =>
        (r['match_item_id'] != null ? 4 : 0) +
        (r['match_category_id'] != null ? 2 : 0) +
        (r['match_size_label'] != null ? 1 : 0);
    matches.sort((a, b) {
      final c = score(b) - score(a);
      if (c != 0) return c;
      return ((a['sort'] as int?) ?? 0) - ((b['sort'] as int?) ?? 0);
    });
    return matches.firstOrNull;
  }

  /// Re-expands one item's base, rule and linked lines (`rebuild_item`): own
  /// lines are never touched; a size's base lines (label-specific over
  /// all-sizes, per ingredient) skip ingredients the size has as own lines;
  /// rule lines skip ingredients already present. A linked copy
  /// (`recipe_source_item_id`) copies the source's same-label size. Returns
  /// how many sizes changed.
  int rebuildItem(String itemId) {
    final item = db[MenuTables.menuItems].find(itemId);
    if (item == null) return 0;
    final sourceId = item['recipe_source_item_id'] as String?;
    var changed = 0;
    for (final size in sizesOf(itemId)) {
      final sizeId = size['id'] as String;
      final label = size['label'] as String;
      final current = linesOf(sizeId);
      final List<Map<String, Object?>> wants;
      final List<MockRow> managed;
      if (sourceId != null) {
        managed = current;
        final src = sizesOf(
          sourceId,
        ).where((s) => s['label'] == label).firstOrNull;
        wants = [
          if (src != null)
            for (final l in linesOf(src['id'] as String))
              {
                'ingredient_id': l['ingredient_id'],
                'quantity': l['quantity'],
                'unit': l['unit'],
                'source': 'linked',
              },
        ];
      } else {
        managed = [
          for (final l in current)
            if (l['source'] != null && l['source'] != 'own') l,
        ];
        final taken = {
          for (final l in current)
            if (l['source'] == null || l['source'] == 'own') l['ingredient_id'],
        };
        wants = [];
        final base = size['base_id'] == null
            ? null
            : db[MenuTables.bases].find(size['base_id'] as String);
        if (base != null && base['is_active'] == true) {
          final picked = <String, Map<String, Object?>>{};
          final baseLines = (base['lines'] as List).cast<Map<String, Object?>>()
            ..sort(
              (a, b) => ((a['sort'] as int?) ?? 0) - ((b['sort'] as int?) ?? 0),
            );
          for (final l in baseLines) {
            final ing = l['ingredient_id'] as String;
            final sl = l['size_label'] as String?;
            if (sl != null && sl != label) continue;
            final have = picked[ing];
            if (have == null || (have['size_label'] == null && sl != null)) {
              picked[ing] = l;
            }
          }
          for (final l in picked.values) {
            if (taken.add(l['ingredient_id'])) {
              wants.add({
                'ingredient_id': l['ingredient_id'],
                'quantity': l['quantity'],
                'unit': l['unit'],
                'source': 'base',
              });
            }
          }
        }
        final rule = bestRuleFor(item, label);
        if (rule != null) {
          for (final l
              in (rule['lines'] as List).cast<Map<String, Object?>>()) {
            if (taken.add(l['ingredient_id'])) {
              wants.add({
                'ingredient_id': l['ingredient_id'],
                'quantity': l['quantity'],
                'unit': l['unit'],
                'source': 'rule',
              });
            }
          }
        }
      }
      String sig(Iterable<Map<String, Object?>> ls) => [
        for (final l in ls)
          '${l['source']}|${l['ingredient_id']}|${jsNumber('${l['quantity']}')}|${l['unit']}',
      ].join(',');
      if (sig(managed) == sig(wants)) continue;
      final drop = {for (final l in managed) l['id']};
      _lines.removeWhere((l) => drop.contains(l['id']));
      for (final (n, w) in wants.indexed) {
        _lines.insert({
          ...w,
          'size_id': sizeId,
          'menu_item_id': itemId,
          'sort': 100 + n,
        }, timestamps: false);
      }
      changed++;
    }
    return changed;
  }

  /// `POST /packaging-rules/apply`: re-expands every item; the
  /// `ApplyPackagingRulesResult` counts.
  Map<String, Object?> applyRules() {
    var seen = 0, withRule = 0, changed = 0, manual = 0;
    final packaging = {
      for (final c in db[MenuTables.ingredientCategories].rows)
        if (c['is_packaging'] == true) c['id'],
    };
    for (final item in db[MenuTables.menuItems].rows) {
      if (item['deleted_at'] != null) continue;
      final itemId = item['id'] as String;
      for (final size in sizesOf(itemId)) {
        seen++;
        if (bestRuleFor(item, size['label'] as String) != null) withRule++;
        final own = linesOf(
          size['id'] as String,
        ).where((l) => l['source'] == null || l['source'] == 'own');
        if (own.any(
          (l) => packaging.contains(
            ingredient(l['ingredient_id'] as String)?['category_id'],
          ),
        )) {
          manual++;
        }
      }
      changed += rebuildItem(itemId);
    }
    return {
      'catalog_revision': 1,
      'sizes_seen': seen,
      'sizes_with_rule': withRule,
      'sizes_changed': changed,
      'sizes_with_manual_packaging': manual,
    };
  }

  /// The shared groups' options as the backend's `addon_items` view (an
  /// add-on IS a modifier option: same id), by type then creation.
  List<Map<String, Object?>> addonItems() {
    final out = <(String, int, Map<String, Object?>)>[];
    for (final g in db[MenuTables.groups].rows) {
      final type = g['legacy_addon_type'] as String?;
      if (type == null) continue;
      for (final (n, o)
          in (g['options'] as List).cast<Map<String, Object?>>().indexed) {
        out.add((
          type,
          n,
          {
            'id': o['id'],
            'org_id': g['org_id'],
            'name': o['name'],
            'name_translations':
                o['name_translations'] ?? const <String, Object?>{},
            'addon_type': type,
            'default_price': o['price'],
            'is_active': o['is_active'],
            'primary_ingredient_id':
                ((o['recipe'] as List?)?.firstOrNull as Map?)?['ingredient_id'],
            'created_at':
                (g['created_at'] as String?) ??
                DateTime.utc(2026, 1, 10, 9, n).toIso8601String(),
            'updated_at':
                (g['updated_at'] as String?) ??
                DateTime.utc(2026, 9, 1, 9).toIso8601String(),
          },
        ));
      }
    }
    out.sort((a, b) {
      final c = a.$1.compareTo(b.$1);
      return c != 0 ? c : a.$2 - b.$2;
    });
    return [for (final e in out) e.$3];
  }

  /// One option's recipe cost (`AddonCost`): its lines, the backend's rollup.
  CostRollup optionCost(Map<String, Object?> option) => costOf(
    ((option['recipe'] as List?) ?? const []).cast<Map<String, Object?>>(),
  );

  /// `GET /costing/addon-items` rows.
  List<Map<String, Object?>> addonCosts() => [
    for (final a in addonItems()) _addonCost(a),
  ];

  Map<String, Object?> _addonCost(Map<String, Object?> a) {
    final option = _option(a['id'] as String);
    final r = option == null
        ? (cost: null, incomplete: false)
        : optionCost(option);
    final price = (a['default_price'] as int?) ?? 0;
    final graded = r.cost != null && !r.incomplete && price > 0;
    return {
      'addon_item_id': a['id'],
      'name': a['name'],
      'addon_type': a['addon_type'],
      'price': price,
      'cost': r.cost,
      'cost_missing': r.incomplete,
      'margin_pct': graded ? (price - r.cost!) / price : null,
    };
  }

  Map<String, Object?>? _option(String optionId) {
    for (final g in db[MenuTables.groups].rows) {
      for (final o in (g['options'] as List).cast<Map<String, Object?>>()) {
        if (o['id'] == optionId) return o;
      }
    }
    return null;
  }

  /// The override rows at one branch for one target.
  List<MockRow> overridesFor(String branchId, String targetId) =>
      db[MenuTables.priceOverrides].where(
        (o) => o['branch_id'] == branchId && o['target_id'] == targetId,
      );
}
