import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'foundation/press.dart';
import 'foundation/tokens.dart';

/// The web's button variants.
enum DashButtonVariant {
  /// The one primary: ink fill (pale slate in dark).
  primary,

  /// Madar teal — brand surfaces only.
  brand,

  /// A destructive confirm.
  destructive,

  /// A hairline frame on the card face — the everyday secondary.
  outline,

  /// The sunk grey.
  secondary,

  /// No frame; a wash on hover.
  ghost,

  /// Underlined text.
  link,
}

/// Button density: [regular] is 44 tall with 16 side padding; [compact]
/// keeps the 44 target with tighter padding and a 13 label (toolbars,
/// table rows, quick chips).
enum DashButtonSize { regular, compact }

/// THE dashboard button (the web's `Button`): 44 tall, 10 corners, a 14/500
/// label, an optional leading glyph, a spinner while [loading].
class DashButton extends StatelessWidget {
  const DashButton({
    required this.label,
    required this.onPressed,
    this.variant = DashButtonVariant.primary,
    this.size = DashButtonSize.regular,
    this.icon,
    this.trailingIcon,
    this.loading = false,
    this.tooltip,
    this.expand = false,
    this.semanticLabel,
    super.key,
  });

  final String label;

  /// Null disables the button.
  final VoidCallback? onPressed;
  final DashButtonVariant variant;
  final DashButtonSize size;

  /// Leading glyph name (`plus`, `download`).
  final String? icon;
  final String? trailingIcon;
  final bool loading;

  /// Why it is disabled, or the word a glyph stands for.
  final String? tooltip;

  /// Fill the line (a phone's full-width action).
  final bool expand;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return DashPressable(
      onTap: enabled ? onPressed : null,
      enabled: enabled,
      tooltip: tooltip,
      semanticLabel: semanticLabel ?? label,
      excludeChildSemantics: true,
      builder: (context, s) => _DashButtonFace(
        label: label,
        variant: variant,
        size: size,
        icon: icon,
        trailingIcon: trailingIcon,
        loading: loading,
        enabled: enabled,
        expand: expand,
        state: s,
      ),
    );
  }
}

/// A glyph-only square button (the web's `size="icon"`): 44 square, with a
/// REQUIRED [semanticLabel] that is also its tooltip.
class DashIconButton extends StatelessWidget {
  const DashIconButton({
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.variant = DashButtonVariant.ghost,
    this.loading = false,
    this.iconSize = IconSize.sm,
    this.color,
    this.tooltip = true,
    super.key,
  });

  final String icon;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final DashButtonVariant variant;
  final bool loading;
  final double iconSize;

  /// Glyph colour override (a muted close ×).
  final Color? color;

  /// Show [semanticLabel] as a tooltip.
  final bool tooltip;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return DashPressable(
      onTap: enabled ? onPressed : null,
      enabled: enabled,
      tooltip: tooltip ? semanticLabel : null,
      semanticLabel: semanticLabel,
      excludeChildSemantics: true,
      builder: (context, s) => _DashButtonFace(
        label: '',
        variant: variant,
        size: DashButtonSize.regular,
        icon: icon,
        iconSize: iconSize,
        iconColor: color,
        loading: loading,
        enabled: enabled,
        expand: false,
        state: s,
      ),
    );
  }
}

