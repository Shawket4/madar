import 'package:flutter/widgets.dart';

/// Width breakpoints + content caps — the natives' Responsive object.
/// Decisions are made on the CONTAINER width (LayoutBuilder), matching
/// Compose's BoxWithConstraints usage, not the window width.
abstract final class Responsive {
  /// ≥ → tablet spacing / wider forms.
  static const double tablet = 600;

  /// ≥ → table layout (order history, shift history).
  static const double wideTable = 680;

  /// ≥ → split / side-by-side (login, open-shift, order).
  static const double wide = 760;

  /// ≥ → desktop mode: cap & center content.
  static const double desktop = 1100;

  // Content max-widths (centering caps — content never stretches past).
  static const double formMaxWidth = 520;
  static const double formMaxWidthWide = 600;
  static const double listMaxWidth = 560;
  static const double contentMaxWidth = 880;
  static const double sheetMaxWidth = 600;
  static const double sheetCompactMaxWidth = 540;

  /// Brand panel ↔ form split ratio on wide auth screens.
  static const double brandPanelRatio = 0.55;

  /// Form cap for a given container width.
  static double formWidth(double containerWidth) =>
      containerWidth >= tablet ? formMaxWidthWide : formMaxWidth;
}

/// LayoutBuilder wrapper that hands the builder the container width plus
/// the derived breakpoint booleans — the standard screen-level entry.
class ResponsiveBuilder extends StatelessWidget {
  const ResponsiveBuilder({required this.builder, super.key});

  final Widget Function(BuildContext context, ResponsiveInfo info) builder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) =>
          builder(context, ResponsiveInfo(constraints.maxWidth)),
    );
  }
}

@immutable
class ResponsiveInfo {
  const ResponsiveInfo(this.width);

  final double width;

  bool get isTablet => width >= Responsive.tablet;
  bool get isWideTable => width >= Responsive.wideTable;
  bool get isWide => width >= Responsive.wide;
  bool get isDesktop => width >= Responsive.desktop;
}
