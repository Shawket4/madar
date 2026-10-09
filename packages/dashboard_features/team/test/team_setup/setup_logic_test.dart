// Set-up's pure rules, against the web's own cases: the pin reader
// (`dawam/geo.test.ts`, TEAM-SET-019/020/022), the ladder's worked figure
// (`staff/rules-preview.test.ts`, TEAM-SET-032), the suggested-rules seed and
// the PUT body (TEAM-SET-032/034), and the shift span (TEAM-SET-029).
import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_team/src/team_setup/geo.dart';
import 'package:dashboard_team/src/team_setup/setup_rules.dart';
import 'package:dashboard_team/src/team_setup/setup_steps.dart';
import 'package:flutter_test/flutter_test.dart';

import 'setup_support.dart';

PinParse _ok(double lat, double lng) => PinParse.ok(LatLng(lat, lng));
const PinParse _short = PinParse.error(PinProblem.shortLink);
const PinParse _none = PinParse.error(PinProblem.none);
const PinParse _range = PinParse.error(PinProblem.outOfRange);

SetupTier _tier(int from, int? to, String kind, double value) =>
    SetupTier(fromMinutes: from, toMinutes: to, kind: kind, value: value);

const PayExample _ex = PayExample(
  salary: 1200000,
  workingDays: 30,
  shiftMinutes: 480,
);

/// Sabah's rules as the mock server answers them, after [edit].
Future<AttendanceSettings> _settings([void Function(MockDb db)? edit]) async {
  final s = setupServer(edit: edit);
  final r = await s.server.send(
    const ApiRequest(method: 'GET', path: '/staff/attendance/settings'),
  );
  return AttendanceSettings.fromJson(
    (jsonDecode(utf8.decode(r.bodyBytes)) as Map).cast<String, Object?>(),
  );
}

