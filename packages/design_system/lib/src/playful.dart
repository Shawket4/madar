import 'dart:async';
import 'dart:math' as math;

import 'package:design_system/src/brand.dart';
import 'package:design_system/src/icons.dart';
import 'package:design_system/src/tokens/colors.dart';
import 'package:design_system/src/tokens/motion.dart';
import 'package:flutter/material.dart';

// The playful kit — the five brand micro-animations, prototyped in-chat and
// ported 1:1 (same choreography, timings, and spring curves). All pure
// vector (CustomPainter / transforms), so they're theme-aware on both
// palettes for free and cost nothing when idle.
//
//   [SyncGlyph]     — the sync chip / offline banner state glyph
//   [SettleMark]    — the checkout "order settled" celebration
//   [SweepCheck]    — the KDS line bump sweep
//   [BellShake]     — the incoming-order bell ring
//   [Nudge]         — badge pop / cart-catch dip on a counter change
//   [playCartFlight] — the add-to-cart dot arcing into the cart

/// The three connectivity states [SyncGlyph] renders.
enum SyncGlyphState {
  /// Confirmed reachable — closed ring + check, still (motion = activity).
  online,

  /// Outbox draining / health probe in flight — gapped ring, rotating.
  syncing,

  /// Confirmed unreachable — dashed amber ring + slash. Not an error state:
  /// offline-first is a supported mode, hence warning, never danger.
  offline,
}

/// The connectivity state glyph: a ring that is *still* when online (with a
/// check inside), sweeps while syncing, and gets slashed amber when offline.
/// State changes animate (the check draws in on the offline→online edge —
/// a tiny "all caught up" moment).
class SyncGlyph extends StatefulWidget {
  /// Creates the glyph for [state].
  const SyncGlyph({required this.state, this.size = 28, super.key});

  /// Which connectivity state to render.
  final SyncGlyphState state;

  /// Side length; the prototype's proportions scale from here.
  final double size;

  @override
  State<SyncGlyph> createState() => _SyncGlyphState();
}

class _SyncGlyphState extends State<SyncGlyph> with TickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );
  late final AnimationController _breathe = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  );
  late final AnimationController _trans = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
    value: 1,
  );
  SyncGlyphState _prev = SyncGlyphState.online;

  @override
  void initState() {
    super.initState();
    _prev = widget.state;
    _syncLoops();
  }

  @override
  void didUpdateWidget(SyncGlyph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _prev = oldWidget.state;
      unawaited(_trans.forward(from: 0));
      _syncLoops();
    }
  }

  /// Run only the loop the current state needs — an idle glyph must not tick.
  void _syncLoops() {
    if (widget.state == SyncGlyphState.syncing) {
      unawaited(_spin.repeat());
    } else {
      _spin.stop();
    }
    if (widget.state == SyncGlyphState.online) {
      unawaited(_breathe.repeat(reverse: true));
    } else {
      _breathe.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _breathe.dispose();
    _trans.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_spin, _breathe, _trans]),
        builder: (context, _) => CustomPaint(
          size: Size.square(widget.size),
          painter: _SyncGlyphPainter(
            state: widget.state,
            prev: _prev,
            t: Curves.easeOut.transform(_trans.value),
            spin: _spin.value,
            breathe: Curves.easeInOut.transform(_breathe.value),
            accent: colors.accent,
            warning: colors.warning,
          ),
        ),
      ),
    );
  }
}

class _SyncGlyphPainter extends CustomPainter {
  const _SyncGlyphPainter({
    required this.state,
    required this.prev,
    required this.t,
    required this.spin,
    required this.breathe,
    required this.accent,
    required this.warning,
  });

  final SyncGlyphState state;
  final SyncGlyphState prev;
  final double t;
  final double spin;
  final double breathe;
  final Color accent;
  final Color warning;

  Color _tone(SyncGlyphState s) =>
      s == SyncGlyphState.offline ? warning : accent;

