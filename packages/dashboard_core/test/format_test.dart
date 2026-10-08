// The web's src/lib/format.test.ts, translated with the same expectations,
// plus every vector the web's own format.ts / presets.ts / excel.ts produced
// under Node (tool/gen_format_vectors.mjs -> test/fixtures/format_vectors.json).
import 'dart:convert';
import 'dart:io';

import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_test/flutter_test.dart';

DashFormat _f(String lang, [String tz = 'Africa/Cairo']) =>
    DashFormat(lang: lang, timezone: tz);

NumberOptions _numberOptions(Object? o) {
  if (o is! Map) return const NumberOptions();
  return NumberOptions(
    minimumFractionDigits: o['minimumFractionDigits'] as int?,
    maximumFractionDigits: o['maximumFractionDigits'] as int?,
    signDisplay: switch (o['signDisplay']) {
      'exceptZero' => SignDisplay.exceptZero,
      'always' => SignDisplay.always,
      'never' => SignDisplay.never,
      _ => SignDisplay.auto,
    },
  );
}

ScopePreset _preset(String wire) => ScopePreset.fromWire(wire)!;

/// Runs one vector through the Dart port.
Object? _run(Map<String, Object?> v) {
  final lang = v['lang']! as String;
  final tz = v['tz']! as String;
  final a = (v['args']! as List).cast<Object?>();
  final f = _f(lang, tz);
  num? n(Object? x) => x as num?;
  switch (v['fn']) {
    case 'fmtMoney':
      final o = a[1] as Map?;
      return f.fmtMoney(
        n(a[0]),
        fractionDigits: o?['fractionDigits'] as int?,
        maxFractionDigits: o?['maxFractionDigits'] as int?,
        signed: o?['signed'] == true,
        currency: o?['currency'] != false,
      );
    case 'fmtMoneySigned':
      return f.fmtMoneySigned(n(a[0]));
    case 'fmtMoneyCompact':
      return f.fmtMoneyCompact(n(a[0]));
    case 'fmtNumber':
      return f.fmtNumber(n(a[0]), _numberOptions(a[1]));
    case 'fmtNumberCompact':
      return f.fmtNumberCompact(n(a[0]));
    case 'fmtPercent':
      return f.fmtPercent(n(a[0])!);
    case 'fmtShare':
      return f.fmtShare(n(a[0])!, n(a[1])!);
    case 'currencyLabel':
      return f.currencyLabel(a[0] as String?);
    case 'fmtDate':
      return f.fmtDate(a[0]);
    case 'fmtTime':
      return f.fmtTime(a[0], a[1] as String?);
    case 'fmtDateTime':
      return f.fmtDateTime(a[0], a[1] as String?);
    case 'fmtDateTimeFull':
      return f.fmtDateTimeFull(a[0]);
    case 'fmtPeriod':
      return f.fmtPeriodNamed(a[0]! as String, a[1]! as String);
    case 'fmtStamp':
      return f.fmtStamp(a[0], DateTime.parse(a[1]! as String));
    case 'fmtElapsedMs':
      final x = a[0];
      return f.fmtElapsedMs(x is String ? double.parse(x) : x! as num);
    case 'fmtDuration':
      return f.fmtDuration(a[0], a[1]);
    case 'fmtHour':
      return f.fmtHour(a[0]! as int);
    case 'fmtWireTime':
      return f.fmtWireTime(a[0]! as String);
    case 'initials':
      return initials(a[0]! as String);
    case 'fmtUnit':
      return fmtUnit(a[0] as String?);
    case 'rateOf':
      final d = a[0]! as Map;
      return rateOf(
        value: d['value']! as num,
        valueRate: d['value_rate'] as num?,
        dtype: d['dtype'] as String?,
      );
    case 'cairoDateISO':
      return f.cairoDateISO(
        a[0]! as int,
        a[1]! as int,
        a[2]! as int,
        endOfDay: a[3]! as bool,
      );
    case 'cairoParts':
      final p = f.cairoParts(a[0]! as String);
      return {'y': p.y, 'm': p.m, 'd': p.d};
    case 'rangeForPreset':
      final r = rangeForPreset(
        _preset(a[0]! as String),
        tz,
        DateTime.fromMillisecondsSinceEpoch(a[1]! as int, isUtc: true),
      );
      return {'from': r.from, 'to': r.to};
    case 'toExcelDateSerial':
      return toExcelDateSerial(DateTime.parse(a[0]! as String), tz);
  }
  throw StateError('no runner for ${v['fn']}');
}

