// Shared set-up for the Branch setup tests: the real app shell on the seeded
// mock server, with the admin area's Branch setup route (wired exactly as
// `lib/src/routes.dart` wires it), the area's supplements, the area seed, the
// Devices mocks and the branch-plan mocks (registered after them, as in
// `register.dart`).
import 'package:dashboard_admin/src/area_seed.dart';
import 'package:dashboard_admin/src/branch_setup/branch_setup_page.dart';
import 'package:dashboard_admin/src/branch_setup/builder_canvas.dart';
import 'package:dashboard_admin/src/branch_setup/inspector.dart'
    show builderErrorText;
import 'package:dashboard_admin/src/mock/branch_setup_mock.dart';
import 'package:dashboard_admin/src/mock/devices_mock.dart';
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

export 'package:dashboard_admin/src/mock/branch_setup_mock.dart'
    show
        BranchPlanRoutes,
        BranchPlanSeed,
        BranchPlanTables,
        BranchPlanRefusals,
        activateSlotCode;

Widget _page(BuildContext context, GoRouterState state) =>
    const BranchSetupPage();

/// How many times the stand-in Item routing page's read ran: the link warms
/// it on intent, so opening the page reads nothing more.
int routingReads = 0;

final _routingRead = FutureProvider.autoDispose<int>((ref) async {
  ref.webCache();
  return ++routingReads;
});

Widget _routing(BuildContext context, GoRouterState state) => Consumer(
  builder: (context, ref, _) {
    ref.watch(_routingRead);
    return const SizedBox.shrink(key: ValueKey('kitchen-routing-page'));
  },
);

void _warmRouting(DashPrefetcher warm, Scope scope) => warm(_routingRead);

void _mocks(MockServer server, MockDb db) {
  loadAdminSeed(db);
  registerDevicesMocks(server, db);
  registerBranchSetupMocks(server, db);
}

const DashArea branchSetupArea = DashArea(
  key: 'admin',
  routes: [
    DashRoute(
      path: BranchSetupPage.path,
      builder: _page,
      titleKey: 'nav.branchSetup',
      titleFallback: 'Branch setup',
      module: OrgModule.pos,
    ),
    // Stands in for the setup area's page the "Item routing" link opens.
    DashRoute(
      path: '/settings/kitchen-routing',
      builder: _routing,
      prefetch: _warmRouting,
    ),
  ],
  registerMocks: _mocks,
  i18nSupplements: [
    'packages/dashboard_admin/assets/i18n/en.json',
    'packages/dashboard_admin/assets/i18n/ar.json',
    'packages/dashboard_admin/assets/i18n/branch_setup.en.json',
    'packages/dashboard_admin/assets/i18n/branch_setup.ar.json',
  ],
);

String atBranch(String branchId) => '?branchId=$branchId';

/// A seeded server with the core's handlers, the area seed and these mocks.
class PlanBackend {
  PlanBackend({Persona persona = Persona.owner}) {
    db = MockDb.seeded();
    server = MockServer(persona: persona, clock: db.clock);
    registerCoreMocks(server, db);
    _mocks(server, db);
  }

  late final MockDb db;
  late final MockServer server;

  DashboardApi get api => DashboardApi(server);
  MockTable table(String name) => db[name];
  MockTable get codes => db[AdminTables.activationCodes];
}

/// Opens `/branch-setup` (+ [query]) as [persona].
Future<DashHarness> pumpBuilder(
  WidgetTester tester, {
  String? branchId,
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  PlanBackend? backend,
}) => DashHarness.pump(
  tester,
  areas: const [branchSetupArea],
  path: '/branch-setup${branchId == null ? '' : atBranch(branchId)}',
  persona: persona,
  size: size,
  locale: locale,
  dark: dark,
  server: backend?.server,
  db: backend?.db,
);

/// Within the page (the shell repeats words in its sidebar and header).
Finder inPage(Finder f) =>
    find.descendant(of: find.byType(BranchSetupPage), matching: f);

Finder pageText(String text) => inPage(find.text(text));

/// [text] where a tap would land (a dialog, a menu).
Finder top(String text) => find.text(text).hitTestable();

/// The card of the piece [key] (`device:<id>`, …).
Finder card(String key) => find.byKey(ValueKey('bb-card-$key'));

/// The card whose title is [title].
Finder cardTitled(String title) =>
    find.byWidgetPredicate((w) => w is BuilderCard && w.piece.title == title);

/// The card's [PieceView].
PieceView pieceOf(WidgetTester tester, Finder cardFinder) =>
    tester.widget<BuilderCard>(cardFinder).piece;

/// The inspector.
Finder inInspector(Finder f) => find.descendant(
  of: find.byKey(const ValueKey('bb-inspector')),
  matching: f,
);

/// The last PUT body.
Map<String, Object?> lastSave(MockServer s) =>
    (s.callsTo(BranchPlanRoutes.plan, method: 'PUT').last.body! as Map)
        .cast<String, Object?>();

/// The words the page shows for a refusal: the transport's message
/// (`h.refusalWords`) through the builder's `getErrorMessage` rule.
String refusalText(DashHarness h, MockResponse response) {
  final e = MockServer.toApiException(response);
  return builderErrorText(
    ApiException(
      status: e.status,
      code: e.code,
      message: h.refusalWords(response),
      details: e.details,
    ),
    h.container.read(tProvider),
  );
}

/// The prefixes every invalidation on the realtime bus named, in order.
List<List<String>> watchInvalidations(DashHarness h) {
  final seen = <List<String>>[];
  final sub = h.container
      .read(realtimeBusProvider)
      .invalidations
      .listen(seen.add);
  addTearDown(sub.cancel);
  return seen;
}