  @override
  void paint(Canvas canvas, Size size) {
    // Prototype geometry on a 56-unit viewBox.
    final u = size.width / 56;
    final c = Offset(size.width / 2, size.height / 2);
    final tone = Color.lerp(_tone(prev), _tone(state), t)!;

    // Halo — online only, a very faint slow breathe (opacity .09 → .13).
    if (state == SyncGlyphState.online) {
      canvas.drawCircle(
        c,
        17 * u * (1 + 0.05 * breathe),
        Paint()..color = accent.withValues(alpha: (0.09 + 0.04 * breathe) * t),
      );
    }

    // Ring — full (online), gapped + rotating (syncing), dashed (offline).
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5 * u
      ..strokeCap = StrokeCap.round
      ..color = state == SyncGlyphState.offline
          ? tone.withValues(alpha: 0.6)
          : tone;
    final r = 13 * u;
    final rect = Rect.fromCircle(center: c, radius: r);
    switch (state) {
      case SyncGlyphState.online:
        canvas.drawCircle(c, r, ringPaint);
      case SyncGlyphState.syncing:
        // 58/82 of the circumference, sweeping (the prototype's dash gap).
        final start = spin * 2 * math.pi - math.pi / 2;
        canvas.drawArc(rect, start, 2 * math.pi * (58 / 82), false, ringPaint);
      case SyncGlyphState.offline:
        // Dashed: 4u on / 7u off around the circumference.
        final dashAngle = 4 * u / r;
        final gapAngle = 7 * u / r;
        var angle = -math.pi / 2;
        while (angle < 1.5 * math.pi) {
          canvas.drawArc(rect, angle, dashAngle, false, ringPaint);
          angle += dashAngle + gapAngle;
        }
    }

    // Check — online only; draws itself in on the transition (delay 0.1,
    // then 0.35s of the 0.4s window ≈ the full eased t).
    if (state == SyncGlyphState.online) {
      final check = Path()
        ..moveTo(c.dx - 6 * u, c.dy + 0.5 * u)
        ..lineTo(c.dx - 1.5 * u, c.dy + 5 * u)
        ..lineTo(c.dx + 6.5 * u, c.dy - 4.5 * u);
      final metric = check.computeMetrics().first;
      canvas.drawPath(
        metric.extractPath(0, metric.length * t),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * u
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = accent,
      );
    }

    // Center dot — pulsing while syncing, solid amber while offline.
    if (state == SyncGlyphState.syncing) {
      final pulse = 0.45 + 0.55 * (0.5 + 0.5 * math.sin(spin * 2 * math.pi));
      canvas.drawCircle(
        c,
        4.5 * u,
        Paint()..color = accent.withValues(alpha: pulse * t),
      );
    } else if (state == SyncGlyphState.offline) {
      canvas.drawCircle(
        c,
        4.5 * u,
        Paint()..color = warning.withValues(alpha: t),
      );
    }

    // Slash — offline only, springs in.
    if (state == SyncGlyphState.offline) {
      final s = MotionSpec.springOut.transform(t);
      canvas
        ..save()
        ..translate(c.dx, c.dy)
        ..scale(s)
        ..translate(-c.dx, -c.dy)
        ..drawLine(
          Offset(c.dx - 13 * u, c.dy + 13 * u),
          Offset(c.dx + 13 * u, c.dy - 13 * u),
          Paint()
            ..strokeWidth = 3 * u
            ..strokeCap = StrokeCap.round
            ..color = warning,
        )
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_SyncGlyphPainter old) =>
      old.state != state ||
      old.t != t ||
      old.spin != spin ||
      old.breathe != breathe ||
      old.accent != accent ||
      old.warning != warning;
}

/// The checkout celebration: a teal ring draws closed, then on ONE impact
/// frame the disc floods teal, a white check strikes in, eight sparks
/// scatter, a burst ring exhales, and the whole mark settles with a spring.
/// An optional [label] chip ("Order settled") rises last. Plays once on
/// mount (~1.3s), exactly the approved prototype.
class SettleMark extends StatefulWidget {
  /// Creates the mark; [label] is the localized chip text (null = no chip).
  const SettleMark({this.size = 116, this.label, super.key});

