// Shared set-up for the customers unit's tests: the page through the real
// shell on the seeded mock server, a server whose `/authz/me` grants a chosen
// set of capabilities, and finders scoped to the page, the sheet and the
// dialog on top (the shell builds every sidebar row; pages share words).
import 'dart:async';
import 'dart:convert';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_sell/src/area_seed.dart';
import 'package:dashboard_sell/src/mock/customers_mock.dart';
import 'package:dashboard_sell/src/customers/customer_sheet.dart';
import 'package:dashboard_sell/src/customers/customers_page.dart';
import 'package:dashboard_sell/src/orders/order_sheet.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const String customersPath = '/customers';

/// The sell area with only this unit's page (and a blank `/bookings` for the
/// bookings link to land on): the other units' pages are not compiled in, so
/// a unit mid-edit elsewhere in the package cannot break these tests. Same
/// key, same supplements, same route as `sellArea`'s `/customers`.
const DashArea customersTestArea = DashArea(
  key: 'sell',
  routes: [
    DashRoute(
      path: '/customers',
      builder: CustomersPage.route,
      titleKey: 'customers.title',
      titleFallback: 'Customers',
      module: OrgModule.pos,
    ),
    DashRoute(
      path: '/bookings',
      builder: _blank,
      titleKey: 'bookings.title',
      titleFallback: 'Bookings',
      module: OrgModule.pos,
    ),
  ],
  i18nSupplements: [
    'packages/dashboard_sell/assets/i18n/en.json',
    'packages/dashboard_sell/assets/i18n/ar.json',
    'packages/dashboard_sell/assets/i18n/orders/en.json',
    'packages/dashboard_sell/assets/i18n/orders/ar.json',
    'packages/dashboard_sell/assets/i18n/bookings/en.json',
    'packages/dashboard_sell/assets/i18n/bookings/ar.json',
    'packages/dashboard_sell/assets/i18n/customers/en.json',
    'packages/dashboard_sell/assets/i18n/customers/ar.json',
  ],
);

Widget _blank(BuildContext context, GoRouterState state) =>
    const SizedBox.shrink();

/// Nada Kamal: the seed's first customer, a loyalty member with orders,
/// two saved addresses and a hand-made ledger row.
String get nadaId => MockSeed.customerId(0);

/// A seeded server with the core's handlers, the area seed and this unit's
/// handlers (which also answer the order sheet's read), for a test that
/// changes the data or the answers before the page opens. The other units'
/// handlers stay out: their pages are not visited here, and a unit mid-edit
/// elsewhere must not break these tests.
({MockServer server, MockDb db}) customersServer({
  Persona persona = Persona.owner,
}) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  loadSellSeed(db);
  registerCustomersMocks(server, db);
  return (server: server, db: db);
}

/// `/authz/me` grants exactly [caps] (the server's own checks still follow
/// the persona).
void grantOnly(MockServer server, List<String> caps, {Persona? persona}) {
  final p = persona ?? server.persona;
  server.on(
    'GET',
    '/authz/me',
    (req) => MockResponse.ok({
      'user_id': p.userId,
      'capabilities': caps,
      'everywhere': caps,
      'ask_manager': <String>[],
      'limits': <String, Object>{},
      'owner': false,
      'platform': false,
      'role_kinds': p.roleKinds,
      'epoch': 1,
      'spec_version': 2,
    }),
  );
}

/// The Customers page (or [path]) as [persona].
Future<DashHarness> pumpCustomers(
  WidgetTester tester, {
  String path = customersPath,
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  MockServer? server,
  MockDb? db,
}) {
  final s = server == null
      ? customersServer(persona: persona ?? Persona.owner)
      : null;
  return DashHarness.pump(
    tester,
    areas: const [customersTestArea],
    path: path,
    persona: persona,
    size: size,
    locale: locale,
    dark: dark,
    server: server ?? s!.server,
    db: db ?? s?.db,
    // A platform admin works inside Sabah Coffee (the org picker's choice).
    prefs: persona == Persona.platform
        ? {
            ScopePrefKeys.org: jsonEncode({'id': SeedIds.sabahOrg}),
          }
        : null,
  );
}

