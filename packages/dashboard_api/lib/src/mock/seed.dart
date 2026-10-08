/// The deterministic dataset behind mock mode and every test: "Sabah Coffee"
/// (POS + Dawam, four Cairo branches, EGP), and "Nakhla Bakery" (Dawam only).
///
/// Every entity is built through the generated models, so its `toJson()` has
/// the spec's exact shape. The 30 days of orders and tills are generated on
/// first use (well under 300 ms); order lines only when an order is opened.
/// Money is in piastres; times are UTC; the business day is Cairo's.
library;

import 'package:meta/meta.dart';

import '../generated/mock_capabilities.dart';
import '../generated/models.dart';
import 'mock_clock.dart';
import 'mock_db.dart';
import 'mock_ids.dart';
import 'seed_data.dart';
import 'seed_ids.dart';

/// An item's attachment to a modifier group (`PUT /menu-items/{id}/modifier-groups`).
class SeedGroupLink {
  const SeedGroupLink({
    required this.id,
    required this.menuItemId,
    required this.groupId,
    required this.sort,
  });

  final String id;
  final String menuItemId;
  final String groupId;
  final int sort;

  Map<String, Object?> toJson() => {
    'id': id,
    'menu_item_id': menuItemId,
    'group_id': groupId,
    'sort': sort,
  };
}

class _Line {
  const _Line(this.item, this.size, this.qty, this.milk, this.extra);

  final int item;
  final int size;
  final int qty;
  final int? milk;
  final int? extra;
}

class _Agg {
  int count = 0;
  int spent = 0;
  DateTime? last;
}

/// The seed. [MockSeed.instance] is built once per process and never mutated:
/// a [MockDb] copies it into tables.
class MockSeed {
  MockSeed._();

  static final MockSeed instance = MockSeed._();

  /// A new, unshared seed (tests: timing and determinism).
  @visibleForTesting
  static MockSeed fresh() => MockSeed._();

  /// The seed's "now" (the default [MockClock] time).
  static final DateTime now = MockClock.defaultNow;

  static const int historyDays = 30;

  /// EGP 1,000 opening float, in piastres.
  static const int floatPiastres = 100000;

  static const double taxRate = 0.14;

  static final DateTime _orgCreated = DateTime.utc(2025, 12, 1, 9);
  static final DateTime _menuCreated = DateTime.utc(2026, 1, 10, 9);
  static final DateTime _configUpdated = DateTime.utc(2026, 9, 1, 9);

  static Map<String, Object?> tr(String en, String ar) => {'en': en, 'ar': ar};

  // ── orgs and branches ─────────────────────────────────────────────────

  late final Org org = Org(
    id: SeedIds.sabahOrg,
    name: 'Sabah Coffee',
    slug: 'sabah-coffee',
    currencyCode: 'EGP',
    timezone: MockClock.timezone,
    taxRate: taxRate,
    taxInclusive: true,
    serviceChargeRate: 0,
    serviceChargeTaxable: true,
    requireTableForOrders: false,
    customBranding: true,
    isActive: true,
    modules: const ['pos', 'dawam'],
    receiptFooter: 'Thank you for stopping by. See you tomorrow morning!',
    brandAccent: '#C2410C',
    brandBackground: '#FFF7ED',
    brandForeground: '#431407',
    brandLogoIsMark: true,
    socialLinks: const {
      'instagram': 'https://instagram.com/sabahcoffee.eg',
      'facebook': 'https://facebook.com/sabahcoffee.eg',
      'whatsapp': 'https://wa.me/201001112233',
    },
  );

  late final Org dawamOrg = Org(
    id: SeedIds.nakhlaOrg,
    name: 'Nakhla Bakery',
    slug: 'nakhla-bakery',
    currencyCode: 'EGP',
    timezone: MockClock.timezone,
    taxRate: taxRate,
    taxInclusive: true,
    serviceChargeRate: 0,
    serviceChargeTaxable: true,
    requireTableForOrders: false,
    customBranding: false,
    isActive: true,
    modules: const ['dawam'],
    socialLinks: const {},
  );

  late final List<Org> orgs = List.unmodifiable([org, dawamOrg]);

  Org orgById(String id) => orgs.firstWhere((o) => o.id == id);

  static String branchIdOf(String key) => switch (key) {
    'heliopolis' => SeedIds.heliopolis,
    'maadi' => SeedIds.maadi,
    'new-cairo' => SeedIds.newCairo,
    'zamalek' => SeedIds.zamalek,
    'dokki' => SeedIds.dokki,
    'nasr-city' => SeedIds.nasrCity,
    _ => throw ArgumentError('Unknown branch $key'),
  };

