/// The home's reads (inventory E1–E7), one provider per endpoint, keyed by
/// exactly the params its request sends — the web's React Query key
/// (`[path, params]`) — so a branch or period change asks again and nothing
/// else does.
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
    show
        BranchSalesReport,
        DeliverySalesReport,
        MarginWatch,
        OnboardingStatus,
        OrgComparisonReport,
        Till,
        TimeseriesPoint;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

DateTime _instant(String iso) => DateTime.parse(iso);

/// A report read's key: the branch (or org) id and the period it sends.
typedef HomeRange = ({String id, String from, String to});

/// The trend's key: its range and its granularity.
typedef HomeSeries = ({String id, String from, String to, String granularity});

/// The one place each read's key is built from the scope (the page, the
/// Retry buttons, the prefetch and the tests all use these).
extension HomeKeys on Scope {
  /// E1: the picked branch (only read with one picked).
  HomeRange get branchRange => (id: branchId!, from: from, to: to);

  /// E4, E5: the branch or the all-branches sentinel.
  HomeRange get scopeRange => (id: scopeBranchId, from: from, to: to);

  /// E3: the org in scope (only read with one).
  HomeRange get orgRange => (id: orgId!, from: from, to: to);

  /// E2: hourly for today / yesterday, else daily.
  HomeSeries get series =>
      (id: scopeBranchId, from: from, to: to, granularity: granularity);
}

/// E1 `GET /reports/branches/{branchId}/sales` — only with a branch picked.
final homeBranchSalesProvider = FutureProvider.autoDispose
    .family<BranchSalesReport, HomeRange>((ref, k) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/reports/branches/${k.id}/sales'));
      return ref
          .watch(apiProvider)
          .reports
          .branchSales(
            branchId: k.id,
            from: _instant(k.from),
            to: _instant(k.to),
          );
    });

/// E2 `GET /reports/branches/{scopeBranchId}/sales/timeseries` — hourly for
/// today / yesterday, else daily.
final homeTimeseriesProvider = FutureProvider.autoDispose
    .family<List<TimeseriesPoint>, HomeSeries>((ref, k) {
      ref.webCache();
      ref.watch(
        realtimeEpochProvider('/reports/branches/${k.id}/sales/timeseries'),
      );
      return ref
          .watch(apiProvider)
          .reports
          .branchSalesTimeseries(
            branchId: k.id,
            from: _instant(k.from),
            to: _instant(k.to),
            granularity: k.granularity,
          );
    });

/// E3 `GET /reports/orgs/{orgId}/comparison` — every branch of the org.
final homeComparisonProvider = FutureProvider.autoDispose
    .family<OrgComparisonReport, HomeRange>((ref, k) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/reports/orgs/${k.id}/comparison'));
      return ref
          .watch(apiProvider)
          .reports
          .orgBranchComparison(
            orgId: k.id,
            from: _instant(k.from),
            to: _instant(k.to),
          );
    });

/// E4 `GET /reports/branches/{scopeBranchId}/delivery-sales`.
final homeDeliveryProvider = FutureProvider.autoDispose
    .family<DeliverySalesReport, HomeRange>((ref, k) {
      ref.webCache();
      ref.watch(
        realtimeEpochProvider('/reports/branches/${k.id}/delivery-sales'),
      );
      return ref
          .watch(apiProvider)
          .reports
          .branchDeliverySales(
            branchId: k.id,
            from: _instant(k.from),
            to: _instant(k.to),
          );
    });

/// E5 `GET /insights/branches/{scopeBranchId}/margin-watch` (no
/// `cost_basis`: the server's snapshot).
final homeMarginWatchProvider = FutureProvider.autoDispose
    .family<MarginWatch, HomeRange>((ref, k) {
      ref.webCache();
      ref.watch(
        realtimeEpochProvider('/insights/branches/${k.id}/margin-watch'),
      );
      return ref
          .watch(apiProvider)
          .insights
          .marginWatch(
            branchId: k.id,
            from: _instant(k.from),
            to: _instant(k.to),
          );
    });

/// E6 `GET /tills/branches/{branchId}/open` (`useOpenTills`) — newest first.
final homeOpenTillsProvider = FutureProvider.autoDispose
    .family<List<Till>, String>((ref, branchId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/tills/branches/$branchId/open'));
      return ref.watch(apiProvider).tills.listOpenTills(branchId: branchId);
    });

/// E7 `GET /orgs/{orgId}/onboarding` — for the Keep-building card.
final homeOnboardingProvider = FutureProvider.autoDispose
    .family<OnboardingStatus, String>((ref, orgId) {
      ref.webCache();
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
/// its empty (or zero) state. [provider] is built only when enabled (its
/// key may need the branch or org that is missing otherwise).
AsyncValue<T?> watchIf<T>(
  WidgetRef ref,
  bool enabled,
  ProviderListenable<AsyncValue<T>> Function() provider,
) => enabled ? ref.watch(provider()) : AsyncData<T?>(null);
