/// The offers catalogue's own data over the core seed ("Sabah Coffee"), so
/// the combos list, the combo editor, the deals and the discounts agree on
/// every name and number:
///
/// | table | rows |
/// |---|---|
/// | `menu_items` (core) | six combos as menu items of `kind: combo` (the backend keeps a combo as a menu item: Menu ▸ Items lists it and `DELETE /menu-items/{id}` deletes it) |
/// | [OffersTables.comboSpecs] | each combo's slots and sale windows, keyed by the combo's id |
/// | [OffersTables.itemCosts] | the unit cost of each item size (the price check's cost; two breakfast items have none) |
/// | [OffersTables.orgSettings] | Sabah's minimum combo margin (55 %) |
/// | [OffersTables.deals] | five deals ([DealRule] JSON) |
/// | [OffersTables.discounts] | seven discounts ([Discount] JSON) |
///
/// Every id is stable ([OffersSeed.comboId], [OffersSeed.dealId],
/// [OffersSeed.discountId]); units add rows in their own mock files.
/// Combo economics and the summaries the list shows are derived from these
/// tables by `mock/offers_rules.dart`, never stored.
library;

import 'package:dashboard_api/mock.dart';

/// The table names this area reads and writes.
abstract final class OffersTables {
  /// The core seed's menu items; combos are rows of `kind: combo`.
  static const String menuItems = 'menu_items';

  /// The core seed's categories.
  static const String categories = 'categories';

  /// The core seed's sizes of multi-size items.
  static const String itemSizes = 'item_sizes';

  /// `{id: <combo id>, slots: [ComboSlot], windows: [SaleWindow]}`.
  static const String comboSpecs = 'combo_specs';

  /// `{id: '<menu item id>|<size label>', menu_item_id, size_label, cost}`.
  static const String itemCosts = 'offers_item_costs';

  /// `{id: <org id>, combo_min_margin: '0.5500' | null}`.
  static const String orgSettings = 'offers_org_settings';

  static const String deals = 'deals';
  static const String discounts = 'discounts';
}

/// The size label a single-price item keeps its price on (`ONE_SIZE`).
const String oneSizeLabel = 'one_size';

/// The backend's legacy integer `value` of a discount (`legacy_value`): a
/// fraction in (0, 1] as a whole percent, anything else as it is (piastres),
/// rounded half away from zero (12.5 % → 13).
int legacyDiscountValue(num valueRate) {
  final scaled = valueRate > 0 && valueRate <= 1 ? valueRate * 100 : valueRate;
  final r = scaled.abs().roundToDouble() * (scaled < 0 ? -1 : 1);
  return r.toInt();
}

/// Ids and loading of the area's seed.
abstract final class OffersSeed {
  static String comboId(String key) => mockUuid('combo:$key');
  static String slotId(String combo, String slot) =>
      mockUuid('combo-slot:$combo:$slot');
  static String choiceId(String combo, String slot, int i) =>
      mockUuid('combo-choice:$combo:$slot:$i');
  static String windowId(String owner, int i) =>
      mockUuid('sale-window:$owner:$i');
  static String dealId(String key) => mockUuid('deal:$key');
  static String discountId(String key) => mockUuid('discount:$key');

  /// A core seed item's id by its seed key (`croissant`).
  static String item(String key) => MockSeed.menuItemId(key);

  /// A core seed category's id by its seed key (`bakery`).
  static String category(String key) => MockSeed.categoryId(key);

  /// Sabah's minimum combo margin, as the wire's fraction string.
  static const String minMargin = '0.5500';

  /// The combo keys, in the order the seed adds them.
  static const List<String> comboKeys = [
    'morning-croissant',
    'coffee-cookie',
    'brunch-for-two',
    'iced-afternoon',
    'suhoor-box',
    'kids-cocoa',
  ];

  static const List<String> dealKeys = [
    'pastry-pair',
    'coffee-cookie-free',
    'iced-latte-half',
    'juice-trio',
    'weekend-breakfast',
  ];

  static const List<String> discountKeys = [
    'staff-meal',
    'student',
    'loyalty-welcome',
    'manager-comp',
    'opening-week',
    'late-order',
    'corporate-vodafone',
  ];

