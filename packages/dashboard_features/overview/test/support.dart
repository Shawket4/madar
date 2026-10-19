// Shared set-up for the overview's tests: the real app shell with only this
// area, on the seeded mock server.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_overview/dashboard_overview.dart';
import 'package:dashboard_overview/src/home/home_page.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opens [path] (the home by default) as [persona].
Future<DashHarness> pumpHome(
  WidgetTester tester, {
  String path = '/',
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  MockServer? server,
  MockDb? db,
  Map<String, String>? prefs,
  bool reducedMotion = true,
}) => DashHarness.pump(
  tester,
  areas: const [overviewArea],
  path: path,
  persona: persona,
  size: size,
  locale: locale,
  dark: dark,
  server: server,
  db: db,
  prefs: prefs,
  reducedMotion: reducedMotion,
);

/// A seeded server with the core's and this area's handlers, for a test that
/// changes the data or the answers before the page opens.
({MockServer server, MockDb db}) homeServer({Persona persona = Persona.owner}) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  registerOverviewMocks(server, db);
  return (server: server, db: db);
}

/// [homeServer] with Sabah's payment methods gone: the payment check blocks
/// at every branch, so the Setup card shows.
({MockServer server, MockDb db}) unfinishedServer({
  Persona persona = Persona.owner,
}) {
  final s = homeServer(persona: persona);
  s.db['payment_methods'].removeWhere((r) => r['org_id'] == SeedIds.sabahOrg);
  return s;
}

/// Text widgets whose text contains [s] (spans included).
Finder textHas(String s) => find.textContaining(s, findRichText: true);

/// [f] inside the home page only: the shell builds every sidebar row and
/// the header repeats words ("All branches", "Dashboard"), so a finder that
/// is about the page is scoped to it.
Finder inHome(Finder f) =>
    find.descendant(of: find.byType(HomePage), matching: f);

/// [text] on the home page (not in the sidebar or the header).
Finder homeText(String text, {bool findRichText = false}) =>
    inHome(find.text(text, findRichText: findRichText));

/// Text on the home page containing [s] (spans included).
Finder homeHas(Pattern s, {bool findRichText = true}) =>
    inHome(find.textContaining(s, findRichText: findRichText));
