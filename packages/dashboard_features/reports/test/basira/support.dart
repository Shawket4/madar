// Shared set-up for the Basira tests: the real app shell with only the
// Basira route and its mocks (so these tests do not depend on the other
// reports units' files), on the seeded mock server.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_reports/src/basira/basira_page.dart';
import 'package:dashboard_reports/src/mock/basira_mock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const String basiraPath = '/basira';

/// The endpoint templates the page calls.
const String listRoute = '/ai/conversations';
const String convRoute = '/ai/conversations/{id}';
const String streamRoute = '/ai/chat/stream';

/// The reports area with only Basira, its route exactly as routes.dart
/// declares it (no page gate; pos module).
const DashArea basiraArea = DashArea(
  key: 'reports',
  routes: [
    DashRoute(
      path: basiraPath,
      builder: basiraPageBuilder,
      titleKey: 'basira.title',
      titleFallback: 'Basira',
      module: OrgModule.pos,
    ),
  ],
  registerMocks: registerBasiraMocks,
  i18nSupplements: [
    'packages/dashboard_reports/assets/i18n/en.json',
    'packages/dashboard_reports/assets/i18n/ar.json',
    'packages/dashboard_reports/assets/i18n/basira.en.json',
    'packages/dashboard_reports/assets/i18n/basira.ar.json',
  ],
);

/// A seeded server with the core's and Basira's handlers, for a test that
/// steers the answers before the page opens.
({MockServer server, MockDb db}) basiraServer({
  Persona persona = Persona.owner,
}) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  registerBasiraMocks(server, db);
  return (server: server, db: db);
}

/// Opens Basira (or [path]) as [persona].
Future<DashHarness> pumpBasira(
  WidgetTester tester, {
  String path = basiraPath,
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  MockServer? server,
  MockDb? db,
  String? branchId,
  bool reducedMotion = true,
}) => DashHarness.pump(
  tester,
  areas: const [basiraArea],
  path: path,
  persona: persona,
  size: size,
  locale: locale,
  dark: dark,
  server: server,
  db: db,
  reducedMotion: reducedMotion,
  prefs: {
    if (branchId != null)
      ScopePrefKeys.branch:
          '{"org":"${SeedIds.sabahOrg}","branch":"$branchId"}',
  },
);

/// The Basira mock behind [h].
BasiraMock mockOf(DashHarness h) => basiraMockOf(h.server);

/// The page under test.
Finder get basiraPage => find.byType(BasiraPage);

/// [f] inside the page (the shell shares words with it).
Finder inPage(Finder f) => find.descendant(of: basiraPage, matching: f);

/// The text [s] inside the page.
Finder pageText(String s) => inPage(find.text(s));

/// The rail, pinned or in the slide-over.
Finder get rail => find.byType(BasiraConversationList);

/// [f] inside the rail.
Finder inRail(Finder f) => find.descendant(of: rail, matching: f);

/// The composer's text box.
Finder get composer => inPage(find.byType(EditableText)).last;

/// Types [text] and taps Send.
Future<void> askByTyping(DashHarness h, String text) async {
  await h.enterText(composer, text);
  await h.tap(inPage(find.bySemanticsLabel(h.t('basira.send'))));
}

/// The stream calls, in order.
List<MockCall> streams(DashHarness h) =>
    h.server.callsTo(streamRoute, method: 'POST');

/// [f] inside the transcript.
Finder inTranscript(Finder f) =>
    find.descendant(of: find.byKey(BasiraPage.transcriptKey), matching: f);
