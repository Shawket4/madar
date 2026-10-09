/// `dawam.reports` page: the port of the web's dawam/reports-page.tsx
/// `StaffReportsPage`; TEAM-RPT rows (+ the area-wide TEAM-ALL rows it
/// carries).
///
/// Over the scope bar's branch and the dates on the page, opening on this pay
/// period: attendance & discipline, labour cost against sales (only with POS
/// on), payroll history with overtime, and advances. Only the open tab's data
/// is asked for; every table exports as CSV. Refused (`<Restricted>`) when no
/// tab is allowed; nothing is requested then.
library;

import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart'
    show
        AttendanceSummary,
        Branch,
        ExpenseAdvanceRow,
        LabourDay,
        PayrollHistoryRow,
        SalaryAdvanceRow;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../attendance/attendance_providers.dart' show attendanceSummaryProvider;
import '../shared/attendance_errors.dart';
import '../shared/page_gate.dart';
import '../shared/refresh_button.dart';
import '../shared/refresh_toast.dart';
import '../shared/staff_query.dart';
import '../shared/team_format.dart';
import 'team_reports_data.dart';
import 'team_reports_providers.dart';

abstract final class ReportsMetrics {
  /// The date range's cap (`max-w-xl`).
  static const double range = 576;
}

class StaffReportsPage extends ConsumerWidget {
  const StaffReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => TeamPageGate(
    allowed: (a) => a.canAny(const [Cap.hrAttendanceRead, Cap.hrPayrollRead]),
    titleKey: 'dawam.reports',
    whoKey: 'dawam.reportsNoAccess',
    child: const _ReportsBody(),
  );
}

/// The tabs this person may open, in the web's order (TEAM-RPT-005).
List<String> reportTabs({
  required bool attendance,
  required bool payroll,
  required bool pos,
}) => [
  if (attendance) 'attendance',
  if (payroll && pos) 'labour',
  if (payroll) 'payroll',
  if (payroll) 'advances',
];

/// The read a tab shows, keyed by the page's params.
FutureProvider<Object?> reportReadOf(String tab, ReportQuery k) =>
    switch (tab) {
      'attendance' => attendanceSummaryProvider(reportAttendanceKey(k)),
      'labour' => labourVsSalesProvider(k),
      'payroll' => payrollHistoryProvider(k),
      _ => advancesReportProvider(k),
    };

class _ReportsBody extends ConsumerStatefulWidget {
  const _ReportsBody();

  @override
  ConsumerState<_ReportsBody> createState() => _ReportsBodyState();
}

