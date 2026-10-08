/// The live mirror (ADM-ONB-025..028; web `dashboard-mirror.tsx`): a compact
/// preview of the real dashboard whose tiles light up from the org's own
/// set-up as the wizard goes — a locked dashed tile with "—" until a step is
/// done, then a card whose count climbs from its last value; the recipe cost
/// ring; and the sales tile that unlocks with the first order. Under reduced
/// motion everything is static.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:dashboard_api/dashboard_api.dart' show OnboardingStep;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'onboarding_config.dart';
import 'onboarding_data.dart';
import 'org_identity_step.dart' show OnbImage;
import 'step_panel.dart' show OnbDashedBorder;

class OnbDashboardMirror extends ConsumerWidget {
  const OnbDashboardMirror({
    required this.orgId,
    required this.byKey,
    required this.recipeCoverage,
    super.key,
  });

  final String orgId;
  final Map<String, OnboardingStep> byKey;
  final double recipeCoverage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final org = ref.watch(onbOrgProvider(orgId)).value;
    final profileDone = byKey['org_profile']?.done ?? false;
    final logo = org?.logoUrl;
    final name = org?.name.trim() ?? '';
    final cols = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm ? 3 : 2;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: c.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.card,
              vertical: Space.lg,
            ),
            decoration: BoxDecoration(
              color: c.muted.withValues(alpha: 0.4),
              border: Border(bottom: BorderSide(color: c.hairline)),
            ),
            child: Row(
              spacing: Space.md,
              children: [
                SizedBox.square(
                  dimension: Space.xxl + Space.xs,
                  child: logo != null && logo.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(Radii.xs),
                          child: OnbImage(url: logo),
                        )
                      : DecoratedBox(
                          decoration: BoxDecoration(
                            color: profileDone
                                ? c.brand.withValues(alpha: 0.1)
                                : c.muted,
                            borderRadius: BorderRadius.circular(Radii.xs),
                          ),
                          child: Center(
                            child: DashIcon(
                              'store',
                              size: IconSize.lg,
                              color: profileDone ? c.brand : c.textSecondary,
                            ),
                          ),
                        ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MadarClippedText(
                        name.isNotEmpty
                            ? name
                            : t('onboarding.mirror.yourCafe'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DashType.bodyStrong.copyWith(
                          color: c.textPrimary,
                        ),
                      ),
                      Text(
                        t('onboarding.mirror.dashboard'),
                        style: DashType.small.copyWith(color: c.textSecondary),
                      ),
                    ],
                  ),
                ),
                Text(
                  t('onboarding.mirror.preview'),
                  style: DashType.small.copyWith(color: c.textSecondary),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Space.card),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.lg,
              children: [
                Column(
                  spacing: Space.md,
                  children: [
                    for (var i = 0; i < mirrorTiles.length; i += cols)
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: Space.md,
                          children: [
                            for (var j = i; j < i + cols; j++)
                              Expanded(
                                child: j < mirrorTiles.length
                                    ? _MirrorTile(
                                        spec: mirrorTiles[j],
                                        step: byKey[mirrorTiles[j].statusKey],
                                      )
                                    : const SizedBox.shrink(),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
                _CoverageRing(ratio: recipeCoverage),
                _SalesTile(done: byKey['first_order']?.done ?? false),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

({Color bg, Color fg}) _accent(MirrorAccent a, MadarColors c) => switch (a) {
  MirrorAccent.primary => (
    bg: c.textPrimary.withValues(alpha: 0.1),
    fg: c.textPrimary,
  ),
  MirrorAccent.brand => (bg: c.brand.withValues(alpha: 0.1), fg: c.brand),
  MirrorAccent.info => (
    bg: DashTone.info.wash(c),
    fg: DashTone.info.foreground(c),
  ),
  MirrorAccent.success => (
    bg: DashTone.success.wash(c),
    fg: DashTone.success.foreground(c),
  ),
  MirrorAccent.warning => (
    bg: DashTone.warning.wash(c),
    fg: DashTone.warning.foreground(c),
  ),
};

/// A locked "—" tile until the step is done, then a live card.
class _MirrorTile extends ConsumerWidget {
  const _MirrorTile({required this.spec, required this.step});

  final MirrorTileSpec spec;
  final OnboardingStep? step;

  static final TextStyle _figure = MadarType.h2.copyWith(
    fontSize: Space.xl,
    fontWeight: FontWeight.w600,
    height: 1.2,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final label = t(spec.labelKey);
    final live = step?.done ?? false;
    if (!live) {
      return CustomPaint(
        key: ValueKey('onb-tile-${spec.statusKey}-locked'),
        foregroundPainter: OnbDashedBorder(
          color: c.input.withValues(alpha: 0.7),
          radius: Radii.md,
        ),
        child: Container(
          padding: const EdgeInsets.all(Space.lg),
          decoration: BoxDecoration(
            color: c.muted.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.sm,
            children: [
              DashIcon('lock', size: IconSize.sm, color: c.textSecondary),
              Text(
                label,
                style: DashType.smallMedium.copyWith(color: c.textSecondary),
              ),
              Text(
                '—',
                style: _figure.copyWith(
                  color: c.textSecondary.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final accent = _accent(spec.accent, c);
    return _Reveal(
      child: Container(
        key: ValueKey('onb-tile-${spec.statusKey}-live'),
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: c.brand.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.sm,
          children: [
            Container(
              width: Space.xxl,
              height: Space.xxl,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.bg,
                borderRadius: BorderRadius.circular(Radii.xs),
              ),
              child: DashIcon(spec.icon, size: IconSize.sm, color: accent.fg),
            ),
            Text(
              label,
              style: DashType.smallMedium.copyWith(color: c.textSecondary),
            ),
            OnbAnimatedCount(
              value: step?.count ?? 0,
              style: _figure.copyWith(color: c.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

/// A count that climbs from its previous value to [value] over ~1 s (eased
/// out); instant under reduced motion. It starts at [value] (no climb on
/// first paint).
class OnbAnimatedCount extends StatefulWidget {
  const OnbAnimatedCount({required this.value, this.style, super.key});

  final int value;
  final TextStyle? style;

  @override
  State<OnbAnimatedCount> createState() => _OnbAnimatedCountState();
}

class _OnbAnimatedCountState extends State<OnbAnimatedCount>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: countAnimation,
  );
  late int _from = widget.value;
  late int _shown = widget.value;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() {
      final p = Curves.easeOutCubic.transform(_ctrl.value);
      setState(() => _shown = (_from + (widget.value - _from) * p).round());
    });
  }

  @override
  void didUpdateWidget(OnbAnimatedCount old) {
    super.didUpdateWidget(old);
    if (old.value == widget.value) return;
    if (DashMotion.reduced(context)) {
      _ctrl.stop();
      setState(() => _shown = widget.value);
      return;
    }
    _from = _shown;
    _ctrl.forward(from: 0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('$_shown', style: widget.style);
}

/// The tile "pops" in when it lights up (a springy rise); static under
/// reduced motion. The resting state is the visible one.
class _Reveal extends StatefulWidget {
  const _Reveal({required this.child});

  final Widget child;

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );
  Timer? _start;

  static const Curve _spring = Cubic(0.34, 1.56, 0.64, 1);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ctrl.isAnimating || _ctrl.value == 1 || _start != null) return;
    if (DashMotion.reduced(context)) {
      _ctrl.value = 1;
    } else {
      _start = Timer(const Duration(milliseconds: 20), _ctrl.forward);
    }
  }

  @override
  void dispose() {
    _start?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _ctrl,
    child: widget.child,
    builder: (context, child) {
      final p = _spring.transform(_ctrl.value);
      final opacity = _ctrl.value.clamp(0.0, 1.0);
      return Opacity(
        opacity: opacity,
        child: Transform.translate(
          offset: Offset(0, Space.sm * (1 - p)),
          child: Transform.scale(scale: 0.9 + 0.1 * p, child: child),
        ),
      );
    },
  );
}

/// Recipe cost coverage (0..1): the ring and "NN%".
class _CoverageRing extends ConsumerWidget {
  const _CoverageRing({required this.ratio});

  final double ratio;

  static const double _size = 76;
  static const double _stroke = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final clamped = ratio.isNaN ? 0.0 : ratio.clamp(0.0, 1.0);
    final pct = (clamped * 100).round();
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Container(
      key: const ValueKey('onb-coverage'),
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.hairline),
      ),
      child: Row(
        spacing: Space.lg,
        children: [
          ExcludeSemantics(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: clamped),
              duration: DashMotion.of(
                context,
                const Duration(milliseconds: 700),
              ),
              curve: Curves.easeOut,
              builder: (context, f, _) => CustomPaint(
                size: const Size.square(_size),
                painter: _RingPainter(
                  fraction: f,
                  track: c.muted,
                  fill: c.brand,
                  stroke: _stroke,
                  mirrored: rtl,
                ),
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t('onboarding.mirror.coverage'),
                  style: DashType.bodyStrong.copyWith(color: c.textPrimary),
                ),
                Text(
                  t('onboarding.mirror.coverageHint'),
                  style: DashType.small.copyWith(color: c.textSecondary),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: Space.xs),
                  child: Text(
                    '$pct%',
                    style: MadarType.h3.copyWith(
                      color: c.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.fraction,
    required this.track,
    required this.fill,
    required this.stroke,
    required this.mirrored,
  });

  final double fraction;
  final Color track;
  final Color fill;
  final double stroke;

  /// Right-to-left: the fill runs the other way round.
  final bool mirrored;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    if (fraction <= 0) return;
    final sweep = math.pi * 2 * fraction;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      mirrored ? -sweep : sweep,
      false,
      Paint()
        ..color = fill
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction ||
      old.track != track ||
      old.fill != fill ||
      old.mirrored != mirrored;
}

/// "Today's sales": locked until the first order, then a small bar chart.
class _SalesTile extends ConsumerWidget {
  const _SalesTile({required this.done});

  final bool done;

  static const List<double> _bars = [0.4, 0.65, 0.5, 0.8, 0.55, 0.7, 0.45];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    if (!done) {
      return CustomPaint(
        key: const ValueKey('onb-sales-locked'),
        foregroundPainter: OnbDashedBorder(
          color: c.input.withValues(alpha: 0.7),
          radius: Radii.md,
        ),
        child: Container(
          padding: const EdgeInsets.all(Space.lg),
          decoration: BoxDecoration(
            color: c.muted.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Row(
            spacing: Space.md,
            children: [
              DashIcon('lock', size: IconSize.sm, color: c.textSecondary),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      t('onboarding.mirror.sales'),
                      style: DashType.smallMedium.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                    Text(
                      t('onboarding.mirror.salesLocked'),
                      style: DashType.small.copyWith(color: c.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    final success = DashTone.success.foreground(c);
    return _Reveal(
      child: Container(
        key: const ValueKey('onb-sales-live'),
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: c.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.md,
          children: [
            Row(
              spacing: Space.sm,
              children: [
                Expanded(
                  child: Text(
                    t('onboarding.mirror.sales'),
                    style: DashType.smallMedium.copyWith(
                      color: c.textSecondary,
                    ),
                  ),
                ),
                DashIcon('sparkles', size: IconSize.xs, color: success),
                Text(
                  t('onboarding.mirror.firstSale'),
                  style: DashType.smallMedium.copyWith(color: success),
                ),
              ],
            ),
            ExcludeSemantics(
              child: SizedBox(
                height: Space.xxl * 2,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  spacing: Space.xs + DashMetrics.hair,
                  children: [
                    for (final h in _bars)
                      Expanded(
                        child: FractionallySizedBox(
                          heightFactor: h,
                          alignment: Alignment.bottomCenter,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: c.brand.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(
                                DashMetrics.hair,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
