// Every screen, every persona, Arabic and English (APP-9): each must lay out
// on a phone and a tablet without an overflow or a raw i18n key. With
//   flutter test test/screens_test.dart --dart-define=MADAR_RENDER=true
// it also writes build/shots/<lang>-<device>-<who>-<tab>.png with the real
// Plex faces.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'support.dart';

const _render = bool.fromEnvironment('MADAR_RENDER');

Future<void> _shot(WidgetTester tester, String name) async {
  await frames(tester);
  // A key the core can't answer renders as itself: never on a real screen.
  expect(
    find.textContaining(RegExp(r'\b(staff|settings|common)\.[a-z_]+')),
    findsNothing,
    reason: name,
  );
  if (_render) await _write(tester, name);
  await finish(tester);
}

Future<void> _write(WidgetTester tester, String name) async {
  final boundary =
      tester.renderObject(find.byKey(const ValueKey('shot')))
          as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('build/shots')..createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  useCoreWords();

  setUpAll(() async {
    await loadFonts();
    await initializeDateFormatting();
  });

  // who, manager side?, tab count
  const views = [('e1', false, 5), ('e2', true, 3), ('e3', true, 4)];
  const devices = {'phone': Size(390, 844), 'tablet': Size(1180, 820)};
  for (final lang in ['ar', 'en']) {
    for (final MapEntry(key: device, value: size) in devices.entries) {
      testWidgets('sign-in · $lang · $device', (tester) async {
        await pumpApp(tester, lang: lang, size: size);
        await _shot(tester, '$lang-$device-signin');
      });
      for (final (who, manage, tabs) in views) {
        for (var tab = 0; tab < tabs; tab++) {
          testWidgets(
            '$who ${manage ? 'manage' : 'own'} tab $tab · $lang · $device',
            (tester) async {
              await pumpApp(
                tester,
                lang: lang,
                who: who,
                manage: manage,
                tab: tab,
                size: size,
              );
              await _shot(
                tester,
                '$lang-$device-$who-${manage ? 'm' : 'o'}$tab',
              );
            },
          );
        }
      }
    }
  }

  // The roster's one-day list, a phone's alternative to the week board.
  for (final lang in ['ar', 'en']) {
    testWidgets('roster day list · $lang · phone', (tester) async {
      await pumpApp(tester, lang: lang, who: 'e2', manage: true, tab: 2);
      await tester.tap(find.text(lang == 'ar' ? 'يوم' : 'Day'));
      await frames(tester);
      await _shot(tester, '$lang-phone-e2-m2-day');
    });
  }

  testWidgets('dark theme follows the shared picker', (tester) async {
    await pumpApp(tester, lang: 'ar', who: 'e1', theme: ThemeChoice.dark);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    await _shot(tester, 'ar-phone-e1-dark');
  });
}
