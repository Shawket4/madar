/// History-feature widget kit — the Flutter mirror of the natives' shared
/// pieces the history screens use (Components.kt / SharedComponents.kt:
/// MadarButton, MadarTextField, SelectableChip, the history filter chip
/// and payment badge; screen headers are the design system's MadarHeader).
/// Tokens-only, plus a few native component metrics that fall between the
/// 4-pt Space steps, kept verbatim (the design system's banners.dart
/// pattern) so the Flutter chrome measures identically to the Kotlin/Swift
/// natives.
library;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Button loading spinner diameter / stroke (natives: 20.dp / 2.5.dp).
const double _spinnerSize = 20;
const double _spinnerStroke = 2.5;

/// Outline button border width (natives: 1.5.dp).
const double _outlineBorder = 1.5;

/// Button label letter-spacing (natives: 0.2.sp).
const double _buttonTracking = 0.2;

/// Text-field vertical inset (natives: 16.dp) and icon↔text gap (10.dp).
const double _fieldVPad = 16;
const double _fieldGap = 10;

/// Focus glow blur on text fields (natives: shadow(8.dp, accent)).
const double _fieldGlowBlur = 8;

/// History filter chip insets / gap (natives: 12/6/5.dp) and press scale.
const double _chipHPad = 12;
const double _chipVPad = 6;
const double _chipGap = 5;
const double kChipPressScale = 0.96;

/// Payment badge insets (natives: 8/3.dp).
const double _badgeHPad = 8;
const double _badgeVPad = 3;

/// The natives' card-payment purple (OrderHistoryScreen.kt `paymentTint`) —
/// hardcoded there too, so it is kept verbatim rather than tokenized.
const Color _cardPurple = Color(0xFF7C3AED);

bool _isDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

/// Tone → background tint (the `*Bg` roles) — the natives' `ChipTone.bg`.
Color toneBg(ChipTone tone, MadarColors colors) => switch (tone) {
  ChipTone.info => colors.navyBg,
  ChipTone.accent => colors.accentBg,
  ChipTone.success => colors.successBg,
  ChipTone.warning => colors.warningBg,
  ChipTone.danger => colors.dangerBg,
  ChipTone.neutral => colors.surfaceAlt,
};

/// Status → a tone-paired chip color (voided/failed = danger, completed =
/// success, queued = warning, else neutral) — the natives' `statusTone`.
ChipTone statusToneOf(String status) => switch (status) {
  'voided' || 'failed' => ChipTone.danger,
  'completed' => ChipTone.success,
  'queued' => ChipTone.warning,
  _ => ChipTone.neutral,
};

/// A colored payment tint keyed off the label text — cash = success,
/// card = the natives' purple, mixed = warning, else navy.
Color paymentTint(String label, MadarColors colors) {
  final l = label.toLowerCase();
  if (l.contains('cash') || l.contains('نقد')) return colors.success;
  if (l.contains('card') || l.contains('بطاق')) return _cardPurple;
  if (l.contains('mixed') || l.contains('مختلط')) return colors.warning;
  return colors.navy;
}

/// A 1-px hairline rule in the theme border color.
class Hairline extends StatelessWidget {
  const Hairline({this.light = false, super.key});

  /// Uses the fainter `borderLight` role when set.
  final bool light;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Container(
      height: 1,
      color: light ? colors.borderLight : colors.border,
    );
  }
}

/// Button variants — the natives' `BtnVariant` subset the history uses.
enum HistoryButtonVariant { primary, outline, danger }

