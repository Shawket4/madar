/// Branch performance: the org's branches ranked by revenue (top six), in
/// both scopes (`dashboard-page.tsx` "Branch leaderboard").
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'home_data.dart';
import 'home_parts.dart';
import 'home_providers.dart';

class HomeBranchPerformanceCard extends ConsumerWidget {
  const HomeBranchPerformanceCard({required this.data, super.key});

  final HomeData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final q = data.comparison;
    final ranked = data.rankedBranches;
    final Widget body;
    if (q.firstLoad) {
      body = const HomeSkeleton(height: HomeMetrics.block);
    } else if (q.hasError) {
      body = DashErrorState(
        framed: false,
        title: t('dashboard.branchesFailed'),
        retryLabel: t('common.retry'),
        onRetry: () => ref.invalidate(homeComparisonProvider(data.scope)),
      );
    } else if (ranked.isEmpty) {
      body = DashEmptyState(framed: false, title: t('dashboard.noSalesPeriod'));
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.xs,
        children: [
          for (final (i, b) in ranked.indexed)
            HomeReveal(
              order: i,
              child: _BranchRow(rank: i + 1, branch: b),
            ),
        ],
      );
    }
    return DashChartCard(title: t('dashboard.branchPerformance'), child: body);
  }
}

class _BranchRow extends ConsumerWidget {
  const _BranchRow({required this.rank, required this.branch});

  final int rank;
  final HomeRankedBranch branch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    final b = branch.row;
    final pct = branch.pct * 100;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm,
        vertical: Space.sm + DashMetrics.hair,
      ),
      child: Row(
        spacing: Space.md,
        children: [
          SizedBox(
            width: HomeMetrics.rank,
            child: Text(
              fmt.fmtNumber(rank),
              textAlign: TextAlign.end,
              style: DashType.mono.copyWith(
                fontSize: DashType.small.fontSize,
                color: c.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.xs + DashMetrics.hair,
              children: [
                Row(
                  spacing: Space.sm,
                  children: [
                    Expanded(
                      child: MadarClippedText(
                        b.branchName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DashType.bodyMedium.copyWith(
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: ltr(fmt.fmtNumber(b.totalOrders)),
                            style: DashType.mono.copyWith(
                              fontSize: DashType.body.fontSize,
                            ),
                          ),
                          TextSpan(text: ' ${t('dashboard.ordersWord')}'),
                        ],
                      ),
                      style: DashType.body.copyWith(color: c.textSecondary),
                    ),
                  ],
                ),
                DashProgressBar(
                  value: pct < 2 ? 2 : pct,
                  semanticLabel: t(
                    'dashboard.branchRevenueBar',
                    args: {'name': b.branchName},
                  ),
                  tone: DashTone.accent,
                ),
              ],
            ),
          ),
          DashConciseValue(
            full: fmt.fmtMoney(b.totalRevenue),
            compact: fmt.fmtMoneyCompact(b.totalRevenue),
            style: DashType.monoStrong.copyWith(
              fontSize: DashType.body.fontSize,
              color: c.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
