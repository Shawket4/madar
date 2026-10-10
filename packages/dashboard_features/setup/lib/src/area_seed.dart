/// The setup area's own domain data: the settings several setup units read,
/// so their numbers agree.
///
/// | table | rows | read by |
/// |---|---|---|
/// | `delivery_settings` | [BranchDeliverySettings], one per Sabah branch | delivery; links (the "Order now" module); QR (in-mall code) |
/// | `booking_settings` | [BookingSettings]; sell's rows, one per branch | booking_settings; links ("Book a table"); QR (booking codes) |
/// | `loyalty_settings` | [LoyaltySettings]: the org's programme + Zamalek's own | loyalty; links ("Rewards card") |
///
/// Every row is a generated model's `toJson()` (the spec's exact shape) and
/// references the core seed's ids (`SeedIds`, `MockSeed`). The rows carry no
/// `id` (the spec has none): find them by `branch_id` / `org_id`. A table is
/// seeded only when no other area seeded it first ([seedTableIfAbsent]), so
/// sell's bookings page and this area's bookings pane read one record.
///
/// Units add their own tables in their own `mock/<unit>_mock.dart` (zones,
/// stations, credentials, …); [linksModules] is the backend's rule for which
/// links-page buttons can show, over the tables above.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';

import 'mock/support.dart';

abstract final class SetupSeed {
  /// Table names (shared with other areas that read the same records).
  static const String deliverySettingsTable = 'delivery_settings';
  static const String bookingSettingsTable = 'booking_settings';
  static const String loyaltySettingsTable = 'loyalty_settings';

  /// The public pages' root domain: a shop on the branding tier with a slug
  /// lives at `https://<slug>.<root>/` (the web derives it from the API host).
  static const String publicRootDomain = 'madar-pos.cloud';

  /// The org's own public address (`public_url`), trailing slash included.
  static String publicUrl(String slug) => 'https://$slug.$publicRootDomain/';

  /// Where each links-page module opens on the shop's host
  /// (`links_module_path`).
  static const Map<String, String> modulePaths = {
    'order': '/order/',
    'menu': '/order/menu',
    'rewards': '/rewards',
    'book': '/book/',
  };

  // ── delivery ───────────────────────────────────────────────────────────

  /// Heliopolis and Maadi deliver and take pickups; New Cairo also serves
  /// its mall; Zamalek takes pickups only. Fees in piastres.
  static final List<BranchDeliverySettings> deliverySettings = [
    BranchDeliverySettings(
      branchId: SeedIds.heliopolis,
      inMallEnabled: false,
      inMallFee: 0,
      inMallOverride: 'auto',
      inMallRequireLocation: true,
      outsideEnabled: true,
      outsideOpenTime: '08:00:00',
      outsideCloseTime: '23:00:00',
      outsideOverride: 'auto',
      maxRoadDistanceMeters: 6000,
      umbrellaEnabled: false,
      umbrellaFee: 0,
      umbrellaOverride: 'auto',
      pickupEnabled: true,
      pickupOpenTime: '07:30:00',
      pickupCloseTime: '23:30:00',
      pickupFee: 0,
      pickupOverride: 'auto',
      prepTimeMinutes: 15,
      otpRequired: true,
    ),
    BranchDeliverySettings(
      branchId: SeedIds.maadi,
      inMallEnabled: false,
      inMallFee: 0,
      inMallOverride: 'auto',
      inMallRequireLocation: true,
      outsideEnabled: true,
      outsideOpenTime: '08:00:00',
      outsideCloseTime: '00:00:00',
      outsideOverride: 'auto',
      maxRoadDistanceMeters: 5000,
      umbrellaEnabled: false,
      umbrellaFee: 0,
      umbrellaOverride: 'auto',
      pickupEnabled: true,
      pickupOpenTime: '07:00:00',
      pickupCloseTime: '00:00:00',
      pickupFee: 0,
      pickupOverride: 'auto',
      prepTimeMinutes: 12,
      otpRequired: true,
    ),
    BranchDeliverySettings(
      branchId: SeedIds.newCairo,
      inMallEnabled: true,
      inMallOpenTime: '10:00:00',
      inMallCloseTime: '22:00:00',
      inMallFee: 1500,
      inMallOverride: 'auto',
      inMallRequireLocation: true,
      outsideEnabled: true,
      outsideOpenTime: '10:00:00',
      outsideCloseTime: '23:00:00',
      outsideOverride: 'auto',
      maxRoadDistanceMeters: 8000,
      umbrellaEnabled: false,
      umbrellaFee: 0,
      umbrellaOverride: 'auto',
      pickupEnabled: true,
      pickupOpenTime: '10:00:00',
      pickupCloseTime: '23:00:00',
      pickupFee: 0,
      pickupOverride: 'auto',
      prepTimeMinutes: 20,
      otpRequired: false,
    ),
    BranchDeliverySettings(
      branchId: SeedIds.zamalek,
      inMallEnabled: false,
      inMallFee: 0,
      inMallOverride: 'auto',
      inMallRequireLocation: true,
      outsideEnabled: false,
      outsideOverride: 'auto',
      umbrellaEnabled: false,
      umbrellaFee: 0,
      umbrellaOverride: 'auto',
      pickupEnabled: true,
      pickupOpenTime: '08:00:00',
      pickupCloseTime: '22:00:00',
      pickupFee: 0,
      pickupOverride: 'auto',
      prepTimeMinutes: 10,
      otpRequired: true,
    ),
  ];

