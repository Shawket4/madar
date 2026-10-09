/// What a late-ladder rung charges for one pay example, worked out the way
/// the server does it (`staff/rules-preview.ts` `tierPiastres` /
/// `dayPiastres`, mirroring `MadarRust/src/staff/rules.rs`
/// `late_deduction_piastres` over `PayRates`: multiply before dividing, then
/// round half away from zero, never below zero). One copy for the Rules
/// page's preview and Set-up's rules step. A preview only: payroll prices
/// from what the server stored, never from this.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// One pay example: a monthly salary (piastres), the working days that
/// divide it, and the shift's scheduled minutes (the minute-rate divisor).
@immutable
class PayExample {
  const PayExample({
    required this.salary,
    required this.workingDays,
    required this.shiftMinutes,
  });

  /// EGP 12,000 a month, 30 days, an 8-hour shift: the Rules page's default
  /// and Set-up's salary and shift.
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

/// `Math.max(0, roundHalfAway(x))` (Dart's `round` is half away from zero);
/// NaN for an unreadable figure (it prints as "—").
num _docked(double x) => x.isFinite ? math.max(0, x.round()) : double.nan;

/// What a rung of [kind] (the wire kind: `piastres`, `day_fraction`, or
/// `minutes` of pay) and [value] costs in piastres for [ex].
num rungPiastres(String kind, double value, PayExample ex) {
  if (kind == 'piastres') return _docked(value);
  if (ex.workingDays <= 0) return 0;
  if (kind == 'day_fraction') {
    return _docked(ex.salary * value / ex.workingDays);
  }
  if (ex.shiftMinutes <= 0) return 0;
  return _docked(ex.salary * value / (ex.workingDays * ex.shiftMinutes));
}

/// [days] days of the example's pay: what an absence docks (`dayPiastres`).
num dayPiastres(PayExample ex, [double days = 1]) =>
    ex.workingDays > 0 ? _docked(ex.salary * days / ex.workingDays) : 0;
