// Shared set-up for the Roles & Permissions tests: the real app shell with
// the Roles page, on the seeded mock server (core seed + admin seed + the
// Users handlers, which answer `GET /authz/roles`, + this unit's handlers).
//
// The tests mount an area holding only `/access/roles` (and a blank page
// with a link to it, for the prefetch test) so they run on their own while
// the other admin units are built in parallel; the page, its dialogs and its
// handlers are exactly the ones `adminArea` wires in.
import 'package:dashboard_admin/src/area_seed.dart';
import 'package:dashboard_admin/src/mock/roles_mock.dart';
import 'package:dashboard_admin/src/mock/users_mock.dart';
import 'package:dashboard_admin/src/shared/org_errors.dart';
import 'package:dashboard_admin/src/roles/roles_data.dart';
import 'package:dashboard_admin/src/roles/roles_page.dart';
import 'package:dashboard_api/dashboard_api.dart' show ApiException, MyAuthz;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show PrefetchOnIntent;
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

export 'package:dashboard_core/testing.dart' show DashHarness, DashSize;

const rolesPath = '/access/roles';
const rolesRoute = '/authz/roles';
const roleRoute = '/authz/roles/{id}';
const grantsRoute = '/authz/roles/{id}/grants';
const policyRoute = '/authz/policy';

/// A page with a link to Roles & Permissions on it (the Access tabs do not
/// prefetch; whatever row points at the page does).
const linkPath = '/blank';

Widget _roles(BuildContext context, GoRouterState state) => const RolesPage();

Widget _link(BuildContext context, GoRouterState state) => Center(
  child: PrefetchOnIntent(
    to: rolesPath,
    child: GestureDetector(
      key: const ValueKey('roles-link'),
      behavior: HitTestBehavior.opaque,
      onTap: () => GoRouter.of(context).go(rolesPath),
      child: const SizedBox(width: 200, height: 60),
    ),
  ),
);

/// The admin area's handlers this page needs.
void registerRolesArea(MockServer server, MockDb db) {
  loadAdminSeed(db);
  registerUsersMocks(server, db);
  registerRolesMocks(server, db);
}

/// The admin area with only `/access/roles`, as `adminRoutes` declares it.
const DashArea rolesArea = DashArea(
  key: 'admin',
  routes: [
    DashRoute(
      path: RolesPage.path,
      builder: _roles,
      titleKey: 'nav.rolesPermissions',
      titleFallback: 'Roles & Permissions',
      prefetch: prefetchRoles,
    ),
    DashRoute(path: linkPath, builder: _link),
  ],
  registerMocks: registerRolesArea,
  i18nSupplements: [
    'packages/dashboard_admin/assets/i18n/en.json',
    'packages/dashboard_admin/assets/i18n/ar.json',
    'packages/dashboard_admin/assets/i18n/roles.en.json',
    'packages/dashboard_admin/assets/i18n/roles.ar.json',
  ],
);

/// Opens [path] (the Roles page by default) as [persona].
Future<DashHarness> pumpRoles(
  WidgetTester tester, {
  String path = rolesPath,
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  MockServer? server,
  MockDb? db,
}) => DashHarness.pump(
  tester,
  areas: const [rolesArea],
  path: path,
  persona: persona,
  size: size,
  locale: locale,
  dark: dark,
  server: server,
  db: db,
);

/// A seeded server with the core's and this page's handlers, for a test that
/// changes the data or the answers before the page opens.
({MockServer server, MockDb db}) rolesServer({
  Persona persona = Persona.owner,
}) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  registerRolesArea(server, db);
  return (server: server, db: db);
}

/// Sabah's system role of [kind] (`roleId('teller')`).
String roleId(String kind) => mockUuid('role:sabah:$kind');

/// The owner's permissions minus [without] (the server still answers as the
/// owner): someone who may see roles but not change them, for instance.
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

/// The Roles page.
Finder get page => find.byType(RolesPage);

/// [text] on the Roles page (not the sidebar).
Finder onPage(String text) =>
    find.descendant(of: page, matching: find.text(text));

/// The roles list's row of [id].
Finder roleRow(String id) => find.byKey(ValueKey('role-$id'));

/// The selected role's card.
Finder get header => find.byKey(const ValueKey('role-header'));

/// [text] in the selected role's card.
Finder inHeader(String text) =>
    find.descendant(of: header, matching: find.text(text));

/// The grant switch of [capability].
Finder grantSwitch(String capability) =>
    find.byKey(ValueKey('grant-$capability'));

DashSwitch switchOf(WidgetTester tester, String capability) =>
    tester.widget<DashSwitch>(grantSwitch(capability));

/// Every toast on screen.
Finder get toasts =>
    find.byWidgetPredicate((w) => w.runtimeType.toString() == '_ToastCard');

/// The capability row showing [label].
Finder capabilityRow(String label) => find.ancestor(
  of: onPage(label),
  matching: find.byWidgetPredicate(
    (w) => w.runtimeType.toString() == '_CapabilityRow',
  ),
);

/// The policy row's control of [capability].
Finder policyControl(String capability) =>
    find.byKey(ValueKey('policy-$capability'));

/// The open dialog / sheet.
Finder get surface => find.byType(DashSurface);

/// [text] inside the open dialog.
Finder inSurface(String text) =>
    find.descendant(of: surface, matching: find.text(text));

/// [text] inside the open confirm dialog.
Finder inConfirm(String text) => find.descendant(
  of: find.byType(DashConfirmDialog),
  matching: find.text(text),
);

/// The field with [key].
Finder field(String key) => find.byKey(ValueKey(key));

/// Taps [text] in an open menu / popover (the page under it takes no taps).
Future<void> pick(DashHarness h, String text) =>
    h.tap(find.text(text).hitTestable().last);

/// The words this unit shows for a refusal: the transport's words through
/// the area's `getErrorMessage` rule (kind prefix off, an uncoded 403 "You
/// don't have permission…", ADM-APP-117).
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