  /// Mark side length; the prototype's proportions scale from here.
  final double size;

  /// Localized chip label shown under the mark (e.g. tr('checkout.settled')).
  final String? label;

  @override
  State<SettleMark> createState() => _SettleMarkState();
}

class _SettleMarkState extends State<SettleMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _play = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..forward();

  @override
  void dispose() {
    _play.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final chipT = CurvedAnimation(
      parent: _play,
      curve: const Interval(0.677, 0.985, curve: Cubic(0.2, 0.8, 0.2, 1)),
    );
    return RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _play,
            builder: (context, _) => CustomPaint(
              size: Size.square(widget.size),
              painter: _SettleMarkPainter(
                p: _play.value,
                accent: colors.accent,
                accentBg: colors.accentBg,
                success: colors.success,
                onAccent: colors.textOnAccent,
              ),
            ),
          ),
          if (widget.label case final label?) ...[
            SizedBox(height: widget.size * 0.1),
            FadeTransition(
              opacity: chipT,
              child: AnimatedBuilder(
                animation: chipT,
                builder: (context, child) => Transform.translate(
                  offset: Offset(0, 8 * (1 - chipT.value)),
                  child: child,
                ),
                child: Container(
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: 14,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: colors.accentBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colors.accent,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SettleMarkPainter extends CustomPainter {
  const _SettleMarkPainter({
    required this.p,
    required this.accent,
    required this.accentBg,
    required this.success,
    required this.onAccent,
  });

  final double p;
  final Color accent;
  final Color accentBg;
  final Color success;
  final Color onAccent;

  /// Per-spark stagger (ms over the 1300ms timeline) — the prototype's.
  static const List<double> _sparkDelays = [0, 40, 10, 60, 20, 50, 0, 40];

  double _seg(double from, double to, [Curve curve = Curves.linear]) {
    if (p <= from) return 0;
    if (p >= to) return 1;
    return curve.transform((p - from) / (to - from));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 120;
    final c = Offset(size.width / 2, size.height / 2);

    // Whole-mark settle: 1 → 1.045 → 1 around the impact frame.
    final settleT = _seg(0.423, 0.808);
    final settle = settleT < 0.4
        ? 1 + 0.045 * Curves.easeOut.transform(settleT / 0.4)
        : 1 + 0.045 * (1 - Curves.easeOut.transform((settleT - 0.4) / 0.6));
    canvas
      ..save()
      ..translate(c.dx, c.dy)
      ..scale(settle)
      ..translate(-c.dx, -c.dy);

    final r = 46 * u;
    final rect = Rect.fromCircle(center: c, radius: r);

    // Track ring fades in first (context for the draw).
    final trackT = _seg(0, 0.115, Curves.easeOut);
    if (trackT > 0) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5 * u
          ..color = accentBg.withValues(alpha: trackT),
      );
    }

    // Burst ring exhales from the impact.
    final burstT = _seg(0.423, 0.885, Curves.easeOut);
    if (burstT > 0 && burstT < 1) {
      canvas.drawCircle(
        c,
        r * (0.9 + 0.5 * burstT),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 * u
          ..color = accent.withValues(alpha: 0.4 * (1 - burstT)),
      );
    }

    // Disc floods teal on the impact frame (spring overshoot).
    final discT = _seg(0.4, 0.746, MotionSpec.springOut);
    if (discT > 0) {
      canvas.drawCircle(c, r * discT, Paint()..color = accent);
    }

    // The ring draws closed from 12 o'clock.
    final ringT = _seg(0.038, 0.423, const Cubic(0.45, 0, 0.2, 1));
    if (ringT > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * ringT,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5 * u
          ..strokeCap = StrokeCap.round
          ..color = accent,
      );
    }

    // Sparks scatter radially — alternating accent/success, staggered.
    for (var i = 0; i < 8; i++) {
      final start = (560 + _sparkDelays[i]) / 1300;
      final sparkT = _seg(start, start + 500 / 1300, Curves.easeOut);
      if (sparkT <= 0 || sparkT >= 1) continue;
      final opacity = sparkT < 0.25
          ? sparkT / 0.25
          : 1 - (sparkT - 0.25) / 0.75;
      final angle = i * math.pi / 4 - math.pi / 2;
      final dist = 45 * u + 11 * u * sparkT;
      canvas.drawCircle(
        c + Offset(math.cos(angle), math.sin(angle)) * dist,
        (i.isEven ? 3 : 2.5) * u,
        Paint()
          ..color = (i.isEven ? accent : success).withValues(alpha: opacity),
      );
    }

    // The check strikes in — white on the flooded disc.
    final checkT = _seg(0.477, 0.692, const Cubic(0.2, 0.8, 0.3, 1));
    if (checkT > 0) {
      final check = Path()
        ..moveTo(c.dx - 20 * u, c.dy + 2 * u)
        ..lineTo(c.dx - 6 * u, c.dy + 16 * u)
        ..lineTo(c.dx + 22 * u, c.dy - 14 * u);
      final metric = check.computeMetrics().first;
      canvas.drawPath(
        metric.extractPath(0, metric.length * checkT),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6.5 * u
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = onAccent,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_SettleMarkPainter old) => old.p != p;
}

/// A KDS bump acknowledgment layered over a line row: a translucent teal
/// band sweeps across (honoring text direction), the row dips to "receive"
/// it, and a check pops at the trailing edge — then the overlay vanishes and
/// the row's own bumped styling takes over. Fast (~700ms): a line cook does
/// this hundreds of times a shift.
class SweepCheck extends StatefulWidget {
  /// Creates the wrapper; bump [play] (monotonically) to run the sweep.
  const SweepCheck({
    required this.child,
    required this.play,
    this.borderRadius,
    super.key,
  });

  /// The line row content.
  final Widget child;

  /// Increment to play the sweep once (0 = never played).
  final int play;

  /// Clip radius for the band (match the row's own radius).
  final BorderRadius? borderRadius;

  @override
  State<SweepCheck> createState() => _SweepCheckState();
}

class _SweepCheckState extends State<SweepCheck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _run = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void didUpdateWidget(SweepCheck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.play > oldWidget.play) unawaited(_run.forward(from: 0));
  }

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return AnimatedBuilder(
      animation: _run,
      builder: (context, child) {
        final t = _run.value;
        if (!_run.isAnimating) return child!;
        final bandT = const Interval(
          0,
          0.64,
          curve: Cubic(0.4, 0, 0.2, 1),
        ).transform(t);
        final dipT = const Interval(0.36, 0.79).transform(t);
        final checkT = MotionSpec.springOut.transform(
          const Interval(0.4, 0.9).transform(t),
        );
        return Transform.translate(
          offset: Offset(0, 3 * math.sin(math.pi * dipT)),
          child: Stack(
            children: [
              child!,
              Positioned.fill(
                child: IgnorePointer(
                  child: ClipRRect(
                    borderRadius: widget.borderRadius ?? BorderRadius.zero,
                    child: Stack(
                      children: [
                        FractionalTranslation(
                          translation: Offset(
                            (rtl ? -1 : 1) * (-1.1 + 2.2 * bandT),
                            0,
                          ),
                          child: ColoredBox(
                            color: colors.accent.withValues(alpha: 0.14),
                            child: const SizedBox.expand(),
                          ),
                        ),
                        if (checkT > 0)
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: Padding(
                              padding: const EdgeInsetsDirectional.only(
                                end: 14,
                              ),
                              child: Transform.scale(
                                scale: checkT,
                                child: MadarIcon(
                                  'checkmark.circle.fill',
                                  tint: colors.success,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Rings its [child] (a bell glyph) when [trigger] increments: a decaying
/// top-pivot shake plus an accent halo exhale behind it. Attention-grabbing
/// once, ignorable after.
class BellShake extends StatefulWidget {
  /// Creates the wrapper; bump [trigger] to ring once.
  const BellShake({required this.child, required this.trigger, super.key});

  /// The bell glyph (any widget — typically a [MadarIcon]).
  final Widget child;

  /// Increment to ring (0 = never).
  final int trigger;

  @override
  State<BellShake> createState() => _BellShakeState();
}

class _BellShakeState extends State<BellShake>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ring = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  @override
  void initState() {
    super.initState();
    // A non-zero trigger at mount means this instance was BORN of an alert
    // (a fresh toast) — ring immediately; didUpdateWidget never fires here.
    if (widget.trigger > 0) unawaited(_ring.forward(from: 0));
  }

  @override
  void didUpdateWidget(BellShake oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger > oldWidget.trigger) unawaited(_ring.forward(from: 0));
  }

  @override
  void dispose() {
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return AnimatedBuilder(
      animation: _ring,
      builder: (context, child) {
        final t = _ring.value;
        if (!_ring.isAnimating) return child!;
        // Decaying swing — the prototype's keyframes (±16° → 0) as a damped
        // sine, pivoting at the bell's crown.
        final angle = 0.30 * math.pow(1 - t, 1.6) * math.sin(t * math.pi * 5);
        final haloT = const Interval(
          0,
          0.85,
          curve: Curves.easeOut,
        ).transform(t);
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            if (haloT < 1)
              Transform.scale(
                scale: 0.5 + haloT,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.accent.withValues(
                      alpha: 0.3 * (1 - haloT),
                    ),
                  ),
                ),
              ),
            Transform.rotate(
              angle: angle,
              alignment: Alignment.topCenter,
              child: child,
            ),
          ],
        );
      },
      child: widget.child,
    );
  }
}

/// How a [Nudge] reacts when its trigger increases.
enum NudgeKind {
  /// A springy scale pop (badge counts).
  pop,

  /// A small downward dip-and-settle (the cart "catching" a flown item).
  dip,
}

/// Nudges its [child] whenever [trigger] INCREASES — a badge pop or a catch
/// dip. Decreases stay still (removing a cart line is not a celebration).
class Nudge extends StatefulWidget {
  /// Creates the wrapper.
  const Nudge({
    required this.child,
    required this.trigger,
    this.kind = NudgeKind.pop,
    super.key,
  });

  /// The badge / icon to nudge.
  final Widget child;

  /// Play once each time this increases.
  final int trigger;

  /// Pop (scale) or dip (translate).
  final NudgeKind kind;

  @override
  State<Nudge> createState() => _NudgeState();
}

class _NudgeState extends State<Nudge> with SingleTickerProviderStateMixin {
  late final AnimationController _play = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );

  @override
  void didUpdateWidget(Nudge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger > oldWidget.trigger) unawaited(_play.forward(from: 0));
  }

  @override
  void dispose() {
    _play.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _play,
      builder: (context, child) {
        if (!_play.isAnimating) return child!;
        final wave = math.sin(
          math.pi * Curves.easeOut.transform(_play.value),
        );
        return switch (widget.kind) {
          NudgeKind.pop => Transform.scale(
            scale: 1 + 0.22 * wave,
            child: child,
          ),
          NudgeKind.dip => Transform.translate(
            offset: Offset(0, 3 * wave),
            child: child,
          ),
        };
      },
      child: widget.child,
    );
  }
}

/// Flies a small accent dot from [from] to [to] (global coordinates) along a
/// parabolic arc — the add-to-cart flight. Inserts a transient overlay entry;
/// [onArrive] fires when the dot lands (pair it with a [Nudge] dip on the
/// cart). No-ops straight to [onArrive] when no overlay is available.
void playCartFlight(
  BuildContext context, {
  required Offset from,
  required Offset to,
  double dotSize = 9,
  Color? color,
  VoidCallback? onArrive,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) {
    onArrive?.call();
    return;
  }
  final dotColor = color ?? context.madarColors.accent;
  final controller = AnimationController(
    vsync: overlay,
    duration: const Duration(milliseconds: 450),
  );
  const xCurve = Cubic(0.3, 0.5, 0.5, 1);
  final arc = math.max<double>(40, (to - from).distance * 0.22);
  final entry = OverlayEntry(
    builder: (context) => AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = controller.value;
        final x = from.dx + (to.dx - from.dx) * xCurve.transform(t);
        final y = from.dy + (to.dy - from.dy) * t - arc * 4 * t * (1 - t);
        final opacity = t > 0.85 ? (1 - t) / 0.15 : 1.0;
        return Positioned(
          left: x - dotSize / 2,
          top: y - dotSize / 2,
          child: IgnorePointer(
            child: Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dotColor.withValues(alpha: opacity),
              ),
            ),
          ),
        );
      },
    ),
  );
  overlay.insert(entry);
  unawaited(
    controller.forward().whenComplete(() {
      entry.remove();
      controller.dispose();
      onArrive?.call();
    }),
  );
}

/// The queued-offline confirmation mark: the amber clock, alive. An amber
/// disc springs in once, then the clock LOOPS — the minute hand sweeps, the
/// hour hand creeps, and a soft halo breathes — "your order is placed and
/// waiting to sync". The looping counterpart of the one-shot [SettleMark].
class QueuedMark extends StatefulWidget {
  /// Creates the mark; proportions scale from [size].
  const QueuedMark({this.size = 88, super.key});

  /// Mark side length.
  final double size;

  @override
  State<QueuedMark> createState() => _QueuedMarkState();
}

class _QueuedMarkState extends State<QueuedMark> with TickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  )..forward();
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  @override
  void dispose() {
    _enter.dispose();
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_enter, _loop]),
        builder: (context, _) => CustomPaint(
          size: Size.square(widget.size),
          painter: _QueuedMarkPainter(
            enter: MotionSpec.springOut.transform(_enter.value),
            loop: _loop.value,
            warning: colors.warning,
            warningBg: colors.warningBg,
          ),
        ),
      ),
    );
  }
}

