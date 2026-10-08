/// The raw facts behind the seed: names, menu and prices. Taken from the launch
/// film's demo café (`film-capture/seed_film.py`) and the web's mock data, so
/// the mock reads like a real Cairo coffee chain. Prices are in EGP here; the
/// seed stores piastres (× 100), as the backend does.
library;

class SeedBranch {
  const SeedBranch(
    this.key,
    this.name,
    this.ar,
    this.code,
    this.address,
    this.lat,
    this.lon,
    this.dailyOrders,
    this.phone,
  );

  final String key;
  final String name;
  final String ar;

  /// The order-ref prefix (`ZM-261008-T1-0042`).
  final String code;
  final String address;
  final double lat;
  final double lon;

  /// Orders on an average weekday.
  final int dailyOrders;
  final String phone;
}

/// Sorted by name, as the web lists branches.
const List<SeedBranch> seedBranches = [
  SeedBranch(
    'heliopolis',
    'Heliopolis',
    'مصر الجديدة',
    'HL',
    'Baghdad St, Korba, Heliopolis',
    30.0911,
    31.3260,
    52,
    '+20 2 2415 3301',
  ),
  SeedBranch(
    'maadi',
    'Maadi',
    'المعادي',
    'MD',
    'Road 9, Maadi, Cairo',
    29.9602,
    31.2569,
    63,
    '+20 2 2358 7702',
  ),
  SeedBranch(
    'new-cairo',
    'New Cairo',
    'القاهرة الجديدة',
    'NC',
    '90th St, Fifth Settlement, New Cairo',
    30.0179,
    31.4710,
    88,
    '+20 2 2812 4403',
  ),
  SeedBranch(
    'zamalek',
    'Zamalek',
    'الزمالك',
    'ZM',
    '26 July St, Zamalek, Cairo',
    30.0626,
    31.2197,
    74,
    '+20 2 2736 1104',
  ),
];

class SeedPerson {
  const SeedPerson(
    this.key,
    this.name,
    this.role,
    this.branch, {
    this.email,
    this.pin,
    this.phone,
    this.gender,
    this.jobTitle,
    this.salaryEgp,
    this.hired,
  });

  final String key;
  final String name;

  /// Backend `UserRole`.
  final String role;

  /// Branch key; null for the owner (every branch).
  final String? branch;
  final String? email;
  final String? pin;
  final String? phone;
  final String? gender;
  final String? jobTitle;
  final int? salaryEgp;

  /// `yyyy-mm-dd`.
  final String? hired;
}

