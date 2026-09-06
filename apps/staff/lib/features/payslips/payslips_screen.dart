import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge_staff/rust_bridge_staff.dart';

import '../../app/providers.dart';
import '../../format.dart';
import '../../ui/kit.dart';

/// What was paid, and why.
///
/// The list is a stack of months; tapping one opens the breakdown. Both put NET
/// on ink — it is the number the employee opened the app for, and a payslip
/// that buries it under a table of components is answering a question nobody
/// asked first.
class PayslipsScreen extends ConsumerStatefulWidget {
  const PayslipsScreen({super.key});

  @override
  ConsumerState<PayslipsScreen> createState() => _PayslipsScreenState();
}

class _PayslipsScreenState extends ConsumerState<PayslipsScreen> {
  PayslipView? _open;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final slips = ref.watch(payslipsProvider);
    final currency = ref.watch(sessionProvider)?.currencyCode ?? '';

    if (_open case final slip?) {
      return _Detail(
        slip: slip,
        currency: currency,
        onBack: () => setState(() => _open = null),
      );
    }

    return StaffPage(
      title: t('pay.title'),
      onRefresh: () async => ref.invalidate(payslipsProvider),
      children: [
        slips.when(
          loading: () => const SkeletonList(count: 4),
          error: (e, _) => ErrorState(
            message: '$e',
            retryLabel: t('common.retry'),
            onRetry: () => ref.invalidate(payslipsProvider),
          ),
          data: (rows) => rows.isEmpty
              ? EmptyState(
                  icon: 'receipt',
                  title: t('pay.empty'),
                  message: t('pay.emptyHint'),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Hero(slip: rows.first, currency: currency),
                    const SizedBox(height: Space.md),
                    for (var i = 0; i < rows.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Space.sm),
                        child: _SlipRow(
                          slip: rows[i],
                          currency: currency,
                          current: i == 0,
                          onTap: () => setState(() => _open = rows[i]),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Net pay on ink — the screen's headline.
class _Hero extends ConsumerWidget {
  const _Hero({
    required this.slip,
    required this.currency,
    this.compact = false,
  });

  final PayslipView slip;
  final String currency;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final colors = context.madarColors;
    // On ink the accent has to be the BRIGHT teal — the light-theme accent is
    // unreadable on a dark surface.
    final accentOnInk = MadarColors.dark.navy;

    return MadarCard(
      color: colors.textPrimary,
      radius: Radii.lg,
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            compact ? slip.periodName : t('pay.net'),
            style: MadarType.labelSm.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: Space.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Num(
                formatAmount(slip.netMinor),
                style: compact ? MadarType.numXl : MadarType.numXl,
                color: colors.bg,
              ),
              const SizedBox(width: Space.sm),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  currency,
                  style: MadarType.title.copyWith(color: accentOnInk),
                ),
              ),
            ],
          ),
          if (!compact && slip.generatedAt.isNotEmpty) ...[
            const SizedBox(height: Space.xs),
            Text(
              t('pay.deposited', {'date': formatDay(slip.generatedAt)}),
              style: MadarType.labelSm.copyWith(color: colors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _SlipRow extends ConsumerWidget {
  const _SlipRow({
    required this.slip,
    required this.currency,
    required this.current,
    required this.onTap,
  });

  final PayslipView slip;
  final String currency;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final colors = context.madarColors;

    return MadarCard(
      onTap: onTap,
      color: current ? colors.accentBg : null,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm + 2,
      ),
      child: Row(
        children: [
          IconTile(
            icon: 'doc.text',
            background: current ? colors.accent : colors.surfaceAlt,
            tint: current ? colors.textOnAccent : colors.textSecondary,
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  slip.periodName,
                  style: MadarType.body.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  t('pay.hoursDays', {
                    'hours': formatHm(
                      // Worked days × the average day is the only hour figure a
                      // frozen payslip carries; overtime is shown separately.
                      (slip.workedCentidays * 480 / 100).round(),
                    ),
                    'days': formatDays(slip.workedCentidays),
                  }),
                  style: MadarType.labelSm.copyWith(color: colors.textMuted),
                ),
              ],
            ),
          ),
          Num(
            formatAmount(slip.netMinor),
            style: MadarType.num.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: Space.sm),
          MadarIcon('chevron.forward', tint: colors.textMuted),
        ],
      ),
    );
  }
}

/// The breakdown: earnings, deductions, net.
class _Detail extends ConsumerWidget {
  const _Detail({
    required this.slip,
    required this.currency,
    required this.onBack,
  });

  final PayslipView slip;
  final String currency;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final colors = context.madarColors;
    final gross = slip.baseMinor + slip.overtimeMinor + slip.bonusesMinor;

    return StaffPage(
      title: t('pay.slipOf', {'period': slip.periodName}),
      titleTrailing: TactileScale(
        onTap: onBack,
        child: const IconTile(icon: 'chevron.backward', size: 34),
      ),
      children: [
        _Hero(slip: slip, currency: currency, compact: true),
        const SizedBox(height: Space.md),
        MadarCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _SectionHeader(label: t('pay.earnings'), currency: currency),
              _Line(label: t('pay.base'), amount: slip.baseMinor),
              if (slip.overtimeMinor != 0)
                _Line(
                  label: t('pay.overtime'),
                  hint: formatHm(slip.overtimeMinutes, signed: true),
                  amount: slip.overtimeMinor,
                ),
              if (slip.bonusesMinor != 0)
                _Line(label: t('pay.bonuses'), amount: slip.bonusesMinor),
              _Line(label: t('pay.gross'), amount: gross, emphasised: true),
              if (slip.deductionsMinor != 0 ||
                  slip.advanceInstallmentMinor != 0) ...[
                _SectionHeader(label: t('pay.deductions'), currency: currency),
                if (slip.deductionsMinor != 0)
                  _Line(
                    label: t('pay.deductions'),
                    amount: -slip.deductionsMinor,
                    negative: true,
                  ),
                if (slip.advanceInstallmentMinor != 0)
                  _Line(
                    label: t('pay.advance'),
                    amount: -slip.advanceInstallmentMinor,
                    negative: true,
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Space.md),
        // Net repeated on ink at the foot of the table — the figure that is
        // actually in the bank, after everything above it.
        MadarCard(
          color: colors.textPrimary,
          padding: const EdgeInsets.symmetric(
            horizontal: Space.lg,
            vertical: Space.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  t('pay.net'),
                  style: MadarType.title.copyWith(
                    color: colors.bg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Num(
                formatAmount(slip.netMinor),
                style: MadarType.numMd,
                color: MadarColors.dark.navy,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.currency});

  final String label;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Container(
      color: colors.surfaceAlt,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm,
      ),
      child: Row(
        children: [
          Expanded(child: FieldLabel(label, color: colors.textSecondary)),
          Text(
            currency,
            style: MadarType.labelSm.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.label,
    required this.amount,
    this.hint,
    this.negative = false,
    this.emphasised = false,
  });

  final String label;
  final int amount;
  final String? hint;
  final bool negative;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Container(
      color: emphasised ? colors.bg : null,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm + 2,
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Text(
                  label,
                  style: MadarType.bodySm.copyWith(
                    color: colors.textPrimary,
                    fontWeight: emphasised ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                if (hint != null) ...[
                  const SizedBox(width: Space.xs + 2),
                  Num(
                    hint!,
                    style: MadarType.num.copyWith(fontSize: 11),
                    color: colors.textMuted,
                  ),
                ],
              ],
            ),
          ),
          Num(
            formatAmount(amount),
            style: MadarType.num.copyWith(
              fontWeight: emphasised ? FontWeight.w700 : FontWeight.w600,
            ),
            color: negative ? colors.danger : colors.textPrimary,
          ),
        ],
      ),
    );
  }
}