/// [f] inside the Customers page (not the sidebar, header or a sheet).
Finder inPage(Finder f) =>
    find.descendant(of: find.byType(CustomersPage), matching: f);

/// [f] inside the open customer sheet.
Finder inSheet(Finder f) =>
    find.descendant(of: find.byType(CustomerSheet), matching: f);

/// [f] inside the top-most dialog / surface (the last [DashSurface]).
Finder inDialog(Finder f) =>
    find.descendant(of: find.byType(DashSurface).last, matching: f);

/// [text] on the page.
Finder pageText(String text) => inPage(find.text(text));

/// [text] in the sheet.
Finder sheetText(String text) => inSheet(find.text(text));

/// Text widgets whose text contains [s] (spans included).
Finder textHas(String s) => find.textContaining(s, findRichText: true);

/// The table row (or phone card) a screen reader calls [name].
Finder rowOf(String name) => inPage(
  find.byWidgetPredicate((w) => w is DashPressable && w.semanticLabel == name),
);

/// Whether [name]'s row is the selected (open) one.
bool rowSelected(WidgetTester tester, String name) =>
    tester.widget<DashPressable>(rowOf(name)).selected ?? false;

/// The list reads made so far (`GET /customers`).
List<MockCall> listCalls(DashHarness h) =>
    h.server.callsTo('/customers', method: 'GET');

/// The query of [call] as single values.
Map<String, String> q1(MockCall call) => {
  for (final e in call.query.entries) e.key: e.value.single,
};

/// The option [text] in an open select's list (a popover or a sheet).
Finder optionText(String text) => find.descendant(
  of: find.byWidgetPredicate((w) => w is DashOptionList),
  matching: find.text(text),
);

/// The [DashButton] labelled [label] on the page.
Finder pageButton(String label) =>
    inPage(find.byWidgetPredicate((w) => w is DashButton && w.label == label));

/// Opens [id]'s sheet the way a customer link does (or the page, when
/// [readOnly] is false), from whatever page is showing.
Future<void> openSheet(
  DashHarness h,
  String id, {
  bool readOnly = false,
}) async {
  final page = find.byType(CustomersPage);
  final at = page.evaluate().isNotEmpty ? page : find.byType(Restricted);
  final context = h.tester.element(at);
  unawaited(
    showCustomerSheet(
      context,
      customerId: id,
      readOnly: readOnly,
      onOpenOrder: (o) => showOrderSheet(context, orderId: o),
    ),
  );
  await h.settle();
}

/// Opens Nada's sheet from the list and settles.
Future<void> openNada(DashHarness h) => h.tap(rowOf('Nada Kamal'));

/// The seed customer named [name].
MockRow customerNamed(MockDb db, String name) =>
    db['customers'].rows.firstWhere((c) => c['name'] == name);

/// The customers in the list's order (most recent visit first).
List<MockRow> listOrder(MockDb db) {
  String seen(MockRow c) => (c['last_order_at'] ?? c['created_at'])! as String;
  return [...db['customers'].rows]..sort((a, b) {
    final d = DateTime.parse(seen(b)).compareTo(DateTime.parse(seen(a)));
    return d != 0 ? d : (a['id']! as String).compareTo(b['id']! as String);
  });
}

/// The first customer of the first list window matching [test] whose name
/// nobody else has (random seed names repeat).
MockRow firstShown(MockDb db, bool Function(MockRow c) test) {
  final names = <Object?, int>{};
  for (final c in db['customers'].rows) {
    names[c['name']] = (names[c['name']] ?? 0) + 1;
  }
  return listOrder(
    db,
  ).take(50).firstWhere((c) => names[c['name']] == 1 && test(c));
}

/// The first non-member on screen, with a name nobody else has.
MockRow nonMember(MockDb db) => firstShown(db, (c) => c['is_member'] != true);
