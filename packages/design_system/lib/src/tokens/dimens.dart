/// Spacing / radius / sizing scales — exact values from the natives'
/// Layout.kt / Tokens.swift. Logical pixels (dp equivalents).
library;

/// 4-pt spacing scale.
abstract final class Space {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Corner radii. `pill` fully rounds.
abstract final class Radii {
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double pill = 999;
}

/// Semantic icon sizes.
abstract final class IconSize {
  static const double xs = 12;
  static const double sm = 14;
  static const double md = 16;
  static const double lg = 18;
  static const double xl = 20;
  static const double xxl = 24;
}

/// Semantic opacities.
abstract final class Opacities {
  /// Faint tints, decorative rings.
  static const double subtle = 0.14;

  /// Chip/banner hairline borders.
  static const double border = 0.25;

  /// Disabled controls.
  static const double disabled = 0.45;

  /// Focused text-field accent glow (approximates the natives'
  /// accent-tinted ambient+spot shadow at 8dp).
  static const double focusGlow = 0.35;

  /// Sheet/modal scrim overlay.
  static const double scrim = 0.45;

  /// Press overlay.
  static const double press = 0.08;
}

/// Named component metrics.
abstract final class Metrics {
  static const double buttonHeight = 54;
  static const double inputHeight = 48;
  static const double amountFieldHeight = 64;
  static const double tableHeaderHeight = 42;
  static const double tableRowHeight = 56;
  static const double iconTile = 38;
  static const double stepper = 30;
  static const double ingredientBox = 54;
  static const double closeButton = 32;
  static const double pinKey = 64;
}

/// Catalog card grid.
abstract final class Grid {
  /// Gap between cards (Space.lg).
  static const double gutter = 16;

  /// Max card width — column count adapts to container width.
  static const double cellMax = 208;

  /// Outer grid padding (Space.lg).
  static const double padding = 16;
}