/// Sabah Coffee's people.
const List<SeedPerson> sabahStaff = [
  SeedPerson(
    'nour',
    'Nour El-Sayed',
    'org_admin',
    null,
    email: 'nour@sabah.test',
    pin: '260601',
    phone: '+201001112233',
    gender: 'f',
    jobTitle: 'Owner',
    hired: '2024-02-01',
  ),
  SeedPerson(
    'karim',
    'Karim Adel',
    'branch_manager',
    'zamalek',
    email: 'karim@sabah.test',
    phone: '+201002223344',
    gender: 'm',
    jobTitle: 'Branch manager',
    salaryEgp: 18000,
    hired: '2024-03-10',
  ),
  SeedPerson(
    'dina',
    'Dina Fouad',
    'branch_manager',
    'new-cairo',
    email: 'dina@sabah.test',
    phone: '+201003334455',
    gender: 'f',
    jobTitle: 'Branch manager',
    salaryEgp: 18000,
    hired: '2024-06-01',
  ),
  SeedPerson(
    'tarek',
    'Tarek Saber',
    'branch_manager',
    'maadi',
    email: 'tarek@sabah.test',
    phone: '+201004445566',
    gender: 'm',
    jobTitle: 'Branch manager',
    salaryEgp: 17000,
    hired: '2024-09-15',
  ),
  SeedPerson(
    'rana',
    'Rana Helmy',
    'branch_manager',
    'heliopolis',
    email: 'rana@sabah.test',
    phone: '+201005556677',
    gender: 'f',
    jobTitle: 'Branch manager',
    salaryEgp: 16500,
    hired: '2025-01-05',
  ),
  SeedPerson(
    'mariam',
    'Mariam Fathy',
    'teller',
    'zamalek',
    pin: '482915',
    phone: '+201110001111',
    gender: 'f',
    jobTitle: 'Barista',
    salaryEgp: 9500,
    hired: '2024-04-01',
  ),
  SeedPerson(
    'youssef',
    'Youssef Samir',
    'teller',
    'zamalek',
    pin: '503826',
    phone: '+201110002222',
    gender: 'm',
    jobTitle: 'Barista',
    salaryEgp: 9000,
    hired: '2024-08-20',
  ),
  SeedPerson(
    'salma',
    'Salma Nabil',
    'teller',
    'new-cairo',
    pin: '615937',
    phone: '+201110003333',
    gender: 'f',
    jobTitle: 'Barista',
    salaryEgp: 9500,
    hired: '2024-07-01',
  ),
  SeedPerson(
    'omar',
    'Omar Khaled',
    'teller',
    'new-cairo',
    pin: '726048',
    phone: '+201110004444',
    gender: 'm',
    jobTitle: 'Cashier',
    salaryEgp: 8500,
    hired: '2025-02-11',
  ),
  SeedPerson(
    'hana',
    'Hana Mostafa',
    'teller',
    'maadi',
    email: 'hana@sabah.test',
    pin: '837159',
    phone: '+201110005555',
    gender: 'f',
    jobTitle: 'Barista',
    salaryEgp: 9000,
    hired: '2024-10-01',
  ),
  SeedPerson(
    'ziad',
    'Ziad Amr',
    'teller',
    'maadi',
    pin: '348261',
    phone: '+201110006666',
    gender: 'm',
    jobTitle: 'Cashier',
    salaryEgp: 8500,
    hired: '2025-03-01',
  ),
  SeedPerson(
    'ali',
    'Ali Hassan',
    'teller',
    'heliopolis',
    pin: '948260',
    phone: '+201110007777',
    gender: 'm',
    jobTitle: 'Barista',
    salaryEgp: 9000,
    hired: '2025-01-15',
  ),
  SeedPerson(
    'farida',
    'Farida Wael',
    'teller',
    'heliopolis',
    pin: '159374',
    phone: '+201110008888',
    gender: 'f',
    jobTitle: 'Cashier',
    salaryEgp: 8500,
    hired: '2025-05-01',
  ),
  SeedPerson(
    'laila',
    'Laila Ehab',
    'waiter',
    'zamalek',
    pin: '271384',
    phone: '+201110009999',
    gender: 'f',
    jobTitle: 'Waiter',
    salaryEgp: 7500,
    hired: '2025-04-01',
  ),
  SeedPerson(
    'adham',
    'Adham Reda',
    'waiter',
    'zamalek',
    pin: '384295',
    phone: '+201111110000',
    gender: 'm',
    jobTitle: 'Waiter',
    salaryEgp: 7500,
    hired: '2025-06-10',
  ),
  SeedPerson(
    'hassan',
    'Hassan Ibrahim',
    'kitchen',
    'zamalek',
    pin: '495306',
    phone: '+201111112222',
    gender: 'm',
    jobTitle: 'Chef',
    salaryEgp: 11000,
    hired: '2024-05-01',
  ),
];

/// The morning and evening cashier of each branch (by person key).
const Map<String, List<String>> branchTellers = {
  'heliopolis': ['ali', 'farida'],
  'maadi': ['hana', 'ziad'],
  'new-cairo': ['salma', 'omar'],
  'zamalek': ['mariam', 'youssef'],
};

/// The branch manager of each branch (by person key).
const Map<String, String> branchManagers = {
  'heliopolis': 'rana',
  'maadi': 'tarek',
  'new-cairo': 'dina',
  'zamalek': 'karim',
};

