// The launcher icon, the splash and the name (owner, 2026-10-10: the POS's
// icons and splash; apps/madar/test/launcher_icon_test.dart is the same test
// for the POS): Android's adaptive icon has a themed (monochrome) layer, no
// platform ships Flutter's template icon, the iOS icons are opaque 1024s with
// dark and tinted appearances, both splash generations draw the orbit at the
// sizes the kit sets, and every platform names the app "Madar Dashboard",
// never the package name. These live in native project files no widget test
// renders, so this test reads them.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

/// FNV-1a (32-bit) of a file's bytes: pins "not this exact file".
int _fnv(String path) {
  var h = 0x811c9dc5;
  for (final b in File(path).readAsBytesSync()) {
    h = ((h ^ b) * 0x01000193) & 0xffffffff;
  }
  return h;
}

/// Width, height and colour type of a PNG, from its IHDR chunk.
({int width, int height, int colourType}) _png(String path) {
  final b = File(path).readAsBytesSync();
  expect(ascii.decode(b.sublist(1, 4)), 'PNG', reason: path);
  final d = ByteData.sublistView(b);
  return (width: d.getUint32(16), height: d.getUint32(20), colourType: b[25]);
}

const _densities = {
  'mdpi': 1.0,
  'hdpi': 1.5,
  'xhdpi': 2.0,
  'xxhdpi': 3.0,
  'xxxhdpi': 4.0,
};

