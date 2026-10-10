// Shared set-up for the Users unit's tests: the real app shell with the
// Users page, on the seeded mock server (core seed + admin seed + the unit's
// handlers).
//
// The tests mount an area holding only `/access/users` (and its mocks) so
// they run on their own while the other admin units are built in parallel;
// the page, its dialogs and its handlers are exactly the ones `adminArea`
// wires in (`lib/src/routes.dart`, `lib/src/mock/register.dart`).
import 'package:dashboard_admin/src/area_seed.dart';
import 'package:dashboard_admin/src/mock/users_mock.dart';
import 'package:dashboard_admin/src/shared/org_errors.dart';
import 'package:dashboard_admin/src/users/users_data.dart';
import 'package:dashboard_admin/src/users/users_page.dart';
import 'package:dashboard_api/dashboard_api.dart' show ApiException;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

export 'package:dashboard_core/testing.dart' show DashHarness, DashSize;

const usersPath = '/access/users';
const listRoute = '/users';
const itemRoute = '/users/{id}';
const pinRoute = '/users/pin-suggestion';
const userBranchesRoute = '/users/{id}/branches';
const unassignRoute = '/users/{id}/branches/{branchId}';
const accessRoute = '/authz/users/{id}';
const overridesRoute = '/authz/users/{id}/overrides';
const assignmentsRoute = '/authz/users/{id}/assignments';
const explainRoute = '/authz/explain';
const rolesRoute = '/authz/roles';
const branchesRoute = '/branches';
const linkableRoute = '/staff/employees/linkable';

/// A page with nothing on it, to start from when a test opens Users itself.
const blankPath = '/blank';

Widget _users(BuildContext context, GoRouterState state) => const UsersPage();

Widget _blank(BuildContext context, GoRouterState state) =>
    const SizedBox.shrink();

/// The admin area's handlers this page needs: the area seed and the Users
/// handlers.
void registerUsersArea(MockServer server, MockDb db) {
  loadAdminSeed(db);
  registerUsersMocks(server, db);
}

/// The admin area with only `/access/users`, as `adminRoutes` declares it.
const DashArea usersArea = DashArea(
  key: 'admin',
  routes: [
    DashRoute(
      path: UsersPage.path,
      builder: _users,
      titleKey: 'nav.users',
      titleFallback: 'Users',
      prefetch: prefetchUsers,
    ),
    DashRoute(path: blankPath, builder: _blank),
  ],
  registerMocks: registerUsersArea,
  i18nSupplements: [
    'packages/dashboard_admin/assets/i18n/en.json',
    'packages/dashboard_admin/assets/i18n/ar.json',
    'packages/dashboard_admin/assets/i18n/users.en.json',
    'packages/dashboard_admin/assets/i18n/users.ar.json',
  ],
);

/// Opens [path] (the Users page by default) as [persona].
Future<DashHarness> pumpUsers(
  WidgetTester tester, {
  String path = usersPath,
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  MockServer? server,
  MockDb? db,
  AreaOpeners openers = const AreaOpeners(),
}) => DashHarness.pump(
  tester,
  areas: const [usersArea],
  path: path,
  persona: persona,
  size: size,
  locale: locale,
  dark: dark,
  server: server,
  db: db,
  overrides: [areaOpenersProvider.overrideWithValue(openers)],
);

/// The app's Add employee seam, recording each person it opens for and
/// each warm.
AreaOpeners makeEmployeeSeam(List<String> opened, {List<String>? warmed}) =>
    AreaOpeners(
      addEmployee: AddEmployeeOpener(
        open: (context, {userId}) async => opened.add(userId ?? ''),
        warm: (ref) => warmed?.add('warm'),
      ),
    );

/// A seeded server with the core's and the Users handlers, for a test that
/// changes the data or the answers before the page opens.
({MockServer server, MockDb db}) usersServer({
  Persona persona = Persona.owner,
}) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  registerUsersArea(server, db);
  return (server: server, db: db);
}

/// A seeded person's id by key (`uid('mariam')`).
String uid(String key) => SeedIds.user(key);

/// The body of the last [method] call to [template].
Map<String, Object?> lastBody(
  MockServer server,
  String template, {
  required String method,
}) {
  final calls = server.callsTo(template, method: method);
  expect(calls, isNotEmpty, reason: 'no $method $template');
  return (calls.last.body! as Map).cast<String, Object?>();
}

/// The Users page.
Finder get page => find.byType(UsersPage);

/// [text] on the Users page (not the sidebar).
Finder onPage(String text) =>
    find.descendant(of: page, matching: find.text(text));

/// The open dialog / side panel / sheet.
Finder get surface => find.byType(DashSurface);

/// [text] inside the open dialog / panel.
Finder inSurface(String text) =>
    find.descendant(of: surface, matching: find.text(text));

/// The table row (or phone card) showing [name].
Finder rowOf(String name) => find.ancestor(
  of: find.descendant(of: page, matching: find.text(name)),
  matching: find.byWidgetPredicate(
    (w) => w.runtimeType.toString().startsWith('DashPressable'),
  ),
);

/// The control a screen reader calls [label] (inside [within]).
Finder labelled(String label, {Finder? within}) => within == null
    ? find.bySemanticsLabel(label)
    : find.descendant(of: within, matching: find.bySemanticsLabel(label));

/// The row action [label] on [name]'s row.
Finder rowAction(String name, String label) => find.descendant(
  of: rowOf(name).first,
  matching: find.bySemanticsLabel(label),
);

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

/// [text] inside the open confirm dialog.
Finder inConfirm(String text) => find.descendant(
  of: find.byType(DashConfirmDialog),
  matching: find.text(text),
);

/// Taps [text] in an open menu / popover (the page under it takes no taps).
Future<void> pick(DashHarness h, String text) =>
    h.tap(find.text(text).hitTestable().last);

/// The words this unit shows for a refusal: the transport's words
/// (`h.refusalWords`) through the area's `getErrorMessage` rule (the kind
/// prefix off, an uncoded 403 "You don't have permission…", ADM-APP-117).
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
