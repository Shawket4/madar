// Shared set-up for the Integrations tests: the real app shell on the seeded
// mock server at `/settings/integrations`.
import 'dart:convert';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_setup/src/integrations/integrations_page.dart';
import 'package:dashboard_setup/src/mock/integrations_mock.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

export 'package:dashboard_setup/src/mock/integrations_mock.dart';

const String intPath = '/settings/integrations';

/// A seeded server signed in as [persona].
({MockServer server, MockDb db}) integrationsServer({
  Persona persona = Persona.owner,
}) => setupMockServer(persona: persona);

/// The pane (+ [query]) as [persona]. A platform admin works inside Sabah
/// Coffee unless [pickOrg] is false.
Future<DashHarness> pumpIntegrations(
  WidgetTester tester, {
  String query = '',
  Persona persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  ({MockServer server, MockDb db})? backend,
  bool pickOrg = true,
}) {
  final b = backend ?? integrationsServer(persona: persona);
  return pumpSetup(
    tester,
    path: '$intPath$query',
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
Finder inPage(Finder f) =>
    find.descendant(of: find.byType(IntegrationsPage), matching: f);

/// [text] on the pane.
Finder pageText(String text) => inPage(find.text(text));

/// [text] where a tap would land (an open dialog over the pane).
Finder top(String text) => find.text(text).hitTestable();

/// The stat card with [key] (`integrations-total|active|revoked`).
DashStatCard stat(WidgetTester tester, String key) =>
    tester.widget(find.byKey(ValueKey(key)));

/// [text] inside the credentials table.
Finder inTable(Finder f) => find.descendant(
  of: find.byKey(const ValueKey('integrations-table')),
  matching: f,
);

/// The GET calls to the list.
int listCalls(DashHarness h) => h.server
    .callsTo(IntegrationsRoutes.list)
    .where((c) => c.method == 'GET')
    .length;

/// The system clipboard, kept in memory; [refuse] makes it throw.
class FakeClipboard {
  FakeClipboard(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          if (refuse) throw PlatformException(code: 'denied');
          text = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
  }

  String? text;
  bool refuse = false;
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
