// The native launch splash (flutter_native_splash.yaml) draws the Madar orbit
// in the app icon's colouring (2026-09-25): on the teal day ground the on-teal
// mark (Paper ring and centre dot, Ink satellite, since a teal satellite would
// vanish into the ground); on the Ink night ground the reversed mark (Paper
// ring and centre dot, Madar Teal deep satellite). Before, the centre dot was
// the teal and one image served both grounds. The generated files live in the
// native projects, which no widget test renders, so this test decodes them.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

const _paper = 0xFFEFF3F4;
const _ink = 0xFF14181E;
const _tealDeep = 0xFF0D6273;

/// Where the orbit's parts sit in every splash image, as fractions of its
/// side (the kit's symbol frame: viewBox 241.49 wide, the orbit's 100-unit
/// box at 300 units, the satellite at (74.04, 25.96) in that box).
const _centre = (0.5, 0.5);
const _satellite = (0.7986, 0.2013);
const _ring = (0.9224, 0.5); // on the ring's stroke, right of the centre
const _gap = (0.5, 0.75); // between the dot and the ring: the ground shows

Future<ui.Image> _decode(String path) async {
  final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
  return (await codec.getNextFrame()).image;
}

/// The opaque colour at a fractional point, or null where it is transparent.
Future<int?> _at(ui.Image image, (double, double) p) async {
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final x = (p.$1 * image.width).round(), y = (p.$2 * image.height).round();
  final i = (y * image.width + x) * 4;
  final a = data.getUint8(i + 3);
  if (a < 8) return null;
  expect(a, 255, reason: 'partly transparent at $p');
  return 0xFF000000 |
      data.getUint8(i) << 16 |
      data.getUint8(i + 1) << 8 |
      data.getUint8(i + 2);
}

Future<void> _expectOrbit(String path, {required int satellite}) async {
  final image = await _decode(path);
  expect(image.width, image.height, reason: path);
  String hex(int? c) => c == null ? 'none' : c.toRadixString(16);
  expect(hex(await _at(image, _centre)), hex(_paper), reason: '$path centre');
  expect(hex(await _at(image, _ring)), hex(_paper), reason: '$path ring');
  expect(
    hex(await _at(image, _satellite)),
    hex(satellite),
    reason: '$path satellite',
  );
  expect(await _at(image, _gap), isNull, reason: '$path ground');
}

void main() {
  const res = 'android/app/src/main/res';
  const ios = 'ios/Runner/Assets.xcassets/LaunchImage.imageset';
  const densities = ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'];

  testWidgets('day: the on-teal mark, with an Ink satellite', (tester) async {
    await tester.runAsync(() async {
      for (final dpi in densities) {
        for (final name in ['splash', 'android12splash']) {
          await _expectOrbit('$res/drawable-$dpi/$name.png', satellite: _ink);
        }
      }
      for (final s in ['', '@2x', '@3x']) {
        await _expectOrbit('$ios/LaunchImage$s.png', satellite: _ink);
      }
      await _expectOrbit(
        'assets/branding/splash-logo-on-teal.png',
        satellite: _ink,
      );
    });
  });

  testWidgets('night: the reversed mark, with a Teal deep satellite', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final dpi in densities) {
        for (final name in ['splash', 'android12splash']) {
          await _expectOrbit(
            '$res/drawable-night-$dpi/$name.png',
            satellite: _tealDeep,
          );
        }
      }
      for (final s in ['', '@2x', '@3x']) {
        await _expectOrbit('$ios/LaunchImageDark$s.png', satellite: _tealDeep);
      }
      await _expectOrbit(
        'assets/branding/splash-logo.png',
        satellite: _tealDeep,
      );
    });
  });

  test('the grounds stay teal by day and Ink by night', () {
    final day = File('$res/values-v31/styles.xml').readAsStringSync();
    final night = File('$res/values-night-v31/styles.xml').readAsStringSync();
    expect(day, contains('windowSplashScreenBackground">#0D6273<'));
    expect(night, contains('windowSplashScreenBackground">#14181E<'));
  });
}