/// Nakhla Bakery (the Dawam-only org): the owner and the bakery team.
const List<SeedPerson> nakhlaStaff = [
  SeedPerson(
    'yasmin',
    'Yasmin Ghali',
    'org_admin',
    null,
    email: 'yasmin@nakhla.test',
    phone: '+201222000111',
    gender: 'f',
    jobTitle: 'Owner',
    hired: '2023-11-01',
  ),
  SeedPerson(
    'sherif',
    'Sherif Mansour',
    'manual',
    'dokki',
    phone: '+201222000222',
    gender: 'm',
    jobTitle: 'Head baker',
    salaryEgp: 14000,
    hired: '2024-01-10',
  ),
  SeedPerson(
    'malak',
    'Malak Zaki',
    'app',
    'dokki',
    phone: '+201222000333',
    gender: 'f',
    jobTitle: 'Cashier',
    salaryEgp: 8000,
    hired: '2024-05-20',
  ),
  SeedPerson(
    'seif',
    'Seif Lotfy',
    'app',
    'dokki',
    phone: '+201222000444',
    gender: 'm',
    jobTitle: 'Baker',
    salaryEgp: 9000,
    hired: '2024-09-01',
  ),
  SeedPerson(
    'jana',
    'Jana Shawky',
    'app',
    'nasr-city',
    phone: '+201222000555',
    gender: 'f',
    jobTitle: 'Cashier',
    salaryEgp: 8000,
    hired: '2025-02-01',
  ),
  SeedPerson(
    'hamza',
    'Hamza Sayed',
    'manual',
    'nasr-city',
    phone: '+201222000666',
    gender: 'm',
    jobTitle: 'Baker',
    salaryEgp: 9000,
    hired: '2025-03-15',
  ),
  SeedPerson(
    'reem',
    'Reem Mostafa',
    'app',
    'nasr-city',
    phone: '+201222000777',
    gender: 'f',
    jobTitle: 'Shift lead',
    salaryEgp: 11000,
    hired: '2024-12-01',
  ),
];

class SeedCategory {
  const SeedCategory(this.key, this.name, this.ar);

  final String key;
  final String name;
  final String ar;
}

/// Coffee first, as a café's menu reads.
const List<SeedCategory> seedCategories = [
  SeedCategory('hot', 'Hot Coffee', 'قهوة ساخنة'),
  SeedCategory('iced', 'Iced Coffee', 'قهوة مثلجة'),
  SeedCategory('tea', 'Tea & More', 'شاي وأكثر'),
  SeedCategory('juice', 'Fresh Juice', 'عصائر طازجة'),
  SeedCategory('bakery', 'Bakery', 'مخبوزات'),
  SeedCategory('dessert', 'Desserts', 'حلويات'),
  SeedCategory('breakfast', 'Breakfast', 'فطور'),
];

class SeedItem {
  const SeedItem(
    this.key,
    this.category,
    this.name,
    this.ar,
    this.sizes,
    this.weight,
    this.groups, [
    this.description,
  ]);

  final String key;
  final String category;
  final String name;
  final String ar;

  /// (label, EGP); one entry means a single-size item priced by `base_price`.
  final List<(String, int)> sizes;

  /// How often it sells, relative to the others.
  final int weight;

  /// Modifier groups by key (`milk`, `extras`).
  final List<String> groups;
  final String? description;
}

