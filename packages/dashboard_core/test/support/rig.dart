// Test support for dashboard_core's own widget tests: the mock backend wired
// into a ProviderScope, real fonts, and screenshots into FDASH_SHOTS.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/mock.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

/// The three screenshot sizes of SPEC §6.2.
enum ShotSize {
  phone(Size(390, 844)),
  tablet(Size(1024, 768)),
  desktop(Size(1440, 900));

  const ShotSize(this.size);
  final Size size;
}

Strings? _strings;

/// The synced web tables (read once per test file).
Strings syncedStrings() => _strings ??= Strings({
  'en': parseStringTable(File('assets/i18n/en.json').readAsStringSync()),
  'ar': parseStringTable(File('assets/i18n/ar.json').readAsStringSync()),
});

bool _fontsLoaded = false;

/// Loads every font the bundle declares (IBM Plex, the icon font), so a
/// screenshot shows real glyphs instead of test boxes.
Future<void> loadFonts() async {
  if (_fontsLoaded) return;
  _fontsLoaded = true;
  final manifest =
      json.decode(await rootBundle.loadString('FontManifest.json')) as List;
  for (final f in manifest.cast<Map<String, Object?>>()) {
    final loader = FontLoader(f['family']! as String);
    for (final font in (f['fonts']! as List).cast<Map<String, Object?>>()) {
      loader.addFont(rootBundle.load(font['asset']! as String));
    }
    await loader.load();
  }
}

/// A container on the mock backend, signed in as [persona].
class CoreRig {
  CoreRig({this.persona = Persona.owner, Map<String, String>? prefs})
    : db = MockDb.seeded() {
    server = MockServer(persona: persona, clock: db.clock);
    registerCoreMocks(server, db);
    gw = MockSessionGateway(server, signedInAs: persona);
    this.prefs = MemoryPreferences(prefs);
  }

  final Persona persona;
  final MockDb db;
  late final MockServer server;
  late final MockSessionGateway gw;
  late final MemoryPreferences prefs;
  final files = RecordingFileGateway();
  final exports = RecordingExportGateway();
  final realtime = MockRealtimeGateway();

  List<Override> overrides({String lang = 'en'}) => [
    transportProvider.overrideWithValue(gw.transport),
    sessionGatewayProvider.overrideWithValue(gw),
    preferencesProvider.overrideWithValue(prefs),
    clockProvider.overrideWithValue(() => db.clock.now),
    initialLocaleProvider.overrideWithValue(lang),
    stringsProvider.overrideWithValue(syncedStrings()),
    fileGatewayProvider.overrideWithValue(files),
    exportGatewayProvider.overrideWithValue(exports),
    realtimeGatewayProvider.overrideWithValue(realtime),
  ];
}

final _shotKey = GlobalKey();

/// Pumps [child] the way the shell will host it: theme, direction, the i18n
/// and kit scopes, at [size].
Future<ProviderContainer> pumpCore(
  WidgetTester tester,
  CoreRig rig,
  Widget child, {
  String lang = 'en',
  bool dark = false,
  ShotSize size = ShotSize.desktop,
}) async {
  await loadFonts();
  tester.view
    ..physicalSize = size.size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(overrides: rig.overrides(lang: lang));
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark ? MadarTheme.dark() : MadarTheme.light(),
        home: RepaintBoundary(
          key: _shotKey,
          child: Directionality(
            textDirection: lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
            child: DashI18nScope(
              child: DashKitScope(
                child: Builder(
                  builder: (context) => Material(
                    color: context.madarColors.bg,
                    child: SafeArea(child: child),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.runAsync(() => container.read(sessionProvider.future));
  await settleRig(tester);
  return container;
}

/// Lets the mock's futures complete and the frame settle.
Future<void> settleRig(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() async {
      for (var j = 0; j < 10; j++) {
        await Future<void>.delayed(Duration.zero);
      }
    });
    await tester.pump();
  }
}

/// Writes `<FDASH_SHOTS>/core/<page>/<name>--<size>-<lang>-<theme>.png` when
/// FDASH_SHOTS is set.
Future<void> shot(
  WidgetTester tester,
  String page,
  String name, {
  required ShotSize size,
  required String lang,
  required bool dark,
}) async {
  final dir = Platform.environment['FDASH_SHOTS'];
  if (dir == null || dir.isEmpty) return;
  final boundary =
      _shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(
      '$dir/core/$page/$name--${size.name}-$lang-${dark ? 'dark' : 'light'}.png',
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
  });
}