/// The natives' `MadarButton`: flat rounded CTA on the shared press-scale
/// with a centered spinner while [loading]. Convention copy of the shift
/// package's ShiftButton (its control kit is package-internal).
class HistoryButton extends StatelessWidget {
  const HistoryButton({
    required this.label,
    required this.onTap,
    this.variant = HistoryButtonVariant.primary,
    this.loading = false,
    this.enabled = true,
    this.icon,
    this.expand = true,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final HistoryButtonVariant variant;
  final bool loading;
  final bool enabled;
  final String? icon;

  /// Fills the available width when set (the natives' `fullWidth`).
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final active = enabled && !loading;
    final fg = switch (variant) {
      HistoryButtonVariant.primary => colors.textOnAccent,
      HistoryButtonVariant.danger => colors.textOnAccent,
      HistoryButtonVariant.outline => colors.accent,
    };
    final fill = switch (variant) {
      HistoryButtonVariant.primary =>
        active
            ? colors.accent
            : colors.accent.withValues(alpha: Opacities.disabled),
      HistoryButtonVariant.danger =>
        active
            ? colors.danger
            : colors.danger.withValues(alpha: Opacities.disabled),
      HistoryButtonVariant.outline => null,
    };

    final button = Container(
      height: Metrics.buttonHeight,
      width: expand ? double.infinity : null,
      padding: const EdgeInsetsDirectional.symmetric(horizontal: Space.lg),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(Radii.md),
        border: variant == HistoryButtonVariant.outline
            ? Border.all(color: colors.accent, width: _outlineBorder)
            : null,
        boxShadow: variant == HistoryButtonVariant.primary && active
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

    if (!active) return button;
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

/// The natives' `MadarTextField`: rounded field with an animated focus ring
/// (accent border + soft glow, surfaceAlt → surface fill) and an optional
/// leading icon that tints accent while focused. Convention copy of the
/// shift package's ShiftTextField, plus a live [onChanged] for the history
/// filter search.
class HistoryTextField extends StatefulWidget {
  const HistoryTextField({
    required this.controller,
    required this.placeholder,
    this.icon,
    this.onChanged,
    this.enabled = true,
    super.key,
  });

  final TextEditingController controller;
  final String placeholder;
  final String? icon;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  @override
  State<HistoryTextField> createState() => _HistoryTextFieldState();
}

class _HistoryTextFieldState extends State<HistoryTextField> {
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    // The focus ring re-renders off the FocusNode itself (a Listenable) —
    // no setState; the field body below rebuilds with it (cheap leaf).
    return ListenableBuilder(
      listenable: _focus,
      builder: (context, _) {
        final focused = _focus.hasFocus;
        return AnimatedContainer(
          duration: MotionSpec.standardDuration,
          curve: MotionSpec.standardCurve,
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: Space.lg,
            vertical: _fieldVPad,
          ),
          decoration: BoxDecoration(
            color: focused ? colors.surface : colors.surfaceAlt,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(
              color: focused ? colors.accent : colors.border,
              width: focused ? 2 : 1,
            ),
            boxShadow: focused
                ? [
                    BoxShadow(
                      color: colors.accent.withValues(
                        alpha: Opacities.focusGlow,
                      ),
                      blurRadius: _fieldGlowBlur,
                    ),
                  ]
                : null,
          ),
          child: Row(
            spacing: _fieldGap,
            children: [
              if (widget.icon != null)
                MadarIcon(
                  widget.icon,
                  tint: focused ? colors.accent : colors.textMuted,
                  size: IconSize.lg,
                ),
              Expanded(
                child: Material(
                  type: MaterialType.transparency,
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focus,
                    enabled: widget.enabled,
                    onChanged: widget.onChanged,
                    cursorColor: colors.accent,
                    style: MadarType.title.copyWith(
                      fontWeight: FontWeight.w400,
                      color: colors.textPrimary,
                    ),
                    decoration: InputDecoration.collapsed(
                      hintText: widget.placeholder,
                      hintStyle: MadarType.title.copyWith(
                        fontWeight: FontWeight.w400,
                        color: colors.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The history screen's filter chip — filled in its active tone, neutral
/// when off (OrderHistoryScreen.kt `HistoryChip` / the Swift `chip`).
class HistoryFilterChip extends StatelessWidget {
  const HistoryFilterChip({
    required this.glyph,
    required this.label,
    required this.active,
    required this.onTap,
    this.tone = ChipTone.accent,
    super.key,
  });

  final String glyph;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final ChipTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final fg = active ? tone.resolve(colors) : colors.textSecondary;
    final bg = active ? toneBg(tone, colors) : colors.surfaceAlt;
    return Semantics(
      button: true,
      selected: active,
      child: TactileScale(
        scale: kChipPressScale,
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(Radii.pill),
            border: Border.all(
              color: active
                  ? fg.withValues(alpha: Opacities.border)
                  : const Color(0x00000000),
            ),
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: _chipHPad,
              vertical: _chipVPad,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: _chipGap,
              children: [
                MadarIcon(glyph, tint: fg, size: IconSize.xs),
                Text(
                  label,
                  style: MadarType.label.copyWith(color: fg),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The natives' `SelectableChip` (SharedComponents.kt): a toggle pill that
/// fills with its tone (+ soft accent glow) while selected — the search
/// screen's date/status filters.
class SelectChip extends StatelessWidget {
  const SelectChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.tone = ChipTone.accent,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ChipTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final fg = selected ? colors.textOnAccent : colors.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      child: TactileScale(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected ? tone.resolve(colors) : colors.surfaceAlt,
            borderRadius: BorderRadius.circular(Radii.pill),
            border: selected ? null : Border.all(color: colors.border),
            boxShadow: selected
                ? MadarElevation.glow.shadows(colors, dark: _isDark(context))
                : null,
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: Space.md,
              vertical: Space.sm,
            ),
            child: Text(label, style: MadarType.title.copyWith(color: fg)),
          ),
        ),
      ),
    );
  }
}

/// A colored payment pill (not a StatusChip): tinted bg @ ~14%, colored
/// label; voided → muted on surfaceAlt (OrderHistoryScreen.kt PaymentBadge).
class PaymentBadge extends StatelessWidget {
  const PaymentBadge({required this.label, this.voided = false, super.key});

  final String label;
  final bool voided;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final tint = paymentTint(label, colors);
    final fg = voided ? colors.textMuted : tint;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: voided
            ? colors.surfaceAlt
            : tint.withValues(alpha: Opacities.subtle),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: _badgeHPad,
          vertical: _badgeVPad,
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: MadarType.labelSm.copyWith(color: fg),
        ),
      ),
    );
  }
}
