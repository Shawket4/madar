import 'package:flutter/material.dart';

/// The Madar color roles — exact values from the natives' Theme.kt /
/// Tokens.swift (ink-on-paper light, paper-on-ink dark, teal accent).
/// Access via `context.madarColors` or `MadarColors.of(context)`.
@immutable
class MadarColors extends ThemeExtension<MadarColors> {
  const MadarColors({
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.surfaceRaised,
    required this.border,
    required this.borderLight,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textOnAccent,
    required this.accent,
    required this.accentBg,
    required this.navy,
    required this.navyBg,
    required this.success,
    required this.successBg,
    required this.danger,
    required this.dangerBg,
    required this.warning,
    required this.warningBg,
  });

  final Color bg;
  final Color surface;
  final Color surfaceAlt;
  final Color surfaceRaised;
  final Color border;
  final Color borderLight;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textOnAccent;
  final Color accent;
  final Color accentBg;
  final Color navy;
  final Color navyBg;
  final Color success;
  final Color successBg;
  final Color danger;
  final Color dangerBg;
  final Color warning;
  final Color warningBg;

  /// Light: ink on paper, teal deep accent.
  static const light = MadarColors(
    bg: Color(0xFFEFF3F4),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFE7EEEF),
    surfaceRaised: Color(0xFFFFFFFF),
    border: Color(0xFFD7E0E1),
    borderLight: Color(0xFFE7EEEF),
    textPrimary: Color(0xFF14181E),
    textSecondary: Color(0xFF54636B),
    textMuted: Color(0xFF76828B),
    textOnAccent: Color(0xFFFFFFFF),
    accent: Color(0xFF0D6273),
    accentBg: Color(0xFFDCE9EB),
    navy: Color(0xFF0D6273),
    navyBg: Color(0xFFDCE9EB),
    success: Color(0xFF16A34A),
    successBg: Color(0xFFE7F6EC),
    danger: Color(0xFFDC2626),
    dangerBg: Color(0xFFFBEAEA),
    warning: Color(0xFFB45309),
    warningBg: Color(0xFFF7ECDD),
  );

  /// Dark: paper on ink, brighter teal accent.
  static const dark = MadarColors(
    bg: Color(0xFF14181E),
    surface: Color(0xFF1B2128),
    surfaceAlt: Color(0xFF222A32),
    surfaceRaised: Color(0xFF262F38),
    border: Color(0xFF313B45),
    borderLight: Color(0xFF232C35),
    textPrimary: Color(0xFFEFF3F4),
    textSecondary: Color(0xFFAEB9C0),
    textMuted: Color(0xFF76828B),
    textOnAccent: Color(0xFFFFFFFF),
    accent: Color(0xFF2E94A6),
    accentBg: Color(0xFF123038),
    navy: Color(0xFF5FB6C7),
    navyBg: Color(0xFF15333B),
    success: Color(0xFF3BCE7E),
    successBg: Color(0xFF13291D),
    danger: Color(0xFFF4655A),
    dangerBg: Color(0xFF33191B),
    warning: Color(0xFFF0A23F),
    warningBg: Color(0xFF332512),
  );

  static MadarColors of(BuildContext context) =>
      Theme.of(context).extension<MadarColors>()!;

  @override
  MadarColors copyWith() => this;

  @override
  MadarColors lerp(MadarColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return MadarColors(
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      surfaceAlt: l(surfaceAlt, other.surfaceAlt),
      surfaceRaised: l(surfaceRaised, other.surfaceRaised),
      border: l(border, other.border),
      borderLight: l(borderLight, other.borderLight),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textMuted: l(textMuted, other.textMuted),
      textOnAccent: l(textOnAccent, other.textOnAccent),
      accent: l(accent, other.accent),
      accentBg: l(accentBg, other.accentBg),
      navy: l(navy, other.navy),
      navyBg: l(navyBg, other.navyBg),
      success: l(success, other.success),
      successBg: l(successBg, other.successBg),
      danger: l(danger, other.danger),
      dangerBg: l(dangerBg, other.dangerBg),
      warning: l(warning, other.warning),
      warningBg: l(warningBg, other.warningBg),
    );
  }
}

extension MadarColorsX on BuildContext {
  MadarColors get madarColors => MadarColors.of(this);
}
