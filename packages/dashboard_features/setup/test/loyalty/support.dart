// Shared set-up for the Loyalty tests: the real app shell on the seeded mock
// server at `/settings/loyalty`, a server whose `/authz/me` grants a chosen
// set of capabilities, and finders scoped to the page, the member card and
// the dialog on top.
import 'dart:convert';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_setup/src/loyalty/loyalty_page.dart';
import 'package:dashboard_setup/src/loyalty/member_sheet.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

import 'package:dashboard_setup/src/mock/loyalty_mock.dart';

export 'package:dashboard_setup/src/mock/loyalty_mock.dart'
    show LoyaltyTables, loyaltySeedRewards;

const String loyaltyPath = '/settings/loyalty';

abstract final class LoyaltyRoutes {
  static const String settings = '/loyalty/settings';
  static const String rewards = '/loyalty/reward-items';
  static const String earning = '/loyalty/earning-items';
  static const String members = '/loyalty/members';
  static const String member = '/loyalty/members/{id}';
  static const String adjust = '/loyalty/adjust';
  static const String analytics = '/loyalty/analytics';
  static const String wallet = '/loyalty/wallet-status';
  static const String preview = '/loyalty/birthday-preview';
  static const String googleObject = '/loyalty/members/{id}/google-object';
  static const String googleRefresh = '/loyalty/members/{id}/google-refresh';
  static const String branchQr = '/branches/{id}/loyalty-qr';
  static const String orgQr = '/orgs/{id}/loyalty-qr';
  static const String menu = '/menu-items';
  static const String customers = '/customers';
}

/// `?branchId=` for [branchId].
String atBranch(String branchId) => '?branchId=$branchId';

/// A fresh seeded backend (core + this area) to edit before pumping.
({MockServer server, MockDb db}) loyaltyServer({
  Persona persona = Persona.owner,
}) => setupMockServer(persona: persona);

/// `/authz/me` grants exactly [caps] (the server's own checks still follow
/// the persona), optionally as a platform admin.
void grantOnly(MockServer server, List<String> caps, {bool platform = false}) {
  final p = server.persona;
  server.on(
    'GET',
    '/authz/me',
    (req) => MockResponse.ok({
      'user_id': p.userId,
      'capabilities': caps,
      'everywhere': caps,
      'ask_manager': <String>[],
      'limits': <String, Object>{},
      'owner': false,
      'platform': platform,
      'role_kinds': p.roleKinds,
      'epoch': 1,
      'spec_version': 2,
    }),
  );
}

/// The Loyalty page (+ [query]) as [persona]. A platform admin works inside
/// Sabah Coffee unless [pickOrg] is false.
Future<DashHarness> pumpLoyalty(
  WidgetTester tester, {
  String query = '',
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  ({MockServer server, MockDb db})? backend,
  bool pickOrg = true,
}) {
  final b = backend ?? loyaltyServer(persona: persona ?? Persona.owner);
  return pumpSetup(
    tester,
    path: '$loyaltyPath$query',
    persona: persona,
    size: size,
    locale: locale,
    dark: dark,
    server: b.server,
    db: b.db,
    prefs: persona == Persona.platform && pickOrg
        ? {
            ScopePrefKeys.org: jsonEncode({'id': SeedIds.sabahOrg}),
          }
        : null,
  );
}

/// [f] inside the page (not the shell's sidebar or rail, not a dialog).
Finder inPage(Finder f) =>
    find.descendant(of: find.byType(LoyaltyPage), matching: f);

/// [text] on the page.
Finder pageText(String text) => inPage(find.text(text));

/// [f] inside the open member card.
Finder inSheet(Finder f) =>
    find.descendant(of: find.byType(MemberSheet), matching: f);

/// [f] inside the top-most dialog / surface.
Finder inDialog(Finder f) =>
    find.descendant(of: find.byType(DashSurface).last, matching: f);

/// The field labelled by wire [key] on the Program tab.
Finder programField(String key) => find.byKey(ValueKey('loyalty-field-$key'));

/// The text input inside [field].
Finder inputOf(Finder field) =>
    find.descendant(of: field, matching: find.byType(EditableText));

/// Opens a tab by its label.
Future<void> openTab(DashHarness h, String label) => h.tap(
  find.descendant(
    of: find.byKey(const ValueKey('loyalty-tabs')),
    matching: find.text(label),
  ),
);

/// The [DashButton] with [key].
DashButton buttonAt(WidgetTester tester, String key) =>
    tester.widget<DashButton>(find.byKey(ValueKey(key)));

/// The toggle labelled [label] on the page (the pressable row).
Finder toggle(String label) => inPage(
  find.byWidgetPredicate(
    (w) => w is DashPressable && w.semanticLabel == label && w.checked != null,
  ),
);

/// Whether the toggle labelled [label] is on.
bool toggleOn(WidgetTester tester, String label) =>
    tester.widget<DashPressable>(toggle(label).first).checked ?? false;

/// The query of [call] as single values.
Map<String, String> q1(MockCall call) => {
  for (final e in call.query.entries) e.key: e.value.single,
};

/// The JSON body of [call].
Map<String, Object?> bodyOf(MockCall call) =>
    (call.body! as Map).cast<String, Object?>();

/// The org's own settings row (or [branchId]'s).
MockRow settingsRow(MockDb db, [String? branchId]) =>
    db[LoyaltyTables.settings].rows.firstWhere(
      (r) => r['org_id'] == SeedIds.sabahOrg && r['branch_id'] == branchId,
    );

/// The prefixes every bus invalidation named, in order.
List<List<String>> watchInvalidations(DashHarness h) {
  final seen = <List<String>>[];
  final sub = h.container
      .read(realtimeBusProvider)
      .invalidations
      .listen(seen.add);
  addTearDown(sub.cancel);
  return seen;
}

/// The seed customer named [name].
MockRow customerNamed(MockDb db, String name) =>
    db['customers'].rows.firstWhere((c) => c['name'] == name);

/// Nada Kamal: the seed's first customer, a member with a hand-made stamp.
String get nadaId => MockSeed.customerId(0);
