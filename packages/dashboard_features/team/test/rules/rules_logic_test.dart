// The Rules unit's pure rules (`staff/rules-form.ts`, `rules-preview.ts`,
// `dawam/rules-card.tsx`) and its mock backend's answers, against
// hand-computed figures.
import 'dart:convert';
import 'dart:io';

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_team/src/rules/rules_form.dart';
import 'package:dashboard_team/src/rules/rules_preview.dart';
import 'package:dashboard_team/src/shared/attendance_errors.dart';
import 'package:flutter_test/flutter_test.dart';

import 'rules_support.dart';

RuleTier tier(double from, double? to, TierKind kind, double value) =>
    RuleTier(from: from, to: to, kind: kind, value: value);

const PayExample ex = PayExample(
  salary: 1200000,
  workingDays: 26,
  shiftMinutes: 480,
);

/// The web's English table, as the app loads it.
final Translator en = Translator(
  Strings({
    'en': {
      for (final e in (jsonDecode(
        File('../../dashboard_core/assets/i18n/en.json').readAsStringSync(),
      ) as Map).entries)
        '${e.key}': '${e.value}',
    },
  }),
  'en',
);

Object? body(ApiResponse r) => jsonDecode(utf8.decode(r.bodyBytes));

void main() {
  group('TEAM-RUL-021 pricing a rung (tierPiastres, selectTier)', () {
    test('minutes of pay: salary × minutes / (days × shift)', () {
      // 1,200,000 × 30 / 12,480 = 2,884.6 → 2,885.
      expect(tierPiastres(tier(15, 30, TierKind.minutes, 30), ex), 2885);
    });
    test('a fraction of a day: salary × fraction / days', () {
      expect(tierPiastres(tier(31, 60, TierKind.dayFraction, 0.25), ex), 11538);
    });
    test('a fixed amount is itself, never negative; zero divisors are 0', () {
      expect(tierPiastres(tier(1, null, TierKind.piastres, 5000), ex), 5000);
      expect(tierPiastres(tier(1, null, TierKind.piastres, -5), ex), 0);
      expect(
        tierPiastres(
          tier(1, null, TierKind.minutes, 15),
          ex.copyWith(workingDays: 0),
        ),
        0,
      );
    });
    test('the first rung holding the minutes wins; on time is none', () {
      final ladder = [
        tier(15, 30, TierKind.minutes, 30),
        tier(31, null, TierKind.dayFraction, 0.5),
      ];
      expect(selectTier(ladder, 0), isNull);
      expect(selectTier(ladder, 10), isNull);
      expect(selectTier(ladder, 30), ladder[0]);
      expect(selectTier(ladder, 500), ladder[1]);
    });
    test('TEAM-RUL-025 an absence docks salary × days / working days', () {
      expect(dayPiastres(ex), 46154);
      expect(dayPiastres(ex, 0.5), 23077);
    });
  });

  group('TEAM-RUL-015 the ladder check (tierProblem)', () {
    test('overlap names the minute; inverted; negative; not a number', () {
      expect(
        tierProblem([
          tier(1, 15, TierKind.minutes, 15),
          tier(15, 30, TierKind.minutes, 30),
        ]),
        (key: 'staff.tierOverlap', n: 15.0),
      );
      expect(
        tierProblem([tier(20, 10, TierKind.minutes, 1)])?.key,
        'staff.tierInverted',
      );
      expect(
        tierProblem([tier(-1, 10, TierKind.minutes, 1)])?.key,
        'staff.tierNegative',
      );
      expect(
        tierProblem([tier(1, 10, TierKind.minutes, -1)])?.key,
        'staff.tierNegativeValue',
      );
      expect(
        tierProblem([tier(double.nan, 10, TierKind.minutes, 1)])?.key,
        'staff.tierNotANumber',
      );
    });
    test('an open rung after others is fine; one before them overlaps', () {
      expect(
        tierProblem([
          tier(1, 15, TierKind.minutes, 15),
          tier(16, null, TierKind.dayFraction, 1),
        ]),
        isNull,
      );
      expect(
        tierProblem([
          tier(1, null, TierKind.minutes, 15),
          tier(16, 30, TierKind.dayFraction, 1),
        ])?.key,
        'staff.tierOverlap',
      );
    });
    test('TEAM-RUL-014 the next rung starts after the last end', () {
      expect(
        nextTier([tier(1, 15, TierKind.minutes, 15)]),
        tier(16, 30, TierKind.minutes, 15),
      );
      expect(nextTier(const []), tier(1, 15, TierKind.minutes, 15));
    });
  });

  group('TEAM-RUL-038 the Dawam checks (rulesRequest)', () {
    const d = DawamRules.defaults;
    test('each range refuses with its words', () {
      expect(rulesRequest(d).error, isNull);
      expect(
        rulesRequest(d.copyWith(otDay: () => 0.9)).error,
        'dawam.rulesRateLow',
      );
      expect(
        rulesRequest(d.copyWith(advanceCap: () => 101)).error,
        'dawam.rulesCapRange',
      );
      expect(
        rulesRequest(d.copyWith(periodStartDay: () => 29)).error,
        'dawam.rulesStartDay',
      );
      expect(
        rulesRequest(d.copyWith(limitRest: () => 0)).error,
        'dawam.rulesLimitRange',
      );
      expect(
        rulesRequest(d.copyWith(ordersPerStaff: () => 2.5)).error,
        'dawam.rulesOrdersPerStaff',
      );
      expect(rulesRequest(d.copyWith(nightStart: '9pm')).error,
          'dawam.rulesNight');
    });
    test('gender rides only with the right; times gain seconds', () {
      expect(rulesRequest(d).ok!.containsKey('gender_mode'), isFalse);
      final ok = rulesRequest(d, canGender: true).ok!;
      expect(ok['gender_mode'], 'off');
      expect(ok['night_start'], '22:00:00');
    });
  });

  group('TEAM-RUL-042/044 what a branch sends (branchBody)', () {
    final loaded = RulesValues.empty;
    test('nothing changed and nothing handed back → nothing to send', () {
      expect(branchBody('b', loaded, loaded, const []), isNull);
    });
    test('only the changes, never a business-only rule; inherit wins', () {
      final v = loaded.copyWith(
        workingDays: () => 24,
        dawam: loaded.dawam.copyWith(advanceCap: () => 30, limitDay: () => 9),
      );
      expect(branchBody('b', v, loaded, const ['limit_day_hours']), {
        'working_days_per_month': 24,
        'branch_id': 'b',
        'inherit': ['limit_day_hours'],
      });
    });
    test('a forced rule is sent at the same value', () {
      expect(branchBody('b', loaded, loaded, const [], const ['cover_pay_mode']),
          {'cover_pay_mode': 'minute_rate', 'branch_id': 'b'});
    });
  });

  group('TEAM-RUL-043 the change lines (describeChange)', () {
    final t = en;
    const f = DashFormat();
    test('booleans, none, ladders, times, choices', () {
      expect(
        describeChange((name: 'x', before: true, after: false), t, f),
        'Yes → No',
      );
      expect(
        describeChange((name: 'x', before: null, after: 3), t, f),
        'none → 3',
      );
      expect(
        describeChange(
          (name: 'late_deduction_tiers', before: [1, 2], after: [1, 3]),
          t,
          f,
        ),
        '2 rungs → 2 rungs (edited)',
      );
      expect(
        describeChange(
          (name: 'night_start', before: '22:00:00', after: '23:30:00'),
          t,
          f,
        ),
        '10:00 PM → 11:30 PM',
      );
      expect(
        describeChange(
          (name: 'overtime_mode', before: 'off', after: 'approval'),
          t,
          f,
        ),
        'Off → When a manager approves',
      );
    });
  });

  group('TEAM-ALL-019 a refused rule named by its label', () {
    final t = en;
    const f = DashFormat();
    ApiException refusal(Map<String, Object?> vars) => ApiException(
      status: 400,
      code: 'SETTING_OUT_OF_RANGE',
      message: 'x',
      details: {'error': 'x', 'code': 'SETTING_OUT_OF_RANGE', 'vars': vars},
    );
    String words(Map<String, Object?> vars) => attendanceErrorText(
      refusal(vars),
      t,
      f,
      fieldLabel: (n) => ruleLabel(n, t),
    );
    test('the four shapes', () {
      expect(
        words({'field': 'absence_deduction_days', 'min': 0, 'max': 31}),
        'Days docked per absence must be from 0 to 31.',
      );
      expect(
        words({
          'field': 'working_days_per_month',
          'min': 0,
          'max': 31,
          'min_inclusive': false,
        }),
        'Working days per month must be more than 0 and at most 31.',
      );
      expect(
        words({
          'field': 'overtime_day_multiplier',
          'min': 1,
          'max': 100,
          'max_inclusive': false,
        }),
        'Day rate × must be from 1 and less than 100.',
      );
      expect(
        words({
          'field': 'cover_pay_mode',
          'allowed': ['minute_rate'],
        }),
        "Cover pay: that value isn't one of the allowed choices.",
      );
    });
  });

  group('the mock backend', () {
    Future<ApiResponse> send(
      Srv s,
      String method,
      String path, {
      Object? body,
      Map<String, List<String>> query = const {},
    }) => s.server.send(
      ApiRequest(method: method, path: path, body: body, query: query),
    );

    test('a branch reads the business under its own overrides', () async {
      final s = rulesServer();
      final r = await send(
        s,
        'GET',
        settingsT,
        query: {
          'branch_id': [SeedIds.zamalek],
        },
      );
      final j = body(r)! as Map;
      expect(j['limit_day_hours'], 10.0);
      expect(j['working_days_per_month'], 26);
      expect(j['overridden'], [
        'auto_checkout_buffer_minutes',
        'limit_day_hours',
      ]);
    });

    test('refusals: overlap, a business-only rule from a branch, inherit '
        'from the business, gender without the right', () async {
      final s = rulesServer();
      Future<int> status(Srv on, Map<String, Object?> b) async {
        try {
          return (await send(on, 'PUT', settingsT, body: b)).status;
        } on ApiException catch (e) {
          return e.status;
        }
      }

      expect(
        await status(s, {
          'late_deduction_tiers': [
            {'from_minutes': 1, 'to_minutes': 15, 'kind': 'minutes', 'value': 1},
            {'from_minutes': 10, 'to_minutes': 20, 'kind': 'minutes', 'value': 1},
          ],
        }),
        400,
      );
      expect(
        await status(s, {
          'branch_id': SeedIds.maadi,
          'advance_cap_percent': 10,
        }),
        400,
      );
      expect(
        await status(s, {
          'inherit': ['limit_day_hours'],
        }),
        400,
      );
      expect(
        await status(rulesServer(persona: Persona.manager), {
          'gender_mode': 'hard',
        }),
        403,
      );
    });

    test('the first save of the ladder and the absence cost stamps '
        'rules_saved_at once', () async {
      final s = rulesServer(edit: neverSaved);
      await send(s, 'PUT', settingsT, body: {'working_days_per_month': 25});
      var j = body(await send(s, 'GET', settingsT))! as Map;
      expect(j['rules_saved_at'], isNull);
      await send(s, 'PUT', settingsT, body: {
        'late_deduction_tiers': const <Object?>[],
        'absence_deduction_days': 1,
      });
      j = body(await send(s, 'GET', settingsT))! as Map;
      expect(j['rules_saved_at'], isNotNull);
    });

    test('follow the business drops every override', () async {
      final s = rulesServer();
      final r = await send(
        s,
        'DELETE',
        '/staff/attendance/settings/branches/${SeedIds.zamalek}',
      );
      expect(r.status, 204);
      final list = body(await send(s, 'GET', branchesT))! as List;
      expect(
        list.every((b) => ((b as Map)['overridden'] as List).isEmpty),
        isTrue,
      );
    });
  });
}