  /// Sabah's four branches, by name.
  late final List<Branch> branches = List.unmodifiable([
    for (final b in seedBranches)
      Branch(
        id: branchIdOf(b.key),
        orgId: SeedIds.sabahOrg,
        name: b.name,
        code: b.code,
        address: b.address,
        phone: b.phone,
        latitude: b.lat,
        longitude: b.lon,
        geoRadiusMeters: 200,
        timezone: MockClock.timezone,
        isActive: true,
        oldBillHours: 3,
        standardFloat: floatPiastres,
        printerBrand: PrinterBrand.epson,
        printerIp: '192.168.1.${40 + seedBranches.indexOf(b)}',
        printerPort: 9100,
        taxInclusive: true,
        taxRate: taxRate,
        serviceChargeRate: 0,
        serviceChargeTaxable: true,
        requireTableForOrders: false,
        orgReceiptFooter: org.receiptFooter,
        createdAt: _orgCreated.add(
          Duration(days: 3 + 40 * seedBranches.indexOf(b)),
        ),
        updatedAt: _configUpdated,
      ),
  ]);

  /// Nakhla Bakery's two branches.
  late final List<Branch> dawamBranches = List.unmodifiable([
    for (final (key, name, address, lat, lon) in const [
      ('dokki', 'Dokki', 'Tahrir St, Dokki, Giza', 30.0385, 31.2120),
      (
        'nasr-city',
        'Nasr City',
        'Abbas El Akkad St, Nasr City',
        30.0561,
        31.3300,
      ),
    ])
      Branch(
        id: branchIdOf(key),
        orgId: SeedIds.nakhlaOrg,
        name: name,
        code: key == 'dokki' ? 'DK' : 'NS',
        address: address,
        latitude: lat,
        longitude: lon,
        geoRadiusMeters: 150,
        timezone: MockClock.timezone,
        isActive: true,
        oldBillHours: 3,
        createdAt: _orgCreated.add(const Duration(days: 20)),
        updatedAt: _configUpdated,
      ),
  ]);

  late final List<Branch> allBranches = List.unmodifiable([
    ...branches,
    ...dawamBranches,
  ]);

  Branch branchById(String id) => allBranches.firstWhere((b) => b.id == id);

  // ── people ────────────────────────────────────────────────────────────

  /// Every user: Sabah's staff, Nakhla's owner and the platform admin.
  late final List<UserPublic> users = List.unmodifiable([
    for (final p in sabahStaff)
      UserPublic(
        id: SeedIds.user(p.key),
        name: p.name,
        email: p.email,
        phone: p.phone,
        role: UserRole.fromJson(p.role),
        orgId: SeedIds.sabahOrg,
        branchId: p.branch == null ? null : branchIdOf(p.branch!),
        isActive: true,
      ),
    UserPublic(
      id: SeedIds.dawamOwner,
      name: 'Yasmin Ghali',
      email: 'yasmin@nakhla.test',
      phone: '+201222000111',
      role: UserRole.orgAdmin,
      orgId: SeedIds.nakhlaOrg,
      isActive: true,
    ),
    UserPublic(
      id: SeedIds.platform,
      name: 'Madar Support',
      email: 'support@madar.test',
      role: UserRole.superAdmin,
      isActive: true,
    ),
  ]);

  UserPublic userById(String id) => users.firstWhere((u) => u.id == id);

  /// Dawam employees: every Sabah person (linked to their user) and Nakhla's team.
  late final List<Employee> employees = List.unmodifiable([
    for (final (i, p) in sabahStaff.indexed)
      _employee(p, SeedIds.sabahOrg, i, 'SB'),
    for (final (i, p) in nakhlaStaff.indexed)
      _employee(p, SeedIds.nakhlaOrg, i, 'NK'),
  ]);

  Employee _employee(SeedPerson p, String orgId, int i, String prefix) {
    final linked = p.role != 'manual' && p.role != 'app';
    final isOwner = p.role == 'org_admin';
    final branchIds = p.branch == null
        ? [
            for (final b
                in (orgId == SeedIds.sabahOrg ? branches : dawamBranches))
              b.id,
          ]
        : [branchIdOf(p.branch!)];
    return Employee(
      id: SeedIds.employee(p.key),
      orgId: orgId,
      userId: linked ? SeedIds.user(p.key) : null,
      name: p.name,
      phone: p.phone,
      email: p.email,
      kind: linked ? 'linked' : p.role,
      role: linked ? p.role : null,
      jobTitle: p.jobTitle,
      employeeCode: '$prefix-${(i + 1).toString().padLeft(3, '0')}',
      gender: p.gender,
      hireDate: p.hired,
      employmentStatus: 'active',
      appAccess: p.role != 'manual' && p.phone != null,
      onPayroll: !isOwner,
      salarySet: p.salaryEgp != null,
      baseSalaryPiastres: p.salaryEgp == null ? null : p.salaryEgp! * 100,
      payMethod: p.role == 'branch_manager' ? 'bank' : 'cash',
      advanceWithinCap: true,
      branchIds: branchIds,
      cantWorkDays: i % 5 == 2 ? const [5] : const [],
      prefTime: i.isEven ? 'morning' : 'evening',
      createdAt: _orgCreated.add(Duration(days: 5 + i)),
      updatedAt: _configUpdated,
    );
  }

