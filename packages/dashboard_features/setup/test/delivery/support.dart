// Shared set-up for the Delivery settings and zones tests: the real app
// shell on the seeded mock server at `/settings/delivery` and
// `/settings/delivery-zones`.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_setup/src/delivery/delivery_settings_page.dart';
import 'package:dashboard_setup/src/delivery/delivery_zones_page.dart';
import 'package:dashboard_setup/src/delivery/zone_dialog.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

export 'package:dashboard_setup/src/mock/delivery_mock.dart'
    show DeliveryRoutes, DeliverySeed;

const String settingsPath = '/settings/delivery';
const String zonesPath = '/settings/delivery-zones';

/// `?branchId=` for [branchId].
String atBranch(String branchId) => '?branchId=$branchId';

/// Opens [path] (+ [query]) as [persona].
Future<DashHarness> pumpDelivery(
  WidgetTester tester, {
  String path = settingsPath,
  String query = '',
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  ({MockServer server, MockDb db})? backend,
}) => pumpSetup(
  tester,
  path: '$path$query',
  persona: persona,
  size: size,
  locale: locale,
  dark: dark,
  server: backend?.server,
  db: backend?.db,
);

/// [matching] inside the settings pane (not the shell's sidebar or rail).
Finder inSettings(Finder matching) =>
    find.descendant(of: find.byType(DeliverySettingsPage), matching: matching);

/// [matching] inside the zones pane.
Finder inZones(Finder matching) =>
    find.descendant(of: find.byType(DeliveryZonesPage), matching: matching);

/// [matching] inside the open zone dialog.
Finder inDialog(Finder matching) =>
    find.descendant(of: find.byType(ZoneDialog), matching: matching);

Finder byKey(String key) => find.byKey(ValueKey(key));

/// [matching] inside the widget keyed [key].
Finder inKey(String key, Finder matching) =>
    find.descendant(of: byKey(key), matching: matching);

/// Types [text] into the field keyed [key] and presses Done (the field
/// settles what was typed).
Future<void> typeIn(DashHarness h, String key, String text) async {
  await h.tester.ensureVisible(byKey(key));
  await h.enterText(byKey(key), text);
  // Leaving the field settles it; Enter would submit the form ([enterIn]).
  FocusManager.instance.primaryFocus?.unfocus();
  await h.settle();
}

/// Types [text] into the field keyed [key], then presses Enter.
Future<void> enterIn(DashHarness h, String key, String text) async {
  await h.tester.ensureVisible(byKey(key));
  await h.enterText(byKey(key), text);
  await h.tester.testTextInput.receiveAction(TextInputAction.done);
  await h.settle();
}

/// The text the field keyed [key] shows.
String fieldText(WidgetTester tester, String key) => tester
    .widget<EditableText>(
      find.descendant(of: byKey(key), matching: find.byType(EditableText)),
    )
    .controller
    .text;

/// The prefixes every invalidation on the realtime bus named, in order.
List<List<String>> watchInvalidations(DashHarness h) {
  final seen = <List<String>>[];
  final sub = h.container
      .read(realtimeBusProvider)
      .invalidations
      .listen(seen.add);
  addTearDown(sub.cancel);
  return seen;
}

/// The last request's JSON body to [method] [template].
Map<String, Object?> lastBody(DashHarness h, String method, String template) {
  final calls = h.server
      .callsTo(template)
      .where((c) => c.method == method)
      .toList();
  expect(calls, isNotEmpty, reason: '$method $template');
  return Map<String, Object?>.from(calls.last.body! as Map);
}

/// Requests to [method] [template] so far.
int countCalls(DashHarness h, String method, String template) =>
    h.server.callsTo(template).where((c) => c.method == method).length;
