/// `/reports/loyalty` Loyalty (REP-LOY rows): tabs Overview, Campaigns,
/// Liability (`features/reports/loyalty/loyalty-report-page.tsx`).
///
/// The page's own `<Restricted>` answers without `loyalty.members.list`
/// (REP-LOY-001). Each tab asks for its own report when it is opened; the
/// tabs are page state, so a reload opens Overview (REP-ALL-022). There is
/// no export.
library;

import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/report_shared.dart';
import 'liability_chart.dart';
import 'lis_providers.dart';
import 'lis_support.dart';

/// The route's page (`DashRoute.builder`).
Widget loyaltyReportPageBuilder(BuildContext context, GoRouterState state) =>
    const LoyaltyReportPage();

/// The tabs (REP-LOY-002), page state; default Overview.
const List<DashRouteTab> loyaltyReportTabs = [
  DashRouteTab(id: 'overview', labelKey: 'reports.loyalty.tabs.overview'),
  DashRouteTab(id: 'campaigns', labelKey: 'reports.loyalty.tabs.campaigns'),
  DashRouteTab(id: 'liability', labelKey: 'reports.loyalty.tabs.liability'),
];

class LoyaltyReportPage extends ConsumerStatefulWidget {
  const LoyaltyReportPage({super.key});

  @override
  ConsumerState<LoyaltyReportPage> createState() => _LoyaltyReportPageState();
}

class _LoyaltyReportPageState extends ConsumerState<LoyaltyReportPage> {
  String _tab = 'overview';

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final title = t('reports.loyalty.title');
    final gate = lisGate(
      ref,
      title: title,
      canSee: (a) => a.can(Cap.loyaltyMembersList),
    );
    if (gate != null) return gate;
    final key = ref.watch(currentScopeProvider.select((s) => s.loyaltyKey));
    return DashPageScaffold(
      title: title,
      subtitleWidget: const ReportPeriodSubtitle(),
      tabs: DashPageTabs<String>(
        value: _tab,
        onChanged: (v) => setState(() => _tab = v),
        onIntent: (v) => ref.warm(switch (v) {
          'campaigns' => loyaltyCampaignsProvider(key),
          'liability' => loyaltyLiabilityProvider(key),
          _ => loyaltyBehaviorProvider(key),
        }),
        tabs: [
          for (final tab in loyaltyReportTabs)
            DashTab(value: tab.id, label: t(tab.labelKey)),
        ],
      ),
      body: KeyedSubtree(
        key: ValueKey('loyalty-tab-$_tab'),
        child: switch (_tab) {
          'campaigns' => LoyaltyCampaignsTab(queryKey: key),
          'liability' => LoyaltyLiabilityTab(queryKey: key),
          _ => LoyaltyOverviewTab(queryKey: key),
        },
      ),
    );
  }
}

/// REP-LOY-004…009: the five behaviour KPIs; a failed read replaces the
/// strip with ErrorState + Retry.
class LoyaltyOverviewTab extends ConsumerWidget {
  const LoyaltyOverviewTab({required this.queryKey, super.key});

  final LoyaltyKey queryKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final q = ref.watch(loyaltyBehaviorProvider(queryKey));
    if (q.hasError && !q.retrying) {
      return DashErrorState(
        retryLabel: t('common.retry'),
        retrying: q.isLoading,
        onRetry: () => ref.invalidate(loyaltyBehaviorProvider(queryKey)),
      );
    }
    final d = q.value;
    final loading = q.awaitingFirst;
    String n(int? v) => f.fmtNumber(v ?? 0);
    DashLedgerItem item(
      String key,
      String label,
      String icon,
      DashTone tone,
      double? value,
      String hint,
    ) => DashLedgerItem(
      key: key,
      label: label,
      icon: icon,
      tone: tone,
      value: value ?? 0,
      format: DashStatFormat.percent,
      loading: loading,
      hint: hint,
    );
    return DashLedgerStrip(
      items: [
        item(
          'active_member_rate',
          t('reports.loyalty.activeRate'),
          'users',
          DashTone.accent,
          d?.activeMemberRate,
          t(
            'reports.loyalty.activeRateHint',
            args: {'active': n(d?.activeMembers), 'total': n(d?.totalMembers)},
          ),
        ),
        item(
          'redemption_rate',
          t('reports.loyalty.redemptionRate'),
          'gift',
          DashTone.info,
          d?.redemptionRate,
          t(
            'reports.loyalty.redemptionRateHint',
            args: {'redeemed': n(d?.membersEverRedeemed)},
          ),
        ),
        item(
          'redemption_ratio',
          t('reports.loyalty.redemptionRatio'),
          'percent',
          DashTone.info,
          d?.redemptionRatio,
          t('reports.loyalty.redemptionRatioHint'),
        ),
        item(
          'repeat_visit_rate',
          t('reports.loyalty.repeatRate'),
          'rotate-ccw',
          DashTone.neutral,
          d?.repeatVisitRate,
          t(
            'reports.loyalty.repeatRateHint',
            args: {
              'repeat': n(d?.repeatMembers),
              // Worked out in the browser (REP-LOY-007).
              'earning': n((d?.repeatMembers ?? 0) + (d?.oneTimeMembers ?? 0)),
            },
          ),
        ),
        item(
          'new_member_share',
          t('reports.loyalty.newShare'),
          'user-plus',
          DashTone.warning,
          d?.newMemberShare,
          t(
            'reports.loyalty.newShareHint',
            args: {
              'new': n(d?.newMembersActive),
              'active': n(d?.activeMembers),
            },
          ),
        ),
      ],
    );
  }
}

