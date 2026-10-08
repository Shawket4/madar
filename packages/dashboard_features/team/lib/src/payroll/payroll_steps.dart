/// Where the month's payroll stands, as the three steps it always goes
/// through (estimate → approved → paid), and the one thing to do next
/// (`dawam/payroll-steps.tsx`, TEAM-PAY-004).
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'payroll_logic.dart';

class PayrollSteps extends ConsumerWidget {
  /// The step being worked on (none once everyone is paid).
  static const Key currentStepKey = ValueKey('payroll-step-current');

  const PayrollSteps({
    required this.phase,
    required this.blockers,
    required this.paid,
    required this.people,
    super.key,
  });

  final PayPhase phase;

  /// Things that stop approval (a salary not set).
  final int blockers;
  final int paid;
  final int people;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final at = phase.index;
    final label = {
      PayPhase.open: t('dawamOps.stepEstimate'),
      PayPhase.approved: t('dawamOps.stepApproved'),
      PayPhase.paid: t('dawamOps.stepPaid'),
    };
    final sub = {
      PayPhase.open: t('dawamOps.stepEstimateSub'),
      PayPhase.approved: t('dawamOps.stepApprovedSub'),
      PayPhase.paid: phase == PayPhase.open
          ? t('dawamOps.stepPaidSub')
          : t('dawamOps.paidOf', args: {'paid': paid, 'people': people}),
    };
    final done = Color.lerp(c.success, c.textPrimary, 0.3)!;
    Widget step(PayPhase p) {
      final i = p.index;
      final isDone = i < at || (p == PayPhase.paid && phase == PayPhase.paid);
      final current = i == at && phase != PayPhase.paid;
      final muted = !isDone && !current;
      final disc = Container(
        width: Space.xl,
        height: Space.xl,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDone
              ? done
              : current
              ? c.accent
              : null,
          border: isDone || current ? null : Border.all(color: c.hairline),
        ),
        child: isDone
            ? DashIcon('check', size: IconSize.xs, color: c.bg)
            : Text(
                '${i + 1}',
                style: DashType.smallStrong.copyWith(
                  color: current ? c.textOnAccent : c.textSecondary,
                ),
              ),
      );
      // `aria-current="step"`.
      return Semantics(
        key: current ? currentStepKey : null,
        container: true,
        selected: current,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.sm,
          children: [
            ExcludeSemantics(child: disc),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label[p]!,
                    style: DashType.bodyStrong.copyWith(
                      color: muted ? c.textSecondary : c.textPrimary,
                    ),
                  ),
                  Text(
                    sub[p]!,
                    style: DashType.small.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Semantics(
      container: true,
      label: t('dawamOps.payrollSteps'),
      child: DashCard(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: Space.md,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.sm,
              children: [
                for (final p in PayPhase.values) Expanded(child: step(p)),
              ],
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.hairline)),
              ),
              child: Padding(
                padding: const EdgeInsets.only(top: Space.sm),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: t('dawamOps.nextLabel'),
                        style: DashType.bodyMedium,
                      ),
                      const TextSpan(text: ' '),
                      TextSpan(
                        text: t(nextStepKey(phase, blockers, paid, people)),
                      ),
                    ],
                  ),
                  style: DashType.body.copyWith(color: c.textPrimary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
