/// The work shift form's rules, as the browser computes them
/// (`staff/work-shift-dialog.tsx`: `SHIFT_PRESETS`, `shiftSchema`,
/// `valuesOf`, `bodyOf`) and the clock arithmetic of a shift that may run
/// past midnight (`inputs/time.ts`: `spanMinutes`, `endsNextDay`,
/// `suggestEnd`, the area's one copy in `shared/time_range_field.dart`).
/// The page, the dialog and their tests share it.
library;

import 'package:dashboard_api/dashboard_api.dart';

export '../shared/time_range_field.dart'
    show endsNextDay, spanMinutes, suggestEnd;

/// The branch select's "Every branch" (`WHOLE_BUSINESS`).
const String wholeBusiness = '__all__';

/// Every weekday, as Postgres DOW (0 = Sunday … 6 = Saturday).
const List<int> allDays = [0, 1, 2, 3, 4, 5, 6];

/// A common shift a new block starts from (TEAM-SHF-012).
typedef ShiftPreset = ({String labelKey, String start, String end});

const List<ShiftPreset> shiftPresets = [
  (labelKey: 'staff.presetMorning', start: '08:00', end: '16:00'),
  (labelKey: 'staff.presetDay', start: '09:00', end: '17:00'),
  (labelKey: 'staff.presetEvening', start: '16:00', end: '00:00'),
  (labelKey: 'staff.presetNight', start: '22:00', end: '06:00'),
];

/// A wire time's `HH:MM`.
String hhmm(String? v) => (v ?? '').length >= 5 ? v!.substring(0, 5) : v ?? '';

/// A figure the way JavaScript writes it: `1.5`, `2`, `1.75`.
String jsFigure(num n) =>
    n == n.roundToDouble() ? n.round().toString() : n.toString();

/// One day's own times (`''` = not set).
typedef DayTimes = ({String start, String end});

/// What the dialog holds while a person edits it. A number field that
/// refused its text hands the form NaN; an optional field left empty is
/// null.
class ShiftValues {
  ShiftValues({
    required this.branchId,
    required this.name,
    required this.start,
    required this.end,
    required this.grace,
    required this.breakMinutes,
    required this.paidBreak,
    required this.halfDay,
    required this.otThreshold,
    required this.otMultiplier,
    required this.otDay,
    required this.otNight,
    required this.checkin,
    required this.isActive,
    required this.validDays,
    required this.dayTimes,
  });

  /// `valuesOf(shift)`: the shift's values, or a new block's defaults
  /// (TEAM-SHF-022): 09:00–17:00, grace 15, no break (paid), overtime after
  /// 15 min ×1.5, the branch's rates, half a shift, check-in 120 min early,
  /// active, every day, every branch.
  factory ShiftValues.of(WorkShift? s) => ShiftValues(
    branchId: s == null ? wholeBusiness : s.branchId ?? wholeBusiness,
    name: s?.name ?? '',
    start: s == null ? '09:00' : hhmm(s.startTime),
    end: s == null ? '17:00' : hhmm(s.endTime),
    grace: (s?.graceMinutes ?? 15).toDouble(),
    breakMinutes: (s?.breakMinutes ?? 0).toDouble(),
    paidBreak: s?.paidBreak ?? true,
    halfDay: s?.halfDayThresholdMinutes?.toDouble(),
    otThreshold: (s?.overtimeThresholdMinutes ?? 15).toDouble(),
    otMultiplier: s?.overtimeMultiplier ?? 1.5,
    otDay: s?.otDayMultiplier,
    otNight: s?.otNightMultiplier,
    checkin: (s?.checkinWindowMinutes ?? 120).toDouble(),
    isActive: s?.isActive ?? true,
    validDays: s != null && s.validDays.isNotEmpty
        ? [...s.validDays]
        : [...allDays],
    dayTimes: {
      for (final d in allDays) d: (start: '', end: ''),
      for (final dt in s?.dayTimes ?? const <DayTime>[])
        dt.dayOfWeek: (start: hhmm(dt.startTime), end: hhmm(dt.endTime)),
    },
  );

  String branchId;
  String name;

  /// `HH:MM`, or what a person typed that is not a time.
  String start;
  String end;
  double? grace;
  double? breakMinutes;
  bool paidBreak;
  double? halfDay;
  double? otThreshold;
  double? otMultiplier;
  double? otDay;
  double? otNight;
  double? checkin;
  bool isActive;
  List<int> validDays;
  Map<int, DayTimes> dayTimes;

  /// Some day has its own times: "Its own times" opens.
  bool get hasDayTimes =>
      dayTimes.values.any((d) => d.start.isNotEmpty || d.end.isNotEmpty);