  /// Loads the area's rows into [db] once (a second call does nothing).
  static void loadInto(MockDb db) {
    final settings = db.table(OffersTables.orgSettings);
    if (settings.find(SeedIds.sabahOrg) != null) return;
    settings.insert({
      'id': SeedIds.sabahOrg,
      'combo_min_margin': minMargin,
    }, timestamps: false);
    db.table(OffersTables.itemCosts).insertAll(_itemCosts(), timestamps: false);
    final items = db.table(OffersTables.menuItems);
    final specs = db.table(OffersTables.comboSpecs);
    for (final c in _combos) {
      items.insert(c.menuItemJson(), timestamps: false);
      specs.insert(c.specJson(), timestamps: false);
    }
    db.table(OffersTables.deals).insertAll(_deals(), timestamps: false);
    db.table(OffersTables.discounts).insertAll(_discounts(), timestamps: false);
  }

  // ── Unit costs (piastres) ─────────────────────────────────────────────

  /// Cost per item and size label. Halloumi Sandwich and Avocado Toast have
  /// no costed recipe yet: a combo that can pick them warns COST_UNKNOWN.
  static const Map<String, Map<String, int>> unitCosts = {
    'espresso': {'Single': 900, 'Double': 1400},
    'americano': {'Regular': 1500, 'Large': 1900},
    'cortado': {oneSizeLabel: 2100},
    'flatwhite': {oneSizeLabel: 2700},
    'cappuccino': {'Regular': 3200, 'Large': 3900},
    'latte': {'Regular': 3800, 'Large': 4600},
    'spanish': {'Regular': 4300, 'Large': 5100},
    'mocha': {'Regular': 4500, 'Large': 5300},
    'pistachio_latte': {'Regular': 5200, 'Large': 6000},
    'v60': {oneSizeLabel: 2400},
    'turkish': {'Single': 800, 'Double': 1200},
    'iced_americano': {'Regular': 1900, 'Large': 2300},
    'iced_latte': {'Regular': 4200, 'Large': 5000},
    'iced_spanish': {'Regular': 5000, 'Large': 5800},
    'iced_mocha': {'Regular': 5200, 'Large': 6000},
    'cold_brew': {'Regular': 2600, 'Large': 3100},
    'frappe': {'Regular': 5800, 'Large': 6600},
    'iced_matcha': {'Regular': 6100, 'Large': 6900},
    'matcha': {'Regular': 5600, 'Large': 6400},
    'chai': {'Regular': 3400, 'Large': 4000},
    'hot_choc': {oneSizeLabel: 3100},
    'mint_lemonade': {oneSizeLabel: 1700},
    'hibiscus': {oneSizeLabel: 900},
    'green_tea': {oneSizeLabel: 600},
    'orange': {oneSizeLabel: 3000},
    'mango': {oneSizeLabel: 4200},
    'strawberry': {oneSizeLabel: 3800},
    'croissant': {oneSizeLabel: 2600},
    'almond_croissant': {oneSizeLabel: 3400},
    'pain_choc': {oneSizeLabel: 3100},
    'cinnamon': {oneSizeLabel: 2900},
    'cookie': {oneSizeLabel: 1800},
    'cheesecake': {oneSizeLabel: 7200},
    'fudge': {oneSizeLabel: 5600},
    'banana_bread': {oneSizeLabel: 2500},
    'lemon_tart': {oneSizeLabel: 4800},
    'turkey_croissant': {oneSizeLabel: 7400},
    'shakshuka': {oneSizeLabel: 5200},
  };

  static Iterable<MockRow> _itemCosts() sync* {
    for (final e in unitCosts.entries) {
      for (final s in e.value.entries) {
        final id = item(e.key);
        yield {
          'id': '$id|${s.key}',
          'menu_item_id': id,
          'size_label': s.key,
          'cost': s.value,
        };
      }
    }
  }

  // ── Combos ─────────────────────────────────────────────────────────────

