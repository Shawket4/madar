// Shared set-up for Today's tests: the real app shell with the inventory
// area on the seeded mock server, and the figures a test checks the page
// against, worked out here from the raw seeded rows (never through the
// mock's own views).
import 'dart:convert';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_inventory/dashboard_inventory.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const String todayPath = '/inventory/today';

/// Today with [branchId] picked (a deep link, as the web's `?branchId=`).
String todayAt(String branchId) => '$todayPath?branchId=$branchId';

// Route templates.
const String branchValuation =
    '/reports/branches/{branch_id}/inventory-valuation';
const String orgValuation = '/reports/orgs/{org_id}/inventory-valuation';
const String branchLow = '/reports/branches/{branch_id}/low-stock';
const String orgLow = '/reports/orgs/{org_id}/low-stock';
const String orgOrders = '/purchasing/orgs/{org_id}/orders';
const String suppliersRoute = '/purchasing/orgs/{org_id}/suppliers';
const String catalogRoute = '/inventory/orgs/{org_id}/catalog';
const String stockRoute = '/inventory/branches/{branch_id}/stock';
const String stocktakesRoute = '/stocktakes/branches/{branch_id}';
const String wasteRoute = '/inventory/branches/{branch_id}/waste';

/// End of 2026-10-08 in Cairo, the seed's today.
const String endOfToday = '2026-10-08T20:59:59.999Z';

/// Start of 2026-10-08 in Cairo.
const String startOfToday = '2026-10-07T21:00:00.000Z';

/// Opens [path] (Today by default) as [persona], with [branch] picked.
Future<DashHarness> pumpToday(
  WidgetTester tester, {
  String path = todayPath,
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  MockServer? server,
  MockDb? db,
  Map<String, String>? prefs,
  String? branch,
  bool reducedMotion = true,
}) => DashHarness.pump(
  tester,
  areas: const [inventoryArea],
  path: path,
  persona: persona,
  size: size,
  locale: locale,
  dark: dark,
  server: server,
  db: db,
  prefs: {...?prefs, if (branch != null) ...branchPicked(branch)},
  reducedMotion: reducedMotion,
);

/// The stored scope with [branchId] picked in Sabah (what the branch picker
/// leaves behind), so the page opens on that branch from its first frame.
Map<String, String> branchPicked(String branchId) => {
  ScopePrefKeys.branch: jsonEncode({
    'org': SeedIds.sabahOrg,
    'branch': branchId,
  }),
};

/// A seeded server with the core's and the inventory area's handlers, for a
/// test that changes the data or the answers before the page opens.
({MockServer server, MockDb db}) todayServer({
  Persona persona = Persona.owner,
}) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  registerInventoryMocks(server, db);
  return (server: server, db: db);
}

/// A platform admin's preferences with Sabah picked.
Map<String, String> sabahPicked() => {
  ScopePrefKeys.org: jsonEncode({'id': SeedIds.sabahOrg}),
};

/// The KPI card labelled [label].
DashStatCard kpi(WidgetTester tester, String label) => tester.widget(
  find.byWidgetPredicate((w) => w is DashStatCard && w.label == label).first,
);

/// Text widgets whose text contains [s] (spans included).
Finder textHas(String s) => find.textContaining(s, findRichText: true);

/// The widget keyed [key] (a string key).
Finder byKey(String key) => find.byKey(ValueKey(key));

// ── Figures from the raw rows ──────────────────────────────────────────────

/// A seeded ingredient row by its seed key.
MockRow ingredientRow(MockDb db, String key) =>
    db[InvTables.ingredients].find(InvIds.ingredient(key))!;

/// The stock record of [branchId] × ingredient [key].
MockRow? stockRow(MockDb db, String branchId, String key) =>
    db[InvTables.branchStock].firstWhere(
      (r) =>
          r['branch_id'] == branchId &&
          r['org_ingredient_id'] == InvIds.ingredient(key),
    );

/// Stock value over [branchIds]: per ingredient, Σ on hand × (branch cost,
/// else catalog cost), rounded; an ingredient with no cost is unknown.
({int total, int unknown}) stockValue(MockDb db, List<String> branchIds) {
  final per = <String, (double, bool)>{};
  for (final bs in db[InvTables.branchStock].rows) {
    if (!branchIds.contains(bs['branch_id'])) continue;
    final ing = db[InvTables.ingredients].find(
      bs['org_ingredient_id']! as String,
    )!;
    final cost =
        (bs['cost_per_unit'] as num?) ?? (ing['cost_per_unit'] as num?);
    final id = ing['id']! as String;
    final (v, known) = per[id] ?? (0.0, true);
    per[id] = cost == null
        ? (v, false)
        : (v + (bs['on_hand']! as num) * cost, known);
  }
  var total = 0;
  var unknown = 0;
  for (final (v, known) in per.values) {
    if (known) {
      total += (v + 0.5).floor();
    } else {
      unknown++;
    }
  }
  return (total: total, unknown: unknown);
}

