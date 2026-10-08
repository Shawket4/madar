import 'dart:convert';
import 'dart:io';

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/mock.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _web = '/Users/shawket/Desktop/Madar/MadarDashboard/src/i18n/locales';

Map<String, String> _asset(String lang) =>
    parseStringTable(File('assets/i18n/$lang.json').readAsStringSync());

Strings _synced() => Strings({'en': _asset('en'), 'ar': _asset('ar')});

void main() {
  group('CLDR plural categories (Intl.PluralRules)', () {
    test('Arabic uses all six', () {
      expect(pluralCategory('ar', 0), 'zero');
      expect(pluralCategory('ar', 1), 'one');
      expect(pluralCategory('ar', 2), 'two');
      for (final n in [3, 7, 10, 103, 110, 1003]) {
        expect(pluralCategory('ar', n), 'few', reason: '$n');
      }
      for (final n in [11, 26, 99, 111, 1099]) {
        expect(pluralCategory('ar', n), 'many', reason: '$n');
      }
      for (final n in [100, 101, 102, 200, 1000, 1001]) {
        expect(pluralCategory('ar', n), 'other', reason: '$n');
      }
      expect(pluralCategory('ar', 2.5), 'other');
      expect(pluralCategory('ar', 3.0), 'few');
      expect(pluralCategory('ar-EG', 2), 'two');
    });

    test('English: one / other', () {
      expect(pluralCategory('en', 1), 'one');
      expect(pluralCategory('en', 1.0), 'one');
      expect(pluralCategory('en', -1), 'one');
      for (final n in [0, 2, 1.5, 11, 100]) {
        expect(pluralCategory('en', n), 'other');
      }
    });
  });

  group('i18next semantics', () {
    final s = Strings(
      {
        'en': {
          'a.plain': 'Plain',
          'a.hello': 'Hello {{name}}',
          'a.items_one': '{{count}} item',
          'a.items_other': '{{count}} items',
          'a.zeroed_zero': 'Nothing',
          'a.zeroed_one': 'One thing',
          'a.zeroed_other': '{{count}} things',
          'a.onlyEn': 'English only',
          'a.empty': '',
          'a.nested': 'By {{user.name}}',
        },
        'ar': {
          'a.plain': 'عادي',
          'a.items_zero': 'لا عناصر',
          'a.items_one': 'عنصر واحد',
          'a.items_two': 'عنصران',
          'a.items_few': '{{count}} عناصر',
          'a.items_many': '{{count}} عنصرًا',
          'a.items_other': '{{count}} عنصر',
        },
      },
      supplements: [
        {
          'en': {'sup.added': 'Added by an area', 'a.plain': 'Plain (area)'},
          'ar': {'sup.added': 'أضافته منطقة'},
        },
      ],
    );

    test('interpolation, missing and null variables', () {
      expect(
        s.translate('en', 'a.hello', args: {'name': 'Nour'}),
        'Hello Nour',
      );
      // Not passed: left as written (skipOnVariables).
      expect(s.translate('en', 'a.hello'), 'Hello {{name}}');
      // Passed as null: empty.
      expect(s.translate('en', 'a.hello', args: {'name': null}), 'Hello ');
      expect(s.translate('en', 'a.hello', args: {'name': 2.0}), 'Hello 2');
      expect(
        s.translate(
          'en',
          'a.nested',
          args: {
            'user': {'name': 'Karim'},
          },
        ),
        'By Karim',
      );
    });

    test('English plurals', () {
      expect(s.translate('en', 'a.items', count: 1), '1 item');
      expect(s.translate('en', 'a.items', count: 0), '0 items');
      expect(s.translate('en', 'a.items', count: 5), '5 items');
      // _zero is used for 0 whatever the language's rules say.
      expect(s.translate('en', 'a.zeroed', count: 0), 'Nothing');
      expect(s.translate('en', 'a.zeroed', count: 1), 'One thing');
    });

    test('Arabic plurals use all six forms', () {
      expect(s.translate('ar', 'a.items', count: 0), 'لا عناصر');
      expect(s.translate('ar', 'a.items', count: 1), 'عنصر واحد');
      expect(s.translate('ar', 'a.items', count: 2), 'عنصران');
      expect(s.translate('ar', 'a.items', count: 3), '3 عناصر');
      expect(s.translate('ar', 'a.items', count: 11), '11 عنصرًا');
      expect(s.translate('ar', 'a.items', count: 100), '100 عنصر');
      expect(s.log.isEmpty, isTrue);
    });

    test('lookup order: language, English, default, key', () {
      s.log.clear();
      expect(s.translate('ar', 'a.plain'), 'عادي');
      expect(s.translate('ar', 'a.onlyEn'), 'English only');
      expect(s.log.englishFallbacks, {'a.onlyEn'});
      expect(s.translate('ar', 'a.none', defaultValue: 'Default'), 'Default');
      expect(s.translate('en', 'a.none2'), 'a.none2');
      expect(s.log.missing, {'a.none', 'a.none2'});
      // An empty string is a value (returnEmptyString).
      expect(s.translate('en', 'a.empty', defaultValue: 'x'), '');
    });

    test('defaults interpolate and pick plural forms', () {
      expect(
        s.translate('en', 'x.y', args: {'n': 3}, defaultValue: '{{n}} left'),
        '3 left',
      );
      const forms = {'one': '1 reward earned', 'other': '{{count}} rewards'};
      expect(
        s.translate('en', 'x.r', count: 1, defaultValues: forms),
        '1 reward earned',
      );
      expect(
        s.translate('en', 'x.r', count: 4, defaultValues: forms),
        '4 rewards',
      );
      expect(
        s.translate(
          'ar',
          'x.r',
          count: 4,
          defaultValues: forms,
          defaultValue: 'd',
        ),
        'd',
        reason: 'Arabic 4 is `few`: no such form, so defaultValue',
      );
    });

    test('supplements merge over the synced tables', () {
      expect(s.translate('en', 'sup.added'), 'Added by an area');
      expect(s.translate('ar', 'sup.added'), 'أضافته منطقة');
      expect(s.translate('en', 'a.plain'), 'Plain (area)');
    });

    test('arrays read back as lists', () {
      final t = Strings({
        'en': flattenStrings({
          'chat': {
            'loading': ['One', 'Two', 'Three'],
          },
        }),
      });
      expect(t.list('en', 'chat.loading'), ['One', 'Two', 'Three']);
      expect(t.list('ar', 'chat.loading'), ['One', 'Two', 'Three']);
      expect(t.list('en', 'chat.none'), isEmpty);
    });

    test('JavaScript number printing', () {
      expect(Strings.jsString(3), '3');
      expect(Strings.jsString(3.0), '3');
      expect(Strings.jsString(2.5), '2.5');
      expect(Strings.jsString(null), '');
      expect(Strings.jsString(true), 'true');
    });
  });

  group('the synced web tables', () {
    test('are exactly the web locales, flattened (parity)', () {
      final dir = Directory(_web);
      if (!dir.existsSync()) {
        markTestSkipped('web repo not on this machine');
        return;
      }
      for (final lang in supportedLanguages) {
        final web = flattenStrings(
          json.decode(File('$_web/$lang.json').readAsStringSync()),
        );
        final ours = _asset(lang);
        expect(ours.keys.toList(), web.keys.toList(), reason: '$lang keys');
        expect(ours, web, reason: '$lang values');
      }
    });

    test('no web string uses nesting (\$t) or formatters we do not run', () {
      for (final lang in supportedLanguages) {
        for (final v in _asset(lang).values) {
          expect(v.contains(r'$t('), isFalse);
          expect(
            RegExp(r'\{\{[^}]*,[^}]*\}\}').hasMatch(v),
            isFalse,
            reason: v,
          );
        }
      }
    });

    test('real keys resolve in both languages', () {
      final s = _synced();
      expect(s.translate('en', 'common.save'), 'Save');
      expect(s.translate('ar', 'common.save'), isNot('Save'));
      expect(s.translate('en', 'excel.done', count: 1), 'Exported 1 row');
      expect(s.translate('en', 'excel.done', count: 3), 'Exported 3 rows');
      expect(
        s.translate('en', 'common.copyright', args: {'year': 2026}),
        '© 2026 Madar. All rights reserved.',
      );
    });

    test('Arabic plurals of real keys answer in Arabic at every category', () {
      final s = _synced();
      final ar = _asset('ar');
      // Every key the Arabic table pluralises fully, at one count per category.
      final bases = {
        for (final k in ar.keys)
          if (k.endsWith('_few')) k.substring(0, k.length - 4),
      };
      expect(bases, isNotEmpty);
      s.log.clear();
      for (final base in bases) {
        for (final n in [0, 1, 2, 3, 11, 100]) {
          s.translate('ar', base, count: n, args: const {});
        }
      }
      expect(s.log.missing, isEmpty);
    });
  });

  group('loading from assets and the providers', () {
    testWidgets('loadStrings reads the bundled tables and supplements', (
      tester,
    ) async {
      final warnings = <String>[];
      final strings = await tester.runAsync(
        () => loadStrings(
          supplementAssets: const [
            'packages/dashboard_missing/assets/i18n/en.json',
          ],
          warnings: warnings,
        ),
      );
      expect(strings!.translate('en', 'common.cancel'), 'Cancel');
      expect(
        strings.translate('ar', 'common.cancel'),
        _asset('ar')['common.cancel'],
      );
      expect(warnings, hasLength(1));
    });

    test('language: stored, then the device, switching remembers it', () async {
      final prefs = MemoryPreferences({languagePrefKey: 'ar'});
      final sinks = <String>[];
      final c = ProviderContainer(
        overrides: [
          preferencesProvider.overrideWithValue(prefs),
          initialLocaleProvider.overrideWithValue('en'),
          localeSinkProvider.overrideWithValue(sinks.add),
          stringsProvider.overrideWithValue(_synced()),
        ],
      );
      addTearDown(c.dispose);
      expect(c.read(localeProvider), 'ar');
      expect(c.read(isRtlProvider), isTrue);
      expect(c.read(tProvider)('common.save'), _asset('ar')['common.save']);
      await c.read(localeProvider.notifier).toggle();
      expect(c.read(localeProvider), 'en');
      expect(prefs.values[languagePrefKey], 'en');
      expect(sinks, ['en']);
      expect(c.read(tProvider)('common.save'), 'Save');
      // A stored region tag or junk falls back sensibly.
      final c2 = ProviderContainer(
        overrides: [
          preferencesProvider.overrideWithValue(
            MemoryPreferences({languagePrefKey: 'ar-EG'}),
          ),
          initialLocaleProvider.overrideWithValue('en'),
        ],
      );
      addTearDown(c2.dispose);
      expect(c2.read(localeProvider), 'ar');
    });

    testWidgets('context.t follows the language', (tester) async {
      final container = ProviderContainer(
        overrides: [
          preferencesProvider.overrideWithValue(MemoryPreferences()),
          initialLocaleProvider.overrideWithValue('en'),
          stringsProvider.overrideWithValue(_synced()),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: DashI18nScope(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Builder(
                builder: (context) => Text(context.t('common.save')),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Save'), findsOneWidget);
      await container.read(localeProvider.notifier).set('ar');
      await tester.pump();
      expect(find.text(_asset('ar')['common.save']!), findsOneWidget);
    });
  });

  test('the bundled asset is declared', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final text = await rootBundle.loadString('assets/i18n/en.json');
    expect(parseStringTable(text)['common.save'], 'Save');
  });
}
