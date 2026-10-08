/// The rules-first banner (`dawam/rules-banner.tsx`, TEAM-ALL-016), mounted
/// on Team, Schedule and Payroll. Until the business saves its rules the API
/// refuses every punch (`RULES_NOT_SET`), so the page says so and sends the
/// owner to the one page that fixes it: the set-up checklist when more than
/// the rules is known missing (fewer than 3 steps done), else the rules.
///
/// Shown only on an answer that says "never saved": nothing while loading,
/// nothing on an error.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'setup_data.dart';

class RulesFirstBanner extends ConsumerWidget {
  const RulesFirstBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(teamSetupDataProvider);
    final settings = data.settings;
    if (settings == null || settings.rulesSavedAt != null) {
      return const SizedBox.shrink();
    }
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final p = data.progress;
    final more = p.ready && p.count < 3;
    const tone = DashTone.warning;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.xs,
      children: [
        Text(
          t('dawam.rulesFirstTitle'),
          style: DashType.bodyStrong.copyWith(color: c.textPrimary),
        ),
        Text(
          t('dawam.rulesFirstHint'),
          style: DashType.body.copyWith(color: c.textSecondary),
        ),
      ],
    );
    final action = DashButton(
      label: more ? t('dawam.setupFinish') : t('dawam.rulesFirstAction'),
      onPressed: () => context.go(more ? '/staff/setup' : '/staff/rules'),
    );
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(
          color: tone.wash(c),
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: tone.solid(c).withValues(alpha: 0.4)),
        ),
        // The web's `flex flex-wrap` with a `flex-1 min-w-0` text: the text
        // takes what the glyph and the button leave, on one line.
        child: Row(
          spacing: Space.md,
          children: [
            DashIcon('scale', size: IconSize.lg, color: tone.solid(c)),
            Expanded(child: text),
            action,
          ],
        ),
      ),
    );
  }
}
