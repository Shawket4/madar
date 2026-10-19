/// The Setup page's opening (web `setup-page.tsx` `Hero`), on the ink panel
/// of the sidebar: a welcome while there is setting up to do, "ready to
/// sell" once nothing blocks, "live" after the first sale. Each shows the
/// app family, the till first: the apps are how a shop actually sells.
///
/// Brand register: a longer entrance than the product's (the words rise in
/// turn, the pips fill one by one, a dot travels the orbit once, and ready /
/// live pop a check). It replays when the stage changes, never delays a
/// control (everything is tappable from the first frame) and is still under
/// reduced motion.
library;

import 'dart:math' as math;

import 'package:dashboard_api/dashboard_api.dart'
    show Readiness, ReadinessCheck;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../apps/app_tiles.dart';
import '../apps/apps.dart';
import 'checks.dart';

class SetupHero extends ConsumerStatefulWidget {
  const SetupHero({
    required this.readiness,
    required this.stage,
    required this.shopName,
    super.key,
  });

  final Readiness readiness;
  final SetupStage stage;
  final String shopName;

  @override
  ConsumerState<SetupHero> createState() => _SetupHeroState();
}

class _SetupHeroState extends ConsumerState<SetupHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _play = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (DashMotion.reduced(context)) {
      _play.value = 1;
    } else if (!_play.isAnimating && _play.value == 0) {
      _play.forward();
    }
  }

  @override
  void didUpdateWidget(SetupHero old) {
    super.didUpdateWidget(old);
    // A new stage is a new moment: play it again.
    if (old.stage != widget.stage && !DashMotion.reduced(context)) {
      _play.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _play.dispose();
    super.dispose();
  }

  /// [child] fading in and rising, over [from]..[to] of the entrance.
  Widget _rise(double from, double to, Widget child) {
    final a = CurvedAnimation(
      parent: _play,
      curve: Interval(from, to, curve: DashMotion.ease),
    );
    return FadeTransition(
      opacity: a,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.25),
          end: Offset.zero,
        ).animate(a),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    final r = widget.readiness;
    final stage = widget.stage;
    final teal = MadarColors.dark.brand;
    final shop = widget.shopName.isEmpty
        ? t('setup.hero.yourShop')
        : widget.shopName;
    final (eyebrow, title, body) = switch (stage) {
      SetupStage.ready => (
        t('setup.hero.readyEyebrow'),
        t('setup.hero.readyTitle', args: {'shop': shop}),
        t('setup.hero.readyBody'),
      ),
      SetupStage.live => (
        t('setup.hero.liveEyebrow'),
        t('setup.hero.liveTitle', args: {'shop': shop}),
        t(
          'setup.hero.liveBody',
          args: {'date': fmt.fmtDate(r.firstOrderAt?.toIso8601String())},
        ),
      ),
      _ => (
        t('setup.hero.welcome'),
        t('setup.hero.setupTitle', args: {'shop': shop}),
        t('setup.hero.setupBody', count: leftToDo(r)),
      ),
    };
    final w = MediaQuery.sizeOf(context).width;
    final phone = DashBreakpoints.isPhoneWidth(w);
    final celebrate = stage == SetupStage.ready || stage == SetupStage.live;

    final tiles = [
      for (final app in madarFamily)
        AppTile(
          app,
          size: AppTileSize.large,
          lead: app == MadarApp.cashier && stage == SetupStage.setup
              ? t('apps.startHere')
              : null,
        ),
    ];

    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Container(
        key: const ValueKey('setup-hero'),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.chrome,
          borderRadius: BorderRadius.circular(Radii.sheet),
          // On a dark page the ink panel needs its edge.
          border: Border.all(color: c.onChrome.withValues(alpha: 0.06)),
        ),
        child: Stack(
          children: [
            PositionedDirectional(
              top: -96,
              end: -96,
              width: 320,
              height: 320,
              child: ExcludeSemantics(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _Orbit(
                      progress: CurvedAnimation(
                        parent: _play,
                        curve: const Interval(
                          0.1,
                          1,
                          curve: Curves.easeInOutCubic,
                        ),
                      ),
                      line: c.onChrome.withValues(alpha: 0.08),
                      dot: teal,
                      rtl: t.isRtl,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(phone ? Space.xl : Space.xxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _rise(
                    0,
                    0.35,
                    Row(
                      spacing: Space.sm,
                      children: [
                        if (celebrate)
                          ScaleTransition(
                            scale: CurvedAnimation(
                              parent: _play,
                              curve: const Interval(
                                0.15,
                                0.5,
                                curve: MotionSpec.springOut,
                              ),
                            ),
                            child: Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: teal,
                                shape: BoxShape.circle,
                              ),
                              child: DashIcon(
                                'check',
                                size: IconSize.xs,
                                color: MadarColors.dark.onBrand,
                              ),
                            ),
                          ),
                        Flexible(
                          child: Text(
                            t.isRtl ? eyebrow : eyebrow.toUpperCase(),
                            style: DashType.smallStrong.copyWith(
                              color: teal,
                              letterSpacing: t.isRtl ? 0 : 1.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Space.sm),
                  _rise(
                    0.06,
                    0.42,
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        style:
                            (phone
                                    ? DashType.pageTitlePhone
                                    : DashType.pageTitle)
                                .copyWith(
                                  color: c.onChrome,
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                    ),
                  ),
                  const SizedBox(height: Space.sm),
                  _rise(
                    0.12,
                    0.5,
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          body,
                          style: DashType.body.copyWith(color: c.onChromeMuted),
                        ),
                      ),
                    ),
                  ),
                  if (stage != SetupStage.live) ...[
                    const SizedBox(height: Space.xl),
                    _Pips(
                      checks: blockingChecks(r),
                      play: _play,
                      lit: teal,
                      dim: c.onChrome.withValues(alpha: 0.15),
                    ),
                  ],
                  const SizedBox(height: Space.xl),
                  LayoutBuilder(
                    builder: (context, box) {
                      final two = box.maxWidth >= 520;
                      final cols = two ? 2 : 1;
                      final width =
                          (box.maxWidth - (cols - 1) * Space.sm) / cols;
                      return Wrap(
                        spacing: Space.sm,
                        runSpacing: Space.sm,
                        children: [
                          for (final (i, tile) in tiles.indexed)
                            SizedBox(
                              width: width,
                              child: _rise(
                                0.18 + i * 0.06,
                                0.5 + i * 0.06,
                                tile,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How far along, as one segment per blocking check (never a percentage);
/// the done ones fill in turn.
class _Pips extends ConsumerWidget {
  const _Pips({
    required this.checks,
    required this.play,
    required this.lit,
    required this.dim,
  });

  final List<ReadinessCheck> checks;
  final Animation<double> play;
  final Color lit;
  final Color dim;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final done = checks.where((c) => c.ok).length;
    return Semantics(
      label: t('setup.progress', args: {'done': done, 'total': checks.length}),
      child: ExcludeSemantics(
        child: Row(
          spacing: Space.xs + DashMetrics.hair,
          children: [
            for (final (i, check) in checks.indexed)
              Expanded(
                child: MadarHoldHint(
                  message: t.checkTitle(check.key),
                  child: Container(
                    height: 6,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: dim,
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                    alignment: AlignmentDirectional.centerStart,
                    child: check.ok
                        ? SizeTransition(
                            axis: Axis.horizontal,
                            alignment: AlignmentDirectional.centerStart,
                            sizeFactor: CurvedAnimation(
                              parent: play,
                              curve: Interval(
                                0.2 + i * 0.08,
                                0.55 + i * 0.08,
                                curve: DashMotion.ease,
                              ),
                            ),
                            child: ColoredBox(
                              color: lit,
                              child: const SizedBox(
                                height: 6,
                                width: double.infinity,
                              ),
                            ),
                          )
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The orbit motif of the sign-in panel, quiet behind the words: two rings
/// and a dot that travels the outer one once, coming to rest.
class _Orbit extends CustomPainter {
  _Orbit({
    required this.progress,
    required this.line,
    required this.dot,
    required this.rtl,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final Color line;
  final Color dot;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final unit = size.shortestSide / 400;
    final ring = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas
      ..drawCircle(centre, 120 * unit, ring)
      ..drawCircle(centre, 170 * unit, ring);
    // Once round the outer ring, coming to rest at its start-side edge,
    // the part the panel shows (the other way round in Arabic).
    final dir = rtl ? -1.0 : 1.0;
    final rest = rtl ? 0.0 : math.pi;
    final a = rest - dir * math.pi * 2 * (1 - progress.value);
    final at = centre + Offset(math.cos(a), math.sin(a)) * 170 * unit;
    canvas.drawCircle(at, 7 * unit, Paint()..color = dot);
  }

  @override
  bool shouldRepaint(_Orbit old) =>
      old.line != line || old.dot != dot || old.rtl != rtl;
}
