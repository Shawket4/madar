import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge_staff/rust_bridge_staff.dart';

import '../../app/providers.dart';
import '../../format.dart';
import '../../ui/kit.dart';
import 'adjustments_screen.dart';

/// The payroll run — the whole month, on one screen, before anything is paid.
///
/// The table is the SERVER's preview: the same computation that generating
/// performs, run read-only. That matters more than it sounds. A preview built
/// from a separate query would be a second implementation of payroll, and the
/// first month the two disagreed would be the month somebody was underpaid.
/// Approving turns the preview into frozen payslips; nothing before that
/// writes a figure.
class PayrollScreen extends ConsumerStatefulWidget {
  const PayrollScreen({super.key});

  @override
  ConsumerState<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends ConsumerState<PayrollScreen> {
  /// Index into the period list — 0 is the newest.
  int _index = 0;
  bool _busy = false;
  bool _showAllRows = false;

  static const _visibleRows = 6;

  Future<void> _approve(PayrollPeriodView period) async {
    final t = ref.read(tProvider);
    final core = ref.read(coreProvider);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await core.bridge.managerPayrollGenerate(periodId: period.id);
      ref
        ..invalidate(payrollPeriodsProvider)
        ..invalidate(payrollPreviewProvider(period.id));
      messenger.showSnackBar(
        SnackBar(content: Text(t('pr.approved', {'period': period.name}))),
      );
    } on MadarError catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(core.bridge.humanMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markPaid(PayrollPeriodView period) async {
    final core = ref.read(coreProvider);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await core.bridge.managerPayrollSetStatus(
        periodId: period.id,
        status: 'paid',
      );
      ref.invalidate(payrollPeriodsProvider);
    } on MadarError catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(core.bridge.humanMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final periods = ref.watch(payrollPeriodsProvider);
    final currency = ref.watch(sessionProvider)?.currencyCode ?? '';

    return periods.when(
      loading: () => StaffPage(
        title: t('pr.title'),
        children: const [SkeletonList(count: 5)],
      ),
      error: (e, _) => StaffPage(
        title: t('pr.title'),
        children: [
          ErrorState(
            message: '$e',
            retryLabel: t('common.retry'),
            onRetry: () => ref.invalidate(payrollPeriodsProvider),
          ),
        ],
      ),
      data: (list) {
        if (list.isEmpty) {
          return StaffPage(
            title: t('pr.title'),
            children: [
              EmptyState(
                icon: 'creditcard',
                title: t('pr.noPeriods'),
                message: t('pr.noPeriodsHint'),
              ),
            ],
          );
        }
        final index = _index.clamp(0, list.length - 1);
        final period = list[index];
        final preview = ref.watch(payrollPreviewProvider(period.id));
        final generated = period.status != 'draft';

        return StaffPage(
          title: t('pr.title'),
          // The adjustments that FEED this run sit one tap away, because the
          // moment you question a figure in the table is the moment you want
          // to waive the deduction behind it.
          titleTrailing: TactileScale(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AdjustmentsScreen(),
              ),
            ),
            child: IconTile(
              icon: 'plus.forwardslash.minus',
              size: 40,
              background: context.madarColors.accentBg,
              tint: context.madarColors.accent,
            ),
          ),
          onRefresh: () async {
            ref
              ..invalidate(payrollPeriodsProvider)
              ..invalidate(payrollPreviewProvider(period.id));
          },
          floating: _Actions(
            period: period,
            busy: _busy,
            onApprove: () => _approve(period),
            onMarkPaid: () => _markPaid(period),
          ),
          children: [
            _PeriodStepper(
              period: period,
              // Newer periods are at lower indices, so "back" means +1.
              onOlder: index < list.length - 1
                  ? () => setState(() => _index = index + 1)
                  : null,
              onNewer: index > 0
                  ? () => setState(() => _index = index - 1)
                  : null,
            ),
            const SizedBox(height: Space.sm + 2),
            if (generated) ...[
              NoticeBanner(
                tone: ChipTone.success,
                icon: 'checkmark.circle',
                text: t('pr.approved', {'period': period.name}),
              ),
              const SizedBox(height: Space.sm + 2),
            ],
            preview.when(
              loading: () => const SkeletonList(count: 4),
              error: (e, _) => ErrorState(
                message: '$e',
                retryLabel: t('common.retry'),
                onRetry: () =>
                    ref.invalidate(payrollPreviewProvider(period.id)),
              ),
              data: (lines) {
                final total = lines.fold<int>(0, (s, l) => s + l.netMinor);
                final exceptions = lines
                    .where((l) => l.exception.isNotEmpty)
                    .length;
                final shown = _showAllRows
                    ? lines.length
                    : lines.length.clamp(0, _visibleRows);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: StatCard(
                            label: t('pr.employees'),
                            value: '${lines.length}',
                          ),
                        ),
                        const SizedBox(width: Space.sm),
                        Expanded(
                          child: StatCard(
                            label: t('pr.totalNet'),
                            value: formatAmount(total),
                            valueStyle: MadarType.numMd,
                          ),
                        ),
                        const SizedBox(width: Space.sm),
                        Expanded(
                          child: StatCard(
                            label: t('pr.exceptions'),
                            value: '$exceptions',
                            valueColor: exceptions > 0
                                ? context.madarColors.warning
                                : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Space.md),
                    MadarCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          _TableHeader(currency: currency),
                          for (var i = 0; i < shown; i++)
                            _LineRow(line: lines[i], last: i == shown - 1),
                          if (!_showAllRows && lines.length > _visibleRows)
                            TactileScale(
                              onTap: () => setState(() => _showAllRows = true),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: Space.md,
                                ),
                                child: Text(
                                  t('pr.moreRows', {
                                    'count': '${lines.length - _visibleRows}',
                                  }),
                                  textAlign: TextAlign.center,
                                  style: MadarType.labelSm.copyWith(
                                    color: context.madarColors.accent,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _PeriodStepper extends ConsumerWidget {
  const _PeriodStepper({
    required this.period,
    required this.onOlder,
    required this.onNewer,
  });

  final PayrollPeriodView period;
  final VoidCallback? onOlder;
  final VoidCallback? onNewer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    return MadarCard(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm + 2,
        vertical: Space.sm,
      ),
      radius: Radii.sm + 2,
      child: Row(
        children: [
          _StepButton(icon: 'chevron.backward', onTap: onOlder),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  period.name,
                  style: MadarType.body.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Num(
                  '${period.startDate} – ${period.endDate}',
                  style: MadarType.num.copyWith(fontSize: 11),
                  color: colors.textMuted,
                ),
              ],
            ),
          ),
          _StepButton(icon: 'chevron.forward', onTap: onNewer),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final String icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Opacity(
      // Disabled rather than hidden: the control keeps its place, so the
      // period label does not jump as you step through months.
      opacity: onTap == null ? Opacities.disabled : 1,
      child: TactileScale(
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(Radii.xs + 2),
          ),
          alignment: Alignment.center,
          child: MadarIcon(icon, tint: colors.textSecondary),
        ),
      ),
    );
  }
}

class _TableHeader extends ConsumerWidget {
  const _TableHeader({required this.currency});

  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final colors = context.madarColors;
    return Container(
      height: 42,
      color: colors.surfaceAlt,
      padding: const EdgeInsets.symmetric(horizontal: Space.md),
      child: Row(
        children: [
          Expanded(child: FieldLabel(t('pr.employee'))),
          SizedBox(width: 52, child: Center(child: FieldLabel(t('pr.days')))),
          SizedBox(width: 44, child: Center(child: FieldLabel(t('pr.ot')))),
          SizedBox(
            width: 78,
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FieldLabel('${t('pr.netCol')} $currency'),
            ),
          ),
        ],
      ),
    );
  }
}

class _LineRow extends ConsumerWidget {
  const _LineRow({required this.line, required this.last});

  final PayrollLineView line;
  final bool last;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final colors = context.madarColors;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm,
      ),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: colors.borderLight)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  line.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MadarType.bodySm.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (line.exception.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  StatusChip(
                    label: t(
                      line.exception == 'absence'
                          ? 'pr.exAbsence'
                          : 'pr.exMissingPunch',
                    ),
                    tone: ChipTone.warning,
                  ),
                ],
              ],
            ),
          ),
          SizedBox(
            width: 52,
            child: Center(child: Num(formatDays(line.workedCentidays))),
          ),
          SizedBox(
            width: 44,
            child: Center(
              child: Num(
                line.overtimeMinutes == 0
                    ? '—'
                    : formatHm(line.overtimeMinutes),
                color: line.overtimeMinutes > 0 ? colors.accent : null,
              ),
            ),
          ),
          SizedBox(
            width: 78,
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Num(
                formatAmount(line.netMinor),
                style: MadarType.num.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The run's one primary action, which changes with the period's state.
class _Actions extends ConsumerWidget {
  const _Actions({
    required this.period,
    required this.busy,
    required this.onApprove,
    required this.onMarkPaid,
  });

  final PayrollPeriodView period;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onMarkPaid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return switch (period.status) {
      'draft' => PrimaryButton(
        label: busy ? t('pr.approving') : t('pr.approve'),
        icon: 'checkmark',
        busy: busy,
        onPressed: busy ? null : onApprove,
      ),
      'generated' => Row(
        children: [
          Expanded(
            child: SecondaryButton(
              label: t('pr.approve'),
              onPressed: busy ? null : onApprove,
            ),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: PrimaryButton(
              label: t('pr.markPaid'),
              icon: 'banknote',
              busy: busy,
              onPressed: busy ? null : onMarkPaid,
            ),
          ),
        ],
      ),
      // Paid or closed: the figures are what was paid, so there is nothing
      // left to do here but read them.
      _ => Center(
        child: StatusChip(label: t('pr.paid'), tone: ChipTone.success),
      ),
    };
  }
}
