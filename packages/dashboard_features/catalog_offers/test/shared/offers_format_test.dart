// The area's shared vocabulary: JS Number() parsing, money in forms, wire
// times, weekday bits, names, and the window form's rules and wire shape.
import 'package:dashboard_api/dashboard_api.dart' show SaleWindow;
import 'package:dashboard_catalog_offers/src/shared/offers_format.dart';
import 'package:dashboard_catalog_offers/src/shared/sale_window_form.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('jsNumber reads text as JavaScript Number() does (OFFR-CED-083)', () {
    expect(jsNumber(' 12 '), 12);
    expect(jsNumber(''), 0);
    expect(jsNumber('.5'), 0.5);
    expect(jsNumber('1e2'), 100);
    expect(jsNumber('0x10'), 16);
    expect(jsNumber('1,000').isNaN, isTrue);
    expect(jsNumber('١٥٠').isNaN, isTrue);
    expect(jsNumber('abc').isNaN, isTrue);
    expect(jsNumber('-5'), -5);
  });

  test('moneyIn / moneyOut: EGP text <-> piastres (OFFR-CED-077)', () {
    expect(moneyIn(''), isNull);
    expect(moneyIn('  '), isNull);
    expect(moneyIn('150'), 15000);
    expect(moneyIn('19.99'), 1999);
    expect(moneyIn('abc')!.isNaN, isTrue);
    expect(moneyIn('-5'), -500);
    expect(moneyOk(''), isTrue);
    expect(moneyOk('0'), isTrue);
    expect(moneyOk('-5'), isFalse);
    expect(moneyOk('1,000'), isFalse);
    expect(moneyOut(15000), '150');
    expect(moneyOut(1250), '12.5');
    expect(moneyOut(1999), '19.99');
    expect(moneyOut(null), '');
  });

  test('hhmm normalises wire times', () {
    expect(hhmm('9:30'), '09:30');
    expect(hhmm('12:00:00'), '12:00');
    expect(hhmm('24:00'), isNull);
    expect(hhmm('12:60'), isNull);
    expect(hhmm(''), isNull);
    expect(hhmm(null), isNull);
  });

  test('weekday bits: Sunday is bit 0, toggling is XOR', () {
    expect(hasDay(allWeekdays, 0), isTrue);
    expect(toggleDay(allWeekdays, 0), 126);
    expect(toggleDay(0, 1), 2);
    expect(hasDay(62, 0), isFalse); // Mon–Fri
    expect(hasDay(62, 5), isTrue);
  });

  test('translatedName picks Arabic only in Arabic and only when present', () {
    expect(translatedName('Bakery', {'ar': 'مخبوزات'}, 'ar'), 'مخبوزات');
    expect(translatedName('Bakery', {'ar': 'مخبوزات'}, 'en'), 'Bakery');
    expect(translatedName('Bakery', const {}, 'ar'), 'Bakery');
    expect(arabicOf({'ar': ''}), isNull);
  });

  group('window form', () {
    test('a new window: every day, no hours, no dates, all branches', () {
      final w = WindowDraft.empty();
      expect(w.weekdays, allWeekdays);
      expect(validateWindow(w).isEmpty, isTrue);
      expect(w.toWire().toJson(), {
        'branch_id': null,
        'ends_at': null,
        'starts_at': null,
        'valid_from': null,
        'valid_to': null,
        'weekdays': 127,
      });
    });

    test(
      'the rules: a day, both times or neither, distinct, dates ordered',
      () {
        final w = WindowDraft.empty();
        expect(
          validateWindow(w.copyWith(weekdays: 0)).weekdays,
          'combos.errors.noDays',
        );
        expect(
          validateWindow(w.copyWith(startsAt: '09:00')).endsAt,
          'combos.errors.hoursPair',
        );
        expect(
          validateWindow(w.copyWith(startsAt: '09:00', endsAt: '09:00')).endsAt,
          'combos.errors.hoursSame',
        );
        expect(
          validateWindow(
            w.copyWith(validFrom: '2026-10-09', validTo: '2026-10-08'),
          ).validTo,
          'combos.errors.datesOrder',
        );
        expect(
          validateWindow(
            w.copyWith(startsAt: '22:00', endsAt: '03:00'),
          ).isEmpty,
          isTrue,
        );
      },
    );

    test('wire round trip keeps the values; seconds are dropped', () {
      final w = WindowDraft.fromWire(
        const SaleWindow(
          branchId: 'b-1',
          weekdays: 62,
          startsAt: '12:00:00',
          endsAt: '16:00:00',
          validFrom: '2026-10-01',
        ),
      );
      expect(w.startsAt, '12:00');
      final json = w.toWire().toJson();
      expect(json['branch_id'], 'b-1');
      expect(json['weekdays'], 62);
      expect(json['starts_at'], '12:00');
      expect(json['ends_at'], '16:00');
      expect(json['valid_from'], '2026-10-01');
      expect(json.containsKey('valid_to'), isTrue);
      expect(json['valid_to'], isNull);
    });

    test('only one time set: no hours go on the wire', () {
      final json = WindowDraft.empty()
          .copyWith(startsAt: '09:00')
          .toWire()
          .toJson();
      expect(json['starts_at'], isNull);
      expect(json['ends_at'], isNull);
    });
  });
}