  static final List<_SeedCombo> _combos = [
    _SeedCombo(
      'morning-croissant',
      'Morning Croissant Combo',
      'كومبو كرواسون الصباح',
      category: 'bakery',
      price: 16500,
      description: 'A fresh croissant and any hot coffee.',
      descriptionAr: 'كرواسون طازج مع أي قهوة ساخنة.',
      created: DateTime.utc(2026, 3, 2, 9),
      slots: [
        _SeedSlot(
          'pastry',
          'Pastry',
          'مخبوزات',
          defaultItem: 'croissant',
          choices: [
            _SeedChoice.item('croissant'),
            _SeedChoice.item('almond_croissant', surcharge: 2000),
            _SeedChoice.item('pain_choc', surcharge: 1500),
          ],
        ),
        _SeedSlot(
          'coffee',
          'Coffee',
          'قهوة',
          defaultItem: 'latte',
          choices: [
            _SeedChoice.category('hot', sizeSurcharges: {'Large': 1500}),
          ],
        ),
      ],
    ),
    _SeedCombo(
      'coffee-cookie',
      'Coffee & Cookie',
      'قهوة وكوكيز',
      price: 12000,
      created: DateTime.utc(2026, 3, 9, 9),
      slots: [
        _SeedSlot(
          'coffee',
          'Coffee',
          'قهوة',
          choices: [_SeedChoice.item('americano', includedSize: 'Regular')],
        ),
        _SeedSlot(
          'cookie',
          'Cookie',
          'كوكيز',
          choices: [_SeedChoice.item('cookie')],
        ),
      ],
    ),
    _SeedCombo(
      'brunch-for-two',
      'Brunch for Two',
      'برانش لشخصين',
      category: 'breakfast',
      price: 52000,
      description: 'Two breakfast plates and two drinks.',
      descriptionAr: 'طبقا فطور ومشروبان.',
      created: DateTime.utc(2026, 4, 14, 9),
      slots: [
        _SeedSlot(
          'mains',
          'Mains',
          'أطباق رئيسية',
          min: 2,
          max: 2,
          defaultItem: 'halloumi',
          choices: [_SeedChoice.category('breakfast')],
        ),
        _SeedSlot(
          'drinks',
          'Drinks',
          'مشروبات',
          min: 2,
          max: 2,
          defaultItem: 'cappuccino',
          choices: [_SeedChoice.category('hot'), _SeedChoice.category('juice')],
        ),
      ],
      windows: [
        _SeedWindow(
          weekdays: 96,
          from: '09:00',
          to: '13:00',
          branch: 'zamalek',
        ),
      ],
    ),
    _SeedCombo(
      'iced-afternoon',
      'Iced Afternoon',
      'عصرية مثلجة',
      category: 'iced',
      price: 23000,
      created: DateTime.utc(2026, 5, 20, 9),
      slots: [
        _SeedSlot(
          'iced',
          'Iced coffee',
          'قهوة مثلجة',
          defaultItem: 'iced_latte',
          choices: [_SeedChoice.category('iced')],
        ),
        _SeedSlot(
          'sweet',
          'Something sweet',
          'شيء حلو',
          defaultItem: 'fudge',
          choices: [
            _SeedChoice.item('fudge'),
            _SeedChoice.item('cheesecake', surcharge: 1500),
            _SeedChoice.item('lemon_tart'),
          ],
        ),
      ],
      windows: [_SeedWindow(from: '15:00', to: '19:00')],
    ),
    _SeedCombo(
      'suhoor-box',
      'Ramadan Suhoor Box',
      'صندوق السحور',
      category: 'breakfast',
      price: 27000,
      active: false,
      created: DateTime.utc(2026, 2, 10, 9),
      slots: [
        _SeedSlot(
          'main',
          'Main',
          'الطبق الرئيسي',
          defaultItem: 'shakshuka',
          choices: [
            _SeedChoice.item('shakshuka'),
            _SeedChoice.item('turkey_croissant'),
          ],
        ),
        _SeedSlot(
          'pastry',
          'Pastry',
          'مخبوزات',
          defaultItem: 'croissant',
          choices: [_SeedChoice.category('bakery')],
        ),
        _SeedSlot(
          'drink',
          'Drink',
          'مشروب',
          defaultItem: 'hibiscus',
          choices: [
            _SeedChoice.item('hibiscus'),
            _SeedChoice.item('mint_lemonade'),
            _SeedChoice.item('green_tea'),
          ],
        ),
      ],
      windows: [
        _SeedWindow(
          from: '22:00',
          to: '03:00',
          validFrom: '2026-02-18',
          validTo: '2026-03-19',
        ),
      ],
    ),
    _SeedCombo(
      'kids-cocoa',
      "Kids' Cocoa & Cookie",
      'كاكاو وكوكيز للأطفال',
      category: 'dessert',
      price: 15000,
      created: DateTime.utc(2026, 6, 1, 9),
      slots: [
        _SeedSlot(
          'cocoa',
          'Hot chocolate',
          'شوكولاتة ساخنة',
          choices: [_SeedChoice.item('hot_choc')],
        ),
        _SeedSlot(
          'cookie',
          'Cookie',
          'كوكيز',
          choices: [_SeedChoice.item('cookie')],
        ),
      ],
      windows: [_SeedWindow(weekdays: 96, from: '10:00', to: '18:00')],
    ),
  ];