  static const Map<String, (String, String)> _roleNames = {
    'org_admin': ('Owner', 'المالك'),
    'branch_manager': ('Branch manager', 'مدير الفرع'),
    'teller': ('Cashier', 'كاشير'),
    'waiter': ('Waiter', 'نادل'),
    'kitchen': ('Kitchen', 'المطبخ'),
  };

  /// Sabah's system roles with the registry's template grants.
  late final List<RoleView> roles = List.unmodifiable([
    for (final kind in _roleNames.keys)
      RoleView(
        id: mockUuid('role:sabah:$kind'),
        key: kind,
        kind: kind,
        nameEn: _roleNames[kind]!.$1,
        nameAr: _roleNames[kind]!.$2,
        isSystem: true,
        editable: kind != 'org_admin',
        members: sabahStaff.where((p) => p.role == kind).length,
        grants: [
          for (final c in mockCapabilities)
            if (c.tier != 'legacy' &&
                !c.key.startsWith('platform.') &&
                c.defaults.contains(kind))
              GrantView(
                capability: c.key,
                limits: const LimitsView(),
                source: 'template',
              ),
        ],
      ),
  ]);

  // ── money set-up ──────────────────────────────────────────────────────

  late final List<OrgPaymentMethod> paymentMethods = List.unmodifiable([
    for (final m in seedPaymentMethods)
      OrgPaymentMethod(
        id: mockUuid('payment-method:${m.name}'),
        orgId: SeedIds.sabahOrg,
        name: m.name,
        labelTranslations: tr(m.en, m.ar),
        color: m.color,
        icon: m.icon,
        isCash: m.isCash,
        isActive: m.active,
        visibleInIntegrations: m.name != 'mixed',
        createdAt: _orgCreated,
        updatedAt: _configUpdated,
      ),
  ]);

  // ── menu ──────────────────────────────────────────────────────────────

  static String categoryId(String key) => mockUuid('category:$key');

  static String menuItemId(String key) => mockUuid('menu-item:$key');

  static String sizeId(String item, String label) =>
      mockUuid('size:$item:$label');

  static String groupId(String key) => mockUuid('group:$key');

  static String optionId(String group, String key) =>
      mockUuid('option:$group:$key');

  static String addonItemId(String group, String key) =>
      mockUuid('addon:$group:$key');

  late final List<Category> categories = List.unmodifiable([
    for (final (i, c) in seedCategories.indexed)
      Category(
        id: categoryId(c.key),
        orgId: SeedIds.sabahOrg,
        name: c.name,
        nameTranslations: tr(c.name, c.ar),
        displayOrder: i,
        isActive: true,
        createdAt: _menuCreated,
        updatedAt: _configUpdated,
      ),
  ]);

  late final List<MenuItem> menuItems = List.unmodifiable([
    for (final (i, m) in seedMenu.indexed)
      MenuItem(
        id: menuItemId(m.key),
        orgId: SeedIds.sabahOrg,
        categoryId: categoryId(m.category),
        name: m.name,
        nameTranslations: tr(m.name, m.ar),
        description: m.description,
        descriptionTranslations: m.description == null
            ? const {}
            : {'en': m.description},
        basePrice: m.sizes.first.$2 * 100,
        isActive: true,
        kind: 'item',
        createdAt: _menuCreated.add(Duration(minutes: i)),
        updatedAt: _configUpdated,
      ),
  ]);

  /// Sizes of the items that come in more than one.
  late final List<ItemSize> itemSizes = List.unmodifiable([
    for (final m in seedMenu)
      if (m.sizes.length > 1)
        for (final (label, egp) in m.sizes)
          ItemSize(
            id: sizeId(m.key, label),
            menuItemId: menuItemId(m.key),
            label: label,
            priceOverride: egp * 100,
            isActive: true,
          ),
  ]);

  late final List<GroupOut> modifierGroups = List.unmodifiable([
    for (final (gi, g) in seedGroups.indexed)
      GroupOut(
        id: groupId(g.key),
        orgId: SeedIds.sabahOrg,
        name: g.name,
        nameTranslations: tr(g.name, g.ar),
        selectionType: g.selectionType,
        minSelections: g.min,
        maxSelections: g.max,
        isRequired: false,
        isActive: true,
        effect: g.effect,
        legacyAddonType: g.legacyType,
        sort: gi,
        options: [
          for (final (oi, o) in g.options.indexed)
            GroupOptionOut(
              id: optionId(g.key, o.key),
              name: o.name,
              nameTranslations: tr(o.name, o.ar),
              price: o.egp * 100,
              isDefault: o.isDefault,
              isActive: true,
              sort: oi,
            ),
        ],
      ),
  ]);

  late final List<SeedGroupLink> itemGroups = List.unmodifiable([
    for (final m in seedMenu)
      for (final (i, g) in m.groups.indexed)
        SeedGroupLink(
          id: mockUuid('group-link:${m.key}:$g'),
          menuItemId: menuItemId(m.key),
          groupId: groupId(g),
          sort: i,
        ),
  ]);

