/// `dawam.payroll` page: the port of the web's `dawam/payroll-page.tsx`
/// `PayrollPage` (TEAM-PAY rows): the month that opened itself, its live
/// preview, approve / reopen / mark paid, the pay lists and the CSV, the
/// older months still to settle, and the four tabs. Every figure is the
/// server's; `payroll_data.dart` lays the reads out.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show DashRoutePrefetch;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/page_gate.dart';
import '../shared/refresh_button.dart';
import '../shared/refresh_toast.dart';
import '../shared/rules_banner.dart';
import '../shared/staff_query.dart';
import '../shared/team_format.dart';
import 'money_dialogs.dart';
import 'money_errors.dart';
import 'payroll_data.dart';
import 'payroll_exports.dart';
import 'payroll_logic.dart';
import 'payroll_steps.dart';
import 'payroll_tabs.dart';
import 'payslip_sheet.dart';

class PayrollPage extends ConsumerWidget {
  const PayrollPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => TeamPageGate(
    allowed: (a) => a.canAny(const [Cap.hrPayrollRead, Cap.hrPayrollRun]),
    titleKey: 'dawam.payroll',
    whoKey: 'dawam.payrollNoAccess',
    child: const _PayrollBody(),
  );
}

/// Fixed web heights (`Skeleton h-40` under a tab).
class PayrollMetrics {
  static const double tabSkeleton = Space.xxl * 5;
}

class _PayrollBody extends ConsumerStatefulWidget {
  const _PayrollBody();

  @override
  ConsumerState<_PayrollBody> createState() => _PayrollBodyState();
}

class _PayrollBodyState extends ConsumerState<_PayrollBody> {
  late final AppLifecycleListener _lifecycle;
  DateTime? _loadedAt;
  bool _exporting = false;

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

  /// Refetch on focus (`dawamQuery`, TEAM-ALL-009): back after the reads
  /// went stale (30 s) asks again; sooner does nothing.
  void _onResume() {
    final at = _loadedAt;
    if (at == null || !mounted) return;
    final now = ref.read(clockProvider)();
    if (now.difference(at) < kQueryStaleTime) return;
    _loadedAt = now;
    ref.read(staffRevisionsProvider.notifier).refetch();
  }

  String _err(Object? e) =>
      dawamErrorMessage(e, ref.read(tProvider), ref.read(formatProvider));

  /// TEAM-PAY-006: confirm, then freeze the month.
  Future<void> _approve(PayrollShown s) async {
    final t = ref.read(tProvider);
    final f = ref.read(formatProvider);
    final period = s.period;
    if (period == null) return;
    final ahead = daysStillToCome(period.endDate, teamTodayIsoOf(ref));
    final hint =
        '${t('dawamOps.approveTotals', args: {'people': s.totals.people, 'net': f.fmtMoney(s.totals.net)})} '
        '${t('dawam.approveHint')}';
    final ok = await showDashConfirm(
      context,
      title: t('dawam.approveTitle'),
      description: ahead > 0
          ? '${t('dawam.approveDaysAhead', count: ahead)} $hint'
          : hint,
      confirmLabel: t('dawam.approve'),
    );
    if (!ok || !mounted) return;
    final staff = ref.read(staffRevisionsProvider.notifier);
    try {
      await ref.read(apiProvider).staff.generatePeriod(id: period.id);
    } on Object catch (e) {
      if (mounted) DashToast.error(context, _err(e));
      return;
    }
    staff.invalidateStaff();
    if (mounted) DashToast.success(context, t('dawam.approved'));
  }

