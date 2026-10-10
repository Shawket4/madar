// Shared set-up for the combo editor's tests: the page through the real
// shell on the mock server, a server whose `/authz/me` grants a chosen set
// of capabilities, and finders scoped to the editor.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_offers/dashboard_catalog_offers.dart';
import 'package:dashboard_catalog_offers/src/area_seed.dart';
import 'package:dashboard_catalog_offers/src/combo_editor/combo_editor_page.dart';
import 'package:dashboard_core/dashboard_core.dart'
    show PickedFile, ScopePrefKeys;
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The seeded combos' editor paths.
String comboPath(String key) => '/menu/combos/${OffersSeed.comboId(key)}';

const String newComboPath = '/menu/combos/new';

/// A seeded server (owner by default).
({MockServer server, MockDb db}) editorServer({
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
({MockServer server, MockDb db}) editorServerWithCaps(
  List<String> caps, {
  Persona persona = Persona.owner,
}) {
  final s = editorServer(persona: persona);
  s.server.on(
    'GET',
    '/authz/me',
    (req) => MockResponse.ok({
      'user_id': persona.userId,
      'capabilities': caps,
      'everywhere': caps,
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

/// The editor at [path].
Future<DashHarness> pumpEditor(
  WidgetTester tester, {
  String path = newComboPath,
  Persona persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  MockServer? server,
  MockDb? db,
  String? branch,
}) async {
  final h = await DashHarness.pump(
    tester,
    areas: const [catalogOffersArea],
    path: path,
    persona: persona,
    size: size,
    locale: locale,
    dark: dark,
    server: server,
    db: db,
    prefs: {
      if (branch != null)
        ScopePrefKeys.branch: jsonEncode({
          'org': SeedIds.sabahOrg,
          'branch': branch,
        }),
    },
  );
  // The price check asks 450 ms after the form settles.
  await debounce(h);
  return h;
}

/// Lets the price check's debounce run out and its answer land.
Future<void> debounce(DashHarness h) async {
  await h.tester.pump(const Duration(milliseconds: 500));
  await h.settle();
}

/// The editor page.
Finder get editor => find.byType(ComboEditorPage);

/// [matching] inside the editor.
Finder inEditor(Finder matching) =>
    find.descendant(of: editor, matching: matching);

/// The control a screen reader calls [label], inside the editor.
Finder labelled(String label) => inEditor(find.bySemanticsLabel(label));

/// A select's trigger ("label: value").
Finder labelledSelect(String label) =>
    inEditor(find.bySemanticsLabel(RegExp('^${RegExp.escape(label)}: ')));

/// The nearest [type] around [of] (a kit control around its semantics).
Finder around(Finder of, Type type) =>
    find.ancestor(of: of, matching: find.byType(type)).first;

/// [text] inside the editor.
Finder editorText(String text) => inEditor(find.text(text));

/// Types [text] into the field a screen reader calls [label] ([index]th).
Future<void> typeInto(
  DashHarness h,
  String label,
  String text, {
  int index = 0,
}) async {
  final field = labelled(label).at(index);
  await h.tester.ensureVisible(field);
  await h.enterText(field, text);
  await debounce(h);
}

/// Taps the control a screen reader calls [label] ([index]th) in the
/// editor.
Future<void> tapLabelled(DashHarness h, String label, {int index = 0}) =>
    h.tap(labelled(label).at(index));

/// Every POST/PUT body sent to [template].
List<Map<String, Object?>> bodiesTo(
  DashHarness h,
  String template, {
  String method = 'POST',
}) => [
  for (final c in h.server.callsTo(template, method: method))
    (c.body! as Map).cast<String, Object?>(),
];

/// Opens the select a screen reader calls [label] ([index]th).
Future<void> openSelect(DashHarness h, String label, {int index = 0}) async {
  final trigger = labelledSelect(label).at(index);
  await h.tester.ensureVisible(trigger);
  await h.tap(trigger);
}

/// The open option list.
Finder get optionList => find.byWidgetPredicate((w) => w is DashOptionList);

/// Picks [text] in the open option list ([search] typed first when the list
/// has a search box).
Future<void> pickOption(DashHarness h, String text, {String? search}) async {
  if (search != null) {
    await h.enterText(
      find.descendant(of: optionList, matching: find.byType(EditableText)),
      search,
    );
  }
  await h.tap(find.descendant(of: optionList, matching: find.text(text)).last);
  await debounce(h);
}

/// Opens the [index]th select called [label] and picks [text].
Future<void> choose(
  DashHarness h,
  String label,
  String text, {
  int index = 0,
  String? search,
}) async {
  await openSelect(h, label, index: index);
  await pickOption(h, text, search: search);
}

/// A 1×1 PNG.
final Uint8List tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

PickedFile pngFile([String name = 'meal.png']) =>
    PickedFile(name: name, bytes: tinyPng, mimeType: 'image/png');
