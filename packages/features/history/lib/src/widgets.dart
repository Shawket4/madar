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
                  : Colors.transparent,
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
                Text(label, style: MadarType.label.copyWith(color: fg)),
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
