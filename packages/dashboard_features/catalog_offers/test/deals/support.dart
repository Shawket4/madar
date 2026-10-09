// Shared set-up for the Deals unit's tests: the real app shell with the
// `/menu/deals` route exactly as `catalogOffersRoutes` declares it, on the
// seeded mock server (core seed + the area seed + the shared menu reads +
// this unit's handlers), and finders scoped to the page and its dialog.
import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart' show DealRule;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_offers/dashboard_catalog_offers.dart';
import 'package:dashboard_catalog_offers/src/area_seed.dart';
import 'package:dashboard_catalog_offers/src/deals/deal_dialog.dart';
import 'package:dashboard_catalog_offers/src/deals/deals_page.dart';
import 'package:dashboard_catalog_offers/src/mock/deals_mock.dart';
import 'package:dashboard_catalog_offers/src/mock/shared_mocks.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

export 'package:dashboard_core/testing.dart' show DashHarness, DashSize;

const String dealsPath = '/menu/deals';
const String listRoute = '/deals';
const String itemRoute = '/deals/{id}';
const String branchRoute = '/deals/{id}/branches/{branchId}';

/// The seeded deals' ids by key.
String dealId(String key) => OffersSeed.dealId(key);

/// The seeded deals in the list's order (by `sort`).
const List<String> seededNames = [
  'Any 2 pastries for 150',
  'Buy 2 coffees, get a cookie free',
  'Second iced latte half price',
  'Juice trio for 270',
  'Weekend breakfast pair for 330',
];

/// The area seed, the shared menu reads and this unit's handlers.
void registerDealsArea(MockServer server, MockDb db) {
  OffersSeed.loadInto(db);
  registerOffersSharedMocks(server, db);
  registerDealsMocks(server, db);
}

/// The offers area with only `/menu/deals` (the real route entry) and its
/// handlers, so these tests stand on their own while the area's other units
/// are built beside them.
final DashArea dealsArea = DashArea(
  key: 'catalog_offers',
  routes: [
    for (final r in catalogOffersRoutes)
      if (r.path == dealsPath) r,
  ],
  registerMocks: registerDealsArea,
  i18nSupplements: const [
    'packages/dashboard_catalog_offers/assets/i18n/en.json',
    'packages/dashboard_catalog_offers/assets/i18n/ar.json',
    'packages/dashboard_catalog_offers/assets/i18n/deals.en.json',
    'packages/dashboard_catalog_offers/assets/i18n/deals.ar.json',
  ],
);

/// A seeded server ([persona] signs in); edit [db] before pumping.
({MockServer server, MockDb db}) dealsServer({
  Persona persona = Persona.owner,
}) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  registerDealsArea(server, db);
  return (server: server, db: db);
}

/// A seeded server where `/authz/me` grants exactly [caps] to [persona]
/// (the server's own checks still follow the persona).
({MockServer server, MockDb db}) serverWithCaps(
  List<String> caps, {
  Persona persona = Persona.limited,
}) {
  final s = dealsServer(persona: persona);
  s.server.on(
    'GET',
    '/authz/me',
    (req) => MockResponse.ok({
      'user_id': persona.userId,
      'capabilities': caps,
      'everywhere': caps,
      'ask_manager': <String>[],
      'limits': <String, Object>{},
      'owner': false,
      'platform': false,
      'role_kinds': persona.roleKinds,
      'epoch': 1,
      'spec_version': 2,
    }),
  );
  return s;
}

/// The deals page at [path] (default `/menu/deals`), with [branch] in scope
/// when given (the realtime stream follows the scope's branch).
Future<DashHarness> pumpDeals(
  WidgetTester tester, {
  String path = dealsPath,
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  MockServer? server,
  MockDb? db,
  String? branch,
}) => DashHarness.pump(
  tester,
  areas: [dealsArea],
  path: path,
  persona: persona,
  size: size,
  locale: locale,
  dark: dark,
  server: server,
  db: db,
  prefs: {
    if (branch != null)
      ScopePrefKeys.branch: jsonEncode({
        'org': SeedIds.sabahOrg,
        'branch': branch,
      }),
  },
);

/// The page.
Finder get page => find.byType(DealsPage);

/// The open dialog (or full-screen sheet).
Finder get dialog => find.byType(DealDialog);

