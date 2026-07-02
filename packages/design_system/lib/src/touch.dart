import 'dart:async';

import 'package:design_system/src/tokens/motion.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Centralized tactile feedback — the Flutter mirror of the natives'
/// `Haptics.kt` / `PressableScale.swift`.
///
/// One vocabulary for the whole app so every press surface buzzes
/// consistently instead of each call site hand-picking a feedback type
/// (or, worse, firing none). Unlike Compose 1.7 (which folds all four
/// events onto two `HapticFeedbackType`s), Flutter exposes the full
/// platform impact range, so each semantic event maps to its closest
/// native equivalent. No-ops on platforms without haptic hardware.
abstract final class MadarHaptics {
  /// Light tick — chips, toggles, PIN keys, selection changes.
  static void selection() => unawaited(HapticFeedback.selectionClick());

  /// Medium thud — primary actions: add to cart, place order, confirm.
  static void impact() => unawaited(HapticFeedback.mediumImpact());

  /// Positive confirmation — order placed, shift opened, sale finalized.
  static void success() => unawaited(HapticFeedback.mediumImpact());

  /// Error nudge — failed validation, blocked action, max reached.
  static void warning() => unawaited(HapticFeedback.heavyImpact());
}

/// Tactile press scale — springs the [child] down to [scale] on
/// pointer-down and rebounds on release/cancel, using the shared
/// [MotionSpec.press] spring so buttons, chips, and cards recoil with
/// the same feel as the Kotlin/Swift natives.
///
/// When [onTap] is null this is purely decorative: a [Listener] tracks
/// the pointer without entering the gesture arena, so the child's own
/// gestures (sliders, ink wells, drags) are never blocked. When [onTap]
/// is provided, a [GestureDetector] handles the tap.
class TactileScale extends StatefulWidget {
  /// Creates a tactile press-scale wrapper around [child].
  const TactileScale({
    required this.child,
    this.scale = MotionSpec.pressScale,
    this.onTap,
    this.haptic = true,
    super.key,
  });

  /// The pressable content.
  final Widget child;

  /// Scale while pressed. Defaults to [MotionSpec.pressScale]; pass
  /// [MotionSpec.pressScaleKey] for the deeper PIN-key press.
  final double scale;

  /// Optional tap handler. When null the wrapper never competes for the
  /// tap gesture — the child keeps full control of its own gestures.
  final VoidCallback? onTap;

  /// Whether to fire [MadarHaptics.selection] on pointer-down.
  final bool haptic;

  @override
  State<TactileScale> createState() => _TactileScaleState();
}

class _TactileScaleState extends State<TactileScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _springTo(double target) {
    unawaited(
      _controller.animateWith(
        SpringSimulation(
          MotionSpec.press,
          _controller.value,
          target,
          _controller.velocity,
        ),
      ),
    );
  }

  void _handleDown(PointerDownEvent _) {
    if (widget.haptic) MadarHaptics.selection();
    _springTo(widget.scale);
  }

  void _handleUp(PointerUpEvent _) => _springTo(1);

  void _handleCancel(PointerCancelEvent _) => _springTo(1);

  @override
  Widget build(BuildContext context) {
    final pressable = Listener(
      onPointerDown: _handleDown,
      onPointerUp: _handleUp,
      onPointerCancel: _handleCancel,
      behavior: HitTestBehavior.translucent,
      child: ScaleTransition(
        scale: _controller,
        child: widget.child,
      ),
    );
    final onTap = widget.onTap;
    if (onTap == null) return pressable;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: pressable,
    );
  }
}
