import 'package:design_system/src/tokens/colors.dart';
import 'package:design_system/src/tokens/typography.dart';
import 'package:flutter/material.dart';

/// Builds the two Madar themes. Screens read roles from
/// `context.madarColors`; the Material ColorScheme below only keeps
/// framework-rendered widgets (ripples, cursors, dialogs) on-palette.
abstract final class MadarTheme {
  static ThemeData light() => _theme(MadarColors.light, Brightness.light);

  static ThemeData dark() => _theme(MadarColors.dark, Brightness.dark);

  static ThemeData _theme(MadarColors c, Brightness brightness) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.accent,
      onPrimary: c.textOnAccent,
      secondary: c.navy,
      onSecondary: c.textOnAccent,
      error: c.danger,
      onError: c.textOnAccent,
      surface: c.surface,
      onSurface: c.textPrimary,
      outline: c.border,
      surfaceContainerHighest: c.surfaceAlt,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      fontFamily: MadarType.fontFamily,
      // package-qualified family: ThemeData.fontFamily can't express it, so
      // set the default via textTheme below.
      textTheme: Typography.material2021(platform: TargetPlatform.iOS).black
          .apply(
            fontFamily: MadarType.fontFamily,
            package: MadarType.fontPackage,
            bodyColor: c.textPrimary,
            displayColor: c.textPrimary,
          ),
      scaffoldBackgroundColor: c.bg,
      dividerColor: c.border,
      splashFactory: InkSparkle.splashFactory,
      extensions: [c],
    );
  }
}