/// [matching] inside the page.
Finder inPage(Finder matching) => find.descendant(of: page, matching: matching);

/// [matching] inside the dialog.
Finder inDialog(Finder matching) =>
    find.descendant(of: dialog, matching: matching);

/// The table (or the phone cards).
Finder get table => find.byType(DashDataTable<DealRule>);

/// [matching] inside the table.
Finder inTable(Finder matching) =>
    find.descendant(of: table, matching: matching);

/// The table row (or phone card) that shows [name].
Finder rowOf(String name) => find
    .ancestor(
      of: inTable(find.text(name)),
      matching: find.byType(DashPressable),
    )
    .first;

/// [matching] inside the row showing [name].
Finder inRow(String name, Finder matching) =>
    find.descendant(of: rowOf(name), matching: matching);

/// What a screen reader calls [label], inside the dialog.
Finder labelled(String label) => inDialog(find.bySemanticsLabel(label));

/// A select's trigger in the dialog (a screen reader reads "label: value").
Finder labelledSelect(String label) =>
    inDialog(find.bySemanticsLabel(RegExp('^${RegExp.escape(label)}: ')));

/// The dialog's switch a screen reader calls [label].
Finder switchOf(String label) => inDialog(
  find.byWidgetPredicate((w) => w is DashSwitch && w.semanticLabel == label),
);

/// The confirm dialog.
Finder get confirm => find.byType(DashConfirmDialog);

/// Types [text] into the dialog's field a screen reader calls [label].
Future<void> typeInto(
  DashHarness h,
  String label,
  String text, {
  int index = 0,
}) async {
  final field = labelled(label).at(index);
  await h.tester.ensureVisible(field);
  await h.enterText(field, text);
}

/// The open option list.
Finder get optionList => find.byWidgetPredicate((w) => w is DashOptionList);

/// Opens the [index]th dialog select called [label] and picks [text]
/// ([search] typed first when the list has a search box).
Future<void> choose(
  DashHarness h,
  String label,
  String text, {
  int index = 0,
  String? search,
}) async {
  final trigger = labelledSelect(label).at(index);
  await h.tester.ensureVisible(trigger);
  await h.tap(trigger);
  if (search != null) {
    await h.enterText(
      find.descendant(of: optionList, matching: find.byType(EditableText)),
      search,
    );
  }
  await h.tap(find.descendant(of: optionList, matching: find.text(text)).last);
}

/// Taps [text] inside the dialog (scrolled into view first).
Future<void> tapInDialog(DashHarness h, String text) async {
  final f = inDialog(find.text(text)).first;
  await h.tester.ensureVisible(f);
  await h.tester.pump();
  await h.tap(f);
}

/// The calls made to [template] with [method].
List<MockCall> callsTo(DashHarness h, String method, String template) =>
    h.server.callsTo(template, method: method);

/// Every JSON body sent to [template] with [method].
List<Map<String, Object?>> bodiesTo(
  DashHarness h,
  String method,
  String template,
) => [
  for (final c in h.server.callsTo(template, method: method))
    (c.body! as Map).cast<String, Object?>(),
];

/// Adds [n] more N-for-price deals to Sabah ("Promo deal 01"…, after the
/// seeded five), so the list runs to a second page.
void addPromoDeals(MockDb db, int n) {
  for (var i = 1; i <= n; i++) {
    final name = 'Promo deal ${i.toString().padLeft(2, '0')}';
    db.table(OffersTables.deals).insert({
      'id': mockUuid('deal:promo-$i'),
      'name': name,
      'name_translations': {'en': name, 'ar': 'عرض ترويجي $i'},
      'kind': 'n_for_price',
      'qty': 2,
      'price': 10000 + i * 100,
      'get_qty': null,
      'get_percent': null,
      'max_per_order': null,
      'is_active': true,
      'sort': 10 + i,
      'pool': [
        {
          'menu_item_id': null,
          'category_id': OffersSeed.category('bakery'),
          'size_label': null,
        },
      ],
      'reward_pool': <Object?>[],
      'windows': <Object?>[],
      'branch_overrides': <Object?>[],
      'created_at': '2026-08-01T09:00:00.000Z',
      'updated_at': '2026-08-01T09:00:00.000Z',
    }, timestamps: false);
  }
}
