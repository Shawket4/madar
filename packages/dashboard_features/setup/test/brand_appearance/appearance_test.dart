// `/settings` Appearance (SET-APP-001 … 009), driven through the app shell.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_setup/src/brand_appearance/appearance_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Finder _row(String key) => inAppearance(byKey(key));
Finder _inRow(String key, Finder f) =>
    find.descendant(of: _row(key), matching: f);
Finder _glyph(String key, String name) =>
    _inRow(key, find.byWidgetPredicate((w) => w is DashIcon && w.name == name));

Brightness _brightness(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(AppearancePage))).brightness;

void main() {
  testWidgets('SET-APP-001 the pane header and no request', (tester) async {
    final h = await pumpBrand(tester, path: appearancePath);
    expect(inAppearance(find.text('Appearance')), findsOneWidget);
    expect(
      inAppearance(find.text('Theme and language for this device.')),
      findsOneWidget,
    );
    // Nothing of its own is asked (the frame's own reads aside).
    expect(h.location.path, appearancePath);
  });

  testWidgets('SET-APP-002 Theme: the row\'s glyph follows the choice; '
      'Light / Dark / System; a choice applies at once and is remembered', (
    tester,
  ) async {
    final h = await pumpBrand(tester, path: appearancePath);
    expect(_inRow('app-theme', find.text('Theme')), findsOneWidget);
    for (final w in ['Light', 'Dark', 'System']) {
      expect(_inRow('app-theme', find.text(w)), findsOneWidget);
    }
    expect(_glyph('app-theme', 'sun'), findsNWidgets(2));
    expect(_brightness(tester), Brightness.light);
    await h.tap(_inRow('app-theme', find.text('Dark')));
    expect(_brightness(tester), Brightness.dark);
    expect(_glyph('app-theme', 'moon'), findsNWidgets(2));
    expect(
      h.container.read(preferencesProvider).getString(themePrefKey),
      'dark',
    );
    await h.tap(_inRow('app-theme', find.text('System')));
    expect(h.container.read(themePrefProvider), ThemePref.system);
    expect(_glyph('app-theme', 'monitor'), findsNWidgets(2));
  });

  testWidgets('SET-APP-002 nothing remembered: System', (tester) async {
    final h = await pumpBrand(
      tester,
      path: appearancePath,
      prefs: {themePrefKey: ''},
    );
    expect(h.container.read(themePrefProvider), ThemePref.system);
    final seg = tester.widget<DashSegmentedControl<ThemePref>>(
      _inRow('app-theme', find.byType(DashSegmentedControl<ThemePref>)),
    );
    expect(seg.value, ThemePref.system);
  });

  testWidgets('SET-APP-003 phone: the theme segments are glyphs, named for '
      'screen readers', (tester) async {
    final h = await pumpBrand(
      tester,
      path: appearancePath,
      size: DashSize.phone,
    );
    for (final w in ['Light', 'Dark', 'System']) {
      expect(_inRow('app-theme', find.text(w)), findsNothing);
      expect(_inRow('app-theme', find.bySemanticsLabel(w)), findsOneWidget);
    }
    final hint = h.t('settings.themeHint');
    expect(
      _inRow(
        'app-theme',
        find.byWidgetPredicate(
          (w) => w is Semantics && w.container && w.properties.label == hint,
        ),
      ),
      findsOneWidget,
      reason: 'the glyph group is named as one control',
    );
    await h.tap(_inRow('app-theme', find.bySemanticsLabel('Dark')));
    expect(h.container.read(themePrefProvider), ThemePref.dark);
  });

  testWidgets('SET-APP-004 Language: English / العربية switches at once, '
      'flips the direction and is remembered', (tester) async {
    final h = await pumpBrand(tester, path: appearancePath);
    expect(_inRow('app-language', find.text('Language')), findsOneWidget);
    expect(_glyph('app-language', 'languages'), findsOneWidget);
    expect(_inRow('app-language', find.text('English')), findsOneWidget);
    await h.tap(_inRow('app-language', find.text('العربية')));
    expect(h.container.read(localeProvider), 'ar');
    expect(
      Directionality.of(tester.element(find.byType(AppearancePage))),
      TextDirection.rtl,
    );
    expect(inAppearance(find.text(h.t('settings.appearance'))), findsWidgets);
    expect(h.t('settings.appearance'), 'المظهر');
    expect(
      h.container.read(preferencesProvider).getString(languagePrefKey),
      'ar',
    );
    await h.tap(_inRow('app-language', find.text('English')));
    expect(h.container.read(localeProvider), 'en');
  });

  testWidgets('SET-APP-005 Account: initials, name, email and the role pill', (
    tester,
  ) async {
    await pumpBrand(tester, path: appearancePath);
    expect(inAppearance(find.text('Account')), findsOneWidget);
    expect(_inRow('app-account', find.text('NE')), findsOneWidget);
    expect(_inRow('app-account', find.text('Nour El-Sayed')), findsOneWidget);
    expect(_inRow('app-account', find.text('nour@sabah.test')), findsOneWidget);
    expect(
      _inRow('app-account', find.text('Organization Admin')),
      findsOneWidget,
    );
  });

  testWidgets('SET-APP-005 a platform admin\'s role reads Super Admin', (
    tester,
  ) async {
    await pumpBrand(tester, path: appearancePath, persona: Persona.platform);
    expect(_inRow('app-account', find.text('Madar Support')), findsOneWidget);
    expect(_inRow('app-account', find.text('Super Admin')), findsOneWidget);
  });

  testWidgets('SET-APP-006 About: three documents opened outside the app', (
    tester,
  ) async {
    final h = await pumpBrand(tester, path: appearancePath);
    expect(inAppearance(find.text('About')), findsOneWidget);
    for (final (key, url) in appearanceLegal) {
      final row = 'app-$key';
      expect(_glyph(row, 'file-text'), findsOneWidget);
      expect(_glyph(row, 'external-link'), findsOneWidget);
      await h.tap(_inRow(row, find.text(h.t(key))));
      expect(h.openedLinks.last, Uri.parse(url));
    }
    expect(h.openedLinks, hasLength(3));
    expect(inAppearance(find.text('Data retention')), findsOneWidget);
  });

  testWidgets('SET-APP-007 the app row: M, Madar, © 2026 Madar, v1.0.0', (
    tester,
  ) async {
    await pumpBrand(tester, path: appearancePath);
    expect(_inRow('app-version', find.text('M')), findsOneWidget);
    expect(_inRow('app-version', find.text('Madar')), findsOneWidget);
    expect(_inRow('app-version', find.text('© 2026 Madar')), findsOneWidget);
    expect(
      _inRow('app-version', find.textContaining('v1.0.0')),
      findsOneWidget,
    );
  });

  testWidgets('SET-APP-008 no "Delete your account"', (tester) async {
    await pumpBrand(tester, path: appearancePath);
    expect(inAppearance(find.textContaining('Delete')), findsNothing);
    expect(inAppearance(find.byType(DashListRow)), findsNWidgets(7));
  });

  testWidgets('SET-APP-009 System follows the device live; Light ignores it', (
    tester,
  ) async {
    final h = await pumpBrand(tester, path: appearancePath);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await h.settle();
    expect(_brightness(tester), Brightness.light, reason: 'Light ignores it');
    await h.tap(_inRow('app-theme', find.text('System')));
    expect(_brightness(tester), Brightness.dark);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await h.settle();
    expect(_brightness(tester), Brightness.light);
  });

  testWidgets('SET-APP-001 Arabic: the pane in Arabic, the language names as '
      'written', (tester) async {
    final h = await pumpBrand(tester, path: appearancePath, locale: 'ar');
    expect(
      inAppearance(find.text(h.t('settings.appearanceDesc'))),
      findsOneWidget,
    );
    expect(_inRow('app-language', find.text('English')), findsOneWidget);
    expect(inAppearance(find.text('الاحتفاظ بالبيانات')), findsOneWidget);
  });
}
