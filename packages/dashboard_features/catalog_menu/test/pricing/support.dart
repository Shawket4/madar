// Shared set-up for the `pricing` unit's tests: the real app shell with the
// menu area on the seeded mock server, a branch picked in the top bar, and
// finders scoped to the page.
import 'dart:convert';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_menu/dashboard_catalog_menu.dart';
import 'package:dashboard_catalog_menu/src/area_seed.dart';
import 'package:dashboard_catalog_menu/src/pricing/pricing_page.dart';
import 'package:dashboard_catalog_menu/src/pricing/pricing_widgets.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const String pricingPath = '/menu/pricing';

const String catalogT = '/costing/catalog';
const String addonCatalogT = '/addon-items/catalog';
const String branchAddonT = '/branch-addon-overrides';
const String channelAddonT = '/delivery/channel-addon-overrides';
const String studioT = '/menu-items/{id}/studio';
const String overrideT = '/menu-price-overrides';

/// A seeded server with the core's and the menu area's handlers.
({MockServer server, MockDb db}) pricingServer({
  Persona persona = Persona.owner,
}) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  registerCatalogMenuMocks(server, db);
  return (server: server, db: db);
}

/// The top bar's branch, as a person picked it before.
Map<String, String> branchPicked(String? branchId) => {
  ScopePrefKeys.branch: jsonEncode({
    'org': SeedIds.sabahOrg,
    'branch': branchId,
  }),
};

/// Opens the page as [persona] with [branch] scoped (Zamalek by default:
/// it holds most of the seed's overrides; [allBranches] scopes none).
Future<DashHarness> pumpPricing(
  WidgetTester tester, {
  Persona? persona = Persona.owner,
  String? branch,
  bool allBranches = false,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  ({MockServer server, MockDb db})? seeded,
  Map<String, String>? prefs,
  String path = pricingPath,
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
  prefs: prefs ?? branchPicked(allBranches ? null : branch ?? SeedIds.zamalek),
);

/// [f] inside the pricing page.
Finder inPage(Finder f) =>
    find.descendant(of: find.byType(PricingAvailabilityPage), matching: f);

Finder pageText(String s) => inPage(find.text(s));

/// The page's own (vertical) scroll view.
Finder get pageScroll => inPage(find.byType(Scrollable)).first;

/// Scrolls the page until [f] shows.
Future<void> reveal(DashHarness h, Finder f) =>
    h.scrollUntilVisible(f, scrollable: pageScroll);

/// The control of the cell [targetId] × [col] (`in_store` or a channel).
Finder cellOf(String targetId, String col) => find.byKey(
  ValueKey('$targetId|${col == 'in_store' ? col : 'channel:$col'}'),
);

/// The price box inside the cell.
Finder priceBox(String targetId, String col) => find.descendant(
  of: cellOf(targetId, col),
  matching: find.byType(EditableText),
);

/// The availability switch inside the cell.
Finder toggleOf(String targetId, String col) => find.descendant(
  of: cellOf(targetId, col),
  matching: find.byKey(const ValueKey('avail')),
);

/// The cell's "Remove override" ×.
Finder clearOf(String targetId, String col) => find.descendant(
  of: cellOf(targetId, col),
  matching: find.byKey(const ValueKey('clear')),
);

/// The cell's control widget.
PricingControl controlOf(WidgetTester tester, String targetId, String col) =>
    tester.widget(cellOf(targetId, col));

/// The text in the cell's price box.
String priceText(WidgetTester tester, String targetId, String col) =>
    tester.widget<EditableText>(priceBox(targetId, col)).controller.text;

/// Expands the item [name] (desktop row or phone card).
Future<void> expand(DashHarness h, String name) async {
  final head = find.ancestor(
    of: pageText(name),
    matching: find.byType(PricingItemHead),
  );
  await reveal(h, head);
  await h.tap(head);
}

/// Types [text] into a cell's price box.
Future<void> typePrice(
  DashHarness h,
  String targetId,
  String col,
  String text,
) async {
  await reveal(h, priceBox(targetId, col));
  await h.enterText(priceBox(targetId, col), text);
}

/// Taps a cell's availability switch.
Future<void> toggle(DashHarness h, String targetId, String col) async {
  await reveal(h, toggleOf(targetId, col));
  await h.tap(toggleOf(targetId, col));
}

/// Seed ids.
String sizeId(String item, String label) => MenuSeedIds.size(item, label);
String optionId(String group, String option) =>
    MenuSeedIds.option(group, option);

/// The override rows at [branch] for [targetId].
List<MockRow> rowsFor(MockDb db, String branch, String targetId) =>
    db[MenuTables.priceOverrides].where(
      (o) => o['branch_id'] == branch && o['target_id'] == targetId,
    );
