// Shared set-up for the combos list's tests: the page through the real shell
// on the seeded mock server, a server whose `/authz/me` grants a chosen set
// of capabilities, extra combos for paging, and finders scoped to the page.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_offers/dashboard_catalog_offers.dart';
import 'package:dashboard_catalog_offers/src/area_seed.dart';
import 'package:dashboard_catalog_offers/src/combos/combos_page.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter_test/flutter_test.dart';

const String combosPath = '/menu/combos';
const String combosApi = '/combos';
const String categoriesApi = '/categories';
const String deleteApi = '/menu-items/{id}';

/// A seeded combo's id by its seed key.
String comboId(String key) => OffersSeed.comboId(key);

/// A seeded server with the core's and the area's handlers.
({MockServer server, MockDb db}) combosServer({
  Persona persona = Persona.owner,
}) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  catalogOffersArea.registerMocks!(server, db);
  return (server: server, db: db);
}

/// A seeded server where `/authz/me` grants exactly [caps] to [persona]
/// (the server's own checks still follow the persona).
({MockServer server, MockDb db}) serverWithCaps(
  List<String> caps, {
  Persona persona = Persona.limited,
}) {
  final s = combosServer(persona: persona);
  s.server.on(
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
  return s;
}

/// Adds [n] plain combos ("Extra combo 01" …, no slots) to the org, so the
/// list runs to more than one page.
void addCombos(MockDb db, int n) {
  OffersSeed.loadInto(db);
  final items = db.table(OffersTables.menuItems);
  for (var i = 1; i <= n; i++) {
    final name = 'Extra combo ${i.toString().padLeft(2, '0')}';
    items.insert({
      'id': mockUuid('combo:extra:$i'),
      'org_id': SeedIds.sabahOrg,
      'category_id': null,
      'name': name,
      'name_translations': {'en': name},
      'description': null,
      'description_translations': <String, Object?>{},
      'base_price': 10000 + i * 100,
      'is_active': true,
      'kind': 'combo',
      'image_url': null,
      'default_milk_addon_id': null,
      'deleted_at': null,
      'created_at': '2026-09-01T09:00:00.000Z',
      'updated_at': '2026-09-01T09:00:00.000Z',
    }, timestamps: false);
  }
}

/// Removes every combo (an org with none yet).
void clearCombos(MockDb db) {
  OffersSeed.loadInto(db);
  for (final r in db.table(OffersTables.menuItems).rows) {
    if (r['kind'] == 'combo') r['deleted_at'] = '2026-09-01T09:00:00.000Z';
  }
}

/// The combos list as [persona] at [size], in [locale].
Future<DashHarness> pumpCombos(
  WidgetTester tester, {
  String path = combosPath,
  Persona? persona,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  ({MockServer server, MockDb db})? seeded,
}) => DashHarness.pump(
  tester,
  areas: const [catalogOffersArea],
  path: path,
  // A seeded server signs in its own persona.
  persona: persona ?? seeded?.server.persona ?? Persona.owner,
  size: size,
  locale: locale,
  dark: dark,
  server: seeded?.server,
  db: seeded?.db,
);

/// [f] inside the combos page (not the sidebar or the header).
Finder inPage(Finder f) =>
    find.descendant(of: find.byType(CombosPage), matching: f);

/// [text] on the page.
Finder pageText(String text) => inPage(find.text(text));

/// The table row (or phone card) of the combo named [name].
Finder rowOf(String name) => inPage(
  find.byWidgetPredicate((w) => w is DashPressable && w.semanticLabel == name),
);

/// [f] inside the row of [name].
Finder inRow(String name, Finder f) =>
    find.descendant(of: rowOf(name), matching: f);

/// The icon button a screen reader calls [label] in the row of [name].
Finder rowButton(String name, String label) => inRow(
  name,
  find.byWidgetPredicate(
    (w) => w is DashIconButton && w.semanticLabel == label,
  ),
);

/// The page's button labelled [label] (a header action, the empty state's).
Finder pageButton(String label) => inPage(
  find.byWidgetPredicate((w) => w is DashButton && w.label == label),
);

/// A filter select whose accessible name is [label].
Finder filterSelect(String label) => inPage(
  find.byWidgetPredicate((w) => w is DashSelect && w.semanticLabel == label),
);

/// The search box.
Finder searchBox() => inPage(find.byType(DashSearchInput));

/// The combo names in the order the table shows them.
List<String> shownNames(WidgetTester tester) => [
  for (final e in inPage(find.byType(ComboNameCell)).evaluate())
    (e.widget as ComboNameCell).combo.name,
];

/// The calls made to [template] with [method].
List<MockCall> callsTo(DashHarness h, String template, {String method = 'GET'}) =>
    h.server.callsTo(template, method: method);