  /// TEAM-PAY-008 / TEAM-ALL-024: the pay lists workbook.
  Future<void> _exportLists(PayrollShown s) async {
    final t = ref.read(tProvider);
    setState(() => _exporting = true);
    try {
      await runPayrollExcel(
        context,
        ref.read(exporterProvider),
        t,
        payListsConfig(
          t: t,
          f: ref.read(formatProvider),
          rows: s.rows,
          people: s.people,
          period: s.period,
          logoUrl: payrollExportLogo(ref),
        ),
      );
    } on Object catch (e) {
      if (mounted) DashToast.error(context, _err(e));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _openSlip(SlipRow r) => showDashSidePanel<void>(
    context,
    builder: (_) => PayslipSheet(employeeId: r.employeeId),
  );

  void _markPaid(PayrollShown s, SlipRow r) {
    final period = s.period;
    if (period == null) return;
    showMarkPaidDialog(
      context,
      periodId: period.id,
      person: MarkPaidPerson(
        employeeId: r.employeeId,
        name: r.name,
        payMethod: s.people[r.employeeId]?.payMethod,
        net: r.netPiastres,
      ),
      first: s.paidByHand == 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final authz = ref.watch(authzProvider);
    final canRun = authz.can(Cap.hrPayrollRun);
    final s = ref.watch(payrollShownProvider);
    final view = ref.watch(payrollViewProvider);
    final views = ref.read(payrollViewProvider.notifier);
    final period = s.period;
    final phase = s.phase;
    ref.listen(payrollCurrentProvider, (_, next) {
      if (next.hasValue && !next.isLoading) {
        _loadedAt = ref.read(clockProvider)();
      }
    });
    if (s.currentRead.hasValue) _loadedAt ??= ref.read(clockProvider)();
    final olderRead = s.older == null
        ? null
        : payrollOlderSlipsProvider(olderKey(s.older!));
    final peopleRead = ref.watch(payrollPeopleProvider);
    final branchId = ref.watch(scopeProvider.select((x) => x.branchId));
    // TEAM-ALL-022: a failed background refresh toasts (never a retry).
    listenStaffRefreshFailure(ref, context, payrollCurrentProvider);
    if (olderRead != null) listenStaffRefreshFailure(ref, context, olderRead);
    listenStaffRefreshFailure(ref, context, payrollPeopleProvider);
    // TEAM-ALL-008: the spinner covers every read on screen (the web's
    // `useIsFetching` over the dawam keys): the active tab's list and an
    // open History sheet's payslips too.
    final historyId = view.historyId;
    final tabRead = switch (view.tab) {
      PayrollTab.lines => ref.watch(payrollAdjustmentsProvider),
      PayrollTab.advances => ref.watch(payrollAdvancesProvider),
      PayrollTab.expenses => ref.watch(payrollExpensesProvider(branchId)),
      PayrollTab.history when historyId != null => ref.watch(
        payrollOlderSlipsProvider((id: historyId, draft: false)),
      ),
      _ => null,
    };

    final actions = <Widget>[
      DawamRefreshButton(
        busy: anyFetching([s.currentRead, s.shownRead, peopleRead, ?tabRead]),
      ),
      if (period != null)
        DashStatusPill(tone: phaseTone(phase), label: t(phaseKey(phase))),
      if (canRun && phase == PayPhase.open && period != null)
        DashButton(
          label: t('dawam.approve'),
          icon: 'badge-check',
          tooltip: s.missingCount > 0 ? t('dawamOps.approveBlocked') : null,
          onPressed: s.missingCount > 0 ? null : () => _approve(s),
        ),
      if (canRun && phase == PayPhase.approved && s.paidByHand == 0)
        DashButton(
          label: t('dawam.reopen'),
          icon: 'rotate-ccw',
          variant: DashButtonVariant.outline,
          onPressed: period == null
              ? null
              : () => showReopenDialog(context, periodId: period.id),
        ),
      if (phase != PayPhase.open) ...[
        DashExportButton(
          label: t('dawam.payLists'),
          loading: _exporting,
          onExport: () => _exportLists(s),
        ),
        DashButton(
          label: t('dawam.csv'),
          variant: DashButtonVariant.ghost,
          onPressed: period == null
              ? null
              : () => savePayrollCsv(context, ref, period),
        ),
      ],
    ];

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        const RulesFirstBanner(),
        if (s.older != null)
          _Notice(
            tone: DashTone.neutral,
            title: t(
              'dawam.viewingOlder',
              args: {
                'month': monthLabel(f, s.older!.startDate, s.older!.endDate),
              },
            ),
            action: DashButton(
              label: t('dawam.backToCurrent'),
              variant: DashButtonVariant.outline,
              size: DashButtonSize.compact,
              onPressed: () => views.openMonth(null),
            ),
          ),
        for (final u in s.unsettled)
          if (u.periodId != s.older?.id) _unsettledBanner(t, f, u, views),
        if (period != null)
          PayrollSteps(
            phase: phase,
            blockers: phase == PayPhase.open ? s.missingCount : 0,
            paid: s.totals.paid,
            people: s.totals.people,
          ),
        if (phase == PayPhase.open && s.missingCount > 0)
          _Notice(
            key: const ValueKey('payroll-salary-missing'),
            tone: DashTone.warning,
            title: t('dawam.salaryMissingTitle', count: s.missingCount),
            body: [
              if (s.missing.isNotEmpty)
                '${s.missing.map((r) => r.name).join(t('common.listSeparator'))}.',
              t('dawam.salaryMissingHint'),
            ].join(' '),
            action: DashButton(
              label: t('dawamOps.setSalaries'),
              variant: DashButtonVariant.outline,
              size: DashButtonSize.compact,
              onIntent: () => ref.prefetchRoute('/staff/employees'),
              onPressed: () => context.go('/staff/employees'),
            ),
          ),
        _StatCards(s: s),
        DashPageTabs<PayrollTab>(
          value: view.tab,
          onChanged: views.setTab,
          onIntent: (tab) => switch (tab) {
            PayrollTab.lines => ref.warm(payrollAdjustmentsProvider),
            PayrollTab.advances => ref.warm(payrollAdvancesProvider),
            PayrollTab.expenses => ref.warm(payrollExpensesProvider(branchId)),
            _ => null,
          },
          tabs: [
            DashTab(value: PayrollTab.payslips, label: t('dawam.payslips')),
            DashTab(value: PayrollTab.lines, label: t('dawam.payLines')),
            DashTab(
              value: PayrollTab.advances,
              label: t('dawam.salaryAdvances'),
            ),
            DashTab(
              value: PayrollTab.expenses,
              label: t('dawam.expenseAdvances'),
            ),
            DashTab(value: PayrollTab.history, label: t('dawam.history')),
          ],
        ),
        switch (view.tab) {
          PayrollTab.payslips => _PayslipsTable(
            s: s,
            canRun: canRun,
            onOpen: _openSlip,
            onMarkPaid: (r) => _markPaid(s, r),
            onRetry: () => olderRead == null
                ? ref.invalidate(payrollCurrentProvider)
                : ref.invalidate(olderRead),
          ),
          PayrollTab.lines => const PayLinesTab(),
          PayrollTab.advances => const AdvancesTab(),
          PayrollTab.expenses => const ExpensesTab(),
          PayrollTab.history => const HistoryTab(),
        },
      ],
    );

    return DashPageScaffold(
      title: t('dawam.payroll'),
      subtitle: period != null
          ? t(
              'dawam.periodLine',
              args: {
                'from': f.fmtDate(period.startDate),
                'to': f.fmtDate(period.endDate),
              },
            )
          : t('dawam.payrollSubtitle'),
      actions: actions,
      body: body,
    );
  }

  /// TEAM-PAY-010: an older month not fully paid.
  Widget _unsettledBanner(
    Translator t,
    DashFormat f,
    Unsettled u,
    PayrollViewNotifier views,
  ) {
    final month = monthLabel(f, u.startsOn, u.endsOn);
    final what = u.status == 'draft'
        ? t('dawam.unsettledDraft')
        : u.paidCount == null
        ? t('dawam.unsettledApprovedNoCount')
        : t(
            'dawam.unsettledApproved',
            args: {'paid': u.paidCount, 'people': u.people},
          );
    final key = (id: u.periodId, draft: u.status == 'draft');
    return _Notice(
      key: ValueKey('payroll-unsettled-${u.periodId}'),
      tone: DashTone.warning,
      title: t('dawam.unsettledTitle', args: {'month': month}),
      body: '$what · ${f.fmtMoney(u.netTotalPiastres)}',
      action: DashButton(
        label: t('dawam.unsettledOpen'),
        variant: DashButtonVariant.outline,
        size: DashButtonSize.compact,
        onIntent: () => ref.warm(payrollOlderSlipsProvider(key)),
        onPressed: () => views.openMonth(u.periodId),
      ),
    );
  }
}

/// A status or alert strip (`role="status"` / `role="alert"`): a title, a
/// line under it, an action at the end; wraps on a narrow screen.
class _Notice extends StatelessWidget {
  const _Notice({
    required this.tone,
    required this.title,
    required this.action,
    this.body,
    super.key,
  });

