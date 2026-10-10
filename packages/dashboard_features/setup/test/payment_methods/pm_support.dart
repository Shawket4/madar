// Shared set-up for the Payment methods tests: the real app shell on the
// seeded mock server at `/settings/payment-methods`.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_setup/src/payment_methods/payment_methods_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

export 'package:dashboard_setup/src/mock/payment_methods_mock.dart'
    show PmRefusals, PmRoutes, PmSeed;

const String pmPath = '/settings/payment-methods';

/// `?branchId=` for [branchId].
String atBranch(String branchId) => '?branchId=$branchId';

final String zamalek = atBranch(SeedIds.zamalek);

/// Opens the page (+ [query]) as [persona].
Future<DashHarness> pumpPm(
  WidgetTester tester, {
  String query = '',
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  ({MockServer server, MockDb db})? backend,
}) => pumpSetup(
  tester,
  path: '$pmPath$query',
  persona: persona,
  size: size,
  locale: locale,
  dark: dark,
  server: backend?.server,
  db: backend?.db,
);

/// [matching] inside the page (not the shell's sidebar or rail).
Finder inPage(Finder matching) =>
    find.descendant(of: find.byType(PaymentMethodsPage), matching: matching);

/// [text] where a tap would land (the open dialog over the page).
Finder top(String text) => find.text(text).hitTestable();

/// The stat card labelled [label].
DashStatCard stat(WidgetTester tester, String label) => tester.widget(
  inPage(
    find.byWidgetPredicate((w) => w is DashStatCard && w.label == label),
  ).first,
);

/// The id of the method named [name] (the core seed's rule).
String pmId(String name) => PmSeedIds.method(name);

abstract final class PmSeedIds {
  static String method(String name) => mockUuid('payment-method:$name');
}

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

/// The allow-list editor with [key] (`allow-list-branch`,
/// `allow-list-user-<id>`, `allow-list-device-<id>`).
Finder editor(String key) => find.byKey(ValueKey(key));

/// [matching] inside the editor [key].
Finder inEditor(String key, Finder matching) =>
    find.descendant(of: editor(key), matching: matching);
