// Shared set-up for the WhatsApp tests: the real app shell on the seeded
// mock server at `/settings/whatsapp`, as the platform admin by default.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_setup/src/whatsapp/whatsapp_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

export 'package:dashboard_setup/src/mock/whatsapp_mock.dart';

const String waPath = '/settings/whatsapp';
const String waStatus = '/whatsapp/status';
const String waPair = '/whatsapp/pair';
const String waLogout = '/whatsapp/logout';
const String waPause = '/whatsapp/pause';

/// A seeded server signed in as [persona] (the gateway linked and sending).
({MockServer server, MockDb db}) whatsappServer({
  Persona persona = Persona.platform,
}) => setupMockServer(persona: persona);

/// The pane as [persona].
Future<DashHarness> pumpWhatsapp(
  WidgetTester tester, {
  Persona persona = Persona.platform,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  ({MockServer server, MockDb db})? backend,
}) {
  final b = backend ?? whatsappServer(persona: persona);
  return pumpSetup(
    tester,
    path: waPath,
    persona: persona,
    size: size,
    locale: locale,
    dark: dark,
    server: b.server,
    db: b.db,
  );
}

/// [f] inside the pane (not the shell's sidebar or rail, not a dialog).
Finder inPage(Finder f) =>
    find.descendant(of: find.byType(WhatsappPage), matching: f);

/// [text] on the pane.
Finder pageText(String text) => inPage(find.text(text));

/// [text] where a tap would land (an open dialog over the pane).
Finder top(String text) => find.text(text).hitTestable();

/// The GET calls to the status.
int statusReads(DashHarness h) =>
    h.server.callsTo(waStatus, method: 'GET').length;

/// The connection pill's words.
String pill(WidgetTester tester) => tester
    .widget<DashStatusPill>(
      inPage(find.byKey(const ValueKey('whatsapp-status'))),
    )
    .label;

/// The header's Refresh button.
DashButton refresh(WidgetTester tester) => tester.widget<DashButton>(
  inPage(find.byKey(const ValueKey('whatsapp-refresh'))),
);

/// The pause switch.
DashSwitch pauseSwitch(WidgetTester tester) => tester.widget<DashSwitch>(
  inPage(find.byKey(const ValueKey('whatsapp-pause-switch'))),
);
