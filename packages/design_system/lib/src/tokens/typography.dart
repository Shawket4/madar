import 'package:flutter/widgets.dart';

/// The Madar type scale — IBM Plex Sans Arabic for words, IBM Plex Mono for
/// every figure. Sizes are the canvas's: 28 / 22 / 18 / 16 / 15 / 13 / 12.
/// Colors are applied by callers from MadarColors.
///
/// ONE SUPERFAMILY, both scripts. Plex Sans Arabic carries Latin as well as
/// Arabic, so a bilingual row — an Arabic item name beside a Latin size label —
/// sits on one skeleton instead of two faces meeting in the middle of it. The
/// figures are Plex Mono, the same superfamily's monospaced cut, which is why
/// a column of totals lines up without the digits looking borrowed.
abstract final class MadarType {
  static const String fontFamily = 'IBMPlexSansArabic';

  /// The package the family is declared in (needed when consuming the font
  /// from outside design_system).
  static const String fontPackage = 'design_system';

  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  static TextStyle _base(
    double size,
    FontWeight weight, {
    double? letterSpacing,
    double? height,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      package: fontPackage,
      fontSize: size,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  /// The heaviest cut there is.
  ///
  /// Cairo went to ExtraBold and these styles asked for `w800`. Plex stops at
  /// Bold, so `w800` would be matched to this anyway — said outright rather
  /// than left as a weight the family cannot honour.
  static const FontWeight heaviest = FontWeight.w700;

  /// The kit board's own title. Not for screens.
  static final TextStyle display = _base(34, heaviest, letterSpacing: -0.5);

  /// Screen titles — 28.
  static final TextStyle h1 = _base(
    28,
    heaviest,
    letterSpacing: -0.4,
    height: 1,
  );

  /// Section / sheet titles — 22.
  static final TextStyle h2 = _base(
    22,
    FontWeight.w700,
    letterSpacing: -0.2,
    height: 1.1,
  );

  /// Card titles — 18.
  static final TextStyle h3 = _base(18, FontWeight.w600, height: 1.2);

  /// A row's title — 16.
  static final TextStyle title = _base(16, FontWeight.w600);

  /// Default body text — 15.
  static final TextStyle body = _base(15, FontWeight.w500);

  /// Meta: a row's second line — 13.
  static final TextStyle bodySm = _base(13, FontWeight.w500);

  /// Uppercase labels — 12, pair with [tracking].
  static final TextStyle label = _base(12, FontWeight.w700);

  /// Dense labels: a rail tab's word, a tag.
  static final TextStyle labelSm = _base(11, FontWeight.w600);

  /// A button's word — 17 bold.
  static final TextStyle button = _base(17, FontWeight.w700);

  /// A small button's or a chip's word — 15 semibold.
  static final TextStyle buttonSm = _base(15, FontWeight.w600);

  /// Uppercase label letter-spacing.
  static const double tracking = 0.8;

  // ── Figures ────────────────────────────────────────────────
  //
  // Money, times, durations, refs, phone numbers are set in IBM Plex Mono,
  // tabular, and are LTR islands inside Arabic text. Two reasons: a column
  // of figures only aligns if the digits are the same width, and a monospace
  // face makes `09:04` read as a reading off a clock instead of as a word in
  // a sentence. Latin digits in BOTH languages — Arabic-Indic numerals on a
  // till are a legibility regression for the people who actually read it.

  static const String monoFamily = 'IBMPlexMono';

  static TextStyle _mono(
    double size,
    FontWeight weight, {
    double? letterSpacing,
  }) => TextStyle(
    fontFamily: monoFamily,
    package: fontPackage,
    fontSize: size,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    fontFeatures: _tabular,
  );

  /// A row's amount — 15 bold.
  static final TextStyle money = _mono(15, FontWeight.w700);

  /// A card's amount, the money bar's figure — 20 bold.
  static final TextStyle moneyMd = _mono(20, FontWeight.w700);

  /// A section total — 22 bold.
  static final TextStyle moneyLg = _mono(22, FontWeight.w700);

  /// The total on Charge, the amount field — 30 bold.
  static final TextStyle moneyDisplay = _mono(30, FontWeight.w700);

  /// A shift's takings — 44 bold.
  static final TextStyle moneyHero = _mono(
    44,
    FontWeight.w700,
    letterSpacing: -1,
  );

  /// Inline figures inside a row of text (a time, a ref, a count) — 13.
  static final TextStyle num = _mono(13, FontWeight.w600);

  /// Emphasised figures — a row's time column — 15.
  static final TextStyle numMd = _mono(15, FontWeight.w600);

  /// A tile's count, a stat — 16.
  static final TextStyle numLg = _mono(16, FontWeight.w600);

  /// A stat card's headline — 30.
  static final TextStyle numXl = _mono(30, FontWeight.w700);

  /// The live clock on the home screen.
  static final TextStyle numDisplay = _mono(46, FontWeight.w700);
}
