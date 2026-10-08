// Shared set-up for the shell's tests: the whole app with every area.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/shell.dart' show DashSidebar;
import 'package:dashboard_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madar_dashboard/areas.dart';

Future<DashHarness> pumpShell(
  WidgetTester tester, {
  String path = '/',
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  Map<String, String>? prefs,
}) => DashHarness.pump(
  tester,
  areas: dashboardAreas,
  path: path,
  persona: persona,
  size: size,
  locale: locale,
  dark: dark,
  prefs: prefs,
  shotArea: 'shell',
);

/// The text widget showing exactly [text] (a nav row, a label).
Finder text(String text) => find.text(text);

/// [text] in the sidebar (the page under it has words of its own).
Finder navText(String text) =>
    find.descendant(of: find.byType(DashSidebar), matching: find.text(text));

/// The control a screen reader calls [label].
Finder labelled(String label) => find.bySemanticsLabel(label);

/// Every handler the app answers with (the core's and each area's), for a
/// test that builds its own server: the home page asks the areas too.
void registerAppMocks(MockServer server, MockDb db) {
  registerCoreMocks(server, db);
  for (final a in dashboardAreas) {
    a.registerMocks?.call(server, db);
  }
}
