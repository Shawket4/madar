/// Small shared pieces the incoming feature reuses across its two tabs —
/// the action button + text field (the natives' MadarButton /
/// MadarTextField), the hairline, and the card shell metrics.
library;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

// Native metrics (IncomingScreen.kt / DeliveryScreen.kt / WaiterScreen.kt /
// Components.kt) that fall between the 4-pt Space steps — kept verbatim so
// the Flutter chrome measures identically to the Kotlin/Swift natives.

/// Board cards center under this cap (natives: widthIn(max = 620.dp)).
const double kBoardCardMaxWidth = 620;

/// Delivery card status strip height (natives: 50.dp).
const double kDeliveryStripHeight = 50;

/// Ticket card status strip height (natives: 56.dp).
const double kTicketStripHeight = 56;

/// Status dot diameter in the strip (natives: 8.dp).
const double kStatusDot = 8;

/// Person tone-tile on the delivery card (natives: 40.dp).
const double kPersonTile = 40;

/// Person tone-tile on the ticket card (natives: 34.dp).
const double kPersonTileSm = 34;

/// The ⋯ overflow button side (natives: 34.dp).
const double kMenuButton = 34;

/// Money hero pill vertical inset (natives: 7.dp).
const double kMoneyPillVPad = 7;

/// Button label letter-spacing (natives: 0.2.sp).
const double _buttonTracking = 0.2;

/// Primary-CTA top-lit gradient blend (natives: lerp(accent, white, 0.16)).
const double _ctaTopLight = 0.16;

/// Button loading spinner diameter / stroke (natives: 20.dp / 2.5.dp).
const double _spinnerSize = 20;
const double _spinnerStroke = 2.5;

/// Outline button border width (natives: 1.5.dp).
const double _outlineBorder = 1.5;

/// Text-field vertical inset (natives: 16.dp) and icon↔text gap (10.dp).
const double _fieldVPad = 16;
const double _fieldGap = 10;

bool _isDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

/// Button variants — the natives' `BtnVariant` (primary/outline/danger).
enum IncomingButtonVariant { primary, outline, danger }

/// The natives' `MadarButton`: flat rounded CTA on the shared press-scale,
/// with a top-lit gradient + accent glow on the primary variant and a
/// centered spinner while [loading]. [expand] mirrors `fullWidth` — the
/// board cards lay content-width buttons in a row.
class IncomingButton extends StatelessWidget {
  const IncomingButton({
    required this.label,
    required this.onTap,
    this.variant = IncomingButtonVariant.primary,
    this.loading = false,
    this.enabled = true,
    this.expand = true,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final IncomingButtonVariant variant;
  final bool loading;
  final bool enabled;

  /// `fullWidth` in the natives — false lets the button hug its label.
  final bool expand;

  final String? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final active = enabled && !loading;
    final fg = switch (variant) {
      IncomingButtonVariant.primary => colors.textOnAccent,
      IncomingButtonVariant.danger => colors.textOnAccent,
      IncomingButtonVariant.outline => colors.accent,
    };
    final gradient = variant == IncomingButtonVariant.primary && active
        ? LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(colors.accent, Colors.white, _ctaTopLight)!,
              colors.accent,
            ],
          )
        : null;
    final fill = switch (variant) {
      IncomingButtonVariant.primary =>
        active ? null : colors.accent.withValues(alpha: Opacities.disabled),
      IncomingButtonVariant.danger =>
        active
            ? colors.danger
            : colors.danger.withValues(alpha: Opacities.disabled),
      IncomingButtonVariant.outline => null,
    };

    final button = Container(
      height: Metrics.buttonHeight,
      width: expand ? double.infinity : null,
      padding: const EdgeInsetsDirectional.symmetric(horizontal: Space.lg),
      decoration: BoxDecoration(
        color: gradient == null ? fill : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(Radii.md),
        border: variant == IncomingButtonVariant.outline
            ? Border.all(color: colors.accent, width: _outlineBorder)
            : null,
        boxShadow: variant == IncomingButtonVariant.primary && active
            ? MadarElevation.glow.shadows(colors, dark: _isDark(context))
            : null,
      ),
      alignment: Alignment.center,
      child: loading
          ? SizedBox.square(
              dimension: _spinnerSize,
              child: CircularProgressIndicator(
                color: fg,
                strokeWidth: _spinnerStroke,
              ),
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
                      letterSpacing: _buttonTracking,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
    );

    if (!active) return Semantics(button: true, enabled: false, child: button);
    return Semantics(
      button: true,
      child: TactileScale(
        onTap: () {
          MadarHaptics.impact();
          onTap();
        },
        child: button,
      ),
    );
  }
}

/// The natives' MadarTextField: leading icon, muted placeholder, surface-alt
/// fill with a hairline border (the cancel-reason / void-note capture).
class IncomingTextField extends StatelessWidget {
  const IncomingTextField({
    required this.controller,
    required this.placeholder,
    this.icon,
    this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final String placeholder;
  final String? icon;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: Space.lg,
        vertical: _fieldVPad,
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            MadarIcon(icon, tint: colors.textMuted),
            const SizedBox(width: _fieldGap),
          ],
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              cursorColor: colors.accent,
              style: MadarType.body.copyWith(color: colors.textPrimary),
              decoration: InputDecoration.collapsed(
                hintText: placeholder,
                hintStyle: MadarType.body.copyWith(color: colors.textMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 1-px `border`-colored divider (the natives' bottom hairline rows).
class IncomingHairline extends StatelessWidget {
  const IncomingHairline({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: context.madarColors.border);
  }
}

/// The shared raised-card shell every board card / detail card uses:
/// surface fill, `borderLight` hairline, [Radii.md] corners, card shadow.
class IncomingCard extends StatelessWidget {
  const IncomingCard({
    required this.child,
    this.padding = const EdgeInsetsDirectional.all(Space.lg),
    this.clip = false,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// True for the board cards whose tinted status strip must clip to the
  /// rounded corners.
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final dark = _isDark(context);
    final decoration = BoxDecoration(
      color: colors.surface,
      borderRadius: BorderRadius.circular(Radii.md),
      border: Border.all(color: colors.borderLight),
      boxShadow: MadarElevation.card.shadows(colors, dark: dark),
    );
    final body = Padding(padding: padding, child: child);
    if (!clip) return DecoratedBox(decoration: decoration, child: body);
    return DecoratedBox(
      decoration: decoration,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.md),
        child: body,
      ),
    );
  }
}