class _ReportsBodyState extends ConsumerState<_ReportsBody> {
  /// Picked by hand; until then, this pay period.
  ({String from, String to})? _range;
  String? _picked;
  late final AppLifecycleListener _lifecycle;
  DateTime? _loadedAt;
  FutureProvider<Object?>? _read;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// Refetch on focus (`dawamQuery`, TEAM-ALL-009): back after the shown
  /// report went stale (30 s) asks again; sooner does nothing.
  void _onResume() {
    final at = _loadedAt;
    final read = _read;
    if (at == null || read == null || !mounted) return;
    final now = ref.read(clockProvider)();
    if (now.difference(at) < kQueryStaleTime) return;
    _loadedAt = now;
    ref.invalidate(read);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final authz = ref.watch(authzProvider);
    final pos = ref.watch(orgModulesProvider.select((m) => m.has('pos')));
    final branchId = ref.watch(scopeProvider.select((s) => s.branchId));
    final settingsQ = ref.watch(staffAttendanceSettingsProvider);
    listenStaffRefreshFailure(ref, context, staffAttendanceSettingsProvider);
    final day = settingsQ.value?.periodStartDay;
    final periodStartDay = day != null && day >= 1 && day <= 28 ? day : 1;
    final today = dashParseYmd(teamTodayIsoOf(ref))!;
    final range =
        _range ??
        (() {
          final r = dashQuickRange(
            DashQuickRange.thisPeriod,
            today: today,
            periodStartDay: periodStartDay,
          );
          return (from: dashYmd(r.from), to: dashYmd(r.to));
        })();

    final tabs = reportTabs(
      attendance: authz.can(Cap.hrAttendanceRead),
      payroll: authz.can(Cap.hrPayrollRead),
      pos: pos,
    );
    final picked = _picked;
    final tab = picked != null && tabs.contains(picked)
        ? picked
        : (tabs.isEmpty ? null : tabs.first);
    final backwards = range.to.compareTo(range.from) < 0;
    final ReportQuery k = (from: range.from, to: range.to, branchId: branchId);
    final read = _read = tab == null || backwards ? null : reportReadOf(tab, k);
    final q = read == null ? null : ref.watch(read);
    if (read != null) {
      listenStaffRefreshFailure(ref, context, read);
      ref.listen(read, (_, next) {
        if (next.hasValue && !next.isLoading) {
          _loadedAt = ref.read(clockProvider)();
        }
      });
      if (q!.hasValue) _loadedAt ??= ref.read(clockProvider)();
    }

    final names = {
      'attendance': t('dawam.rAttendance'),
      'labour': t('dawam.rLabour'),
      'payroll': t('dawam.rPayroll'),
      'advances': t('dawam.salaryAdvances'),
    };
    return DashPageScaffold(
      title: t('dawam.reports'),
      subtitle: t('dawamOps.reportsSubtitle'),
      actions: [
        DawamRefreshButton(busy: anyFetching([settingsQ, ?q])),
      ],
      filters: Align(
        alignment: AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: ReportsMetrics.range),
          child: DashDateRangeField(
            from: dashParseYmd(range.from),
            to: dashParseYmd(range.to),
            today: today,
            quick: const [
              DashQuickRange.thisPeriod,
              DashQuickRange.lastPeriod,
              DashQuickRange.thisMonth,
              DashQuickRange.lastMonth,
              DashQuickRange.thisWeek,
            ],
            periodStartDay: periodStartDay,
            onChanged: (f, to) => setState(
              () => _range = (
                from: f == null ? range.from : dashYmd(f),
                to: to == null ? range.to : dashYmd(to),
              ),
            ),
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.xl,
        children: [
          if (tab != null)
            DashPageTabs<String>(
              tabs: [for (final v in tabs) DashTab(value: v, label: names[v]!)],
              value: tab,
              onChanged: (v) => setState(() => _picked = v),
              // The read the tab shows, with the page's params.
              onIntent: backwards ? null : (v) => ref.warm(reportReadOf(v, k)),
            ),
          if (backwards)
            DashEmptyState(
              icon: 'calendar-clock',
              title: t('dawamOps.rangeBackwards'),
              description: t('dawamOps.rangeBackwardsHint'),
            )
          else if (tab != null)
            switch (tab) {
              'attendance' => _AttendanceTab(k),
              'labour' => _LabourTab(k),
              'payroll' => _PayrollTab(k),
              _ => _AdvancesTab(k),
            },
        ],
      ),
    );
  }
}

// ── the tabs ─────────────────────────────────────────────────────────────

int _sum<R>(Iterable<R> rows, int Function(R r) f) =>
    rows.fold(0, (a, r) => a + f(r));

/// A failed read says so in its table(s), a failed refresh too (the web's
/// table takes the raw query error, TEAM-ALL-010); an attempt Riverpod will
/// retry is still loading.
bool _failed(AsyncValue<Object?> q) => q.hasError && !q.retrying;

/// TEAM-RPT-010/011.
class _AttendanceTab extends ConsumerWidget {
  const _AttendanceTab(this.k);