class _QueuedMarkPainter extends CustomPainter {
  const _QueuedMarkPainter({
    required this.enter,
    required this.loop,
    required this.warning,
    required this.warningBg,
  });

  final double enter;
  final double loop;
  final Color warning;
  final Color warningBg;

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 120;
    final c = Offset(size.width / 2, size.height / 2);
    final wave = 0.5 + 0.5 * math.sin(loop * 2 * math.pi);

    // Breathing halo (the "waiting" pulse), then the amber disc springing in
    // once with the face ring riding its edge.
    canvas
      ..drawCircle(
        c,
        (52 + 4 * wave) * u * enter.clamp(0, 1),
        Paint()..color = warning.withValues(alpha: 0.10 + 0.05 * wave),
      )
      ..drawCircle(c, 46 * u * enter, Paint()..color = warningBg)
      ..drawCircle(
        c,
        46 * u * enter,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4 * u
          ..color = warning,
      );
    if (enter < 0.6) return;

    // Clock hands — minute sweeps a revolution per loop, hour creeps.
    final handPaint = Paint()
      ..strokeWidth = 5 * u
      ..strokeCap = StrokeCap.round
      ..color = warning;
    final minuteAngle = loop * 2 * math.pi - math.pi / 2;
    final hourAngle = (loop / 12 + 0.72) * 2 * math.pi - math.pi / 2;
    canvas
      ..drawLine(
        c,
        c + Offset(math.cos(minuteAngle), math.sin(minuteAngle)) * 30 * u,
        handPaint,
      )
      ..drawLine(
        c,
        c + Offset(math.cos(hourAngle), math.sin(hourAngle)) * 19 * u,
        handPaint..strokeWidth = 6 * u,
      )
      ..drawCircle(c, 4.5 * u, Paint()..color = warning);
  }

  @override
  bool shouldRepaint(_QueuedMarkPainter old) =>
      old.enter != enter || old.loop != loop;
}