/// Forty items: the film café's thirty-two plus eight from the web's mock menu.
const List<SeedItem> seedMenu = [
  SeedItem(
    'espresso',
    'hot',
    'Espresso',
    'إسبريسو',
    [('Single', 70), ('Double', 90)],
    5,
    ['extras'],
    'A short, intense shot of our house blend.',
  ),
  SeedItem(
    'americano',
    'hot',
    'Americano',
    'أمريكانو',
    [('Regular', 85), ('Large', 100)],
    7,
    ['extras'],
  ),
  SeedItem(
    'cortado',
    'hot',
    'Cortado',
    'كورتادو',
    [('One size', 95)],
    4,
    ['milk', 'extras'],
  ),
  SeedItem(
    'flatwhite',
    'hot',
    'Flat White',
    'فلات وايت',
    [('One size', 115)],
    6,
    ['milk', 'extras'],
  ),
  SeedItem(
    'cappuccino',
    'hot',
    'Cappuccino',
    'كابتشينو',
    [('Regular', 110), ('Large', 130)],
    9,
    ['milk', 'extras'],
    'Espresso with steamed milk and a thick layer of foam.',
  ),
  SeedItem(
    'latte',
    'hot',
    'Caffè Latte',
    'لاتيه',
    [('Regular', 115), ('Large', 135)],
    10,
    ['milk', 'extras'],
  ),
  SeedItem(
    'spanish',
    'hot',
    'Spanish Latte',
    'سبانش لاتيه',
    [('Regular', 130), ('Large', 150)],
    11,
    ['milk', 'extras'],
    'Our best seller: espresso, milk and condensed milk.',
  ),
  SeedItem(
    'mocha',
    'hot',
    'Mocha',
    'موكا',
    [('Regular', 135), ('Large', 155)],
    5,
    ['milk', 'extras'],
  ),
  SeedItem(
    'pistachio_latte',
    'hot',
    'Pistachio Latte',
    'لاتيه فستق',
    [('Regular', 145), ('Large', 165)],
    5,
    ['milk', 'extras'],
  ),
  SeedItem(
    'v60',
    'hot',
    'V60 Pour Over',
    'قهوة مقطّرة V60',
    [('One size', 120)],
    3,
    [],
  ),
  SeedItem(
    'turkish',
    'hot',
    'Turkish Coffee',
    'قهوة تركي',
    [('Single', 60), ('Double', 80)],
    4,
    [],
  ),
  SeedItem(
    'iced_americano',
    'iced',
    'Iced Americano',
    'آيس أمريكانو',
    [('Regular', 95), ('Large', 110)],
    6,
    ['extras'],
  ),
  SeedItem(
    'iced_latte',
    'iced',
    'Iced Latte',
    'آيس لاتيه',
    [('Regular', 130), ('Large', 150)],
    10,
    ['milk', 'extras'],
  ),
  SeedItem(
    'iced_spanish',
    'iced',
    'Iced Spanish Latte',
    'آيس سبانش لاتيه',
    [('Regular', 145), ('Large', 165)],
    12,
    ['milk', 'extras'],
  ),
  SeedItem(
    'iced_mocha',
    'iced',
    'Iced Mocha',
    'آيس موكا',
    [('Regular', 150), ('Large', 170)],
    5,
    ['milk', 'extras'],
  ),
  SeedItem(
    'cold_brew',
    'iced',
    'Cold Brew',
    'كولد برو',
    [('Regular', 120), ('Large', 140)],
    5,
    ['extras'],
  ),
  SeedItem(
    'frappe',
    'iced',
    'Caramel Frappé',
    'فرابيه كراميل',
    [('Regular', 155), ('Large', 175)],
    6,
    ['milk', 'extras'],
  ),
  SeedItem(
    'iced_matcha',
    'iced',
    'Iced Matcha',
    'آيس ماتشا',
    [('Regular', 150), ('Large', 170)],
    4,
    ['milk', 'extras'],
  ),
  SeedItem(
    'matcha',
    'tea',
    'Matcha Latte',
    'ماتشا لاتيه',
    [('Regular', 140), ('Large', 160)],
    6,
    ['milk', 'extras'],
  ),
  SeedItem(
    'chai',
    'tea',
    'Chai Latte',
    'تشاي لاتيه',
    [('Regular', 125), ('Large', 145)],
    3,
    ['milk', 'extras'],
  ),
  SeedItem(
    'hot_choc',
    'tea',
    'Hot Chocolate',
    'هوت شوكليت',
    [('One size', 120)],
    4,
    ['milk', 'extras'],
  ),
  SeedItem(
    'mint_lemonade',
    'tea',
    'Mint Lemonade',
    'ليمون بالنعناع',
    [('One size', 95)],
    6,
    [],
  ),
  SeedItem(
    'hibiscus',
    'tea',
    'Iced Hibiscus',
    'كركديه مثلج',
    [('One size', 70)],
    3,
    [],
  ),
  SeedItem(
    'green_tea',
    'tea',
    'Green Tea',
    'شاي أخضر',
    [('One size', 60)],
    3,
    [],
  ),
  SeedItem(
    'orange',
    'juice',
    'Orange Juice',
    'عصير برتقال',
    [('One size', 90)],
    4,
    [],
  ),
  SeedItem(
    'mango',
    'juice',
    'Mango Juice',
    'عصير مانجو',
    [('One size', 110)],
    4,
    [],
  ),
  SeedItem(
    'strawberry',
    'juice',
    'Strawberry Juice',
    'عصير فراولة',
    [('One size', 100)],
    3,
    [],
  ),
  SeedItem(
    'croissant',
    'bakery',
    'Butter Croissant',
    'كرواسون زبدة',
    [('One size', 75)],
    9,
    [],
  ),
  SeedItem(
    'almond_croissant',
    'bakery',
    'Almond Croissant',
    'كرواسون لوز',
    [('One size', 95)],
    5,
    [],
  ),
  SeedItem(
    'pain_choc',
    'bakery',
    'Pain au Chocolat',
    'بان أو شوكولا',
    [('One size', 90)],
    5,
    [],
  ),
  SeedItem(
    'cinnamon',
    'bakery',
    'Cinnamon Roll',
    'سينامون رول',
    [('One size', 85)],
    4,
    [],
  ),
  SeedItem(
    'cookie',
    'bakery',
    'Chocolate Chip Cookie',
    'كوكيز بالشوكولاتة',
    [('One size', 55)],
    5,
    [],
  ),
  SeedItem(
    'cheesecake',
    'dessert',
    'San Sebastián Cheesecake',
    'تشيز كيك سان سيباستيان',
    [('One size', 165)],
    6,
    [],
  ),
  SeedItem(
    'fudge',
    'dessert',
    'Chocolate Fudge Cake',
    'كيكة شوكولاتة',
    [('One size', 150)],
    4,
    [],
  ),
  SeedItem(
    'banana_bread',
    'dessert',
    'Banana Bread',
    'بنانا بريد',
    [('One size', 85)],
    3,
    [],
  ),
  SeedItem(
    'lemon_tart',
    'dessert',
    'Lemon Tart',
    'تارت الليمون',
    [('One size', 120)],
    3,
    [],
  ),
  SeedItem(
    'halloumi',
    'breakfast',
    'Halloumi Sandwich',
    'ساندوتش حلومي',
    [('One size', 185)],
    4,
    [],
  ),
  SeedItem(
    'turkey_croissant',
    'breakfast',
    'Turkey & Cheese Croissant',
    'كرواسون تركي وجبن',
    [('One size', 195)],
    4,
    [],
  ),
  SeedItem(
    'avocado',
    'breakfast',
    'Avocado Toast',
    'توست أفوكادو',
    [('One size', 210)],
    3,
    [],
  ),
  SeedItem(
    'shakshuka',
    'breakfast',
    'Shakshuka',
    'شكشوكة',
    [('One size', 165)],
    3,
    [],
  ),
];

