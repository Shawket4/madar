// Shared set-up for the overview's tests: the real app shell with only this
// area, on the seeded mock server.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_overview/dashboard_overview.dart';
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

/// Text widgets whose text contains [s] (spans included).
Finder textHas(String s) => find.textContaining(s, findRichText: true);
