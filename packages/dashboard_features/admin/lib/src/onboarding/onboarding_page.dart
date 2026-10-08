/// `/onboarding`, the POS first-run wizard (ADM-ONB-001..031; web
/// `features/onboarding/onboarding-page.tsx`): full screen, outside the shell
/// (no sidebar, header, footer or module gate). The top bar with "Skip for
/// now", the "NN% ready to open" bar and its cheer, then — from 1024 wide —
/// three columns (the step navigator, the step panel, the live mirror of the
/// dashboard); below, the panel above the mirror. "Open my café" plays the
/// celebration and opens the dashboard.
///
/// The active step is page state, not in the address (a reload opens the
/// first unfinished step again).
library;

import 'dart:async';

import 'package:dashboard_api/dashboard_api.dart' show OnboardingStatus;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'celebration.dart';
import 'dashboard_mirror.dart';
import 'onboarding_config.dart';
import 'onboarding_data.dart';
import 'step_navigator.dart';
import 'step_panel.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  static const String path = '/onboarding';

  /// The page's widest content (the web's `max-w-6xl`).
  static const double maxWidth = 1152;

  /// The navigator column (`lg:grid-cols-[220px_…]`).
  static const double navigatorWidth = 220;

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  OnbStep? _active;
  bool _finishing = false;
  bool _celebrating = false;

  /// The server's answer to "Open my café" (the web seeds its cache with it).
  OnboardingStatus? _finished;
  Timer? _leave;

  @override
  void dispose() {
    _leave?.cancel();
    super.dispose();
  }

  void _goTo(int index) => setState(
    () => _active = OnbStep.values[index.clamp(0, OnbStep.values.length - 1)],
  );

  Future<void> _finish(String orgId) async {
    final t = ref.read(tProvider);
    setState(() => _finishing = true);
    try {
      final updated = await ref
          .read(apiProvider)
          .orgs
          .completeOnboarding(id: orgId);
      if (!mounted) return;
      // The shell's first-run gate asks again, so it lets them through on
      // landing (the web seeds the same query synchronously).
      ref.invalidate(onboardingCompletedProvider);
      setState(() {
        _finished = updated;
        _celebrating = true;
      });
      _leave = Timer(celebrationHold, () {
        if (mounted) context.go('/');
      });
    } on Object catch (e) {
      if (!mounted) return;
      DashToast.error(context, errorMessage(e, t));
      setState(() => _finishing = false);
    }
  }

  void _skip() {
    ref.read(onboardingSkippedProvider.notifier).skip();
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= DashBreakpoints.lg;
    final orgId = ref.watch(orgIdProvider);
    final query = orgId == null ? null : ref.watch(onbStatusProvider(orgId));
    final status = _finished ?? query?.value;
    final byKey = stepsByKey(status);
    final active = _active ?? firstIncomplete(byKey);
    final activeIndex = OnbStep.values.indexOf(active);
    final canComplete = status?.canComplete ?? false;
    final pct = readyPercent(status);

    Widget body;
    if (query != null && query.hasError && _finished == null) {
      body = _LoadError(
        onRetry: () => ref.invalidate(onbStatusProvider(orgId!)),
      );
    } else if (orgId == null || status == null) {
      body = _Loading(wide: wide);
    } else {
      final panel = Container(
        padding: const EdgeInsets.all(Space.xl),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: c.hairline),
        ),
        child: OnbStepPanel(
          orgId: orgId,
          active: active,
          byKey: byKey,
          canComplete: canComplete,
          isFirst: activeIndex <= 0,
          finishing: _finishing,
          onPrev: () => _goTo(activeIndex - 1),
          onNext: () => _goTo(activeIndex + 1),
          onFinish: () => _finish(orgId),
        ),
      );
      final mirror = OnbDashboardMirror(
        orgId: orgId,
        byKey: byKey,
        recipeCoverage: status.recipeCoverage,
      );
      body = wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.xl,
              children: [
                SizedBox(
                  width: OnboardingPage.navigatorWidth,
                  child: OnbStepNavigator(
                    byKey: byKey,
                    active: active,
                    canComplete: canComplete,
                    onSelect: (s) => setState(() => _active = s),
                  ),
                ),
                Expanded(flex: 100, child: panel),
                Expanded(flex: 105, child: mirror),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.xl,
              children: [panel, mirror],
            );
    }

    final gutter = width >= DashBreakpoints.sm ? Space.xl : Space.lg;
    final page = SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: gutter,
        vertical: wide ? Space.xxl + Space.sm : Space.xxl,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: OnboardingPage.maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TopBar(onSkip: _skip),
              const SizedBox(height: Space.xxl),
              _Progress(pct: pct, cheer: t(cheerKey(pct))),
              const SizedBox(height: Space.xxl),
              body,
            ],
          ),
        ),
      ),
    );

    return Stack(
      children: [
        Positioned.fill(child: SafeArea(bottom: false, child: page)),
        if (_celebrating) const Positioned.fill(child: OnbCelebration()),
      ],
    );
  }
}