  final DashTone tone;
  final String title;
  final String? body;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final neutral = tone == DashTone.neutral;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(
          color: neutral ? c.surfaceAlt : tone.wash(c),
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(
            color: neutral ? c.hairline : tone.solid(c).withValues(alpha: 0.4),
          ),
        ),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: Space.md,
          runSpacing: Space.sm,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: Space.xs,
              children: [
                Text(
                  title,
                  style: DashType.bodyStrong.copyWith(color: c.textPrimary),
                ),
                if (body != null)
                  Text(
                    body!,
                    style: DashType.body.copyWith(color: c.textSecondary),
                  ),
              ],
            ),
            action,
          ],
        ),
      ),
    );
  }
}

/// TEAM-PAY-012: Net pay · People · Deductions · Advances collected.
class _StatCards extends ConsumerWidget {
  const _StatCards({required this.s});

  final PayrollShown s;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final cols = MediaQuery.sizeOf(context).width >= DashBreakpoints.lg ? 4 : 2;
    final loading = s.loading;
    final cards = [
      DashStatCard(
        label: t('dawam.totalNet'),
        value: s.totals.net,
        format: DashStatFormat.money,
        icon: 'circle-dollar-sign',
        loading: loading,
        reserveFooter: true,
      ),
      DashStatCard(
        label: t('dawam.people'),
        value: s.totals.people,
        format: DashStatFormat.number,
        icon: 'users-round',
        loading: loading,
        reserveFooter: true,
        hint: s.phase == PayPhase.open
            ? null
            : t(
                'dawam.paidCount',
                args: {'paid': s.totals.paid, 'people': s.totals.people},
              ),
      ),
      DashStatCard(
        label: t('dawam.deductions'),
        value: s.totals.deductions,
        format: DashStatFormat.money,
        icon: 'receipt-text',
        loading: loading,
        reserveFooter: true,
      ),
      DashStatCard(
        label: t('dawam.advancesCollected'),
        value: s.totals.advances,
        format: DashStatFormat.money,
        icon: 'hand-coins',
        loading: loading,
        reserveFooter: true,
      ),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final w = (box.maxWidth - Space.md * (cols - 1)) / cols;
        return Wrap(
          spacing: Space.md,
          runSpacing: Space.md,
          children: [for (final c in cards) SizedBox(width: w, child: c)],
        );
      },
    );
  }
}

