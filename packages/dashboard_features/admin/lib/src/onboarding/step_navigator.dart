/// The wizard's step list (ADM-ONB-009; web `step-navigator.tsx`), shown from
/// 1024 wide: the stages as headings, each step as a button — a check when
/// done, a lock while "Open your café" is not yet allowed, else its glyph —
/// with "Optional" on the non-required steps and "N added" on a step that has
/// some but is not done.
library;

import 'package:dashboard_api/dashboard_api.dart' show OnboardingStep;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'onboarding_config.dart';

class OnbStepNavigator extends ConsumerWidget {
  const OnbStepNavigator({
    required this.byKey,
    required this.active,
    required this.canComplete,
    required this.onSelect,
    super.key,
  });

  final Map<String, OnboardingStep> byKey;
  final OnbStep active;
  final bool canComplete;
  final ValueChanged<OnbStep> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    return Semantics(
      label: t('onboarding.navLabel'),
      container: true,
      explicitChildNodes: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.xl,
        children: [
          for (final stage in OnbStage.values)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: Space.xs,
                    end: Space.xs,
                    bottom: Space.sm,
                  ),
                  child: Text(
                    t(stage.labelKey).toUpperCase(),
                    style: DashType.tableHeader.copyWith(
                      color: c.textSecondary,
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: Space.xs,
                  children: [
                    for (final step in stage.steps)
                      _StepButton(
                        step: step,
                        status: step.statusKey == null
                            ? null
                            : byKey[step.statusKey],
                        active: step == active,
                        locked: step == OnbStep.goLive && !canComplete,
                        onTap: () => onSelect(step),
                      ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _StepButton extends ConsumerWidget {
  const _StepButton({
    required this.step,
    required this.status,
    required this.active,
    required this.locked,
    required this.onTap,
  });

  final OnbStep step;
  final OnboardingStep? status;
  final bool active;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final finale = step == OnbStep.goLive;
    final done = !finale && (status?.done ?? false);
    final required = !finale && (status?.required_ ?? false);
    final count = status?.count ?? 0;
    final title = t(step.titleKey);
    final optional = !required && !finale;
    final added = count > 0 && !done
        ? t('onboarding.countAdded', args: {'count': count}, count: count)
        : null;

    final Color discBg;
    final Color discFg;
    if (done) {
      discBg = c.success.withValues(alpha: 0.15);
      discFg = DashTone.success.foreground(c);
    } else if (active) {
      discBg = c.brand.withValues(alpha: 0.1);
      discFg = c.brand;
    } else {
      discBg = c.muted;
      discFg = c.textSecondary;
    }

    return Opacity(
      opacity: locked ? Opacities.disabled + 0.1 : 1,
      child: DashPressable(
        onTap: locked ? null : onTap,
        enabled: !locked,
        selected: active,
        semanticLabel: [
          title,
          if (optional) t('onboarding.optional'),
          ?added,
        ].join(', '),
        excludeChildSemantics: true,
        pressScale: false,
        builder: (context, s) => Container(
          constraints: const BoxConstraints(minHeight: DashMetrics.target),
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: Space.sm + DashMetrics.hair,
            vertical: Space.sm,
          ),
          foregroundDecoration: dashFocusRing(
            context,
            s,
            BorderRadius.circular(Radii.md),
          ),
          decoration: BoxDecoration(
            color: active
                ? c.muted
                : (s.highlighted ? c.muted.withValues(alpha: 0.6) : null),
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Row(
            spacing: Space.md,
            children: [
              Container(
                width: Space.xl + Space.xs,
                height: Space.xl + Space.xs,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: discBg,
                  shape: BoxShape.circle,
                  border: active && !done
                      ? Border.all(color: c.brand, width: 1.5)
                      : null,
                ),
                child: DashIcon(
                  done
                      ? 'check'
                      : locked
                      ? 'lock'
                      : step.icon,
                  size: done ? IconSize.sm : IconSize.xs,
                  color: discFg,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      spacing: Space.sm,
                      children: [
                        Flexible(
                          child: MadarClippedText(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                (active || done
                                        ? DashType.bodyMedium
                                        : DashType.body)
                                    .copyWith(
                                      color: active || done
                                          ? c.textPrimary
                                          : c.textSecondary,
                                    ),
                          ),
                        ),
                        if (optional)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: Space.xs,
                              vertical: DashMetrics.hair,
                            ),
                            decoration: BoxDecoration(
                              color: c.muted,
                              borderRadius: BorderRadius.circular(
                                DashMetrics.hair * 2,
                              ),
                            ),
                            child: Text(
                              t('onboarding.optional'),
                              style: DashType.tableHeader.copyWith(
                                color: c.textSecondary,
                                letterSpacing: 0,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (added != null)
                      Text(
                        added,
                        style: DashType.small.copyWith(color: c.textSecondary),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
