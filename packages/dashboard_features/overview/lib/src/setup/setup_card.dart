/// The home page's pointer to Setup (web `setup-card.tsx`): while something
/// stops a sale, how many things and the next one; once nothing does, the
/// first sale to ring up. Gone after the first sale, and back by itself if
/// something breaks the till again. Nothing is dismissed or stored: it
/// follows the server's answer. Shown to whoever may edit the org's settings
/// (a platform admin scoped to a shop too: setting it up for its owner).
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'checks.dart';
import 'setup_page.dart';

class SetupHomeCard extends ConsumerWidget {
  const SetupHomeCard({super.key});

  /// Whether the card shows (readiness is read only for someone who may
  /// edit the org's settings).
  static bool visible(WidgetRef ref) {
    final orgId = ref.watch(orgIdProvider);
    final can = ref.watch(
      authzProvider.select((a) => a.can(Cap.orgSettingsEdit)),
    );
    if (orgId == null || !can) return false;
    final r = ref.watch(readinessProvider(orgId)).value;
    return r != null && showsHomeCard(r);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orgId = ref.watch(orgIdProvider);
    final r = orgId == null ? null : ref.watch(readinessProvider(orgId)).value;
    if (r == null) return const SizedBox.shrink();
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final ready = stageOf(r) == SetupStage.ready;
    final next = nextCheck(r);
    final title = ready
        ? t('setup.card.readyTitle')
        : t('setup.card.title', count: leftToDo(r));
    final body = ready
        ? t('setup.card.readyBody')
        : next == null
        ? ''
        : '${t('setup.card.next', args: {'what': t.checkTitle(next.key)})} '
              '${t.checkLine(next)}';
    final cta = DashButton(
      label: ready ? t('setup.card.readyCta') : t('setup.card.cta'),
      variant: ready ? DashButtonVariant.outline : DashButtonVariant.primary,
      size: DashButtonSize.compact,
      trailingIcon: DashIcon.arrowForward(context),
      to: SetupPage.path,
      onPressed: () => context.go(SetupPage.path),
    );
    return Container(
      key: const ValueKey('setup-card'),
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: Color.lerp(c.card, c.brand, 0.05),
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: c.brand.withValues(alpha: 0.2)),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final words = Row(
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
                  ready ? 'rocket' : 'wrench',
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
                      title,
                      style: DashType.bodyStrong.copyWith(color: c.textPrimary),
                    ),
                    if (body.isNotEmpty)
                      Text(
                        body,
                        style: DashType.small.copyWith(color: c.textSecondary),
                      ),
                  ],
                ),
              ),
            ],
          );
          // The button wraps under the words on a phone.
          if (box.maxWidth < 560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              spacing: Space.md,
              children: [words, cta],
            );
          }
          return Row(
            spacing: Space.lg,
            children: [
              Expanded(child: words),
              cta,
            ],
          );
        },
      ),
    );
  }
}
