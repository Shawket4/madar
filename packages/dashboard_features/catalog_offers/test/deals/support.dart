// Shared set-up for the deals tests: the page through the real shell on the
// mock server, a server whose `/authz/me` grants a chosen set of
// capabilities, and finders for what a screen reader names.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_offers/dashboard_catalog_offers.dart';
import 'package:dashboard_catalog_offers/src/area_seed.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const String dealsPath = '/menu/deals';

/// The seeded deals' ids by key.
String dealId(String key) => OffersSeed.dealId(key);

/// A seeded server where `/authz/me` grants exactly [caps] to [persona]
/// (the server's own checks still follow the persona).
({MockServer server, MockDb db}) serverWithCaps(
  List<String> caps, {
  Persona persona = Persona.limited,
}) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  catalogOffersArea.registerMocks!(server, db);
  server.on(
    'GET',
    '/authz/me',
    (req) => MockResponse.ok({
      'user_id': persona.userId,
      'capabilities': caps,
      'ask_manager': <String>[],
      'limits': <String, Object>{},
      'owner': false,
      'platform': false,
      'role_kinds': persona.roleKinds,
      'epoch': 1,
      'spec_version': 2,
    }),
  );
  return (server: server, db: db);
}

/// The deals page at [path] (default `/menu/deals`).
Future<DashHarness> pumpDeals(
  WidgetTester tester, {
  String path = dealsPath,
  Persona persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  MockServer? server,
  MockDb? db,
}) => DashHarness.pump(
  tester,
  areas: const [catalogOffersArea],
  path: path,
  persona: persona,
  size: size,
  locale: locale,
  dark: dark,
  server: server,
  db: db,
);

/// What a screen reader calls [label] (exactly).
Finder labelled(String label) => find.bySemanticsLabel(label);

/// What a screen reader calls [label] or "[label]: …" (a select's trigger).
Finder labelledSelect(String label) =>
    find.bySemanticsLabel(RegExp('^${RegExp.escape(label)}(: .*)?\$'));

/// The [DealsPage]'s dialog surface, when one is up.
Finder get dialogTitleEdit => find.text('Edit deal');

/// The calls made to [template] with [method].
List<MockCall> callsTo(DashHarness h, String method, String template) =>
    h.server.callsTo(template, method: method);

/// Every text widget's string under [of].
List<String> textsIn(Finder of) => [
  for (final e in find
      .descendant(of: of, matching: find.byType(Text))
      .evaluate())
    (e.widget as Text).data ?? (e.widget as Text).textSpan?.toPlainText() ?? '',
];