class SeedOption {
  const SeedOption(
    this.key,
    this.name,
    this.ar,
    this.egp,
    this.isDefault,
    this.share,
  );

  final String key;
  final String name;
  final String ar;
  final int egp;
  final bool isDefault;

  /// How often it is picked when the group applies.
  final double share;
}

class SeedGroup {
  const SeedGroup(
    this.key,
    this.name,
    this.ar,
    this.selectionType,
    this.min,
    this.max,
    this.legacyType,
    this.effect,
    this.options,
  );

  final String key;
  final String name;
  final String ar;
  final String selectionType;
  final int min;
  final int? max;

  /// The legacy add-on type (`milk_type`, `extra`).
  final String legacyType;

  /// `swaps` or `adds`.
  final String effect;
  final List<SeedOption> options;
}

const List<SeedGroup> seedGroups = [
  SeedGroup('milk', 'Milk', 'اللبن', 'single', 0, 1, 'milk_type', 'swaps', [
    SeedOption('full', 'Full cream', 'كامل الدسم', 0, true, 0.60),
    SeedOption('skimmed', 'Skimmed', 'خالي الدسم', 0, false, 0.08),
    SeedOption('oat', 'Oat milk', 'حليب الشوفان', 25, false, 0.17),
    SeedOption('almond', 'Almond milk', 'حليب اللوز', 30, false, 0.07),
    SeedOption('coconut', 'Coconut milk', 'حليب جوز الهند', 30, false, 0.04),
    SeedOption(
      'lactose_free',
      'Lactose-free',
      'خالي اللاكتوز',
      15,
      false,
      0.04,
    ),
  ]),
  SeedGroup('extras', 'Extras', 'إضافات', 'multi', 0, null, 'extra', 'adds', [
    SeedOption('shot', 'Extra shot', 'شوت إضافي', 30, false, 0.13),
    SeedOption('vanilla', 'Vanilla syrup', 'سيروب فانيليا', 20, false, 0.07),
    SeedOption('caramel', 'Caramel syrup', 'سيروب كراميل', 20, false, 0.06),
    SeedOption('hazelnut', 'Hazelnut syrup', 'سيروب بندق', 20, false, 0.05),
    SeedOption('cream', 'Whipped cream', 'كريمة', 15, false, 0.05),
  ]),
];

