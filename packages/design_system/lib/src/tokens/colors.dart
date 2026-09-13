import 'package:flutter/material.dart';

/// The Madar colour roles — system v2, the values on the approved canvas.
///
/// Two families. The WORK SURFACE is paper: a light ground, white cards, a
/// sunk grey for secondary controls, ink text. The CHROME is ink: the rail,
/// the top bar, the active tab, the outbox pill — dark in both themes, so the
/// frame around the work never changes colour when the room does. Teal is
/// the one primary; amber is attention; green is ready; red is money going
/// the wrong way.
///
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
    required this.accentDeep,
    required this.accentBg,
    required this.navy,
    required this.navyBg,
    required this.success,
    required this.successBg,
    required this.danger,
    required this.dangerBg,
    required this.warning,
    required this.warningBg,
    required this.chrome,
    required this.chromeAlt,
    required this.chromeRaised,
    required this.onChrome,
    required this.onChromeMuted,
    required this.brand,
    required this.onBrand,
    this.info = const Color(0xFF2563C9),
    this.infoBg = const Color(0xFFE1EBFA),
  });

  // ── Work surface ──────────────────────────────────────────────────────

  /// The paper the screen is printed on.
  final Color bg;

  /// A card, a field, a row.
  final Color surface;

  /// The sunk grey: secondary buttons, chips at rest, segment tracks.
  final Color surfaceAlt;

  /// Kept for callers that ask for it; the flat system has no third level,
  /// so it is [surface].
  final Color surfaceRaised;

  /// A field's edge.
  final Color border;

  /// A card's edge, a hairline between rows.
  final Color borderLight;

  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  /// Text on an accent fill. White on the ink accent in light mode; rail ink
  /// in dark mode, where the accent is a pale slate so it reads on the dark
  /// work surface.
  final Color textOnAccent;

  // ── Roles ────────────────────────────────────────────────────────────

  /// The one primary: the rail's ink (light) / pale slate (dark). One per
  /// screen.
  final Color accent;

  /// The primary, pressed.
  final Color accentDeep;

  /// Ink wash: the focus ring, a "new" tag, a selected tile's tint.
  final Color accentBg;

  /// Legacy alias of [accentDeep]. New work says what it means.
  final Color navy;

  /// Legacy alias of [accentBg].
  final Color navyBg;

  final Color success;
  final Color successBg;
  final Color danger;
  final Color dangerBg;
  final Color warning;
  final Color warningBg;

  // ── Chrome ───────────────────────────────────────────────────────────

  /// The rail and the top bar.
  final Color chrome;

  /// An ink-filled control: a chip that is on, the "ink" button.
  final Color chromeAlt;

  /// A raised patch on the chrome: the active tab, the outbox pill, the
  /// avatar disc.
  final Color chromeRaised;

  /// Text and glyphs on the chrome.
  final Color onChrome;

  /// Quieter text on the chrome: the inactive tab, the till number.
  final Color onChromeMuted;

  // ── Brand ────────────────────────────────────────────────────────────

  /// Madar teal, for brand marks only (the rail's logo square, a sync glyph
  /// on the chrome). Buttons and selections use [accent], never this.
  final Color brand;

  /// The mark's ink on a [brand] plate.
  final Color onBrand;

  /// A real blue for "somebody is here" — the floor's occupied tables. The
  /// accent is near-black, which made the busiest tables the dullest.
  final Color info;

  /// The wash behind [info].
  final Color infoBg;

  /// Light: ink on paper.
  static const light = MadarColors(
    bg: Color(0xFFF1F3F3),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFE4E9EA),
    surfaceRaised: Color(0xFFFFFFFF),
    border: Color(0xFFD3DADB),
    borderLight: Color(0xFFE6EBEC),
    textPrimary: Color(0xFF101820),
    textSecondary: Color(0xFF4F5F66),
    textMuted: Color(0xFF7A8890),
    textOnAccent: Color(0xFFFFFFFF),
    accent: Color(0xFF0D1A1E),
    accentDeep: Color(0xFF1E353B),
    accentBg: Color(0xFFDDE4E6),
    navy: Color(0xFF1E353B),
    navyBg: Color(0xFFDDE4E6),
    success: Color(0xFF178A4C),
    successBg: Color(0xFFDCF2E4),
    danger: Color(0xFFD0392C),
    dangerBg: Color(0xFFFBE3E0),
    warning: Color(0xFFBF5F07),
    warningBg: Color(0xFFFBEBD5),
    chrome: Color(0xFF0D1A1E),
    chromeAlt: Color(0xFF15272C),
    chromeRaised: Color(0xFF1E353B),
    onChrome: Color(0xFFEAF0F1),
    onChromeMuted: Color(0xFF9DB0B6),
    brand: Color(0xFF0F7A8A),
    onBrand: Color(0xFFFFFFFF),
  );

  /// Dark: paper on ink, for a dim room. The chrome goes a shade deeper so
  /// it still frames the work.
  static const dark = MadarColors(
    bg: Color(0xFF0F1A1E),
    surface: Color(0xFF16252A),
    surfaceAlt: Color(0xFF213238),
    surfaceRaised: Color(0xFF16252A),
    border: Color(0xFF2C4048),
    borderLight: Color(0xFF243740),
    textPrimary: Color(0xFFEEF3F4),
    textSecondary: Color(0xFFB3C2C7),
    textMuted: Color(0xFF7E929A),
    textOnAccent: Color(0xFF0D1A1E),
    accent: Color(0xFFD3DEE1),
    accentDeep: Color(0xFFB2C3C8),
    accentBg: Color(0xFF26393F),
    navy: Color(0xFFB2C3C8),
    navyBg: Color(0xFF26393F),
    success: Color(0xFF3BCB7E),
    successBg: Color(0xFF123324),
    danger: Color(0xFFF26B5E),
    dangerBg: Color(0xFF3D1C1C),
    warning: Color(0xFFF0A23F),
    warningBg: Color(0xFF3A2A12),
    chrome: Color(0xFF0A1417),
    chromeAlt: Color(0xFF0F1D21),
    chromeRaised: Color(0xFF173036),
    onChrome: Color(0xFFEAF0F1),
    onChromeMuted: Color(0xFF8FA4AB),
    brand: Color(0xFF2AA7B8),
    onBrand: Color(0xFF06191D),
    info: Color(0xFF6EA3F5),
    infoBg: Color(0xFF172F4D),
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
      accentDeep: l(accentDeep, other.accentDeep),
      accentBg: l(accentBg, other.accentBg),
      navy: l(navy, other.navy),
      navyBg: l(navyBg, other.navyBg),
      success: l(success, other.success),
      successBg: l(successBg, other.successBg),
      danger: l(danger, other.danger),
      dangerBg: l(dangerBg, other.dangerBg),
      warning: l(warning, other.warning),
      warningBg: l(warningBg, other.warningBg),
      chrome: l(chrome, other.chrome),
      chromeAlt: l(chromeAlt, other.chromeAlt),
      chromeRaised: l(chromeRaised, other.chromeRaised),
      onChrome: l(onChrome, other.onChrome),
      onChromeMuted: l(onChromeMuted, other.onChromeMuted),
      brand: l(brand, other.brand),
      onBrand: l(onBrand, other.onBrand),
      info: l(info, other.info),
      infoBg: l(infoBg, other.infoBg),
    );
  }
}

extension MadarColorsX on BuildContext {
  MadarColors get madarColors => MadarColors.of(this);
}

/// `#RRGGBB` (with or without the hash) to an opaque [Color].
///
/// The one place a colour arrives from OUTSIDE the token set: a category's
/// style, a payment method's brand. Unparseable input falls back to black
/// rather than throwing — a menu tile with the wrong tint is a blemish, a
/// crashed catalogue is a shop that cannot sell.
Color hexColor(String hex) {
  final digits = hex.replaceFirst('#', '');
  final value = int.tryParse(digits, radix: 16) ?? 0;
  return Color(0xFF000000 | value);
}
