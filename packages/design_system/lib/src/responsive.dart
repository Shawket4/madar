import 'package:flutter/foundation.dart';
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

/// The four size classes the spec (docs/design/SPEC.md §1) draws grids for.
///
/// [MadarLayout] stays THE phone/tablet switch (rail or tab bar); this is the
/// finer question a page's grid asks — how wide may content run, how many
/// table columns fit. Decided by the window and the platform:
///
/// * [phone] — shortest side < 600 (any orientation).
/// * [desktop] — a macOS / Windows / Linux window that is not a phone.
/// * [tabletLandscape] / [tabletPortrait] — everything else, by orientation.
enum MadarSizeClass {
  phone,
  tabletPortrait,
  tabletLandscape,
  desktop;

  static MadarSizeClass of(BuildContext context) =>
      fromSize(MediaQuery.sizeOf(context), platform: defaultTargetPlatform);

  static MadarSizeClass fromSize(
    Size size, {
    TargetPlatform platform = TargetPlatform.iOS,
  }) {
    if (MadarLayout.fromSize(size).isPhone) return MadarSizeClass.phone;
    switch (platform) {
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return MadarSizeClass.desktop;
      case TargetPlatform.iOS:
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
        return size.width >= size.height
            ? MadarSizeClass.tabletLandscape
            : MadarSizeClass.tabletPortrait;
    }
  }

  bool get isPhone => this == MadarSizeClass.phone;

  /// The page gutter — the same number [MadarLayout.gutter] gives, so a page
  /// built either way lands on one edge. 16 phone, 24 everything else.
  double get gutter => isPhone ? 16 : 24;
}

/// How wide a page's content may run. Content is ALWAYS aligned to the
/// leading gutter — the title's edge — and never centred in the leftover
/// width: a centred island moves every time the window does, and the eye
/// has to find the page again. See docs/design/SPEC.md §3.
enum MadarContentWidth {
  /// Dashboards and split views: Till, Close shift, Orders, Queue, Sell,
  /// Floor. Runs gutter to gutter.
  full(double.infinity),

  /// Tables and settings: Past shifts, Settings, Me, Sync, Bills. 880.
  reading(880),

  /// Forms: Cash in/out, Open shift. 560.
  form(560);

  const MadarContentWidth(this.maxWidth);

  /// The cap; [double.infinity] for [full]. A phone always runs full.
  final double maxWidth;
}

/// Lays [child] on the page grid: the leading gutter, capped at [width],
/// aligned to the start edge. `MadarPageScaffold` applies this to the header
/// and the body when given a `width`; use it directly for a block that must
/// share that edge (a sheet's body, a split view's master column).
class MadarContentFrame extends StatelessWidget {
  const MadarContentFrame({
    required this.child,
    this.width = MadarContentWidth.full,
    this.gutter = true,
    super.key,
  });

  final Widget child;
  final MadarContentWidth width;

  /// Pad the side gutters. Off when an ancestor already did.
  final bool gutter;

  @override
  Widget build(BuildContext context) {
    final layout = MadarLayout.of(context);
    var out = child;
    if (width != MadarContentWidth.full && layout.isTablet) {
      final inner = out;
      // Padding the END, not Align + ConstrainedBox: the child keeps exactly
      // the constraints it would have had (tight stays tight, so a body's
      // Expanded children still fill), only narrower, and on the start edge.
      out = LayoutBuilder(
        builder: (context, c) {
          final spare = c.maxWidth.isFinite
              ? (c.maxWidth - width.maxWidth).clamp(0.0, double.infinity)
              : 0.0;
          return Padding(
            padding: EdgeInsetsDirectional.only(end: spare),
            child: inner,
          );
        },
      );
    }
    if (gutter) {
      out = Padding(
        padding: EdgeInsetsDirectional.symmetric(horizontal: layout.gutter),
        child: out,
      );
    }
    return out;
  }
}
