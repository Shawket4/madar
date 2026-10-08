// Shared set-up for the Branches unit's tests: the real app shell with the
// Branches page, on the seeded mock server (core seed + admin seed + the
// unit's handlers).
//
// The tests mount an area holding only `/branches` (and its mocks) so they
// compile and run on their own while the other admin units are being built
// in parallel; the page, its dialog and its handlers are exactly the ones
// `adminArea` wires in (`lib/src/routes.dart`, `lib/src/mock/register.dart`).
import 'package:dashboard_admin/src/area_seed.dart';
import 'package:dashboard_admin/src/branches/branches_page.dart';
import 'package:dashboard_admin/src/mock/branches_mock.dart';
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

export 'package:dashboard_core/testing.dart' show DashHarness, DashSize;

const branchesPath = '/branches';
const listRoute = '/branches';
const itemRoute = '/branches/{id}';
const timezonesRoute = '/timezones';

Widget _branches(BuildContext context, GoRouterState state) =>
    const BranchesPage();

/// The admin area's handlers this page needs: the area seed (the other
/// organizations, their branches) and the Branches handlers.
void registerBranchesArea(MockServer server, MockDb db) {
  loadAdminSeed(db);
  registerBranchesMocks(server, db);
}

/// The admin area with only `/branches`, as `adminRoutes` declares it.
const DashArea branchesArea = DashArea(
  key: 'admin',
  routes: [
    DashRoute(
      path: BranchesPage.path,
      builder: _branches,
      titleKey: 'nav.branches',
      titleFallback: 'Branches',
    ),
  ],
  registerMocks: registerBranchesArea,
  i18nSupplements: [
    'packages/dashboard_admin/assets/i18n/en.json',
    'packages/dashboard_admin/assets/i18n/ar.json',
    'packages/dashboard_admin/assets/i18n/branches.en.json',
    'packages/dashboard_admin/assets/i18n/branches.ar.json',
  ],
);

/// Opens [path] (the Branches page by default) as [persona].
Future<DashHarness> pumpBranches(
  WidgetTester tester, {
  String path = branchesPath,
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  MockServer? server,
  MockDb? db,
}) => DashHarness.pump(
  tester,
  areas: const [branchesArea],
  path: path,
  persona: persona,
  size: size,
  locale: locale,
  dark: dark,
  server: server,
  db: db,
);

/// A seeded server with the core's and the Branches handlers, for a test
/// that changes the data or the answers before the page opens.
({MockServer server, MockDb db}) branchesServer({
  Persona persona = Persona.owner,
}) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  registerBranchesArea(server, db);
  return (server: server, db: db);
}

/// The branch row [id] in [db].
Map<String, Object?> branchRow(MockDb db, String id) => db['branches'].get(id);

/// The branch row named [name] in [db].
Map<String, Object?> branchNamed(MockDb db, String name) =>
    db['branches'].rows.firstWhere((r) => r['name'] == name);

/// Sabah's branches as the page lists them.
List<Branch> sabahBranches(MockDb db) => [
  for (final r in db['branches'].query(
    filters: {'org_id': SeedIds.sabahOrg},
    sort: 'name',
  ))
    Branch.fromJson(r),
];

/// Closes every open till of branch [id] (so it can be deleted).
void closeTills(MockDb db, String id) {
  if (!db.hasTable('tills')) return;
  for (final r in db['tills'].where(
    (r) => r['branch_id'] == id && r['closed_at'] == null,
  )) {
    r['closed_at'] = db.nowIso;
    r['status'] = 'closed';
  }
}

/// The body of the last [method] call to [template].
Map<String, Object?> lastBody(
  MockServer server,
  String template, {
  String method = 'PATCH',
}) {
  final calls = server.callsTo(template, method: method);
  expect(calls, isNotEmpty, reason: 'no $method $template');
  return (calls.last.body! as Map).cast<String, Object?>();
}

/// The table row (or phone card) showing [name].
Finder rowOf(String name) => find.ancestor(
  of: find.text(name),
  matching: find.byWidgetPredicate(
    (w) => w.runtimeType.toString().startsWith('DashPressable'),
  ),
);

/// The control a screen reader calls [label] (inside [within]).
Finder labelled(String label, {Finder? within}) => within == null
    ? find.bySemanticsLabel(label)
    : find.descendant(of: within, matching: find.bySemanticsLabel(label));

/// The field with [key].
Finder field(String key) => find.byKey(ValueKey(key));

/// The text in the field with [key].
String fieldText(WidgetTester tester, String key) => tester
    .widget<EditableText>(
      find.descendant(of: field(key), matching: find.byType(EditableText)),
    )
    .controller
    .text;

/// The stat card labelled [label].
DashStatCard stat(WidgetTester tester, String label) => tester.widget(
  find.byWidgetPredicate((w) => w is DashStatCard && w.label == label).first,
);

/// The header button labelled [label].
DashButton button(WidgetTester tester, String label) => tester.widget(
  find.byWidgetPredicate((w) => w is DashButton && w.label == label).first,
);

/// [text] inside the open confirm dialog.
Finder inConfirm(String text) => find.descendant(
  of: find.byType(DashConfirmDialog),
  matching: find.text(text),
);

/// Taps [text] in an open menu / popover (the page under it takes no taps).
Future<void> pick(DashHarness h, String text) =>
    h.tap(find.text(text).hitTestable());
