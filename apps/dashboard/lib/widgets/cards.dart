import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';

import 'motion.dart';

/// A small titled section label with an optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {this.trailing, super.key});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: Space.md),
      child: Row(
        children: [
          Text(title, style: MadarType.h3.copyWith(color: c.textPrimary)),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

/// A KPI stat card: icon chip + label over a large value, with an optional
/// sub-line. `accent: true` paints the whole card teal (the hero metric).
/// Lifts on hover.
class StatCard extends StatelessWidget {
  const StatCard({
    required this.label,
    required this.icon,
    required this.value,
    this.sub,
    this.accent = false,
    super.key,
  });

  final String label;
  final String icon;
  final Widget value;
  final String? sub;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final onCard = accent ? c.textOnAccent : c.textMuted;
    return HoverLift(
      child: Container(
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(
          color: accent ? c.accent : c.surface,
          borderRadius: BorderRadius.circular(Radii.md),
          border: accent ? null : Border.all(color: c.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(Space.xs),
                  decoration: BoxDecoration(
                    color: accent
                        ? c.textOnAccent.withValues(alpha: 0.18)
                        : c.accentBg,
                    borderRadius: BorderRadius.circular(Radii.xs),
                  ),
                  child: MadarIcon(
                    icon,
                    tint: accent ? c.textOnAccent : c.accent,
                    size: IconSize.lg,
                  ),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    label.toUpperCase(),
                    style: MadarType.labelSm.copyWith(
                      color: accent ? onCard.withValues(alpha: 0.9) : onCard,
                      letterSpacing: MadarType.tracking,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.md),
            value,
            if (sub case final sub?) ...[
              const SizedBox(height: Space.xs),
              Text(
                sub,
                style: MadarType.bodySm.copyWith(
                  color: accent ? onCard.withValues(alpha: 0.85) : onCard,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A titled card wrapping a chart (or any content block). Lifts on hover.
class ChartCard extends StatelessWidget {
  const ChartCard({
    required this.title,
    required this.child,
    this.trailing,
    super.key,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return HoverLift(
      child: Container(
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: c.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(title, style: MadarType.h3.copyWith(color: c.textPrimary)),
                const Spacer(),
                ?trailing,
              ],
            ),
            const SizedBox(height: Space.lg),
            child,
          ],
        ),
      ),
    );
  }
}