  /// The legacy add-on catalogue (milk types and extras).
  late final List<AddonItem> addonItems = List.unmodifiable([
    for (final g in seedGroups)
      for (final o in g.options)
        AddonItem(
          id: addonItemId(g.key, o.key),
          orgId: SeedIds.sabahOrg,
          name: o.name,
          nameTranslations: tr(o.name, o.ar),
          addonType: g.legacyType,
          defaultPrice: o.egp * 100,
          isActive: true,
          createdAt: _menuCreated,
          updatedAt: _configUpdated,
        ),
  ]);

  // ── staff schedule set-up (Dawam) ─────────────────────────────────────

  late final List<WorkShift> workShifts = List.unmodifiable([
    for (final (orgId, prefix) in [
      (SeedIds.sabahOrg, 'sabah'),
      (SeedIds.nakhlaOrg, 'nakhla'),
    ])
      for (final (key, name, start, end) in const [
        ('morning', 'Morning', '07:00', '15:00'),
        ('evening', 'Evening', '15:00', '23:00'),
      ])
        WorkShift(
          id: mockUuid('work-shift:$prefix:$key'),
          orgId: orgId,
          name: name,
          startTime: start,
          endTime: end,
          crossesMidnight: false,
          breakMinutes: 30,
          paidBreak: true,
          graceMinutes: 10,
          checkinWindowMinutes: 60,
          overtimeThresholdMinutes: 30,
          overtimeMultiplier: 1.5,
          validDays: const [0, 1, 2, 3, 4, 5, 6],
          isActive: true,
          createdAt: _orgCreated.add(const Duration(days: 10)),
          updatedAt: _configUpdated,
        ),
  ]);

  late final List<AttendanceSettings> attendanceSettings = List.unmodifiable([
    for (final (orgId, prefix) in [
      (SeedIds.sabahOrg, 'sabah'),
      (SeedIds.nakhlaOrg, 'nakhla'),
    ])
      AttendanceSettings(
        id: mockUuid('attendance-settings:$prefix'),
        orgId: orgId,
        absenceDeductionDays: 1,
        advanceCapPercent: 50,
        autoCheckoutBufferMinutes: 60,
        coverPayMode: 'minute_rate',
        defaultOvertimeMultiplier: 1.5,
        excusedTimePaidDefault: true,
        genderMode: 'soft',
        halfDayLeaveCounts: 'half_shift',
        holidayMultiplier: 2,
        lateDeductionTiers: const [
          {
            'from_minutes': 15,
            'to_minutes': 30,
            'kind': 'minutes',
            'value': 30,
          },
          {
            'from_minutes': 30,
            'to_minutes': 60,
            'kind': 'day_fraction',
            'value': 0.25,
          },
          {'from_minutes': 60, 'kind': 'day_fraction', 'value': 0.5},
        ],
        limitDayHours: 12,
        limitOvertimeDayHours: 4,
        limitPresenceHours: 14,
        limitRestHours: 11,
        limitWeekHours: 60,
        nightStart: '22:00',
        nightEnd: '06:00',
        ordersPerStaff: 25,
        overtimeMode: 'approval',
        overtimeDayMultiplier: 1.35,
        overtimeNightMultiplier: 1.7,
        periodStartDay: 1,
        requireGeofence: true,
        workingDaysPerMonth: 26,
        rulesSavedAt: _configUpdated,
        createdAt: _orgCreated.add(const Duration(days: 10)),
        updatedAt: _configUpdated,
      ),
  ]);

  // ── shell reads ───────────────────────────────────────────────────────

  OrgModules modules(String orgId) =>
      OrgModules(orgId: orgId, modules: orgById(orgId).modules);

  /// Sabah finished its first-run checklist; Nakhla (Dawam only) never sees it.
  OnboardingStatus onboarding(String orgId) {
    final done = orgId == SeedIds.sabahOrg;
    return OnboardingStatus(
      orgId: orgId,
      completed: done,
      completedAt: done ? DateTime.utc(2026, 1, 12, 10) : null,
      canComplete: done,
      recipeCoverage: done ? 0.85 : 0,
      steps: [
        OnboardingStep(
          key: 'branches',
          count: done ? 4 : 0,
          done: done,
          required_: true,
        ),
        OnboardingStep(
          key: 'categories',
          count: done ? categories.length : 0,
          done: done,
          required_: true,
        ),
        OnboardingStep(
          key: 'menu_items',
          count: done ? menuItems.length : 0,
          done: done,
          required_: true,
        ),
        OnboardingStep(
          key: 'staff',
          count: done ? sabahStaff.length - 1 : 0,
          done: done,
          required_: true,
        ),
        OnboardingStep(
          key: 'payment_methods',
          count: done ? 5 : 0,
          done: done,
          required_: false,
        ),
        OnboardingStep(
          key: 'recipes',
          count: done ? 34 : 0,
          done: done,
          required_: false,
        ),
      ],
    );
  }

