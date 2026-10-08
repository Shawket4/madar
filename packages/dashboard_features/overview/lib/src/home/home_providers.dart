/// The home's reads (inventory E1–E7), one provider per endpoint, keyed by
/// the resolved [Scope] so a branch or period change asks again — the web's
/// React Query keys (`[path, params]`).
///
/// - Each read watches `realtimeEpochProvider(<its path>)`: a realtime event
///   that invalidates a prefix of the path (`till.*` → `/tills`, `/reports`;
///   `resync` → everything) refetches it, as the web's prefix invalidation
///   does.
/// - A read the web keeps disabled (no branch picked, no org in scope) is not
///   watched at all: see [watchIf].
/// - Retries are the app's (the root container's policy); a card's Retry
///   button invalidates exactly its own read.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show BranchSalesReport, DeliverySalesReport, MarginWatch, OnboardingStatus, OrgComparisonReport, Till, TimeseriesPoint;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

DateTime _instant(String iso) => DateTime.parse(iso);

/// E1 `GET /reports/branches/{branchId}/sales` — only with a branch picked.
final homeBranchSalesProvider = FutureProvider.autoDispose
    .family<BranchSalesReport, Scope>((ref, s) {
      final id = s.branchId!;
      ref.watch(realtimeEpochProvider('/reports/branches/$id/sales'));
      return ref
          .watch(apiProvider)
          .reports
          .branchSales(
            branchId: id,
            from: _instant(s.from),
            to: _instant(s.to),
          );
    });

/// E2 `GET /reports/branches/{scopeBranchId}/sales/timeseries` — hourly for
/// today / yesterday, else daily.
final homeTimeseriesProvider = FutureProvider.autoDispose
    .family<List<TimeseriesPoint>, Scope>((ref, s) {
      ref.watch(
        realtimeEpochProvider(
          '/reports/branches/${s.scopeBranchId}/sales/timeseries',
        ),
      );
      return ref
          .watch(apiProvider)
          .reports
          .branchSalesTimeseries(
            branchId: s.scopeBranchId,
            from: _instant(s.from),
            to: _instant(s.to),
            granularity: s.granularity,
          );
    });

/// E3 `GET /reports/orgs/{orgId}/comparison` — every branch of the org.
final homeComparisonProvider = FutureProvider.autoDispose
    .family<OrgComparisonReport, Scope>((ref, s) {
      final org = s.orgId!;
      ref.watch(realtimeEpochProvider('/reports/orgs/$org/comparison'));
      return ref
          .watch(apiProvider)
          .reports
          .orgBranchComparison(
            orgId: org,
            from: _instant(s.from),
            to: _instant(s.to),
          );
    });

/// E4 `GET /reports/branches/{scopeBranchId}/delivery-sales`.
final homeDeliveryProvider = FutureProvider.autoDispose
    .family<DeliverySalesReport, Scope>((ref, s) {
      ref.watch(
        realtimeEpochProvider(
          '/reports/branches/${s.scopeBranchId}/delivery-sales',
        ),
      );
      return ref
          .watch(apiProvider)
          .reports
          .branchDeliverySales(
            branchId: s.scopeBranchId,
            from: _instant(s.from),
            to: _instant(s.to),
          );
    });

/// E5 `GET /insights/branches/{scopeBranchId}/margin-watch` (no
/// `cost_basis`: the server's snapshot).
final homeMarginWatchProvider = FutureProvider.autoDispose
    .family<MarginWatch, Scope>((ref, s) {
      ref.watch(
        realtimeEpochProvider(
          '/insights/branches/${s.scopeBranchId}/margin-watch',
        ),
      );
      return ref
          .watch(apiProvider)
          .insights
          .marginWatch(
            branchId: s.scopeBranchId,
            from: _instant(s.from),
            to: _instant(s.to),
          );
    });

/// E6 `GET /tills/branches/{branchId}/open` (`useOpenTills`) — newest first.
final homeOpenTillsProvider = FutureProvider.autoDispose
    .family<List<Till>, String>((ref, branchId) {
      ref.watch(realtimeEpochProvider('/tills/branches/$branchId/open'));
      return ref.watch(apiProvider).tills.listOpenTills(branchId: branchId);
    });

/// E7 `GET /orgs/{orgId}/onboarding` — for the Keep-building card.
final homeOnboardingProvider = FutureProvider.autoDispose
    .family<OnboardingStatus, String>((ref, orgId) {
      ref.watch(realtimeEpochProvider('/orgs/$orgId/onboarding'));
      return ref.watch(apiProvider).orgs.getOnboarding(id: orgId);
    });

/// The Keep-building card was dismissed: for the rest of this app session
/// (the web's `sessionStorage["madar.onboarding.nudge.dismissed"]`).
class NudgeDismissed extends Notifier<bool> {
  @override
  bool build() => false;

  void dismiss() => state = true;
}

final homeNudgeDismissedProvider = NotifierProvider<NudgeDismissed, bool>(
  NudgeDismissed.new,
);

/// The state of a read the web keeps disabled until [enabled]: a disabled
/// query is neither loading nor failed and has no data, so the card shows
/// its empty (or zero) state.
AsyncValue<T?> watchIf<T>(
  WidgetRef ref,
  bool enabled,
  ProviderListenable<AsyncValue<T>> provider,
) => enabled ? ref.watch(provider) : AsyncData<T?>(null);

/// React Query's `isLoading`: the first load, with nothing to show yet.
extension HomeAsync<T> on AsyncValue<T> {
  bool get firstLoad => isLoading && !hasValue && !hasError;
}