  final ReportQuery k;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final lang = ref.watch(localeProvider);
    final read = attendanceSummaryProvider(reportAttendanceKey(k));
    final q = ref.watch(read);
    final rows = q.value ?? const <AttendanceSummary>[];
    final loading = q.awaitingFirst;
    String h(int m) => fmtHours(lang, m);
    final cols = <ReportCol<AttendanceSummary>>[
      ReportCol('name', t('staff.name'), (r) => r.employeeName),
      ReportCol(
        'present',
        t('dawam.rPresent'),
        (r) => r.presentDays,
        numeric: true,
      ),
      ReportCol('late', t('dawam.stateLate'), (r) => r.lateDays, numeric: true),
      ReportCol(
        'absent',
        t('dawam.stateAbsent'),
        (r) => r.absentDays,
        numeric: true,
      ),
      ReportCol(
        'leave',
        t('dawam.state_on_leave'),
        (r) => r.leaveDays,
        numeric: true,
      ),
      ReportCol(
        'worked',
        t('dawam.rWorked'),
        (r) => h(r.totalWorkedMinutes),
        numeric: true,
      ),
      ReportCol(
        'lateMin',
        t('dawam.rLateTime'),
        (r) => h(r.totalLateMinutes),
        numeric: true,
      ),
      ReportCol(
        'ot',
        t('dawam.overtime'),
        (r) => h(r.totalOvertimeMinutes),
        numeric: true,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        _Cards(
          wideColumns: 4,
          children: [
            DashStatCard(
              label: t('dawam.people'),
              value: rows.length,
              format: DashStatFormat.number,
              loading: loading,
            ),
            DashStatCard(
              label: t('dawam.stateLate'),
              value: _sum(rows, (r) => r.lateDays),
              format: DashStatFormat.number,
              loading: loading,
            ),
            DashStatCard(
              label: t('dawam.stateAbsent'),
              value: _sum(rows, (r) => r.absentDays),
              format: DashStatFormat.number,
              loading: loading,
            ),
            DashStatCard(
              label: t('dawam.overtime'),
              valueText: h(_sum(rows, (r) => r.totalOvertimeMinutes)),
              loading: loading,
            ),
          ],
        ),
        ReportTable<AttendanceSummary>(
          name: 'attendance',
          cols: cols,
          rows: rows,
          rowKey: (r) => r.employeeId,
          q: q,
          empty: t('dawam.rEmpty'),
          onRetry: () => ref.invalidate(read),
        ),
      ],
    );
  }
}

/// TEAM-RPT-020/021.
class _LabourTab extends ConsumerWidget {
  const _LabourTab(this.k);

  final ReportQuery k;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final read = labourVsSalesProvider(k);
    final q = ref.watch(read);
    final branches = ref.watch(branchesProvider).value ?? const <Branch>[];
    final names = {for (final b in branches) b.id: b.name};
    final rows = q.value ?? const <LabourDay>[];
    final loading = q.awaitingFirst;
    final cols = <ReportCol<LabourDay>>[
      ReportCol('date', t('dawam.rDate'), (r) => f.fmtDate(r.date)),
      ReportCol('branch', t('dawam.branch'), (r) => names[r.branchId] ?? '—'),
      ReportCol(
        'sales',
        t('dawam.rSales'),
        (r) => r.salesPiastres,
        money: true,
      ),
      ReportCol(
        'labour',
        t('dawam.rLabourCost'),
        (r) => r.labourPiastres,
        money: true,
      ),
      ReportCol(
        'share',
        t('dawam.rShare'),
        (r) => labourShareBp(r.labourShareBp),
        numeric: true,
      ),
    ];
    final sales = _sum(rows, (r) => r.salesPiastres);
    final labour = _sum(rows, (r) => r.labourPiastres);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        _Cards(
          wideColumns: 3,
          children: [
            DashStatCard(
              label: t('dawam.rSales'),
              value: sales,
              format: DashStatFormat.money,
              loading: loading,
            ),
            DashStatCard(
              label: t('dawam.rLabourCost'),
              value: labour,
              format: DashStatFormat.money,
              loading: loading,
            ),
            DashStatCard(
              label: t('dawam.rShare'),
              valueText: ltr(labourShare(labour, sales)),
              loading: loading,
            ),
          ],
        ),
        ReportTable<LabourDay>(
          name: 'labour-vs-sales',
          cols: cols,
          rows: rows,
          rowKey: (r) => '${r.date}|${r.branchId}',
          q: q,
          empty: t('dawam.rEmpty'),
          onRetry: () => ref.invalidate(read),
        ),
      ],
    );
  }
}

/// TEAM-RPT-030/031.
class _PayrollTab extends ConsumerWidget {
  const _PayrollTab(this.k);