/// Low-stock rows of [branchIds]: par_min > 0 and on hand at or under it.
List<MockRow> lowRowsOf(MockDb db, List<String> branchIds) => [
  for (final bs in db[InvTables.branchStock].rows)
    if (branchIds.contains(bs['branch_id']) &&
        ((bs['par_min'] as num?) ?? 0) > 0 &&
        (bs['on_hand']! as num) <= (bs['par_min']! as num))
      bs,
];

/// Catalog rows [branchId] has never counted or counted over 14 days
/// before [now].
int countsDueAt(MockDb db, String branchId, DateTime now) {
  var n = 0;
  for (final i in db[InvTables.ingredients].where(
    (r) => r['org_id'] == SeedIds.sabahOrg,
  )) {
    final bs = db[InvTables.branchStock].firstWhere(
      (r) => r['branch_id'] == branchId && r['org_ingredient_id'] == i['id'],
    );
    final at = bs?['last_counted_at'] as String?;
    if (at == null ||
        now.difference(DateTime.parse(at)) > const Duration(days: 14)) {
      n++;
    }
  }
  return n;
}

/// Puts [branchId] × ingredient [key] at [onHand] with pars [parMin] /
/// [parMax] (creating the stock record when the branch has none).
void setStock(
  MockDb db,
  String branchId,
  String key, {
  required double onHand,
  double? parMin,
  double? parMax,
}) {
  final existing = stockRow(db, branchId, key);
  final patch = {
    'on_hand': onHand,
    'par_min': ?parMin,
    'par_max': ?parMax,
  };
  if (existing != null) {
    db[InvTables.branchStock].update(existing['id']! as String, patch);
  } else {
    db[InvTables.branchStock].insert({
      'id': mockUuid('test-stock:$branchId:$key'),
      'branch_id': branchId,
      'org_ingredient_id': InvIds.ingredient(key),
      'cost_per_unit': null,
      'last_counted_at': null,
      'last_movement_at': null,
      'par_min': null,
      'par_max': null,
      ...patch,
    }, timestamps: false);
  }
}

/// Adds a purchase order of [branchId] due at [expectedAt] in [status].
MockRow addOrder(
  MockDb db, {
  required String key,
  required String branchId,
  required String status,
  String? expectedAt = endOfToday,
  String? reference,
  String? supplierKey = 'metro',
}) => db[InvTables.purchaseOrders].insert({
  'id': InvIds.purchaseOrder(key),
  'org_id': SeedIds.sabahOrg,
  'branch_id': branchId,
  'supplier_id': supplierKey == null ? null : InvIds.supplier(supplierKey),
  'status': status,
  'reference': reference,
  'expected_at': expectedAt,
  'created_by': SeedIds.owner,
  'created_at': '2026-10-07T09:00:00.000Z',
  'updated_at': '2026-10-07T09:00:00.000Z',
  'received_at': null,
  'received_by': null,
  'note': null,
}, timestamps: false);

/// Adds a waste line at [branchId] the server received at [createdAt].
MockRow addWaste(
  MockDb db, {
  required String key,
  required String branchId,
  required String ingredientKey,
  required double qty,
  required String createdAt,
  String? occurredAt,
  String? reason = 'expired',
}) {
  final ing = ingredientRow(db, ingredientKey);
  return db[InvTables.movements].insert({
    'id': mockUuid('test-waste:$key'),
    'branch_id': branchId,
    'branch_name': null,
    'branch_stock_id': null,
    'org_ingredient_id': ing['id'],
    'ingredient_name': ing['name'],
    'unit': ing['unit'],
    'movement_type': 'waste',
    'quantity': -qty,
    'balance_after': 0.0,
    'below_zero': false,
    'reason': reason,
    'note': null,
    'unit_cost': ing['cost_per_unit'] == null
        ? null
        : (ing['cost_per_unit']! as num).round(),
    'created_at': createdAt,
    'occurred_at': occurredAt,
    'received_at': createdAt,
    'created_by': SeedIds.owner,
    'created_by_name': 'Nour El-Sayed',
    'waste_source': 'dashboard',
    'source_type': null,
  }, timestamps: false);
}
