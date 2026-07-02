import 'dart:async';

import 'package:design_system/src/responsive.dart';
import 'package:design_system/src/tokens/colors.dart';
import 'package:design_system/src/tokens/dimens.dart';
import 'package:design_system/src/tokens/motion.dart';
import 'package:flutter/widgets.dart';

/// Provides one shared pulse [Animation] to every descendant
/// [SkeletonBlock], so a whole loading screen ticks off a single
/// [AnimationController] instead of one per block.
///
/// [SkeletonList] installs a scope automatically; wrap custom skeleton
/// layouts in a [SkeletonScope] to get the same single-ticker behavior.
/// Blocks without a scope fall back to a controller of their own.
class SkeletonScope extends StatefulWidget {
  /// Creates a scope whose descendants share one skeleton pulse ticker.
  const SkeletonScope({required this.child, super.key});

  /// The subtree that may contain [SkeletonBlock]s.
  final Widget child;

  /// The shared pulse animation (1.0 → 0.5, reverse-repeating), or null
  /// when no enclosing [SkeletonScope] exists.
  static Animation<double>? maybePulseOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SkeletonPulse>()?.animation;

  @override
  State<SkeletonScope> createState() => _SkeletonScopeState();
}

class _SkeletonScopeState extends State<SkeletonScope>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: MotionSpec.skeletonPulse,
  )..repeat(reverse: true);

  late final Animation<double> _pulse = _controller.drive(
    Tween<double>(
      begin: 1,
      end: 0.5,
    ).chain(CurveTween(curve: Curves.fastOutSlowIn)),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SkeletonPulse(animation: _pulse, child: widget.child);
  }
}

class _SkeletonPulse extends InheritedWidget {
  const _SkeletonPulse({required this.animation, required super.child});

  final Animation<double> animation;

  @override
  bool updateShouldNotify(_SkeletonPulse oldWidget) =>
      animation != oldWidget.animation;
}

/// A single rounded placeholder bar that gently pulses — mirrors the
/// natives' SkeletonBlock. Shown while content loads, in place of a bare
/// spinner.
///
/// The alpha pulses 1.0 → 0.5 and back over [MotionSpec.skeletonPulse].
/// When a [SkeletonScope] (or [SkeletonList]) is an ancestor, all blocks
/// share its single ticker; otherwise the block drives its own.
class SkeletonBlock extends StatefulWidget {
  /// Creates a pulsing placeholder bar.
  const SkeletonBlock({
    this.width,
    this.height = 13,
    this.corner = 6,
    super.key,
  });

  /// Fixed width, or null to let the parent decide.
  final double? width;

  /// Bar height in logical pixels.
  final double height;

  /// Corner radius of the rounded rect.
  final double corner;

  @override
  State<SkeletonBlock> createState() => _SkeletonBlockState();
}

class _SkeletonBlockState extends State<SkeletonBlock>
    with SingleTickerProviderStateMixin {
  AnimationController? _ownController;
  Animation<double>? _ownPulse;

  Animation<double> _pulse(BuildContext context) {
    final shared = SkeletonScope.maybePulseOf(context);
    if (shared != null) {
      _ownController?.dispose();
      _ownController = null;
      _ownPulse = null;
      return shared;
    }
    var controller = _ownController;
    if (controller == null) {
      controller = AnimationController(
        vsync: this,
        duration: MotionSpec.skeletonPulse,
      );
      unawaited(controller.repeat(reverse: true));
      _ownController = controller;
    }
    return _ownPulse ??= controller.drive(
      Tween<double>(
        begin: 1,
        end: 0.5,
      ).chain(CurveTween(curve: Curves.fastOutSlowIn)),
    );
  }

  @override
  void dispose() {
    _ownController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return RepaintBoundary(
      child: FadeTransition(
        opacity: _pulse(context),
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(widget.corner),
            ),
          ),
        ),
      ),
    );
  }
}

/// A card-shaped skeleton standing in for one list row: two stacked bars
/// on the leading side, one short bar on the trailing side.
class SkeletonRow extends StatelessWidget {
  /// Creates a card-shaped skeleton row.
  const SkeletonRow({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: colors.border),
      ),
      child: const Padding(
        padding: EdgeInsets.all(Space.md),
        child: Row(
          spacing: Space.md,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Space.sm,
                children: [
                  SkeletonBlock(width: 130, height: 14),
                  SkeletonBlock(width: 80, height: 11),
                ],
              ),
            ),
            SkeletonBlock(width: 56, height: 14),
          ],
        ),
      ),
    );
  }
}

/// A column of [count] skeleton rows — the loading state for a list
/// screen. Capped at [Responsive.listMaxWidth]; all rows pulse in sync
/// off one shared ticker.
class SkeletonList extends StatelessWidget {
  /// Creates a list-loading skeleton of [count] rows.
  const SkeletonList({this.count = 6, super.key});

  /// How many placeholder rows to show.
  final int count;

  @override
  Widget build(BuildContext context) {
    return SkeletonScope(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Responsive.listMaxWidth),
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            spacing: Space.sm,
            children: [
              for (var i = 0; i < count; i++) const SkeletonRow(),
            ],
          ),
        ),
      ),
    );
  }
}