void main() {
  group('TEAM-SET-019/020 parsePin', () {
    test('the place pin of a long Maps link wins over its map centre', () {
      expect(
        parsePin(
          'https://www.google.com/maps/place/Cairo+Tower/@30.0459,31.2243,17z'
          '/data=!3m1!4b1!4m6!3m5!1s0x1458!8m2!3d30.045915!4d31.224290!16s',
        ),
        _ok(30.045915, 31.22429),
      );
    });

    test('the map centre when there is no place pin (6 decimals)', () {
      expect(
        parsePin('https://www.google.com/maps/@30.0444196,31.2357116,15z'),
        _ok(30.04442, 31.235712),
      );
    });

    test('?q= / query= / ll= links, encoded or not', () {
      expect(
        parsePin('https://maps.google.com/?q=30.0444,31.2357'),
        _ok(30.0444, 31.2357),
      );
      expect(
        parsePin(
          'https://www.google.com/maps/search/?api=1&query=30.0444%2C31.2357',
        ),
        _ok(30.0444, 31.2357),
      );
      expect(
        parsePin('https://maps.google.com/maps?ll=29.96,31.25&z=16'),
        _ok(29.96, 31.25),
      );
    });

    test('bare coordinates and geo: URIs', () {
      expect(parsePin('30.0444, 31.2357'), _ok(30.0444, 31.2357));
      expect(parsePin('  30.0444 31.2357 '), _ok(30.0444, 31.2357));
      expect(parsePin('geo:30.0444,31.2357'), _ok(30.0444, 31.2357));
      expect(parsePin('-33.86, 151.2'), _ok(-33.86, 151.2));
    });

    test('Arabic digits and the Arabic comma', () {
      expect(parsePin('٣٠٫٠٤٤٤، ٣١٫٢٣٥٧'), _ok(30.0444, 31.2357));
    });

    test('a short share link is named, never guessed', () {
      expect(parsePin('https://maps.app.goo.gl/AbCdEf123'), _short);
      expect(parsePin('https://goo.gl/maps/xyz'), _short);
    });

    test('what is not a place', () {
      expect(parsePin(''), _none);
      expect(parsePin('Zamalek, Cairo'), _none);
      expect(parsePin('95.1, 31.2'), _range);
    });
  });

  test('TEAM-SET-022 Egypt, the Maps link and the pin as read', () {
    expect(inEgypt(const LatLng(30.04, 31.23)), isTrue);
    expect(inEgypt(const LatLng(31.23, 30.04)), isTrue);
    expect(inEgypt(const LatLng(51.5, -0.12)), isFalse);
    expect(
      mapsLink(const LatLng(30.04, 31.23)).toString(),
      'https://www.google.com/maps?q=30.04,31.23',
    );
    expect(fmtLatLng(const LatLng(30.0444, 31.2357)), '30.04440, 31.23570');
    expect(round6(30.0444196), 30.04442);
    expect(jsNumber(30.0), '30');
    expect(jsNumber(0.25), '0.25');
  });

  group('TEAM-SET-032 the worked figure (tierPiastres)', () {
    test('a quarter day on EGP 12,000 / 30 days = EGP 100', () {
      expect(tierPiastres(_tier(16, 30, 'day_fraction', 0.25), _ex), 10000);
    });

    test('15 minutes of pay on an 8 h day = EGP 12.50', () {
      expect(tierPiastres(_tier(1, 15, 'minutes', 15), _ex), 1250);
    });

    test('multiplies before dividing, rounds half away from zero', () {
      expect(
        tierPiastres(
          _tier(1, null, 'minutes', 30),
          const PayExample(salary: 1000000, workingDays: 30, shiftMinutes: 480),
        ),
        2083,
      );
      expect(
        tierPiastres(
          _tier(1, null, 'day_fraction', 0.5),
          const PayExample(salary: 1, workingDays: 1, shiftMinutes: 480),
        ),
        1,
      );
    });

    test('zero divisors give 0; a fixed amount is itself', () {
      expect(
        tierPiastres(
          _tier(16, 30, 'day_fraction', 0.25),
          const PayExample(salary: 1200000, workingDays: 0, shiftMinutes: 480),
        ),
        0,
      );
      expect(
        tierPiastres(
          _tier(1, 15, 'minutes', 15),
          const PayExample(salary: 1200000, workingDays: 30, shiftMinutes: 0),
        ),
        0,
      );
      expect(tierPiastres(_tier(1, null, 'piastres', 5000), _ex), 5000);
    });
  });

  group('TEAM-SET-032/034 the rules Set-up shows and saves', () {
    test(
      'never saved, no ladder stored: the server\'s suggested ladder',
      () async {
        final s = await _settings(rulesNeverSaved);
        final r = SetupRules.from(s);
        expect(r.tiers, isNotEmpty);
        expect(
          [for (final t in r.tiers) t.fromMinutes],
          [for (final t in s.suggestedTiers!) t.fromMinutes],
        );
      },
    );

    test('saved: the stored ladder, even when empty', () async {
      final s = await _settings((db) {
        db['attendance_settings'].firstWhere(
          (r) => r['org_id'] == SeedIds.sabahOrg,
        )!['late_deduction_tiers'] = <Object?>[];
      });
      expect(s.rulesSavedAt, isNotNull);
      expect(SetupRules.from(s).tiers, isEmpty);
    });

    test(
      'the PUT names every rule; the gender mode only with the right',
      () async {
        final r = SetupRules.from(await _settings(rulesNeverSaved));
        final full = r.fullBody(canGender: true).toJson();
        expect(full['gender_mode'], isNotNull);
        expect(full['night_start'], matches(RegExp(r'^\d\d:\d\d:00$')));
        expect(full['late_deduction_tiers'], hasLength(r.tiers.length));
        final open = (full['late_deduction_tiers']! as List).last as Map;
        expect(open.containsKey('to_minutes'), isTrue);
        expect(open['to_minutes'], isNull);
        expect(
          r.fullBody(canGender: false).toJson().containsKey('gender_mode'),
          isFalse,
        );
      },
    );

    test('the example divisor: the rules\' working days, or 30 for none', () {
      expect(
        SetupRules.from(
          AttendanceSettings.fromJson({
            ..._minimalSettings,
            'working_days_per_month': 0,
          }),
        ).exampleWorkingDays,
        30,
      );
    });
  });

  test('TEAM-SET-029 a shift\'s span and its next-day end', () {
    expect(spanMinutes('08:00:00', '16:00:00'), 480);
    expect(spanMinutes('22:00:00', '06:00:00'), 480);
    expect(spanMinutes('09:00:00', '17:30:00'), 510);
    expect(spanMinutes('09:00:00', '09:00:00'), 0);
    expect(spanMinutes(null, '09:00:00'), isNull);
    expect(endsNextDay('22:00:00', '06:00:00'), isTrue);
    expect(endsNextDay('08:00:00', '16:00:00'), isFalse);
  });
}

/// The fields `AttendanceSettings.fromJson` requires, at the server's
/// defaults.
const Map<String, Object?> _minimalSettings = {
  'id': '00000000-0000-0000-0000-000000000001',
  'org_id': '00000000-0000-0000-0000-000000000002',
  'absence_deduction_days': 1,
  'advance_cap_percent': 50,
  'auto_checkout_buffer_minutes': 60,
  'cover_pay_mode': 'minute_rate',
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
  'default_overtime_multiplier': 1.5,
  'excused_time_paid_default': false,
  'gender_mode': 'off',
  'half_day_leave_counts': 'half_shift',
  'holiday_multiplier': 2,
  'late_deduction_tiers': <Object?>[],
  'limit_day_hours': 8,
  'limit_overtime_day_hours': 4,
  'limit_presence_hours': 12,
  'limit_rest_hours': 11,
  'limit_week_hours': 48,
  'night_end': '06:00:00',
  'night_start': '22:00:00',
  'orders_per_staff': 30,
  'overtime_day_multiplier': 1.5,
  'overtime_mode': 'off',
  'overtime_night_multiplier': 2,
  'period_start_day': 1,
  'require_geofence': true,
  'working_days_per_month': 26,
};
