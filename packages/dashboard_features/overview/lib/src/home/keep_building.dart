/// The calm "keep building your café" nudge
/// (`features/onboarding/keep-building-card.tsx`): what is still unset
/// after go-live, a way into the set-up wizard, and a dismiss that lasts the
/// app session.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'home_providers.dart';

class HomeKeepBuildingCard extends ConsumerWidget {
  const HomeKeepBuildingCard({super.key});

  /// Whether the card shows (it reads the checklist only for someone who
  /// may edit the org's settings, until they dismiss it).
  static bool visible(WidgetRef ref) {
    final orgId = ref.watch(orgIdProvider);
    final can = ref.watch(
      authzProvider.select((a) => a.can(Cap.orgSettingsEdit)),
    );
    final dismissed = ref.watch(homeNudgeDismissedProvider);
    if (orgId == null || !can || dismissed) return false;
    final steps = ref.watch(homeOnboardingProvider(orgId)).value?.steps;
    if (steps == null || steps.isEmpty) return false;
    return steps.where((s) => s.done).length < steps.length;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orgId = ref.watch(orgIdProvider);
    if (orgId == null) return const SizedBox.shrink();
    final steps = ref.watch(homeOnboardingProvider(orgId)).value?.steps;
    if (steps == null) return const SizedBox.shrink();
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final done = steps.where((s) => s.done).length;
    return Container(
      decoration: BoxDecoration(
        color: Color.lerp(c.card, c.brand, 0.05),
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: c.brand.withValues(alpha: 0.2)),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: Space.lg,
              top: Space.lg,
              bottom: Space.lg,
              end: Space.xxl + Space.md,
            ),
            child: Row(
              spacing: Space.lg,
              children: [
                Container(
                  width: Space.xxl + Space.sm,
                  height: Space.xxl + Space.sm,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.brand.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                  child: DashIcon(
                    'sparkles',
                    size: IconSize.lg,
                    color: c.brand,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        t(
                          'onboarding.nudge.title',
                          args: {'done': done, 'total': steps.length},
                        ),
                        style: DashType.bodyStrong.copyWith(
                          color: c.textPrimary,
                        ),
                      ),
                      Text(
                        t('onboarding.nudge.body'),
                        style: DashType.small.copyWith(color: c.textSecondary),
                      ),
                    ],
                  ),
                ),
                DashButton(
                  label: t('onboarding.nudge.cta'),
                  size: DashButtonSize.compact,
                  trailingIcon: DashIcon.arrowForward(context),
                  onPressed: () => context.go('/onboarding'),
                ),
              ],
            ),
          ),
          PositionedDirectional(
            top: 0,
            end: 0,
            child: DashIconButton(
              icon: 'x',
              semanticLabel: t('common.dismiss'),
              color: c.textSecondary,
              onPressed: () =>
                  ref.read(homeNudgeDismissedProvider.notifier).dismiss(),
            ),
          ),
        ],
      ),
    );
  }
}
