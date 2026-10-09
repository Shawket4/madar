/// The Payroll page's reads, each keyed by its endpoint path so the web's
/// invalidations reach it (`watchStaffPath`, TEAM-ALL-026), and the page's
/// own state (tab, the older month in view, the person whose payslip is
/// open), kept in a provider so the payslip sheet — its own route — reads
/// the payslip as it is NOW (after a waiver or a new line, TEAM-PAY-023).
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/setup_data.dart';
import '../shared/staff_query.dart';
import 'payroll_logic.dart';

/// Whether this person may read payroll (`canAny(read, run)`).
final payrollCanReadProvider = Provider.autoDispose<bool>(
  (ref) => ref.watch(
    authzProvider.select(
      (a) => a.canAny(const [Cap.hrPayrollRead, Cap.hrPayrollRun]),
    ),
  ),
);

/// `GET /staff/payroll/current`; null (nothing asked) without the right.
final payrollCurrentProvider = FutureProvider.autoDispose<CurrentPayroll?>((
  ref,
) async {
  ref.webCache();
  watchStaffPath(ref, '/staff/payroll/current');
  if (!ref.watch(payrollCanReadProvider)) return null;
  if (ref.watch(orgIdProvider) == null) return null;
  return ref.watch(apiProvider).staff.current();
});

/// The ACTIVE employees (`GET /staff/employees?employment_status=active`):
/// names and pay methods, the money dialogs' pickers. One cache with the
/// set-up checklist's read of the same address.
final payrollPeopleProvider = setupActiveEmployeesProvider;

/// An older month's own read: its live preview while it is a draft
/// (`GET …/preview`), else its frozen payslips (`GET …/payslips`, also the
/// History sheet's read). Each item is a [ComputedPayslip] or a [Payslip].
final payrollOlderSlipsProvider = FutureProvider.autoDispose
    .family<List<Object>, ({String id, bool draft})>((ref, key) async {
      ref.webCache();
      final api = ref.watch(apiProvider).staff;
      if (key.draft) {
        watchStaffPath(ref, '/staff/payroll/periods/${key.id}/preview');
        return api.previewPeriod(id: key.id);
      }
      watchStaffPath(ref, '/staff/payroll/periods/${key.id}/payslips');
      return api.listPayslips(id: key.id);
    });

/// `GET /staff/adjustments` (the Bonuses & deductions tab).
final payrollAdjustmentsProvider = FutureProvider.autoDispose<List<Adjustment>>(
  (ref) async {
    ref.webCache();
    watchStaffPath(ref, '/staff/adjustments');
    return ref.watch(apiProvider).staff.listAdjustments();
  },
);

/// `GET /staff/payroll/advances` (the Salary advances tab).
final payrollAdvancesProvider = FutureProvider.autoDispose<List<SalaryAdvance>>(
  (ref) async {
    ref.webCache();
    watchStaffPath(ref, '/staff/payroll/advances');
    return ref.watch(apiProvider).staff.listAdvances();
  },
);

/// `GET /staff/expense-advances(?branch_id)`: the scope bar's branch, every
/// branch when none is picked (AV-9).
final payrollExpensesProvider = FutureProvider.autoDispose
    .family<List<ExpenseAdvance>, String?>((ref, branchId) async {
      ref.webCache();
      watchStaffPath(ref, '/staff/expense-advances');
      return ref
          .watch(apiProvider)
          .staff
          .listExpenseAdvances(branchId: branchId);
    });

// ── page state ─────────────────────────────────────────────────────────

/// The page's tabs (`payslips` is the default).
enum PayrollTab { payslips, lines, advances, expenses, history }

/// The page's own state, reset when the page is left (TEAM-ALL-021).
class PayrollView {
  const PayrollView({
    this.tab = PayrollTab.payslips,
    this.viewId,
    this.historyId,
  });

  final PayrollTab tab;

  /// An older month opened from its banner or History; null = this month.
  final String? viewId;

  /// The settled month whose History sheet is open (the Refresh spinner
  /// covers its read).
  final String? historyId;
}

class PayrollViewNotifier extends Notifier<PayrollView> {
  @override
  PayrollView build() => const PayrollView();

  void setTab(PayrollTab tab) =>
      state = PayrollView(tab: tab, viewId: state.viewId);

  /// Views an older month (null = back to this month) on the Payslips tab.
  void openMonth(String? id) => state = PayrollView(viewId: id);

  /// The History sheet opened (an id) or closed (null).
  void showHistory(String? id) =>
      state = PayrollView(tab: state.tab, viewId: state.viewId, historyId: id);
}

final payrollViewProvider =
    NotifierProvider.autoDispose<PayrollViewNotifier, PayrollView>(
      PayrollViewNotifier.new,
    );

