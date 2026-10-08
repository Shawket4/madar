/// The floating "N unsaved changes · Discard · Save" pill the menu studio
/// (`menu.studio.*`, MENU-STUDIO-010) and the pricing matrix
/// (`menu.pricing.*`, MENU-PRC-024) show at the bottom centre while
/// something is dirty.
library;

import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Floats [bar] at the bottom centre over [child] (above the safe area), and
/// keeps a spacer under the content so the last row stays reachable. Shows
/// nothing extra while [bar] is null.
class MenuUnsavedBarHost extends StatelessWidget {
  const MenuUnsavedBarHost({required this.child, this.bar, super.key});

  final Widget child;

  /// The pill (a [MenuUnsavedBar]) while something is dirty, else null.
  final Widget? bar;

  @override
  Widget build(BuildContext context) {
    final b = bar;
    if (b == null) return child;
    return Stack(
      children: [
        Positioned.fill(child: child),
        PositionedDirectional(
          start: Space.md,
          end: Space.md,
          bottom: Space.lg,
          child: SafeArea(top: false, child: Center(child: b)),
        ),
      ],
    );
  }
}

/// The pill: the count sentence, a ghost Discard, a primary Save (a spinner
/// while [saving]; both disabled while saving).
class MenuUnsavedBar extends StatelessWidget {
  const MenuUnsavedBar({
    required this.countText,
    required this.discardLabel,
    required this.saveLabel,
    required this.onDiscard,
    required this.onSave,
    this.saving = false,
    super.key,
  });

  /// `t('menu.studio.unsavedN', count: n)` / `t('menu.pricing.unsavedN', …)`.
  final String countText;
  final String discardLabel;
  final String saveLabel;
  final VoidCallback onDiscard;
  final VoidCallback onSave;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: Space.md,
        vertical: Space.xs,
      ),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: c.hairline),
        boxShadow: DashShadows.popover(context),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: Space.xs),
              child: MadarClippedText(
                countText,
                style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: Space.sm),
          DashButton(
            label: discardLabel,
            variant: DashButtonVariant.ghost,
            size: DashButtonSize.compact,
            onPressed: saving ? null : onDiscard,
          ),
          const SizedBox(width: Space.xs),
          DashButton(
            label: saveLabel,
            size: DashButtonSize.compact,
            loading: saving,
            onPressed: saving ? null : onSave,
          ),
        ],
      ),
    );
  }
}
