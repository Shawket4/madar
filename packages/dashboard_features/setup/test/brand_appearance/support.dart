// Shared helpers for the Brand / Appearance / settings-shell tests.
import 'dart:convert';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_setup/src/brand_appearance/appearance_page.dart';
import 'package:dashboard_setup/src/brand_appearance/brand_page.dart';
import 'package:dashboard_setup/src/brand_appearance/settings_shell.dart';
import 'package:dashboard_setup/src/mock/support.dart' show qrPng;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

const String brandPath = '/settings/brand';
const String appearancePath = '/settings';
const String orgRoute = '/orgs/{id}';
const String logoRoute = '/orgs/{id}/logo';
const String cardImageRoute = '/orgs/{id}/card-image';

/// A platform admin's picked org (Sabah), as the header stores it.
Map<String, String> get pickedSabah => {
  ScopePrefKeys.org: jsonEncode({'id': SeedIds.sabahOrg}),
};

Future<DashHarness> pumpBrand(
  WidgetTester tester, {
  String path = brandPath,
  Persona? persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
  ({MockServer server, MockDb db})? backend,
  Map<String, String>? prefs,
}) => pumpSetup(
  tester,
  path: path,
  persona: persona,
  size: size,
  locale: locale,
  dark: dark,
  server: backend?.server,
  db: backend?.db,
  prefs: prefs,
);

Finder inBrand(Finder f) =>
    find.descendant(of: find.byType(BrandPage), matching: f);
Finder inAppearance(Finder f) =>
    find.descendant(of: find.byType(AppearancePage), matching: f);
Finder inShell(Finder f) =>
    find.descendant(of: find.byType(SettingsShell), matching: f);
Finder byKey(String key) => find.byKey(ValueKey(key));
Finder inKey(String key, Finder f) =>
    find.descendant(of: byKey(key), matching: f);

/// A real PNG to upload (a QR code is a PNG we can draw without a codec).
Uint8List get samplePng => qrPng('Sabah Coffee');

/// [bytes] as base64 (a `data:` URI's payload).
String base64Of(List<int> bytes) => base64Encode(bytes);

/// Queues [bytes] as the next picked image.
void queueImage(
  DashHarness h, {
  String name = 'logo.png',
  String mimeType = 'image/png',
  List<int>? bytes,
}) => h.files.imageQueue.add(
  PickedFile(name: name, bytes: bytes ?? samplePng, mimeType: mimeType),
);

/// The JSON body of the last [method] call to [template].
Map<String, Object?> lastBody(DashHarness h, String method, String template) =>
    h.server.callsTo(template, method: method).last.body!
        as Map<String, Object?>;

/// The system clipboard, answered in-process (`refuse` makes it fail).
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
