import 'package:flutter/widgets.dart';

/// The Madar type scale — Cairo at the natives' exact sizes/weights
/// (Type.kt / Typography.swift). Money styles use tabular figures so
/// amount columns align. Colors are applied by callers from MadarColors.
abstract final class MadarType {
  static const String fontFamily = 'Cairo';

  /// The package the Cairo family is declared in (needed when consuming
  /// the font from outside design_system).
  static const String fontPackage = 'design_system';

  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  static TextStyle _base(
    double size,
    FontWeight weight, {
    double? letterSpacing,
    List<FontFeature>? features,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      package: fontPackage,
      fontSize: size,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      fontFeatures: features,
    );
  }

  /// Hero numbers, grand totals.
  static final TextStyle display = _base(
    34,
    FontWeight.w800,
    letterSpacing: -0.5,
  );

  /// Screen titles.
  static final TextStyle h1 = _base(30, FontWeight.w800, letterSpacing: -0.4);

  /// Section / sheet titles.
  static final TextStyle h2 = _base(22, FontWeight.w700, letterSpacing: -0.2);

  /// Card titles.
  static final TextStyle h3 = _base(17, FontWeight.w600);

  /// Emphasized rows.
  static final TextStyle title = _base(15, FontWeight.w600);

  /// Default body text.
  static final TextStyle body = _base(14, FontWeight.w500);

  /// Secondary body.
  static final TextStyle bodySm = _base(13, FontWeight.w400);

  /// Uppercase labels (pair with [tracking]).
  static final TextStyle label = _base(12, FontWeight.w600);

  /// Chips, dense labels.
  static final TextStyle labelSm = _base(11, FontWeight.w600);

  /// Amounts (tabular).
  static final TextStyle money = _base(14, FontWeight.w700, features: _tabular);

  /// Large amounts (tabular).
  static final TextStyle moneyLg = _base(
    24,
    FontWeight.w800,
    features: _tabular,
  );

  /// Hero amount totals (tabular).
  static final TextStyle moneyDisplay = _base(
    34,
    FontWeight.w800,
    features: _tabular,
  );

  /// Uppercase label letter-spacing.
  static const double tracking = 0.6;

  // ── Numbers ────────────────────────────────────────────────
  //
  // Times, durations, currency, employee IDs and phone numbers are set in IBM
  // Plex Mono rather than Cairo. Two reasons: a column of figures only aligns
  // if the digits are the same width, and a monospace face makes `09:04` read
  // as a reading off a clock instead of as a word in a sentence. Latin digits
  // in BOTH languages — Arabic-Indic numerals in a timesheet are a legibility
  // regression for the people who actually read these screens.

  static const String monoFamily = 'IBMPlexMono';

  static TextStyle _mono(double size, FontWeight weight) => TextStyle(
    fontFamily: monoFamily,
    package: fontPackage,
    fontSize: size,
    fontWeight: weight,
  );

  /// Inline figures inside a row of text (a shift window, a duration).
  static final TextStyle num = _mono(13, FontWeight.w600);

  /// Emphasised figures — a day's hours, a stat card's value.
  static final TextStyle numMd = _mono(15, FontWeight.w700);

  /// Stat-card headline numbers.
  static final TextStyle numLg = _mono(20, FontWeight.w700);

  /// Net pay on a payslip hero.
  static final TextStyle numXl = _mono(30, FontWeight.w700);

  /// The live clock on the home screen.
  static final TextStyle numDisplay = _mono(46, FontWeight.w700);
}
