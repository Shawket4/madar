// Shared set-up for the `items` unit's tests: the real app shell with the
// menu area on the seeded mock server, and finders scoped to the page's
// cards, toolbar and dialogs.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_menu/dashboard_catalog_menu.dart';
import 'package:dashboard_catalog_menu/src/area_seed.dart';
import 'package:dashboard_catalog_menu/src/items/items_page.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const String itemsPath = '/menu/items';
const String catalogPath = '/costing/catalog';

/// A seeded server with the core's and the menu area's handlers, for a test
/// that changes the data or the answers before the page opens.
({MockServer server, MockDb db}) itemsServer({
  Persona persona = Persona.owner,
}) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  registerCatalogMenuMocks(server, db);
  return (server: server, db: db);
}

/// Opens the items page as [persona]; [branchId] scopes one branch.
Future<DashHarness> pumpItems(
  WidgetTester tester, {
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  ({MockServer server, MockDb db})? seeded,
  String? branchId,
  String path = itemsPath,
}) async {
  final h = await DashHarness.pump(
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
  if (branchId != null) {
    await h.container.read(scopeProvider.notifier).setBranch(branchId);
    await h.settle();
  }
  return h;
}

/// The page itself.
Finder get page => find.byType(MenuItemsPage);

/// [f] inside the page.
Finder inPage(Finder f) => find.descendant(of: page, matching: f);

/// The card whose title reads [title].
Finder cardOf(String title) => find
    .ancestor(
      of: inPage(find.text(title)),
      matching: find.byWidgetPredicate(
        (w) => w.runtimeType.toString().startsWith('_EditableCard<'),
      ),
    )
    .first;

/// [f] inside the card titled [title].
Finder inCard(String title, Finder f) =>
    find.descendant(of: cardOf(title), matching: f);

/// The control a screen reader calls [label] inside [scope].
Finder labelIn(Finder scope, String label) =>
    find.descendant(of: scope, matching: find.bySemanticsLabel(label));

/// The open dialog / sheet surface.
Finder get surface => find.byType(DashSurface).last;

/// [f] inside the open dialog.
Finder inSurface(Finder f) => find.descendant(of: surface, matching: f);

/// Opens the ⋯ menu of the card titled [title].
Future<void> openCardMenu(DashHarness h, String title) =>
    h.tap(labelIn(cardOf(title), h.t('common.moreActions')));

/// Picks [item] in the open ⋯ menu.
Future<void> pickMenu(DashHarness h, String item) =>
    h.tap(find.text(item).last);

/// Switches the page to [tab] (its segment).
Future<void> openTab(DashHarness h, String tab) =>
    h.tap(find.byKey(ValueKey('menu-tab-$tab')));

/// The last recorded call to `method template`.
MockCall lastCall(DashHarness h, String method, String template) =>
    h.server.callsTo(template, method: method).last;

/// Calls to `method template`.
List<MockCall> callsOf(DashHarness h, String method, String template) =>
    h.server.callsTo(template, method: method);

/// Seed ids used across the tests.
String get sabahOrg => SeedIds.sabahOrg;
String item(String key) => MenuSeedIds.item(key);
String category(String key) => MenuSeedIds.category(key);
String option(String group, String key) => MenuSeedIds.option(group, key);
String size(String item, String label) => MenuSeedIds.size(item, label);

/// The live (not deleted) seeded items of the org.
List<MockRow> liveItems(MockDb db) => db[MenuTables.menuItems].where(
  (m) => m['org_id'] == sabahOrg && m['deleted_at'] == null,
);

/// Picks [label] in the open option list.
Future<void> pickOption(DashHarness h, String label) => h.tap(
  find
      .descendant(
        of: find.byWidgetPredicate((w) => w is DashOptionList),
        matching: find.text(label),
      )
      .last,
);

/// Opens the select a screen reader calls [label] (first match in [scope])
/// and picks [option].
Future<void> chooseIn(
  DashHarness h,
  Finder scope,
  String label,
  String option,
) async {
  await h.tap(selectIn(scope, label));
  await pickOption(h, option);
}

/// Types [text] into the open inline cell (its field) and presses Enter.
Future<void> typeAndSubmit(DashHarness h, Finder field, String text) async {
  await h.enterText(field, text);
  await h.tester.testTextInput.receiveAction(TextInputAction.done);
  await h.settle();
}

/// The switch a screen reader calls [label] inside [scope].
Finder switchIn(Finder scope, String label) => find.descendant(
  of: scope,
  matching: find.byWidgetPredicate(
    (w) => w is DashSwitch && w.semanticLabel == label,
  ),
);

/// The select a screen reader calls [label] inside [scope].
Finder selectIn(Finder scope, String label) => find.descendant(
  of: scope,
  matching: find.byWidgetPredicate(
    (w) => w is DashSelect && w.semanticLabel == label,
  ),
);

/// The text box a screen reader calls [label] inside [scope] (not its
/// visible label).
Finder fieldIn(Finder scope, String label) => find.descendant(
  of: scope,
  matching: find.byWidgetPredicate(
    (w) => w is DashTextInput && w.semanticLabel == label,
  ),
);
