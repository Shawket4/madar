/// The Payroll page's browser-side rules, as pure Dart (inventory §13):
/// `dawam/payroll-page.tsx` (`periodPhase`, `daysStillToCome`, `monthLabel`,
/// `unsettledOf`, `olderPeriod`), `dawam/payroll-steps.tsx` (`nextStepKey`),
/// `dawam/money-dialogs.tsx` (`firstOpenMonth`, `monthToDate`),
/// `dawam/phase-d.ts` (`capView`) and `dawam/lines.ts` (`payslipLines`,
/// `reasonText`). Every figure is the server's; these only lay it out.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart' show DashTone;

// ── phases ──────────────────────────────────────────────────────────────

/// open · approved · paid, the page's three phases.
enum PayPhase { open, approved, paid }

/// The server's period status as a phase (`periodPhase`): `generated` →
/// approved, `paid` / `closed` → paid, anything else (draft) → open.
PayPhase periodPhase(String? status) => switch (status) {
  'generated' => PayPhase.approved,
  'paid' || 'closed' => PayPhase.paid,
  _ => PayPhase.open,
};

/// `dawam.phase_<phase>`.
String phaseKey(PayPhase p) => 'dawam.phase_${p.name}';

/// The phase pill's tone (`PHASE_TONE`).
DashTone phaseTone(PayPhase p) => switch (p) {
  PayPhase.open => DashTone.neutral,
  PayPhase.approved => DashTone.info,
  PayPhase.paid => DashTone.success,
};

/// Still to settle: a past month never approved, or approved with someone
/// unpaid (`isUnsettled`).
bool isUnsettledStatus(String? status) =>
    status == 'draft' || status == 'generated';

// ── dates ───────────────────────────────────────────────────────────────

DateTime _date(String iso) {
  final p = iso.split('-').map(int.parse).toList();
  return DateTime.utc(p[0], p[1], p.length > 2 ? p[2] : 1);
}

String _two(int v) => v.toString().padLeft(2, '0');

String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${_two(d.month)}-${_two(d.day)}';

/// Days from [today] to the month's last day, both counted; 0 once it has
/// ended (`daysStillToCome`).
int daysStillToCome(String endDate, String today) {
  final n = _date(endDate).difference(_date(today)).inDays + 1;
  return n < 0 ? 0 : n;
}

/// The last day of [iso]'s month.
String monthEnd(String iso) {
  final d = _date(iso);
  return _iso(DateTime.utc(d.year, d.month + 1, 0));
}

/// A month by its dates (`monthLabel`): "Aug 2026" when it is exactly a
/// calendar month (the 1st to its last day), else "d1 → d2".
String monthLabel(DashFormat f, String start, String end) =>
    start.endsWith('-01') && end == monthEnd(start)
    ? f.fmtPeriod('${start}T12:00:00Z', PeriodGranularity.monthly)
    : '${f.fmtDate(start)} → ${f.fmtDate(end)}';

/// The first month that can still take a pay line (`firstOpenMonth`, owner
/// decision 27): the open period's month while it is a draft, else the
/// month after its end; today's month when the period is unknown.
String firstOpenMonth(PayrollPeriod? period, String today) {
  if (period == null) return today.substring(0, 7);
  if (period.status == 'draft') return period.endDate.substring(0, 7);
  final end = _date(period.endDate);
  final next = DateTime.utc(end.year, end.month + 1);
  return '${next.year.toString().padLeft(4, '0')}-${_two(next.month)}';
}

/// A month picker's `YYYY-MM` → the first day the server files the line
/// under (`monthToDate`).
String monthToDate(String month) => '$month-01';

/// `YYYY-MM` moved by [n] months.
String addMonths(String month, int n) {
  final d = _date(month);
  final m = DateTime.utc(d.year, d.month + n);
  return '${m.year.toString().padLeft(4, '0')}-${_two(m.month)}';
}

// ── older months (H2-P1) ───────────────────────────────────────────────

/// An older month to settle; [paidCount] is null when it comes from
/// history (an older server without `unsettled`).
class Unsettled {
  const Unsettled({
    required this.periodId,
    required this.startsOn,
    required this.endsOn,
    required this.status,
    required this.netTotalPiastres,
    required this.people,
    this.paidCount,
  });

  final String periodId;
  final String startsOn;
  final String endsOn;
  final String status;
  final int netTotalPiastres;
  final int people;
  final int? paidCount;
}

