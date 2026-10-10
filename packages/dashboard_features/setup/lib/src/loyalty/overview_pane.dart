/// The programme at a glance (the web's `overview/overview-pane.tsx`,
/// SET-LOY-076 … 079, 085): who has joined, what was given away, and what the
/// outstanding balances are worth. Both reads follow the header scope and
/// are kept fresh for 60 s, as on the web.
library;

import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'loyalty_data.dart';
import 'loyalty_widgets.dart';

/// The Overview's reads keep their data 60 s (`staleTime: 60_000`).
const Duration overviewStaleTime = Duration(seconds: 60);

/// `GET /loyalty/analytics[?branch_id]`.
final overviewAnalyticsProvider = FutureProvider.autoDispose
    .family<LoyaltyAnalytics, String?>((ref, branchId) {
      ref.webCache(staleTime: overviewStaleTime);
      ref.watch(realtimeEpochProvider(LoyaltyPaths.analytics));
      return ref
          .watch(apiProvider)
          .loyalty
          .getLoyaltyAnalytics(branchId: branchId);
    });

/// `GET /loyalty/members?[branch_id&]limit=1`: the member total.
final overviewMembersProvider = FutureProvider.autoDispose
    .family<MembersPage, String?>((ref, branchId) {
      ref.webCache(staleTime: overviewStaleTime);
      ref.watch(realtimeEpochProvider(LoyaltyPaths.members));
      return ref
          .watch(apiProvider)
          .loyalty
          .listLoyaltyMembers(branchId: branchId, limit: 1);
    });

class OverviewPane extends ConsumerWidget {
  const OverviewPane({required this.branchId, super.key});

  final String? branchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    final analytics = ref.watch(overviewAnalyticsProvider(branchId));
    final members = ref.watch(overviewMembersProvider(branchId));

    final failed = analytics.failedFirst
        ? analytics
        : (members.failedFirst ? members : null);
    if (failed != null) {
      return DashErrorState(
        key: const ValueKey('loyalty-overview-failed'),
        title: t('loyalty.overviewFailed'),
        message: errorMessage(failed.error, t),
        retryLabel: t('common.retry'),
        retrying: analytics.isLoading || members.isLoading,
        onRetry: () {
          ref.invalidate(overviewAnalyticsProvider(branchId));
          ref.invalidate(overviewMembersProvider(branchId));
        },
      );
    }

    final a = analytics.value;
    final loading = analytics.awaitingFirst || members.awaitingFirst;
    final liability = a?.liability;
    final currency = liability?.currency ?? 'points';
    final outstanding = liability == null
        ? 0
        : (currency == 'visits'
              ? liability.outstandingVisits
              : liability.outstandingPoints);
    final valued = liability?.valuedMinor;
    final refused = a?.refusedRedemptions ?? 0;

    final cards = [
      DashStatCard(
        key: const ValueKey('stat-members'),
        loading: loading,
        icon: 'users',
        label: t('loyalty.statMembers'),
        valueText: fmt.fmtNumber(members.value?.total ?? 0),
        reserveFooter: true,
      ),
      DashStatCard(
        key: const ValueKey('stat-outstanding'),
        loading: loading,
        icon: 'coins',
        label: t('loyalty.statOutstanding'),
        valueText:
            '${fmt.fmtNumber(outstanding)} ${loyaltyUnit(t, currency, outstanding)}',
        hint: t(
          'loyalty.statOutstandingHint',
          args: {'count': liability?.membersWithBalance ?? 0},
        ),
      ),
      DashStatCard(
        key: const ValueKey('stat-liability'),
        loading: loading,
        icon: 'wallet',
        tone: DashTone.warning,
        label: t('loyalty.statLiability'),
        valueText: valued == null ? '—' : fmt.fmtMoney(valued),
        hint: valued == null
            ? t('loyalty.statLiabilityNoRedemptions')
            : t('loyalty.statLiabilityValued'),
      ),
      DashStatCard(
        key: const ValueKey('stat-redemptions'),
        loading: loading,
        icon: 'gift',
        label: t('loyalty.statRedemptions'),
        valueText: fmt.fmtNumber(a?.redemptions ?? 0),
        hint: t(
          'loyalty.statRedemptionsHint',
          args: {'units': fmt.fmtNumber(a?.redeemedUnits ?? 0)},
        ),
      ),
      DashStatCard(
        key: const ValueKey('stat-value'),
        loading: loading,
        icon: 'hand-coins',
        label: t('loyalty.statValueGiven'),
        valueText: fmt.fmtMoney(a?.redeemedValueMinor ?? 0),
        hint: refused > 0
            ? t(
                'loyalty.statValueGivenHint',
                args: {'refused': fmt.fmtNumber(refused)},
              )
            : null,
        reserveFooter: true,
      ),
    ];
    final cols = MediaQuery.sizeOf(context).width >= DashBreakpoints.lg ? 3 : 2;

    return Column(
      key: const ValueKey('loyalty-overview'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        for (var i = 0; i < cards.length; i += cols)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.md,
              children: [
                for (var j = i; j < i + cols; j++)
                  Expanded(
                    child: j < cards.length
                        ? cards[j]
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
          ),
        if (a != null)
          LoyaltyCard(
            key: const ValueKey('loyalty-top-rewards'),
            padding: const EdgeInsets.all(Space.lg),
            spacing: Space.sm,
            children: [
              Semantics(
                header: true,
                child: Text(
                  t('loyalty.topRewards'),
                  style: DashType.sectionTitle.copyWith(color: c.textPrimary),
                ),
              ),
              if (a.topRewards.isEmpty)
                Text(
                  t('loyalty.topRewardsEmpty'),
                  style: DashType.body.copyWith(color: c.textSecondary),
                )
              else
                for (final (i, r) in a.topRewards.indexed) ...[
                  if (i > 0)
                    Divider(height: 1, thickness: 1, color: c.hairline),
                  Padding(
                    key: ValueKey('top-reward-${r.menuItemId}'),
                    padding: const EdgeInsets.symmetric(vertical: Space.sm),
                    child: Row(
                      spacing: Space.md,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              MadarClippedText(
                                r.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: DashType.bodyMedium.copyWith(
                                  color: c.textPrimary,
                                ),
                              ),
                              Text(
                                t(
                                  'loyalty.topRewardsTimes',
                                  args: {
                                    'count': r.redemptions,
                                    'units': r.units,
                                  },
                                ),
                                style: DashType.small.copyWith(
                                  color: c.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          dashFigure(fmt.fmtMoney(r.valueMinor)),
                          style: DashType.mono.copyWith(color: c.textPrimary),
                        ),
                      ],
                    ),
                  ),
                ],
            ],
          ),
      ],
    );
  }
}
