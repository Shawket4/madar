/// The dashboard home (`/`): `routes/_app/index.tsx` and
/// `features/dashboard/dashboard-page.tsx`.
///
/// Top to bottom: the greeting with the scope line; the Setup card;
/// the KPI strip with the Open tills card under it (a branch picked); the
/// revenue trend beside the payment mix; branch performance; margin watch;
/// the delivery section.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'delivery.dart';
import 'home_branches.dart';
import 'home_charts.dart';
import 'home_data.dart';
import 'home_kpis.dart';
import 'home_parts.dart';
import 'margin_watch.dart';
import '../setup/setup_card.dart';

/// The route's page: nothing until the org's modules are known (and nothing
/// for a Dawam-only org, which the router sends to its team), then the home.
class HomeRoute extends ConsumerWidget {
  const HomeRoute({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mods = ref.watch(orgModulesProvider);
    if (!mods.known) return const SizedBox.shrink();
    if (!mods.has(OrgModule.pos) && mods.has(OrgModule.dawam)) {
      return const SizedBox.shrink();
    }
    return const HomePage();
  }
}

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final scope = ref.watch(currentScopeProvider);
    // The page does not watch the home's reads itself: each part that shows
    // them watches them ([_WithHomeData]), so a realtime refetch (a till
    // event, every few seconds on a busy branch) rebuilds the KPI strip and
    // the cards that show those figures, not the whole page with its charts.
    final name = ref.watch(currentSessionProvider.select((s) => s?.user.name));
    final title = name != null && name.isNotEmpty
        ? t('dashboard.greetingName', args: {'name': name})
        : t('dashboard.greeting');
    final wide = MediaQuery.sizeOf(context).width >= DashBreakpoints.lg;
    final trend = HomeRevenueTrendCard(scope: scope);
    final payments = _WithHomeData(
      scope: scope,
      builder: (data) => HomePaymentMixCard(data: data),
    );
    return DashPageScaffold(
      title: title,
      subtitleWidget: _WithHomeData(
        scope: scope,
        builder: (data) => HomeScopeLine(data: data),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.xl,
        children: [
          if (SetupHomeCard.visible(ref)) const SetupHomeCard(),
          HomeReveal(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              // OVW-HOME-045: the web's `space-y-4`, 16 at every width.
              spacing: Space.lg,
              children: [
                _WithHomeData(
                  scope: scope,
                  builder: (data) => HomeKpiStrip(data: data),
                ),
                if (scope.branchId != null)
                  HomeOpenTillsCard(branchId: scope.branchId!),
              ],
            ),
          ),
          if (wide)
            HomeEqualRow(
              flex: const [2, 1],
              children: [
                HomeReveal(child: trend),
                HomeReveal(order: 1, child: payments),
              ],
            )
          else ...[
            HomeReveal(child: trend),
            HomeReveal(order: 1, child: payments),
          ],
          // Below the fold: built a frame apart after the first, so a first
          // visit spreads its build instead of dropping frames in one.
          DashDeferred(
            child: _WithHomeData(
              scope: scope,
              builder: (data) => HomeBranchPerformanceCard(data: data),
            ),
          ),
          DashDeferred(frames: 2, child: HomeMarginWatchCard(scope: scope)),
          DashDeferred(frames: 3, child: HomeDeliverySection(scope: scope)),
        ],
      ),
    );
  }
}

/// [builder] over the home's reads for [scope] ([HomeData.watch]), watched
/// here, below the page.
class _WithHomeData extends ConsumerWidget {
  const _WithHomeData({required this.scope, required this.builder});

  final Scope scope;
  final Widget Function(HomeData data) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      builder(HomeData.watch(ref, scope));
}

/// The ledger's header: which branch, which period, which zone — parts
/// that wrap onto further lines between each other, never inside one.
class HomeScopeLine extends ConsumerWidget {
  const HomeScopeLine({required this.data, super.key});

  final HomeData data;

  /// Keeps a part on one line (no break inside "Last 30 days").
  static String keep(String s) => s.replaceAll(' ', '\u00a0');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final scope = data.scope;
    final style = DashType.body.copyWith(color: c.textSecondary);
    Widget part(String text, [String? glyph]) => Row(
      mainAxisSize: MainAxisSize.min,
      spacing: Space.xs + 2,
      children: [
        if (glyph != null)
          DashIcon(glyph, size: IconSize.xs, color: c.textSecondary),
        Flexible(
          child: MadarClippedText(
            keep(text),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
    final dot = ExcludeSemantics(
      child: Text('·', style: style.copyWith(color: c.border)),
    );
    return Wrap(
      spacing: Space.sm + 2,
      runSpacing: Space.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        part(data.branchLabel(t), 'store'),
        dot,
        part(t(scope.preset.labelKey), 'calendar-range'),
        dot,
        part(timezoneLabel(scope.timezone, t)),
      ],
    );
  }
}
