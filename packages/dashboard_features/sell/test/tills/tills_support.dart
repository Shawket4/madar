// Test support for the tills unit: the app at `/tills` on the sell mocks,
// a branch picked (Heliopolis by default), and finders scoped to the page.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_sell/dashboard_sell.dart';
import 'package:dashboard_sell/src/tills/tills_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/sell_harness.dart';

export 'package:dashboard_sell/src/mock/tills_mock.dart'
    show TillIds, TillTables, loadTillsScenario;

/// The reads' path templates.
const String tillsList = '/tills/branches/{branchId}';
const String tillsCurrent = '/tills/branches/{branchId}/current';
const String tillsOpen = '/tills/branches/{branchId}/open';
const String tillsNotice = '/tills/branches/{branchId}/open-bills-notice';
const String tillReport = '/tills/{tillId}/report';
const String tillSummary = '/reports/tills/{tillId}/summary';
const String tillDeductions = '/reports/tills/{tillId}/deductions';
const String tillSpotViews = '/tills/{tillId}/spot-views';
const String tillClosePreview = '/tills/{tillId}/close-preview';

/// A seeded server (core + sell mocks) to edit before pumping.
({MockServer server, MockDb db}) tillsServer({
  Persona persona = Persona.owner,
}) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  registerSellMocks(server, db);
  return (server: server, db: db);
}

/// `/tills` (+ [query]) with [branchId] picked (Heliopolis by default;
/// [allBranches] for All branches).
Future<DashHarness> pumpTills(
  WidgetTester tester, {
  String query = '',
  String? branchId,
  bool allBranches = false,
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  MockServer? server,
  MockDb? db,
}) => pumpSell(
  tester,
  query.isEmpty ? '/tills' : '/tills?$query',
  persona: persona,
  size: size,
  locale: locale,
  dark: dark,
  branchId: allBranches ? null : (branchId ?? SeedIds.heliopolis),
  server: server,
  db: db,
);

Finder get tillsPage => find.byType(TillsPage);

/// [matching] inside the tills page (the shell has its own words).
Finder inPage(Finder matching) =>
    find.descendant(of: tillsPage, matching: matching);

/// [matching] inside the widget keyed [key].
Finder inKey(String key, Finder matching) =>
    find.descendant(of: find.byKey(ValueKey(key)), matching: matching);

/// The till table.
Finder get tillsTable => find.byKey(const ValueKey('tills-table'));

/// [matching] inside the top dialog / panel / sheet.
Finder inSurface(Finder matching) =>
    find.descendant(of: find.byType(DashSurface).last, matching: matching);

/// [branchId]'s till rows in [db].
List<MockRow> tillsAt(MockDb db, String branchId) =>
    db['tills'].where((t) => t['branch_id'] == branchId).toList();

/// The ids of [branchId]'s open tills.
Set<String> openAt(MockDb db, String branchId) => {
  for (final t in tillsAt(db, branchId))
    if (t['status'] == 'open') t['id']! as String,
};

/// Closes every open till at [branchId] but [keep] (the last-till cases).
void closeOthers(MockDb db, String branchId, String keep) {
  for (final t in tillsAt(db, branchId)) {
    if (t['status'] == 'open' && t['id'] != keep) t['status'] = 'closed';
  }
}

/// Picks [option] in the filter select keyed [key].
Future<void> pickFilter(DashHarness h, String key, String option) async {
  await h.tap(inKey(key, find.byType(DashSelectTrigger)));
  final list = find.byWidgetPredicate((w) => w is DashOptionList);
  await h.tap(find.descendant(of: list, matching: find.text(option)).last);
}

/// The labels the filter select keyed [key] offers ("All …" first).
List<String> filterOptions(DashHarness h, String key) {
  final w = h.tester.widget<DashFilterSelect<String>>(
    find.byKey(ValueKey(key)),
  );
  return [w.allLabel, for (final o in w.options) o.label];
}

/// Opens the "…" menu of [tillId]'s row.
Future<void> openRowMenu(DashHarness h, String tillId) =>
    h.tap(find.byKey(ValueKey('till-actions-$tillId')));

/// The words the open row menu offers.
List<String> menuLabels(DashHarness h, List<String> candidates) => [
  for (final c in candidates)
    if (find.text(c).evaluate().isNotEmpty) c,
];

/// Taps [label] in the open row menu.
Future<void> pickMenu(DashHarness h, String label) =>
    h.tap(find.text(label).last);

/// Taps [label] in the confirm dialog (its button: the title may say the
/// same).
Future<void> confirm(DashHarness h, String label) => h.tap(
  find
      .descendant(
        of: find.byType(DashConfirmDialog),
        matching: find.text(label),
      )
      .last,
);
