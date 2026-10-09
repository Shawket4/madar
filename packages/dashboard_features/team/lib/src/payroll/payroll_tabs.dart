/// The Payroll page's other tabs (`dawam/payroll-page.tsx`): Bonuses &
/// deductions (TEAM-PAY-040 … -044), Salary advances (-050/-051), Expense
/// advances (-055/-056) and History with its month sheet (-060/-061).
library;

import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/staff_query.dart';
import '../shared/team_format.dart';
import '../shared/team_util.dart';
import 'money_dialogs.dart';
import 'money_errors.dart';
import 'payroll_data.dart';
import 'payroll_logic.dart';
import 'payroll_page.dart' show PayrollMetrics, PayrollRefreshListener;

/// A tab's list in its four states: error with Retry, skeleton, the web's
/// empty state, the rows.
Widget _states<T>(
  WidgetRef ref,
  AsyncValue<List<T>> q, {
  required String errorKey,
  required VoidCallback onRetry,
  required Widget empty,
  required Widget Function(List<T> rows) rows,
}) {
  final t = ref.watch(tProvider);
  if (q.failedFirst) {
    return DashErrorState(
      title: t(errorKey),
      message: dawamErrorMessage(q.error, t, ref.watch(formatProvider)),
      retryLabel: t('common.retry'),
      retrying: q.isLoading,
      onRetry: onRetry,
    );
  }
  if (q.awaitingFirst) {
    return const DashSkeleton(
      height: PayrollMetrics.tabSkeleton,
      radius: Radii.card,
    );
  }
  final list = q.value ?? const [];
  return list.isEmpty ? empty : rows(list);
}

/// A list row whose title carries badges and whose end holds figures and
/// buttons (the web's `ListRow` with a rich title); wraps on a phone.
class _RichRow extends StatelessWidget {
  const _RichRow({
    required this.title,
    required this.trailing,
    this.badges = const [],
    this.meta,
    super.key,
  });

  final String title;
  final List<Widget> badges;
  final String? meta;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.md,
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
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    title,
                    style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                  ),
                  ...badges,
                ],
              ),
              if (meta != null && meta!.isNotEmpty)
                Text(
                  meta!,
                  style: DashType.small.copyWith(color: c.textSecondary),
                ),
            ],
          ),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: trailing,
          ),
        ],
      ),
    );
  }
}

Widget _figure(BuildContext context, String text) => Text(
  text,
  style: DashType.mono.copyWith(color: context.madarColors.textPrimary),
);

// ── Bonuses & deductions ────────────────────────────────────────────────

class PayLinesTab extends ConsumerStatefulWidget {
  const PayLinesTab({super.key});

  @override
  ConsumerState<PayLinesTab> createState() => _PayLinesTabState();
}

class _PayLinesTabState extends ConsumerState<PayLinesTab> {
  /// TEAM-PAY-043: approve in one tap.
  Future<void> _approve(Adjustment a) async {
    final t = ref.read(tProvider);
    final f = ref.read(formatProvider);
    final staff = ref.read(staffRevisionsProvider.notifier);
    try {
      await ref
          .read(apiProvider)
          .staff
          .decideAdjustment(
            kind: a.kind,
            id: a.id,
            body: const DecidePay(approve: true),
          );
    } on Object catch (e) {
      if (mounted) DashToast.error(context, dawamErrorMessage(e, t, f));
      return;
    }
    staff.invalidateStaff();
    if (mounted) DashToast.success(context, t('staff.decisionSaved'));
  }

