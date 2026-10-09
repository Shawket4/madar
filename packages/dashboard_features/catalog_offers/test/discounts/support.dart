// Shared set-up for the Discounts unit's tests: the real app shell with the
// `/discounts` route exactly as `catalogOffersRoutes` declares it (prefetch
// included), on the seeded mock server (core seed + the area seed + this
// unit's handlers), and finders scoped to the page and its dialog.
import 'package:dashboard_api/dashboard_api.dart' show Discount;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_offers/dashboard_catalog_offers.dart';
import 'package:dashboard_catalog_offers/src/area_seed.dart';
import 'package:dashboard_catalog_offers/src/discounts/discount_dialog.dart';
import 'package:dashboard_catalog_offers/src/discounts/discounts_data.dart';
import 'package:dashboard_catalog_offers/src/discounts/discounts_page.dart';
import 'package:dashboard_catalog_offers/src/mock/discounts_mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter_test/flutter_test.dart';

export 'package:dashboard_core/testing.dart' show DashHarness, DashSize;

const String discountsPath = '/discounts';
const String listRoute = '/discounts';
const String itemRoute = '/discounts/{id}';

/// A seeded discount's id by its seed key (`staff-meal`).
String discountId(String key) => OffersSeed.discountId(key);

/// The area seed and this unit's handlers.
void registerDiscountsArea(MockServer server, MockDb db) {
  OffersSeed.loadInto(db);
  registerDiscountsMocks(server, db);
}

/// The offers area with only `/discounts` (the real route entry) and its
/// handlers, so these tests stand on their own while the area's other units
/// are built beside them.
final DashArea discountsArea = DashArea(
  key: 'catalog_offers',
  routes: [
    for (final r in catalogOffersRoutes)
      if (r.path == discountsPath) r,
  ],
  registerMocks: registerDiscountsArea,
  i18nSupplements: const [
    'packages/dashboard_catalog_offers/assets/i18n/en.json',
    'packages/dashboard_catalog_offers/assets/i18n/ar.json',
    'packages/dashboard_catalog_offers/assets/i18n/discounts.en.json',
    'packages/dashboard_catalog_offers/assets/i18n/discounts.ar.json',
  ],
);

/// A seeded server ([persona] signs in); edit [db] before pumping.
({MockServer server, MockDb db}) discountsServer({
  Persona persona = Persona.owner,
}) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  registerDiscountsArea(server, db);
  return (server: server, db: db);
}

/// Opens [path] (the Discounts page by default) as [persona].
Future<DashHarness> pumpDiscounts(
  WidgetTester tester, {
  String path = discountsPath,
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  MockServer? server,
  MockDb? db,
}) => DashHarness.pump(
  tester,
  areas: [discountsArea],
  path: path,
  persona: persona,
  size: size,
  locale: locale,
  dark: dark,
  server: server,
  db: db,
);

/// The page.
Finder get page => find.byType(DiscountsPage);

/// The open dialog (or full-screen sheet).
Finder get dialog => find.byType(DiscountDialog);

/// [matching] inside the page.
Finder inPage(Finder matching) => find.descendant(of: page, matching: matching);

/// [matching] inside the dialog.
Finder inDialog(Finder matching) =>
    find.descendant(of: dialog, matching: matching);

/// The table (or the phone cards).
Finder get table => find.byType(DashDataTable<Discount>);

/// [matching] inside the table.
Finder inTable(Finder matching) =>
    find.descendant(of: table, matching: matching);

/// What a screen reader calls [label], inside [of] (the page by default).
Finder labelled(String label, {Finder? of}) =>
    find.descendant(of: of ?? page, matching: find.bySemanticsLabel(label));

/// The text box a screen reader calls [label] in the dialog.
Finder dialogField(String label) =>
    find.descendant(of: dialog, matching: find.bySemanticsLabel(label));

/// The seeded discounts in the server's order (by name).
const List<String> seededNames = [
  'Corporate: Vodafone',
  'Late Order Apology',
  'Loyalty Welcome',
  'Manager Comp',
  'Opening Week',
  'Staff Meal',
  'Student Discount',
];

/// Adds [n] more percentage discounts to the org ("Promo 01"…), so the list
/// runs to a second page.
void addPromos(MockDb db, int n) {
  for (var i = 1; i <= n; i++) {
    final name = 'Promo ${i.toString().padLeft(2, '0')}';
    db.table(OffersTables.discounts).insert({
      'id': mockUuid('discount:promo-$i'),
      'org_id': SeedIds.sabahOrg,
      'name': name,
      'name_translations': {'en': name, 'ar': 'عرض $i'},
      'dtype': 'percentage',
      'value': 5,
      'value_rate': 0.05,
      'is_active': true,
    });
  }
}

/// What the page shows for [response]: its envelope read as the app reads
/// it, worded by the page's own rule (`getErrorMessage`).
String refusalText(DashHarness h, MockResponse response) => discountErrorText(
  MockServer.toApiException(response),
  h.container.read(tProvider),
);
