// The store identity (PS-6, SA-7, APP-2, APP-4): the name under the icon is
// "Dawam by Madar" / "دوام بواسطة مدار" on both platforms, in the phone's
// language; the permission prompts name Dawam in both languages; the icons
// are not Flutter's template. These live in native project files no widget
// test renders, so this test reads them.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:staff_core/testing.dart';

String _read(String path) => File(path).readAsStringSync();

/// `"key" = "value";` pairs of an iOS `.strings` file.
Map<String, String> _strings(String path) => {
  for (final m in RegExp(
    r'^"([^"]+)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;',
    multiLine: true,
  ).allMatches(_read(path)))
    m.group(1)!: m.group(2)!,
};

/// A plist `<key>` followed by its `<string>`.
String? _plist(String xml, String key) => RegExp(
  '<key>$key</key>\\s*<string>([^<]*)</string>',
).firstMatch(xml)?.group(1);

void main() {
  final en = coreWord('staff.dawam_by_madar');
  final ar = coreWord('staff.dawam_by_madar', arabic: true);

  test('the core names the product', () {
    expect(en, 'Dawam by Madar');
    expect(ar, 'دوام بواسطة مدار');
  });

  group('Android', () {
    const res = 'android/app/src/main/res';

    test('the launcher label is the localised app_name', () {
      expect(
        _read('android/app/src/main/AndroidManifest.xml'),
        contains('android:label="@string/app_name"'),
      );
      expect(_read('$res/values/strings.xml'), contains('>$en<'));
      expect(_read('$res/values-ar/strings.xml'), contains('>$ar<'));
    });

    test('an adaptive icon with a themed layer, not the template', () {
      final xml = _read('$res/mipmap-anydpi-v26/ic_launcher.xml');
      // Brand v2 draws the layers as vector drawables (PNG fallbacks per
      // density stay below); either kind is an adaptive icon.
      expect(
        xml,
        anyOf(
          contains('@drawable/ic_launcher_foreground'),
          contains('@mipmap/ic_launcher_foreground'),
        ),
      );
      expect(xml, contains('<monochrome'));
      for (final dpi in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
        for (final f in [
          'ic_launcher',
          'ic_launcher_foreground',
          'ic_launcher_monochrome',
        ]) {
          expect(File('$res/mipmap-$dpi/$f.png').existsSync(), isTrue);
        }
      }
      // Flutter's template icon, byte for byte (the audit's finding):
      // 442 bytes, FNV-1a 0xcc80822407dd8469.
      final bytes = File('$res/mipmap-mdpi/ic_launcher.png').readAsBytesSync();
      var h = 0xcbf29ce484222325;
      for (final b in bytes) {
        h = (h ^ b) * 0x100000001b3;
      }
      expect(h, isNot(0xcc80822407dd8469));
    });
  });

  group('iOS', () {
    final plist = _read('ios/Runner/Info.plist');

    test('the display name and the languages the app speaks', () {
      expect(_plist(plist, 'CFBundleDisplayName'), en);
      expect(plist, contains('<key>CFBundleLocalizations</key>'));
      expect(plist, contains('<string>ar</string>'));
    });

    test('each language names the app and asks for location as Dawam', () {
      for (final (lang, name, product) in [
        ('en', en, 'Dawam'),
        ('ar', ar, 'دوام'),
      ]) {
        final s = _strings('ios/Runner/$lang.lproj/InfoPlist.strings');
        expect(s['CFBundleDisplayName'], name, reason: lang);
        for (final k in [
          'NSLocationWhenInUseUsageDescription',
          'NSLocationAlwaysAndWhenInUseUsageDescription',
        ]) {
          expect(s[k], startsWith(product), reason: '$lang $k');
          // A key the .strings file translates must exist in Info.plist.
          expect(_plist(plist, k), isNotNull, reason: k);
        }
      }
      expect(
        _plist(plist, 'NSLocationWhenInUseUsageDescription'),
        isNot(contains('Madar uses')),
      );
    });

    // CL-4: the prompts say what the phone does — checks where they are
    // regularly on shift and when they leave the branch (even closed), never
    // after clock-out — and the background modes that do it stay declared.
    test('the location prompts say what tracking does, in both languages', () {
      for (final (lang, regularly, leave, never) in [
        (
          'en',
          'regularly',
          'leave your branch',
          'never checks after you clock out',
        ),
        ('ar', 'كل شوية', 'تخرج من فرعك', 'عمره ما بيشوفه بعد ما تسجّل انصراف'),
      ]) {
        final s = _strings('ios/Runner/$lang.lproj/InfoPlist.strings');
        final always = s['NSLocationAlwaysAndWhenInUseUsageDescription']!;
        final using = s['NSLocationWhenInUseUsageDescription']!;
        for (final t in [always, using]) {
          expect(t.toLowerCase(), contains(regularly), reason: '$lang: $t');
          expect(t.toLowerCase(), contains(never), reason: '$lang: $t');
        }
        expect(always, contains(leave), reason: '$lang: $always');
        expect(using, isNot(contains('only')), reason: 'not only at punches');
      }
      expect(
        _plist(plist, 'NSLocationAlwaysAndWhenInUseUsageDescription'),
        _strings(
          'ios/Runner/en.lproj/InfoPlist.strings',
        )['NSLocationAlwaysAndWhenInUseUsageDescription'],
        reason: 'the base string is the English one',
      );
      final modes = RegExp(
        r'<key>UIBackgroundModes</key>\s*<array>([\s\S]*?)</array>',
      ).firstMatch(plist)!.group(1)!;
      expect(modes, contains('<string>location</string>'));
      expect(modes, contains('<string>remote-notification</string>'));
    });

    // TestFlight holds every build on "Missing Compliance" without it; the
    // app uses only standard HTTPS/TLS (rustls, the platform), which is exempt.
    test('export compliance is declared', () {
      expect(
        plist,
        matches(RegExp(r'<key>ITSAppUsesNonExemptEncryption</key>\s*<false/>')),
      );
    });

    test('the localised strings are bundled (project file)', () {
      final pbx = _read('ios/Runner.xcodeproj/project.pbxproj');
      expect(pbx, contains('InfoPlist.strings in Resources'));
      expect(pbx, contains('path = ar.lproj/InfoPlist.strings'));
      expect(pbx, contains('path = en.lproj/InfoPlist.strings'));
      // Firebase config is optional: copied by a script, never a resource.
      expect(pbx, isNot(contains('GoogleService-Info.plist in Resources')));
    });
  });
}