/// The sparkles tile, the title and its sub-line, "Skip for now".
class _TopBar extends ConsumerWidget {
  const _TopBar({required this.onSkip});

  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    return Row(
      spacing: Space.md,
      children: [
        Container(
          width: Space.xxl + Space.sm,
          height: Space.xxl + Space.sm,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.brand.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(Radii.card),
          ),
          child: DashIcon('sparkles', size: IconSize.lg, color: c.brand),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text(
                  t('onboarding.title'),
                  style: DashType.paneTitle.copyWith(color: c.textPrimary),
                ),
              ),
              Text(
                t('onboarding.subtitle'),
                style: DashType.body.copyWith(color: c.textSecondary),
              ),
            ],
          ),
        ),
        DashButton(
          label: t('onboarding.skip'),
          variant: DashButtonVariant.ghost,
          onPressed: onSkip,
        ),
      ],
    );
  }
}

/// "NN% ready to open", the cheer, and the bar (it eases to a new value;
/// instant under reduced motion; no animation on first paint).
class _Progress extends ConsumerWidget {
  const _Progress({required this.pct, required this.cheer});

  final int pct;
  final String cheer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final label = t('onboarding.readyPct', args: {'pct': pct});
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.xs + DashMetrics.hair,
      children: [
        Row(
          spacing: Space.md,
          children: [
            Expanded(
              child: Text(
                label,
                style: DashType.smallMedium.copyWith(color: c.textSecondary),
              ),
            ),
            Text(cheer, style: DashType.smallMedium.copyWith(color: c.brand)),
          ],
        ),
        ExcludeSemantics(
          child: Container(
            height: Space.sm,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: c.muted,
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(end: pct / 100),
                duration: DashMotion.of(
                  context,
                  const Duration(milliseconds: 700),
                ),
                curve: Curves.easeOut,
                builder: (context, f, _) => FractionallySizedBox(
                  key: const ValueKey('onb-progress-fill'),
                  widthFactor: f.clamp(0, 1),
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.brand,
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// "Couldn't load your setup" with a Refresh that asks again.
class _LoadError extends ConsumerWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final danger = DashTone.danger.foreground(c);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.xl,
          vertical: Space.xxl * 2,
        ),
        decoration: BoxDecoration(
          color: c.danger.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: c.danger.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: Space.md,
          children: [
            DashIcon('alert-circle', size: Space.xxl, color: danger),
            Text(
              t('onboarding.loadError'),
              textAlign: TextAlign.center,
              style: DashType.bodyStrong.copyWith(color: danger),
            ),
            DashButton(
              label: t('common.refresh'),
              variant: DashButtonVariant.outline,
              size: DashButtonSize.compact,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

/// Three skeleton panels (the navigator's only from 1024 wide).
class _Loading extends StatelessWidget {
  const _Loading({required this.wide});

  final bool wide;

  static const double _height = 384;

  @override
  Widget build(BuildContext context) {
    const block = DashSkeleton(height: _height, radius: Radii.card);
    return Semantics(
      key: const ValueKey('onb-loading'),
      container: true,
      child: wide
          ? const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.xl,
              children: [
                SizedBox(width: OnboardingPage.navigatorWidth, child: block),
                Expanded(flex: 100, child: block),
                Expanded(flex: 105, child: block),
              ],
            )
          : const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.xl,
              children: [block, block],
            ),
    );
  }
}