/// The older months not fully paid, oldest first (`unsettledOf`): the
/// server's `unsettled`, or, from a server without it, the same months found
/// in history. A missing field decodes as an empty list; an empty answer
/// beside history holding a draft or approved month can only come from such
/// a server (a current one lists every one of them), so history speaks then.
List<Unsettled> unsettledOf(CurrentPayroll? cur) {
  if (cur == null) return const [];
  if (cur.unsettled.isNotEmpty) {
    return [
      for (final u in cur.unsettled)
        Unsettled(
          periodId: u.periodId,
          startsOn: u.startsOn,
          endsOn: u.endsOn,
          status: u.status,
          netTotalPiastres: u.netTotalPiastres,
          people: u.people,
          paidCount: u.paidCount,
        ),
    ];
  }
  final older = [
    for (final p in cur.history)
      if (isUnsettledStatus(p.status)) p,
  ]..sort((a, b) => a.startDate.compareTo(b.startDate));
  return [
    for (final p in older)
      Unsettled(
        periodId: p.id,
        startsOn: p.startDate,
        endsOn: p.endDate,
        status: p.status,
        netTotalPiastres: p.totalNetPiastres,
        people: p.employeeCount,
      ),
  ];
}

/// An older month as a period (`olderPeriod`): history's row, or one made
/// from `unsettled` past history's reach.
PayrollPeriod? olderPeriod(
  CurrentPayroll? cur,
  String? id,
  List<Unsettled> unsettled,
  DashFormat f,
) {
  if (cur == null || id == null) return null;
  for (final p in cur.history) {
    if (p.id == id) return p;
  }
  for (final u in unsettled) {
    if (u.periodId == id) {
      return PayrollPeriod(
        id: u.periodId,
        orgId: cur.period.orgId,
        name: monthLabel(f, u.startsOn, u.endsOn),
        startDate: u.startsOn,
        endDate: u.endsOn,
        status: u.status,
        totalNetPiastres: u.netTotalPiastres,
        employeeCount: u.people,
        createdAt: cur.period.createdAt,
        updatedAt: cur.period.updatedAt,
      );
    }
  }
  return null;
}

// ── steps ───────────────────────────────────────────────────────────────

/// The sentence under the steps: what to do now (`nextStepKey`).
String nextStepKey(PayPhase phase, int blockers, int paid, int people) {
  switch (phase) {
    case PayPhase.open:
      return blockers > 0
          ? 'dawamOps.payNextBlocked'
          : 'dawamOps.payNextApprove';
    case PayPhase.approved:
      return paid == 0
          ? 'dawamOps.payNextPayFirst'
          : paid < people
          ? 'dawamOps.payNextPayRest'
          : 'dawamOps.payNextDone';
    case PayPhase.paid:
      return 'dawamOps.payNextClosed';
  }
}

// ── advance cap (D7) ────────────────────────────────────────────────────

/// Where an advance stands against the owner's cap (`capView`): within /
/// over for everyone; the figures only when the server sends the cap.
({bool? within, int owed, int? cap}) capView(SalaryAdvance a) =>
    (within: a.withinCap, owed: a.outstandingPiastres, cap: a.capPiastres);

// ── payslips ────────────────────────────────────────────────────────────

/// One payslip row as the page shows it: a live preview row
/// ([ComputedPayslip]) or a frozen one ([Payslip]), with its name resolved
/// and how it was paid.
class SlipRow {
  SlipRow.computed(ComputedPayslip s, {String? fallbackName})
    : employeeId = s.employeeId,
      name = s.name.isNotEmpty ? s.name : (fallbackName ?? '—'),
      paidMethod = null,
      payslipId = null,
      basePiastres = s.basePiastres,
      overtimePiastres = s.overtimePiastres,
      overtimeMinutes = s.overtimeMinutes,
      bonusesPiastres = s.bonusesPiastres,
      deductionsPiastres = s.deductionsPiastres,
      advancePiastres = s.advanceInstallmentPiastres,
      netPiastres = s.netPiastres,
      carryOutPiastres = s.carryOutPiastres,
      salaryMissing = s.salaryMissing ?? false,
      breakdown = s.breakdown;

  SlipRow.frozen(Payslip s, {String? fallbackName})
    : employeeId = s.employeeId,
      name = (s.employeeName?.isNotEmpty ?? false)
          ? s.employeeName!
          : (fallbackName ?? '—'),
      paidMethod = (s.paidMethod?.isNotEmpty ?? false) ? s.paidMethod : null,
      payslipId = s.id,
      basePiastres = null,
      overtimePiastres = s.overtimePiastres,
      overtimeMinutes = s.overtimeMinutes,
      bonusesPiastres = s.bonusesPiastres,
      deductionsPiastres = s.deductionsPiastres,
      advancePiastres = s.advanceInstallmentPiastres,
      netPiastres = s.netPiastres,
      carryOutPiastres = s.carryOutPiastres,
      salaryMissing = false,
      breakdown = s.breakdown;

  final String employeeId;
  final String name;

