// Test support for the dashboard packages: real fonts, the three window
// sizes, and a PNG of the whole view.
//
// flutter_test is every package's dev dependency and this library is only
// ever imported from tests, so it is not a runtime dependency of the kit.
// ignore_for_file: depend_on_referenced_packages

/// Testing helpers for the dashboard packages: `loadDashFonts`,
/// `captureShot`, the `DashSize` presets and `pumpDashApp`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:design_system/design_system.dart';
import 'package:flutter/cupertino.dart'
    show CupertinoLocalizations, DefaultCupertinoLocalizations;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'src/foundation/l10n.dart';

bool _fontsLoaded = false;

/// Loads the real faces — IBM Plex Sans Arabic and IBM Plex Mono (from
/// design_system) and the Lucide icon font `MadarIcon` falls back to — so a
/// screenshot shows words and glyphs instead of test boxes. Call it from
/// `setUpAll`; it loads once per isolate.
Future<void> loadDashFonts() async {
  if (_fontsLoaded) return;
  final manifest =
      json.decode(await rootBundle.loadString('FontManifest.json'))
          as List<dynamic>;
  for (final entry in manifest) {
    final fam = entry as Map<String, dynamic>;
    final family = fam['family'] as String;
    final wanted =
        family.endsWith('/${MadarType.fontFamily}') ||
        family.endsWith('/${MadarType.monoFamily}') ||
        family == MadarType.fontFamily ||
        family == MadarType.monoFamily ||
        family.endsWith('lucide_icons_flutter/Lucide');
    if (!wanted) continue;
    final loader = FontLoader(family);
    for (final f in fam['fonts'] as List<dynamic>) {
      loader.addFont(
        rootBundle.load((f as Map<String, dynamic>)['asset'] as String),
      );
    }
    await loader.load();
  }
  _fontsLoaded = true;
}

/// A window size the dashboard is checked at, at device pixel ratio 2.
enum DashSize {
  phone(Size(390, 844)),
  tablet(Size(1024, 768)),
  desktop(Size(1440, 900));

  const DashSize(this.size);

  /// The logical size.
  final Size size;

  static const double pixelRatio = 2;

  /// Sets the test view to this size (reset at the end of the test).
  void apply(WidgetTester tester) {
    tester.view.devicePixelRatio = pixelRatio;
    tester.view.physicalSize = size * pixelRatio;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }
}

/// `FDASH_SHOTS`, the folder screenshots go to; null when unset.
String? get dashShotsDir {
  final v = Platform.environment['FDASH_SHOTS'];
  return v == null || v.isEmpty ? null : v;
}

/// Writes a PNG of the whole view — every route, dialog and toast — to
/// [path] (folders created), at the view's pixel ratio. Runs the encoding
/// inside `tester.runAsync`.
Future<void> captureShot(WidgetTester tester, String path) async {
  final view = tester.binding.renderViews.first;
  final layer = view.debugLayer! as OffsetLayer;
  final physical = view.size * tester.view.devicePixelRatio;
  await tester.runAsync(() async {
    final image = await layer.toImage(Offset.zero & physical);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File(path)..parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

/// Localizations for a test app in English or Arabic without
/// flutter_localizations: Material's and Cupertino's default (English)
/// words, and the widgets layer's text direction for the language — so an
/// Arabic test app is right-to-left everywhere, dialogs included.
const List<LocalizationsDelegate<dynamic>> dashTestLocalizationsDelegates = [
  _AnyLocaleDelegate<MaterialLocalizations>(DefaultMaterialLocalizations()),
  _AnyLocaleDelegate<CupertinoLocalizations>(DefaultCupertinoLocalizations()),
  _DirectionDelegate(),
];

class _AnyLocaleDelegate<T> extends LocalizationsDelegate<T> {
  const _AnyLocaleDelegate(this.value);
  final T value;

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<T> load(Locale locale) => SynchronousFuture<T>(value);

  @override
  bool shouldReload(_AnyLocaleDelegate<T> old) => false;
}

class _DirectionDelegate extends LocalizationsDelegate<WidgetsLocalizations> {
  const _DirectionDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<WidgetsLocalizations> load(Locale locale) => SynchronousFuture(
    locale.languageCode == 'ar'
        ? const _Rtl()
        : const DefaultWidgetsLocalizations(),
  );

  @override
  bool shouldReload(_DirectionDelegate old) => false;
}

class _Rtl extends DefaultWidgetsLocalizations {
  const _Rtl();

  @override
  TextDirection get textDirection => TextDirection.rtl;
}

/// The kit's phrases in [lang] — the web's own words.
DashKitStrings dashTestStrings(String lang) => DashKitStrings.forLanguage(lang);

/// An app frame for a kit test: the Madar theme ([dark] or light), the
/// language's direction, the kit's words, [child] as the home page.
Widget dashTestApp({
  required Widget child,
  String lang = 'en',
  bool dark = false,
  bool reducedMotion = false,
}) {
  final rtl = lang == 'ar';
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: MadarTheme.light(),
    darkTheme: MadarTheme.dark(),
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    locale: Locale(lang),
    supportedLocales: const [Locale('en'), Locale('ar')],
    localizationsDelegates: dashTestLocalizationsDelegates,
    builder: (context, page) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
      child: Directionality(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        child: DashKitLocalizations.forLanguage(lang, child: page!),
      ),
    ),
    home: child,
  );
}

/// Sets [size], pumps [child] in [dashTestApp] and settles.
Future<void> pumpDashApp(
  WidgetTester tester,
  Widget child, {
  DashSize size = DashSize.desktop,
  String lang = 'en',
  bool dark = false,
  bool reducedMotion = false,
}) async {
  size.apply(tester);
  await tester.pumpWidget(
    dashTestApp(
      child: child,
      lang: lang,
      dark: dark,
      reducedMotion: reducedMotion,
    ),
  );
  await tester.pump();
}
