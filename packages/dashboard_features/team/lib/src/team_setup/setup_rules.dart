/// What Set-up's rules step (TEAM-SET-031…035) reads and sends: the web's
/// `staff/rules-form.ts` `valuesFrom(settings, {suggest: true})` and
/// `fullBody`, `dawam/rules-card.tsx` `rulesFrom` / `rulesRequest`, and
/// `staff/rules-preview.ts` `tierPiastres`. Only the parts the step uses: it
/// shows the values and saves them unchanged. Pure, so it is tested
/// directly.
library;

import 'package:dashboard_api/dashboard_api.dart';

import 'geo.dart' show jsNumber;

/// One rung of the late-penalty ladder, in the shape the API stores.
class SetupTier {
  const SetupTier({
    required this.fromMinutes,
    required this.toMinutes,
    required this.kind,
    required this.value,
  });

  /// From a stored or suggested rung (raw JSON or a [LateTier]).
  factory SetupTier.fromJson(Map<String, Object?> j) => SetupTier(
    fromMinutes: (j['from_minutes']! as num).toInt(),
    toMinutes: (j['to_minutes'] as num?)?.toInt(),
    kind: j['kind']! as String,
    value: (j['value']! as num).toDouble(),
  );

  final int fromMinutes;

  /// Null = the open-ended top rung.
  final int? toMinutes;

  /// `minutes`, `piastres` or `day_fraction`.
  final String kind;
  final double value;

  LateTier toLateTier() => LateTier(
    fromMinutes: fromMinutes,
    toMinutes: toMinutes,
    kind: LateDeductionKind.fromJson(kind),
    value: value,
    // The web sends `to_minutes: null` for the open rung.
    explicitNulls: toMinutes == null ? const {'to_minutes'} : const {},
  );
}

/// The rules as Set-up shows and saves them (`RulesValues` + `DawamRules`),
/// each figure kept as the web's form strings would print it.
class SetupRules {
  const SetupRules({
    required this.tiers,
    required this.absenceDays,
    required this.workingDays,
    required this.autoBuffer,
    required this.excusedPaid,
    required this.overtimeMode,
    required this.otDay,
    required this.otNight,
    required this.holidayMult,
    required this.advanceCap,
    required this.periodStartDay,
    required this.halfDay,
    required this.nightStart,
    required this.nightEnd,
    required this.genderMode,
    required this.limitDay,
    required this.limitWeek,
    required this.limitPresence,
    required this.limitRest,
    required this.limitOtDay,
    required this.ordersPerStaff,
    required this.coverPayMode,
  });

  final List<SetupTier> tiers;
  final double absenceDays;
  final double workingDays;
  final int autoBuffer;
  final bool excusedPaid;

  /// `off`, `automatic` or `approval`.
  final String overtimeMode;
  final double otDay;
  final double otNight;
  final double holidayMult;
  final double advanceCap;
  final int periodStartDay;
  final String halfDay;

  /// `HH:MM`.
  final String nightStart;
  final String nightEnd;
  final String genderMode;
  final double limitDay;
  final double limitWeek;
  final double limitPresence;
  final double limitRest;
  final double limitOtDay;
  final int ordersPerStaff;
  final String coverPayMode;

  /// `valuesFrom(s, {suggest: true})`: a business that never saved its rules
  /// and stores no ladder starts from the server's suggested one.
  factory SetupRules.from(AttendanceSettings s) {
    final stored = _tiersOf(s.lateDeductionTiers);
    final suggested = [
      for (final t in s.suggestedTiers ?? const <LateTier>[])
        SetupTier.fromJson(t.toJson()),
    ];
    final tiers = s.rulesSavedAt == null && stored.isEmpty ? suggested : stored;
    // `(s.night_start ?? "22:00").slice(0, 5)`: the wire always sends one.
    String hhmm(String v) => v.length >= 5 ? v.substring(0, 5) : v;
    return SetupRules(
      tiers: tiers,
      absenceDays: s.absenceDeductionDays,
      workingDays: s.workingDaysPerMonth,
      autoBuffer: s.autoCheckoutBufferMinutes,
      excusedPaid: s.excusedTimePaidDefault,
      overtimeMode: const ['off', 'automatic', 'approval'].contains(s.overtimeMode)
          ? s.overtimeMode
          : 'off',
      otDay: s.overtimeDayMultiplier,
      otNight: s.overtimeNightMultiplier,
      holidayMult: s.holidayMultiplier,
      advanceCap: s.advanceCapPercent,
      periodStartDay: s.periodStartDay,
      halfDay: s.halfDayLeaveCounts == 'whole_day' ? 'whole_day' : 'half_shift',
      nightStart: hhmm(s.nightStart),
      nightEnd: hhmm(s.nightEnd),
      genderMode: const ['off', 'soft', 'hard'].contains(s.genderMode)
          ? s.genderMode
          : 'off',
      limitDay: s.limitDayHours,
      limitWeek: s.limitWeekHours,
      limitPresence: s.limitPresenceHours,
      limitRest: s.limitRestHours,
      limitOtDay: s.limitOvertimeDayHours,
      ordersPerStaff: s.ordersPerStaff,
      coverPayMode: s.coverPayMode == 'full_block' ? 'full_block' : 'minute_rate',
    );
  }