  // ── bookings ───────────────────────────────────────────────────────────

  /// Sell's rows (`SellSeed.bookingSettings`), value for value: the app
  /// loads both seeds into one table, and this area's tests run without
  /// sell's. Every branch takes online bookings but Zamalek; only
  /// Heliopolis asks for a code, caps covers and has a blackout day.
  static final List<BookingSettings> bookingSettings = [
    for (final b in const ['heliopolis', 'maadi', 'new-cairo', 'zamalek'])
      BookingSettings(
        branchId: MockSeed.branchIdOf(b),
        enabled: b != 'zamalek',
        requireOtp: b == 'heliopolis',
        slotMinutes: b == 'new-cairo' ? 15 : 30,
        defaultDurationMinutes: 90,
        minParty: 1,
        maxParty: 8,
        leadTimeMinutes: 60,
        horizonDays: 30,
        holdMinutes: 30,
        autoNoShowMinutes: b == 'maadi' ? null : 20,
        reminderLeadMinutes: b == 'new-cairo' ? null : 120,
        maxCoversPerSlot: b == 'heliopolis' ? 16 : null,
        blackoutDates: b == 'heliopolis'
            ? const ['2026-10-31']
            : const <String>[],
        hours: [
          for (var dow = 0; dow < 7; dow++)
            // Friday opens after prayers and runs past midnight.
            dow == 5
                ? const HoursEntry(dow: 5, open: '13:00', close: '01:00')
                : HoursEntry(dow: dow, open: '09:00', close: '23:00'),
        ],
      ),
  ];

  // ── loyalty ────────────────────────────────────────────────────────────