/// The animated brand lockup — the Madar symbol RECREATED in vector (ink
/// orbit ring, fused satellite, teal planet) so the mark itself is alive:
/// the satellite rides the ring on a slow revolution while the planet
/// breathes and exhales a faint teal ring and the satellite twinkles (the
/// picked "quiet pulse × living orbit" mix). The typed wordmark sits
/// beneath. Theme-aware like the PNG marks (ink ↔ paper).
class AnimatedBrandMark extends StatefulWidget {
  /// Creates the mark.
  const AnimatedBrandMark({
    this.symbolSize = 36,
    this.wordmarkWidth = 56,
    super.key,
  });

  /// Side length of the recreated Madar symbol.
  final double symbolSize;

  /// Width of the typed wordmark under it.
  final double wordmarkWidth;

  @override
  State<AnimatedBrandMark> createState() => _AnimatedBrandMarkState();
}

class _AnimatedBrandMarkState extends State<AnimatedBrandMark>
    with TickerProviderStateMixin {
  late final AnimationController _orbit = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..repeat();
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3500),
  )..repeat();

  @override
  void dispose() {
    _orbit.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: Listenable.merge([_orbit, _pulse]),
            builder: (context, _) => CustomPaint(
              size: Size.square(widget.symbolSize),
              painter: _BrandMarkPainter(
                orbit: _orbit.value,
                pulse: _pulse.value,
                // textPrimary mirrors the PNG marks: ink on paper, paper
                // on ink — the reversed variant for free.
                ink: colors.textPrimary,
                accent: colors.accent,
              ),
            ),
          ),
          const SizedBox(height: 4),
          MadarWordmark(width: widget.wordmarkWidth),
        ],
      ),
    );
  }
}