/// The campaign's name: "Win-back", "Birthday"; the raw code otherwise.
String loyaltyCampaignName(Translator t, String code) {
  final key = 'reports.loyalty.campaign.$code';
  return t.exists(key) ? t(key) : code;
}

/// REP-LOY-010…012: one row per campaign with its return rate.
class LoyaltyCampaignsTab extends ConsumerWidget {
  const LoyaltyCampaignsTab({required this.queryKey, super.key});

  final LoyaltyKey queryKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final q = ref.watch(loyaltyCampaignsProvider(queryKey));
    if (q.hasError && !q.retrying) {
      return DashErrorState(
        retryLabel: t('common.retry'),
        retrying: q.isLoading,
        onRetry: () => ref.invalidate(loyaltyCampaignsProvider(queryKey)),
      );
    }
    if (q.awaitingFirst) {
      return DashCard(
        padding: const EdgeInsets.all(Space.card),
        child: Column(
          spacing: Space.lg,
          children: [
            for (var i = 0; i < 2; i++)
              const DashSkeleton(height: Space.xxl * 2),
          ],
        ),
      );
    }
    final rows = q.value?.campaigns ?? const <CampaignEffectivenessRow>[];
    if (rows.isEmpty || rows.every((r) => r.sent == 0)) {
      return DashEmptyState(title: t('reports.loyalty.noCampaigns'));
    }
    return DashCard(
      padding: const EdgeInsets.all(Space.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          for (final r in rows)
            Column(
              key: ValueKey('campaign-${r.campaign}'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.xs + DashMetrics.hair,
              children: [
                Row(
                  spacing: Space.lg,
                  children: [
                    Expanded(
                      child: MadarClippedText(
                        loyaltyCampaignName(t, r.campaign),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DashType.bodyMedium.copyWith(
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      dashFigure(f.fmtPercent(r.returnRate)),
                      style: DashType.mono.copyWith(color: c.textPrimary),
                    ),
                  ],
                ),
                DashProgressBar(
                  value: r.returnRate,
                  max: 1,
                  // The web names the bar by the raw code (REP-LOY-018).
                  semanticLabel: loyaltyCampaignName(t, r.campaign),
                ),
                Text(
                  t(
                    'reports.loyalty.campaignHint',
                    args: {
                      'returned': f.fmtNumber(r.returnedWithin30d),
                      'sent': f.fmtNumber(r.sent),
                    },
                  ),
                  style: DashType.small.copyWith(color: c.textSecondary),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// `currencyLabel(mode, count)`: "points" / "orders" (a visits programme),
/// plural-aware; no count reads as many (`count ?? 2`).
String loyaltyUnitLabel(Translator t, String mode, [num? count]) => t(
  mode == 'visits' ? 'loyalty.unitOrders' : 'loyalty.unitPoints',
  count: count ?? 2,
);

/// REP-LOY-013…016: the weekly net change as bars, in a card whose title
/// and description always show (REP-LOY-018).
class LoyaltyLiabilityTab extends ConsumerWidget {
  const LoyaltyLiabilityTab({required this.queryKey, super.key});

  final LoyaltyKey queryKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final q = ref.watch(loyaltyLiabilityProvider(queryKey));
    final currency = q.value?.currency ?? 'points';
    final points = q.value?.points ?? const <LiabilityTrendPoint>[];
    final Widget body;
    if (q.awaitingFirst) {
      body = const DashSkeleton(height: liabilityChartHeight);
    } else if (q.hasError && !q.retrying) {
      body = SizedBox(
        height: liabilityChartHeight,
        child: DashErrorState(
          retryLabel: t('common.retry'),
          retrying: q.isLoading,
          onRetry: () => ref.invalidate(loyaltyLiabilityProvider(queryKey)),
        ),
      );
    } else if (points.isEmpty) {
      body = SizedBox(
        height: liabilityChartHeight,
        child: DashEmptyState(title: t('reports.loyalty.noLiability')),
      );
    } else {
      body = LiabilityChart(
        labels: [for (final p in points) f.fmtDate(p.week)],
        values: [for (final p in points) p.outstanding.toDouble()],
        formatAxis: (v) => f.fmtNumber(v),
        // The web heads the tooltip with the raw ISO week and labels the
        // row "outstanding" (REP-LOY-015): the date and the unit instead.
        tooltip: (i) {
          final v = points[i].outstanding;
          return '${f.fmtNumber(v)} ${loyaltyUnitLabel(t, currency, v)}';
        },
      );
    }
    return DashChartCard(
      title: t('reports.loyalty.liabilityTrend'),
      description: t(
        'reports.loyalty.liabilityTrendHint',
        args: {'unit': loyaltyUnitLabel(t, currency)},
      ),
      child: body,
    );
  }
}
