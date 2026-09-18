// The kit's formats are a MIRROR of the core's `display.rs`. Both suites read
// the same fixture file, so a rule changed on one side fails the other until
// they agree again. See docs/design/SPEC.md §9.

import 'dart:convert';
import 'dart:io';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _fixtures() {
  final file = File('../../docs/design/format_fixtures.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

List<Map<String, dynamic>> _cases(String key) =>
    (_fixtures()[key] as List).cast<Map<String, dynamic>>();

void main() {
  test('money matches the core fixtures', () {
    for (final c in _cases('money')) {
      expect(
        MadarFormat.money(
          c['minor'] as int,
          currency: c['currency'] as String,
          locale: c['locale'] as String,
          signed: c['signed'] as bool,
        ),
        c['out'],
        reason: '$c',
      );
    }
  });

  test('currency labels match the core fixtures', () {
    for (final c in _cases('currency')) {
      expect(
        MadarFormat.currencyLabel(
          c['code'] as String,
          locale: c['locale'] as String,
        ),
        c['out'],
        reason: '$c',
      );
    }
  });

  test('elapsed matches the core fixtures', () {
    for (final c in _cases('elapsed')) {
      expect(
        MadarFormat.elapsed(
          Duration(seconds: c['secs'] as int),
          locale: c['locale'] as String,
        ),
        c['out'],
        reason: '$c',
      );
    }
  });

  test('stamps match the core fixtures', () {
    for (final c in _cases('stamp')) {
      expect(
        MadarFormat.stamp(
          DateTime.parse(c['at'] as String),
          DateTime.parse(c['now'] as String),
          locale: c['locale'] as String,
        ),
        c['out'],
        reason: '$c',
      );
    }
  });

  test('a clock time is 12-hour, midnight and noon included', () {
    // The mirror of the core's display::hhmm12 — hour zero-padded, figures
    // Western, only the meridiem word changes with the language.
    expect(MadarFormat.clock(0, 5), '12:05 AM');
    expect(MadarFormat.clock(9, 0), '09:00 AM');
    expect(MadarFormat.clock(11, 59), '11:59 AM');
    expect(MadarFormat.clock(12, 0), '12:00 PM');
    expect(MadarFormat.clock(18, 2), '06:02 PM');
    expect(MadarFormat.clock(23, 30), '11:30 PM');
    expect(MadarFormat.clock(0, 5, locale: 'ar'), '12:05 ص');
    expect(MadarFormat.clock(18, 2, locale: 'ar'), '06:02 م');
    // Never a 24-hour hour, in either language.
    for (var h = 0; h < 24; h++) {
      for (final l in ['en', 'ar']) {
        final out = MadarFormat.clock(h, 0, locale: l);
        final hour = int.parse(out.substring(0, 2));
        expect(hour, greaterThanOrEqualTo(1), reason: '$l $h -> $out');
        expect(hour, lessThanOrEqualTo(12), reason: '$l $h -> $out');
      }
    }
  });

  test('Money.format is the English shape by default', () {
    expect(Money.format(623000, currency: 'EGP'), 'EGP 6,230.00');
    expect(Money.format(-5000, currency: 'egp'), '−EGP 50.00');
    expect(Money.format(1250), '12.50');
    expect(MadarFormat.ltr('42'), '\u206642\u2069');
  });

  Future<String> moneyTextIn(WidgetTester tester, Locale locale) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: MadarTheme.light(),
        locale: locale,
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const Scaffold(body: MoneyText(123450, currency: 'EGP')),
      ),
    );
    final text = tester.widget<Text>(find.byType(Text));
    expect(
      text.textDirection,
      locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
    );
    return text.data!;
  }

  testWidgets('MoneyText follows the app language', (tester) async {
    expect(await moneyTextIn(tester, const Locale('en')), 'EGP 1,234.50');
    expect(
      await moneyTextIn(tester, const Locale('ar')),
      '\u20661,234.50\u2069 ج.م',
    );
  });
}