  final ReportQuery k;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final lang = ref.watch(localeProvider);
    final read = payrollHistoryProvider(k);
    final q = ref.watch(read);
    final rows = q.value ?? const <PayrollHistoryRow>[];
    final loading = q.awaitingFirst;
    final cols = <ReportCol<PayrollHistoryRow>>[
      ReportCol(
        'period',
        t('dawam.period'),
        (r) => '${f.fmtDate(r.startDate)} – ${f.fmtDate(r.endDate)}',
        minWidth: 220,
      ),
      ReportCol('people', t('dawam.people'), (r) => r.people, numeric: true),
      ReportCol('base', t('dawam.salary'), (r) => r.basePiastres, money: true),
      ReportCol(
        'otMin',
        t('dawam.rOtTime'),
        (r) => fmtHours(lang, r.overtimeMinutes),
        numeric: true,
        minWidth: 160,
      ),
      ReportCol(
        'ot',
        t('dawam.overtime'),
        (r) => r.overtimePiastres,
        money: true,
      ),
      ReportCol(
        'bonuses',
        t('dawam.bonuses'),
        (r) => r.bonusesPiastres,
        money: true,
      ),
      ReportCol(
        'deductions',
        t('dawam.deductions'),
        (r) => r.deductionsPiastres,
        money: true,
      ),
      ReportCol(
        'advances',
        t('dawam.advancesCollected'),
        (r) => r.advancesPiastres,
        money: true,
      ),
      ReportCol('net', t('dawam.net'), (r) => r.netPiastres, money: true),
      // The reader's words for the phase, never the server's raw status.
      ReportCol(
        'status',
        t('common.status'),
        (r) => t('dawam.phase_${reportPhase(r.status)}'),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        _Cards(
          wideColumns: 3,
          children: [
            DashStatCard(
              label: t('dawam.totalNet'),
              value: _sum(rows, (r) => r.netPiastres),
              format: DashStatFormat.money,
              loading: loading,
            ),
            DashStatCard(
              label: t('dawam.overtime'),
              value: _sum(rows, (r) => r.overtimePiastres),
              format: DashStatFormat.money,
              loading: loading,
            ),
            DashStatCard(
              label: t('dawam.deductions'),
              value: _sum(rows, (r) => r.deductionsPiastres),
              format: DashStatFormat.money,
              loading: loading,
            ),
          ],
        ),
        ReportTable<PayrollHistoryRow>(
          name: 'payroll-history',
          cols: cols,
          rows: rows,
          rowKey: (r) => r.periodId,
          q: q,
          empty: t('dawam.rEmpty'),
          onRetry: () => ref.invalidate(read),
        ),
      ],
    );
  }
}

/// TEAM-RPT-040/041/042.
class _AdvancesTab extends ConsumerWidget {
  const _AdvancesTab(this.k);

  final ReportQuery k;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final read = advancesReportProvider(k);
    final q = ref.watch(read);
    final data = q.value;
    final loading = q.awaitingFirst;
    final sCols = <ReportCol<SalaryAdvanceRow>>[
      ReportCol('name', t('staff.name'), (r) => r.employeeName),
      ReportCol('given', t('dawam.rGiven'), (r) => f.fmtDate(r.givenOn)),
      ReportCol(
        'amount',
        t('dawam.amountEgp'),
        (r) => r.amountPiastres,
        money: true,
      ),
      ReportCol(
        'inst',
        t('dawam.installments'),
        (r) => r.installments,
        numeric: true,
      ),
      ReportCol(
        'left',
        t('dawam.rLeft'),
        (r) => r.remainingPiastres,
        money: true,
      ),
      ReportCol(
        'status',
        t('common.status'),
        (r) => t('staff.req_${r.status}', defaultValue: r.status),
      ),
    ];
    final eCols = <ReportCol<ExpenseAdvanceRow>>[
      ReportCol('name', t('staff.name'), (r) => r.employeeName),
      ReportCol('given', t('dawam.rGiven'), (r) => f.fmtDate(r.givenOn)),
      ReportCol('purpose', t('dawam.purpose'), (r) => r.purpose),
      ReportCol(
        'via',
        t('dawam.rVia'),
        (r) => t('dawam.via_${r.via}', defaultValue: r.via),
      ),
      ReportCol(
        'amount',
        t('dawam.amountEgp'),
        (r) => r.amountPiastres,
        money: true,
      ),
    ];
    final heading = DashType.bodyStrong.copyWith(color: c.textSecondary);
    Widget section(String title, Widget table) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.sm,
      children: [
        Semantics(header: true, child: Text(title, style: heading)),
        table,
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.xl,
      children: [
        _Cards(
          wideColumns: 3,
          children: [
            DashStatCard(
              label: t('dawam.rSalaryGiven'),
              value: data?.salaryGivenPiastres ?? 0,
              format: DashStatFormat.money,
              loading: loading,
            ),
            DashStatCard(
              label: t('dawam.rOutstanding'),
              value: data?.salaryOutstandingPiastres ?? 0,
              format: DashStatFormat.money,
              loading: loading,
            ),
            DashStatCard(
              label: t('dawam.rExpenseGiven'),
              value: data?.expenseGivenPiastres ?? 0,
              format: DashStatFormat.money,
              loading: loading,
            ),
          ],
        ),
        section(
          t('dawam.salaryAdvances'),
          ReportTable<SalaryAdvanceRow>(
            name: 'salary-advances',
            cols: sCols,
            rows: data?.salary ?? const [],
            rowKey: (r) => r.id,
            q: q,
            empty: t('dawam.noAdvances'),
            onRetry: () => ref.invalidate(read),
          ),
        ),
        section(
          t('dawam.expenseAdvances'),
          ReportTable<ExpenseAdvanceRow>(
            name: 'expense-advances',
            cols: eCols,
            rows: data?.expense ?? const [],
            rowKey: (r) => r.id,
            q: q,
            empty: t('dawam.noExpenses'),
            onRetry: () => ref.invalidate(read),
          ),
        ),
      ],
    );
  }
}

