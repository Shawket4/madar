import 'package:flutter/animation.dart';

/// Motion specs — the natives' MotionSpec (springs tuned to match SwiftUI).
abstract final class MotionSpec {
  /// Buttons, chips, cards — tactile rebound. (damping .72, stiffness 620)
  static final SpringDescription press = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 620,
    ratio: 0.72,
  );

  /// Bottom-sheet / overlay slide. (damping .9, stiffness 300)
  static final SpringDescription sheet = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 300,
    ratio: 0.9,
  );

  /// PIN dots, qty steppers, badges. (medium-bouncy, stiffness 520)
  static final SpringDescription bouncy = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 520,
    ratio: 0.5,
  );

  /// Color, opacity, border, cross-fades: 220 ms ease-out.
  static const Duration standardDuration = Duration(milliseconds: 220);
  static const Curve standardCurve = Curves.easeOut;

  /// Route/tab swaps, slower content fades: 300 ms ease-in-out.
  static const Duration gentleDuration = Duration(milliseconds: 300);
  static const Curve gentleCurve = Curves.easeInOut;

  /// Tactile press scale on buttons/cards.
  static const double pressScale = 0.97;

  /// Deeper press scale on PIN keys.
  static const double pressScaleKey = 0.92;

  /// Skeleton alpha pulse period (reverse-repeating 1 → 0.5).
  static const Duration skeletonPulse = Duration(milliseconds: 900);

  /// Sheet slide-out duration before onDismiss fires.
  static const Duration sheetDismissDelay = Duration(milliseconds: 280);

  /// Overshooting spring-out for celebratory pops (the playful kit: badge
  /// pops, the settle-mark disc, the bump check). Overshoots ~6% then lands.
  static const Curve springOut = Cubic(0.34, 1.56, 0.64, 1);
}
