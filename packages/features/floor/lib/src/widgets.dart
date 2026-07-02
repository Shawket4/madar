import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Button height for the floor screen's compact actions (Seat / status
/// picks) — the natives' M3 button height (40.dp).
const double _buttonHeight = 40;

/// Visual weight of a [FloorButton].
enum FloorButtonVariant {
  /// Accent fill — the terminal pick.
  primary,

  /// Hairline outline on the surface — secondary actions.
  outline,
}

/// Compact design-system button standing in for the natives' M3
/// Button/OutlinedButton on the floor screen (matching the other feature
/// ports, which replace M3 widgets with the shared kit).
class FloorButton extends StatelessWidget {
  /// Creates a floor action button.
  const FloorButton({
    required this.label,
    required this.onTap,
    this.variant = FloorButtonVariant.primary,
    this.enabled = true,
    this.loading = false,
    this.icon,
    super.key,
  });

  /// Localized label.
  final String label;

  /// Tap handler — ignored while disabled/loading.
  final VoidCallback onTap;

  /// Visual weight.
  final FloorButtonVariant variant;

  /// Grays out + mutes taps when false.
  final bool enabled;

  /// Swaps the content for a spinner + mutes taps.
  final bool loading;

  /// Optional leading [MadarIcon] name.
  final String? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final primary = variant == FloorButtonVariant.primary;
    final active = enabled && !loading;
    final fg = primary ? colors.textOnAccent : colors.textPrimary;
    final content = loading
        ? SizedBox.square(
            dimension: IconSize.lg,
            child: CircularProgressIndicator(color: fg, strokeWidth: 2),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                MadarIcon(icon, tint: fg),
                const SizedBox(width: Space.sm),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MadarType.title.copyWith(
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ),
            ],
          );
    return Opacity(
      opacity: active ? 1 : Opacities.disabled,
      child: TactileScale(
        onTap: active
            ? () {
                MadarHaptics.selection();
                onTap();
              }
            : null,
        child: Container(
          height: _buttonHeight,
          alignment: Alignment.center,
          padding: const EdgeInsetsDirectional.symmetric(horizontal: Space.lg),
          decoration: BoxDecoration(
            color: primary ? colors.accent : colors.surface,
            borderRadius: BorderRadius.circular(Radii.sm),
            border: primary ? null : Border.all(color: colors.border),
          ),
          child: content,
        ),
      ),
    );
  }
}