class _BrandMarkPainter extends CustomPainter {
  const _BrandMarkPainter({
    required this.orbit,
    required this.pulse,
    required this.ink,
    required this.accent,
  });

  final double orbit;
  final double pulse;
  final Color ink;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    // The PNG symbol's proportions on a 120-unit viewBox.
    final u = size.width / 120;
    final c = Offset(size.width / 2, size.height / 2);
    final wave = 0.5 - 0.5 * math.cos(pulse * 2 * math.pi);

    // Orbit ring.
    canvas.drawCircle(
      c,
      44 * u,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10 * u
        ..color = ink,
    );

    // The fused satellite rides the ring (starts at the mark's 1-o'clock)
    // and twinkles gently as it goes.
    final angle = -math.pi / 4 + orbit * 2 * math.pi;
    canvas.drawCircle(
      c + Offset(math.cos(angle), math.sin(angle)) * 44 * u,
      13 * u,
      Paint()..color = ink.withValues(alpha: 1 - 0.45 * wave),
    );

    // The planet exhales a faint teal ring (stays inside the orbit)…
    final emitT = Curves.easeOut.transform((pulse / 0.7).clamp(0, 1));
    if (emitT < 1) {
      canvas.drawCircle(
        c,
        (16 + 18 * emitT) * u,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * u
          ..color = accent.withValues(alpha: 0.5 * (1 - emitT)),
      );
    }

    // …and breathes.
    canvas.drawCircle(
      c,
      16 * u * (1 + 0.1 * wave),
      Paint()..color = accent,
    );
  }

  @override
  bool shouldRepaint(_BrandMarkPainter old) =>
      old.orbit != orbit ||
      old.pulse != pulse ||
      old.ink != ink ||
      old.accent != accent;
}