  void _reject(Adjustment a) {
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider).staff;
    showRejectDialog(
      context,
      title: t('dawam.rejectLineTitle', args: {'name': a.employeeName}),
      description: t('dawam.rejectWhyHint'),
      onReject: (reason) => api.decideAdjustment(
        kind: a.kind,
        id: a.id,
        body: DecidePay(approve: false, reason: reason),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final authz = ref.watch(authzProvider);
    final canAdjust = authz.canAny(const [
      Cap.hrAdjustmentsCreate,
      Cap.hrDeductionsCreate,
    ]);
    final owner = authz.can(Cap.hrPayrollRun);
    final today = teamTodayIsoOf(ref);
    final q = ref.watch(payrollAdjustmentsProvider);
    return PayrollRefreshListener<List<Adjustment>>(
      read: payrollAdjustmentsProvider,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          if (canAdjust)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: DashButton(
                label: t('dawam.addPayLine'),
                icon: 'plus',
                onPressed: () => showAdjustmentDialog(context),
              ),
            ),
          _states<Adjustment>(
            ref,
            q,
            errorKey: 'dawam.payLinesLoadError',
            onRetry: () => ref.invalidate(payrollAdjustmentsProvider),
            empty: DashEmptyState(
              icon: 'receipt-text',
              title: t('dawam.noPayLines'),
              description: t('dawam.noPayLinesHint'),
            ),
            rows: (rows) => DashListCard(
              children: [
                for (final a in rows)
                  _lineRow(context, t, f, a, today, owner, canAdjust),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _lineRow(
    BuildContext context,
    Translator t,
    DashFormat f,
    Adjustment a,
    String today,
    bool owner,
    bool canAdjust,
  ) {
    // Stop ends a monthly line after the open month, which keeps it.
    final endsOn = a.endsOn;
    final stopped = endsOn != null && endsOn.compareTo(today) < 0;
    final value = a.percentOfBase != null
        ? '${fmtPercentOf(a.percentOfBase!)}%'
        : f.fmtMoney(
            a.kind == 'bonus'
                ? (a.amountPiastres ?? 0)
                : -(a.amountPiastres ?? 0),
          );
    final rule = ruleSourceKeys[a.source];
    return _RichRow(
      key: ValueKey('payline-${a.kind}-${a.id}'),
      title: a.employeeName,
      badges: [
        DashBadge(a.kind == 'bonus' ? t('dawam.bonus') : t('dawam.deduction')),
        if (rule != null) DashBadge(t(rule)),
        if (a.recurring)
          DashBadge(
            stopped
                ? t('dawam.stopped')
                : endsOn != null
                ? t('dawam.monthlyUntil', args: {'date': f.fmtDate(endsOn)})
                : t('dawam.monthly'),
          ),
      ],
      meta: [
        reasonText(t, a.reasonCode, a.reasonVars, a.reason),
        f.fmtDate(a.effectiveDate),
        if (a.status == 'rejected' && (a.decisionNote ?? '').isNotEmpty)
          t('dawam.rejectedWhy', args: {'reason': a.decisionNote}),
      ].where((s) => s.isNotEmpty).join(' · '),
      trailing: [
        _figure(context, value),
        DashStatusPill(
          tone: adjustmentTone(a.status),
          small: true,
          label: t('dawam.adj_${a.status}', defaultValue: a.status),
        ),
        if (owner && a.status == 'pending') ...[
          DashButton(
            label: t('common.approve'),
            variant: DashButtonVariant.outline,
            size: DashButtonSize.compact,
            onPressed: () => _approve(a),
          ),
          DashIconButton(
            icon: 'x',
            semanticLabel: t('common.reject'),
            onPressed: () => _reject(a),
          ),
        ],
        if (canAdjust && a.recurring && endsOn == null && a.status == 'approved')
          DashButton(
            label: t('dawam.stop'),
            variant: DashButtonVariant.ghost,
            size: DashButtonSize.compact,
            onPressed: () =>
                showStopDialog(context, kind: a.kind, id: a.id, line: a.reason),
          ),
      ],
    );
  }
}

/// `${a.percent_of_base}%`: JavaScript's number text (5 → "5", 2.5 → "2.5").
String fmtPercentOf(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

// ── Salary advances ─────────────────────────────────────────────────────

class AdvancesTab extends ConsumerWidget {
  const AdvancesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final authz = ref.watch(authzProvider);
    final canAdvance = authz.can(Cap.hrAdvancesDecide);
    // The owner may pass the cap and sees its figures (D7).
    final mayPassCap = authz.canEverywhere(Cap.hrPayrollRun);
    final q = ref.watch(payrollAdvancesProvider);
    return PayrollRefreshListener<List<SalaryAdvance>>(
      read: payrollAdvancesProvider,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          if (canAdvance)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: DashButton(
                label: t('dawam.recordAdvance'),
                icon: 'plus',
                onPressed: () => showRecordAdvanceDialog(context),
              ),
            ),
          _states<SalaryAdvance>(
            ref,
            q,
            errorKey: 'dawam.advancesLoadError',
            onRetry: () => ref.invalidate(payrollAdvancesProvider),
            empty: DashEmptyState(
              icon: 'hand-coins',
              title: t('dawam.noAdvances'),
              description: t('dawam.noAdvancesHint'),
            ),
            rows: (rows) => DashListCard(
              children: [
                for (final a in rows)
                  _RichRow(
                    key: ValueKey('advance-${a.id}'),
                    title: a.employeeName ?? '—',
                    meta: [
                      t(
                        'dawam.advanceMeta',
                        count: a.installments,
                        args: {'amount': f.fmtMoney(a.amountPiastres)},
                      ),
                      ?a.reason,
                    ].where((s) => s.isNotEmpty).join(' · '),
                    trailing: [
                      if (a.status == 'pending' || a.status == 'approved')
                        AdvanceCapNote(advance: a, mayPassCap: mayPassCap),
                      if (a.status == 'approved')
                        Text(
                          t(
                            'dawam.remaining',
                            args: {'amount': f.fmtMoney(a.remainingPiastres)},
                          ),
                          style: DashType.mono.copyWith(
                            color: context.madarColors.textSecondary,
                          ),
                        ),
                      DashStatusPill(
                        tone: requestStatusTone[a.status] ?? DashTone.neutral,
                        small: true,
                        label: t('staff.req_${a.status}', defaultValue: a.status),
                      ),
                      if (canAdvance && a.status == 'pending')
                        DashButton(
                          label: t('dawam.review'),
                          variant: DashButtonVariant.outline,
                          size: DashButtonSize.compact,
                          onPressed: () =>
                              showReviewAdvanceDialog(context, advance: a),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Expense advances ────────────────────────────────────────────────────

class ExpensesTab extends ConsumerWidget {
  const ExpensesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final authz = ref.watch(authzProvider);
    final canLog = authz.can(Cap.hrExpenseAdvancesLog);
    // The owner corrects a till tag here: the POS has no correction screen.
    final canCorrectTag = authz.canEverywhere(Cap.hrPayrollRun);
    final branchId = ref.watch(scopeProvider.select((s) => s.branchId));
    final read = payrollExpensesProvider(branchId);
    final q = ref.watch(read);
    return PayrollRefreshListener<List<ExpenseAdvance>>(
      read: read,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          if (canLog)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: DashButton(
                label: t('dawam.logExpense'),
                icon: 'plus',
                // The dialog's branch list.
                onIntent: () => ref.warm(branchesProvider),
                onPressed: () => showExpenseAdvanceDialog(context),
              ),
            ),
          Text(
            t('dawam.expenseNever'),
            style: DashType.small.copyWith(
              color: context.madarColors.textSecondary,
            ),
          ),
          _states<ExpenseAdvance>(
            ref,
            q,
            errorKey: 'dawam.expensesLoadError',
            onRetry: () => ref.invalidate(read),
            empty: DashEmptyState(
              icon: 'wallet',
              title: t('dawam.noExpenses'),
              description: t('dawam.noExpensesHint'),
            ),
            rows: (rows) => DashListCard(
              children: [
                for (final x in rows)
                  _RichRow(
                    key: ValueKey('expense-${x.id}'),
                    title: x.employeeName,
                    meta: [
                      x.purpose,
                      f.fmtDate(x.givenOn),
                      t('dawam.via_${x.via}', defaultValue: x.via),
                      ?x.handedByName,
                    ].where((s) => s.isNotEmpty).join(' · '),
                    trailing: [
                      _figure(context, f.fmtMoney(x.amountPiastres)),
                      if (canCorrectTag && x.via == 'till')
                        DashButton(
                          label: t('dawam.correctTag'),
                          variant: DashButtonVariant.ghost,
                          size: DashButtonSize.compact,
                          onPressed: () =>
                              showCorrectExpenseTagDialog(context, expense: x),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── History ─────────────────────────────────────────────────────────────

class HistoryTab extends ConsumerWidget {
  const HistoryTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final periods =
        ref.watch(payrollShownProvider).current?.history ??
        const <PayrollPeriod>[];
    if (periods.isEmpty) {
      return DashEmptyState(
        icon: 'history',
        title: t('dawam.noHistory'),
        description: t('dawam.noHistoryHint'),
      );
    }
    return DashListCard(
      children: [
        for (final p in periods)
          () {
            final phase = periodPhase(p.status);
            final unsettled = isUnsettledStatus(p.status);
            return DashListRow(
              key: ValueKey('history-${p.id}'),
              variant: DashListRowVariant.nav,
              title: p.name,
              meta:
                  '${f.fmtDate(p.startDate)} → ${f.fmtDate(p.endDate)}'
                  '${unsettled ? ' · ${t('dawam.notFullyPaid')}' : ''}',
              trailing: Wrap(
                spacing: Space.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _figure(context, f.fmtMoney(p.totalNetPiastres)),
                  DashStatusPill(
                    tone: phaseTone(phase),
                    small: true,
                    label: t(phaseKey(phase)),
                  ),
                ],
              ),
              onIntent: () => unsettled
                  ? ref.warm(payrollOlderSlipsProvider(olderKey(p)))
                  : ref.warm(payrollHistorySlipsProvider(p.id)),
              // A month still to settle opens in the page with its actions.
              onTap: () => unsettled
                  ? ref.read(payrollViewProvider.notifier).openMonth(p.id)
                  : showDashSidePanel<void>(
                      context,
                      builder: (_) => HistorySheet(period: p),
                    ),
            );
          }(),
      ],
    );
  }
}

/// A settled month's frozen payslips (TEAM-PAY-061).
class HistorySheet extends ConsumerWidget {
  const HistorySheet({required this.period, super.key});

  final PayrollPeriod period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final read = payrollHistorySlipsProvider(period.id);
    final q = ref.watch(read);
    final people = ref.watch(payrollShownProvider).people;
    final Widget body;
    if (q.failedFirst) {
      body = DashErrorState(
        title: t('dawam.payslipsLoadError'),
        message: dawamErrorMessage(q.error, t, f),
        retryLabel: t('common.retry'),
        retrying: q.isLoading,
        onRetry: () => ref.invalidate(read),
      );
    } else if (q.awaitingFirst) {
      body = const DashSkeleton(height: PayrollMetrics.tabSkeleton);
    } else {
      body = DashListCard(
        children: [
          for (final s in q.value ?? const <Payslip>[])
            DashListRow(
              title:
                  (s.employeeName?.isNotEmpty ?? false
                      ? s.employeeName
                      : people[s.employeeId]?.name) ??
                  '—',
              meta: (s.paidMethod ?? '').isNotEmpty
                  ? t('dawam.pay_${s.paidMethod}', defaultValue: s.paidMethod)
                  : t('dawam.unpaid'),
              value: f.fmtMoney(s.netPiastres),
              numericValue: true,
            ),
        ],
      );
    }
    return PayrollRefreshListener<List<Payslip>>(
      read: read,
      child: DashSurface(
        title: period.name,
        description: periodPhase(period.status) == PayPhase.open
            ? t('dawam.neverApproved')
            : t('dawam.frozenHint'),
        body: body,
      ),
    );
  }
}