/// Fill, text and edge colours of a variant in a state.
({Color? fill, Color fg, Color? edge}) dashButtonColors(
  BuildContext context,
  DashButtonVariant variant,
  DashPressState s, {
  required bool enabled,
}) {
  final c = context.madarColors;
  final hot = s.highlighted;
  if (!enabled) {
    return switch (variant) {
      DashButtonVariant.outline => (
        fill: null,
        fg: c.disabledText,
        edge: c.input,
      ),
      DashButtonVariant.ghost ||
      DashButtonVariant.link => (fill: null, fg: c.disabledText, edge: null),
      _ => (fill: c.muted, fg: c.disabledText, edge: null),
    };
  }
  return switch (variant) {
    DashButtonVariant.primary => (
      fill: hot ? Color.lerp(c.accent, c.bg, 0.12) : c.accent,
      fg: c.textOnAccent,
      edge: null,
    ),
    DashButtonVariant.brand => (
      fill: hot ? Color.lerp(c.brand, c.bg, 0.1) : c.brand,
      fg: c.onBrand,
      edge: null,
    ),
    DashButtonVariant.destructive => (
      fill: hot ? Color.lerp(c.danger, c.bg, 0.1) : c.danger,
      fg: Theme.of(context).brightness == Brightness.dark
          ? c.chrome
          : c.surface,
      edge: null,
    ),
    DashButtonVariant.outline => (
      fill: hot ? c.hover : c.card,
      fg: c.textPrimary,
      edge: c.input,
    ),
    DashButtonVariant.secondary => (
      fill: hot ? c.hover : c.muted,
      fg: c.textPrimary,
      edge: null,
    ),
    DashButtonVariant.ghost => (
      fill: hot ? c.hover : null,
      fg: c.textPrimary,
      edge: null,
    ),
    DashButtonVariant.link => (fill: null, fg: c.textPrimary, edge: null),
  };
}

class _DashButtonFace extends StatelessWidget {
  const _DashButtonFace({
    required this.label,
    required this.variant,
    required this.size,
    required this.loading,
    required this.enabled,
    required this.expand,
    required this.state,
    this.icon,
    this.trailingIcon,
    this.iconSize = IconSize.sm,
    this.iconColor,
  });

  final String label;
  final DashButtonVariant variant;
  final DashButtonSize size;
  final String? icon;
  final String? trailingIcon;
  final double iconSize;
  final Color? iconColor;
  final bool loading;
  final bool enabled;
  final bool expand;
  final DashPressState state;

  @override
  Widget build(BuildContext context) {
    final colors = dashButtonColors(
      context,
      variant,
      state,
      enabled: enabled || loading,
    );
    final fg = loading ? colors.fg.withValues(alpha: 0.7) : colors.fg;
    final square = label.isEmpty;
    final compact = size == DashButtonSize.compact;
    final textStyle =
        (compact
                ? DashType.meta.copyWith(fontWeight: FontWeight.w500)
                : DashType.bodyMedium)
            .copyWith(
              color: fg,
              decoration: variant == DashButtonVariant.link
                  ? TextDecoration.underline
                  : null,
              decorationColor: fg.withValues(
                alpha: state.highlighted ? 1 : 0.3,
              ),
            );
    final radius = BorderRadius.circular(Radii.sm);
    final lead = loading
        ? SizedBox.square(
            dimension: iconSize,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          )
        : icon == null
        ? null
        : DashIcon(icon!, size: iconSize, color: iconColor ?? fg);
    final hPad = square
        ? 0.0
        : variant == DashButtonVariant.link
        ? Space.xs
        : compact
        ? Space.md
        : (lead != null ? Space.md : Space.lg);
    return Container(
      height: DashMetrics.control,
      constraints: const BoxConstraints(minWidth: DashMetrics.target),
      padding: EdgeInsetsDirectional.symmetric(horizontal: hPad),
      foregroundDecoration: dashFocusRing(context, state, radius),
      decoration: BoxDecoration(
        color: colors.fill,
        borderRadius: radius,
        border: colors.edge == null ? null : Border.all(color: colors.edge!),
      ),
      // Ellipsis needs a bound: a bare Row child gets an unbounded width, and
      // a Flexible there would throw.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final text = MadarClippedText(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyle,
          );
          return Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: Space.sm,
            children: [
              ?lead,
              if (!square)
                if (constraints.hasBoundedWidth)
                  Flexible(child: text)
                else
                  text,
              if (trailingIcon != null)
                DashIcon(trailingIcon!, size: IconSize.xs, color: fg),
            ],
          );
        },
      ),
    );
  }
}