  PublicBrand brand(String orgId) {
    final o = orgById(orgId);
    return PublicBrand(
      orgId: o.id,
      name: o.name,
      slug: o.slug,
      customBranding: o.customBranding,
      accentColor: o.brandAccent ?? '#0F766E',
      backgroundColor: o.brandBackground ?? '#FFFFFF',
      foregroundColor: o.brandForeground ?? '#0F172A',
      logoIsMark: o.brandLogoIsMark ?? false,
      logoUrl: o.logoUrl,
    );
  }

  // ── customers, tills and orders (generated together) ─────────────────

  /// The customers: the film's loyalty member first, then 199 more.
  late final List<Customer> customers = _buildCustomers();

  /// Two tills per branch per day (morning, evening) for 30 days; today's
  /// morning tills are still open.
  List<Till> get tills => _history.tills;

  /// Every order of the last 30 days, oldest first.
  List<Order> get orders => _history.orders;

  late final Map<String, Order> _ordersById = {for (final o in orders) o.id: o};

  Order? orderById(String id) => _ordersById[id];

  /// The lines of an order (built on demand).
  List<OrderItemFull> orderItems(String orderId) {
    final lines = _history.lines[orderId];
    if (lines == null) return const [];
    return [for (final (i, l) in lines.indexed) _orderItem(orderId, i, l)];
  }

  /// An order with its lines, as `GET /orders/{id}` answers.
  OrderFull? orderFull(String orderId) {
    final o = orderById(orderId);
    if (o == null) return null;
    return OrderFull.fromJson({
      ...o.toJson(),
      'items': [for (final i in orderItems(orderId)) i.toJson()],
    });
  }

  OrderItemFull _orderItem(String orderId, int i, _Line l) {
    final m = seedMenu[l.item];
    final (label, egp) = m.sizes[l.size];
    final id = mockUuid('order-item:$orderId:$i');
    final addons = <OrderItemAddon>[];
    var unit = egp * 100;
    void addon(String group, int option) {
      final g = seedGroups.firstWhere((x) => x.key == group);
      final o = g.options[option];
      addons.add(
        OrderItemAddon(
          id: mockUuid('order-item-addon:$id:$group'),
          orderItemId: id,
          addonItemId: addonItemId(group, o.key),
          addonName: o.name,
          nameTranslations: tr(o.name, o.ar),
          quantity: l.qty,
          unitPrice: o.egp * 100,
          lineTotal: o.egp * 100 * l.qty,
        ),
      );
    }

    if (l.milk != null) addon('milk', l.milk!);
    if (l.extra != null) addon('extras', l.extra!);
    final addonUnit = addons.fold<int>(0, (s, a) => s + a.unitPrice);
    unit += addonUnit;
    return OrderItemFull(
      id: id,
      orderId: orderId,
      menuItemId: menuItemId(m.key),
      itemName: m.name,
      nameTranslations: tr(m.name, m.ar),
      sizeLabel: m.sizes.length > 1 ? label : null,
      quantity: l.qty,
      unitPrice: egp * 100,
      lineTotal: unit * l.qty,
      costMissing: false,
      deductionsSnapshot: const <Object?>[],
      addons: addons,
      optionals: const [],
    );
  }

  static int _lineTotal(_Line l) {
    final m = seedMenu[l.item];
    var unit = m.sizes[l.size].$2 * 100;
    if (l.milk != null) unit += seedGroups[0].options[l.milk!].egp * 100;
    if (l.extra != null) unit += seedGroups[1].options[l.extra!].egp * 100;
    return unit * l.qty;
  }

  static String _customerPhone(MockRandom rng, Set<String> used) {
    while (true) {
      final p =
          '01${rng.pick(const ['0', '1', '2', '5'])}'
          '${List.generate(8, (_) => rng.nextInt(10)).join()}';
      if (used.add(p)) return p;
    }
  }

  late final List<(String, String)> _customerPeople = () {
    final rng = MockRandom('sabah-customers');
    final used = <String>{'01001234567'};
    return [
      ('Nada Kamal', '01001234567'),
      for (var i = 1; i < 200; i++)
        (
          '${rng.pick(seedFirstNames)} ${rng.pick(seedLastNames)}',
          _customerPhone(rng, used),
        ),
    ];
  }();

