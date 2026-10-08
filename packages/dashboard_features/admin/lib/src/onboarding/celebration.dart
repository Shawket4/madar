/// "Your café is open! 🎉" (ADM-ONB-024; web `celebration.tsx`): a veil over
/// the whole window with the party glyph and "Taking you to your
/// dashboard…". The falling confetti is a bonus, left out under reduced
/// motion; the card itself always shows.
library;

import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OnbCelebration extends ConsumerWidget {
  const OnbCelebration({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final reduced = DashMotion.reduced(context);
    return Semantics(
      key: const ValueKey('onb-celebration'),
      liveRegion: true,
      container: true,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: Space.xs, sigmaY: Space.xs),
        child: ColoredBox(
          color: c.bg.withValues(alpha: 0.85),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (!reduced) const _Confetti(),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.xl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    spacing: Space.lg,
                    children: [
                      Container(
                        width: Space.xxl * 2 + Space.lg,
                        height: Space.xxl * 2 + Space.lg,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: c.brand.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(Radii.xxl),
                        ),
                        child: DashIcon(
                          'party-popper',
                          size: Space.xxl + Space.sm,
                          color: c.brand,
                        ),
                      ),
                      Text(
                        t('onboarding.celebrate.title'),
                        textAlign: TextAlign.center,
                        style: DashType.pageTitle.copyWith(
                          color: c.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        t('onboarding.celebrate.body'),
                        textAlign: TextAlign.center,
                        style: DashType.body.copyWith(color: c.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 28 pieces falling and spinning once (2.4 s), staggered.
class _Confetti extends StatefulWidget {
  const _Confetti();

  @override
  State<_Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<_Confetti>
    with SingleTickerProviderStateMixin {
  static const int _pieces = 28;
  static const Duration _fall = Duration(milliseconds: 2400);
  static const Duration _stagger = Duration(milliseconds: 140);
  static const Curve _curve = Cubic(0.3, 0.6, 0.4, 1);

  /// The fall plus the longest delay.
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: _fall + _stagger * 6,
  )..forward();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final colors = [c.brand, c.textPrimary, c.success, c.warning];
    final total = _ctrl.duration!.inMilliseconds;
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, box) => AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final now = _ctrl.value * total;
            return Stack(
              children: [
                for (var i = 0; i < _pieces; i++)
                  _piece(i, now, box, colors[i % colors.length]),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _piece(int i, double nowMs, BoxConstraints box, Color color) {
    final delay = (i % 7) * _stagger.inMilliseconds;
    final p = ((nowMs - delay) / _fall.inMilliseconds).clamp(0.0, 1.0);
    final e = _curve.transform(p);
    final start = (i * 3.57) % 100 / 100 * box.maxWidth;
    final y = -Space.md + e * box.maxHeight * 1.1;
    return PositionedDirectional(
      start: start,
      top: y,
      child: Opacity(
        opacity: 1 - 0.15 * e,
        child: Transform.rotate(
          angle: e * 680 * math.pi / 180,
          child: Container(
            width: Space.sm,
            height: Space.sm,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(DashMetrics.hair),
            ),
          ),
        ),
      ),
    );
  }
}