  /// The org's stamp card (the core seed's members hold `visits_balance`
  /// 0–7): a drink on us at six stamps. Zamalek runs its own five-stamp
  /// card; every other branch inherits.
  static final List<LoyaltySettings> loyaltySettings = [
    LoyaltySettings(
      orgId: SeedIds.sabahOrg,
      enabled: true,
      programName: 'Sabah Stamps',
      programNameAr: 'طوابع صباح',
      mode: 'visits',
      earnPiastresPerPoint: 1000,
      earnOnDiscounted: true,
      earnIncludeTax: true,
      stampPerLineItem: false,
      defaultRewardCost: 6,
      rewardAnyItem: false,
      balanceCapEnabled: false,
      effectiveBalanceCap: 6,
      maxRewardsPerOrder: 1,
      requireOtp: true,
      birthdayEnabled: true,
      birthdayRewardAmount: 1,
      winbackEnabled: false,
      allowNegativeBalance: false,
      terms: 'One stamp per order. Six stamps buy any regular hot drink.',
      termsAr:
          'طابع واحد لكل طلب. ستة طوابع تساوي أي مشروب ساخن بالحجم العادي.',
      geofencedBranches: 2,
    ),
    LoyaltySettings(
      orgId: SeedIds.sabahOrg,
      branchId: SeedIds.zamalek,
      enabled: true,
      programName: 'Sabah Stamps — Zamalek',
      programNameAr: 'طوابع صباح — الزمالك',
      mode: 'visits',
      earnPiastresPerPoint: 1000,
      earnOnDiscounted: true,
      earnIncludeTax: true,
      stampPerLineItem: false,
      defaultRewardCost: 5,
      rewardAnyItem: false,
      balanceCapEnabled: false,
      effectiveBalanceCap: 5,
      maxRewardsPerOrder: 1,
      requireOtp: false,
      birthdayEnabled: false,
      winbackEnabled: false,
      allowNegativeBalance: false,
      terms: 'One stamp per order. Five stamps buy any regular hot drink.',
      geofencedBranches: 2,
    ),
  ];

  /// Seeds the tables above into [db] (each only when absent).
  static void loadInto(MockDb db) {
    seedTableIfAbsent(
      db,
      deliverySettingsTable,
      () => [for (final s in deliverySettings) s.toJson()],
    );
    seedTableIfAbsent(
      db,
      bookingSettingsTable,
      () => [for (final s in bookingSettings) s.toJson()],
    );
    seedTableIfAbsent(
      db,
      loyaltySettingsTable,
      () => [for (final s in loyaltySettings) s.toJson()],
    );
  }

  // ── the links page's modules ───────────────────────────────────────────

  /// Which links-page modules can show for [orgId], by the backend's rule
  /// (`orgs/links_page.rs` `availability`) over the current rows: "Order
  /// now" where any delivery channel is on, "Menu" at every active branch,
  /// "Rewards card" while the org's own programme runs, "Book a table"
  /// where bookings are switched on. Branch names in name order.
  static List<LinksModuleStatus> linksModules(MockDb db, String orgId) {
    final branches = db['branches'].query(
      filters: {'org_id': orgId, 'is_active': true},
      sort: 'name',
    );
    bool on(MockRow? r, String field) => r?[field] == true;
    final ordering = <String>[];
    final booking = <String>[];
    for (final b in branches) {
      final d = db[deliverySettingsTable].firstWhere(
        (r) => r['branch_id'] == b['id'],
      );
      if (on(d, 'pickup_enabled') ||
          on(d, 'outside_enabled') ||
          on(d, 'in_mall_enabled') ||
          on(d, 'umbrella_enabled')) {
        ordering.add(b['name']! as String);
      }
      final k = db[bookingSettingsTable].firstWhere(
        (r) => r['branch_id'] == b['id'],
      );
      if (on(k, 'enabled')) booking.add(b['name']! as String);
    }
    final programme = db[loyaltySettingsTable].firstWhere(
      (r) => r['org_id'] == orgId && r['branch_id'] == null,
    );
    LinksModuleStatus status(
      LinksItemKind kind,
      bool available, [
      List<String> names = const [],
    ]) => LinksModuleStatus(
      kind: kind,
      available: available,
      branchNames: names,
      path: modulePaths[kind.value]!,
    );
    return [
      status(LinksItemKind.order, ordering.isNotEmpty, ordering),
      status(LinksItemKind.menu, branches.isNotEmpty, [
        for (final b in branches) b['name']! as String,
      ]),
      status(LinksItemKind.rewards, on(programme, 'enabled')),
      status(LinksItemKind.book, booking.isNotEmpty, booking),
    ];
  }
}