/// A tab's stat cards: 2 columns, [wideColumns] from `lg`
/// (`grid-cols-2 gap-3 lg:grid-cols-N`).
class _Cards extends StatelessWidget {
  const _Cards({required this.wideColumns, required this.children});

  final int wideColumns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cols = MediaQuery.sizeOf(context).width >= DashBreakpoints.lg
        ? wideColumns
        : 2;
    return LayoutBuilder(
      builder: (context, box) {
        final w = (box.maxWidth - Space.md * (cols - 1)) / cols;
        return Wrap(
          spacing: Space.md,
          runSpacing: Space.md,
          children: [for (final c in children) SizedBox(width: w, child: c)],
        );
      },
    );
  }
}

/// One report table (TEAM-RPT-006/007, TEAM-ALL-020): the CSV button over a
/// table of pages of 10 (no search, no Columns menu, phone cards titled by
/// the first column); a failed read is the report's error with Retry
/// instead (a 403 is not "nothing in this period").
class ReportTable<R> extends ConsumerWidget {
  const ReportTable({
    required this.name,
    required this.cols,
    required this.rows,
    required this.rowKey,
    required this.q,
    required this.empty,
    required this.onRetry,
    super.key,
  });

  /// The CSV's file name, without `.csv`.
  final String name;
  final List<ReportCol<R>> cols;
  final List<R> rows;
  final Object Function(R row) rowKey;
  final AsyncValue<Object?> q;
  final String empty;
  final VoidCallback onRetry;

  Future<void> _csv(BuildContext context, WidgetRef ref) async {
    final t = ref.read(tProvider);
    final f = ref.read(formatProvider);
    try {
      await ref
          .read(fileGatewayProvider)
          .saveBytes(
            utf8.encode('\uFEFF${reportCsv(cols, rows)}'),
            filename: '$name.csv',
            mimeType: MimeTypes.csv,
          );
    } on Object catch (e) {
      if (context.mounted) {
        DashToast.error(context, attendanceErrorText(e, t, f));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    if (_failed(q)) {
      return DashErrorState(
        title: t('dawam.reportLoadError'),
        message: attendanceErrorText(q.error, t, f),
        retryLabel: t('common.retry'),
        retrying: q.isLoading,
        onRetry: onRetry,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.sm,
      children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: DashButton(
            label: t('dawam.csv'),
            variant: DashButtonVariant.outline,
            size: DashButtonSize.compact,
            onPressed: rows.isEmpty ? null : () => _csv(context, ref),
          ),
        ),
        DashDataTable<R>(
          columns: [
            for (final c in cols)
              DashColumn<R>(
                id: c.id,
                label: c.header,
                numeric: c.money || c.numeric,
                minWidth: c.minWidth ?? (c.money ? 160 : 120),
                text: (r) {
                  final v = c.value(r);
                  return c.money ? f.fmtMoney(v as num) : '$v';
                },
              ),
          ],
          rows: rows,
          rowKey: rowKey,
          loading: q.awaitingFirst,
          hideViewOptions: true,
          empty: DashEmptyState(icon: 'scale', title: empty),
        ),
      ],
    );
  }
}