  List<Customer> _buildCustomers() {
    final rng = MockRandom('sabah-customer-details');
    final agg = _history.customerAgg;
    const notes = [
      'Prefers oat milk.',
      'Allergic to nuts — check the pastry.',
      'Orders for the office every Thursday.',
      'Likes the window table.',
    ];
    return List.unmodifiable([
      for (final (i, (name, phone)) in _customerPeople.indexed)
        () {
          final a = agg[i];
          final member = i == 0 || rng.chance(0.6);
          final created = now.subtract(
            Duration(days: 31 + rng.nextInt(300), minutes: rng.nextInt(600)),
          );
          final birthday = rng.chance(0.4);
          return Customer(
            id: customerId(i),
            name: name,
            phone: phone,
            locale: rng.chance(0.55) ? 'ar' : 'en',
            source: i == 0
                ? 'loyalty'
                : rng.weighted(
                    const ['pos', 'loyalty', 'order_now'],
                    const [7, 2, 1],
                  ),
            isMember: member,
            loyaltyCustomerId: member ? mockUuid('loyalty-member:$i') : null,
            visitsBalance: member ? (i == 0 ? 6 : rng.nextInt(8)) : null,
            marketingOptOut: rng.chance(0.08),
            birthDay: birthday ? 1 + rng.nextInt(28) : null,
            birthMonth: birthday ? 1 + rng.nextInt(12) : null,
            notes: i % 37 == 5 ? notes[(i ~/ 37) % notes.length] : null,
            ordersCount: a?.count ?? 0,
            totalSpent: a?.spent ?? 0,
            lastOrderAt: a?.last,
            createdAt: created,
            updatedAt: a?.last ?? created,
          );
        }(),
    ]);
  }

  static String customerId(int i) => mockUuid('customer:$i');

  static String tillId(String branchKey, String date, String shift) =>
      mockUuid('till:$branchKey:$date:$shift');

  late final _History _history = _History.build(this);

  /// Copies the seed into [db] as JSON rows (each a model's `toJson()`):
  ///
  /// | table | rows |
  /// |---|---|
  /// | `orgs` | [Org] (Sabah Coffee, Nakhla Bakery) |
  /// | `branches` | [Branch] (both orgs) |
  /// | `users` | [UserPublic] |
  /// | `employees` | [Employee] |
  /// | `roles` | [RoleView] (Sabah's system roles) |
  /// | `payment_methods` | [OrgPaymentMethod] |
  /// | `categories` | [Category] |
  /// | `menu_items` | [MenuItem] |
  /// | `item_sizes` | [ItemSize] |
  /// | `modifier_groups` | [GroupOut] (options inline) |
  /// | `item_group_links` | [SeedGroupLink] |
  /// | `addon_items` | [AddonItem] |
  /// | `work_shifts` | [WorkShift] |
  /// | `attendance_settings` | [AttendanceSettings] (one per org) |
  /// | `customers` | [Customer] (lazy) |
  /// | `tills` | [Till] (lazy) |
  /// | `orders` | [Order] (lazy; lines via [orderItems]) |
  void loadInto(MockDb db) {
    void put<T>(
      String table,
      List<T> rows,
      Map<String, Object?> Function(T row) json,
    ) => db.table(table).insertAll(rows.map(json), timestamps: false);
    put<Org>('orgs', orgs, (o) => o.toJson());
    put<Branch>('branches', allBranches, (o) => o.toJson());
    put<UserPublic>('users', users, (o) => o.toJson());
    put<Employee>('employees', employees, (o) => o.toJson());
    put<RoleView>('roles', roles, (o) => o.toJson());
    put<OrgPaymentMethod>('payment_methods', paymentMethods, (o) => o.toJson());
    put<Category>('categories', categories, (o) => o.toJson());
    put<MenuItem>('menu_items', menuItems, (o) => o.toJson());
    put<ItemSize>('item_sizes', itemSizes, (o) => o.toJson());
    put<GroupOut>('modifier_groups', modifierGroups, (o) => o.toJson());
    put<SeedGroupLink>('item_group_links', itemGroups, (o) => o.toJson());
    put<AddonItem>('addon_items', addonItems, (o) => o.toJson());
    put<WorkShift>('work_shifts', workShifts, (o) => o.toJson());
    put<AttendanceSettings>(
      'attendance_settings',
      attendanceSettings,
      (o) => o.toJson(),
    );
    db.lazyTable('customers', () => [for (final c in customers) c.toJson()]);
    db.lazyTable('tills', () => [for (final t in tills) t.toJson()]);
    db.lazyTable('orders', () => [for (final o in orders) o.toJson()]);
  }
}

class _History {
  _History(this.orders, this.tills, this.lines, this.customerAgg);

  final List<Order> orders;
  final List<Till> tills;
  final Map<String, List<_Line>> lines;
  final Map<int, _Agg> customerAgg;

