// Shared set-up for the onboarding unit's tests: the real app shell with the
// full-screen `/onboarding` page, on the seeded mock server (core seed +
// admin seed + the handlers the wizard and its editors reach).
//
// The tests mount an area holding only `/onboarding` (and the admin units'
// handlers its steps call: the org's PATCH and logo, the branch dialog's
// writes) so they run on their own while the other admin units are being
// built in parallel; the page and its handlers are exactly the ones
// `adminArea` wires in.
import 'package:dashboard_admin/src/area_seed.dart';
import 'package:dashboard_admin/src/mock/branches_mock.dart';
import 'package:dashboard_admin/src/mock/onboarding_mock.dart';
import 'package:dashboard_admin/src/mock/orgs_mock.dart';
import 'package:dashboard_admin/src/mock/users_mock.dart';
import 'package:dashboard_admin/src/onboarding/onboarding_page.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

export 'package:dashboard_core/testing.dart' show DashHarness, DashSize;

const onboardingPath = '/onboarding';
const statusRoute = '/orgs/{id}/onboarding';
const completeRoute = '/orgs/{id}/onboarding/complete';
const orgRoute = '/orgs/{id}';
const logoRoute = '/orgs/{id}/logo';

final sabah = SeedIds.sabahOrg;

Widget _onboarding(BuildContext context, GoRouterState state) =>
    const OnboardingPage();

/// The admin handlers the wizard reaches: the area seed, the org's PATCH and
/// logo, the branch dialog's writes, the users unit's, and its own.
void registerOnboardingArea(MockServer server, MockDb db) {
  loadAdminSeed(db);
  registerOrgsMocks(server, db);
  registerUsersMocks(server, db);
  registerBranchesMocks(server, db);
  registerOnboardingMocks(server, db);
}

/// The admin area with only `/onboarding`, as `adminRoutes` declares it.
const DashArea onboardingArea = DashArea(
  key: 'admin',
  routes: [
    DashRoute(
      path: OnboardingPage.path,
      builder: _onboarding,
      titleKey: 'onboarding.title',
      titleFallback: "Let's open your café",
    ),
  ],
  registerMocks: registerOnboardingArea,
  i18nSupplements: [
    'packages/dashboard_admin/assets/i18n/en.json',
    'packages/dashboard_admin/assets/i18n/ar.json',
    'packages/dashboard_admin/assets/i18n/branches.en.json',
    'packages/dashboard_admin/assets/i18n/branches.ar.json',
    'packages/dashboard_admin/assets/i18n/users.en.json',
    'packages/dashboard_admin/assets/i18n/users.ar.json',
    'packages/dashboard_admin/assets/i18n/onboarding.en.json',
    'packages/dashboard_admin/assets/i18n/onboarding.ar.json',
  ],
);

/// A seeded server with the core's and the wizard's handlers, for a test
/// that changes the data or the answers before the page opens.
({MockServer server, MockDb db}) onboardingServer({
  Persona persona = Persona.owner,
}) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  registerOnboardingArea(server, db);
  return (server: server, db: db);
}

