/// The reporting period: the web's presets (`src/data/scope/presets.ts`), the
/// custom range, and the trend granularity the pages derive from them.
library;

import 'package:dashboard_core/src/format/format.dart';
import 'package:dashboard_core/src/format/tz.dart';

/// `ScopePreset`; [wire] is the web's value (`7d`, `30d`, …).
enum ScopePreset {
  today('today'),
  yesterday('yesterday'),
  last7Days('7d'),
  last30Days('30d'),
  monthToDate('mtd'),
  custom('custom');

  const ScopePreset(this.wire);

  final String wire;

  /// The i18n key of its label (`scope.preset.7d`).
  String get labelKey => 'scope.preset.$wire';

  /// The web's English fallback for [labelKey].
  String get fallback => switch (this) {
    today => 'Today',
    yesterday => 'Yesterday',
    last7Days => 'Last 7 days',
    last30Days => 'Last 30 days',
    monthToDate => 'Month to date',
    custom => 'Custom',
  };

  static ScopePreset? fromWire(String? wire) {
    for (final p in values) {
      if (p.wire == wire) return p;
    }
    return null;
  }
}

/// The presets the picker offers, in order (`SCOPE_PRESETS`; not `custom`).
const List<ScopePreset> scopePresets = [
  ScopePreset.today,
  ScopePreset.yesterday,
  ScopePreset.last7Days,
  ScopePreset.last30Days,
  ScopePreset.monthToDate,
];

/// The default period (`DEFAULT_PRESET`): one the app can resolve itself.
const ScopePreset defaultPreset = ScopePreset.last30Days;

/// A resolved period: UTC ISO instants (`2026-03-07T22:00:00.000Z`).
class PeriodRange {
  const PeriodRange(this.from, this.to);

  final String from;
  final String to;

  DateTime get fromInstant => DateTime.parse(from);
  DateTime get toInstant => DateTime.parse(to);

  @override
  bool operator ==(Object other) =>
      other is PeriodRange && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => 'PeriodRange($from, $to)';
}

/// [from, to] for a named preset, day-bounded in [zone]'s calendar
/// (`rangeForPreset`). Day offsets are calendar arithmetic in the zone, so DST
/// days stay 23/25 hours long.
PeriodRange rangeForPreset(ScopePreset preset, String zone, DateTime now) {
  assert(preset != ScopePreset.custom, 'custom carries its own dates');
  final n = inZone(now, zone);
  final y = n.year;
  final m0 = n.month - 1;
  final d = n.day;
  // `new TZDate(y, m, d + offset, tz)`: normalised in the zone.
  ({int y, int m0, int d}) day(int offset) {
    final p = DateTime.utc(y, m0 + 1, d + offset);
    return (y: p.year, m0: p.month - 1, d: p.day);
  }

  String start(({int y, int m0, int d}) p) =>
      dayBoundaryISO(zone, p.y, p.m0, p.d);
  String end(({int y, int m0, int d}) p) =>
      dayBoundaryISO(zone, p.y, p.m0, p.d, endOfDay: true);
  return switch (preset) {
    ScopePreset.today => PeriodRange(start(day(0)), end(day(0))),
    ScopePreset.yesterday => PeriodRange(start(day(-1)), end(day(-1))),
    ScopePreset.last7Days => PeriodRange(start(day(-6)), end(day(0))),
    ScopePreset.last30Days => PeriodRange(start(day(-29)), end(day(0))),
    ScopePreset.monthToDate => PeriodRange(
      dayBoundaryISO(zone, y, m0, 1),
      end(day(0)),
    ),
    ScopePreset.custom => throw ArgumentError.value(preset),
  };
}

/// A custom range from two calendar days (inclusive) as the date picker
/// sends it: the start of [first] to the last millisecond of [last], in
/// [zone]. Only the year/month/day of each [DateTime] are read.
PeriodRange customDaysRange(String zone, DateTime first, DateTime last) =>
    PeriodRange(
      dayBoundaryISO(zone, first.year, first.month - 1, first.day),
      dayBoundaryISO(zone, last.year, last.month - 1, last.day, endOfDay: true),
    );

/// The trend granularity the overview derives: hourly for the intraday
/// presets, daily otherwise (custom included).
String trendGranularity(ScopePreset preset) =>
    preset == ScopePreset.today || preset == ScopePreset.yesterday
    ? 'hourly'
    : 'daily';
