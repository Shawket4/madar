/// What a rule would charge, worked out the way the server does it, for the
/// Rules page's "try it" preview (`staff/rules-preview.ts`). Mirrors
/// `MadarRust/src/staff/rules.rs`: `select_late_tier` (the FIRST rung whose
/// range holds the minutes) and `late_deduction_piastres` over `PayRates`
/// (multiply before dividing, then round half away from zero). A preview
/// only: payroll prices from what the server stored, never from this.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'rules_form.dart';

/// One pay example: a monthly salary (piastres), the working days that
/// divide it, and the shift's scheduled minutes (the minute-rate divisor).
@immutable
class PayExample {
  const PayExample({
    required this.salary,
    required this.workingDays,
    required this.shiftMinutes,
  });

  /// EGP 12,000 a month, 30 days, an 8-hour shift: the page's default.
  static const PayExample initial = PayExample(
    salary: 1200000,
    workingDays: 30,
    shiftMinutes: 480,
  );

  final int salary;
  final double workingDays;
  final int shiftMinutes;

  PayExample copyWith({int? salary, double? workingDays, int? shiftMinutes}) =>
      PayExample(
        salary: salary ?? this.salary,
        workingDays: workingDays ?? this.workingDays,
        shiftMinutes: shiftMinutes ?? this.shiftMinutes,
      );
}

/// The rung [lateMinutes] falls on, or null (on time, or past a ladder that
/// stops) (`selectTier`).
RuleTier? selectTier(List<RuleTier> tiers, num lateMinutes) {
  if (lateMinutes <= 0) return null;
  for (final t in tiers) {
    final to = t.to;
    if (lateMinutes >= math.max(0, t.from) &&
        (to == null || lateMinutes <= to)) {
      return t;
    }
  }
  return null;
}

/// `Math.max(0, roundHalfAway(x))`; NaN for an unreadable figure (it
/// prints as "—").
num _docked(double x) => x.isFinite ? math.max(0, x.round()) : double.nan;

/// What a rung costs in piastres for one pay example (`tierPiastres`).
num tierPiastres(RuleTier tier, PayExample ex) {
  if (tier.kind == TierKind.piastres) return _docked(tier.value);
  if (ex.workingDays <= 0) return 0;
  if (tier.kind == TierKind.dayFraction) {
    return _docked(ex.salary * tier.value / ex.workingDays);
  }
  if (ex.shiftMinutes <= 0) return 0;
  return _docked(
    ex.salary * tier.value / (ex.workingDays * ex.shiftMinutes),
  );
}

/// [days] days of the example's pay: what an absence docks (`dayPiastres`).
num dayPiastres(PayExample ex, [double days = 1]) =>
    ex.workingDays > 0 ? _docked(ex.salary * days / ex.workingDays) : 0;