/// Opens [path] (the wizard by default) as [persona].
Future<DashHarness> pumpOnboarding(
  WidgetTester tester, {
  String path = onboardingPath,
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
  areas: const [onboardingArea],
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

/// Sabah Coffee as a café that has just signed up: no logo, branch, payment
/// method, menu, ingredient, add-on, extra person or order, and its
/// checklist not finished.
void freshCafe(MockDb db) {
  bool mine(MockRow r) => r['org_id'] == sabah;
  db['orgs'].get(sabah)['logo_url'] = null;
  final branchIds = {
    for (final b in db['branches'].rows)
      if (mine(b)) b['id'],
  };
  db['branches'].removeWhere(mine);
  for (final t in const [
    OnbTables.paymentMethods,
    OnbTables.categories,
    OnbTables.menuItems,
    OnbTables.groups,
    OnbTables.ingredients,
    OnbTables.ingredientCategories,
  ]) {
    db[t].removeWhere(mine);
  }
  db[OnbTables.sizes].clear();
  db[OnbTables.groupLinks].clear();
  db['users'].removeWhere((u) => mine(u) && u['role'] != 'org_admin');
  db['orders'].clear();
  db['tills'].removeWhere((t) => branchIds.contains(t['branch_id']));
  db[onboardingTable].put({'id': sabah, 'completed_at': null});
}

/// Adds rows so the café has [n] of each kind the step counts.
MockRow addBranch(MockDb db, {String name = 'Heliopolis'}) {
  final model = MockSeed.instance.allBranches.firstWhere(
    (b) => b.orgId == sabah,
  );
  return db['branches'].insert({...model.toJson(), 'id': null, 'name': name});
}

MockRow addPaymentMethod(MockDb db, {String name = 'cash'}) =>
    db[OnbTables.paymentMethods].insert({
      'org_id': sabah,
      'name': name,
      'label_translations': {'en': 'Cash', 'ar': 'نقدي'},
      'color': '#10B981',
      'icon': 'money',
      'is_cash': true,
      'is_active': true,
      'visible_in_integrations': true,
    });

MockRow addCategory(
  MockDb db, {
  String name = 'Hot drinks',
  String ar = 'مشروبات ساخنة',
}) => db[OnbTables.categories].insert({
  'org_id': sabah,
  'name': name,
  'name_translations': {'en': name, 'ar': ar},
  'image_url': null,
  'is_active': true,
  'display_order': db[OnbTables.categories].length,
  'deleted_at': null,
});

MockRow addItem(
  MockDb db,
  MockRow category, {
  String name = 'Latte',
  String ar = 'لاتيه',
  int price = 6500,
}) => db[OnbTables.menuItems].insert({
  'org_id': sabah,
  'category_id': category['id'],
  'name': name,
  'name_translations': {'en': name, 'ar': ar},
  'description': null,
  'description_translations': const <String, Object?>{},
  'image_url': null,
  'base_price': price,
  'is_active': true,
  'deleted_at': null,
  'kind': 'item',
});

MockRow addIngredient(
  MockDb db, {
  String name = 'Whole milk',
  String unit = 'ml',
  double? cost = 4.5,
}) {
  final cats = db[OnbTables.ingredientCategories];
  final general =
      cats.firstWhere((c) => c['org_id'] == sabah && c['slug'] == 'general') ??
      cats.insert({
        'org_id': sabah,
        'name': 'General',
        'slug': 'general',
        'sort_order': 0,
        'is_packaging': false,
        'ingredient_count': 0,
      });
  return db[OnbTables.ingredients].insert({
    'org_id': sabah,
    'name': name,
    'category_id': general['id'],
    'category_name': general['name'],
    'category_slug': general['slug'],
    'unit': unit,
    'cost_per_unit': cost,
    'is_active': true,
    'deleted_at': null,
  });
}

/// The four required steps done (a branch, a payment method, a category and
/// an item): "Open my café" is allowed.
void readyCafe(MockDb db) {
  freshCafe(db);
  addBranch(db);
  addPaymentMethod(db);
  addItem(db, addCategory(db));
}

/// Every step done, the optional ones too: a logo, an ingredient, an
/// add-on, a recipe and a second person.
void everythingDone(MockDb db) {
  readyCafe(db);
  db['orgs'].get(sabah)['logo_url'] = 'data:image/png;base64,AA==';
  final milk = addIngredient(db);
  final item = db[OnbTables.menuItems].rows.firstWhere(
    (i) => i['org_id'] == sabah,
  );
  final size = db[OnbTables.sizes].insert({
    'menu_item_id': item['id'],
    'label': 'one_size',
    'price_override': item['base_price'],
    'is_active': true,
    'sort': 0,
  }, timestamps: false);
  db[OnbTables.recipeLines].insert({
    'size_id': size['id'],
    'menu_item_id': item['id'],
    'ingredient_id': milk['id'],
    'quantity': '180',
    'unit': 'ml',
    'source': 'own',
    'sort': 0,
  }, timestamps: false);
  db[OnbTables.groups].insert({
    'org_id': sabah,
    'name': 'Extras',
    'name_translations': {'ar': 'إضافات'},
    'selection_type': 'multi',
    'min_selections': 0,
    'max_selections': null,
    'is_required': false,
    'sort': 0,
    'is_active': true,
    'legacy_addon_type': 'extras',
    'effect': 'none',
    'is_item_options': false,
    'options': [
      {
        'id': 'opt-shot',
        'name': 'Extra shot',
        'name_translations': {'ar': 'شوت إضافي'},
        'price': 1500,
        'is_default': false,
        'is_active': true,
        'sort': 0,
      },
    ],
  }, timestamps: false);
  final owner = db['users'].rows.firstWhere(
    (u) => u['org_id'] == sabah && u['role'] == 'org_admin',
  );
  db['users'].insert({
    ...owner,
    'id': null,
    'name': 'Omar Fathy',
    'email': 'omar@sabah.test',
    'role': 'teller',
  });
}

/// The body of the last [method] call to [template].
Map<String, Object?> lastBody(
  MockServer server,
  String template, {
  String method = 'POST',
}) {
  final calls = server.callsTo(template, method: method);
  expect(calls, isNotEmpty, reason: 'no $method $template');
  return (calls.last.body! as Map).cast<String, Object?>();
}

/// The number of times the checklist was asked for.
int statusReads(MockServer server) =>
    server.callsTo(statusRoute, method: 'GET').length;

/// The page (not the shell around it).
Finder get page => find.byType(OnboardingPage);

/// [text] inside the wizard page.
Finder inPage(String text) =>
    find.descendant(of: page, matching: find.text(text));

/// The open dialog / full-screen editor.
Finder get surface => find.byType(DashSurface).last;

/// [text] inside the open editor.
Finder inSurface(String text) =>
    find.descendant(of: surface, matching: find.text(text));

/// The field with [key].
Finder field(String key) => find.byKey(ValueKey(key));

/// The button labelled [label] (its widget).
DashButton button(WidgetTester tester, String label, {Finder? within}) =>
    tester.widget(buttonOf(label, within: within).first);

/// The button labelled [label] (a finder).
Finder buttonOf(String label, {Finder? within}) => find.descendant(
  of: within ?? page,
  matching: find.byWidgetPredicate((w) => w is DashButton && w.label == label),
);

/// Taps [text] in an open menu / popover (the page under it takes no taps).
Future<void> pick(DashHarness h, String text) =>
    h.tap(find.text(text).hitTestable().last);