  /// `cash` · `bank` · `wallet` · `none`; null until paid.
  final String? paidMethod;
  final String? payslipId;

  /// The preview's own base; null on a frozen payslip (worked out).
  final int? basePiastres;
  final int overtimePiastres;
  final int overtimeMinutes;
  final int bonusesPiastres;
  final int deductionsPiastres;
  final int advancePiastres;
  final int netPiastres;
  final int carryOutPiastres;
  final bool salaryMissing;
  final Object? breakdown;

  /// Base pay before overtime, bonuses, deductions and the advance
  /// (`basePiastres`).
  int get base =>
      basePiastres ??
      netPiastres -
          overtimePiastres -
          bonusesPiastres +
          deductionsPiastres +
          advancePiastres;

  /// Paid by a person, not settled by the run itself (`paid_method none`).
  bool get paidByHand => paidMethod != null && paidMethod != 'none';
}

/// Unpaid payslips first so every "Mark paid" is on page 1; the order
/// within is kept (`sort((a, b) => !!a.paid - !!b.paid)`).
List<SlipRow> unpaidFirst(List<SlipRow> rows) {
  final indexed = [for (var i = 0; i < rows.length; i++) (i, rows[i])];
  indexed.sort((a, b) {
    final c =
        (a.$2.paidMethod != null ? 1 : 0) - (b.$2.paidMethod != null ? 1 : 0);
    return c != 0 ? c : a.$1 - b.$1;
  });
  return [for (final e in indexed) e.$2];
}

/// One payslip line (`PayLine`).
class PayLine {
  const PayLine({
    required this.key,
    required this.label,
    required this.amount,
    required this.rule,
    this.labelKey,
    this.vars,
    this.manualKind,
    this.manualId,
    this.deductionId,
    this.waivedId,
    this.waived = false,
    this.waiveReason,
    this.overrideReason,
  });

  final String key;

  /// i18n key for rule-made lines; null for a person's own words.
  final String? labelKey;

  /// The fallback words (the server's or a person's).
  final String label;
  final Map<String, Object?>? vars;

  /// Signed piastres: + earning, − deduction.
  final int amount;

  /// Rule-made (lateness, absence, leaving mid-shift): waivable, never
  /// deletable.
  final bool rule;

  /// A manual bonus or deduction: deletable until the month is approved.
  final String? manualKind;
  final String? manualId;

  /// The deduction row behind a live rule line (waive / override).
  final String? deductionId;

  /// The row behind a WAIVED rule line (undo the waiver).
  final String? waivedId;
  final bool waived;
  final String? waiveReason;
  final String? overrideReason;

  bool get manual => manualId != null;
}

/// Server-written reasons by code, in the reader's language (AT-13).
const Map<String, String> reasonKeys = {
  'late': 'dawam.reason_late',
  'absent_no_punch': 'dawam.reason_absent_no_punch',
  'unpaid_leave': 'dawam.reason_unpaid_leave',
  'absent_half_unpaid_leave': 'dawam.reason_absent_half_unpaid_leave',
  'unpaid_excused_minutes': 'dawam.reason_unpaid_excused_minutes',
  'unpaid_excuse': 'dawam.reason_unpaid_excuse',
  'left_mid_shift': 'dawam.reason_left_mid_shift',
};

/// A line's reason in the reader's language (`reasonText`): the code's
/// wording when it is known, else the server's (or a person's) text.
String reasonText(
  Translator t,
  String? code,
  Map<String, Object?>? vars,
  String fallback,
) {
  final key = code == null ? null : reasonKeys[code];
  return key == null ? fallback : t(key, args: vars, defaultValue: fallback);
}

Map<String, Object?> _map(Object? v) => v is Map
    ? v.map((k, val) => MapEntry(k.toString(), val))
    : const <String, Object?>{};

List<Map<String, Object?>> _list(Object? v) =>
    v is List ? [for (final e in v) _map(e)] : const [];

int _int(Object? v) => v is num ? v.round() : 0;

String? _str(Object? v) => v is String ? v : null;