  // ── Deals ──────────────────────────────────────────────────────────────

  static Iterable<MockRow> _deals() sync* {
    MockRow deal(
      String key,
      String name,
      String ar, {
      required String kind,
      required int qty,
      int? price,
      int? getQty,
      int? getPercent,
      int? maxPerOrder,
      bool active = true,
      required int sort,
      required List<MockRow> pool,
      List<MockRow> rewardPool = const [],
      List<_SeedWindow> windows = const [],
      Map<String, bool> overrides = const {},
      required DateTime created,
    }) => {
      'id': dealId(key),
      'name': name,
      'name_translations': {'en': name, 'ar': ar},
      'kind': kind,
      'qty': qty,
      'price': price,
      'get_qty': getQty,
      'get_percent': getPercent,
      'max_per_order': maxPerOrder,
      'is_active': active,
      'sort': sort,
      'pool': pool,
      'reward_pool': rewardPool,
      'windows': [
        for (final (i, w) in windows.indexed) w.toJson(windowId(key, i)),
      ],
      'branch_overrides': [
        for (final e in overrides.entries)
          {'branch_id': _branch(e.key), 'is_active': e.value},
      ],
      'created_at': created.toIso8601String(),
      'updated_at': DateTime.utc(2026, 9, 1, 9).toIso8601String(),
    };
    MockRow cat(String key, [String? size]) => {
      'menu_item_id': null,
      'category_id': category(key),
      'size_label': size,
    };
    MockRow itm(String key, [String? size]) => {
      'menu_item_id': item(key),
      'category_id': null,
      'size_label': size,
    };

    yield deal(
      'pastry-pair',
      'Any 2 pastries for 150',
      'أي قطعتين مخبوزات بـ 150',
      kind: 'n_for_price',
      qty: 2,
      price: 15000,
      sort: 0,
      pool: [cat('bakery')],
      created: DateTime.utc(2026, 3, 1, 9),
    );
    yield deal(
      'coffee-cookie-free',
      'Buy 2 coffees, get a cookie free',
      'اشترِ قهوتين واحصل على كوكيز مجانًا',
      kind: 'buy_get',
      qty: 2,
      getQty: 1,
      getPercent: 100,
      maxPerOrder: 2,
      sort: 1,
      pool: [cat('hot')],
      rewardPool: [itm('cookie')],
      overrides: {'zamalek': false},
      created: DateTime.utc(2026, 3, 15, 9),
    );
    yield deal(
      'iced-latte-half',
      'Second iced latte half price',
      'اللاتيه المثلج الثاني بنصف السعر',
      kind: 'buy_get',
      qty: 1,
      getQty: 1,
      getPercent: 50,
      sort: 2,
      pool: [itm('iced_latte', 'Large')],
      windows: [_SeedWindow(weekdays: 62, from: '12:00', to: '16:00')],
      created: DateTime.utc(2026, 5, 4, 9),
    );
    yield deal(
      'juice-trio',
      'Juice trio for 270',
      'ثلاثة عصائر بـ 270',
      kind: 'n_for_price',
      qty: 3,
      price: 27000,
      active: false,
      sort: 3,
      pool: [cat('juice')],
      windows: [_SeedWindow(validFrom: '2026-06-01', validTo: '2026-08-31')],
      overrides: {'heliopolis': true, 'maadi': true},
      created: DateTime.utc(2026, 5, 25, 9),
    );
    yield deal(
      'weekend-breakfast',
      'Weekend breakfast pair for 330',
      'فطور نهاية الأسبوع لشخصين بـ 330',
      kind: 'n_for_price',
      qty: 2,
      price: 33000,
      maxPerOrder: 1,
      sort: 4,
      pool: [cat('breakfast')],
      windows: [
        _SeedWindow(weekdays: 96, from: '08:00', to: '12:00'),
        _SeedWindow(weekdays: 1, from: '09:00', to: '11:00', branch: 'zamalek'),
      ],
      created: DateTime.utc(2026, 7, 2, 9),
    );
  }