  static List<SetupTier> _tiersOf(Object? raw) => [
    if (raw is List)
      for (final t in raw)
        if (t is Map) SetupTier.fromJson(t.cast<String, Object?>()),
  ];

  /// The working-days divisor of the worked example: the rules' own, or 30
  /// (`Number(values.workingDays) || 30`).
  double get exampleWorkingDays => workingDays == 0 ? 30 : workingDays;

  /// `fullBody(values, canGender)`: every rule, as the PUT names them. The
  /// gender mode rides only for someone holding `hr.roster.settings`.
  PutAttendanceSettingsRequest fullBody({required bool canGender}) =>
      PutAttendanceSettingsRequest(
        overtimeMode: overtimeMode,
        overtimeDayMultiplier: otDay,
        overtimeNightMultiplier: otNight,
        holidayMultiplier: holidayMult,
        advanceCapPercent: advanceCap,
        periodStartDay: periodStartDay,
        halfDayLeaveCounts: halfDay,
        nightStart: _hhmmss(nightStart),
        nightEnd: _hhmmss(nightEnd),
        limitDayHours: limitDay,
        limitWeekHours: limitWeek,
        limitPresenceHours: limitPresence,
        limitRestHours: limitRest,
        limitOvertimeDayHours: limitOtDay,
        ordersPerStaff: ordersPerStaff,
        coverPayMode: coverPayMode,
        genderMode: canGender ? genderMode : null,
        lateDeductionTiers: [for (final t in tiers) t.toLateTier()],
        absenceDeductionDays: absenceDays,
        workingDaysPerMonth: workingDays,
        autoCheckoutBufferMinutes: autoBuffer,
        excusedTimePaidDefault: excusedPaid,
      );

  /// What an absence docks, as the web prints the form's string.
  String get absenceDaysText => jsNumber(absenceDays);
}

String _hhmmss(String s) => s.length == 5 ? '$s:00' : s;

/// A pay example for the worked figures (`PayExample`).
class PayExample {
  const PayExample({
    required this.salary,
    required this.workingDays,
    required this.shiftMinutes,
  });

  /// Set-up's example: EGP 12,000 a month, a 480-minute shift.
  static const int setupSalary = 1200000;
  static const int setupShiftMinutes = 480;

  /// Monthly salary, piastres.
  final int salary;
  final double workingDays;

  /// The shift's scheduled minutes a day (the minute-rate divisor).
  final int shiftMinutes;
}

/// `Math.sign(x) * Math.round(Math.abs(x))`.
int _roundHalfAway(double x) =>
    x < 0 ? -((-x) + 0.5).floor() : (x + 0.5).floor();

/// What a rung costs in piastres for one pay example (`tierPiastres`,
/// mirroring the server's `late_deduction_piastres`).
int tierPiastres(SetupTier tier, PayExample ex) {
  int nonNeg(int v) => v < 0 ? 0 : v;
  if (tier.kind == 'piastres') return nonNeg(_roundHalfAway(tier.value));
  if (ex.workingDays <= 0) return 0;
  if (tier.kind == 'day_fraction') {
    return nonNeg(_roundHalfAway(ex.salary * tier.value / ex.workingDays));
  }
  if (ex.shiftMinutes <= 0) return 0;
  return nonNeg(
    _roundHalfAway(
      ex.salary * tier.value / (ex.workingDays * ex.shiftMinutes),
    ),
  );
}
