// Shared set-up for the Staff drinks tests: the real app shell on the
// seeded mock server at `/settings/staff-pool`, a server whose `/authz/me`
// grants a chosen set of capabilities, and finders scoped to the pane.
import 'dart:convert';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_setup/src/mock/staff_pool_mock.dart';
import 'package:dashboard_setup/src/staff_pool/staff_pool_settings_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

export 'package:dashboard_setup/src/mock/staff_pool_mock.dart';

const String splPath = '/settings/staff-pool';
const String splSettings = '/staff-pool/settings';
const String splMenu = '/menu-items';

/// `?branchId=` for [branchId].
String atBranch(String branchId) => '?branchId=$branchId';

/// A fresh seeded backend (core + this area) to edit before pumping.
({MockServer server, MockDb db}) splServer({
  Persona persona = Persona.owner,
}) => setupMockServer(persona: persona);

/// `/authz/me` grants exactly [caps] (the server's own checks still follow
/// the persona).
void grantOnly(MockServer server, List<String> caps) {
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
      'platform': false,
      'role_kinds': p.roleKinds,
      'epoch': 1,
      'spec_version': 2,
    }),
  );
}

/// The pane (+ [query]) as [persona]. A platform admin works inside Sabah
/// Coffee unless [pickOrg] is false.
Future<DashHarness> pumpStaffPool(
  WidgetTester tester, {
  String query = '',
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  ({MockServer server, MockDb db})? backend,
  bool pickOrg = true,
}) {
  final b = backend ?? splServer(persona: persona ?? Persona.owner);
  return pumpSetup(
    tester,
    path: '$splPath$query',
    persona: persona,
    size: size,
    locale: locale,
    dark: dark,
    server: b.server,
    db: b.db,
    prefs: persona == Persona.platform && pickOrg
        ? {ScopePrefKeys.org: jsonEncode({'id': SeedIds.sabahOrg})}
        : null,
  );
}

/// [f] inside the pane (not the shell's sidebar or rail, not a dialog).
Finder inPane(Finder f) =>
    find.descendant(of: find.byType(StaffPoolSettingsPage), matching: f);

/// [text] on the pane.
Finder paneText(String text) => inPane(find.text(text));

/// [f] inside the top-most dialog / surface.
Finder inDialog(Finder f) =>
    find.descendant(of: find.byType(DashSurface).last, matching: f);

/// The picker list (popover or sheet).
Finder inPicker(Finder f) =>
    find.descendant(of: find.byKey(const ValueKey('spl-picker')), matching: f);

/// The [DashButton] with [key].
DashButton buttonAt(WidgetTester tester, String key) =>
    tester.widget<DashButton>(find.byKey(ValueKey(key)));

/// The allowance input.
Finder allowanceInput() => find.descendant(
  of: find.byKey(const ValueKey('spl-allowance')),
  matching: find.byType(EditableText),
);

/// The settings row the server holds for [branchId] (null = the org's).
MockRow? savedRow(MockDb db, String? branchId) =>
    StaffPoolSettingsMock.own(db, SeedIds.sabahOrg, branchId);

/// A Sabah menu item's id by seed key.
String itemId(String key) => MockSeed.menuItemId(key);

/// The seed item [key].
SeedItem seedItem(String key) => seedMenu.firstWhere((m) => m.key == key);

/// The seed item's name in [lang].
String itemName(String key, [String lang = 'en']) =>
    lang == 'ar' ? seedItem(key).ar : seedItem(key).name;
