// The Madar orbit in the app icon's colouring (owner, 2026-09-25: "Yes,
// everywhere"): on light grounds an Ink ring and centre dot with a Madar
// Teal deep satellite, on dark grounds a Paper ring and centre dot with the
// same teal satellite. The PNG marks (MadarSymbol, MadarLockup) come from the
// Madar Design System kit; AnimatedBrandMark (the till's rail) draws the
// same colouring in vector.
//
//   flutter test test/brand_test.dart --dart-define=MADAR_RENDER=true
//
// writes build/render/brand-<light|dark>.png: the sign-in marks, the brand
// panel and the rail mark, to be LOOKED at.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _render = bool.fromEnvironment('MADAR_RENDER');

const _ink = Color(0xFF14181E);
const _paper = Color(0xFFEFF3F4);
const _teal = Color(0xFF0D6273);

/// RGBA of one pixel of a brand PNG in this package.
Future<Color> _pixel(WidgetTester tester, String name, int x, int y) async {
  final bytes = File('assets/brand/$name.png').readAsBytesSync();
  final data = (await tester.runAsync(() async {
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;
    final raw = await image.toByteData();
    return (raw!, image.width);
  }))!;
  final (raw, width) = data;
  final i = (y * width + x) * 4;
  return Color.fromARGB(
    raw.getUint8(i + 3),
    raw.getUint8(i),
    raw.getUint8(i + 1),
    raw.getUint8(i + 2),
  );
}

Future<void> _loadFonts() async {
  const cuts = ['Regular', 'Medium', 'SemiBold', 'Bold'];
  for (final family in [MadarType.fontFamily, MadarType.monoFamily]) {
    final loader = FontLoader('packages/${MadarType.fontPackage}/$family');
    for (final cut in cuts) {
      loader.addFont(
        File(
          'assets/fonts/$family-$cut.ttf',
        ).readAsBytes().then(ByteData.sublistView),
      );
    }
    await loader.load();
  }
}

/// The marks as the apps show them: the sign-in symbol, both lockups and the
/// wordmark, the wide sign-in brand panel, the rail's living mark on the
/// chrome and the same mark on the page.
Widget _board(BuildContext context) {
  final colors = context.madarColors;
  return ColoredBox(
    color: colors.bg,
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 24,
            children: [
              const Row(
                spacing: 32,
                children: [
                  MadarSymbol(size: 88),
                  MadarLockup(width: 150),
                  MadarLockup(width: 108, arabic: true),
                ],
              ),
              const MadarWordmark(),
              Row(
                spacing: 32,
                children: [
                  Container(
                    width: Metrics.railMark,
                    height: Metrics.railMark,
                    color: colors.chrome,
                    alignment: Alignment.center,
                    child: AnimatedBrandMark(
                      symbolSize: 26,
                      wordmark: false,
                      ink: colors.onChrome,
                    ),
                  ),
                  const AnimatedBrandMark(symbolSize: 88, wordmarkWidth: 120),
                ],
              ),
            ],
          ),
          const SizedBox(width: 32),
          const SizedBox(
            width: 520,
            height: 420,
            child: MadarBrandPanel(
              headline: 'Run the floor.',
              tagline: 'Orders, tables and tills in one place.',
            ),
          ),
        ],
      ),
    ),
  );
}

void main() {
  setUpAll(_loadFonts);

  for (final dark in [false, true]) {
    final tag = dark ? 'dark' : 'light';
    testWidgets('the brand marks lay out · $tag', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1080, 480);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('shot'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: dark ? MadarTheme.dark() : MadarTheme.light(),
            home: const Material(child: Builder(builder: _board)),
          ),
        ),
      );
      // The living mark never settles: step it to a fixed frame instead.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(() => Future<void>.delayed(Durations.short2));
      await tester.pump();
      expect(tester.takeException(), isNull);
      if (!_render) return;
      final boundary =
          tester.renderObject(find.byKey(const ValueKey('shot')))
              as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final dir = Directory('build/render')..createSync(recursive: true);
        File(
          '${dir.path}/brand-$tag.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    });
  }

  // Sample points: the centre dot, the satellite and the ring's leftmost
  // point of each PNG's orbit (the kit's geometry, unchanged by the recolour).
  for (final (name, centre, satellite, ring, dark) in [
    ('symbol_primary', (800, 800), (1278, 322), (124, 800), false),
    ('symbol_reversed', (800, 800), (1278, 322), (124, 800), true),
    ('lockup_latin', (807, 410), (1033, 184), (488, 410), false),
    ('lockup_latin_reversed', (807, 410), (1033, 184), (488, 410), true),
    ('lockup_arabic', (576, 416), (806, 186), (252, 416), false),
    ('lockup_arabic_reversed', (576, 416), (806, 186), (252, 416), true),
  ]) {
    testWidgets(
      '$name: ring and dot ${dark ? 'Paper' : 'Ink'}, teal satellite',
      (tester) async {
        final fg = dark ? _paper : _ink;
        expect(await _pixel(tester, name, centre.$1, centre.$2), fg);
        expect(await _pixel(tester, name, ring.$1, ring.$2), fg);
        expect(await _pixel(tester, name, satellite.$1, satellite.$2), _teal);
      },
    );
  }

  testWidgets('the rail mark draws the same colouring in vector', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: MadarTheme.light(),
        home: const Center(
          child: AnimatedBrandMark(symbolSize: 120, wordmark: false),
        ),
      ),
    );
    final ink = MadarColors.light.textPrimary;
    // Ring and planet in the ambient ink (the planet's exhale too, faded);
    // the satellite in Teal deep. First frame: no twinkle, no breath.
    expect(
      find.descendant(
        of: find.byType(AnimatedBrandMark),
        matching: find.byType(CustomPaint),
      ),
      paints
        ..circle(radius: 44, color: ink, style: PaintingStyle.stroke)
        ..circle(radius: 13, color: MadarBrandColors.satellite)
        ..circle(
          radius: 16,
          color: ink.withValues(alpha: 0.5),
          style: PaintingStyle.stroke,
        )
        ..circle(radius: 16, color: ink),
    );
  });
}