  // ── Discounts ──────────────────────────────────────────────────────────

  static Iterable<MockRow> _discounts() sync* {
    MockRow discount(
      String key,
      String name,
      String ar, {
      required String dtype,
      required num rate,
      bool active = true,
      required DateTime created,
    }) => {
      'id': discountId(key),
      'org_id': SeedIds.sabahOrg,
      'name': name,
      'name_translations': {'ar': ar},
      'dtype': dtype,
      'value': legacyDiscountValue(rate),
      'value_rate': rate,
      'is_active': active,
      'created_at': created.toIso8601String(),
      'updated_at': created.toIso8601String(),
    };

    yield discount(
      'staff-meal',
      'Staff Meal',
      'وجبة الموظفين',
      dtype: 'percentage',
      rate: 0.5,
      created: DateTime.utc(2025, 12, 2, 9),
    );
    yield discount(
      'student',
      'Student Discount',
      'خصم الطلاب',
      dtype: 'percentage',
      rate: 0.15,
      created: DateTime.utc(2026, 1, 12, 9),
    );
    yield discount(
      'loyalty-welcome',
      'Loyalty Welcome',
      'ترحيب برنامج الولاء',
      dtype: 'fixed',
      rate: 2500,
      created: DateTime.utc(2026, 2, 3, 9),
    );
    yield discount(
      'manager-comp',
      'Manager Comp',
      'ضيافة المدير',
      dtype: 'percentage',
      rate: 1,
      created: DateTime.utc(2025, 12, 2, 9),
    );
    yield discount(
      'opening-week',
      'Opening Week',
      'أسبوع الافتتاح',
      dtype: 'percentage',
      rate: 0.2,
      active: false,
      created: DateTime.utc(2025, 12, 1, 9),
    );
    yield discount(
      'late-order',
      'Late Order Apology',
      'اعتذار عن تأخر الطلب',
      dtype: 'fixed',
      rate: 5000,
      created: DateTime.utc(2026, 4, 8, 9),
    );
    yield discount(
      'corporate-vodafone',
      'Corporate: Vodafone',
      'الشركات: فودافون',
      dtype: 'percentage',
      rate: 0.125,
      created: DateTime.utc(2026, 6, 15, 9),
    );
  }
}

String _branch(String key) => switch (key) {
  'heliopolis' => SeedIds.heliopolis,
  'maadi' => SeedIds.maadi,
  'new-cairo' => SeedIds.newCairo,
  'zamalek' => SeedIds.zamalek,
  _ => throw ArgumentError('unknown branch $key'),
};

/// A core seed item's English and Arabic names by key.
(String, String) _itemNames(String key) {
  for (final m in seedMenu) {
    if (m.key == key) return (m.name, m.ar);
  }
  throw ArgumentError('unknown menu item $key');
}

(String, String) _categoryNames(String key) {
  for (final c in seedCategories) {
    if (c.key == key) return (c.name, c.ar);
  }
  throw ArgumentError('unknown category $key');
}

