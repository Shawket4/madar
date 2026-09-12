import 'package:flutter/widgets.dart';

/// Which device the till is running on — THE decision every package makes
/// the same way.
///
/// iPad landscape (1194 × 834) is the primary target; a phone (~390 wide) is
/// a real fallback that a waiter carries all shift. The two are told apart
/// by the SHORTEST side of the window, not the width: an iPad is a tablet in
/// portrait too (834 × 1194 still gets the rail), and a phone turned sideways
/// is still a phone (844 × 390 does not suddenly grow a rail and a cart
/// column it cannot fit). 600 is the line; nothing ships between 430 and 744.
///
/// ```dart
/// switch (MadarLayout.of(context)) {
///   case MadarLayout.phone:  return const _PhoneFloor();
///   case MadarLayout.tablet: return const _TabletFloor();
/// }
/// ```
///
/// What the layout decides:
///
///   * [MadarLayout.tablet] — the dark rail on the start edge, the top bar
///     with branch + till + outbox pill, split screens (catalog | cart),
///     sheets capped at 600 wide and centred, cards in two columns.
///   * [MadarLayout.phone]  — bottom tab bar, the status strip on top, one
///     column, full-height sheets, a cart behind a bottom bar's ▲.
///
/// For a decision inside ONE widget's own box (does this card wrap its
/// buttons?), keep using a `LayoutBuilder` against [Responsive]'s
/// container breakpoints — a tablet's 340px cart column is still narrow.
enum MadarLayout {
  phone,
  tablet;

  /// Shortest window side at or above which the device is a tablet.
  static const double tabletMinShortSide = 600;

  /// The layout for the window this [context] is in.
  static MadarLayout of(BuildContext context) =>
      fromSize(MediaQuery.sizeOf(context));

  /// The layout for a window of [size] (tests, previews).
  static MadarLayout fromSize(Size size) =>
      size.shortestSide >= tabletMinShortSide
      ? MadarLayout.tablet
      : MadarLayout.phone;

  bool get isPhone => this == MadarLayout.phone;
  bool get isTablet => this == MadarLayout.tablet;

  /// The dark rail on the start edge (tablet) versus a bottom tab bar
  /// (phone). Same tabs, same order, same badges.
  bool get usesRail => isTablet;

  /// Page side gutter: 24 on a tablet, 16 on a phone.
  double get gutter => isTablet ? 24 : 16;

  /// Picks one of two values by layout.
  T pick<T>({required T phone, required T tablet}) => isTablet ? tablet : phone;
}

extension MadarLayoutX on BuildContext {
  /// `context.madarLayout` — see [MadarLayout].
  MadarLayout get madarLayout => MadarLayout.of(this);

  /// True when the window is a phone. Sugar for the commonest test.
  bool get isPhone => madarLayout.isPhone;
}

/// Builds one of two subtrees by [MadarLayout]. Prefer this over an
/// `if (width > 700)` — every package then flips at the same line.
class MadarLayoutSwitch extends StatelessWidget {
  const MadarLayoutSwitch({
    required this.phone,
    required this.tablet,
    super.key,
  });

  final WidgetBuilder phone;
  final WidgetBuilder tablet;

  @override
  Widget build(BuildContext context) => switch (MadarLayout.of(context)) {
    MadarLayout.phone => phone(context),
    MadarLayout.tablet => tablet(context),
  };
}

/// Container-width breakpoints + content caps, for decisions made INSIDE a
/// box (LayoutBuilder), where the window's layout is not the question.
///
/// Pick the device with [MadarLayout]; pick a widget's own arrangement with
/// these.
abstract final class Responsive {
  /// ≥ → tablet spacing / wider forms.
  static const double tablet = 600;

  /// ≥ → table layout (order history, shift history).
  static const double wideTable = 680;

  /// ≥ → split / side-by-side (catalog | cart, brand panel | form).
  static const double wide = 760;

  /// ≥ → desktop mode: cap & center content.
  static const double desktop = 1100;

  /// The cart column beside the catalog on a tablet.
  static const double cartColumnWidth = 340;

  /// The Bill, centred on a tablet.
  static const double billMaxWidth = 640;

  // Content max-widths (centering caps — content never stretches past).
  static const double formMaxWidth = 520;
  static const double formMaxWidthWide = 600;
  static const double listMaxWidth = 560;
  static const double contentMaxWidth = 880;

  /// A sheet on a tablet: 600 wide, centred.
  static const double sheetMaxWidth = 600;
  static const double sheetCompactMaxWidth = 540;

  /// Brand panel ↔ form split ratio on wide auth screens.
  static const double brandPanelRatio = 0.55;

  /// Form cap for a given container width.
  static double formWidth(double containerWidth) =>
      containerWidth >= tablet ? formMaxWidthWide : formMaxWidth;
}

/// LayoutBuilder wrapper that hands the builder the container width plus
/// the derived breakpoint booleans — for a widget deciding about its own
/// box. For the device, ask [MadarLayout].
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