void main() {
  setUpAll(ensureTimeZones);

  group('money (POS shape)', () {
    test('English: label first, grouped, two decimals, true minus', () {
      final f = _f('en');
      expect(f.fmtMoney(123450), 'EGP 1,234.50');
      expect(f.fmtMoney(-5000), '−EGP 50.00');
      expect(f.fmtMoneySigned(2000), '+EGP 20.00');
      expect(f.fmtMoney(0), 'EGP 0.00');
      expect(f.fmtMoney(null), '—');
      expect(f.fmtMoney(123456, maxFractionDigits: 0), 'EGP 1,235');
    });

    test('Arabic: Western digits, LTR-isolated figure, label after', () {
      final f = _f('ar');
      expect(f.fmtMoney(123450), '\u20661,234.50\u2069 ج.م');
      expect(f.fmtMoney(-5000), '\u2066−50.00\u2069 ج.م');
      expect(f.fmtNumber(1234), '1,234');
    });
  });

  group('elapsed + stamps', () {
    test('elapsed drops seconds and pads', () {
      final f = _f('en');
      expect(f.fmtElapsedMs(0), '0m');
      expect(f.fmtElapsedMs(42 * 60000), '42m');
      expect(f.fmtElapsedMs(65 * 60000), '1h 05m');
      expect(f.fmtElapsedMs((27 * 60 + 5) * 60000), '1d 03h');
    });

    test('stamps are 12h in the branch timezone', () {
      final f = _f('en');
      final now = DateTime.parse('2026-09-12T20:00:00Z'); // 23:00 Cairo
      expect(f.fmtStamp('2026-09-12T15:02:00Z', now), '06:02 PM');
      expect(
        f.fmtStamp('2026-09-10T15:02:00Z', now),
        matches(RegExp(r'10 Sept?\s·\s06:02 PM')),
      );
      expect(
        f.fmtStamp('2025-12-31T21:30:00Z', now),
        matches(RegExp(r'31 Dec 2025\s·\s11:30 PM')),
      );
    });

    test('clock labels are 12h, midnight and noon included', () {
      final f = _f('en');
      expect(f.fmtHour(0), '12:00 AM');
      expect(f.fmtHour(12), '12:00 PM');
      expect(f.fmtHour(13), '01:00 PM');
      expect(f.fmtWireTime('00:05'), '12:05 AM');
      expect(f.fmtWireTime('18:02'), '06:02 PM');
      // Never a 24-hour hour.
      for (var h = 0; h < 24; h++) {
        final hour = int.parse(f.fmtHour(h).substring(0, 2));
        expect(hour, inInclusiveRange(1, 12));
      }
      // Not a clock time -> untouched.
      expect(f.fmtWireTime(''), '');
      expect(f.fmtWireTime('nope'), 'nope');
    });

    test('Arabic uses ص / م, with Western figures', () {
      final f = _f('ar');
      expect(f.fmtHour(9), '09:00 ص');
      expect(f.fmtHour(18), '06:00 م');
    });
  });

  group('rangeForPreset timezone (presets.test.ts)', () {
    // 2026-03-08 15:00 UTC: US DST starts that morning.
    final now = DateTime.utc(2026, 3, 8, 15);

    test('New York and Cairo branches get different today boundaries', () {
      final ny = rangeForPreset(ScopePreset.today, 'America/New_York', now);
      final cairo = rangeForPreset(ScopePreset.today, 'Africa/Cairo', now);
      expect(cairo.from, '2026-03-07T22:00:00.000Z');
      expect(cairo.to, '2026-03-08T21:59:59.999Z');
      expect(ny.from, '2026-03-08T05:00:00.000Z');
      expect(ny.from, isNot(cairo.from));
    });

    test('handles the DST transition day (23h day)', () {
      final ny = rangeForPreset(ScopePreset.today, 'America/New_York', now);
      expect(ny.to, '2026-03-09T03:59:59.999Z');
      expect(
        ny.toInstant.difference(ny.fromInstant).inMilliseconds + 1,
        23 * 3600000,
      );
      final y = rangeForPreset(
        ScopePreset.yesterday,
        'America/New_York',
        DateTime.utc(2026, 3, 9, 15),
      );
      expect(
        y,
        const PeriodRange(
          '2026-03-08T05:00:00.000Z',
          '2026-03-09T03:59:59.999Z',
        ),
      );
      expect(
        rangeForPreset(ScopePreset.last7Days, 'America/New_York', now).from,
        '2026-03-02T05:00:00.000Z',
      );
      expect(
        rangeForPreset(ScopePreset.monthToDate, 'America/New_York', now).from,
        '2026-03-01T05:00:00.000Z',
      );
      expect(
        rangeForPreset(ScopePreset.last30Days, 'Africa/Cairo', now).from,
        '2026-02-06T22:00:00.000Z',
      );
    });

    test('trend granularity: hourly for intraday presets only', () {
      expect(trendGranularity(ScopePreset.today), 'hourly');
      expect(trendGranularity(ScopePreset.yesterday), 'hourly');
      for (final p in [
        ScopePreset.last7Days,
        ScopePreset.last30Days,
        ScopePreset.monthToDate,
        ScopePreset.custom,
      ]) {
        expect(trendGranularity(p), 'daily');
      }
    });
  });

  group('misc', () {
    test('piastres <-> pounds round, never truncate', () {
      expect(egpToPiastres(19.99), 1999);
      expect(piastresToEgp(1999), 19.99);
      expect(egpToPiastres(-1.005), -100);
    });
  });

  group('the web vectors', () {
    final file = File('test/fixtures/format_vectors.json');
    final doc = json.decode(file.readAsStringSync()) as Map<String, Object?>;
    final vectors = (doc['vectors']! as List).cast<Map<String, Object?>>();

    test('there are vectors for every function', () {
      expect(vectors.length, greaterThan(2000));
    });

    test('every vector matches the web', () {
      final failures = <String>[];
      for (final v in vectors) {
        final want = v['out'];
        Object? got;
        try {
          got = _run(v);
        } on Object catch (e) {
          got = {'error': '$e'};
        }
        bool same;
        if (want is Map && want.containsKey('error')) {
          same = got is Map && got.containsKey('error');
        } else if (want is num && got is num) {
          same = (want - got).abs() < 1e-9;
        } else if (want is Map && got is Map) {
          same = json.encode(want) == json.encode(got);
        } else {
          same = want == got;
        }
        if (!same) {
          failures.add(
            '${v['fn']} ${v['lang']} ${v['tz']} ${json.encode(v['args'])}: '
            'web ${json.encode(want)} dart ${json.encode(got)}',
          );
        }
      }
      expect(failures, isEmpty, reason: failures.take(40).join('\n'));
    });
  });
}