  static _History build(MockSeed seed) {
    final orders = <Order>[];
    final tills = <Till>[];
    final lines = <String, List<_Line>>{};
    final agg = <int, _Agg>{};
    final now = MockSeed.now;
    final today = MockClock.startOfCairoDay(now);
    final hours = seedHours.keys.toList();
    final hourWeights = seedHours.values.toList();
    final itemWeights = [for (final m in seedMenu) m.weight];
    final itemIdx = [for (var i = 0; i < seedMenu.length; i++) i];
    final pms = [
      for (final m in seedPaymentMethods)
        if (m.share > 0) m,
    ];
    final pmWeights = [for (final m in pms) m.share];
    final milk = seedGroups[0].options;
    final milkIdx = [for (var i = 0; i < milk.length; i++) i];
    final milkW = [for (final o in milk) o.share];
    final extras = seedGroups[1].options;
    final extraIdx = [for (var i = 0; i < extras.length; i++) i];
    final extraW = [for (final o in extras) o.share];
    final names = {for (final p in sabahStaff) p.key: p.name};

    for (final b in seedBranches) {
      final branchId = MockSeed.branchIdOf(b.key);
      final tellers = branchTellers[b.key]!;
      final managerId = SeedIds.user(branchManagers[b.key]!);
      final deviceId = mockUuid('device:${b.key}:T1');
      for (var d = MockSeed.historyDays - 1; d >= 0; d--) {
        final dayStart = today.subtract(Duration(days: d));
        final date = MockClock.cairoDate(
          dayStart.add(const Duration(hours: 12)),
        );
        final ymd = date.substring(2).replaceAll('-', '');
        final rng = MockRandom('orders:${b.key}:$date');
        final weekday = MockClock.wall(
          dayStart.add(const Duration(hours: 12)),
        ).weekday;
        final n =
            (b.dailyOrders *
                    seedWeekday[weekday]! *
                    (0.92 + 0.16 * rng.nextDouble()))
                .round();
        final times = <DateTime>[
          for (var i = 0; i < n; i++)
            dayStart.add(
              Duration(
                hours: rng.weighted(hours, hourWeights),
                minutes: rng.nextInt(60),
                seconds: rng.nextInt(60),
              ),
            ),
        ]..sort();
        // The two tills of the day.
        final tillOf = <String, (String, DateTime, String)>{};
        for (final (shift, startH, tellerKey) in [
          ('morning', 6, tellers[0]),
          ('evening', 14, tellers[1]),
        ]) {
          final opened = dayStart.add(
            Duration(hours: startH, minutes: 50 + rng.nextInt(9)),
          );
          if (opened.isAfter(now)) continue;
          tillOf[shift] = (
            MockSeed.tillId(b.key, date, shift),
            opened,
            tellerKey,
          );
        }
        final tillCash = <String, int>{};
        final tillOrders = <String, int>{};
        var seq = 0;
        for (final at in times) {
          if (at.isAfter(now)) break;
          final shift = MockClock.wall(at).hour < 15 ? 'morning' : 'evening';
          final till = tillOf[shift];
          if (till == null) continue;
          final (tillId, _, tellerKey) = till;
          seq++;
          final number = (tillOrders[tillId] = (tillOrders[tillId] ?? 0) + 1);
          final id = mockUuid('order:${b.key}:$date:$seq');
          // Lines.
          final count = rng.weighted(const [1, 2, 3], const [55, 30, 15]);
          final ls = <_Line>[];
          for (var k = 0; k < count; k++) {
            final item = rng.weighted(itemIdx, itemWeights);
            final m = seedMenu[item];
            final size = m.sizes.length > 1 && rng.chance(0.35) ? 1 : 0;
            final qty = rng.chance(0.9) ? 1 : 2;
            int? milkPick;
            if (m.groups.contains('milk') && rng.chance(0.4)) {
              final p = rng.weighted(milkIdx, milkW);
              if (p != 0) milkPick = p;
            }
            int? extraPick;
            if (m.groups.contains('extras') && rng.chance(0.22)) {
              extraPick = rng.weighted(extraIdx, extraW);
            }
            ls.add(_Line(item, size, qty, milkPick, extraPick));
          }
          lines[id] = ls;
          final subtotal = ls.fold<int>(
            0,
            (s, l) => s + MockSeed._lineTotal(l),
          );
          final discounted = rng.chance(0.05);
          final discount = discounted ? (subtotal * 0.10).round() : 0;
          final total = subtotal - discount;
          final tax = (total * 14 / 114).round();
          final pm = rng.weighted(pms, pmWeights);
          final split = pm.name == 'card' && rng.chance(0.06);
          final method = split ? 'mixed' : pm.name;
          final delivery = pm.name.startsWith('talabat');
          final orderType = delivery
              ? 'delivery'
              : (rng.chance(0.4) ? 'dine_in' : 'takeaway');
          final voided = rng.chance(0.015);
          final tip = pm.name == 'card' && !voided && rng.chance(0.1)
              ? (10 + rng.nextInt(3) * 5) * 100
              : null;
          final legs = split
              ? [
                  PaymentLeg(
                    method: 'cash',
                    amount: (total ~/ 200) * 100,
                    isCash: true,
                  ),
                  PaymentLeg(
                    method: 'card',
                    amount: total - (total ~/ 200) * 100,
                    isCash: false,
                  ),
                ]
              : [PaymentLeg(method: pm.name, amount: total, isCash: pm.isCash)];
          final cashPart = legs
              .where((l) => l.isCash ?? false)
              .fold<int>(0, (s, l) => s + l.amount);
          int? tendered;
          int? change;
          if (method == 'cash') {
            final step = total > 20000 ? 10000 : 5000;
            tendered = rng.chance(0.4)
                ? total
                : ((total + step - 1) ~/ step) * step;
            change = tendered - total;
          }
          // A customer on about a quarter of orders, regulars more often.
          int? customer;
          if (rng.chance(0.24)) {
            customer = rng.chance(0.55) ? rng.nextInt(40) : rng.nextInt(200);
          }
          final status = voided ? 'voided' : 'completed';
          if (!voided) {
            tillCash[tillId] = (tillCash[tillId] ?? 0) + cashPart;
            if (customer != null) {
              final a = agg[customer] ??= _Agg();
              a.count++;
              a.spent += total;
              if (a.last == null || at.isAfter(a.last!)) a.last = at;
            }
          }
          final tellerId = SeedIds.user(tellerKey);
          orders.add(
            Order(
              id: id,
              branchId: branchId,
              tillId: tillId,
              shiftId: tillId,
              tellerId: tellerId,
              tellerName: names[tellerKey]!,
              deviceId: deviceId,
              deviceCode: 'T1',
              displayNumber: 'T1-$number',
              orderNumber: number,
              orderRef: '${b.code}-$ymd-T1-${seq.toString().padLeft(4, '0')}',
              status: status,
              orderType: orderType,
              deliveryChannel: delivery ? 'outside' : null,
              deliveryFee: 0,
              paymentMethod: method,
              paymentLegs: legs,
              amountTendered: tendered,
              changeGiven: change,
              subtotal: subtotal,
              discountAmount: discount,
              discountValue: discounted ? 10 : 0,
              discountType: discounted ? 'percentage' : null,
              discountKind: discounted ? 'manual_percent' : null,
              discountPercentBps: discounted ? 1000 : null,
              discountAppliedBy: discounted ? managerId : null,
              discountAppliedByName: discounted
                  ? names[branchManagers[b.key]]
                  : null,
              taxAmount: tax,
              taxInclusive: true,
              taxRateApplied: MockSeed.taxRate,
              serviceChargeAmount: 0,
              totalAmount: total,
              tipAmount: tip,
              tipPaymentMethod: tip == null ? null : 'card',
              customerId: customer == null
                  ? null
                  : MockSeed.customerId(customer),
              customerName: customer == null
                  ? null
                  : seed._customerPeople[customer].$1,
              voidReason: voided ? rng.pick(seedVoidReasons) : null,
              voidedAt: voided
                  ? at.add(Duration(minutes: 3 + rng.nextInt(12)))
                  : null,
              voidedBy: voided ? managerId : null,
              timezone: MockClock.timezone,
              verification: 'server',
              createdAt: at,
            ),
          );
        }
        // Close the day's tills.
        for (final (shift, (tillId, opened, tellerKey)) in [
          for (final e in tillOf.entries) (e.key, e.value),
        ]) {
          final closeAt = dayStart.add(
            Duration(
              hours: shift == 'morning' ? 15 : 23,
              minutes: 5 + rng.nextInt(10),
            ),
          );
          final open = closeAt.isAfter(now);
          final system = MockSeed.floatPiastres + (tillCash[tillId] ?? 0);
          final r = rng.nextDouble();
          final discrepancy = r < 0.8
              ? 0
              : (r < 0.9
                    ? -(5 + rng.nextInt(26)) * 100
                    : (5 + rng.nextInt(16)) * 100);
          final forced =
              !open && b.key == 'maadi' && d == 12 && shift == 'evening';
          final tellerId = SeedIds.user(tellerKey);
          tills.add(
            Till(
              id: tillId,
              branchId: branchId,
              branchName: b.name,
              tellerId: tellerId,
              tellerName: names[tellerKey]!,
              deviceId: deviceId,
              deviceCode: 'T1',
              deviceLabel: 'Counter 1',
              openedAt: opened,
              openingCash: MockSeed.floatPiastres,
              openingCashWasEdited: false,
              openedWhileAnotherOpen: false,
              disagreementCount: 0,
              status: open
                  ? TillStatus.open
                  : (forced ? TillStatus.forceClosed : TillStatus.closed),
              verification: TillVerification.server,
              closedAt: open ? null : closeAt,
              closedBy: open ? null : (forced ? managerId : tellerId),
              closingCashSystem: open || forced ? null : system,
              closingCashDeclared: open || forced ? null : system + discrepancy,
              cashDiscrepancy: open || forced ? null : discrepancy,
              forceClosedAt: forced ? closeAt : null,
              forceClosedBy: forced ? managerId : null,
              forceCloseReason: forced
                  ? 'Teller left without closing the drawer.'
                  : null,
              openBillsAtClose: open ? null : 0,
              oldBillsAtClose: open ? null : 0,
              timezone: MockClock.timezone,
            ),
          );
        }
      }
    }
    orders.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    tills.sort((a, b) => a.openedAt.compareTo(b.openedAt));
    return _History(
      List.unmodifiable(orders),
      List.unmodifiable(tills),
      lines,
      agg,
    );
  }
}
