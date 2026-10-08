/// The Rules page's form model (`staff/rules-form.ts`, `dawam/rules-card.tsx`
/// `rulesFrom` / `rulesRequest`, RU-1, RU-2): the values the page edits, the
/// checks that refuse them, and what a save sends.
///
/// The business saves every rule in one PUT. A branch saves only the rules it
/// changed (they become its overrides) plus `inherit`, the rules it hands back
/// to the business; the server merges branch over business field by field and
/// says which fields a branch sets itself (`overridden`). Nothing here decides
/// a figure: the server validates again and prices from what it stored.
///
/// Numbers the person types are `double?`: null is an empty field, NaN is
/// text the field could not read (the kit's number field hands it on so a
/// save refuses it), exactly as the web's `Number("")` / `Number("NaN")`.
library;

import 'package:collection/collection.dart';
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter/foundation.dart';

/// How a rung charges (`LateDeductionKind`).
enum TierKind {
  minutes('minutes'),
  piastres('piastres'),
  dayFraction('day_fraction');

  const TierKind(this.wire);
  final String wire;

  static TierKind fromWire(Object? v) =>
      values.firstWhere((k) => k.wire == v, orElse: () => TierKind.minutes);
}

/// One rung of the late-penalty ladder, as the form holds it.
@immutable
class RuleTier {
  const RuleTier({
    required this.from,
    required this.to,
    required this.kind,
    required this.value,
  });

  /// From a stored rung (`{from_minutes, to_minutes, kind, value}`).
  factory RuleTier.fromJson(Map<Object?, Object?> j) => RuleTier(
    from: (j['from_minutes'] as num?)?.toDouble() ?? double.nan,
    to: (j['to_minutes'] as num?)?.toDouble(),
    kind: TierKind.fromWire(j['kind']),
    value: (j['value'] as num?)?.toDouble() ?? double.nan,
  );

  factory RuleTier.fromLateTier(LateTier t) => RuleTier(
    from: t.fromMinutes.toDouble(),
    to: t.toMinutes?.toDouble(),
    kind: TierKind.fromWire(t.kind.toJson()),
    value: t.value,
  );

  /// Minutes past grace the rung starts at (NaN: not a number).
  final double from;

  /// Where it ends; null = no limit (NaN: not a number).
  final double? to;
  final TierKind kind;

  /// Minutes of pay, a fraction of a day, or piastres.
  final double value;

  RuleTier copyWith({
    double? from,
    double? Function()? to,
    TierKind? kind,
    double? value,
  }) => RuleTier(
    from: from ?? this.from,
    to: to == null ? this.to : to(),
    kind: kind ?? this.kind,
    value: value ?? this.value,
  );

  /// The rung as the PUT sends it (one key order, `to_minutes` always sent).
  Map<String, Object?> toWire() => {
    'from_minutes': wireNum(from),
    'to_minutes': to == null ? null : wireNum(to!),
    'kind': kind.wire,
    'value': wireNum(value),
  };

  @override
  bool operator ==(Object other) =>
      other is RuleTier &&
      other.from == from &&
      other.to == to &&
      other.kind == kind &&
      other.value == value;

  @override
  int get hashCode => Object.hash(from, to, kind, value);

  @override
  String toString() => 'RuleTier(${toWire()})';
}

/// A number as JSON carries it: whole numbers as integers (the web's
/// `JSON.stringify(7)` is `7`, never `7.0`).
Object wireNum(num n) =>
    n is double && n.isFinite && n == n.roundToDouble() && n.abs() < 1e15
    ? n.toInt()
    : n;

/// How a confirmed cover is paid (owner decision D5).
const String coverMinuteRate = 'minute_rate';
const String coverFullBlock = 'full_block';