/// A payslip's lines from the server's `breakdown` (`payslipLines`).
List<PayLine> payslipLines(SlipRow p, DashFormat f) {
  final b = _map(p.breakdown);
  final out = <PayLine>[];
  final paid = _int(b['paid_days']);
  final window = _int(b['window_days']);
  final partial = paid > 0 && paid < window;
  out.add(
    PayLine(
      key: 'salary',
      labelKey: partial ? 'dawam.lineSalaryPartial' : 'dawam.lineSalary',
      label: partial ? 'Salary ($paid of $window days)' : 'Salary',
      vars: {'paid': paid, 'window': window},
      amount: p.base,
      rule: false,
    ),
  );
  if (p.overtimePiastres > 0) {
    out.add(
      PayLine(
        key: 'ot',
        labelKey: 'dawam.lineOvertime',
        label: 'Overtime (${p.overtimeMinutes} min)',
        vars: {'minutes': p.overtimeMinutes},
        amount: p.overtimePiastres,
        rule: false,
      ),
    );
  }
  for (final l in _list(b['bonuses'])) {
    final kind = _str(l['kind']) ?? '';
    final id = _str(l['id']);
    out.add(
      PayLine(
        key: 'b|${id ?? kind}',
        labelKey: kind == 'cover'
            ? 'dawam.lineCover'
            : kind == 'holiday'
            ? 'dawam.lineHoliday'
            : null,
        label: kind == 'cover'
            ? 'Cover shifts'
            : kind == 'holiday'
            ? 'Public holiday worked'
            : (_str(l['reason']) ?? ''),
        amount: _int(l['piastres']),
        rule: false,
        manualKind: id == null ? null : 'bonus',
        manualId: id,
      ),
    );
  }
  for (final l in _list(b['deductions'])) {
    final carry = l['kind'] == 'carry';
    final manual = l['source'] == 'manual';
    final id = _str(l['id']);
    final waived = l['waived'] == true;
    final code = _str(l['reason_code']);
    final coded = !carry && code != null ? reasonKeys[code] : null;
    final waiveReason = _str(l['waive_reason']);
    final overrideReason = _str(l['override_reason']);
    out.add(
      PayLine(
        key: carry ? 'carry' : 'd|$id',
        labelKey: carry ? 'dawam.lineCarry' : coded,
        vars: coded == null ? null : _map(l['reason_vars']),
        label: carry ? 'Carried from the last payslip' : (_str(l['reason']) ?? ''),
        amount: -_int(l['piastres']),
        rule: !carry && !manual,
        manualKind: manual && id != null ? 'deduction' : null,
        manualId: manual ? id : null,
        deductionId: !carry && !manual && !waived ? id : null,
        waivedId: !carry && !manual && waived ? id : null,
        waived: waived,
        waiveReason: waived && (waiveReason?.isNotEmpty ?? false)
            ? waiveReason
            : null,
        overrideReason: !waived && (overrideReason?.isNotEmpty ?? false)
            ? overrideReason
            : null,
      ),
    );
  }
  // What a payslip could not afford stops here and carries to the next one
  // (PAY-12), so the lines still add up to the net.
  final capped = b['capped_piastres'] is num
      ? _int(b['capped_piastres'])
      : p.carryOutPiastres;
  if (capped > 0) {
    final amount = f.fmtMoney(capped);
    out.add(
      PayLine(
        key: 'capped',
        labelKey: 'dawam.lineCapped',
        label: 'Capped at what was earned ($amount carries)',
        vars: {'amount': amount},
        amount: capped,
        rule: false,
      ),
    );
  }
  for (final a in _list(b['advances'])) {
    final take = _int(a['applied_piastres']);
    if (take == 0) continue;
    out.add(
      PayLine(
        key: 'adv|${a['id']}',
        labelKey: 'dawam.lineAdvance',
        label: 'Advance installment',
        amount: -take,
        rule: false,
      ),
    );
  }
  return out;
}

/// What the lines add up to: the net, waived lines left out (`linesTotal`).
int linesTotal(List<PayLine> lines) =>
    lines.fold(0, (s, l) => s + (l.waived ? 0 : l.amount));

/// A line's words (`lineLabel`).
String lineLabel(PayLine l, Translator t) => l.labelKey == null
    ? l.label
    : t(l.labelKey!, args: l.vars, defaultValue: l.label);

/// "Waived", with why when the server says (`waivedText`).
String waivedText(PayLine l, Translator t) => l.waiveReason != null
    ? t('dawam.lineWaivedWhy', args: {'reason': l.waiveReason})
    : t('dawam.lineWaived');

// ── pay lines tab ───────────────────────────────────────────────────────

/// Which rule made a line (`RULE_SOURCE`).
const Map<String, String> ruleSourceKeys = {
  'late_penalty': 'dawam.ruleSource_late',
  'absence': 'dawam.ruleSource_absence',
  'left_mid_shift': 'dawam.ruleSource_left_mid_shift',
  'excused_unpaid': 'dawam.ruleSource_excused_unpaid',
  'carry': 'dawam.ruleSource_carry',
};

/// A pay line's status pill tone (`ADJ_TONE`).
DashTone adjustmentTone(String status) => switch (status) {
  'pending' => DashTone.warning,
  'approved' => DashTone.success,
  'rejected' => DashTone.danger,
  _ => DashTone.neutral,
};

/// The pay methods a person is marked paid by (`PAY_METHODS`).
const List<String> payMethods = ['cash', 'bank', 'wallet'];
