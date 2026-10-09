// Shared set-up for the Organizations tests: the real app shell with the
// admin area, on the seeded mock server (core seed + admin seed).
import 'dart:convert';
import 'dart:typed_data';

import 'package:dashboard_admin/dashboard_admin.dart';
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opens [path] (the Organizations page by default) as [persona] (a
/// platform admin by default: the page is theirs).
Future<DashHarness> pumpOrgs(
  WidgetTester tester, {
  String path = '/orgs',
  Persona? persona = Persona.platform,
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

/// A seeded server with the core's and the admin area's handlers, for a
/// test that changes the data or the answers before the page opens.
({MockServer server, MockDb db}) orgsServer({
  Persona persona = Persona.platform,
}) {
  final db = MockDb.seeded();
  final server = MockServer(persona: persona, clock: db.clock);
  registerCoreMocks(server, db);
  registerAdminMocks(server, db);
  return (server: server, db: db);
}

/// The org rows of [db] (soft-deleted ones included).
List<Org> orgRows(MockDb db) => [
  for (final r in db['orgs'].rows) Org.fromJson(r),
];

Org orgNamed(MockDb db, String name) =>
    orgRows(db).firstWhere((o) => o.name == name);

/// A real 1×1 PNG, for logo uploads.
final Uint8List tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

/// [tinyPng] as base64 (for a `data:` logo address).
String base64Png() => base64Encode(tinyPng);

PickedFile pngFile([String name = 'logo.png']) =>
    PickedFile(name: name, bytes: tinyPng, mimeType: 'image/png');

/// The text field labelled [label] (its EditableText).
Finder fieldByKey(String key) => find.byKey(ValueKey(key));

/// The body of the last call to [template] with [method].
Map<String, Object?> lastBody(
  MockServer server,
  String template, {
  String method = 'POST',
}) {
  final calls = server.callsTo(template, method: method);
  expect(calls, isNotEmpty, reason: 'no $method $template');
  return (calls.last.body! as Map).cast<String, Object?>();
}

/// Text widgets whose text contains [s] (spans included).
Finder textHas(String s) => find.textContaining(s, findRichText: true);