/// Payment methods as the backend provisions them, with how often each is used.
class SeedPaymentMethod {
  const SeedPaymentMethod(
    this.name,
    this.en,
    this.ar,
    this.color,
    this.icon,
    this.isCash,
    this.share, {
    this.active = true,
  });

  final String name;
  final String en;
  final String ar;
  final String color;
  final String icon;
  final bool isCash;
  final double share;
  final bool active;
}

const List<SeedPaymentMethod> seedPaymentMethods = [
  SeedPaymentMethod(
    'cash',
    'Cash',
    'نقدي',
    'emerald',
    'payments_outlined',
    true,
    0.42,
  ),
  SeedPaymentMethod(
    'card',
    'Card',
    'بطاقة',
    'blue',
    'credit_card_rounded',
    false,
    0.36,
  ),
  SeedPaymentMethod(
    'digital_wallet',
    'Digital Wallet',
    'محفظة رقمية',
    'purple',
    'account_balance_wallet_rounded',
    false,
    0.14,
  ),
  SeedPaymentMethod(
    'mixed',
    'Mixed',
    'مختلط',
    'amber',
    'pie_chart_rounded',
    false,
    0,
  ),
  SeedPaymentMethod(
    'talabat_online',
    'Talabat Online',
    'طلبات أونلاين',
    'orange',
    'delivery_dining_rounded',
    false,
    0.08,
  ),
  SeedPaymentMethod(
    'talabat_cash',
    'Talabat Cash',
    'طلبات كاش',
    'orange',
    'delivery_dining_rounded',
    true,
    0,
    active: false,
  ),
];

/// Hour of day (Cairo) → relative order volume.
const Map<int, int> seedHours = {
  7: 2,
  8: 7,
  9: 9,
  10: 8,
  11: 6,
  12: 6,
  13: 7,
  14: 7,
  15: 6,
  16: 6,
  17: 7,
  18: 8,
  19: 9,
  20: 9, //
  21: 7, 22: 5,
};

/// Weekday (DateTime.monday = 1 … sunday = 7) → volume factor; Thu–Sat busier.
const Map<int, double> seedWeekday = {
  1: 0.93,
  2: 0.95,
  3: 1.0,
  4: 1.12,
  5: 1.24,
  6: 1.16,
  7: 0.97,
};

const List<String> seedFirstNames = [
  'Nada',
  'Omar',
  'Laila',
  'Youssef',
  'Salma',
  'Karim',
  'Hana',
  'Ali',
  'Mariam',
  'Ziad',
  'Farida', //
  'Tarek',
  'Rana',
  'Hassan',
  'Dina',
  'Adham',
  'Nour',
  'Mostafa',
  'Yasmin',
  'Sherif',
  'Malak',
  'Seif',
  'Jana', 'Hamza', 'Reem', 'Khaled', 'Habiba', 'Amr', 'Lina', 'Marwan',
];

const List<String> seedLastNames = [
  'Kamal',
  'Fathy',
  'Samir',
  'Nabil',
  'Khaled',
  'Mostafa',
  'Amr',
  'Hassan',
  'Wael',
  'Adel',
  'Fouad', //
  'Saber',
  'Helmy',
  'Ehab',
  'Reda',
  'Ibrahim',
  'Sayed',
  'Mansour',
  'Ghali',
  'Zaki',
  'Shawky',
  'Lotfy',
];

const List<String> seedVoidReasons = [
  'customer_request',
  'wrong_order',
  'quality_issue',
  'other',
];
