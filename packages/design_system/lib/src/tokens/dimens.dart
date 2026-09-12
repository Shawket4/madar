/// Spacing / radius / sizing scales — system v2, the numbers on the canvas.
/// Logical pixels.
library;

/// 4-pt spacing scale.
abstract final class Space {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// A card's inner inset and a page's side gutter on a tablet.
  static const double card = 20;
}

/// Corner radii. `pill` fully rounds.
///
/// Three do the work: [control] on anything you press, [card] on anything
/// that holds rows, [sheet] on anything that slides or floats in.
abstract final class Radii {
  static const double xs = 8;

  /// A small button, a glyph tile, a stepper.
  static const double sm = 10;

  /// A button, a field, a chip tile, a segment track.
  static const double control = 12;

  /// A card.
  static const double card = 16;

  /// A sheet or a modal.
  static const double sheet = 20;

  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double pill = 999;
}

/// Semantic icon sizes.
abstract final class IconSize {
  static const double xs = 14;
  static const double sm = 16;
  static const double md = 18;
  static const double lg = 20;
  static const double xl = 22;

  /// A rail tab's glyph.
  static const double xxl = 26;
}

/// Semantic opacities.
abstract final class Opacities {
  /// Faint tints, the duotone fill behind an active glyph's stroke.
  static const double subtle = 0.28;

  /// Chip/banner hairline borders.
  static const double border = 0.25;

  /// Disabled controls.
  static const double disabled = 0.4;

  /// Kept for callers; the flat system draws no glow. Zero.
  static const double focusGlow = 0;

  /// Sheet/modal scrim overlay.
  static const double scrim = 0.5;

  /// Press overlay.
  static const double press = 0.08;
}

/// Named component metrics.
///
/// The system has four heights and everything sits on one of them: 44 for
/// small things (chips, small buttons, glyph tiles), 52–56 for the things
/// you press all day (fields, buttons), 64 for a row or the money bar, and
/// 72 for the amount you are about to take.
abstract final class Metrics {
  /// THE button. Nothing you press for money is shorter.
  static const double buttonHeight = 56;

  /// A small button in a dense row; a chip; a glyph tile.
  static const double buttonSmallHeight = 44;

  /// The money bar — the one control that carries an amount.
  static const double moneyBarHeight = 64;

  /// A text field.
  static const double inputHeight = 52;

  /// The hero amount field.
  static const double amountFieldHeight = 72;

  /// A list row. Also the money bar's height, on purpose: the total at the
  /// foot of a list is a row that happens to be teal.
  static const double rowHeight = 64;

  /// A chip.
  static const double chipHeight = 44;

  /// A chip tile — a chip that carries a figure (a party size, a minute
  /// count) and so is squarer.
  static const double chipTileHeight = 52;
  static const double chipTileMinWidth = 64;

  /// A segmented control's track.
  static const double segmentHeight = 48;

  /// A glyph tile (a square button holding one icon).
  static const double glyphTile = 44;
  static const double glyphTileLarge = 56;

  /// A stepper's track and each of its keys.
  static const double stepper = 40;

  /// The dark rail on the start edge of a tablet.
  static const double railWidth = 88;
  static const double railTabWidth = 72;
  static const double railTabHeight = 68;
  static const double railMark = 44;

  /// The top bar.
  static const double topBarHeight = 56;

  /// The phone's bottom tab bar (above the home indicator).
  static const double tabBarHeight = 64;

  /// The outbox pill in the top bar.
  static const double pillHeight = 32;

  /// The signed-in person's disc at the foot of the rail.
  static const double avatar = 40;

  /// A state tag ("NEW", "READY").
  static const double tagHeight = 26;

  /// An in-page header row.
  static const double headerHeight = 48;

  /// A table's header and row, where a table is still the right shape.
  static const double tableHeaderHeight = 42;
  static const double tableRowHeight = 56;

  static const double iconTile = 38;
  static const double ingredientBox = 54;
  static const double closeButton = 32;
  static const double pinKey = 64;
}

/// Catalog card grid.
abstract final class Grid {
  /// Gap between tiles.
  static const double gutter = 14;

  /// Max tile width — column count adapts to container width.
  static const double cellMax = 220;

  /// A menu tile's height.
  static const double tileHeight = 120;

  /// Outer grid padding.
  static const double padding = 16;
}
