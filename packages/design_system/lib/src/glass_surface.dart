/// A chrome surface that wears iOS 26's real Liquid Glass where the device
/// has it, and an ordinary painted surface everywhere else.
///
/// The glass is Apple's, drawn by SwiftUI through a platform view — not a
/// blur-and-highlight imitation in Flutter. That is the whole point: an
/// imitation on Android or on iOS 18 is a Flutter app pretending to be an OS,
/// and it reads as one.
///
/// It is used on the RAIL and nowhere else, deliberately. A platform view is
/// expensive on iOS (hybrid composition puts the whole Flutter surface into a
/// different compositing path) and it has a documented z-order problem where
/// its pixels bleed through a sheet drawn above it. The rail is one view, it
/// lives for the life of the app rather than being created per screen, and
/// the sheets in this app are the surfaces most likely to sit over it — which
/// is exactly why they stay painted, not glass.
library;

import 'package:cupertino_native_better/cupertino_native.dart';
import 'package:design_system/src/glass.dart';
import 'package:flutter/widgets.dart';

/// The navigator observer the glass needs to behave under a sheet.
///
/// A platform view is composited by iOS, not by Flutter, so its pixels can
/// bleed through a route drawn above it. The plugin tears the native view
/// down while a modal is up — but only if it can see the route change, which
/// is what this reports. Register it in the app's `navigatorObservers`; it is
/// inert on every platform that has no glass.
NavigatorObserver glassRouteObserver() => CNTabBarRouteObserver();

/// Wraps [child] in native glass when [MadarGlass.isAvailable], and in a
/// plain [ColoredBox] of [fallback] otherwise.
class MadarGlassSurface extends StatelessWidget {
  /// Creates the surface.
  const MadarGlassSurface({
    required this.child,
    required this.fallback,
    this.borderRadius = 0,
    super.key,
  });

  /// The content drawn over the surface.
  final Widget child;

  /// The colour painted when this device has no glass — which is most of
  /// them. The screen must be complete in this form; glass is never the
  /// only way a surface exists.
  final Color fallback;

  /// Corner radius of the glass shape, and of nothing else: the fallback is
  /// a flat fill, because a rounded rail on Android is not a consolation
  /// prize for missing glass, it is a different design.
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    if (!MadarGlass.isAvailable) {
      return ColoredBox(color: fallback, child: child);
    }
    return LiquidGlassContainer(
      config: LiquidGlassConfig(
        shape: CNGlassEffectShape.rect,
        cornerRadius: borderRadius,
      ),
      child: child,
    );
  }
}
