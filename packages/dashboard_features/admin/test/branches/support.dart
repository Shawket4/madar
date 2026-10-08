// Shared set-up for the Branches unit's tests: the real app shell with the
// admin area, on the seeded mock server.
import 'package:dashboard_admin/dashboard_admin.dart';
import 'package:dashboard_api/dashboard_api.dart' show Branch;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

export 'package:dashboard_kit/testing.dart' show DashSize;

const branchesPath = '/branches';
const listRoute = '/branches';
const itemRoute = '/branches/{id}';

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
  areas: const [adminArea],
  path: path,
  persona: persona,
  size: size,
  locale: locale,
  dark: dark,
  server: server,
  db: db,
);

/// A seeded server with the core's and the admin area's handlers, for a test
/// that changes the data or the answers before the page opens.
({MockServer server, MockDb db}) branchesServer({
  Persona persona = Persona.owner,
}) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  registerAdminMocks(server, db);
  return (server: server, db: db);
}

/// Sabah's branch row [id] in [db].
Map<String, Object?> branchRow(MockDb db, String id) => db['branches'].get(id);

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
  for (final r in db['tills'].where(
    (r) => r['branch_id'] == id && r['closed_at'] == null,
  )) {
    r['closed_at'] = db.nowIso;
    r['status'] = 'closed';
  }
}

/// The table row (or phone card) of the branch named [name].
Finder rowOf(String name) => find.ancestor(
  of: find.text(name),
  matching: find.byWidgetPredicate(
    (w) => w.runtimeType.toString().startsWith('DashPressable'),
  ),
);

/// The control a screen reader calls [label] inside [within].
Finder labelled(String label, {Finder? within}) => within == null
    ? find.bySemanticsLabel(label)
    : find.descendant(of: within, matching: find.bySemanticsLabel(label));

/// The field with [key] (its editable text).
Finder field(String key) => find.descendant(
  of: find.byKey(ValueKey(key)),
  matching: find.byType(EditableText),
);
