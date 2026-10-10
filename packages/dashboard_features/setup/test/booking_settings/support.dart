// Shared set-up for the Bookings settings tests: the real app shell on the
// seeded mock server at `/settings/bookings`, and finders scoped to the
// pane and the rules dialog.
import 'dart:convert';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_setup/src/booking_settings/booking_rules_dialog.dart';
import 'package:dashboard_setup/src/booking_settings/booking_settings_page.dart';
import 'package:dashboard_setup/src/mock/booking_settings_mock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

export 'package:dashboard_setup/src/booking_settings/booking_rules_dialog.dart';
export 'package:dashboard_setup/src/booking_settings/booking_settings_data.dart';
export 'package:dashboard_setup/src/mock/booking_settings_mock.dart';

export '../support.dart' show pumpSetup;

const String bkgPath = '/settings/bookings';
const String bkgSettings = '/bookings/settings';

/// A fresh seeded backend (core + this area) to edit before pumping.
({MockServer server, MockDb db}) bkgServer({Persona persona = Persona.owner}) =>
    setupMockServer(persona: persona);

/// The pane as [persona]. A platform admin works inside Sabah Coffee
/// unless [pickOrg] is false.
Future<DashHarness> pumpBookingRules(
  WidgetTester tester, {
  String query = '',
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  ({MockServer server, MockDb db})? backend,
  bool pickOrg = true,
}) {
  final b = backend ?? bkgServer(persona: persona ?? Persona.owner);
  return pumpSetup(
    tester,
    path: '$bkgPath$query',
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

Finder byKey(String k) => find.byKey(ValueKey(k));

/// [f] inside the pane (not the shell's sidebar or rail).
Finder inPane(Finder f) =>
    find.descendant(of: find.byType(BookingSettingsPage), matching: f);

/// [f] inside the rules dialog.
Finder inRules(Finder f) =>
    find.descendant(of: find.byType(BookingRulesDialog), matching: f);

/// [k] inside the rules dialog.
Finder rulesKey(String k) => inRules(byKey(k));

/// The open option list.
Finder options() => find.byWidgetPredicate((w) => w is DashOptionList<String>);

/// Picks [name] in the branch select.
Future<void> pickBranch(DashHarness h, String name) async {
  await h.tap(byKey('bkg-branch'));
  await h.tap(find.descendant(of: options(), matching: find.text(name)));
}

/// Picks [name] and opens its rules.
Future<void> openRules(DashHarness h, String name) async {
  await pickBranch(h, name);
  await h.tap(byKey('bkg-edit'));
}

/// The rules dialog's Save.
DashButton rulesSave(WidgetTester tester) =>
    tester.widget<DashButton>(rulesKey('bkg-save'));

/// Presses Save and returns the PUT body.
Future<Map<String, Object?>> saveRules(DashHarness h) async {
  await h.tap(rulesKey('bkg-save'));
  return h.server.callsTo(bkgSettings, method: 'PUT').last.body!
      as Map<String, Object?>;
}

/// The stored row of [branchId].
MockRow? storedRules(MockDb db, String branchId) =>
    BookingSettingsMock.row(db, branchId);
