// Shared set-up for the QR page's tests: the real app shell on the seeded
// mock server at `/settings/qr`, finders scoped to the page and to one card.
import 'dart:convert';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_setup/src/qr/qr_page.dart';
import 'package:dashboard_setup/src/qr/qr_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

export 'package:dashboard_setup/src/mock/qr_mock.dart';
export 'package:dashboard_setup/src/mock/support.dart' show mockQrResponse;
export 'package:dashboard_setup/src/qr/qr_providers.dart';

export '../support.dart' show setupMockServer;

const String qrPath = '/settings/qr';

abstract final class QrRoutes {
  static const String orgQr = '/orgs/{id}/qr';
  static const String orgBooking = '/orgs/{id}/booking-qr';
  static const String branchQr = '/branches/{id}/qr';
  static const String branchBooking = '/branches/{id}/booking-qr';
  static const String tables = '/branches/{id}/tables';
  static const String tableQr = '/branches/{id}/tables/{tid}/qr';
}

/// `?branchId=` for [branchId] (empty = All branches).
String atBranch(String branchId) => '?branchId=$branchId';

/// The QR page (+ [query]) as [persona]. A platform admin works inside
/// Sabah Coffee unless [pickOrg] is false.
Future<DashHarness> pumpQr(
  WidgetTester tester, {
  String query = '',
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  ({MockServer server, MockDb db})? backend,
  bool pickOrg = true,
}) {
  final b = backend ?? setupMockServer(persona: persona ?? Persona.owner);
  return pumpSetup(
    tester,
    path: '$qrPath$query',
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

/// Moves the header scope to [branchId] (null = All branches).
Future<void> pickBranch(DashHarness h, String? branchId) async {
  await h.container.read(scopeProvider.notifier).setBranch(branchId);
  await h.settle();
}

/// [f] inside the page (not the shell's sidebar or rail, not a dialog).
Finder inQr(Finder f) => find.descendant(of: find.byType(QrPage), matching: f);

/// [f] inside [kind]'s card.
Finder inKind(QrKind kind, Finder f) => find.descendant(
  of: find.byKey(ValueKey('qr-kind-${kind.name}')),
  matching: f,
);

/// [f] inside the table codes card.
Finder inTables(Finder f) =>
    find.descendant(of: find.byKey(const ValueKey('qr-tables')), matching: f);

/// [kind]'s Generate button.
Finder generateOf(QrKind kind) =>
    find.byKey(ValueKey('qr-generate-${kind.name}'));

/// [kind]'s result card.
Finder resultOf(QrKind kind) => find.byKey(ValueKey('qr-result-${kind.name}'));

/// The query [call] sent, one value per key.
Map<String, String> queryOf(MockCall call) => {
  for (final e in call.query.entries) e.key: e.value.single,
};
