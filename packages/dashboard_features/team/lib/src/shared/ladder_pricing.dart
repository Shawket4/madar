/// What a late-ladder rung and an absence charge for one pay example:
/// madar-dawam's `ladder` through the core, the server's payroll arithmetic
/// (`late_deduction_piastres`, `absence_deduction_piastres` over `PayRates`:
/// exact, multiplied before divided, rounded once half away from zero, never
/// below zero). One door for the Rules page's preview and Set-up's rules
/// step. A preview only: payroll prices from what the server stored.
library;

import 'package:flutter/foundation.dart';
import 'package:rust_bridge_dashboard/rules.dart' as rules;

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

/// What a rung of [kind] (the wire kind: `piastres`, `day_fraction`, or
/// `minutes` of pay) and [value] costs in piastres for [ex]; NaN for an
/// unreadable figure (it prints as "—").
num rungPiastres(String kind, double value, PayExample ex) =>
    rules.lateDeductionPiastres(
      kind: kind,
      value: value,
      salary: ex.salary,
      workingDays: ex.workingDays,
      dayMinutes: ex.shiftMinutes,
    ) ??
    double.nan;

/// [days] days of the example's pay: what an absence docks (`dayPiastres`);
/// NaN for an unreadable figure.
num dayPiastres(PayExample ex, [double days = 1]) =>
    rules.absenceDeductionPiastres(
      salary: ex.salary,
      workingDays: ex.workingDays,
      daysAbsent: 1,
      deductionDays: days,
    ) ??
    double.nan;
