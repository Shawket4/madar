// Shared set-up for the `bases` unit's tests: the real app shell with the
// menu area on the seeded mock server, and finders for the pages' rows.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_menu/dashboard_catalog_menu.dart';
import 'package:dashboard_catalog_menu/src/area_seed.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const String basesPath = '/menu/bases';
const String packagingPath = '/menu/packaging';

/// A seeded server with the core's and the menu area's handlers, for a test
/// that changes the data or the answers before the page opens.
({MockServer server, MockDb db}) menuServer({Persona persona = Persona.owner}) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  registerCatalogMenuMocks(server, db);
  return (server: server, db: db);
}

/// Opens [path] as [persona].
Future<DashHarness> pumpMenu(
  WidgetTester tester, {
  String path = basesPath,
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  ({MockServer server, MockDb db})? seeded,
}) => DashHarness.pump(
  tester,
  areas: const [catalogMenuArea],
  path: path,
  persona: persona,
  size: size,
  locale: locale,
  dark: dark,
  server: seeded?.server,
  db: seeded?.db,
);

/// The row of the base or rule [id].
Finder rowOf(String id) => find.byKey(ValueKey(id));

/// The control a screen reader calls [label] inside [scope].
Finder labelIn(Finder scope, String label) =>
    find.descendant(of: scope, matching: find.bySemanticsLabel(label));

/// Text widgets whose text contains [s] (spans included).
Finder textHas(String s) => find.textContaining(s, findRichText: true);

/// Seed ids used across the tests.
final String espressoBase = MenuSeedIds.base('espresso');
final String icedBase = MenuSeedIds.base('iced_build');
final String mochaOldBase = MenuSeedIds.base('mocha_old');

/// The sizes following [baseId] (live items), as the seed holds them.
int sizesUsing(MockDb db, String baseId) =>
    db[MenuTables.sizes].where((s) => s['base_id'] == baseId).length;

/// The distinct items with a size following [baseId].
int itemsUsing(MockDb db, String baseId) => {
  for (final s in db[MenuTables.sizes].where((s) => s['base_id'] == baseId))
    s['menu_item_id'],
}.length;

/// The last recorded call to `method template`.
MockCall lastCall(DashHarness h, String method, String template) =>
    h.server.callsTo(template, method: method).last;

/// A seeded server whose `/authz/me` grants exactly [caps] to [persona]
/// (the server's own checks still follow the persona).
({MockServer server, MockDb db}) serverWithCaps(
  List<String> caps, {
  Persona persona = Persona.limited,
}) {
  final s = menuServer(persona: persona);
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

/// The quantity cell of [ingredient] in the column [size].
Finder cell(DashHarness h, String ingredient, String size) =>
    find.bySemanticsLabel(
      h.t(
        'modeling.grid.cellAria',
        args: {'ingredient': ingredient, 'size': size},
      ),
    );

/// The editable text inside [f].
EditableText editable(WidgetTester tester, Finder f) => tester.widget(
  find.descendant(of: f, matching: find.byType(EditableText)).first,
);

/// Picks [name] in the "+ ingredient" combobox.
Future<void> addIngredient(DashHarness h, String name) async {
  await h.tap(find.text(h.t('modeling.grid.addIngredient')).last);
  await pickOption(h, name);
}

/// Picks [name] in the open option list, searched for first (the list is
/// longer than its popover; a person types). The option row comes after the
/// search box, which now holds [name] too.
Future<void> pickOption(DashHarness h, String name) async {
  final list = find.byWidgetPredicate((w) => w is DashOptionList);
  await h.enterText(
    find.descendant(of: list, matching: find.byType(EditableText)),
    name,
  );
  await h.tap(find.descendant(of: list, matching: find.text(name)).last);
}

/// The invalidation epoch of [path], read through a listener kept for the
/// test: a refresh reaching a key nothing on the page reads bumps it.
int Function() epochOf(DashHarness h, String path) {
  final sub = h.container.listen(realtimeEpochProvider(path), (_, _) {});
  addTearDown(sub.close);
  return sub.read;
}

/// The keys `invalidateCatalog()` reaches that the bases page never reads.
const List<String> catalogKeys = ['/costing/catalog', '/categories'];