void main() {
  group('Android', () {
    const res = 'android/app/src/main/res';

    test('an adaptive icon with a themed layer, not the template', () {
      for (final name in ['ic_launcher', 'ic_launcher_round']) {
        final xml = _read('$res/mipmap-anydpi-v26/$name.xml');
        for (final layer in ['background', 'foreground', 'monochrome']) {
          expect(
            xml,
            contains('<$layer android:drawable="@drawable/ic_launcher_$layer"'),
            reason: '$name $layer',
          );
          expect(
            File('$res/drawable/ic_launcher_$layer.xml').existsSync(),
            isTrue,
          );
        }
      }
      // The themed layer is a silhouette: one colour (plus "no fill").
      final mono = _read('$res/drawable/ic_launcher_monochrome.xml');
      final colours = RegExp('android:(?:stroke|fill)Color="(#[0-9A-Fa-f]+)"')
          .allMatches(mono)
          .map((m) => m.group(1)!.toUpperCase())
          .where((c) => c != '#00000000')
          .toSet();
      expect(colours, hasLength(1));

      for (final dpi in _densities.keys) {
        for (final f in [
          'ic_launcher',
          'ic_launcher_round',
          'ic_launcher_foreground',
          'ic_launcher_background',
          'ic_launcher_monochrome',
        ]) {
          expect(
            File('$res/mipmap-$dpi/$f.png').existsSync(),
            isTrue,
            reason: '$dpi $f',
          );
        }
      }
      // Flutter's template icon, byte for byte (442 bytes), as apps/staff pins.
      expect(_fnv('$res/mipmap-mdpi/ic_launcher.png'), isNot(0xf1553769));
    });

    test('the splash: the orbit before and from Android 12, day and night', () {
      for (final night in ['', 'night-']) {
        for (final MapEntry(key: dpi, value: d) in _densities.entries) {
          final splash = _png('$res/drawable-$night$dpi/splash.png');
          expect(splash.width, (150 * d).round(), reason: '$night$dpi');
          final a12 = _png('$res/drawable-$night$dpi/android12splash.png');
          expect(a12.width, (288 * d).round(), reason: '$night$dpi');
        }
      }
      for (final v in ['values-v31', 'values-night-v31']) {
        final styles = _read('$res/$v/styles.xml');
        expect(styles, contains('@drawable/android12splash'), reason: v);
        expect(
          styles,
          contains('windowSplashScreenIconBackgroundColor'),
          reason: v,
        );
      }
      expect(
        _read('$res/drawable/launch_background.xml'),
        contains('@drawable/splash'),
      );
    });
  });

  group('iOS', () {
    const assets = 'ios/Runner/Assets.xcassets';

    test('opaque 1024 icons, with dark and tinted appearances', () {
      final json =
          jsonDecode(_read('$assets/AppIcon.appiconset/Contents.json'))
              as Map<String, dynamic>;
      final images = (json['images'] as List).cast<Map<String, dynamic>>();
      final looks = <String>{};
      for (final image in images) {
        final png = _png('$assets/AppIcon.appiconset/${image['filename']}');
        expect((png.width, png.height), (1024, 1024));
        // App Store Connect refuses an icon with an alpha channel.
        expect(png.colourType, 2, reason: '${image['filename']} is RGB');
        final appearances = image['appearances'] as List?;
        looks.add(
          appearances == null
              ? 'any'
              : (appearances.single as Map<String, dynamic>)['value'] as String,
        );
      }
      expect(looks, {'any', 'dark', 'tinted'});
    });

    test('the launch image is the 150 pt orbit, light and dark', () {
      for (final dark in ['', 'Dark']) {
        for (final (suffix, scale) in [('', 1), ('@2x', 2), ('@3x', 3)]) {
          final png = _png(
            '$assets/LaunchImage.imageset/LaunchImage$dark$suffix.png',
          );
          expect((png.width, png.height), (150 * scale, 150 * scale));
        }
      }
      final storyboard = _read('ios/Runner/Base.lproj/LaunchScreen.storyboard');
      expect(storyboard, contains('image="LaunchImage"'));
      expect(storyboard, contains('image="LaunchBackground"'));
    });
  });

  group('desktop', () {
    test('the macOS icon set is the orbit, not the template', () {
      const set = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';
      final json =
          jsonDecode(_read('$set/Contents.json')) as Map<String, dynamic>;
      for (final image
          in (json['images'] as List).cast<Map<String, dynamic>>()) {
        final pt = int.parse((image['size'] as String).split('x').first);
        final scale = int.parse((image['scale'] as String).replaceAll('x', ''));
        final png = _png('$set/${image['filename']}');
        expect(png.width, pt * scale, reason: '${image['filename']}');
      }
      // Flutter's template files, as the app was scaffolded with them.
      expect(_fnv('$set/app_icon_16.png'), isNot(0x2f1deeff));
      expect(_fnv('$set/app_icon_1024.png'), isNot(0x5002065f));
    });

    test('the Windows icon carries every size, not the template', () {
      const ico = 'windows/runner/resources/app_icon.ico';
      expect(_fnv(ico), isNot(0x59ae9775));
      final b = File(ico).readAsBytesSync();
      final d = ByteData.sublistView(b);
      expect(d.getUint16(2, Endian.little), 1); // an icon, not a cursor
      final count = d.getUint16(4, Endian.little);
      final sizes = {
        for (var i = 0; i < count; i++)
          if (b[6 + 16 * i] == 0) 256 else b[6 + 16 * i],
      };
      expect(sizes, containsAll(<int>{16, 24, 32, 48, 64, 256}));
    });
  });

  test('the app is called Madar Dashboard, never madar_dashboard', () {
    const res = 'android/app/src/main/res';
    expect(
      _read('android/app/src/main/AndroidManifest.xml'),
      contains('android:label="@string/app_name"'),
    );
    expect(
      _read('$res/values/strings.xml'),
      contains('<string name="app_name">Madar Dashboard</string>'),
    );
    expect(
      _read('$res/values-ar/strings.xml'),
      contains('<string name="app_name">لوحة تحكم مدار</string>'),
    );
    expect(
      _read('ios/Runner/Info.plist'),
      contains('<string>Madar Dashboard</string>'),
    );
    expect(
      _read('macos/Runner/Info.plist'),
      contains('<key>CFBundleName</key>\n\t<string>Madar Dashboard</string>'),
    );
    expect(_read('windows/runner/main.cpp'), contains('L"Madar Dashboard"'));
  });
}