/// TEAM-PAY-020 … -023: the payslips, unpaid first.
class _PayslipsTable extends ConsumerWidget {
  const _PayslipsTable({
    required this.s,
    required this.canRun,
    required this.onOpen,
    required this.onMarkPaid,
    required this.onRetry,
  });

  final PayrollShown s;
  final bool canRun;
  final ValueChanged<SlipRow> onOpen;
  final ValueChanged<SlipRow> onMarkPaid;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final read = s.shownRead;
    if (read.failedFirst) {
      return DashErrorState(
        title: t('dawam.payrollLoadError'),
        message: dawamErrorMessage(read.error, t, f),
        retryLabel: t('common.retry'),
        retrying: read.isLoading,
        onRetry: onRetry,
      );
    }
    String money(int v) => f.fmtMoney(v);
    DashColumn<SlipRow> num(String id, String key, int Function(SlipRow) v) =>
        DashColumn<SlipRow>(
          id: id,
          label: t(key),
          numeric: true,
          hideable: false,
          text: (r) => money(v(r)),
        );
    return DashDataTable<SlipRow>(
      rows: s.rows,
      rowKey: (r) => r.employeeId,
      loading: s.loading,
      onRowTap: onOpen,
      empty: DashEmptyState(
        icon: 'banknote',
        title: t('dawam.noPayslips'),
        description: t('dawam.noPayslipsHint'),
      ),
      columns: [
        DashColumn<SlipRow>(
          id: 'name',
          label: t('staff.name'),
          phone: DashPhoneRole.title,
          text: (r) => r.name,
          cell: (context, r) => MadarClippedText(
            r.name,
            style: DashType.bodyStrong.copyWith(color: c.textPrimary),
          ),
        ),
        DashColumn<SlipRow>(
          id: 'base',
          label: t('dawam.salary'),
          numeric: true,
          hideable: false,
          text: (r) => r.salaryMissing
              ? t('dawam.notSet')
              : money(payslipLines(r, f).first.amount),
          cell: (context, r) => r.salaryMissing
              ? Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: DashBadge(t('dawam.notSet'), tone: DashTone.warning),
                )
              : Text(
                  money(payslipLines(r, f).first.amount),
                  style: DashType.mono.copyWith(color: c.textPrimary),
                ),
        ),
        num('ot', 'dawam.overtime', (r) => r.overtimePiastres),
        num('bonuses', 'dawam.bonuses', (r) => r.bonusesPiastres),
        num('deductions', 'dawam.deductions', (r) => -r.deductionsPiastres),
        num('advance', 'dawam.advance', (r) => -r.advancePiastres),
        DashColumn<SlipRow>(
          id: 'net',
          label: t('dawam.net'),
          numeric: true,
          hideable: false,
          minWidth: 160,
          text: (r) => money(r.netPiastres),
          cell: (context, r) => Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: Space.sm,
            children: [
              Text(
                money(r.netPiastres),
                style: DashType.mono.copyWith(
                  color: c.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (r.carryOutPiastres > 0)
                DashBadge(
                  t(
                    'dawam.carries',
                    args: {'amount': money(r.carryOutPiastres)},
                  ),
                ),
            ],
          ),
        ),
        DashColumn<SlipRow>(
          id: 'paid',
          label: t('dawam.paid'),
          hideable: false,
          text: (r) => r.paidMethod != null
              ? t('dawam.pay_${r.paidMethod}', defaultValue: r.paidMethod)
              : s.phase == PayPhase.open
              ? t('dawam.estimate')
              : '—',
          cell: (context, r) {
            if (r.paidMethod != null) {
              return Align(
                alignment: AlignmentDirectional.centerStart,
                child: DashStatusPill(
                  tone: DashTone.success,
                  small: true,
                  label: t(
                    'dawam.pay_${r.paidMethod}',
                    defaultValue: r.paidMethod,
                  ),
                ),
              );
            }
            if (s.phase == PayPhase.approved && canRun) {
              return Align(
                alignment: AlignmentDirectional.centerStart,
                child: DashButton(
                  label: t('dawam.markPaid'),
                  variant: DashButtonVariant.outline,
                  size: DashButtonSize.compact,
                  onPressed: () => onMarkPaid(r),
                ),
              );
            }
            return Text(
              s.phase == PayPhase.open ? t('dawam.estimate') : '—',
              style: DashType.small.copyWith(color: c.textSecondary),
            );
          },
        ),
      ],
    );
  }
}