/// The Dawam rules beside the ladder (`DawamRules`).
@immutable
class DawamRules {
  const DawamRules({
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

  /// `DEFAULT_RULES`.
  static const DawamRules defaults = DawamRules(
    overtimeMode: 'off',
    otDay: 1.35,
    otNight: 1.7,
    holidayMult: 2,
    advanceCap: 50,
    periodStartDay: 1,
    halfDay: 'half_shift',
    nightStart: '22:00',
    nightEnd: '06:00',
    genderMode: 'off',
    limitDay: 8,
    limitWeek: 48,
    limitPresence: 10,
    limitRest: 12,
    limitOtDay: 2,
    ordersPerStaff: 12,
    coverPayMode: coverMinuteRate,
  );

  /// `rulesFrom(settings)`.
  factory DawamRules.from(AttendanceSettings s) => DawamRules(
    overtimeMode:
        const ['off', 'automatic', 'approval'].contains(s.overtimeMode)
        ? s.overtimeMode
        : 'off',
    otDay: s.overtimeDayMultiplier,
    otNight: s.overtimeNightMultiplier,
    holidayMult: s.holidayMultiplier,
    advanceCap: s.advanceCapPercent,
    periodStartDay: s.periodStartDay.toDouble(),
    halfDay: s.halfDayLeaveCounts == 'whole_day' ? 'whole_day' : 'half_shift',
    nightStart: _hhmm(s.nightStart, '22:00'),
    nightEnd: _hhmm(s.nightEnd, '06:00'),
    genderMode: const ['off', 'soft', 'hard'].contains(s.genderMode)
        ? s.genderMode
        : 'off',
    limitDay: s.limitDayHours,
    limitWeek: s.limitWeekHours,
    limitPresence: s.limitPresenceHours,
    limitRest: s.limitRestHours,
    limitOtDay: s.limitOvertimeDayHours,
    ordersPerStaff: s.ordersPerStaff.toDouble(),
    coverPayMode: s.coverPayMode == coverFullBlock
        ? coverFullBlock
        : coverMinuteRate,
  );

  /// `off` · `automatic` · `approval`.
  final String overtimeMode;
  final double? otDay;
  final double? otNight;
  final double? holidayMult;
  final double? advanceCap;
  final double? periodStartDay;

  /// `half_shift` · `whole_day`.
  final String halfDay;

  /// `HH:MM`, or text a time field could not read.
  final String nightStart;
  final String nightEnd;

  /// `off` · `soft` · `hard`.
  final String genderMode;
  final double? limitDay;
  final double? limitWeek;
  final double? limitPresence;
  final double? limitRest;
  final double? limitOtDay;
  final double? ordersPerStaff;

  /// [coverMinuteRate] · [coverFullBlock].
  final String coverPayMode;

  DawamRules copyWith({
    String? overtimeMode,
    double? Function()? otDay,
    double? Function()? otNight,
    double? Function()? holidayMult,
    double? Function()? advanceCap,
    double? Function()? periodStartDay,
    String? halfDay,
    String? nightStart,
    String? nightEnd,
    String? genderMode,
    double? Function()? limitDay,
    double? Function()? limitWeek,
    double? Function()? limitPresence,
    double? Function()? limitRest,
    double? Function()? limitOtDay,
    double? Function()? ordersPerStaff,
    String? coverPayMode,
  }) => DawamRules(
    overtimeMode: overtimeMode ?? this.overtimeMode,
    otDay: otDay == null ? this.otDay : otDay(),
    otNight: otNight == null ? this.otNight : otNight(),
    holidayMult: holidayMult == null ? this.holidayMult : holidayMult(),
    advanceCap: advanceCap == null ? this.advanceCap : advanceCap(),
    periodStartDay: periodStartDay == null
        ? this.periodStartDay
        : periodStartDay(),
    halfDay: halfDay ?? this.halfDay,
    nightStart: nightStart ?? this.nightStart,
    nightEnd: nightEnd ?? this.nightEnd,
    genderMode: genderMode ?? this.genderMode,
    limitDay: limitDay == null ? this.limitDay : limitDay(),
    limitWeek: limitWeek == null ? this.limitWeek : limitWeek(),
    limitPresence: limitPresence == null ? this.limitPresence : limitPresence(),
    limitRest: limitRest == null ? this.limitRest : limitRest(),
    limitOtDay: limitOtDay == null ? this.limitOtDay : limitOtDay(),
    ordersPerStaff: ordersPerStaff == null
        ? this.ordersPerStaff
        : ordersPerStaff(),
    coverPayMode: coverPayMode ?? this.coverPayMode,
  );

  List<Object?> get _props => [
    overtimeMode,
    otDay,
    otNight,
    holidayMult,
    advanceCap,
    periodStartDay,
    halfDay,
    nightStart,
    nightEnd,
    genderMode,
    limitDay,
    limitWeek,
    limitPresence,
    limitRest,
    limitOtDay,
    ordersPerStaff,
    coverPayMode,
  ];

  @override
  bool operator ==(Object other) =>
      other is DawamRules &&
      const ListEquality<Object?>().equals(other._props, _props);

  @override
  int get hashCode => Object.hashAll(_props);
}

/// "22:00:00" → "22:00" for a time field.
String _hhmm(String? s, String fallback) {
  final v = s ?? fallback;
  return v.length >= 5 ? v.substring(0, 5) : v;
}

/// "22:00" → "22:00:00" for the wire.
String hhmmss(String s) => s.length == 5 ? '$s:00' : s;

/// What the Rules page edits (`RulesValues`).
@immutable
class RulesValues {
  const RulesValues({
    required this.tiers,
    required this.absenceDays,
    required this.workingDays,
    required this.autoBuffer,
    required this.excusedPaid,
    required this.dawam,
  });

  /// `EMPTY_VALUES`.
  static const RulesValues empty = RulesValues(
    tiers: [],
    absenceDays: 1,
    workingDays: 30,
    autoBuffer: 120,
    excusedPaid: true,
    dawam: DawamRules.defaults,
  );

  /// `valuesFrom(settings, {suggest})`: a business that never saved its
  /// rules starts from the server's suggested ladder (RU-1) when [suggest]
  /// (an editor of the business with no stored rungs); a branch always shows
  /// what it effectively runs on.
  factory RulesValues.from(AttendanceSettings s, {bool suggest = false}) {
    final stored = storedTiers(s);
    final suggested = [
      for (final t in s.suggestedTiers ?? const <LateTier>[])
        RuleTier.fromLateTier(t),
    ];
    final tiers = suggest && s.rulesSavedAt == null && stored.isEmpty
        ? suggested
        : stored;
    return RulesValues(
      tiers: tiers,
      absenceDays: s.absenceDeductionDays,
      workingDays: s.workingDaysPerMonth,
      autoBuffer: s.autoCheckoutBufferMinutes.toDouble(),
      excusedPaid: s.excusedTimePaidDefault,
      dawam: DawamRules.from(s),
    );
  }

  final List<RuleTier> tiers;
  final double? absenceDays;
  final double? workingDays;
  final double? autoBuffer;
  final bool excusedPaid;
  final DawamRules dawam;

  RulesValues copyWith({
    List<RuleTier>? tiers,
    double? Function()? absenceDays,
    double? Function()? workingDays,
    double? Function()? autoBuffer,
    bool? excusedPaid,
    DawamRules? dawam,
  }) => RulesValues(
    tiers: tiers ?? this.tiers,
    absenceDays: absenceDays == null ? this.absenceDays : absenceDays(),
    workingDays: workingDays == null ? this.workingDays : workingDays(),
    autoBuffer: autoBuffer == null ? this.autoBuffer : autoBuffer(),
    excusedPaid: excusedPaid ?? this.excusedPaid,
    dawam: dawam ?? this.dawam,
  );

  @override
  bool operator ==(Object other) =>
      other is RulesValues &&
      const ListEquality<RuleTier>().equals(other.tiers, tiers) &&
      other.absenceDays == absenceDays &&
      other.workingDays == workingDays &&
      other.autoBuffer == autoBuffer &&
      other.excusedPaid == excusedPaid &&
      other.dawam == dawam;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(tiers),
    absenceDays,
    workingDays,
    autoBuffer,
    excusedPaid,
    dawam,
  );
}

/// The ladder the settings store (never the suggestion).
List<RuleTier> storedTiers(AttendanceSettings s) {
  final raw = s.lateDeductionTiers;
  if (raw is! List) return const [];
  return [
    for (final r in raw)
      if (r is Map) RuleTier.fromJson(r),
  ];
}

/// Settings a branch can't override: the business's alone (server: 400).
const Set<String> businessOnlyRules = {
  'period_start_day',
  'advance_cap_percent',
  'gender_mode',
};

/// The wire's rule names → the label the page shows for them (`RULE_LABELS`).
const Map<String, String> ruleLabelKeys = {
  'late_deduction_tiers': 'staff.lateLadder',
  'absence_deduction_days': 'staff.absenceDays',
  'default_overtime_multiplier': 'staff.otMultiplierLegacy',
  'auto_checkout_buffer_minutes': 'staff.autoBuffer',
  'working_days_per_month': 'staff.workingDays',
  'excused_time_paid_default': 'staff.excusedPaid',
  'overtime_mode': 'dawam.overtime',
  'overtime_day_multiplier': 'dawam.otDay',
  'overtime_night_multiplier': 'dawam.otNight',
  'holiday_multiplier': 'dawam.holidayRate',
  'half_day_leave_counts': 'dawam.halfDayLeave',
  'night_start': 'dawam.nightStart',
  'night_end': 'dawam.nightEnd',
  'limit_day_hours': 'dawam.limitDay',
  'limit_week_hours': 'dawam.limitWeek',
  'limit_presence_hours': 'dawam.limitPresence',
  'limit_rest_hours': 'dawam.limitRest',
  'limit_overtime_day_hours': 'dawam.limitOtDay',
  'orders_per_staff': 'dawam.ordersPerStaff',
  'cover_pay_mode': 'dawam.coverPay',
  // Business-only settings: never a branch chip, but a refusal can name them.
  'advance_cap_percent': 'dawam.advanceCap',
  'period_start_day': 'dawam.periodStartDay',
  'gender_mode': 'dawam.genderTitle',
};

/// A rule's page label (`ruleLabel`); an unknown name reads as sent.
String ruleLabel(String name, Translator t) {
  final key = ruleLabelKeys[name];
  return key == null ? name : t(key);
}

/// A problem with the ladder: its i18n key and the minute it names.
typedef TierProblem = ({String key, double? n});

/// The non-overlap rule the server enforces in `rules::validate_tiers`,
/// checked here too so the operator sees the problem on the row they edit
/// (`tierProblem`).
TierProblem? tierProblem(List<RuleTier> tiers) {
  final sorted = [...tiers]..sort((a, b) => _cmpFrom(a.from, b.from));
  double? previousEnd;
  for (final tier in sorted) {
    final to = tier.to;
    if (!tier.from.isFinite || (to != null && !to.isFinite)) {
      return (key: 'staff.tierNotANumber', n: null);
    }
    if (tier.from < 0) return (key: 'staff.tierNegative', n: null);
    if (to != null && to < tier.from) {
      return (key: 'staff.tierInverted', n: null);
    }
    if (!tier.value.isFinite || tier.value < 0) {
      return (key: 'staff.tierNegativeValue', n: null);
    }
    if (previousEnd != null && tier.from <= previousEnd) {
      return (key: 'staff.tierOverlap', n: tier.from);
    }
    previousEnd = to ?? double.maxFinite;
  }
  return null;
}

/// The JS sort comparator `a - b` (NaN compares as equal).
int _cmpFrom(double a, double b) {
  final d = a - b;
  return d.isNaN ? 0 : d.sign.toInt();
}

/// The fields of the form a problem belongs to, in the order the web's
/// schema reports them (`superRefine`): the first is what a refused save
/// toasts.
enum RulesField { tiers, workingDays, absenceDays, autoBuffer, dawam }

/// What a dawam number reads as for its range check (`Number(s)`: an empty
/// field is 0, unreadable text NaN).
double _n(double? v) => v ?? 0;

/// The form's checks (`rulesSchema`): each failing field's i18n key (and the
/// minute an overlap names).
Map<RulesField, TierProblem> rulesProblems(RulesValues v) {
  final out = <RulesField, TierProblem>{};
  final p = tierProblem(v.tiers);
  if (p != null) out[RulesField.tiers] = p;
  double num(double? x) => x ?? double.nan;
  if (!(num(v.workingDays) > 0)) {
    out[RulesField.workingDays] = (key: 'staff.workingDaysPositive', n: null);
  }
  if (!(num(v.absenceDays) >= 0)) {
    out[RulesField.absenceDays] = (key: 'staff.absenceDaysRange', n: null);
  }
  final buffer = num(v.autoBuffer);
  if (!(buffer.isFinite && buffer == buffer.roundToDouble() && buffer >= 0)) {
    out[RulesField.autoBuffer] = (key: 'staff.autoBufferRange', n: null);
  }
  final dawam = rulesRequest(v.dawam, canGender: true);
  if (dawam.error != null) {
    out[RulesField.dawam] = (key: dawam.error!, n: null);
  }
  return out;
}

bool _isInt(double x) => x.isFinite && x == x.roundToDouble();

/// What the Dawam card would send, or the first thing wrong with it
/// (`rulesRequest`). The gender mode rides only for someone holding
/// `hr.roster.settings`; anyone else would be refused the whole save for a
/// field they can't change.
({Map<String, Object?>? ok, String? error}) rulesRequest(
  DawamRules r, {
  bool canGender = false,
}) {
  if (!(_n(r.otDay) >= 1 && _n(r.otNight) >= 1 && _n(r.holidayMult) >= 1)) {
    return (ok: null, error: 'dawam.rulesRateLow');
  }
  final cap = _n(r.advanceCap);
  if (!(cap >= 0 && cap <= 100)) {
    return (ok: null, error: 'dawam.rulesCapRange');
  }
  final day = _n(r.periodStartDay);
  if (!(_isInt(day) && day >= 1 && day <= 28)) {
    return (ok: null, error: 'dawam.rulesStartDay');
  }
  final limits = [
    r.limitDay,
    r.limitWeek,
    r.limitPresence,
    r.limitRest,
    r.limitOtDay,
  ].map(_n).toList();
  if (!limits.every((h) => h > 0 && h <= 168)) {
    return (ok: null, error: 'dawam.rulesLimitRange');
  }
  final perStaff = _n(r.ordersPerStaff);
  if (!(_isInt(perStaff) && perStaff >= 1)) {
    return (ok: null, error: 'dawam.rulesOrdersPerStaff');
  }
  final time = RegExp(r'^\d{2}:\d{2}');
  if (!time.hasMatch(r.nightStart) || !time.hasMatch(r.nightEnd)) {
    return (ok: null, error: 'dawam.rulesNight');
  }
  return (
    ok: {
      'overtime_mode': r.overtimeMode,
      'overtime_day_multiplier': wireNum(_n(r.otDay)),
      'overtime_night_multiplier': wireNum(_n(r.otNight)),
      'holiday_multiplier': wireNum(_n(r.holidayMult)),
      'advance_cap_percent': wireNum(cap),
      'period_start_day': day.toInt(),
      'half_day_leave_counts': r.halfDay,
      'night_start': hhmmss(r.nightStart),
      'night_end': hhmmss(r.nightEnd),
      'limit_day_hours': wireNum(limits[0]),
      'limit_week_hours': wireNum(limits[1]),
      'limit_presence_hours': wireNum(limits[2]),
      'limit_rest_hours': wireNum(limits[3]),
      'limit_overtime_day_hours': wireNum(limits[4]),
      'orders_per_staff': perStaff.toInt(),
      'cover_pay_mode': r.coverPayMode,
      if (canGender) 'gender_mode': r.genderMode,
    },
    error: null,
  );
}

/// Every rule the form holds, as the PUT names them (`fullBody`). Throws
/// when the values are not valid (the form refuses them first).
Map<String, Object?> fullBody(RulesValues v, {required bool canGender}) {
  final dawam = rulesRequest(v.dawam, canGender: canGender);
  if (dawam.ok == null) throw StateError(dawam.error!);
  return {
    ...dawam.ok!,
    'late_deduction_tiers': [for (final t in v.tiers) t.toWire()],
    'absence_deduction_days': wireNum(_n(v.absenceDays)),
    'working_days_per_month': wireNum(_n(v.workingDays)),
    'auto_checkout_buffer_minutes': _n(v.autoBuffer).toInt(),
    'excused_time_paid_default': v.excusedPaid,
  };
}

const DeepCollectionEquality _deep = DeepCollectionEquality();

/// Two rule values are the same rule whatever their key order.
bool sameRule(Object? a, Object? b) => _deep.equals(a, b);

/// A branch's save (`branchBody`): only the rules that differ from what the
/// branch runs on now (each becomes an override), never a business-only
/// setting, and the rules handed back to the business. [force] names rules
/// the branch makes its own even at the value it runs on now (it picked it
/// explicitly, D5). Null when there is nothing to send.
Map<String, Object?>? branchBody(
  String branchId,
  RulesValues v,
  RulesValues loaded,
  List<String> inherit, [
  List<String> force = const [],
]) {
  final now = fullBody(v, canGender: false);
  final before = fullBody(loaded, canGender: false);
  final body = <String, Object?>{};
  for (final e in now.entries) {
    if (businessOnlyRules.contains(e.key) || inherit.contains(e.key)) continue;
    if (!sameRule(e.value, before[e.key]) || force.contains(e.key)) {
      body[e.key] = e.value;
    }
  }
  if (body.isEmpty && inherit.isEmpty) return null;
  return {
    ...body,
    'branch_id': branchId,
    if (inherit.isNotEmpty) 'inherit': [...inherit],
  };
}

/// One saved rule a save would change.
typedef RuleChange = ({String name, Object? before, Object? after});

/// Which saved rules a save would change, by wire name (`changedRules`), for
/// the "you're about to change…" confirmation. Invalid values yield none
/// (the form refuses them before it asks).
List<RuleChange> changedRules(
  RulesValues now,
  RulesValues before, {
  required bool canGender,
}) {
  final Map<String, Object?> a;
  final Map<String, Object?> b;
  try {
    a = fullBody(now, canGender: canGender);
    b = fullBody(before, canGender: canGender);
  } on StateError {
    return const [];
  }
  return [
    for (final k in a.keys)
      if (!sameRule(a[k], b[k])) (name: k, before: b[k], after: a[k]),
  ];
}

/// A new rung's amount when its kind changes: a sensible start, never a
/// leftover from another unit (`defaultTierValue`).
double defaultTierValue(TierKind kind) => switch (kind) {
  TierKind.minutes => 15,
  TierKind.dayFraction => 0.25,
  TierKind.piastres => 5000,
};

/// The rung "Add a rung" appends: from the last end + 1 (or 1), fifteen
/// minutes long, fifteen minutes of pay.
RuleTier nextTier(List<RuleTier> tiers) {
  final last = tiers.isEmpty ? null : tiers.last;
  final end = last?.to;
  final from = end != null && end.isFinite ? end + 1 : 1.0;
  return RuleTier(from: from, to: from + 14, kind: TierKind.minutes, value: 15);
}

/// A figure as JavaScript prints it (`String(n)`: `7`, `0.25`, `NaN`).
String jsNum(num? n) => n == null ? '' : Strings.jsString(n);

/// The arrow between two read-back phrases, pointing the way the line reads.
String readArrow(Translator t) => t.isRtl ? '←' : '→';

/// A plain-language restatement of a rung (`describeTier`), so the operator
/// reads back what they built without the arithmetic: "1–15 min late → 15
/// minutes of pay".
String describeTier(RuleTier tier, Translator t, DashFormat f) {
  final to = tier.to;
  final range = to == null
      ? t('staff.tierFromOnly', args: {'from': jsNum(tier.from)})
      : t('staff.tierRange', args: {'from': jsNum(tier.from), 'to': jsNum(to)});
  final cost = switch (tier.kind) {
    TierKind.minutes => t(
      'staff.tierCostMinutes',
      args: {'n': jsNum(tier.value)},
    ),
    TierKind.dayFraction => t(
      'staff.tierCostDay',
      args: {'n': jsNum(tier.value)},
    ),
    TierKind.piastres => f.fmtMoney(tier.value),
  };
  return '$range ${readArrow(t)} $cost';
}

/// The words a choice-valued rule's wire value stands for, so a change
/// never shows a raw `approval` in the confirmation.
const Map<String, Map<String, String>> _choiceLabels = {
  'overtime_mode': {
    'off': 'dawam.otOff',
    'automatic': 'dawam.otAutomatic',
    'approval': 'dawam.otApproval',
  },
  'half_day_leave_counts': {
    'half_shift': 'dawam.halfShift',
    'whole_day': 'dawam.wholeDay',
  },
  'cover_pay_mode': {
    coverMinuteRate: 'dawam.coverPayMinute',
    coverFullBlock: 'dawam.coverPayBlock',
  },
  'gender_mode': {
    'off': 'dawam.genderOff',
    'soft': 'dawam.genderSoft',
    'hard': 'dawam.genderHard',
  },
};

/// One changed rule, before → after, in words (`describeChange`): booleans
/// Yes/No, empty "none", times on the 12-hour clock, ladders "{{count}}
/// rungs" (+ "(edited)" when the count is the same), choices by their
/// option's words.
String describeChange(RuleChange c, Translator t, DashFormat f) {
  final time = RegExp(r'^\d{2}:\d{2}(:\d{2})?$');
  final choices = _choiceLabels[c.name];
  String show(Object? v) {
    if (v == null || v == '') return t('staff.changeNone');
    if (v is bool) return v ? t('common.yes') : t('common.no');
    if (v is List) return t('staff.changeRungs', count: v.length);
    if (v is String && choices != null && choices[v] != null) {
      return t(choices[v]!);
    }
    if (v is String && time.hasMatch(v)) return f.fmtWireTime(v);
    if (v is num) return jsNum(v);
    return '$v';
  }

  final arrow = readArrow(t);
  final before = c.before;
  final after = c.after;
  if (after is List) {
    final edited = before is List && before.length == after.length
        ? ' (${t('staff.changeEdited')})'
        : '';
    return '${show(before)} $arrow ${show(after)}$edited';
  }
  return '${show(before)} $arrow ${show(after)}';
}