class _SeedWindow {
  const _SeedWindow({
    this.weekdays = 127,
    this.from,
    this.to,
    this.validFrom,
    this.validTo,
    this.branch,
  });

  final int weekdays;
  final String? from;
  final String? to;
  final String? validFrom;
  final String? validTo;
  final String? branch;

  MockRow toJson(String id) => {
    'id': id,
    'branch_id': branch == null ? null : _branch(branch!),
    'weekdays': weekdays,
    'starts_at': from,
    'ends_at': to,
    'valid_from': validFrom,
    'valid_to': validTo,
  };
}

class _SeedChoice {
  const _SeedChoice.item(this.key, {this.surcharge = 0, this.includedSize})
    : isCategory = false,
      sizeSurcharges = const {};

  const _SeedChoice.category(this.key, {this.sizeSurcharges = const {}})
    : isCategory = true,
      surcharge = 0,
      includedSize = null;

  final String key;
  final bool isCategory;
  final int surcharge;
  final String? includedSize;
  final Map<String, int> sizeSurcharges;

  MockRow toJson(String id, int sort) {
    final (en, ar) = isCategory ? _categoryNames(key) : _itemNames(key);
    return {
      'id': id,
      'menu_item_id': isCategory ? null : OffersSeed.item(key),
      'category_id': isCategory ? OffersSeed.category(key) : null,
      'name': en,
      'name_translations': {'en': en, 'ar': ar},
      'surcharge': surcharge,
      'included_size_label': includedSize,
      'size_surcharges': [
        for (final e in sizeSurcharges.entries)
          {'size_label': e.key, 'surcharge': e.value},
      ],
      'sort': sort,
    };
  }
}

class _SeedSlot {
  const _SeedSlot(
    this.key,
    this.name,
    this.ar, {
    this.min = 1,
    this.max = 1,
    this.defaultItem,
    required this.choices,
  });

  final String key;
  final String name;
  final String ar;
  final int min;
  final int max;
  final String? defaultItem;
  final List<_SeedChoice> choices;

  MockRow toJson(String combo, int sort) => {
    'id': OffersSeed.slotId(combo, key),
    'name': name,
    'name_translations': {'en': name, 'ar': ar},
    'sort': sort,
    'min': min,
    'max': max,
    'default_item_id': defaultItem == null
        ? null
        : OffersSeed.item(defaultItem!),
    'default_size_label': null,
    'choices': [
      for (final (i, c) in choices.indexed)
        c.toJson(OffersSeed.choiceId(combo, key, i), i),
    ],
  };
}

class _SeedCombo {
  _SeedCombo(
    this.key,
    this.name,
    this.ar, {
    this.category,
    required this.price,
    this.description,
    this.descriptionAr,
    this.active = true,
    required this.created,
    required this.slots,
    this.windows = const [],
  });

  final String key;
  final String name;
  final String ar;
  final String? category;
  final int price;
  final String? description;
  final String? descriptionAr;
  final bool active;
  final DateTime created;
  final List<_SeedSlot> slots;
  final List<_SeedWindow> windows;

  String get id => OffersSeed.comboId(key);

  /// The combo as the core `menu_items` table holds it (a [MenuItem]).
  MockRow menuItemJson() => {
    'id': id,
    'org_id': SeedIds.sabahOrg,
    'category_id': category == null ? null : OffersSeed.category(category!),
    'name': name,
    'name_translations': {'en': name, 'ar': ar},
    'description': description,
    'description_translations': {'en': ?description, 'ar': ?descriptionAr},
    'base_price': price,
    'is_active': active,
    'kind': 'combo',
    'image_url': null,
    'default_milk_addon_id': null,
    'deleted_at': null,
    'created_at': created.toIso8601String(),
    'updated_at': DateTime.utc(2026, 9, 1, 9).toIso8601String(),
  };

  MockRow specJson() => {
    'id': id,
    'slots': [for (final (i, s) in slots.indexed) s.toJson(key, i)],
    'windows': [
      for (final (i, w) in windows.indexed)
        w.toJson(OffersSeed.windowId(key, i)),
    ],
  };
}
