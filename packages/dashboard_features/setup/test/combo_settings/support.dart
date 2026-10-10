// Shared set-up for the Combos and deals settings tests: the real app shell
// on the seeded mock server at `/settings/combos`, a server whose
// `/authz/me` grants a chosen set of capabilities, and finders scoped to
// the pane.
import 'dart:convert';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_setup/src/combo_settings/combo_settings_data.dart';
import 'package:dashboard_setup/src/combo_settings/combo_settings_page.dart';
import 'package:dashboard_setup/src/mock/combo_settings_mock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

export 'package:dashboard_setup/src/combo_settings/combo_settings_data.dart';
export 'package:dashboard_setup/src/mock/combo_settings_mock.dart';

export '../support.dart' show pumpSetup;

const String cmbPath = '/settings/combos';
const String cmbSettings = '/settings/combos';
const String cmbBranch = '/settings/combos/branches/{branch_id}';

/// A fresh seeded backend (core + this area) to edit before pumping.
({MockServer server, MockDb db}) cmbServer({Persona persona = Persona.owner}) =>
    setupMockServer(persona: persona);

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

/// The pane as [persona]. A platform admin works inside Sabah Coffee
/// unless [pickOrg] is false.
Future<DashHarness> pumpCombos(
  WidgetTester tester, {
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  ({MockServer server, MockDb db})? backend,
  bool pickOrg = true,
}) {
  final b = backend ?? cmbServer(persona: persona ?? Persona.owner);
  return pumpSetup(
    tester,
    path: cmbPath,
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

/// [f] inside the pane (not the shell's sidebar or rail, not a popover).
Finder inPane(Finder f) =>
    find.descendant(of: find.byType(ComboSettingsPage), matching: f);

/// [text] on the pane.
Finder paneText(String text) => inPane(find.text(text));

Finder byKey(String k) => find.byKey(ValueKey(k));

/// The org switch of [channel].
Finder sellSwitch(ComboChannel channel) => find.descendant(
  of: byKey('cmb-sell-${channel.name}'),
  matching: find.byType(DashSwitch),
);

/// The margin input's editable text.
Finder marginInput() => find.descendant(
  of: byKey('cmb-margin'),
  matching: find.byType(EditableText),
);

/// [branchId]'s select for [channel].
Finder cell(String branchId, ComboChannel channel) =>
    byKey('cmb-cell-$branchId-${channel.name}');

DashSelect<ComboTri> cellWidget(
  WidgetTester tester,
  String branchId,
  ComboChannel channel,
) => tester.widget<DashSelect<ComboTri>>(cell(branchId, channel));

/// The open option list.
Finder options() =>
    find.byWidgetPredicate((w) => w is DashOptionList<ComboTri>);

/// Opens [branchId]'s [channel] cell and picks [label].
Future<void> pickCell(
  DashHarness h,
  String branchId,
  ComboChannel channel,
  String label,
) async {
  await h.tap(cell(branchId, channel));
  await h.tap(find.descendant(of: options(), matching: find.text(label)));
}

/// The Save button.
DashButton saveButton(WidgetTester tester) =>
    tester.widget<DashButton>(byKey('cmb-save'));

/// The org's stored minimum margin.
Object? storedMargin(MockDb db) =>
    db[ComboSettingsMock.margins].find(SeedIds.sabahOrg)?['combo_min_margin'];

/// The stored override of [branchId], or null.
MockRow? storedOverride(MockDb db, String branchId) =>
    db[ComboSettingsMock.branchChannels].find(branchId);
