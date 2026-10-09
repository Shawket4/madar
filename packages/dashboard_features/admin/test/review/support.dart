// Shared set-up for the Review tests: the real app shell with the Review
// page, on the seeded mock server (core seed + admin seed + this unit's
// handlers). The area holds only `/access/review`, so the tests run on their
// own while the other admin units are built in parallel; the page and its
// handlers are exactly the ones `adminArea` wires in.
import 'package:dashboard_admin/src/area_seed.dart';
import 'package:dashboard_admin/src/mock/review_mock.dart';
import 'package:dashboard_admin/src/orgs/org_errors.dart';
import 'package:dashboard_admin/src/review/review_page.dart';
import 'package:dashboard_api/dashboard_api.dart'
    show ApiException, MyAuthz, ReplayFlag;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

export 'package:dashboard_core/testing.dart' show DashHarness, DashSize;

const reviewPath = '/access/review';
const flagsRoute = '/authz/flags';
const reviewRoute = '/authz/flags/{id}/review';
const bulkRoute = '/authz/flags/bulk-review';

Widget _review(BuildContext context, GoRouterState state) => const ReviewPage();

void registerReviewArea(MockServer server, MockDb db) {
  loadAdminSeed(db);
  registerReviewMocks(server, db);
}

/// The admin area with only `/access/review`, as `adminRoutes` declares it.
const DashArea reviewArea = DashArea(
  key: 'admin',
  routes: [
    DashRoute(
      path: ReviewPage.path,
      builder: _review,
      titleKey: 'access.review.title',
      titleFallback: 'Review',
    ),
  ],
  registerMocks: registerReviewArea,
  i18nSupplements: [
    'packages/dashboard_admin/assets/i18n/en.json',
    'packages/dashboard_admin/assets/i18n/ar.json',
    'packages/dashboard_admin/assets/i18n/review.en.json',
    'packages/dashboard_admin/assets/i18n/review.ar.json',
  ],
);

Future<DashHarness> pumpReview(
  WidgetTester tester, {
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  MockServer? server,
  MockDb? db,
}) => DashHarness.pump(
  tester,
  areas: const [reviewArea],
  path: reviewPath,
  persona: persona,
  size: size,
  locale: locale,
  dark: dark,
  server: server,
  db: db,
);

/// A seeded server, for a test that changes the data or the answers first.
({MockServer server, MockDb db}) reviewServer({
  Persona persona = Persona.owner,
}) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  registerReviewArea(server, db);
  return (server: server, db: db);
}

/// The seeded flag rows.
MockTable flagRows(MockDb db) => db[AdminTables.flags];

/// [n] more open flags (ids 101…), newest after the seed's.
void addFlags(MockDb db, int n) => flagRows(db).insertAll([
  for (var i = 0; i < n; i++)
    ReplayFlag(
      id: 101 + i,
      authorId: SeedIds.user('hana'),
      authorName: 'Teller ${101 + i}',
      op: 'VoidOrder',
      capability: 'orders.void',
      reason: 'unauthorized_offline',
      occurredAt: db.clock.now.subtract(Duration(minutes: 10 + i)),
      createdAt: db.clock.now.subtract(Duration(minutes: 5 + i)),
    ).toJson(),
]);

/// The owner's permissions minus [without], while the server still answers
/// as the owner (a person whose grants changed after the list loaded).
void signedInWithout(MockServer server, Set<String> without) {
  server.on('GET', '/authz/me', (req) {
    final caps = [
      for (final c in Persona.owner.capabilities)
        if (!without.contains(c)) c,
    ]..sort();
    return MockResponse.ok(
      MyAuthz(
        userId: SeedIds.owner,
        capabilities: caps,
        everywhere: caps,
        askManager: const [],
        limits: const {},
        owner: false,
        platform: false,
        roleKinds: const ['org_admin'],
        epoch: 1,
        specVersion: 2,
      ),
    );
  });
}

/// The words this unit shows for a refusal (`h.refusalWords` through the
/// area's `getErrorMessage` rule).
String shown(DashHarness h, MockResponse response) {
  final e = MockServer.toApiException(response);
  return orgErrorWords(
    ApiException(
      status: e.status,
      code: e.code,
      message: h.refusalWords(response),
      details: e.details,
    ),
    h.container.read(tProvider),
  );
}

/// The Review page.
Finder get page => find.byType(ReviewPage);

/// [text] on the page (not the sidebar).
Finder onPage(String text) =>
    find.descendant(of: page, matching: find.text(text));

Finder pick(int id) => find.byKey(ValueKey('review-pick-$id'));
Finder mark(int id) => find.byKey(ValueKey('review-mark-$id'));
Finder get selectAll => find.byKey(const ValueKey('review-select-all'));
Finder get bulkBar => find.byKey(const ValueKey('review-bulk-bar'));
Finder get bulkNote => find.byKey(const ValueKey('review-bulk-note'));
Finder get bulkResolve => find.byKey(const ValueKey('review-bulk-resolve'));
Finder get showReviewed => find.byKey(const ValueKey('review-show-reviewed'));

/// The GET /authz/flags calls so far.
List<MockCall> flagReads(DashHarness h) => h.server.callsTo(flagsRoute);
