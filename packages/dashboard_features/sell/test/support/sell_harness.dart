// Test support for the sell area: the whole app on the mock server with the
// sell area mounted, optionally with a branch already picked.
import 'dart:convert';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_sell/dashboard_sell.dart';
import 'package:flutter_test/flutter_test.dart';

/// The scope preference that picks [branchId] of Sabah Coffee (the top
/// bar's branch picker, remembered).
Map<String, String> branchPrefs(String branchId, {String? orgId}) => {
  ScopePrefKeys.branch: jsonEncode({
    'org': orgId ?? SeedIds.sabahOrg,
    'branch': branchId,
  }),
};

/// [DashHarness.pump] with the sell area; [branchId] picks a branch (null =
/// All branches). Screenshots go to `<FDASH_SHOTS>/sell/…`.
Future<DashHarness> pumpSell(
  WidgetTester tester,
  String path, {
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  String? branchId,
  Map<String, String>? prefs,
  MockServer? server,
  MockDb? db,
}) => DashHarness.pump(
  tester,
  areas: const [sellArea],
  path: path,
  persona: persona,
  size: size,
  locale: locale,
  dark: dark,
  server: server,
  db: db,
  prefs: {
    if (branchId != null) ...branchPrefs(branchId),
    ...?prefs,
  },
);
