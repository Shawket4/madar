// Shared helpers for the links page editor's tests.
import 'dart:convert';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_setup/src/links/links_page.dart';
import 'package:dashboard_setup/src/links/links_preview.dart';
import 'package:dashboard_setup/src/mock/links_mock.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

const String linksPath = '/settings/links';

abstract final class LinksRoutes {
  static const String page = '/orgs/{id}/links-page';
  static const String qr = '/orgs/{id}/links-qr';
  static const String public = '/public/orgs/links';
  static const String menuDisplay = '/orgs/{id}/links-page/menu-display';
}

/// A Free organisation's plan: the floor and nothing else paid.
final Override freePlan = planFeaturesProvider.overrideWith(_FreePlan.new);

class _FreePlan extends PlanFeaturesNotifier {
  @override
  Set<String>? build() => const {'floor'};
}

/// A platform admin's picked org, as the header stores it.
Map<String, String> picked(String orgId) => {
  ScopePrefKeys.org: jsonEncode({'id': orgId}),
};

Future<DashHarness> pumpLinks(
  WidgetTester tester, {
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  ({MockServer server, MockDb db})? backend,
  Map<String, String>? prefs,
  List<Override> overrides = const [],
}) => pumpSetup(
  tester,
  path: linksPath,
  persona: persona,
  size: size,
  locale: locale,
  dark: dark,
  server: backend?.server,
  db: backend?.db,
  prefs: prefs,
  overrides: overrides,
);

Finder inLinks(Finder f) =>
    find.descendant(of: find.byType(LinksPage), matching: f);
Finder inEditor(Finder f) =>
    find.descendant(of: find.byType(LinksEditor), matching: f);
Finder inPreview(Finder f) =>
    find.descendant(of: find.byType(LinksPublicPreview), matching: f);
Finder byKey(String key) => find.byKey(ValueKey(key));
Finder inKey(String key, Finder f) =>
    find.descendant(of: byKey(key), matching: f);

/// The text field under [key] (a `DashTextInput`'s editable).
Finder fieldOf(String key) => inKey(key, find.byType(EditableText));

/// The switch whose label is [label] in the editor.
Finder switchOf(String label) => inEditor(find.bySemanticsLabel(label));

/// Sabah's saved page as the mock holds it.
MockRow sabahPage(MockDb db) => db[linksPagesTable].get(SeedIds.sabahOrg);

/// The JSON body of the last [method] call to [template].
Map<String, Object?> lastBody(DashHarness h, String method, String template) =>
    h.server.callsTo(template, method: method).last.body!
        as Map<String, Object?>;

int gets(DashHarness h, String template) =>
    h.server.callsTo(template, method: 'GET').length;

/// The system clipboard, answered in-process (`refuse` makes it fail).
class FakeClipboard {
  FakeClipboard(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          if (refuse) throw PlatformException(code: 'denied');
          text = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
  }

  String? text;
  bool refuse = false;
}
