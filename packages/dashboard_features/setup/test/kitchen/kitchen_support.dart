// Shared set-up for the kitchen tests: the real app shell on the seeded mock
// server at `/settings/kitchen-stations` and `/settings/kitchen-routing`.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_setup/src/kitchen/kitchen_routing_page.dart';
import 'package:dashboard_setup/src/kitchen/kitchen_stations_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

export 'package:dashboard_setup/src/mock/kitchen_mock.dart'
    show KitchenRefusals, KitchenRoutes, KitchenSeed;

export '../support.dart' show setupMockServer;

const String stationsPath = '/settings/kitchen-stations';
const String routingPath = '/settings/kitchen-routing';

/// `?branchId=` for [branchId].
String atBranch(String branchId) => '?branchId=$branchId';

final String zamalek = atBranch(SeedIds.zamalek);
final String maadi = atBranch(SeedIds.maadi);
final String heliopolis = atBranch(SeedIds.heliopolis);

/// A seeded station's id (`zamalek`, `bar`).
String stationId(String branch, String key) =>
    mockUuid('kitchen-station:$branch:$key');

/// Opens [path] (+ [query]) as [persona].
Future<DashHarness> pumpKitchen(
  WidgetTester tester, {
  String path = stationsPath,
  String? query,
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  ({MockServer server, MockDb db})? backend,
}) => pumpSetup(
  tester,
  path: '$path${query ?? zamalek}',
  persona: persona,
  size: size,
  locale: locale,
  dark: dark,
  server: backend?.server,
  db: backend?.db,
);

/// [matching] inside the stations page (not the shell's sidebar or rail).
Finder inStations(Finder matching) =>
    find.descendant(of: find.byType(KitchenStationsPage), matching: matching);

/// [matching] inside the routing page.
Finder inRouting(Finder matching) =>
    find.descendant(of: find.byType(KitchenRoutingPage), matching: matching);

Finder byKey(String k) => find.byKey(ValueKey(k));

/// [text] where a tap would land (the open dialog or sheet over the page).
Finder top(String text) => find.text(text).hitTestable();

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