  /// An optional rate is set: "Overtime and check-in" opens.
  bool get hasOptionalRates =>
      otDay != null || otNight != null || halfDay != null;
}

final RegExp _hhmm = RegExp(r'^\d{2}:\d{2}$');

/// The fields the "Overtime and check-in" section holds.
const Set<String> moreFields = {
  'otThreshold',
  'otMultiplier',
  'otDay',
  'otNight',
  'halfDay',
  'checkin',
};

/// What is wrong with [v] (`shiftSchema`), by field: `name`, `start`, `end`,
/// `grace`, `break`, the [moreFields], `days`, and `day:<dow>` for a day's
/// own times. Empty when it can be saved.
Map<String, String> shiftProblems(ShiftValues v, String Function(String) t) {
  final p = <String, String>{};
  if (v.name.trim().isEmpty) p['name'] = t('staff.errShiftName');
  if (!_hhmm.hasMatch(v.start)) p['start'] = t('staff.errTime');
  if (!_hhmm.hasMatch(v.end)) {
    p['end'] = t('staff.errTime');
  } else if (v.start == v.end) {
    p['end'] = t('staff.errSameTime');
  }
  String? number(double? n, {bool positive = false, bool optional = false}) {
    if (n == null && optional) return null;
    if (n == null || n.isNaN) return t('staff.errNumber');
    if (positive ? n <= 0 : n < 0) {
      return t(positive ? 'staff.errPositive' : 'staff.errNonNegative');
    }
    return null;
  }

  final checks = <String, String?>{
    'grace': number(v.grace),
    'break': number(v.breakMinutes),
    'otThreshold': number(v.otThreshold),
    'otMultiplier': number(v.otMultiplier, positive: true),
    'otDay': number(v.otDay, positive: true, optional: true),
    'otNight': number(v.otNight, positive: true, optional: true),
    'halfDay': number(v.halfDay, positive: true, optional: true),
    'checkin': number(v.checkin, positive: true),
  };
  checks.forEach((k, e) {
    if (e != null) p[k] = e;
  });
  if (v.validDays.isEmpty) p['days'] = t('staff.errNoDays');
  for (final dow in v.validDays) {
    final dt = v.dayTimes[dow] ?? (start: '', end: '');
    if (dt.start.isEmpty && dt.end.isEmpty) continue;
    if (dt.start.isEmpty || dt.end.isEmpty) {
      p['day:$dow'] = t('staff.errBothTimes');
    } else if (!_hhmm.hasMatch(dt.start) || !_hhmm.hasMatch(dt.end)) {
      p['day:$dow'] = t('staff.errTime');
    } else if (dt.start == dt.end) {
      p['day:$dow'] = t('staff.errSameTime');
    }
  }
  return p;
}

/// The request body (`bodyOf`): `branch_id` null for every branch, times
/// `HH:MM:00`, empty optional rates as null (back to the branch's rules),
/// sorted days, and a day's own times only on the block's days.
UpsertWorkShiftRequest shiftBody(ShiftValues v) {
  final days = [...v.validDays]..sort();
  return UpsertWorkShiftRequest(
    branchId: v.branchId == wholeBusiness ? null : v.branchId,
    name: v.name.trim(),
    startTime: '${v.start}:00',
    endTime: '${v.end}:00',
    graceMinutes: v.grace!.round(),
    breakMinutes: v.breakMinutes!.round(),
    paidBreak: v.paidBreak,
    halfDayThresholdMinutes: v.halfDay?.round(),
    overtimeThresholdMinutes: v.otThreshold!.round(),
    overtimeMultiplier: v.otMultiplier,
    otDayMultiplier: v.otDay,
    otNightMultiplier: v.otNight,
    checkinWindowMinutes: v.checkin!.round(),
    isActive: v.isActive,
    validDays: days,
    dayTimes: [
      for (final d in days)
        if (v.dayTimes[d] case final dt?
            when dt.start.isNotEmpty && dt.end.isNotEmpty)
          DayTime(
            dayOfWeek: d,
            startTime: '${dt.start}:00',
            endTime: '${dt.end}:00',
          ),
    ],
    explicitNulls: const {
      'branch_id',
      'half_day_threshold_minutes',
      'ot_day_multiplier',
      'ot_night_multiplier',
    },
  );
}

/// The preset whose label a new block's name may be replaced from: the name
/// is empty or another preset's (TEAM-SHF-012).
bool presetMayRename(String name, Iterable<String> presetLabels) =>
    name.trim().isEmpty || presetLabels.contains(name);