/// An older month's own read key (its preview while a draft).
({String id, bool draft}) olderKey(PayrollPeriod p) =>
    (id: p.id, draft: p.status == 'draft');

// ── what the page shows ────────────────────────────────────────────────

/// Everything the page and the payslip sheet derive from the reads.
class PayrollShown {
  const PayrollShown({
    required this.current,
    required this.currentRead,
    required this.unsettled,
    required this.older,
    required this.period,
    required this.phase,
    required this.rows,
    required this.shownRead,
    required this.people,
    required this.totals,
    required this.missing,
    required this.missingCount,
    required this.paidByHand,
  });

  final CurrentPayroll? current;
  final AsyncValue<CurrentPayroll?> currentRead;
  final List<Unsettled> unsettled;

  /// The older month in view, null for this month.
  final PayrollPeriod? older;

  /// The period every action goes by.
  final PayrollPeriod? period;
  final PayPhase phase;

  /// Unpaid first.
  final List<SlipRow> rows;

  /// The read behind [rows] (the older month's, else the current one).
  final AsyncValue<Object?> shownRead;

  /// Active employees by id.
  final Map<String, Employee> people;
  final ({int net, int deductions, int advances, int people, int paid}) totals;
  final List<SlipRow> missing;
  final int missingCount;

  /// Payslips paid by a person (a `none` mark by the run doesn't count).
  final int paidByHand;

  /// The skeleton: the shown read has nothing yet.
  bool get loading => shownRead.awaitingFirst;
}

final payrollShownProvider = Provider.autoDispose<PayrollShown>((ref) {
  final f = ref.watch(formatProvider);
  final currentRead = ref.watch(payrollCurrentProvider);
  final cur = currentRead.value;
  final view = ref.watch(payrollViewProvider);
  final unsettled = unsettledOf(cur);
  final older = olderPeriod(cur, view.viewId, unsettled, f);
  final canRead = ref.watch(payrollCanReadProvider);
  final olderRead = older == null || !canRead
      ? null
      : ref.watch(payrollOlderSlipsProvider(olderKey(older)));
  final period = older ?? cur?.period;
  final phase = periodPhase(period?.status);
  final peopleList =
      (canRead ? ref.watch(payrollPeopleProvider).value : null) ?? const [];
  final people = {for (final e in peopleList) e.id: e};
  String? nameOf(String id) => people[id]?.name;

  // After approval the frozen payslips are the truth; before, the preview.
  SlipRow rowOf(Object s) => s is Payslip
      ? SlipRow.frozen(s, fallbackName: nameOf(s.employeeId))
      : SlipRow.computed(
          s as ComputedPayslip,
          fallbackName: nameOf(s.employeeId),
        );
  List<SlipRow> source;
  if (older != null) {
    source = [for (final s in olderRead?.value ?? const <Object>[]) rowOf(s)];
  } else if (cur != null && cur.payslips.isNotEmpty) {
    source = [
      for (final s in cur.payslips)
        SlipRow.frozen(s, fallbackName: nameOf(s.employeeId)),
    ];
  } else {
    source = [
      for (final s in cur?.preview ?? const <ComputedPayslip>[])
        SlipRow.computed(s, fallbackName: nameOf(s.employeeId)),
    ];
  }
  final rows = unpaidFirst(source);
  int sum(int Function(SlipRow r) pick) => rows.fold(0, (a, r) => a + pick(r));
  final totals = older != null
      ? (
          net: sum((r) => r.netPiastres),
          deductions: sum((r) => r.deductionsPiastres),
          advances: sum((r) => r.advancePiastres),
          people: rows.length,
          paid: rows.where((r) => r.paidMethod != null).length,
        )
      : (
          net: cur?.totals.netPiastres ?? 0,
          deductions: cur?.totals.deductionsPiastres ?? 0,
          advances: cur?.totals.advancesPiastres ?? 0,
          people: cur?.totals.people ?? rows.length,
          paid: cur?.paidCount ?? 0,
        );
  final missing = [
    for (final r in rows)
      if (r.salaryMissing) r,
  ];
  final missingCount = older != null
      ? missing.length
      : (cur?.missingSalaryCount ??
            cur?.totals.missingSalaryCount ??
            missing.length);
  return PayrollShown(
    current: cur,
    currentRead: currentRead,
    unsettled: unsettled,
    older: older,
    period: period,
    phase: phase,
    rows: rows,
    shownRead: olderRead ?? currentRead,
    people: people,
    totals: totals,
    missing: missing,
    missingCount: missingCount,
    paidByHand: rows.where((r) => r.paidByHand).length,
  );
});
